---
description: Full status of all workers, the board and open tracker work
---
Rebuild the full picture and brief me.

1. Read `{{STATE}}/board.tsv`, today's and yesterday's `{{STATE}}/logs/`, and `tmux list-windows -t hq`.
2. For each active worker: `ListAgents` presence, the last ~40 lines of `tmux capture-pane -p -t hq:<ISSUE> -S -40`, and its tracker status/latest comment.
3. List my in-progress {{TEAM}} issues that have no worker, and any assigned to me in Todo with high priority.
4. Flag mismatches: board row with no window, window with no row, worktree with no branch, tracker status that disagrees with reality. Fix board mismatches you are sure about.
5. Reply in the brief format from your instructions, then one short line per worker.
