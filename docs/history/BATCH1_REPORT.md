# Batch 1 Implementation Report

Date: 2026-09-13  
Implementation worktree: `E:/Human-AI-Working-Standard/.worktrees/codex-haws-old-base-selected`  
Base commit: `71797228368959ab7a8d16b152da87e8452392b6`  
Scope: Batch 1 launcher and old-style menu only; no merge or push.

## Implemented

- Added a thin `haws.bat` launcher. It prefers established Git-for-Windows paths, accepts a compatible PATH Bash only when `cygpath` is available, forwards explicit arguments, maps a bare launch to `menu`, preserves the child exit code, and keeps automation non-blocking with `HAWS_NO_PAUSE=1`.
- Changed bare `haws.sh` from the old implicit `sync` default to `menu`.
- Added `run_main_menu()` with the required eight entries and old raw-key conventions. TTY navigation redraws in place; non-TTY input remains pipe-testable. Each selected public action runs in a separate Bash process so its own `set -e` behavior remains effective and a non-zero result is shown before returning to the menu.
- Preserved the existing Single Skills / Multi-Skill Packs screens and arrow, Space, Enter, and q/Q controls.
- Changed checklist EOF from implicit confirmation to cancellation, preventing a closed/non-interactive input stream from saving configuration.
- Replaced the pre-commit hook's mutating Doctor call with the disposable-fixture CLI suite while retaining the existing staged-secret and LF checks.
- Added Bash fixture helpers, launcher/menu coverage, a CLI runner, and Windows execution tests. No `HAWS_TEST_KEYS` input API was added; tests use real piped key bytes and real `cmd.exe`/Git Bash execution.

Key implementation locations:

- `haws.sh:9` — safe bare default.
- `haws.sh:1130-1269` — existing checklist with pipe/EOF safety.
- `haws.sh:2532-2621` — main menu, TTY redraw, and isolated action dispatch.
- `haws.sh:2624-2628` — public `menu|interactive` dispatch.
- `haws.bat:8-50` — Bash discovery, forwarding, exit propagation, and guarded pause.
- `.githooks/pre-commit:55-61` — fixture CLI pre-commit gate.

## Red evidence

The tests were written before production changes. Dynamic shell cases first checked for `run_main_menu`, so the old `COMMAND=sync` path was never executed.

```text
& 'C:\Program Files\Git\bin\bash.exe' -c 'export PATH="/usr/bin:/bin:$PATH"; bash tests/cli/launcher_menu_test.sh'
exit 1 — 0 passed, 6 failed

node --test tests/windows_launcher_execution.test.mjs
exit 1 — 0 passed, 5 failed
```

The failures identified the missing `haws.bat` and missing bare main-menu entry point as intended.

## Final automated evidence

```text
& 'C:\Program Files\Git\bin\bash.exe' -c 'export PATH="/usr/bin:/bin:$PATH"; bash -n haws.sh && bash tests/cli/launcher_menu_test.sh'
exit 0 — 7 passed, 0 failed
```

Covered: launcher thinness, q and Q exits, EOF exit, required menu labels, old Skills categories/controls, real arrow/Space/Enter fixture update, checklist EOF cancellation without saving, and Exit selection without dispatch or HOME mutation.

```text
node --test tests/windows_launcher_execution.test.mjs
exit 0 — 6 passed, 0 failed
```

Covered: launcher existence, bare-to-menu forwarding, child exit-code preservation, quoted argument forwarding, missing-script error, missing-Bash error contract, and a real `cmd.exe -> haws.bat -> Git Bash -> haws.sh` bare-q smoke test with a disposable HOME.

```text
node --test ai-configs/codex/agents.test.mjs
exit 0 — 14 passed, 0 failed
```

```text
GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=safe.directory \
GIT_CONFIG_VALUE_0='E:/Human-AI-Working-Standard/.worktrees/codex-haws-old-base-selected' \
bash .githooks/pre-commit
exit 0 — secret scan, LF audit, and fixture CLI gate passed; CLI 7/7
```

Additional checks:

- `git diff --check` exited 0 for tracked changes.
- Explicit CR scan reported `CR=False` for the modified hook, `haws.sh`, and all new `.sh`/`.mjs` test files. `.gitattributes` retains required CRLF checkout normalization for `.bat`.
- No setup, sync, Doctor, uninstall, repository removal, or Second Brain action was run against the user's real HOME or configuration.

## Reference preservation

- `E:/Human-AI-Working-Standard/.worktrees/codex-haws-bootstrap` remained clean.
- `E:/Human-AI-Working-Standard` remained in its pre-existing dirty reference state; the Batch 1 work did not write there.
- The implementation worktree contains the Batch 1 edits plus the controller-owned untracked `IMPLEMENTATION_PROGRESS.md`.
- Nothing was staged, committed, merged, or pushed by this implementation task.

## Deferred / unverified

- `[Unverified]` Physical Explorer double-click behavior, terminal lifetime, and human-perceived one-row arrow movement. User acceptance is deferred until the final end-to-end gate.
- `[Unverified]` Full real Skills catalog interaction because submodules in this worktree are intentionally uninitialized. Automated fixtures prove Single Skills and Multi-Skill Packs behavior without copying or linking reference directories.
- `[Unverified]` Network timeout behavior. Batch 1 performed no network operation.
- `[Unverified]` Junction/symlink link-type behavior. It is outside the launcher/menu path exercised here.
- `[Unverified]` Human acceptance. Automated green evidence is not acceptance.

For a safe manual Skills-only fixture later, from Git Bash in this worktree:

```bash
source tests/cli/test_helper.sh
create_fixture
HOME="$FIXTURE_HOME" bash "$FIXTURE_PROJECT/haws.sh"
cleanup_fixture
```

This fixture contains one standalone skill and one two-skill pack. Do not use the uninitialized worktree catalog as evidence of the complete real catalog; a populated checkout or authorized submodule initialization is required for that later manual check.

