# HAWS Recovery & Cross-Device Handoff Dossier

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
| **Task 3** | Known-Good TUI Behavior Only | **DEFERRED, NOT Approved** | Automated tests pass and core Windows Git Bash stdin reading works, but manual acceptance still found known bugs. The user intentionally chose to continue rather than manually debug Task 3 now. **Known bugs remain.** |
| **Task 4** | Clean Base Validation Only | **Completed (Partial Compliance)** | Validation suite passes (21/21), and CLI regression passes (85/85), but **we do NOT claim full `spec.md` compliance**. Several detailed spec requirements remain unaligned or deferred. |
| **Task 5** | Windows `.bat` Entry Only | **NOT Started** | Do not start until Task 3 and Clean Base alignment are approved. |
| **Task 6** | Cross-Platform Parity | **NOT Started** | Deferred. |
| **Task 7** | Documentation + Final Validation | **NOT Started** | Deferred. |

---

## 2. Tracked Files on `recovery/clean-base`

All essential context files are committed directly to this branch so no context is lost across devices:
- `spec.md`: The authoritative implementation contract (English, sequential execution rules).
- `HANDOFF.md`: This cross-device handoff dossier.
- `HAWS-ANTIGRAVITY-SEQUENTIAL-RECOVERY-PLAN.md`: Sequential recovery plan reference.
- `HAWS-CLEAN-BASE-RECOVERY-PLAN.md`: Clean base recovery plan reference.
- `haws.sh`: Entrypoint runtime loading, non-interactive bare launch detection, doctor/sync integration dispatch, interactive terminal detection (`[ -t 0 ]`).
- `runtime/ui.sh`: In-place TUI cursor menu (`ui_cursor_menu`), multi-select checklist (`ui_checklist`), dynamic `Q` context labeling (Back / Cancel / Exit), terminal key reading via interactive stdin (`[ -t 0 ]`), ANSI cursor rewind and redraw without frame accumulation.
- `runtime/settings.sh`: Settings draft lifecycle, repository add/remove plan integration, URL determinism (`_settings_repo_path_from_url`), collision checks, lazy skills loading, preview update/install generation.
- `runtime/integrations.sh`: Integration plan generator with source add (`add-source`) and source removal (`remove-source`), owned skill link pruning on detach.
- `runtime/health.sh`: Doctor recursion guard, read-only diagnostic checks.
- `tests/cli/task4_clean_base_validation.sh`: Comprehensive 21-point validation suite.
- `tests/cli/settings_test.sh`: 34 regression tests covering cursor menu, checklist, select all, lazy skills loading, draft isolation, preview review, and uninstall visibility.
- `tests/cli/first_install_test.sh`: 9 tests verifying clean machine first install, draft defaults, and non-mutating preview.
- `tests/cli/cross_platform_test.sh`: 3 tests verifying command surface consistency.
- `tests/cli/status_doctor_test.sh`: 6 tests verifying read-only status and doctor behavior.
- `tests/cli/catalog_test.sh`: 6 tests verifying source and skill discovery rules.
- `tests/cli/state_test.sh`: 12 tests verifying atomic writes, settings defaults, and lock safety.
- `tests/cli/sync_test.sh`: 8 tests verifying sync lock, dirty source blocking, and network guard.
- `tests/cli/uninstall_test.sh`: 7 tests verifying exact preview and owned file unlinking.

---

## 3. Test Results at Checkpoint

All test suites pass 100% green (125 tests total):
- `tests/cli/task4_clean_base_validation.sh`: **21 passed, 0 failed**
- `tests/cli/catalog_test.sh`: **6 passed, 0 failed**
- `tests/cli/cross_platform_test.sh`: **3 passed, 0 failed**
- `tests/cli/first_install_test.sh`: **9 passed, 0 failed**
- `tests/cli/settings_test.sh`: **34 passed, 0 failed**
- `tests/cli/state_test.sh`: **12 passed, 0 failed**
- `tests/cli/status_doctor_test.sh`: **6 passed, 0 failed**
- `tests/cli/sync_test.sh`: **8 passed, 0 failed**
- `tests/cli/uninstall_test.sh`: **7 passed, 0 failed**
- `ai-configs/codex/agents.test.mjs`: **14 passed, 0 failed**
- `ai-configs/codex/skills.test.mjs`: **1 passed, 0 failed**
- `skills/custom/keyboard-layout-fixer/tests/test_layout_fixer.mjs`: **4 passed, 0 failed**

---

## 4. Known Bugs, Gaps & Deferred Defects

Do not claim full spec compliance. The following gaps and known bugs remain:

1. **Task 3 Deferred Defects (Known TUI Bugs)**:
   - **Terminal buffer & escape handling**: Under certain Windows terminal configurations (e.g. mintty vs standard Windows conhost), arrow key timing and escape sequence timeouts (`0.1s`) may exhibit minor lag or dropped input during fast continuous keystrokes.
   - **Manual acceptance failure**: Manual run of `bash haws.sh settings` previously experienced immediate exit under certain terminal conditions before the `/dev/tty` fix. While the automated suite passes, full cross-terminal interactive manual acceptance is not yet certified.
2. **Settings Lifecycle Wording vs `spec.md` (Sections 5 & 6)**:
   - `spec.md` requires a dedicated first-install landing page called `HAWS Setup` (`Use Default Setup`, `Customize Settings`, `Exit`), leading into a lifecycle-neutral `HAWS Settings` page (`Apply`, `Reset to Defaults`, `Discard Changes`).
   - The current code still uses `HAWS Settings — First Install` with `Use Recommended Defaults` and `Preview Install`. This wording discrepancy must be aligned with `spec.md` in future iterations.
3. **Dirty Draft Exit Confirmation (`spec.md` Section 6.7)**:
   - `spec.md` mandates that if the draft has unapplied changes, pressing `Q` or `Discard Changes` must prompt the user with a confirmation (`Discard Changes? You have unapplied changes...`).
   - The current implementation cancels immediately on `Q` without prompt.
4. **Repository Multi-Select Removal & Full Prune (`spec.md` Section 7)**:
   - `spec.md` specifies multi-select checklist removal for repositories and complete auto-pruning of orphan skills.
   - Current implementation provides draft integration plan actions (`remove-source`), but full interactive multi-select repository removal UI and git submodule edge-case handling are only partially integrated.

---

## 5. Exact Next Steps for the Next Device / Session

When continuing work on another device:

1. **Clone or fetch**:
   ```bash
   git fetch origin
   git checkout recovery/clean-base
   git pull origin recovery/clean-base
   ```
2. **Verify working tree**:
   ```bash
   git status
   # Ensure working tree is clean and matches origin/recovery/clean-base
   ```
3. **Read authoritative contract**:
   - Inspect `spec.md` (especially Sections 0, 5, 6, 7, and 14).
4. **Address deferred defects & spec alignment**:
   - Align first-install landing page (`HAWS Setup` vs `HAWS Settings`).
   - Implement dirty draft exit confirmation on `Q` (`Discard Changes?`).
   - Re-test interactive TUI manually in the target terminal environment.
5. **DO NOT start Task 5 (Windows `.bat`)** until Task 3 and Clean Base alignment are explicitly approved by the user.
