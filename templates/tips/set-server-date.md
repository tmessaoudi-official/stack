# Set System Date and Time Manually

**What it solves**: Forcing a machine's clock to a specific date/time — needed for certificate expiry testing, reproducing time-sensitive bugs, or running on offline VMs where NTP doesn't sync.

## The correct sequence

NTP must be disabled first, or it will immediately overwrite your manual setting:

```bash
# 1. Disable NTP sync
sudo timedatectl set-ntp false

# 2. Set the date and time
sudo timedatectl set-time "2021-01-15 10:30:00"

# 3. Verify
timedatectl status

# 4. Re-enable NTP when done (restores automatic sync)
sudo timedatectl set-ntp true
```

**Gotcha**: If you skip step 1 and run `set-time` while NTP is active, the command may succeed but the clock snaps back within seconds. Always disable NTP first.

## Quick one-time set (alternative)

For a fast one-off change without using `timedatectl`:

```bash
sudo date -s "2021-01-15 10:30:00"
```

`date -s` takes effect immediately. NTP will still correct it on the next sync cycle, so this is only reliable short-term or on systems without NTP.

## Use cases

- **Certificate expiry testing**: set the date past a cert's `notAfter` to test expiry handling
- **VM snapshots**: VMs restored from snapshots often have stale clocks — set manually if NTP is unavailable
- **Offline machines**: air-gapped systems with no NTP server need manual clock management
- **Cron/scheduler testing**: advance the clock to trigger a scheduled job immediately
