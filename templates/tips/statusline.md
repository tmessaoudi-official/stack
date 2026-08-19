# Claude Code Statusline — Complete Reference

The statusline is a single-line display shown at the bottom of the Claude Code TUI after
every assistant turn. It is produced by `~/.claude/hooks/statusline.sh`, registered as a
`statusLine` hook in `~/.claude/settings.json`.

---

## Registration

`statusLine` is a top-level hook type (not nested under `hooks`):

```json
{
  "statusLine": "\"$HOME\"/.claude/hooks/statusline.sh"
}
```

The hook script receives a JSON payload on **stdin** and must print a single line to **stdout**.
Claude Code renders that line verbatim at the bottom of the TUI. Stderr is ignored.

---

## Payload Schema — statusLine Hook

Complete authoritative schema (verified 2026-05-30). Optional fields are **entirely absent**
when the condition is not met — never `null`. Fields that may be `null` are noted.

```json
{
  "cwd": "/stack",
  "session_id": "abc123…",
  "session_name": "my-session",
  "transcript_path": "/path/to/transcript.jsonl",

  "model": {
    "id": "claude-sonnet-4-6",
    "display_name": "Sonnet"
  },

  "workspace": {
    "current_dir": "/stack",
    "project_dir": "/stack",
    "added_dirs": [],
    "git_worktree": "feature-xyz",
    "repo": {
      "host": "github.com",
      "owner": "anthropics",
      "name": "claude-code"
    }
  },

  "version": "2.1.90",
  "output_style": { "name": "default" },

  "cost": {
    "total_cost_usd": 0.01234,
    "total_duration_ms": 45000,
    "total_api_duration_ms": 2300,
    "total_lines_added": 156,
    "total_lines_removed": 23
  },

  "context_window": {
    "total_input_tokens": 131000,
    "total_output_tokens": 1200,
    "context_window_size": 200000,
    "used_percentage": 65.5,
    "remaining_percentage": 34.5,
    "current_usage": {
      "input_tokens": 8500,
      "output_tokens": 1200,
      "cache_creation_input_tokens": 5000,
      "cache_read_input_tokens": 118500
    }
  },

  "exceeds_200k_tokens": false,

  "thinking": { "enabled": true },

  "effort": { "level": "high" },

  "agent": { "name": "stack-infra-reviewer" },

  "rate_limits": {
    "five_hour": { "used_percentage": 23.5, "resets_at": 1738425600 },
    "seven_day":  { "used_percentage": 41.2, "resets_at": 1738857600 }
  },

  "vim": { "mode": "NORMAL" },

  "pr": {
    "number": 1234,
    "url": "https://github.com/anthropics/claude-code/pull/1234",
    "review_state": "pending"
  },

  "worktree": {
    "name": "my-feature",
    "path": "/path/to/.claude/worktrees/my-feature",
    "branch": "worktree-my-feature",
    "original_cwd": "/stack",
    "original_branch": "main"
  }
}
```

### Optional field conditions

| Field | Present when |
|-------|-------------|
| `session_name` | Session has a custom name |
| `workspace.git_worktree` | Inside a linked worktree |
| `workspace.repo` | Inside a git repo with remote configured |
| `context_window.used_percentage` | After first API call; may be null before |
| `context_window.remaining_percentage` | Same as used_percentage |
| `context_window.current_usage` | null before first API call, null after /compact until next call |
| `effort` | Model supports effort levels (thinking-capable models) |
| `agent` | Launched with `--agent` flag or agent settings |
| `rate_limits` | Claude.ai Pro/Max subscribers, after first API response |
| `vim` | Vim mode is enabled |
| `pr` | Open PR for the current branch |
| `worktree` | `--worktree` session |

### Key field paths (jq)

| Segment | jq path | Notes |
|---------|---------|-------|
| Model ID | `.model.id` | e.g. `"claude-sonnet-4-6"` |
| Thinking | `.thinking.enabled` | boolean, always present |
| Effort | `.effort.level // ""` | "low"/"medium"/"high"/"xhigh"/"max" |
| Cost USD | `.cost.total_cost_usd` | cumulative session cost |
| Duration ms | `.cost.total_duration_ms` | ms since session start |
| Lines added | `.cost.total_lines_added` | |
| Lines removed | `.cost.total_lines_removed` | |
| CWD | `.workspace.current_dir // .cwd` | prefer workspace.current_dir |
| Agent | `.agent.name // ""` | empty string when not set |
| **Cache reads** | `.context_window.current_usage.cache_read_input_tokens // 0` | **nested inside current_usage** |
| Total input | `.context_window.total_input_tokens` | includes all categories |
| Window size | `.context_window.context_window_size` | |
| Used % | `.context_window.used_percentage` | null before first API call |
| PR state | `.pr.review_state // ""` | "approved"/"pending"/"changes_requested"/"draft" |
| Vim mode | `.vim.mode // ""` | "NORMAL"/"INSERT"/"VISUAL"/"VISUAL LINE" |

> **Cache reads are NOT at `.context_window.cache_reads_input_tokens`** — that path does
> not exist. The correct path is `.context_window.current_usage.cache_read_input_tokens`.

---

## Other Hook Payloads

### SessionStart, Stop

```json
{
  "session_id": "abc123…",
  "transcript_path": "/home/developer/.claude/projects/…/abc123….jsonl",
  "cwd": "/stack",
  "hook_event_name": "Stop"
}
```

Stop hooks parse `transcript_path` (JSONL, one message per line) to compute token counts.
`session-status.sh` provides `ss_parse_transcript`, `ss_window_for_model`, `ss_context_bar`.

### SubagentStop

```json
{
  "agent_name": "code-reviewer",
  "transcript_path": "…",
  "session_id": "…",
  "cwd": "…",
  "hook_event_name": "SubagentStop"
}
```

---

## Auxiliary Data Files

The statusline reads these files (written by SessionStart + Stop hooks) for data not
available in the statusLine payload:

### `~/.claude/run/status-banner.txt`

Written by `session-start-banner.sh` (SessionStart), refreshed per-turn by `stop-git-status.sh`.

```
MODEL:sonnet-4-6
WIN:200K
BUF:33K
HANDOFF:5m ago auto
ANALYSIS:6 days ago
GIT:master · clean
GIT_BRANCH:master
GIT_DIRTY:0
GIT_UNPUSHED:2
GIT_STASHES:0
GIT_LAST:2h ago
CLAUDEMD:
CWD:/stack
STARTED_AT:1748000000
```

### `~/.claude/run/status-context.txt`

Written by `stop-context-bar.sh` after every turn. Read by statusline for urgency + turn data.

```
SESSION_ID:<uuid>
PCT:65
INPUT_K:131
EFF_K:167
FREE_K:36
BUF_K:33
SUM_K:42
URGENCY:🟡
IS_ESTIMATE:false
TURNS:7
TURN_DUR:23
CLEAR_CTR:0
```

`IS_ESTIMATE:true` during startup (before first real API call). Flips to `false` after Stop hook
writes real data. On first transition, `startup-ctx-baseline.txt` is written for the next
session's initial estimate.

### `~/.claude/run/pane-started-at.txt`

Session start epoch (Unix seconds). Written once on first SessionStart; read on subsequent
starts (compaction) to preserve uptime across context boundaries.

### `~/.claude/run/lifetime-output.txt`

Cumulative output tokens (K) across all sessions. Never auto-resets — delete file to reset.

### `~/.claude/run/actual-model.txt`

Real model ID from last Stop hook. Used by next session's banner when `settings.json` shows
an alias (e.g. `opusplan`).

### `~/.claude/run/startup-ctx-baseline.txt`

Two lines: token count + model ID. Saved on first IS_ESTIMATE→real transition. Used by next
session's SessionStart for an accurate initial % estimate.

---

## Statusline Anatomy

```
⚠ 💭 sonnet  ·  [████████░▒] ~84% 141K  ·  /stack  ·  master ✎ 38 ↑ 2  ·  $0.42  ·  T:12
────────────    ──────────────────────    ──────    ──────────────────    ──────    ──────
    [1]                  [2]               [3]              [4]            [5]      [6+]
```

Segments separated by `  ·  `. Omitted entirely when empty (separator disappears too).

---

## Segment Reference

### [1] Model + Mode + Urgency

**Always present.** Format: `{urgency}{mode}{model_short}{win_tag}{effort_suffix}`

**Urgency prefix** (set by `stop-context-bar.sh` based on free tokens):

| Symbol | Free tokens | Trigger |
|--------|-------------|---------|
| _(none)_ | > 60K | default |
| `🟡 ` | 30–60K | URGENCY field in status-context.txt |
| `⚠ ` | 10–30K | |
| `🔴 ` | < 10K | |

Urgency is recomputed from the payload's `total_input_tokens` (accurate) when IS_ESTIMATE is
false, overriding the file value (which underestimates because transcript parse omits cache reads).

**Mode prefix:**

| Symbol | Condition |
|--------|-----------|
| `💭 ` | `.thinking.enabled == true` |
| _(none)_ | Standard mode |

**Effort suffix** (appended to model short name when thinking is enabled):

| Suffix | `.effort.level` |
|--------|----------------|
| ` [high]` | "high" |
| ` [xhigh]` | "xhigh" |
| ` [max]` | "max" |
| _(none)_ | "low"/"medium" or field absent |

**Model short name:**

| Display | Matches |
|---------|---------|
| `opus` | model id containing "opus" |
| `sonnet` | model id containing "sonnet" |
| `haiku` | model id containing "haiku" |
| _(full id)_ | unknown model (truncated at first `@`) |

**Window tag:** ` 1M` appended when `.context_window.context_window_size >= 900000`.

---

### [2] Context Usage

Format: `[████████░▒] ~84% 141K`

- **Bar**: 9 fill chars + 1 trailing `▒`. `█` = used, `░` = free.
- **Tilde**: present when `IS_ESTIMATE:true` (startup estimate, not API-confirmed)
- **Percentage**: from `.context_window.used_percentage` when available; computed from
  `total_input_tokens / context_window_size` as fallback
- **Token count (K)**: from `.context_window.total_input_tokens`; overrides file's INPUT_K when larger

**Math:**
```
EFFECTIVE = context_window_size - BUFFER
BUFFER    = window_size * 165 / 1000   (≈ 16.5%)
PCT       = total_input_tokens / EFFECTIVE * 100
```

---

### [3] CWD

Current working directory with `~` substitution. Deep paths (> 2 slash levels) abbreviated
to `…/parent/basename`. Source: `.workspace.current_dir // .cwd` from payload.

---

### [4] Git

Format: `master ✎ 38 ↑ 2 ⚑ 1 2h ago`

Read from `status-banner.txt` (refreshed per-turn by `stop-git-status.sh`). Falls back to
`git rev-parse --abbrev-ref HEAD` in `cwd` when no banner file exists.

| Token | Field | Shown when |
|-------|-------|-----------|
| `master` | `GIT_BRANCH` | always |
| `✎ N` | `GIT_DIRTY` | > 0 uncommitted files |
| `↑ N` | `GIT_UNPUSHED` | > 0 commits ahead of upstream |
| `⚑ N` | `GIT_STASHES` | > 0 stash entries |
| `2h ago` | `GIT_LAST` | last commit age |

`GIT_UNPUSHED = -1` means no upstream configured — the `↑` token is suppressed.

---

### [5] Cost

Format: `$0.42` or `$0.42 $0.12/h`

Source: `.cost.total_cost_usd`. Hourly rate `$N/h` appended when session > 10 minutes.

---

### [6+] Variable segments

Order: `↩` · `💾N%` · `[agent]` · `↑NK/h` · `ΣNK` · `+N/-N` · `~Ns` · `T:N` · `⟳ Nm` · `⏱ NhNm` · `md⚠` · `ana⚠`

| Token | Source | Shown when |
|-------|--------|-----------|
| `↩` | `CLEAR_CTR > 0` | Context dropped > 40pts (likely /clear) |
| `💾N%` | `.context_window.current_usage.cache_read_input_tokens` | Cache hit rate > 0% |
| `[agent]` | `.agent.name` | Running inside a named agent |
| `↑NK/h` | Computed: input_k × 3600 / elapsed | Session > 10 min |
| `ΣNK` | `lifetime-output.txt` | Lifetime output > 0 |
| `+N/-N` | `.cost.total_lines_added/removed` | Either > 0 |
| `~Ns` | `TURN_DUR` field | Turn took > 3s |
| `T:N` | `TURNS + turns-total.txt` | Turn count > 0 |
| `⟳ Nm` | `handoff.md` mtime | Handoff file exists and non-empty |
| `⟳ auto Nm` | `handoff.md` + `grep "auto-generated"` | Precompact-generated handoff |
| `⏱ NhNm` | `STARTED_AT` in banner file | Session > 60s old |
| `md⚠` | `CLAUDEMD` field in banner | CLAUDE.md > 3 days behind HEAD |
| `ana⚠` | `ANALYSIS` field in banner | Mega-analysis > 7 days old |

---

## Context Priority Logic

The statusline reconciles two sources of context data (payload vs. file):

1. **File `IS_ESTIMATE:false` + payload `used_percentage` present**: both real. Use higher PCT.
2. **File real, payload estimate**: use file's real data.
3. **File estimate, payload real**: use payload (real beats estimate).
4. **Both estimates**: use file (has size-aware startup baseline).

**Token count override (F5):** `total_input_tokens` from payload overrides file's `INPUT_K`
when larger. Reason: transcript parsing omits cache reads (`cache_read_input_tokens` is in
`current_usage`), so the stop-hook's parse underestimates.

**Urgency recompute (F6):** When IS_ESTIMATE is false, urgency is recomputed from
`EFF_K - input_k` (real free space). The stop-hook file urgency is stale for the same reason as F5.

---

## Debugging

```bash
# Capture one real payload (run then check the file after the first assistant turn)
STATUSLINE_PROBE=1 claude -p "hello"
cat /tmp/statusline-probe.json | jq .

# Check current file state
cat ~/.claude/run/status-context.txt
cat ~/.claude/run/status-banner.txt

# Simulate a statusLine call
echo '{"model":{"id":"claude-sonnet-4-6"},"context_window":{"total_input_tokens":50000,"context_window_size":200000,"used_percentage":30},"cost":{"total_cost_usd":0.05},"workspace":{"current_dir":"/stack"},"thinking":{"enabled":false}}' \
  | bash ~/.claude/hooks/statusline.sh

# Verify bash syntax
bash -n ~/.claude/hooks/statusline.sh && echo OK
```
