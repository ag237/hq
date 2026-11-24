---
description: Quiet periodic check; notifies only when something needs {{USER_NAME}}
---
Run the quiet check-in from your instructions.

1. Compare `{{STATE}}/board.tsv` (only `active` rows matter; ignore `parked`/`done`) with `tmux list-windows -t hq` and `ListAgents`.
2. For each active worker, read the last lines of its pane and its latest tracker comment, and classify it:
   - **working**: a spinner/running command, or output changed since last check. Fine.
   - **waiting on {{USER_NAME}}**: sitting at an empty prompt after a handoff, question or checkpoint, or at a plan-approval or permission prompt. Normal for long-running workers. Not stuck; include it in the standup. Do NOT push unless it has waited over 60 minutes (see step 4). A worker idle after a DONE that is already reported (tracker comment, DONE message or PR ready) is not waiting: never push for it.
   - **blocked**: it said it is blocked, or hit an error it can't resolve.
   - **stuck**: mid-task with no new output for 30+ min and no checkpoint.
   - **gone**: row is active but the window is missing.
3. Push to {{USER_NAME}} with the `PushNotification` tool (one line, lead with the action needed) ONLY for: blocked, stuck, gone, or a PR ready for merge. One push per state change (check today's log to avoid repeats).
4. **Long wait.** If an active worker has been waiting on {{USER_NAME}} for more than 60 minutes (plan approval, permission prompt, or an unanswered question after a handoff), send ONE `PushNotification` for that wait, leading with the action: `<ISSUE>: plan waiting for your approval since 13:00 (hq:<ISSUE>)` (or `permission prompt` / `question`). Judge the start of the wait from the pane, the tracker comment time or the worker's last output. One push per wait: grep today's log for `long-wait <ISSUE>` first and skip if present; when you push, log `long-wait <ISSUE> since <HH:MM>`. A new wait (the worker moved on, then stopped again) is a new push.
5. Run `{{HQ_BIN}}/sync` (commits and pushes hq state to its git origin; silent no-op when clean). Exit 2 means the push failed (diverged history or no network): tell {{USER_NAME}} once per failure with `PushNotification`, don't retry in a loop. Exit 0 needs no mention.
6. Log anything you pushed.
7. **Heartbeat, always last.** Overwrite (never append) the single line `{{STATE}}/heartbeat`, e.g. `printf '%s checkin ok · active %s · sync %s\n' "$(date +%Y-%m-%dT%H:%M)" N "<sync result>" > {{STATE}}/heartbeat`. Result is `ok`, or `attention` if you pushed or anything is blocked/stuck/gone; N is the number of active rows; sync result is `up-to-date`, `pushed`, `rebased and pushed`, `failed` or `off`. `bin/sync` git-ignores this file locally, so it never causes a commit; `hq status` shows it with its age. Do this even when nothing else happened.

If nothing needs attention, output only "ok".
