# Git Commit Signing (GPG)

[Why sign your commits?](https://withblue.ink/2020/05/17/how-and-why-to-sign-git-commits.html)

Signing proves that a commit was made by the person who controls the private key — not just someone who knows the git username and email (which anyone can set to anything). GitHub and GitLab show a "Verified" badge on signed commits.

## Setup

```bash
sudo apt install -y gnupg2
gpg2 --full-generate-key
```

During key generation, choose:
- `9 - ECC (sign and encrypt)` (default)
- `1 - Curve 25519` (default)
- `0 = key does not expire` (default)
- Your name (must match `git config user.name`)
- Your email (must match `git config user.email`)
- Optional comment to distinguish keys
- Set a passphrase — protects the key if your machine is compromised

## Get your key ID

```bash
gpg2 --list-secret-keys --keyid-format LONG
```

Output example:
```
sec   ed25519/1A62BECDE903888 2020-12-07 [SC]
uid   [ultimate] FirstName LastName (Comment) email@example.com
```

Copy the ID after the `/` (e.g., `1A62BECDE903888`).

## Configure git to use the key

```bash
git config gpg.program /usr/bin/gpg2
git config user.signingKey 1A62BECDE903888
git config commit.gpgSign true
```

Or edit `.git/config` directly:
```ini
[gpg]
    program = /usr/bin/gpg2
[user]
    signingKey = 1A62BECDE903888
[commit]
    gpgSign = true
```

## Per-repo signing (repo-level override)

To sign commits only in specific repos (rather than globally):

```bash
# Inside the repo:
git config commit.gpgSign true
git config user.signingKey 1A62BECDE903888

# Globally disabled, repo-level enabled:
git config --global commit.gpgSign false
git config commit.gpgSign true   # run inside the repo
```

This is useful when you have personal vs. work identities with different keys.

## Add public key to your git provider

```bash
gpg2 --armor --export 1A62BECDE903888
# Copy the output → GitLab/GitHub Settings → GPG Keys
```

## Verify a signed commit

```bash
git verify-commit HEAD
# Or for any commit:
git verify-commit <commit-hash>
# Or see all verified commits in log:
git log --show-signature -5
```

## Upload public key to keyserver (optional)

```bash
gpg --send-keys 1A62BECDE903888
```

## Debugging

```bash
# Test that gpg can sign:
echo "test" | gpg2 --clearsign

# If it hangs (waiting for passphrase with no prompt):
# Add to ~/.gnupg/gpg.conf:
use-agent
pinentry-mode loopback

# Add to ~/.gnupg/gpg-agent.conf:
allow-loopback-pinentry
```

## Gotcha: signing fails silently if gpg-agent isn't running

If `git commit` produces no error but the commit is unsigned, the GPG agent may not be running:

```bash
gpg-agent --daemon
# or:
gpgconf --launch gpg-agent
```

Add this to your shell profile (`~/.bashrc` or `~/.zshrc`) so the agent starts automatically:
```bash
export GPG_TTY=$(tty)
```
