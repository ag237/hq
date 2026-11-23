# Contributing

This repository is a **read-only mirror**. The maintainer's Git server is the source of truth and pushes here on every commit, so anything merged on GitHub would be overwritten or break that sync.

- **Bugs and ideas:** open a GitHub issue. For security problems use private vulnerability reporting instead (see `SECURITY.md`).
- **Patches:** open a pull request anyway if you like. It will be reviewed here, and if accepted the change is applied on the source repo and arrives here as a normal commit (the PR is then closed, with credit in the commit message).
- **Before sending a change:** `tests/lint.sh`, `tests/run.sh`, `tests/secrets.sh` and `tests/policy.sh` must pass. `git config core.hooksPath hooks` runs them before every push.
- **Rules of the road:** bash 3.2 compatible (macOS), no GNU-only tools, no personal or environment data, no new permissions in the generated `settings.json` without a reason. The tests enforce most of this.
