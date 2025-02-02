There are a lot of git configs (in .git/config) that are awesome,

We will try to talk about few of them in here

```
core.fileMode
```

It will determine if git will treat file access mod as changes or not

Usually you do not want git to track file mods !!

```
git config core.fileMode false
```