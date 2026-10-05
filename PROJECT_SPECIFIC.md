# Project-Specific Rules

## Branch and documentation flow

- Use `dev` as the working branch. `main` mirrors its completed HAWS code, tests, and user-facing documentation.
- When a work chunk is complete and checked, push its HAWS code, tests, and user-facing documents/templates to both `origin/dev` and `origin/main` in the same task. A request to finish and push to `dev` includes this `main` sync; do not wait for or request that instruction again. Follow a narrower `dev`-only request if the user explicitly gives one.
- At each completed delivery boundary, the product tree should match across `dev` and `main`; the intended differences are the development-only instruction and continuation files.
- Keep `AGENTS.md`, `PROJECT_SPECIFIC.md`, `HANDOFF.md`, unfinished plans or drafts, and task-specific progress notes on `dev` only. Do not merge, cherry-pick, or otherwise carry these development documents into `main`.
- Keep README and other finalized user-facing HAWS documents and templates on both branches when changed.
- Keep personal or device-local Second Brain content in its ignored/private location. Do not stage it for either branch.
- At the end of a substantial `dev` task, update `HANDOFF.md` with the root cause or decision, changed files, executed checks and results, commit/push state, and exact resume point.

This standing instruction means completed work delivered to `dev` is also delivered to `main`, without a repeated request.
