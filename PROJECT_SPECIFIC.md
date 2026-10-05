# Project-Specific Rules

## Branch and documentation flow

- Use `dev` as the working branch. `main` is the user branch and contains HAWS runtime files, skills, templates, and finalized user-facing documentation.
- Keep automated tests, test fixtures, `AGENTS.md`, `PROJECT_SPECIFIC.md`, `HANDOFF.md`, unfinished plans or drafts, and task-specific progress notes on `dev` only. Do not merge, cherry-pick, or otherwise carry these development-only files into `main`.
- When a work chunk is complete and checked, push its user-facing HAWS code and finalized documents/templates to both `origin/dev` and `origin/main` in the same task. Keep tests and development-only files on `dev`. A request to finish and push to `dev` includes this user-facing `main` sync; do not wait for or request that instruction again. Follow a narrower `dev`-only request if the user explicitly gives one.
- At each completed delivery boundary, user-facing product files should match across `dev` and `main`; `dev` additionally carries the test suite and development-only instructions and continuation files.
- Keep README and other finalized user-facing HAWS documents and templates on both branches when changed.
- Keep personal or device-local Second Brain content in its ignored/private location. Do not stage it for either branch.
- At the end of a substantial `dev` task, update `HANDOFF.md` with the root cause or decision, changed files, executed checks and results, commit/push state, and exact resume point.

This standing instruction means completed user-facing work delivered to `dev` is also delivered to `main`, without a repeated request; development-only files remain on `dev`.
