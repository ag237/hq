---
description: Close a worker's window but keep its session for later
argument-hint: <ISSUE>
---
Park the worker for $ARGUMENTS.

1. Look at its pane (`tmux capture-pane -p -t hq:<ISSUE> -S -30`). If it is mid-task (running command or working), tell me and ask before parking.
2. Make sure its latest state is in the tracker issue (ask the worker via SendMessage to checkpoint if not).
3. `{{HQ_BIN}}/hq park <ISSUE>`, log it, and reply in one line. A parked worker is not resumed on rebuild; `/revive <ISSUE>` brings it back.
