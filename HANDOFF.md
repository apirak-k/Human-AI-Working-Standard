# Development Handoff

Updated: 2026-10-01

## Branch Contract

- `main` is the ready-to-use baseline at `dc9d393`.
- At the start of this review follow-up, `dev` and `origin/dev` both pointed to `7846259` (parent `87a9c3a`); `main` and `origin/main` both pointed to `dc9d393`. Keep this work on `dev`.
- This handoff is the only development-status document kept on `dev`; shared Agent and HAWS documents remain available on both branches.
- The public `origin` branch set is `main` and `dev`.

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

## ChatGPT Review Feedback Follow-up — Local Changes

- Evaluated the review findings for commit `7846259` against the current CLI, adapters, and tests. Implemented exact-only ownership recovery for legacy pointers, agent files, Claude commands, Gemini skill entries, and the tracked Git hook; modified and unrelated user content remains unowned and is preserved.
- Fixed Install/Update to return severe Sync failures, stale-manifest launch detection, fresh setup defaults after uninstall, uninstall ownership-ledger cleanup, draft repository filtering, Codex environment naming, and partial cleanup when the native Codex adapter cannot run.
- Second Brain reconnect now restores the previous `origin` URL when the remote operation fails. README privacy text now states that HAWS does not check GitHub repository visibility. Settings Apply documentation and the production Sync→Uninstall E2E were corrected.
- `tests/cli/run.sh` passed on Windows Git Bash 5.3.15 with **179 passed, 0 failed**:

| Suite | Result |
| --- | ---: |
| Launcher/menu | 17 passed |
| Local state | 16 passed |
| Settings flow | 46 passed |
| Catalog | 6 passed |
| Repository/skill | 24 passed |
| Sync | 31 passed |
| Status/doctor | 14 passed |
| Uninstall | 14 passed |
| Home entrypoint | 4 passed |
| Lifecycle/plugins E2E | 7 passed |

- The lifecycle E2E includes a production Sync→Uninstall run without seeded ownership rows and an upgrade fixture that adopts exact legacy HAWS artifacts while preserving edited files and user entries. Focused tests also cover final Install/Update failure propagation, post-uninstall defaults, stale manifest handling, Codex disabled health, Second Brain rollback, interrupted uninstall recovery, and ownership-ledger cleanup.
- `bash -n haws.sh`, `node --check ai-configs/gemini/skills-json.mjs`, `node --check ai-configs/codex/agents.mjs`, and `git diff --check` passed on the final local tree. [Unverified] macOS and Linux were not run; Second Brain rollback with no pre-existing `origin` was not separately verified. These review fixes remain uncommitted and unpushed on `dev`.

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

Continue new work on `dev`. Keep the shared Agent and HAWS documents in both branches, and promote verified changes to `main` when they are ready for use.
