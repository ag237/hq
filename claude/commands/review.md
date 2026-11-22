---
description: Review a worker's finished diff/PR
argument-hint: <ISSUE>
---
Review the work for $ARGUMENTS.

1. Get the worktree/branch from `{{STATE}}/board.tsv`. Read `git -C <worktree> diff origin/HEAD...HEAD` and the PR description, and the worker's tracker comment.
2. Check against the issue's goal and the worker rules (scope, no secrets, nothing outside the worktree, verification actually done).
3. Verdict: approve (tell me it's ready to merge, with the PR link), request changes (SendMessage the worker with specifics), or escalate (what decision I need to make).
4. Log the verdict. Do not merge.
