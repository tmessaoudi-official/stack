# Online Linters

**What they solve**: Validating a config file or snippet without installing a linter locally. Faster than setting up a tool for a one-off check, and useful when working on a machine where you can't install packages.

**When online beats CLI**:
- Validating a YAML or JSON file from a system where you only have a browser
- Quickly checking someone else's config snippet without pulling their repo
- Debugging a format error when you're not sure if the issue is the file or your local tool version

**The non-obvious part**: Online linters process your data on a third-party server. Don't paste secrets, credentials, API keys, or any production config with sensitive values.

---

**YAML linter**: http://www.yamllint.com/

**JSON formatter + validator**: https://jsonformatter.curiousconcept.com/

---

For local linting in scripts and CI, prefer the CLI equivalents which can be pinned to a version and run offline:

```bash
yamllint file.yaml           # pip install yamllint
jq . file.json > /dev/null   # validates JSON, exits 1 on error (jq is usually pre-installed)
```
