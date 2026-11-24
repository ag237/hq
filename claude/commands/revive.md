---
description: Reopen a parked/finished worker, or find an old session by keyword
argument-hint: <ISSUE | search term>
---
Revive: $ARGUMENTS.

1. If it looks like an exact board issue id (`{{ISSUE_EXAMPLE}}`), run `{{HQ_BIN}}/hq revive <ID>`. Report whether the conversation was resumed or re-briefed.
2. If it's exact but not on the board, or it's anything else (keyword, hostname, partial title), run `{{HQ_BIN}}/hq find <term>`. Show me the candidates (id/uuid, last active, one-line summary) and let me pick. Never guess when more than one matches.
3. For a transcript hit that isn't on the board, after I pick it: `hq adopt <uuid> <ISSUE>` (ask me which issue id to use; default to a tracker id if the transcript mentions one), then `hq revive <ISSUE>`.
   **Remote rows** (repo `@<name>`) are not resumed: reviving sends a follow-up request. Generate `nonce=$({{HQ_BIN}}/remote-task --new-nonce)`, post a tracker comment whose first line is `[PM] brief nonce=<nonce> mode=followup` (the new instruction below), then `{{HQ_BIN}}/hq revive <ISSUE> --nonce <nonce>` (without `--nonce` it sends nothing). Don't revive while `remote-status` says `working`.
4. Set the tracker issue back to In Progress if it was Done/Backlog and I'm resuming real work. Log it.
