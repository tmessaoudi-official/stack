# APT Weak Key Signature Warning

## What this warning means

When running `apt-get update`, you may see:

```
W: An error occurred during the signature verification. The repository is not updated
   and the previous index files will be used. GPG error: ... EXPKEYSIG
```

or a warning about "weak digest algorithm" or "weak public key algorithm".

This appears when a repository's signing key uses an algorithm that modern GnuPG considers too weak — typically short RSA keys (< 2048 bits) or SHA-1 signatures. Older PPAs, unmaintained third-party repos, and corporate internal repositories are common sources.

## The security implication

Suppressing this warning means you're accepting packages signed with a cryptographically weak key. An attacker with sufficient resources could theoretically forge packages signed with a weak key. **Do not suppress this warning on production systems** — instead, find a repository with properly signed packages, or contact the maintainer.

## The suppression config (dev/testing only)

```bash
sudo nano /etc/apt/apt.conf.d/99weakkey-warning
```

Add:
```
APT::Key::Assert-Pubkey-Algo "";
```

This tells APT to accept any key algorithm without asserting minimum strength. Empty string = no assertion = warning suppressed.

**Apply it only when**:
- You understand the source and trust it despite the weak key
- The repo is on a closed network (no attack surface)
- You're in a development/testing environment where security guarantees don't matter

## Better alternatives

1. **Check if a newer repo URL exists** — many repos with old keys have migrated to new infrastructure with stronger keys
2. **Import the key manually and pin it**: use the newer `.sources` format with `Signed-By` pointing to a specific keyring file
3. **Mirror the packages internally** and re-sign with your own key
