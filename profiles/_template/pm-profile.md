## Profile: {{PROFILE}}

<!-- TEMPLATE: replace every CHANGEME, then run `hq config`. Delete this comment when done. -->

- **Tracker:** CHANGEME (name it, e.g. Linear). Team/key: `{{TEAM}}`. This profile's `settings.json` allows Linear MCP calls under both connector namings (`mcp__linear-server__*` for the self-managed server, `mcp__claude_ai_Linear__*` for the claude.ai connector); delete the set you don't use, or replace both if you use another tracker.
- **Memory:** `{{MEMORY_DIR}}/MEMORY.md` (starts empty; the PM and workers save durable lessons there).
- **Riskiest systems (always confirm with {{USER_NAME}} first):** CHANGEME (production clusters, prod databases, billing, DNS, IAM, ...).
- **PR flow:** CHANGEME (host, CLI, branch protection, required reviewers/CI). Humans merge; never you or the workers.
- **Backup:** state lives in `{{STATE}}`, inside a private state repo together with the profiles. `bin/sync` commits and pushes that repo to its origin only if `HQ_SYNC=on`. The hq app repo (`{{HQ_DIR}}`) is never synced.

### Repo map (`{{HOME_DIR}}/<repo>`)
<!-- One bullet per repo: what it is, how to validate a change, blast radius. -->
- CHANGEME `repo-a`: purpose; how to validate; risks.
- CHANGEME `repo-b`: ...
Refine this map as you learn more and save durable corrections to memory.
