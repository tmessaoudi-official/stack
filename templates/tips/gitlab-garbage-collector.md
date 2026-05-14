# GitLab Registry Garbage Collection

**What it solves**: Reclaiming disk space on a self-hosted GitLab instance after bulk image deletes. Deleting images or tags in GitLab marks them for deletion but does NOT free disk space — the actual layer blobs remain until garbage collection runs.

**When to run it**: After bulk-deleting container registry images or tags (e.g., pruning old CI artifacts), when the registry disk partition is running low, or as part of a scheduled maintenance window.

## Commands

```bash
# Dry run — shows what would be deleted without removing anything
gitlab-ctl registry-garbage-collect -m

# Full run — deletes unreferenced blobs (frees disk space)
gitlab-ctl registry-garbage-collect
```

The `-m` flag enables the "missing blobs" check (dry run mode showing what will be removed).

## Important: stop the registry first

The garbage collector **must** run while the registry is not accepting writes. Running it against a live registry risks data corruption:

```bash
# Stop the registry
gitlab-ctl stop registry

# Run garbage collection
gitlab-ctl registry-garbage-collect

# Restart the registry
gitlab-ctl start registry
```

**Gotcha**: If you run `registry-garbage-collect` without stopping the registry, GitLab will warn you but may still proceed — and any blobs written during the run could be incorrectly marked as unreferenced and deleted. Always stop the registry first in production.

## After the run

Verify disk space was reclaimed:
```bash
df -h /var/opt/gitlab/gitlab-rails/shared/registry
```
