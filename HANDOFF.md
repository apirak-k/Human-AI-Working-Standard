# Development Handoff

Updated: 2026-10-05

## Branch Contract

- `dev` is the working branch and carries automated tests, fixtures, and development instructions. `main` is the user branch and carries user-facing HAWS code and finalized documentation.
- At the start of this correction, `dev` and `origin/dev` pointed to `50b9665`; `main` and `origin/main` pointed to `2ae4967`. The code fix was already on both branches, while the shared workflow instructions existed only on `dev`.
- `AGENTS.md`, `PROJECT_SPECIFIC.md`, `HANDOFF.md`, tests, fixtures, unfinished plans, and task progress notes stay on `dev`; keep user-facing product code and documentation on both branches.
- When a completed work chunk is pushed to `dev`, synchronize its user-facing code and documentation to `main` in that task. Do not wait for the user to repeat this direction.
- The `origin` branch set is `main` and `dev`.

## User Branch Content — 2026-10-05

- `main` is for HAWS users. Keep the automated test suite and fixtures on `dev`; they are not part of the user branch.
- The full `tests/` directory is retained on `dev` and removed from the current `main` tree. Past commits remain in Git history; no history rewrite was performed.
- Keep finalized user-facing code, skills, templates, README, and user documentation synchronized to both branches. Keep test and continuation material on `dev` only.
- Delivery: policy and handoff commit `59a7ba4` was pushed to `origin/dev`; main cleanup commit `f0e5ecf` removed the 15 tracked test files (5,740 lines) and was pushed to `origin/main`. The branch tree comparison confirmed that tests and development-only documents are the only intended differences. `git diff --check` passed; no runtime tests were run because this cleanup changed no executable product code.

## Branch Sync Rule Correction — 2026-10-05

- The previous correction incorrectly placed `AGENTS.md` and `PROJECT_SPECIFIC.md` on `main`; both are development-only instructions and must remain on `dev` with this Handoff.
- The standing rule is stored in the dev-only `PROJECT_SPECIFIC.md`: every completed, checked work chunk delivered to `dev` also syncs its user-facing code and documentation/templates to `main` in the same task; tests stay on `dev`.
- Updated the user-facing README on both branches to describe scrolling long menus. Removed the development instruction files from `main`.
- Delivery under the current policy: only user-facing product code and documentation are synchronized to `main`; tests, development instructions, and this Handoff remain on `dev`. Resume from the current `dev` HEAD.

## Skill Menu Viewport and Codex Skill Check — 2026-10-05

- Root cause: `interactive_menu` redrew every checklist row and moved the cursor by the full list height. Long skill packs exceeded the terminal viewport; cursor movement was clamped at the screen boundary, so redraws duplicated rows. Long descriptions also wrapped and made the physical list taller than its row count.
- Fix: render only the visible row window, keep the selection in view, show the item range, and fit row details to the terminal width. The key controls are shortened only when they would wrap.
- Codex skill check: `frontend-ui-engineering` exists in the `agent-skills` pack, its `SKILL.md` and HAWS Codex link are readable, it is not disabled in the device-local skill list, and the current Codex catalog exposes it. The screenshot's `mattpocock-skills` pack is separate; no skill repair was needed.
- Branch workflow rule at that delivery: completed, checked work was synchronized to both branches. The current rule keeps tests and development instructions on `dev` and sends only user-facing work to `main`.
- Verification: launcher/menu **19/19**, local state **16/16**, settings flow **56/56**, catalog **6/6**, repository/skill **27/27**, sync **32/32**, status/doctor **14/14**, uninstall **16/16**, home **4/4**, lifecycle/plugins **14/14** — **204 passed, 0 failed**. `bash -n` and `git diff --check` passed. Manual 24×80 TTY check with 35 skills showed 16 visible rows per frame, range update from `Items 1-16 of 36` to `Items 2-17 of 36`, and no wrapped details.
- Delivery: menu fix commit `ef23b16` was pushed to `origin/dev`, and the same code and regression test were delivered to `main` as `2ae4967`. This Handoff and the workflow instructions remain on `dev`; the README behavior note is shared. Resume from the current `dev` HEAD.

## Sync Candidate Validation Follow-up — 2026-10-02

- Root cause: candidate validation required every active skill entrypoint to remain at its previous path. A valid upstream move or removal therefore failed the entire source update.
- Updated validation to inspect regular skill entrypoints in the fetched candidate tree, accept path changes/removals when the candidate still has usable skill content, and continue rejecting an empty candidate without falling back to old content.
- Verification: `tests/cli/sync_test.sh` passed **32/32**; `bash -n haws.sh tests/cli/sync_test.sh` and `git diff --check` passed.
- Fix commit `9df9a79` was promoted to `main` in merge commit `e7da972`; `origin/main` was verified at that revision.
- Next action for an affected device: update HAWS to `main`, then retry Sync.

## Baseline Audit Follow-up — Commit 7846259

- Source: today's ChatGPT conversation “แก้HAWS,” which prioritized a real install-to-uninstall lifecycle, Second Brain settings as a draft until final confirmation, preserving unowned files during Sync, and a clear Bash minimum for macOS.
- Updated `haws.sh` and the Gemini JSON adapter to merge HAWS skill entries with existing Antigravity settings, record only HAWS-owned entries, and remove only those entries during uninstall. Existing or edited unowned files are preserved.
- Changed Second Brain connect/disconnect in Settings to remain draft actions until Install/Update applies the reviewed plan. Direct `haws.sh user connect` remains immediate.
- Added uninstall state tracking so a completed full uninstall does not reopen as installed solely because an old manifest remains. Native Codex cleanup now runs through its ownership manifest, and unchanged unowned profiles are no longer claimed by the shell ownership ledger.
- Added a Bash 4.2 startup guard and documented the Homebrew Bash launch command for macOS.
- Updated the stale Second Brain Settings expectations to verify draft-only connection changes and no mutation before final confirmation. Scoped the worktree ownership assertion to skill records, retained the Antigravity config status line, and fixed the Windows Codex manifest path by constructing it with Node's path API. The E2E helper now prints captured command output on failure.
- `tests/cli/run.sh` passed on Windows Git Bash 5.3.15 with 167 passed and 0 failed:

| Suite | Result |
| --- | ---: |
| Launcher/menu | 17 passed |
| Local state | 16 passed |
| Settings flow | 38 passed |
| Catalog | 6 passed |
| Repository/skill | 23 passed |
| Sync | 31 passed |
| Status/doctor | 13 passed |
| Uninstall | 13 passed |
| Home entrypoint | 4 passed |
| Lifecycle/plugins E2E | 6 passed |

- Codex native profile tests passed 14/14. Disposable Gemini adapter checks passed for preserving user entries, removing only HAWS-owned entries, retaining edited entries, cleaning HAWS-created JSON, and leaving empty candidates untouched.
- `bash -n haws.sh`, `node --check ai-configs/codex/agents.mjs`, `node --check ai-configs/gemini/skills-json.mjs`, and `git diff --check` passed for commit `7846259`. [Unverified] The startup guard has not been exercised on macOS's system Bash 3.2; this machine has Git Bash 5.3.15. That commit is the pushed `origin/dev` baseline; the separate review fixes below are local until reported complete.

## ChatGPT Review Feedback Follow-up — Commit 4d5d222

- Evaluated the nine review findings against the current CLI, Gemini/Codex adapters, ownership records, and lifecycle tests. Legacy ownership recovery is now limited to a one-time migration from an installed v1 manifest and exact matching artifacts. Gemini adoption uses a path-specific candidate map; newly encountered exact-looking user integrations remain unowned.
- Uninstall now clears stale ownership rows for changed or missing artifacts while retaining ownership for dirty managed repositories. Codex Node adapter execution is required when either owned native records or a valid HAWS Codex manifest exists, and skipped when no HAWS Codex state exists.
- Second Brain reconnect operates on a disposable sibling candidate and only swaps it into place after fetch, merge, and push succeed. A failed push leaves the existing local checkout, history, and index unchanged; linked worktrees are refused.
- Install, Update, Settings, and Home preserve severe statuses such as `2` and `130`, including the `settings` command's final process status. First-use Setup no longer offers “Use Previous Settings” unless saved settings exist.
- Lifecycle coverage now includes a fresh integration that remains unowned through Uninstall, a frozen legacy fixture sourced from `7846259`, stateful Setup → Update → Uninstall → Setup, and Windows junction fixtures. The post-uninstall Auto Update assertion fails when its expected saved value is absent.
- The final `tests/cli/run.sh` regression passed on Windows Git Bash with **188 passed, 0 failed**:

| Suite | Result |
| --- | ---: |
| Launcher/menu | 17 passed |
| Local state | 16 passed |
| Settings flow | 51 passed |
| Catalog | 6 passed |
| Repository/skill | 24 passed |
| Sync | 31 passed |
| Status/doctor | 14 passed |
| Uninstall | 16 passed |
| Home entrypoint | 4 passed |
| Lifecycle/plugins E2E | 9 passed |

- The post-uninstall Auto Update assertion was mutation-tested: changing the expected saved value makes its focused test fail. `bash -n haws.sh`, `node --check ai-configs/gemini/skills-json.mjs`, `node --check ai-configs/codex/agents.mjs`, and `git diff --check` passed.
- These verified review fixes were committed on `dev` and pushed to `origin/dev` after the checks above; the exact revision is in Git history.
- [Unverified] macOS and Linux were not run. Native platform behavior outside Windows Git Bash remains unverified.

## Completed

- Integrated the useful changes from the three public branches into `main`.
- Preserved the Second Brain merge and Settings Apply fixes with focused regression tests.
- Restored the advisory `commit-msg` hook required by the current setup flow.
- Updated repository taxonomy detection in `catalog_source_kind` to respect `skills/standalone/*` folder taxonomy and ignore hidden directories (`.*`).
- Fixed `load_disabled_skills` in `haws.sh` to declare `DISABLED_SKILLS` as a global associative array (`declare -gA`), eliminating `unbound variable` crashes during sync.
- Refined Antigravity (`skills.json`) generation to register exact active skill directories instead of broad parent directories, cleanly excluding disabled skills from Antigravity IDE.
- Added comprehensive `ponytail*` prefix matching in sync to prevent duplicate global symlinks when plugin cache exists.
- Kept this active checkpoint on `dev` only.

## Prior Verification — Before the Current Audit Follow-up

The results below describe the earlier tree only and do not verify the current uncommitted changes:

The scripts included by `tests/cli/run.sh` were run individually on the final tree:

| Suite | Result |
| --- | ---: |
| Launcher/menu | 17 passed |
| Local state | 16 passed |
| Settings flow | 38 passed |
| Catalog | 6 passed |
| Repository/skill | 23 passed |
| Sync | 31 passed |
| Status/doctor | 13 passed |
| Uninstall | 13 passed |
| Home entrypoint | 4 passed |
| Lifecycle/plugins E2E | 6 passed |

Additional checks passed: Settings Apply regression, Second Brain merge preservation, and `bash -n`. Node tests passed 28 with 1 Windows symlink case skipped because the runner lacks link-creation privilege.

## Graphify Installation Boundary

- HAWS catalogs Graphify as an external standalone skill. HAWS Sync updates its device-local runtime source and links the skill directory like other skills, so the linked skill instructions follow that source.
- HAWS does not bootstrap Graphify's CLI or run Graphify's platform installer. Users who need the full CLI and native Codex/Antigravity skill bundles install those Graphify extras separately; HAWS Sync does not refresh the generated app bundles.
- Device snapshot on 2026-09-30: the HAWS submodule pin is Graphify `0.9.65`, while this device's runtime source, CLI, and Codex/Antigravity bundles are `0.9.72`. The CLI is editable from the device runtime; the app bundles are generated copies outside HAWS Sync.
- Current accepted behavior: HAWS supplies Graphify as a regular skill, and users maintain Graphify's CLI and app-specific extras. Add Graphify-specific HAWS automation only if this support requirement changes.

## Resume Point

Continue new work on `dev`. Keep tests and development documents on `dev`; promote verified user-facing code and finalized HAWS documentation to `main` when ready for users.
