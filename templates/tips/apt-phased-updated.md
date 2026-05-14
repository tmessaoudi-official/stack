# APT Phased Updates

## What are phased updates?

Ubuntu and Debian roll out some package updates in **phases** — initially releasing them to a small percentage of users, then gradually expanding to 100%. This is a safety mechanism: if a bad update breaks things for the first 5%, it gets pulled before reaching everyone.

Your machine's phase assignment is based on a hash of your machine ID, so it's deterministic — you'll consistently be in or out of a phase for a given package version.

## When to enable phased updates (always-include)

By default, phased updates are **excluded** — your system only sees a package when it reaches your phase. If you want every machine to always receive updates immediately (regardless of phase), add:

```
APT::Get::Always-Include-Phased-Updates "true";
```

to `/etc/apt/apt.conf.d/99-phased-updates`.

**When this makes sense**:
- **CI/CD builders**: you want reproducible, current packages across all runners
- **Security-sensitive systems**: you don't want to wait for a security fix to reach your phase
- **Environments where you track upstream closely**: testing machines, developer workstations that deliberately run the bleeding edge

**When NOT to enable it**:
- **Stable production systems**: the phased rollout exists to protect you — opting out means you'll be in the first wave of any bad update
- **Systems where "it works" is more important than "it's current"**: a server running smoothly doesn't need the latest minor update the moment it's released

## Check if a package is in a phased update

```bash
apt-cache policy PACKAGE
```

Look for `Phased-Update-Percentage` in the output. A value less than 100 means it's still rolling out.
