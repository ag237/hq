# Security

hq starts AI agent sessions that can run commands, so treat it like any tool with shell access.

## Reporting a vulnerability
Please use GitHub's private vulnerability reporting for this repository (Security tab, "Report a vulnerability"), not a public issue.

## What hq does and does not protect
- Issue ids, repo names and session ids are validated (letters, digits, `.`, `_`, `-`) before they reach file paths, branch names or tmux command strings, because they can originate from tracker text.
- Briefs are written to files and never interpolated into shell commands.
- `bin/sync` refuses to commit changes that look like credentials, and never force-pushes.
- Workers run with whatever permissions your Claude Code settings grant. The generated `settings.json` allowlists only read-only inspection plus the hq scripts; anything else prompts. hq does not sandbox workers.
- Profiles are shell-sourced (`profile.env`): only use profiles you wrote or reviewed.
- The state directory is created owner-only (700). Secrets in your environment are not copied into briefs, logs, generated config, tmux commands or the synced repo, and `tests/secrets.sh` checks that. Lint and sync never print a secret they detect.
- Keep your state repo private. Briefs and logs can contain issue text and environment details.

## Checks that run on every push
`tests/lint.sh` (shellcheck, portability, secret and personal-data scan of the tree and its history, workflow hardening) and `tests/run.sh` (end-to-end tests in a sandbox) and `tests/secrets.sh` (secret-disclosure tests), the last two on Linux and macOS.
