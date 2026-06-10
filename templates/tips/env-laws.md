# env-laws.md — Universal Laws for env-update and env-scan

> **These are inviolable rules.** They define the contract that keeps env-update and
> env-scan safe. No flag, annotation, or future feature may silently break them.
> Any change to the decision ladder or scan pipeline must be verified against this
> document before merging.

---

## env-update Universal Laws

### Law 1 — Major jump → HOLD, always

A version change that crosses a major boundary (e.g. 17.x → 18.x) **always** produces
HOLD. No flag, annotation, or mode bypasses this gate inside `classify_decision`.

**Source**: `bin/lib/env-update/core/decide.sh` step 7:

```bash
if [[ "${_delta}" == "major" && -z "${_major_hint}" ]]; then
  echo "HOLD"; return 0
fi
```

The legitimate paths to AUTO on a major jump are:

| Path | Mechanism | Where |
|------|-----------|-------|
| `:N` major-hint pin in annotation | Caller passes `_major_hint`; step 7 is skipped | `decide.sh` step 7 |
| `--force-auto` one-time override | HOLD→AUTO upgrade applied *after* classify_decision returns | `main.sh` Phase 2 |
| `--force-hold` one-time override | HOLD→AUTO upgrade (MANUAL/OVERRIDE unaffected) | `main.sh` Phase 2 |

`--unstable=full`, `(channel:unstable)`, and any future channel flag do **not** touch
step 7. The reverted commit `53b76f15` was wrong precisely because it added an
`unstable_mode=full` bypass to step 7 — turning HOLD→AUTO silently on `--apply
--unstable`.

**Concrete example**:
```
# @todo env-update github:org/repo 17.2.1
GLOBAL_STACK_FOO=17.2.1
```
Fetcher returns `18.0.0`. Decision: **HOLD** — regardless of `--unstable`, `--stable`,
or `(channel:unstable)` annotation. Only `:18` pin, `--force-auto`, or `--force-hold`
can promote to AUTO.

---

### Law 2 — Prerelease guard: step 4 priority ladder

When the current version is stable and the proposed version is a prerelease (e.g.
`18.0.0-rc1`, `6.3.0beta2`), step 4 applies a priority ladder:

| Priority | Condition | Decision |
|----------|-----------|----------|
| 1st | `--stable=full` active | **SKIP** (force-reject prerelease regardless of channel) |
| 2nd | `--unstable=full` active | bypass step 4 entirely (continue to step 5+) |
| 3rd | annotation `(channel:unstable)` | **HOLD** (annotation opt-in, review required) |
| default | none of the above | **SKIP** |

**Source**: `bin/lib/env-update/core/decide.sh` step 4:

```bash
if _gs_eu2_is_prerelease "${_prop}" && ! _gs_eu2_is_prerelease "${_cur}"; then
  if [[ "${_stable_mode}" == "full" ]]; then echo "SKIP"; return 0; fi
  if [[ "${_unstable_mode}" != "full" ]]; then
    if [[ "${_record_channel}" == "unstable" ]]; then echo "HOLD"; return 0; fi
    echo "SKIP"; return 0
  fi
  # unstable_mode=full: bypass
fi
```

**Note**: step 4 fires *before* step 7. A prerelease proposed version that also crosses a
major boundary hits step 4 first — only if step 4 bypasses (unstable_mode=full) will
step 7 then fire for the major-jump HOLD check.

**Law 2b — `(channel:unstable)` annotation bridges fetcher and classifier**:
A record annotated with `(channel:unstable)` now produces **HOLD** (not SKIP) when a
prerelease is proposed over a stable current — regardless of CLI flags (unless
`--stable=full` or `--unstable=full` override). This is the annotation opt-in bridge:
the fetcher is asked for prerelease, and the classifier signals "review before applying."

---

### Law 3 — Downgrade → SKIP, always

If the proposed version sorts before the current version (via `sort -V`), the result is
**SKIP**. No flag or annotation can override this — downgrade protection fires before
the `(manual)`/`(override)` gate (step 6) and before the HOLD gate (step 7).

**Source**: `bin/lib/env-update/core/decide.sh` step 5 (downgrade check using `sort -V`
with perl normalization for date-based SHAs).

**Exception**: RC→stable promotion (e.g. current=`18.0.0-rc2`, proposed=`18.0.0`) is
detected and the `sort -V` check is skipped for that pair only — this is a forward
promotion, not a downgrade.

---

### Law 4 — `(manual)` / `(override)` annotation → MANUAL when proposed > current

When an annotation carries `(manual)` or `(override)`, the result is **MANUAL** — auto-apply
never writes MANUAL items to `.env`.

**Source**: `bin/lib/env-update/core/decide.sh` step 6:

```bash
if [[ "${_override}" == "true" || "${_manual}" == "true" ]]; then
  echo "MANUAL"; return 0
fi
```

Step 6 fires *after* the downgrade and prerelease guards (steps 4-5), so a downgrade or
stable→prerelease case is caught first. Step 6 fires *before* HOLD (step 7), so even a
major jump with `(manual)` → MANUAL (not HOLD).

`--force-auto` bypasses this gate by passing `""` to classify_decision for the override
and manual fields (see `main.sh` Phase 1). The HOLD upgrade then applies in Phase 2.

---

### Law 5 — Decision strength hierarchy and force-flag scope

| Decision | Meaning | `--apply` behavior | `--force-auto` effect | `--force-hold` effect |
|----------|---------|-------------------|----------------------|----------------------|
| **HOLD** | Update ready but requires human review | Never written | Upgrades to AUTO | Upgrades to AUTO |
| **SKIP** | Nothing to do, or change is blocked | Never written | No effect | No effect |
| **MANUAL** | Annotated as requiring manual handling | Never written | Bypasses annotation → HOLD upgrade applies | No effect (MANUAL stays MANUAL) |
| **AUTO** | Safe to apply automatically | Written by `--apply` | Already AUTO | Already AUTO |
| **LOCK** | Locked by `(lock:REASON)` annotation | Never written | No effect | No effect |
| **FROZEN** | `(skip:REASON)` annotation | Never written | No effect | No effect |

**Hierarchy** (immune from highest to lowest): FROZEN > LOCK > HOLD > MANUAL > AUTO.

`--force-auto` bypasses HOLD + MANUAL + OVERRIDE (by clearing the annotation flags before
classify_decision is called). `--force-hold` bypasses HOLD only — MANUAL/OVERRIDE annotation
flags are NOT cleared. `--force-auto` cannot upgrade SKIP, LOCK, or FROZEN.

**`--apply` warns on RESOLVED skips**: when `--apply` completes and RESOLVED records were
present but not written (because `--apply-resolve` was not passed), a warning is emitted:
`↳ N RESOLVED record(s) skipped — use --apply --apply-resolve to pin floating references`

---

### Law 6 — Force-flag scope: run-wide, not per-record

Both `--force-auto` and `--force-hold` apply to **all** records in a single invocation.
There is no per-record CLI opt-in. The per-record mechanism for targeted major-jump
approval is the `:N` major-hint pin in the annotation.

```bash
# Targeted: only this record can cross to major 18
# @todo env-update github:org/repo :18 17.2.1
GLOBAL_STACK_FOO=17.2.1

# Run-wide: every HOLD in this run becomes AUTO (use carefully)
bin/env-update.sh --apply --force-auto --confirm="Confirm override"

# Run-wide: every HOLD becomes AUTO, but MANUAL records stay MANUAL
bin/env-update.sh --apply --force-hold --confirm="Confirm override"
```

**`--force-hold` vs `--force-auto`**:
- `--force-hold`: HOLD→AUTO only. MANUAL and OVERRIDE annotation flags are NOT cleared.
  Records with `(manual)` or `(override)` remain MANUAL.
- `--force-auto`: HOLD→AUTO + clears (manual)/(override) flags before classification.
  Records that would be MANUAL become AUTO-eligible after flag clearing.

---

### Law 7 — `--apply` gate: only AUTO items are written

`--apply` writes only records with final decision **AUTO** to `.env`. HOLD, MANUAL, SKIP,
RESOLVED, LOCK, and ERROR items appear in the report but are never written.

RESOLVED items require both `--apply` and `--apply-resolve` to be written.

---

### Law 8 — Detection is always preserved

HOLD and SKIP items are always shown in `--check` output (unless filtered by `--filter`).
Nothing is silently dropped from the report. A record with no proposed version emits SKIP
with a reason annotation — it does not disappear.

`--changes-only` suppresses up-to-date SKIP records from display but does not suppress
HOLD, MANUAL, ERROR, or LOCK records.

---

### Law 9 — Decision ladder: strict order, first match wins

Steps 1–9 are applied in the order defined in `decide.sh`. No step can be reordered or
skipped by any flag (individual bypass conditions are noted per step). The full ladder:

| Step | Condition | Decision | Bypassable? |
|------|-----------|----------|-------------|
| 1 | No proposed version | SKIP | No |
| 2 | Current is floating (nightly/latest/…) + proposed is concrete | RESOLVED (or MANUAL if annotated) | No |
| 3 | Current == proposed | SKIP | No |
| 4 | Proposed is prerelease and current is stable | See priority ladder (Law 2) | Priority-dependent |
| 5 | Proposed sorts before current (downgrade) | SKIP | No (except RC→stable promotion) |
| 6 | `(override)` or `(manual)` annotation | MANUAL | Yes — `--force-auto` clears flags before step |
| 7 | Major jump without `:N` pin | HOLD | No (post-classify upgrade applies separately) |
| 8 | Major jump with pin but proposed escapes the pin | HOLD | No |
| 9 | Otherwise | AUTO | — |

Post-classify phases in `main.sh` (applied after the ladder):
- **Phase 2**: `--force-hold` HOLD→AUTO upgrade (MANUAL/OVERRIDE unaffected)
- **Phase 2b**: `--force-auto` HOLD→AUTO upgrade (MANUAL/OVERRIDE cleared in Phase 1)
- **Phase 3**: `(lock:REASON)` → LOCK (overrides AUTO/HOLD/MANUAL; not ERROR or skip-gate SKIP)
- **Phase 4**: SHA classification (SKIP→SHA when annotation `sha:` lags proposed SHA)

---

## env-scan Universal Laws

### Law S1 — LOCAL_ vars in `.env.local` are preserved

`bin/env-scan.sh` **never deletes** `LOCAL_` prefixed keys from `.env.local`. These keys
are machine-specific additions (not present in `.env`) and are silently preserved through
every sync cycle.

**Source**: `bin/env-scan.sh` Phase 6 sync logic — LOCAL_ keys are excluded from the
conflict and overwrite checks.

---

### Law S2 — Backup before any sync

env-scan always takes a timestamped backup of `.env.local` (and Dockerfiles) before
writing, unless `--backup=false` is explicitly passed. The default retention is 10 backups
per file (`--backup-keep=10`).

---

### Law S3 — Dockerfile ARG propagation: concrete strings only

ARG values in Dockerfiles are only rewritten when the corresponding `.env` value is a
plain concrete string. Variables whose `.env` value contains `${` (shell expansion) are
**skipped** — propagating an unexpanded template to a Dockerfile ARG would produce a
broken build.

---

### Law S4 — Conflict protection

Variables matching `_GS_ES_PATTERN_CONFLICT_IGNORE` are never overwritten by env-scan,
regardless of the `--sync-values` setting.

---

## The Channel-Classifier Relationship (Two Axes, One Bridge)

**Axis 1 — Fetcher channel** (annotation-driven): `(channel:X)` controls which version
the fetcher returns. Routing is via `bin/lib/env-update/core/channel.sh`.

**Axis 2 — Classifier** (CLI-driven): `--unstable=full` bypasses step 4 globally;
`--stable=full` force-rejects prerelease in step 4 (highest priority).

**Bridge — annotation opt-in**: `(channel:unstable)` now crosses into the classifier.
When a record is annotated with `(channel:unstable)`, a prerelease proposed over a stable
current produces **HOLD** (not SKIP) — regardless of CLI flags (unless overridden by
`--stable=full` or `--unstable=full`). The annotation signals intent that the classifier
honors.

```
Annotation (channel:unstable)          CLI --unstable=full / --stable=full
         │                                      │
         ▼                                      ▼
  [FETCHER AXIS]                      [CLASSIFIER AXIS]
  channel.sh selects                  decide.sh step 4
  which tags the fetcher              priority ladder:
  queries from upstream               stable=full → SKIP
                                      unstable=full → bypass
                  └── bridge ──►      channel:unstable → HOLD
                                      default → SKIP
```

### Axis 1 — Annotation `(channel:unstable)`: fetcher axis

`(channel:unstable)` routes the fetcher through `bin/lib/env-update/core/channel.sh`,
which selects the highest prerelease tag from the upstream source.

It also bridges into the classifier: when the channel is `unstable`, a stable→prerelease
proposed version produces **HOLD** instead of SKIP (annotation opt-in bridge).

**Source**: `bin/lib/env-update/core/channel.sh`; `bin/lib/env-update/core/decide.sh` step 4

### Axis 2 — CLI flags: classifier axis

- `--unstable=full`: passes `unstable_mode=full` ($6) to `_gs_eu2_classify_decision`,
  bypassing step 4 entirely. Global for all records.
- `--stable=full`: passes `stable_mode=full` ($7) to `_gs_eu2_classify_decision`, which
  force-rejects prerelease at step 4 with highest priority (overrides channel annotation).
  Also overrides any `(channel:*)` annotation on the fetcher axis and emits a per-record warning.

**Source**: `bin/lib/env-update/core/args.sh`; `main.sh`

### Step 4 priority in detail

| Priority | Condition | Result |
|----------|-----------|--------|
| 1st | `--stable=full` | SKIP (force-reject, overrides channel annotation) |
| 2nd | `--unstable=full` | bypass step 4 (continue to step 5+) |
| 3rd | `(channel:unstable)` annotation | HOLD (opt-in review) |
| default | none of the above | SKIP |

### Consequence table

| Annotation | CLI flag | Fetcher returns | Step 4 result | Step 7 fires? | Final decision |
|------------|----------|-----------------|---------------|---------------|----------------|
| *(none)* | *(none)* | stable `18.0.0` | No trigger | Yes (major) | **HOLD** |
| *(none)* | *(none)* | prerelease `18.0.0-rc1` | SKIP (default) | — | **SKIP** |
| `(channel:unstable)` | *(none)* | prerelease `6.0.0-alpha-1` | HOLD (bridge) | — | **HOLD** |
| `(channel:unstable)` | `--unstable=full` | prerelease `18.0.0-rc1` | bypassed | Yes (major) | **HOLD** |
| `(channel:unstable)` | `--stable=full` | prerelease `18.0.0-rc1` | SKIP (force) | — | **SKIP** |
| `:18` pin | *(none)* | stable `18.0.0` | No trigger | No (pin matches) | **AUTO** |
| *(none)* | `--force-auto` | stable `18.0.0` | No trigger | Yes → upgraded | **AUTO** |

---

## Common Scenario Reference

### Scenario A: Track next major pre-release (opt-in per record)

```bash
# @todo env-update dockerhub:library/postgres (channel:unstable) :19 18.3
GLOBAL_STACK_POSTGRES18_VERSION=18.3
```

Run: `bin/env-update.sh --check --unstable=full`

- Fetcher: `(channel:unstable)` → returns highest prerelease (e.g. `19.0-beta2`)
- Step 4: bypassed by `--unstable=full`
- Step 7: skipped because `:19` pin matches → **AUTO**
- Without `--unstable=full`: step 4 fires → **SKIP**
- Without `:19` pin: step 7 fires → **HOLD**

### Scenario B: Review all major bumps this cycle

```bash
bin/env-update.sh --check
# Shows HOLD for any record where proposed crossed a major boundary
# Review the HOLD items, then add :N pin or use --force-auto

bin/env-update.sh --apply --force-auto --confirm="Confirm override"
# One-time: upgrades all HOLD to AUTO and writes them
```

### Scenario C: Single-record major bump

```bash
# Add :18 pin to the annotation for the specific record
# @todo env-update dockerhub:library/postgres :18 17.5
GLOBAL_STACK_POSTGRES17_VERSION=17.5

bin/env-update.sh --apply
# → AUTO (pin matches, step 7 skipped, step 8 would check escaping — passes for 18.x)
```

---

## Reference

| Component | File | Role |
|-----------|------|------|
| Decision ladder | `bin/lib/env-update/core/decide.sh` | Steps 1–9; emits AUTO/HOLD/MANUAL/SKIP/RESOLVED |
| Post-classify phases | `bin/lib/env-update/main.sh` | force-auto upgrade, lock gate, SHA classification |
| CLI argument parsing | `bin/lib/env-update/core/args.sh` | `--unstable`, `--force-auto`, `--stable`, etc. |
| Channel (fetcher axis) | `bin/lib/env-update/core/channel.sh` | `(channel:unstable)` tag filtering |
| Annotation parsing | `bin/lib/env-update/core/parse.sh` | Extracts flags, hints, channel from `@todo` lines |
| env-scan pipeline | `bin/env-scan.sh` | 8-phase sync: source index → backup → sync → propagate |
