# HAWS Recovery & Cross-Device Handoff Dossier

> **Current status authority:** [PROJECT_STATE.md](PROJECT_STATE.md).
> **Product and execution contract:** [spec.md](spec.md).
> The checkpoint details below are a historical snapshot from 2026-09-11, not current status. Do not use them to select a branch, task, or merge decision.

## Current AGY Handoff Continuation (2026-09-13)

Continue only on `recovery/clean-base`. The existing worktree changes were
preserved. No reset, merge, push, worktree switch, or old-base Batch 7/8 work
was performed or started.

The requested scope is limited to three recovery fixes:

1. `haws.sh` help aliases (`help`, `--help`, `-h`) must exit 0.
2. `runtime/settings.sh` must display `all active (default)` while the skills draft is still unloaded.
3. Opening Skills without edits must not create a false `Discard Changes?` prompt.

Root-cause findings:

- The shared dispatcher had no help case, so all help aliases fell through to the unknown-command branch and exited 1.
- Lazy settings initialization intentionally leaves `HAWS_SELECTED_SKILLS` empty until Skills or Preview is opened; the menu treated that lazy sentinel as zero active skills.
- `settings_edit` captured an empty `orig_skills` before lazy loading; `settings_ensure_skills_draft` then populated the draft and the dirty check incorrectly saw a change.

Implemented and tested changes:

- Added one shared help dispatcher case returning exit 0.
- Added the smallest lazy-display branch and synchronized the original skills baseline after catalog materialization.
- Added regression coverage for all three behaviors. Existing performance changes in the four runtime files remain intact.

Fresh evidence:

- RED: settings regression run reported `47 passed, 2 failed`; the new Windows help check reported `8 passed, 1 failed` because help returned 1.
- `tests/cli/run.sh`: exit 0; catalog 6, cross-platform 5, first-install 10, settings 49, state 12, status/doctor 6, sync 8, uninstall 7, and Windows launcher 8 passed (111 total).
- `node --test tests/windows_launcher_execution.test.mjs`: exit 0; 10 passed, 0 failed.
- `.\haws.bat --help`: shared usage printed; PowerShell `$LASTEXITCODE` was 0.

Platform limits remain explicit: direct macOS/Linux execution and native TTY
behavior are [Unverified]; physical Windows Explorer double-click behavior and
native interactive-console/TUI behavior outside the executed launcher checks
are [Unverified].

`CODEX_HANDOFF.md` was inspected and remains preserved as an untracked artifact.
The next and only delivery action for this handoff is the requested commit after
the final checks. Stop there; do not begin old-base batches.

**Date**: 2026-09-11  
**Branch**: `recovery/clean-base`  
**Current HEAD**: `858ccb4` (prior to this final checkpoint commit)  
**Remote Target**: `origin/recovery/clean-base`  
**Authoritative Contract**: `spec.md` (committed and tracked in this branch)  
**Reference Plans**: `HAWS-ANTIGRAVITY-SEQUENTIAL-RECOVERY-PLAN.md`, `HAWS-CLEAN-BASE-RECOVERY-PLAN.md` (tracked in this branch)  

---

## 1. Executive Summary & Task Status

This dossier records the complete, exact recovery status for seamless continuation on another machine.

| Task | Title | Status | Notes |
| :--- | :--- | :--- | :--- |
| **Task 1** | Loop Fix Only | **Complete** | Resolved pre-commit hang, `run_doctor` recursion, and protected with regression tests. |
| **Task 2** | Approved UX Improvements Only | **Complete** | Restored approved UX feedback, Skills hierarchy (single/packs), vertical preview flows, draft-first settings, and lazy catalog loading. |
| **Task 3** | Known-Good TUI Behavior Only | **NOT Approved** | Known implementation/spec mismatches remain. |
| **Task 4** | Clean Base Validation Only | **Validation Completed (Caveat)** | Automated validation completed, but passing tests do NOT prove full spec compliance because some current tests encode outdated behavior. |
| **Task 5** | Windows `.bat` Entry Only | **Implemented (Not Approved)** | Implemented but not fully reviewed/approved. |
| **Task 6** | Cross-Platform Parity | **Implemented (Not Approved)** | Implemented but not fully reviewed/approved. |
| **Task 7** | Documentation + Final Validation | **Implemented (Not Approved)** | Implemented but not fully reviewed/approved. |

---

## 2. Tracked Files on `recovery/clean-base`

All essential context files are committed directly to this branch so no context is lost across devices:
- `spec.md`: The authoritative implementation contract (English, sequential execution rules).
- `HANDOFF.md`: This cross-device handoff dossier.
- `HAWS-ANTIGRAVITY-SEQUENTIAL-RECOVERY-PLAN.md`: Sequential recovery plan reference.
- `HAWS-CLEAN-BASE-RECOVERY-PLAN.md`: Clean base recovery plan reference.
- `haws.bat`: Windows native thin launcher (auto-locates Git Bash runtime, forwards all arguments cleanly).
- `haws.sh`: Entrypoint runtime loading, non-interactive bare launch detection, doctor/sync integration dispatch, interactive terminal detection (`[ -t 0 ]`).
- `runtime/ui.sh`: In-place TUI cursor menu (`ui_cursor_menu`), multi-select checklist (`ui_checklist`), dynamic `Q` context labeling (Back / Cancel / Exit), terminal key reading via interactive stdin (`[ -t 0 ]`), ANSI cursor rewind and redraw without frame accumulation.
- `runtime/settings.sh`: Settings draft lifecycle, repository add/remove plan integration, URL determinism (`_settings_repo_path_from_url`), collision checks, lazy skills loading, preview update/install generation.
- `runtime/integrations.sh`: Integration plan generator with source add (`add-source`) and source removal (`remove-source`), owned skill link pruning on detach.
- `runtime/health.sh`: Doctor recursion guard, read-only diagnostic checks.
- `tests/cli/task4_clean_base_validation.sh`: Comprehensive 21-point validation suite.
- `tests/cli/windows_launcher_test.sh`: 6 tests verifying haws.bat launcher contracts.
- `tests/windows_launcher_execution.test.mjs`: 7 tests verifying Windows execution and cross-platform parity.
- `tests/cli/settings_test.sh`: 37 regression tests covering cursor menu, checklist, select all, lazy skills loading, draft isolation, preview review, and uninstall visibility.
- `tests/cli/first_install_test.sh`: 9 tests verifying clean machine first install, draft defaults, and non-mutating preview.
- `tests/cli/cross_platform_test.sh`: 5 tests verifying command surface consistency and parity.
- `tests/cli/status_doctor_test.sh`: 6 tests verifying read-only status and doctor behavior.
- `tests/cli/catalog_test.sh`: 6 tests verifying source and skill discovery rules.
- `tests/cli/state_test.sh`: 12 tests verifying atomic writes, settings defaults, and lock safety.
- `tests/cli/sync_test.sh`: 8 tests verifying sync lock, dirty source blocking, and network guard.
- `tests/cli/uninstall_test.sh`: 7 tests verifying exact preview and owned file unlinking.

---

## 3. Test Results at Checkpoint

Automated test suites currently pass (141 tests total), but passing tests do NOT prove full spec compliance because some current tests encode outdated behavior:
- `tests/cli/task4_clean_base_validation.sh`: **21 passed, 0 failed**
- `tests/cli/windows_launcher_test.sh`: **6 passed, 0 failed**
- `tests/cli/catalog_test.sh`: **6 passed, 0 failed**
- `tests/cli/cross_platform_test.sh`: **5 passed, 0 failed**
- `tests/cli/first_install_test.sh`: **9 passed, 0 failed**
- `tests/cli/settings_test.sh`: **37 passed, 0 failed**
- `tests/cli/state_test.sh`: **12 passed, 0 failed**
- `tests/cli/status_doctor_test.sh`: **6 passed, 0 failed**
- `tests/cli/sync_test.sh`: **8 passed, 0 failed**
- `tests/cli/uninstall_test.sh`: **7 passed, 0 failed**
- `tests/windows_launcher_execution.test.mjs`: **7 passed, 0 failed**
- `ai-configs/codex/agents.test.mjs`: **14 passed, 0 failed**
- `ai-configs/codex/skills.test.mjs`: **1 passed, 0 failed**
- `skills/custom/keyboard-layout-fixer/tests/test_layout_fixer.mjs`: **4 passed, 0 failed**

---

## 4. Known Bugs, Gaps & Deferred Defects

Do not claim full spec compliance. The following known issues and limitations remain:

- **Task 3 Known Issues**:
  - Add Repository does not yet reliably enforce valid GitHub URL input.
  - Remove Repository still has UX/data representation issues.
  - Real-terminal TUI frame accumulation/redraw behavior is not accepted.
  - Settings wording/flow still differs from spec.
  - AI Environments behavior still needs verification against the detected-only selection rule.
  - Multi-provider skill identity remains a known limitation.
- **Test Inaccuracies**: Some existing automated tests encode outdated behavior, masking spec divergence.
- **Review Deficits**: Tasks 5, 6, and 7 are implemented but have not been fully reviewed and approved.

---

## 5. Final Status & Branch Readiness

Current task breakdown:
1. **Task 1 (Loop Fix Only)**: Complete.
2. **Task 2 (Approved UX Improvements Only)**: Complete.
3. **Task 3 (Known-Good TUI Behavior Only)**: NOT approved. Known implementation/spec mismatches remain.
4. **Task 4 (Clean Base Validation Only)**: Automated validation completed, but passing tests do NOT prove full spec compliance because some current tests encode outdated behavior.
5. **Task 5 (Windows `.bat` Entry Only)**: Implemented but not fully reviewed/approved.
6. **Task 6 (Cross-Platform Parity)**: Implemented but not fully reviewed/approved.
7. **Task 7 (Documentation & Final Validation)**: Implemented but not fully reviewed/approved.

**Branch Status**:
The branch is **NOT ready to merge**. Outstanding implementation/spec mismatches in Task 3 and unverified behaviors must be addressed, and full review/approval is required before any merge into `main` can occur.
