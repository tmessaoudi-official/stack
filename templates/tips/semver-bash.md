# SemVer Comparison in Bash

**What it solves**: Comparing version strings like `1.10.0` vs `1.9.0` correctly in shell scripts. Lexicographic string comparison (`[[ "1.10.0" > "1.9.0" ]]`) is wrong — it compares character by character, so "1.9" > "1.10" (because "9" > "1"). You need version-aware sorting.

## `sort -V` — the built-in tool

GNU `sort -V` (version sort) is correct and widely available on Linux:

```bash
printf '%s\n' "1.0.0" "2.0.0" "1.10.0" "1.9.0" | sort -V
# Output (correct):
# 1.0.0
# 1.9.0
# 1.10.0
# 2.0.0
```

Lexicographic `sort` would give: `1.0.0`, `1.10.0`, `1.9.0`, `2.0.0` (wrong — `1.10.0` before `1.9.0`).

**Platform note**: `sort -V` is GNU coreutils — standard on Linux, but NOT on macOS. On macOS, install it with `brew install coreutils` and use `gsort -V`.

## `sort -V` behavior with suffixes

`sort -V` treats suffixes as "later" in version ordering — any character after the numeric version sorts after the plain number:

| Comparison | sort -V output order | Correct for semver? |
|---|---|---|
| `1.0.0` vs `1.0.0-rc1` | `1.0.0` then `1.0.0-rc1` (rc1 sorts LATER/higher) | **Wrong** — semver says rc1 is OLDER than the stable release |
| `1.0.0` vs `1.0.0-alpine3.23` | `1.0.0` then `1.0.0-alpine3.23` (suffix sorts later) | Acceptable for Docker tags (alpine variant is a different artifact) |
| `v1.0.0` vs `1.0.0` | `1.0.0` then `v1.0.0` (v prefix sorts later) | Use the strip-v pattern in semver_compare to normalize |

**Bottom line**: `sort -V` is correct for file/tag sorting but WRONG for semver prerelease semantics. A release candidate (`1.0.0-rc1`) is older than the stable release (`1.0.0`), but `sort -V` treats the suffix as "later" and places rc1 after stable. See the prerelease section below.

## Comparing two versions

```bash
# Returns "older", "newer", or "equal"
semver_compare() {
  local _a="${1#v}" _b="${2#v}"   # strip v prefix
  local _older
  _older="$(printf '%s\n%s\n' "$_a" "$_b" | sort -V | head -1)"
  if [[ "$_a" == "$_b" ]]; then
    echo "equal"
  elif [[ "$_older" == "$_a" ]]; then
    echo "older"
  else
    echo "newer"
  fi
}

semver_compare "1.9.0" "1.10.0"   # → older
semver_compare "2.0.0" "1.10.0"   # → newer
semver_compare "1.0.0" "1.0.0"    # → equal
```

## Detecting prerelease versions

```bash
is_prerelease() {
  [[ "$1" =~ -(rc|alpha|beta|dev|pre|RC|Alpha|Beta) ]]
}

is_prerelease "1.0.0-rc1"     # → true (exit 0)
is_prerelease "1.0.0"         # → false (exit 1)
is_prerelease "1.0.0-beta.2"  # → true
```

## Prerelease promotion: the sort -V trap

When comparing a prerelease to its stable release, `sort -V` gives the wrong answer:

```bash
printf '%s\n' "1.0.0-rc2" "1.0.0" | sort -V
# Output:
#   1.0.0
#   1.0.0-rc2
# sort -V puts 1.0.0 first — so it considers 1.0.0-rc2 to be "newer" than 1.0.0
```

`sort -V` places `1.0.0-rc2` AFTER `1.0.0` (suffix = later), so `semver_compare "1.0.0-rc2" "1.0.0"` returns "newer" — which is WRONG. The RC is older than the stable release.

**Fix**: detect the same-base prerelease-to-stable promotion explicitly:

```bash
semver_compare_smart() {
  local _a="${1#v}" _b="${2#v}"
  local _base_a="${_a%%-*}" _base_b="${_b%%-*}"   # strip from first dash

  # Same numeric base: prerelease < stable
  if [[ "$_base_a" == "$_base_b" ]]; then
    if is_prerelease "$_a" && ! is_prerelease "$_b"; then
      echo "older"; return
    elif ! is_prerelease "$_a" && is_prerelease "$_b"; then
      echo "newer"; return
    fi
  fi

  # Fall through to sort -V for everything else
  semver_compare "$_a" "$_b"
}

semver_compare_smart "1.0.0-rc2" "1.0.0"   # → older (correct)
semver_compare_smart "1.0.0" "1.0.0-rc2"   # → newer (correct)
semver_compare_smart "1.10.0" "1.9.0"       # → newer (correct)
```

## Check if version A is at least version B

```bash
is_at_least() {
  local result; result="$(semver_compare "$1" "$2")"
  [[ "$result" == "newer" || "$result" == "equal" ]]
}

is_at_least "2.0.0" "1.9.0"   # → true
is_at_least "1.8.0" "1.9.0"   # → false
```
