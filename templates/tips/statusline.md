# Claude Code Statusline — Field Reference

The statusline is a single-line display shown at the bottom of the Claude Code TUI after
every assistant turn. It is produced by `~/.claude/hooks/statusline.sh`, a `PostToolUse`
hook registered as `statusLine` in `settings.json`. All output goes through stdout;
stderr is never touched (zero tokens — Claude never sees it).

---

## Anatomy

```
⚠ 💭 sonnet  ·  [████████░▒] 84% 141K  ·  master ✎ 38 ↑ 70 3m ago  ·  $0.00  ·  ⟳ 0m ago  ·  ⏱ 10h27m
─────────────    ──────────────────────    ──────────────────────────    ──────    ────────────    ────────
   [1]                    [2]                          [3]                [4]         [5]            [6]
```

Segments are separated by `  ·  ` (two spaces · two spaces). Segments are **omitted
entirely** when they have nothing to show — the separator disappears with them.

---

## Segment [1] — Model + Mode + Urgency

```
⚠ 💭 sonnet
```

Three tokens concatenated without separator, always present.

### Urgency prefix (leftmost, highest visibility)

| Symbol | Meaning | Trigger |
|--------|---------|---------|
| `⚠ `  | Context is filling — consider /handoff | `URGENCY` field in `status-context.txt` contains `⚠` |
| `🔴 ` | Context critical — run /handoff NOW | `URGENCY` field contains `🔴` |
| `🟡 ` | Context moderately full — heads up | `URGENCY` field contains `🟡` |
| _(none)_ | Plenty of space | Default |

The urgency level is set by `stop-context-bar.sh` when it writes `status-context.txt`
after each turn, based on how much free space remains in the effective context window:

| Free tokens | Bar color | Urgency written |
|-------------|-----------|-----------------|
| > 60 K      | green     | _(none)_        |
| 30 – 60 K   | yellow    | `🟡`            |
| 10 – 30 K   | orange    | `⚠`             |
| < 10 K      | red       | `🔴`            |

### Mode prefix

| Symbol | Meaning | Condition |
|--------|---------|-----------|
| `⚡ `  | Fast mode active | `fast_mode == true` in payload |
| `💭 `  | Extended thinking active | `thinking.enabled == true` in payload |
| _(none)_ | Standard mode | Default |

Fast mode and thinking are mutually exclusive — only one prefix appears.

### Model short name

| Displayed | Matches |
|-----------|---------|
| `opus`    | any model id containing `opus` |
| `sonnet`  | any model id containing `sonnet` |
| `haiku`   | any model id containing `haiku` |
| _(full id)_ | unknown model — shown verbatim up to first `@` |

When a 1M-window model is active, `1M` is appended directly to the short name: `sonnet 1M`.
Source: `WIN` field in `status-banner.txt` (written by `session-start-banner.sh`). Only shown for non-standard window sizes.

---

## Segment [2] — Context Usage

```
[████████░▒] 84% 141K
```

Three tokens joined by spaces, always present: progress bar · percentage · token count.

### Percentage (`84%` or `~84%`)

Proportion of the **effective window** consumed by input tokens.
Effective window = full context window − autocompact buffer (16.5% of window).

A leading tilde (`~`) means the value is an **estimate** — the real API-reported
`used_percentage` field is not yet available (first turn of a new session, before the
first Stop hook fires). After the first turn the tilde disappears permanently.

**Data priority** (highest wins):

1. `status-context.txt` `PCT` field with `IS_ESTIMATE: false` — transcript-confirmed real data
2. Payload `context_window.used_percentage` when present (real API value)
3. `status-context.txt` `PCT` field with `IS_ESTIMATE: true` — session-start estimate
4. Calculated from `total_input_tokens / context_window_size` as a last resort

### Token count (`141K`)

Raw input token count in thousands, read from `status-context.txt` `INPUT_K` field.
Omitted when 0 or absent. Tells you the absolute load regardless of window size.

---

## Segment [3] — Git

```
master ✎ 38 ↑ 70 3m ago
```

Space-separated tokens within the segment. The branch name is always present when
inside a git repo. All other tokens are **optional** — they disappear when zero/absent.

| Token | Symbol | Meaning | Source |
|-------|--------|---------|--------|
| Branch | _(plain text)_ | Current branch name | `GIT_BRANCH` in `status-banner.txt`; falls back to live `git rev-parse --abbrev-ref HEAD` |
| Dirty | `✎ N` | N files with uncommitted changes (tracked + untracked) | `GIT_DIRTY` in `status-banner.txt` |
| Unpushed | `↑ N` | N local commits not yet pushed to the tracked upstream | `GIT_UNPUSHED` in `status-banner.txt` |
| Stashes | `⚑ N` | N stash entries | `GIT_STASHES` in `status-banner.txt` |
| Last commit | `3m ago` | Age of the most recent commit | `GIT_LAST` in `status-banner.txt` |

The git data is **written at session start** by `session-start-banner.sh` using five
parallel `git` subprocesses (each guarded by `timeout 2`). It is **not refreshed
between turns** — only refreshed at the next `SessionStart` (new session or post-compaction).

If no tracking branch exists for the current branch, `↑` is suppressed entirely
(`GIT_UNPUSHED == -1` signals "no upstream").

---

## Segment [4] — Session Cost

```
$0.00
```

Always present. Cumulative USD cost for the current session, formatted to two decimal
places. Source: `cost.total_cost_usd` from the statusline payload (provided natively by
Claude Code; includes all API calls in the session).

---

## Segment [5] — Handoff Age

```
⟳ 0m ago
```

**Only shown when a handoff file exists.** Age of the most recent `/handoff` call.

Source: mtime of `~/.claude/projects/<slug>/memory/sessions/handoff.md`.

| Age | Format shown |
|-----|-------------|
| < 1 hour | `⟳ Nm ago` |
| 1 h – 23 h | `⟳ Nh ago` |
| ≥ 24 h | `⟳ Nd ago` |

When `status-banner.txt` has a `HANDOFF` field (written by `session-start-banner.sh`),
it is used directly. Otherwise the statusline computes the age live from the file mtime.

A `⟳ 0m ago` means you just ran `/handoff`. A missing `⟳` segment means no handoff
file exists yet — run `/handoff` at the end of any significant session.

---

## Segment [6] — Session Uptime

```
⏱ 10h27m
```

**Only shown when the session has been running for more than 60 seconds.**
Elapsed time since the current pane was launched.

| Elapsed | Format |
|---------|--------|
| 1 m – 59 m | `⏱ Nm` |
| ≥ 1 hour | `⏱ NhMm` |

Source: `STARTED_AT` unix timestamp in `status-banner.txt`.
When `claux` is used, `STARTED_AT` is anchored to the pane launch time (stable across
compactions — the clock does not reset after auto-compact). Without `claux`, it resets
to the most recent `SessionStart`.

---

## Optional Segments (appear only when relevant)

These segments appear conditionally. The order below matches the actual assembly order in `statusline.sh`.

### Clear indicator `↩`

```
·  ↩  ·
```

Shown immediately after the context segment when `/clear` has been run at least once in the current session. Source: `CLEAR_CTR` field in `status-context.txt` (written by `stop-context-bar.sh`). Resets to 0 at session start.

### Cache hit rate `💾 N%`

```
·  💾 42%  ·
```

Shown when the fraction of input tokens served from the prompt cache is > 0. Computed from `cache_reads_input_tokens / total_input_tokens` in the payload. Appears between the context segment and the git segment.

### Agent context `[name]`

```
·  [global-stack-lead-dev]  ·
```

Shown when Claude is running inside a named agent (`agent.name` non-empty in the
payload). Identifies which agent definition is active.

### Token velocity `↑NK/h`

```
·  ↑23K/h  ·
```

Shown after the cost segment, once the session has been running for more than 10 minutes and input token data is available. Rate at which input tokens are accumulating, projected to an hourly value. Source: `INPUT_K` (from `status-context.txt`) ÷ session elapsed time.

### Cost rate `$N.NN/h`

Not a separate segment — appended to the cost segment after 10 minutes of uptime:

```
$0.13 $0.04/h
```

Source: `cost.total_cost_usd` ÷ session elapsed time. Disappears if the rate rounds to `$0.00/h`.

### Lines changed `+N/-M`

```
·  +142/-38  ·
```

Shown when the session has written or deleted lines. Source: `cost.total_lines_added`
and `cost.total_lines_removed` from the payload. Omitted entirely when both are zero.
Format: `+N` alone when only additions, `+N/-M` when both, `/-M` alone when only deletions.

### Last turn duration `~Ns` / `~NmMs`

```
·  ~12s  ·
```

Duration of the most recent assistant turn. Shown only when > 3 seconds. Source: `TURN_DUR` field in `status-context.txt` (written by `stop-context-bar.sh`). Format: `~Ns` for under a minute, `~NmMs` for a minute or more.

### Turn counter `T:N`

```
·  T:7  ·
```

Number of assistant turns completed in this session. Source: `TURNS` field in `status-context.txt` (written by `stop-context-bar.sh`). Shown only when N > 0.

### Cumulative output `Σ NK`

```
·  Σ 1234K  ·
```

Total output tokens generated **across all compaction boundaries** in the current pane
session. Each time autocompact fires (creating a new session ID), `session-start-banner.sh`
reads the previous session's `SUM_K` from `status-context.txt` and accumulates it into
`cumulative-output.txt`. Shown only when the cumulative value is > 0.

This answers "how much total output has Claude produced in this work session?" across
context resets.

### CLAUDE.md staleness `md⚠`

```
·  md⚠  ·
```

Shown when the project's `CLAUDE.md` has not been touched in more than **3 days** after
the latest git commit in the repo. Computed at session start by comparing `CLAUDE.md`
mtime to the timestamp of the most recent commit (`git log -1 --format='%ct'`).
A gap > 259 200 s (3 days) triggers this flag.

Signals that CLAUDE.md may be out of date relative to recent code changes — run
`/repair` to check for drift.

### Mega-analysis staleness `ana⚠`

```
·  ana⚠  ·
```

Shown when the most recent mega-analysis report directory in
`~/.claude/projects/meta-reports/` is older than **1 week** (604 800 s).
Computed at session start from the mtime of the newest dated directory.

Signals that the full codebase health picture may be stale.

---

## Supporting Infrastructure

### Data flow

```
SessionStart → session-start-banner.sh
  └─ writes status-banner.txt     (model, git, handoff, uptime anchor)
  └─ writes status-context.txt    (initial ctx estimate, IS_ESTIMATE:true)

Stop → stop-context-bar.sh
  └─ reads transcript, gets real input_tokens
  └─ overwrites status-context.txt  (real PCT, IS_ESTIMATE:false, urgency, TURNS, TURN_DUR, CLEAR_CTR)
  └─ prints context bar to stderr

StatusLine hook → statusline.sh   (runs after every assistant turn)
  └─ reads payload JSON           (model, cost, fast_mode, thinking, lines)
  └─ reads status-context.txt     (PCT, INPUT_K, URGENCY)
  └─ reads status-banner.txt      (git, handoff, uptime, flags)
  └─ prints one line to stdout    → displayed by Claude Code TUI
```

### Files read by statusline.sh

| File | Location | Contents |
|------|----------|---------|
| `status-context.txt` | `~/.claude/run/` or `~/.claude/run/sessions/<PANE_ID>/` | PCT, INPUT_K, EFF_K, FREE_K, BUF_K, SUM_K, URGENCY, IS_ESTIMATE, TURNS, TURN_DUR, CLEAR_CTR |
| `status-banner.txt` | same dir | MODEL, WIN, BUF, HANDOFF, ANALYSIS, GIT_BRANCH, GIT_DIRTY, GIT_UNPUSHED, GIT_STASHES, GIT_LAST, CLAUDEMD, STARTED_AT |
| `cumulative-output.txt` | same dir | single integer: total output K across compactions |
| `handoff.md` | `~/.claude/projects/<slug>/memory/sessions/` | read for mtime only |

When `claux` (the session manager) sets `CLAUDE_PANE_ID`, each pane gets its own
isolated directory under `run/sessions/<PANE_ID>/` so multiple simultaneous Claude
panes don't overwrite each other's state. Without `claux`, all panes share `run/`.

### Context window sizes (hardcoded lookup table)

| Model variant | Window | Effective (−16.5% buffer) |
|---------------|--------|--------------------------|
| any model id with `[1m]` suffix | 1 000 000 | ~835 000 |
| `opus`, `sonnet`, `haiku` | 200 000 | ~167 000 |

---

## Debugging

```bash
# Dump the raw payload the statusline receives (run Claude with this env var)
env STATUSLINE_PROBE=1 claude ...
# Payload written to: /tmp/statusline-probe.json

# Inspect current state files
cat ~/.claude/run/status-context.txt
cat ~/.claude/run/status-banner.txt

# Force a re-read by restarting the session (triggers SessionStart → status-banner.sh)

# Run the statusline hook manually against a saved probe
cat /tmp/statusline-probe.json | bash ~/.claude/hooks/statusline.sh
```

---

## Complete Field Inventory

| Segment | Always shown | Symbol | Omit when |
|---------|-------------|--------|-----------|
| Urgency prefix | no | `⚠ ` / `🔴 ` / `🟡 ` | context not filling |
| Mode prefix | no | `💭 ` / `⚡ ` | standard mode |
| Model name | **yes** | plain text | — |
| Window tag | no | `1M` (appended to model) | standard 200K window |
| Context bar | **yes** | `[████░░░░░▒]` | — |
| Context % | **yes** | `~N%` / `N%` | — |
| Token count | no | `NK` | INPUT_K is 0 |
| Clear indicator | no | `↩` | no `/clear` this session |
| Cache hit rate | no | `💾 N%` | no cache reads |
| Git branch | no | plain text | not in a git repo |
| Dirty count | no | `✎ N` | N == 0 |
| Unpushed count | no | `↑ N` | N == 0 or no upstream |
| Stash count | no | `⚑ N` | N == 0 |
| Last commit age | no | `Nm ago` | no commits |
| Agent name | no | `[name]` | not in an agent |
| Session cost | **yes** | `$N.NN` | — |
| Cost rate | no | `$N.NN/h` (appended to cost) | uptime < 10min |
| Token velocity | no | `↑NK/h` | uptime < 10min or no token data |
| Cumulative output | no | `Σ NK` | no compactions yet |
| Lines changed | no | `+N/-M` | both are 0 |
| Last turn duration | no | `~Ns` / `~NmMs` | ≤ 3s |
| Turn counter | no | `T:N` | N == 0 |
| Handoff age | no | `⟳ N_` | no handoff file |
| Session uptime | no | `⏱ NhMm` | elapsed < 60s |
| CLAUDE.md staleness | no | `md⚠` | CLAUDE.md up to date |
| Analysis staleness | no | `ana⚠` | report < 1 week old |
