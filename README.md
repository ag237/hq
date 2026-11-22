# hq: a PM agent that runs your Claude Code sessions

One long-running `pm` Claude agent in a tmux session. You talk to it; it starts worker `claude` sessions
(one tmux window each), checks on them quietly, and tracks everything in your issue tracker and a small
board. Workers can be parked and revived, and the whole layout rebuilds from disk after a reboot.

## Requirements
Linux, macOS or WSL with `bash git tmux python3` and the `claude` CLI (`hq doctor` checks). Native Windows needs WSL.

## macOS (zsh)
Your login shell doesn't matter: every `hq` script starts with `#!/usr/bin/env bash`, so zsh just launches them. Notes:
- Install the requirements: `brew install tmux git python3` (macOS already has `uuidgen`; the `claude` CLI per its docs). `hq doctor` shows what's missing.
- macOS's system bash is 3.2. The scripts avoid bash 4 features, so it should work as is (or `brew install bash`).
- `hq init` links `hq` into `~/.local/bin`; for plain `hq` in zsh add it to your PATH: `echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && exec zsh`.
- Clone into a dedicated directory such as `~/work/hq`, not directly in `~`.
- `hq autostart on` writes a launchd agent (`~/Library/LaunchAgents/net.hq.up.plist`).
- macOS has never been run by the author (only Linux/WSL), so expect to report small issues.

## Quick start (any machine)
```
git clone <this repo> ~/work/hq        # any dedicated directory; its PARENT is the working dir (or pass --workdir)
~/work/hq/bin/hq init --name work --team ENG --state-repo ~/work/hq-state --remote <private repo URL>
$EDITOR ~/work/hq-state/profiles/work/pm-profile.md   # fill every CHANGEME (tracker, risky systems, PR flow, repo map)
hq config && hq
```
No access to the git host (e.g. a work machine)? Download an archive of the repo instead, move it over, and `tar xzf hq.tar.gz -C ~/work`.
`hq init` checks requirements, creates a profile from `profiles/_template`, writes `~/.config/hq/env`, links `hq` into
`~/.local/bin`, and renders the config. It refuses to use `$HOME` itself as the working dir (that would overwrite your global `~/.claude`).

### Two repos: the app (public) and your state (private)
- **This repo is the app**: scripts, generic agent/command templates, `profiles/_template`. It contains nothing about you, your employer or your tracker, so it can be public.
- **Your state repo is private and separate** (`--state-repo DIR`, a sibling directory, not a submodule): `profiles/<name>/` (your tracker, repo map, rules) and `state/<hostname>/` (board, briefs, logs). `bin/sync` commits and pushes only that repo, to the origin you gave with `--remote`.
- No `--state-repo`? Profile goes to `~/.config/hq/profiles/` and state to `~/.local/state/hq`, with sync off: nothing is backed up, nothing leaks.
- Use one state repo per environment (for example personal and work), each with its own private origin.

## Use
```
hq                  # build/resume everything, then attach to tmux session `hq`
hq status           # board vs live windows
hq park ISSUE       # close window, keep session (not resumed on rebuild)
hq revive ISSUE     # reopen by EXACT board id, conversation resumed
hq find <term>      # search board, briefs, old transcripts (any session, even pre-hq)
hq adopt <uuid> ISSUE [cwd]   # put an old session on the board as parked
hq config           # re-render the PM agent, commands, settings after editing claude/ or a profile
hq doctor | init | down | autostart on|off|status
```
PM slash commands: `/dispatch /park /revive /standup /review /checkin /eod`.

## Worker kinds
- `spawn-worker --ops ISSUE "<brief>"`: runs in the working dir, no worktree. Sysadmin/IaC/diagnosis.
- Models: `HQ_PM_MODEL` / `HQ_WORKER_MODEL` in `profile.env` (aliases like `opus`/`sonnet` or full IDs; empty = Claude Code default). `spawn-worker --model <m>` overrides one worker and is remembered. Applied on every start/resume; restart the PM (`hq down && hq`) to pick up a change.
- `spawn-worker --plan ...`: plan mode on the `opusplan` model (opus plans, sonnet executes). First start only; later resumes don't re-enter plan mode.
- `spawn-worker <repo> ISSUE "<brief>"`: own worktree at `hq/worktrees/<repo>/<ISSUE>` + branch, ends in a PR.
- `--read-only` on either. Background subagents only for quick read-only lookups.

## Layout
`bin/` scripts · `claude/` generic PM agent, commands, settings (templates with `{{placeholders}}`) ·
`profiles/_template/` start of a profile · `worktrees/` per machine, gitignored.
In your state repo: `profiles/<name>/` and `state/<hostname>/` (board, briefs, logs, `pm.session`, per-worker model pins).

Board (`board.tsv`): `issue repo cwd uuid status updated`; `active` (resumed on rebuild) / `parked` / `done`
(worktree gone, session kept, still revivable); `repo` is `-` for ops workers.

## Local config (`~/.config/hq/env`)
Sets `HQ_PROFILE`, `HQ_WORKDIR`, `HQ_PROFILES_DIR` (where profiles live), `HQ_STATE_DIR`, `HQ_SYNC=on|off`. Profiles are looked up in
`HQ_PROFILES_DIR`, then `~/.config/hq/profiles/`, then this repo's `profiles/`. Employer or personal details stay in your private state repo or on that machine.

## Rebuild after a reboot
Run `hq`. It resumes the PM by `pm.session`, resumes every `active` worker by pinned session id (a fresh re-briefed
session if the transcript is gone), and re-arms `/standup` + `/loop /checkin`. `hq autostart on` does this at login
(systemd user unit on Linux/WSL; launchd on macOS, untested).

## Backup / sync
`bin/sync` commits and pushes the private state repo (the git repo that contains `$HQ_STATE_DIR`) to its origin: never forced,
one pull-rebase retry, exit 2 = needs a human. The PM runs it from `/checkin` and `/eod`. It refuses to run if the state lives
inside this app repo, so personal data can't be committed here by accident. `HQ_SYNC=off` disables it. Authentication is whatever git already uses on that machine.

## Development and security checks
- `tests/lint.sh`: shellcheck, bash 3.2/macOS portability, credential and personal-data scan (tree and history), workflow pinning. Optional machine-local `~/.config/hq/denylist` (one regex per line: your names, hosts, internal domains) is checked too and never committed.
- `tests/run.sh`: end-to-end tests in a sandbox (fake HOME, private tmux server, stub `claude`, local bare remote). Safe to run anywhere.
- `tests/secrets.sh`: secret-disclosure tests: the credential patterns (must-match and must-not-match corpus), proof that secrets in the environment never reach files, process args, tmux, command output or the synced remote, that sync and lint never print a secret they find, and that state and `~/.claude.json` keep owner-only permissions.
- `git config core.hooksPath hooks` enables a pre-push hook that runs all three. CI runs them on Linux and macOS. See `SECURITY.md`.

## Notes
- `<workdir>/.claude/{agents,commands,settings.json}` are generated; edit `claude/` or the profile, then `hq config`. The PM re-reads its own instructions only when restarted.
- Notifications use the `PushNotification` tool (Remote Control); no extra service.
- Testing tmux code: use a private server and clean up by socket: `env -u TMUX HQ_SOCKET=hqtest ...`, `tmux -L hqtest kill-server`. Never `kill-server` on the default socket.
- Details, history and lessons: `PORTING.md`.
