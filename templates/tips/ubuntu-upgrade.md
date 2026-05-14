# Ubuntu Release Upgrade

## Commands

```bash
# Upgrade to next LTS (or latest release with -d):
update-manager -c -d

# Or via CLI:
sudo do-release-upgrade -d
```

The `-d` flag enables development/unreleased versions. For upgrading between stable LTS releases, `-d` is only needed when the target LTS has been released but `do-release-upgrade` hasn't yet set it as the default upgrade path (typically within 3 months of LTS release).

## Pre-upgrade checklist

Run these before starting — an upgrade started on a broken system is much harder to recover:

```bash
# 1. Ensure the current system is fully up to date
sudo apt-get update
sudo apt-get dist-upgrade

# 2. Remove old kernels (frees space in /boot, which must have room for the new kernel)
sudo apt-get autoremove --purge

# 3. Check for held packages — these won't upgrade and may block the release upgrade
apt-mark showhold

# 4. Disable third-party PPAs — they often don't have packages for the new release
#    and can cause upgrade failures
ls /etc/apt/sources.list.d/
# Temporarily disable by commenting out or renaming to *.disabled

# 5. Check available disk space
df -h
# /boot needs ~200MB free; / needs ~2GB free minimum
```

## What can go wrong

- **PPAs**: third-party PPAs for the old release break on upgrade. Disable them before upgrading, re-enable after (if a new-release version exists).
- **Docker APT source**: the Docker APT repo uses Ubuntu codenames in its URL (`jammy`, `noble`, etc.). After upgrade, `apt update` will fail until you update `/etc/apt/sources.list.d/docker.sources` with the new codename.
- **Custom kernels**: out-of-tree kernel modules (nvidia, VirtualBox, etc.) need to be rebuilt for the new kernel. The upgrade process may warn you but won't rebuild them automatically.
- **Config file conflicts**: `do-release-upgrade` will prompt you about modified config files (Apache, SSH, etc.) — read the diff before choosing to keep your version or take the new one.

## Recovery: if the upgrade hangs or breaks

```bash
# Fix interrupted dpkg/apt state (run this first if upgrade died mid-way):
sudo dpkg --configure -a

# Force-install any packages left in broken state:
sudo apt-get install -f

# If apt is completely stuck, forcefully remove the lock:
sudo rm /var/lib/dpkg/lock-frontend
sudo rm /var/lib/dpkg/lock
sudo dpkg --configure -a
```

After recovery, re-run `sudo apt-get dist-upgrade` to complete any remaining package updates before retrying the release upgrade.
