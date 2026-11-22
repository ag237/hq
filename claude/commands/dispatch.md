---
description: Start a worker session for a tracker issue
argument-hint: <ISSUE> [repo]
---
Dispatch a worker for $ARGUMENTS.

1. Read the tracker issue and its comments.
2. Check `{{STATE}}/board.tsv`: if the issue is already on the board, don't spawn. Say where it stands (`active` -> point to its window; `parked`/`done` -> offer `/revive`).
3. Pick the mode and say why in a few words:
   - **ops** (default for sysadmin/cluster/host/diagnosis work, or anything not clearly a repo change): `spawn-worker --ops <ISSUE> "<brief>"`.
   - **worktree** (the work is a change to one repo that will become a PR): `spawn-worker <repo> <ISSUE> "<brief>"`.
   - add `--read-only` for investigation-only work.
4. Skim `{{MEMORY_DIR}}/MEMORY.md` and name the relevant memory files in the brief. The brief must be self-contained: goal, constraints, how to verify, what needs my sign-off.
5. Set the issue to In Progress, append a line to today's log, and reply with one line: issue, mode, tmux window.
