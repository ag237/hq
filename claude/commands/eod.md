---
description: End-of-day wrap-up: log, board and memory
---
Wrap up the day.

1. Append a summary to today's `{{STATE}}/logs/YYYY-MM-DD.md`: done, in flight, blocked, decided.
2. Make sure `{{STATE}}/board.tsv` and the tracker agree. Reap any worker whose PR I've confirmed merged (`{{HQ_BIN}}/reap-worker`).
3. Save any durable lessons (not task status) as memory files per the memory instructions.
4. Run `{{HQ_BIN}}/sync` so the day's log and board are saved to the hq repo's origin.
5. Reply with a 3-line summary and what's first tomorrow, and say if the sync failed.
