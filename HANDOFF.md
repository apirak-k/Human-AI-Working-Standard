# Development Handoff

Updated: 2026-09-29

## Branch Contract

- `main` is the ready-to-use baseline at `86c7459`.
- `dev` starts from the same code, tests, HAWS standards, Agent roles, and templates as `main`.
- This handoff is the only development-status document kept on `dev`; shared Agent and HAWS documents remain available on both branches.
- The public `origin` branch set is `main` and `dev`.

## Completed

- Integrated the useful changes from the three public branches into `main`.
- Preserved the Second Brain merge and Settings Apply fixes with focused regression tests.
- Restored the advisory `commit-msg` hook required by the current setup flow.
- Updated the repository taxonomy regression to match the current folder-based catalog behavior.
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

## Resume Point

Continue new work on `dev`. Keep the shared Agent and HAWS documents in both branches, and promote verified changes to `main` when they are ready for use.
