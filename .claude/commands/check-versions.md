Run the automated version checker in preview mode to find outdated dependencies.

Execute: `bin/env-update.sh --dry-run --progress $ARGUMENTS`

## After the run:
1. Summarize results by decision type: [AUTO], [MANUAL], [HOLD], [SKIP], [UBUNTU]
2. For [MANUAL] entries: explain why human review is needed
3. For [HOLD] entries: explain the pre-release vs stable situation
4. Recommend which [AUTO] updates are safe to apply together
5. Flag any entries where a major version bump is involved

If no arguments provided, check all entries. Common filters:
- `--filter=NODE` — only Node-related versions
- `--type=github` — only GitHub-sourced versions
- `--type=dockerhub` — only Docker Hub images
