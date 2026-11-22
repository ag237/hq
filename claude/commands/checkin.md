---
description: Quiet periodic check; notifies only when something needs {{USER_NAME}}
---
Run the quiet check-in from your instructions.

1. Compare `{{STATE}}/board.tsv` (only `active` rows matter; ignore `parked`/`done`) with `tmux list-windows -t hq` and `ListAgents`.
2. For each active worker, read the last lines of its pane and its latest tracker comment, and classify it:
   - **working**: a spinner/running command, or output changed since last check. Fine.
   - **waiting on {{USER_NAME}}**: sitting at an empty prompt after a handoff, question or checkpoint. Normal for long-running workers. Not stuck; include it in the standup but do NOT push.
   - **blocked**: it said it is blocked, or hit an error it can't resolve.
   - **stuck**: mid-task with no new output for 30+ min and no checkpoint.
   - **gone**: row is active but the window is missing.
3. Push to {{USER_NAME}} with the `PushNotification` tool (one line, lead with the action needed) ONLY for: blocked, stuck, gone, or a PR ready for merge. One push per state change (check today's log to avoid repeats).
4. Run `{{HQ_BIN}}/sync` (commits and pushes hq state to its git origin; silent no-op when clean). Exit 2 means the push failed (diverged history or no network): tell {{USER_NAME}} once per failure with `PushNotification`, don't retry in a loop. Exit 0 needs no mention.
5. Log anything you pushed. If nothing needs attention, output only "ok".
