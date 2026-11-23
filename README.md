# hq

[![ci](https://github.com/ag237/hq/actions/workflows/ci.yml/badge.svg)](https://github.com/ag237/hq/actions/workflows/ci.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**A project-manager agent for your Claude Code sessions.**

Running several `claude` sessions at once gets hard to track. `hq` puts one long-running `pm` agent in front of them:
you talk to the PM, it starts worker sessions (one tmux window each), checks on them quietly, keeps your issue tracker
current, and pings you only when something needs you. Workers can be parked and revived later, and the whole layout
rebuilds from disk after a reboot.

- **One conversation, many workers.** Ask the PM to work on an issue; it writes the brief and spawns the worker.
- **Built for long-running work.** Workers are ordinary interactive sessions you can attach to, park and revive, not one-shot jobs.
- **Rebuildable.** State lives on disk and in your tracker, so `hq` after a reboot resumes the PM and every active worker.
- **Private by construction.** The app repo holds no personal data; your profile and state live in a separate private repo.

## How it works

```
 you ──► tmux session "hq"
          ├─ window pm        claude --agent pm      reads the tracker, dispatches, reviews, briefs you
          ├─ window ISSUE-1   claude (ops worker)    runs in your working dir, no worktree
          ├─ window ISSUE-2   claude (worktree)      own git worktree + branch, ends in a PR
          └─ ...
 board.tsv   issue  repo  cwd  uuid  status  updated     (what the PM and `hq up` rebuild from)
 state repo  profiles/<name>/  state/<host>/            (private; pushed by bin/sync)
```

The PM never edits your repos. It delegates, tracks status in the issue tracker, and never merges: you merge.
Workers message the PM when done or blocked (`SendMessage`), and the PM answers or escalates to you.

## Requirements
Linux, macOS or WSL with `bash`, `git`, `tmux`, `python3` and the [`claude` CLI](https://docs.claude.com/en/docs/claude-code). `hq doctor` checks. Native Windows needs WSL.

## Quick start
```
git clone https://github.com/ag237/hq ~/work/hq     # any dedicated directory; its PARENT is the working dir (or pass --workdir)
~/work/hq/bin/hq init --name work --team ENG --state-repo ~/work/hq-state --remote <private repo URL>
$EDITOR ~/work/hq-state/profiles/work/pm-profile.md  # fill every CHANGEME: tracker, risky systems, PR flow, repo map
hq config && hq
```
Then tell the PM what to work on: "Work on ENG-123".

`hq init` checks requirements, creates a profile from `profiles/_template` (it asks how the PM should address you and for an
example issue id when run in a terminal and the flags `--user-name` / `--issue-example` are missing; without a terminal it uses
defaults), writes `~/.config/hq/env`, links `hq` into
`~/.local/bin`, and renders the config into `<workdir>/.claude/`. It refuses to use `$HOME` itself as the working
directory, because that would overwrite your global `~/.claude`. No access to the git host (for example a locked-down
work machine)? Download an archive of the repo (the GitHub "Download ZIP" or a `git archive` tarball), move it over and extract it instead of cloning.

## Daily use
```
hq                  build or resume everything, then attach to tmux session `hq`
hq status           board next to live tmux windows
hq park ISSUE       close the window, keep the session (not resumed on rebuild)
hq revive ISSUE     reopen by EXACT board id, conversation resumed
hq find <term>      search board, briefs and old transcripts (any session, even ones from before hq)
hq adopt <uuid> ISSUE [cwd]   put an existing session on the board as parked (warns if it later moved to another directory)
hq config           re-render the PM agent, commands and settings after editing claude/ or a profile
hq doctor | init | down | autostart on|off|status|show
```
PM slash commands: `/dispatch /park /revive /standup /review /checkin /eod`. The PM runs `/checkin` on a loop and
pushes a phone notification (the `PushNotification` tool) only for blocked, stuck or gone workers and PRs ready to merge.

To restart the PM after changing its instructions: detach (`ctrl+b d`, or your tmux prefix), `hq down`, then `hq`.

## Workers
- `spawn-worker --ops ISSUE "<brief>"`: runs in the working dir, no worktree. For sysadmin, IaC and diagnosis.
- `spawn-worker <repo> ISSUE "<brief>"`: own worktree at `hq/worktrees/<repo>/<ISSUE>` on a branch named after the issue, ends in a PR.
- `--read-only` on either: investigation only. `--plan`: start in plan mode on the `opusplan` model (opus plans, sonnet executes); first start only, so a resumed worker doesn't re-enter plan mode.
- **Models:** `HQ_PM_MODEL` / `HQ_WORKER_MODEL` in `profile.env` (aliases like `opus`/`sonnet` or full IDs; empty = Claude Code's default). `spawn-worker --model <m>` pins one worker and is remembered across restarts. Restart the PM to pick up a change.
- **Board states:** `active` (resumed on rebuild), `parked` (window closed, session kept), `done` (worktree removed, session kept, still revivable).
- Background subagents are used only for quick read-only lookups; they die with the PM.

## Profiles, and the two repos
A **profile** is what differs between environments: the tracker and team key, your repo map, which systems are risky,
the PR flow, extra worker rules, and the extra permissions the PM gets (such as tracker MCP tools). It lives in
`profiles/<name>/` (`profile.env`, `pm-profile.md`, `worker-extra.md`, `settings.json`); start from `profiles/_template`.

- **This repo is the app**: scripts, generic agent and command templates, and the profile template. It contains nothing about you, your employer or your tracker.
- **Your state repo is private and separate** (`--state-repo DIR`, a sibling directory, not a submodule): `profiles/<name>/` and `state/<hostname>/` (board, briefs, logs, session ids, per-worker model pins). `bin/sync` commits and pushes only that repo, to the origin you gave with `--remote`.
- Without `--state-repo`, the profile goes to `~/.config/hq/profiles/` and state to `~/.local/state/hq`, with sync off: nothing is backed up and nothing leaves the machine.
- Use one state repo per environment (for example personal and work), each with its own private origin. Only put work data in a repo your employer allows.

Local config is `~/.config/hq/env`: `HQ_PROFILE`, `HQ_WORKDIR`, `HQ_PROFILES_DIR`, `HQ_STATE_DIR`, `HQ_SYNC=on|off`. Profiles are looked up in
`HQ_PROFILES_DIR`, then `~/.config/hq/profiles/`, then this repo's `profiles/`.

## After a reboot
Run `hq`. It resumes the PM by its pinned session id, resumes every `active` worker (a fresh, re-briefed session if the
transcript is gone), and re-arms `/standup` and `/loop /checkin`. `hq autostart on` does this at login: a systemd user
unit on Linux/WSL, a launchd agent on macOS. Background processes a worker was running do not survive a reboot; its conversation does.

## Backup and sync
`bin/sync` commits and pushes the state repo (never forced; one pull-rebase retry; exit 2 means a human is needed). The PM
runs it from `/checkin` and `/eod`. It refuses to run if the state lives inside this app repo, refuses to commit anything
that looks like a credential, and `HQ_SYNC=off` disables it. Authentication is whatever git already uses on that machine.
`hq init --remote` and `hq doctor` (when `HQ_SYNC=on`) check that git can push to the origin without a prompt, using `git ls-remote`
and a `git push --dry-run` of a throwaway commit, so nothing is ever pushed to test it. If that fails, fix git's credentials first:
`gh auth setup-git` for GitHub over HTTPS, a credential helper for other HTTPS hosts, or an ssh key that is usable without a
passphrase prompt (loaded in `ssh-agent`).

## macOS (zsh)
Your login shell doesn't matter: every script starts with `#!/usr/bin/env bash`, so zsh just launches them.
- `brew install tmux git python3` (macOS already has `uuidgen`). `hq doctor` shows what's missing.
- The scripts avoid bash 4 features and GNU-only tools; CI runs the full test suite on macOS with its stock bash 3.2.
- Add `~/.local/bin` to your PATH for plain `hq`: `echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc && exec zsh`.
- Clone into a dedicated directory such as `~/work/hq`, not into `~`.
- `hq autostart on` writes a launchd agent (`~/Library/LaunchAgents/net.hq.up.plist`). launchd starts agents with a minimal
  environment, so the agent sets a fixed `PATH` (`~/.local/bin`, `/opt/homebrew/bin`, `/usr/local/bin`, the system dirs) instead
  of copying yours. If `tmux`, `git`, `python3` or `claude` live elsewhere, `autostart on` says so and prints the line to add to
  `~/.config/hq/env` (for example `PATH="$PATH:/some/dir"`; hq sources that file on every start). Output of a start at login goes to
  `~/Library/Logs/hq/autostart.log`. `hq autostart show` prints the agent without installing it. The generated plist is checked
  with Python's `plistlib` in the tests, but loading it with `launchctl` is not yet tested on a real Mac.

## Security and development
hq starts agents that can run commands, so read [SECURITY.md](SECURITY.md) for what it does and does not protect.
- `tests/lint.sh`: shellcheck (and gitleaks if installed), bash 3.2/macOS portability, credential and personal-data scan of the tree and history, workflow pinning. An optional machine-local `~/.config/hq/denylist` (one regex per line: your names, hosts, internal domains) is checked too and never committed.
- `tests/run.sh`: end-to-end tests in a sandbox (fake HOME, private tmux server, stub `claude`, local bare remote). Safe to run anywhere.
- `tests/secrets.sh`: secret-disclosure tests: the credential patterns, proof that environment secrets never reach files, process args, tmux, output or the synced remote, and that sync and lint never print a secret they find.
- `tests/policy.sh`: the permission allowlist stays small and read-only, input validators reject hostile input (fuzzed, per locale), LF line endings.
- `git config core.hooksPath hooks` runs all four before every push. CI runs them on Linux and macOS, plus gitleaks, actionlint and zizmor.
- Contributing: [CONTRIBUTING.md](CONTRIBUTING.md). History: [CHANGELOG.md](CHANGELOG.md). Design notes and lessons learned: [PORTING.md](PORTING.md).

## Layout
`bin/` scripts · `claude/` generic PM agent, commands and settings (templates with `{{placeholders}}`) ·
`profiles/_template/` start of a profile · `systemd/` autostart unit · `tests/` · `worktrees/` per machine, gitignored.

`<workdir>/.claude/{agents,commands,settings.json}` are generated: edit `claude/` or your profile, then `hq config`. The PM re-reads its instructions only when restarted.

## Testing tmux code
Use a private server and clean up by socket: `env -u TMUX HQ_SOCKET=hqtest ...`, then `tmux -L hqtest kill-server`. Never `kill-server` on the default socket.

## License
[MIT](LICENSE)
