# Project-Specific Rules

## Branch and documentation flow

- Use `dev` as the working branch. `main` is the user branch and contains HAWS runtime files, skills, templates, and finalized user-facing documentation.
- Keep all HAWS-maintained automated tests and test fixtures on `dev` only, regardless of location. This includes files under `tests/`, `test/`, `__tests__/`, and files named `*.test.*` or `*.spec.*` next to product code.
- Keep `AGENTS.md`, `PROJECT_SPECIFIC.md`, `HANDOFF.md`, unfinished plans or drafts, and task-specific progress notes on `dev` only. Do not merge, cherry-pick, or otherwise carry these development-only files into `main`.
- When a work chunk is complete and checked, push its user-facing HAWS code and finalized documents/templates to both `origin/dev` and `origin/main` in the same task. Keep tests and development-only files on `dev`. A request to finish and push to `dev` includes this user-facing `main` sync; do not wait for or request that instruction again. Follow a narrower `dev`-only request if the user explicitly gives one.
- At each completed delivery boundary, user-facing product files should match across `dev` and `main`; `dev` additionally carries the test suite and development-only instructions and continuation files.
- Keep README and other finalized user-facing HAWS documents and templates on both branches when changed.
- Keep personal or device-local Second Brain content in its ignored/private location. Do not stage it for either branch.
- At the end of a substantial `dev` task, update `HANDOFF.md` with the root cause or decision, changed files, executed checks and results, commit/push state, and exact resume point.

This standing instruction means completed user-facing work delivered to `dev` is also delivered to `main`, without a repeated request; development-only files remain on `dev`.

## Go modernization delivery constraints

- Continue the existing Go TUI migration incrementally. Keep the legacy runtime until the corresponding native Go behavior passes parity and safety checks. Do not describe an action as native while it invokes Bash.
- Keep the developer's live test path available from the current checkout and isolate its runtime, settings, AI configuration, credentials, and Second Brain from the regular HAWS installation. See `docs/development.md`.
- Future packaging requirement, deferred while application behavior is being completed: provide one convenient downloadable artifact per supported operating system that can launch HAWS without manual ZIP extraction or user-installed developer tools. Do not prioritize packaging until the application lifecycle and native behavior are verified.
- The active request explicitly limits this delivery to `dev`; do not merge or synchronize it to `main` unless the user later authorizes that work.
