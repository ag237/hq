# Porting hq, and what went wrong building it

## Setting up another machine
See the Quick start in `README.md`: clone, `hq init --state-repo`, fill in the profile, `hq`. Design points:
- The app repo holds only the generic framework. Everything environment-specific lives in a profile inside your **private state repo** (or `~/.config/hq/profiles/`), so nothing employer- or machine-specific is committed to the app repo.
- Scripts avoid GNU-only tools (no `readlink -f`, `flock`, `date -Is`; `timeout` is optional), so macOS works with the system bash 3.2. The macOS launchd autostart and the macOS path as a whole are untested.
- If your tracker isn't Linear, edit the profile's `pm-profile.md` and its `settings.json` (the Linear MCP permission rules live there, not in the framework).
- Open each project repo once in Claude and accept the trust prompt; worktree workers are auto-trusted only if their main repo already is.
- To move an existing install to the split layout: create the state repo, move `profiles/<name>` and `state/<host>` into it, set `HQ_PROFILES_DIR` and `HQ_STATE_DIR` in `~/.config/hq/env`, run `hq config`, then restart the PM (its rendered instructions contain the old paths).

## What went wrong (so it isn't repeated)
- **`tmux kill-server` killed the real server.** A "sandbox" test set `TMUX_TMPDIR`, but `$TMUX` wins, so the command hit the live server. Use `env -u TMUX HQ_SOCKET=<name> ...` (all scripts honour `HQ_SOCKET`) and clean up with `tmux -L <name> kill-server`.
- **Folder-trust prompt stalled new worktree workers.** Trust is per path and not inherited by sibling worktrees. Fixed with `bin/trust-path` (guarded on the main repo being trusted, verified and retried because `~/.claude.json` is shared by every session).
- **Worktree sprawl.** Sibling worktrees (`<repo>-wt-<issue>`) cluttered `~/home`. They now live in `hq/worktrees/<repo>/<ISSUE>` (gitignored).
- **Workers aren't all coding tasks.** Sysadmin/IaC work is long-lived and often repo-less. Added `--ops` workers (no worktree) and `parked`/`done` states that keep the session UUID, so `hq revive` works on old sessions.
- **Adopted sessions keep their old name**, so `SendMessage to <ISSUE>` can't reach them. `hq revive` now resumes with `-n <ISSUE>` (verified: after park + revive the session is addressable by its issue id).
- **Background tasks don't survive a crash/reboot.** A resumed worker has its conversation but not its running processes. Expected; not fixable.
- **`pkill -f <pattern>` matches its own command line** and killed the shell running it. Use `pgrep -f` to check first, or target a pid.
- **`PushNotification` is skipped while the terminal is focused.** Switching to another tmux window and waiting ~90s is enough for it to send (verified).

## Sync with the state repo
`bin/sync` runs `git -C <repo containing $STATE> add -A`, commits, and pushes the current branch to that repo's origin (never forced; one rebase retry, then exit 2). The lock lives in that repo's `.git`, so it is never committed. The app repo is never touched by sync: changes to hq itself are ordinary commits and PRs.
- A state repo needs its own private origin (a self-hosted git server, a work GitHub, ...). Only put work data in a repo your employer allows.
- Updates to the app reach a machine with `git pull` (or a fresh archive extracted over the clone). Profiles and state live elsewhere and are untouched.
