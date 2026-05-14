# Git Configuration Tips

## core.fileMode

Controls whether git treats file permission changes as modifications.

Usually you do not want git to track file permission changes:

```bash
git config core.fileMode false
```

Set globally (all repos on the machine):
```bash
git config --global core.fileMode false
```

**When to use**: Useful on filesystems or in environments where file permissions get altered automatically (Docker bind mounts, NTFS/FAT shares, WSL). Without this, a simple `chmod` shows up as a modified file and pollutes diffs.

---

## Useful one-liners

### Show ignored files

```bash
git status --ignored
```

**When to use**: Diagnosing why a file isn't being tracked — it may be listed in `.gitignore` or a parent directory's `.gitignore`. The `--ignored` flag surfaces those files, which `git status` hides by default. Useful when you added a file and it silently disappeared from `git status`.

Filter to a specific path:
```bash
git status --ignored -- path/to/check/
```
