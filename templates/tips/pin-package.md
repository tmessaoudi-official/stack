# APT Package Pinning

**What it solves**: Installing or holding a specific version of a package from a specific APT repository, even when a newer version is available from another source. Common use cases: pinning a security package to `resolute-security` instead of `resolute-updates`, or preventing a package from being upgraded.

## Pin a package to a specific release pocket

Create a pin file:
```bash
sudo nano /etc/apt/preferences.d/my-package.pref
```

Contents:
```
Package: <package-name>
Pin: release n=focal-security
Pin-Priority: 990
```

**Priority values**:
- `< 0` — prevents installation
- `1–99` — install only if no other version is available
- `100` — default for installed packages
- `500` — default for APT sources
- `990` — strongly prefer this version (used when you want to pin over the default)
- `1001+` — install even if it would downgrade the installed version

## Install from a specific target

```bash
sudo apt install -t focal-security <package-name>
```

The `-t` flag sets the target release for this one install, without creating a persistent pin.

## Verify what pin is active

```bash
apt-cache policy <package-name>
```

Output shows all available versions, their sources, and their effective priority. The candidate (to be installed) is marked with `***`.

## Temporarily override a pin

```bash
# Install a specific version regardless of pin:
sudo apt-get install PACKAGE=VERSION

# Example:
sudo apt-get install nginx=1.18.0-6ubuntu14
```

## Real-world example: pinning to resolute-security

You want a package from `resolute-security` (vetted security updates only) rather than `resolute-updates` (all updates, including non-security ones):

```
Package: libssl3
Pin: release n=resolute-security
Pin-Priority: 990
```

This ensures `libssl3` only upgrades when a security update ships, not when a general update does.

## Hold a package at its current version

```bash
# Prevent upgrades entirely:
sudo apt-mark hold <package-name>

# Resume upgrades:
sudo apt-mark unhold <package-name>

# See what's held:
apt-mark showhold
```
