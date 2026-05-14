# Clear systemd Journal Logs

**What it solves**: The systemd journal (`/var/log/journal/`) accumulates logs indefinitely by default and can consume gigabytes on long-running systems. Clearing it frees disk space without affecting running services.

## Check current size before cleaning

```bash
journalctl --disk-usage
```

Example output: `Archived and active journals take up 2.3G in the file system.`

## Vacuum options

Each option targets a different pruning strategy — pick the one that fits your situation:

```bash
# Remove logs older than N days (good after an incident you no longer need)
sudo journalctl --vacuum-time=2days

# Keep only the most recent N megabytes of logs (good for ongoing cap)
sudo journalctl --vacuum-size=100M

# Keep only the N most recent journal files (good when file count is the issue)
sudo journalctl --vacuum-files=5
```

You can combine options (both apply, whichever frees more):
```bash
sudo journalctl --vacuum-time=7days --vacuum-size=500M
```

## Rotate before vacuuming

`--rotate` forces the current active journal to be archived (closed and marked as old), making it eligible for vacuum. Without rotate, the active journal file is never touched even if it's large:

```bash
sudo journalctl --rotate
sudo journalctl --vacuum-time=2days
```

## Make the limit permanent

To cap journal size automatically going forward, edit `/etc/systemd/journald.conf`:

```ini
[Journal]
SystemMaxUse=500M
SystemKeepFree=1G
MaxRetentionSec=30day
```

Then restart the journald service:
```bash
sudo systemctl restart systemd-journald
```
