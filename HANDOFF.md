# Development Handoff

Updated: 2026-09-30

## Branch Contract

- `main` is the ready-to-use baseline at `9e752e3`.
- `dev` starts from the same code, tests, HAWS standards, Agent roles, and templates as `main`.
- This handoff is the only development-status document kept on `dev`; shared Agent and HAWS documents remain available on both branches.
- The public `origin` branch set is `main` and `dev`.

## Completed

- Integrated the useful changes from the three public branches into `main`.
- Preserved the Second Brain merge and Settings Apply fixes with focused regression tests.
- Restored the advisory `commit-msg` hook required by the current setup flow.
- Updated repository taxonomy detection in `catalog_source_kind` to respect `skills/standalone/*` folder taxonomy and ignore hidden directories (`.*`).
- Fixed `load_disabled_skills` in `haws.sh` to declare `DISABLED_SKILLS` as a global associative array (`declare -gA`), eliminating `unbound variable` crashes during sync.
- Refined Antigravity (`skills.json`) generation to register exact active skill directories instead of broad parent directories, cleanly excluding disabled skills from Antigravity IDE.
- Added comprehensive `ponytail*` prefix matching in sync to prevent duplicate global symlinks when plugin cache exists.
- Kept this active checkpoint on `dev` only.

## Verification

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
