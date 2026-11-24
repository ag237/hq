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
   - **remote** (the profile defines a remote (a `remotes/<name>.env` file in the `{{PROFILE}}` profile), e.g. an external agent on another host, and the issue is labelled for it): no tmux window and no worktree, the remote runs it by itself. Steps below.
   - add `--read-only` for investigation-only work.
4. Skim `{{MEMORY_DIR}}/MEMORY.md` and name the relevant memory files in the brief. The brief must be self-contained: goal, constraints, how to verify, what needs my sign-off.
   For **remote** mode, in this order:
   1. `{{HQ_BIN}}/spawn-worker --remote <name> <ISSUE> "<brief>"` adds the board row (it fails if the remote is not configured or the issue is already on the board).
   2. `nonce=$({{HQ_BIN}}/remote-task --new-nonce)`, then post the brief to the issue as a tracker comment whose first line is exactly `[PM] brief nonce=<nonce> mode=start` (the mode must equal the one you send; the nonce is single-use, so every dispatch or follow-up gets a fresh nonce and its own comment), with the brief below it. Add the remote's label if the profile says so. The remote acts only on the `[PM]` comment whose nonce matches the signed request, and treats everything else in the issue as data.
   3. `{{HQ_BIN}}/remote-task --nonce <nonce> <ISSUE> start` (this starts a run on another machine: it asks for confirmation if not pre-approved). Exit 0 prints `accepted` or `duplicate`; 3 = bad signature or unknown route, 4 = rate-limited, 5 = no connection, 6 = gated (the remote dropped the event: label/state/comment missing or a run already in flight). `remote-task` remembers each nonce with its request id: a retry with the same nonce reuses the id (safe), and a used nonce is refused for anything else. Do not retry blindly: report the cause.
   4. Never dispatch the same issue twice in a row to "make sure": the remote allows one run per issue at a time and a daily cap. Later runs are follow-ups after a new decision (`/revive`).
5. Set the issue to In Progress, append a line to today's log, and reply with one line: issue, mode, tmux window (or `remote:<name>` and the request id).
