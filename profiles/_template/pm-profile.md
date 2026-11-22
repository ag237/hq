## Profile: {{PROFILE}}

<!-- TEMPLATE: replace every CHANGEME, then run `hq config`. Delete this comment when done. -->

- **Tracker:** CHANGEME (name it, e.g. Linear). Team/key: `{{TEAM}}`. This profile's `settings.json` allows Linear MCP calls by default; replace them if you use another tracker.
- **Memory:** `{{MEMORY_DIR}}/MEMORY.md` (starts empty; the PM and workers save durable lessons there).
- **Riskiest systems (always confirm with {{USER_NAME}} first):** CHANGEME (production clusters, prod databases, billing, DNS, IAM, ...).
- **PR flow:** CHANGEME (host, CLI, branch protection, required reviewers/CI). Humans merge; never you or the workers.
- **Backup:** `{{HQ_DIR}}` is a git repo; `bin/sync` pushes it to its origin only if `HQ_SYNC=on`. State lives in `{{STATE}}`.

### Repo map (`{{HOME_DIR}}/<repo>`)
<!-- One bullet per repo: what it is, how to validate a change, blast radius. -->
- CHANGEME `repo-a`: purpose; how to validate; risks.
- CHANGEME `repo-b`: ...
Refine this map as you learn more and save durable corrections to memory.
