# HAWS Legacy Console Entry Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the `haws` command in native terminals while preserving the
historic HAWS console UX and integrating Task 1–5 features safely.

**Architecture:** Add one ownership-aware command-integration module and
route it through the existing Preview/Apply path. Replace the Git-Bash
full-screen cursor presentation with the historic line-oriented renderer;
keep catalog, draft, and operations logic from Task 1–5 unchanged.

**Tech Stack:** Bash, Windows per-user Command Processor AutoRun/doskey,
POSIX shell profiles, fixture HOME/registry-command fakes.

**Spec:** `docs/superpowers/specs/2026-09-10-legacy-console-entry-design.md`

## Global Constraints

- Keep historic entrypoints and all Task 1–5 behavior.
- No required `.bat` or `.exe` entrypoint.
- Preview before every profile or registry mutation; ownership-aware uninstall.
- Automated tests use fake registry/profile locations only.
- Do not test against the real home, registry, remotes, or Git Bash session.

---

### Task 0: Command-integration model and fixture tests

**Files:**
- Create: `runtime/command_integration.sh`
- Modify: `runtime/settings.sh`
- Modify: `runtime/state.sh`
- Create: `tests/cli/command_integration_test.sh`
- Modify: `tests/cli/run.sh`

- [ ] Write failing fixture tests for Windows AutoRun preservation, bash-missing
  Blocked preview, marked macOS/Linux profile blocks, idempotent Apply, and
  ownership-aware uninstall.
- [ ] Implement `command_integration_plan`, `command_integration_apply`, and
  `command_integration_remove`; use injected fixture paths/commands in tests.
- [ ] Add Command Access to Settings Preview and run the focused suite.

Run: `bash tests/cli/command_integration_test.sh`

### Task 1: Restore the historic console presentation model

**Files:**
- Modify: `runtime/ui.sh`
- Modify: `runtime/settings.sh`
- Modify: `tests/cli/settings_test.sh`

- [ ] Add failing fixture assertions for historic headings, numbered prompts,
  loading status, pack-status columns, and no full-screen ANSI redraw.
- [ ] Implement line-oriented menu/prompt helpers and route Settings, Skills,
  Preview, and Home through them while retaining draft semantics.
- [ ] Run `bash tests/cli/settings_test.sh`.

### Task 2: Integrate Task 1–5 capabilities into the legacy flow

**Files:**
- Modify: `runtime/settings.sh`
- Modify: `runtime/operations.sh`
- Modify: `tests/cli/first_install_test.sh`
- Modify: `tests/cli/sync_test.sh`

- [ ] Add failing flow tests: Settings → Skills pack → draft → Preview → Apply
  → Home, plus Back and Cancel with no persistent write.
- [ ] Make the legacy renderer expose these existing capabilities without
  changing catalog, sync, status, or doctor safety rules.
- [ ] Run focused first-install, settings, and sync suites.

### Task 3: Regression and user acceptance

**Files:**
- Modify only for defects found in Tasks 0–2.

- [ ] Run `bash -n haws.sh runtime/*.sh tests/cli/*.sh`.
- [ ] Run `bash tests/cli/run.sh` and adapter tests.
- [ ] Run `git diff --check` and verify only scoped files changed.
- [ ] Manually verify Command Prompt → `haws` on Windows; record user
  acceptance separately from automated test results.
