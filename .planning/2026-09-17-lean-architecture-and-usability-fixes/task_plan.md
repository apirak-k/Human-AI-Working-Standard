# Task Plan: Lean Architecture & Usability Root-Cause Fixes

- [x] Task 1: Stale Sync Lock Auto-Recovery (Check PID liveness and auto-recover stale locks in sync_run)
  - Focus Test: bash tests/cli/state_test.sh (14 passed, 0 failed)
- [x] Task 2: Safe [Q] Return-to-Home Navigation (Preserve home intent even on warnings; no false code 3 abort)
  - Focus Test: bash tests/cli/launcher_menu_test.sh (17 passed, 0 failed)
- [x] Task 3: Scope-Scoped Adapter Linking (Sync & write pointers only for active AI environments)
  - Focus Test: bash tests/cli/sync_test.sh (21 passed, 0 failed)
- [x] Task 4: Settings Preview Screen Grid Alignment (Align status columns, vertical single skills, custom/standalone badges)
  - Focus Test: bash tests/cli/settings_flow_test.sh (36 passed, 0 failed)
- [x] Task 5: Wording & Step Simplification ([Step X] without /5, dynamic settings skills label)
  - Focus Test: bash tests/cli/settings_flow_test.sh (37 passed, 0 failed)
- [x] Task 6: Final Full-Suite Acceptance & Handoff Update
  - Full Test Suite: bash tests/cli/run.sh (10 test suites, all passed)
