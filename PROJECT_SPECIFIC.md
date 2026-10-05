# Project-Specific Rules

## Branch and documentation flow

- Use `dev` as the working branch and keep `main` synchronized with completed, verified code and shared documentation.
- A request to push a completed work chunk to `dev` also directs Codex to sync that chunk to `main` in the same task. Do not wait for or request a repeated instruction to update `main`. If the user explicitly says a chunk is `dev`-only, follow that narrower direction.
- At each completed delivery boundary, push the corresponding changes to both `origin/dev` and `origin/main`. The shared source and documentation trees should match across branches.
- `AGENTS.md` and `PROJECT_SPECIFIC.md` are shared workflow instructions and must be present and updated on both branches. Product code and finalized shared documents also belong on both.
- Keep only continuation material on `dev`: `HANDOFF.md`, unfinished plans or drafts, and task-specific progress notes. Never carry those continuation documents into `main`.
- Keep personal or device-local Second Brain content in its ignored/private location. Do not stage it for either branch.
- At the end of a substantial `dev` task, update `HANDOFF.md` with the root cause or decision, changed files, executed checks and results, commit/push state, and exact resume point.

When the completed work is ready to push to `dev`, synchronize the shared deliverable to `main` in the same task under this standing instruction.
