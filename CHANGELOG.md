# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions are not yet tagged.

## [Unreleased]

## [0.1.0] - 2026-11-22

First public snapshot.

### Added
- `hq` launcher: `up` (default), `init`, `doctor`, `config`, `status`, `down`, `park`, `revive`, `find`, `adopt`, `autostart on|off|status`.
- Long-running `pm` agent and slash commands `/dispatch /park /revive /standup /review /checkin /eod`.
- Workers as independent `claude` sessions in tmux windows with pinned session ids: ops workers (no worktree) and worktree workers (own branch, ends in a PR), `--read-only`.
- Rebuild after reboot: the PM and every `active` worker are resumed from the board; `park`/`revive`/`done` keep session ids so old sessions can be brought back; `hq find` and `hq adopt` pull in sessions that predate hq.
- Models: `HQ_PM_MODEL` / `HQ_WORKER_MODEL` in the profile, `spawn-worker --model` (remembered per worker), `spawn-worker --plan` (plan mode on `opusplan`).
- Profiles (`profiles/_template`) with `{{placeholders}}`, including `{{USER_NAME}}`; `hq init` creates one locally.
- Separate private state repo (`hq init --state-repo DIR --remote URL`) and `bin/sync`, which commits and pushes only that repo and never forces.
- Folder-trust handling for new worktrees (`bin/trust-path`), systemd user unit and launchd agent for autostart.
- Quiet check-ins via the `PushNotification` tool.
- Tests: `tests/lint.sh`, `tests/run.sh` (sandboxed end-to-end), `tests/secrets.sh` (secret disclosure), `tests/policy.sh` (allowlist and input fuzzing); CI on Linux and macOS with gitleaks, actionlint and zizmor.
- `SECURITY.md`, `CONTRIBUTING.md`, MIT license, Dependabot for workflow actions, pre-push hook.

### Security
- Issue ids, repo names and session ids are validated and shell-quoted before reaching paths, branch names or tmux commands.
- Template values are escaped when rendered; `bin/sync` refuses to commit credential-shaped changes; lint output never prints a matched secret.
- State directory is owner-only (`700`); the generated permission allowlist is small and read-only (`git branch` limited to `--list` and `--show-current`), enforced by tests.

### Fixed
- Scripts run on bash 3.2 and BSD tools (no `readlink -f`, `flock`, `date -Is`; portable locking).
