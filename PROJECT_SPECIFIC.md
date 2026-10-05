# Project-Specific Rules

## Branch and documentation flow

- Use `dev` for ongoing HAWS implementation, investigation, drafts, and continuation work. Treat `main` as the ready-to-use public baseline.
- When the user authorizes a push without naming a destination branch, push to `origin/dev`. Do not promote to or push `main` unless the user explicitly requests that destination.
- Keep `AGENTS.md`, `PROJECT_SPECIFIC.md`, `HANDOFF.md`, unfinished plans, work-in-progress documents, and development notes on `dev`. Do not merge, cherry-pick, or otherwise carry these continuation documents into `main`.
- Promote only verified, human-approved code and finalized shared documentation needed by the ready-to-use baseline. Select those files deliberately; keep development notes on `dev`.
- Keep personal or device-local Second Brain content in its ignored/private location. Do not stage it for either branch.
- At the end of a substantial `dev` task, update `HANDOFF.md` with the root cause or decision, changed files, executed checks and results, commit/push state, and exact resume point.

Automated test results are evidence for review; they do not count as human acceptance or authorize promotion to `main`.