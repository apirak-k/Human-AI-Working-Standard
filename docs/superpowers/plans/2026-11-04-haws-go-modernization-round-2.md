# HAWS Go Modernization — Round 2 Plan

**Source request:** `/Users/bubu/.codex/attachments/9202ee15-f6c9-4a93-ac90-8ff372a40cee/ข้อความที่วาง.txt`
**Branch:** `codex/go-modernization`
**Round 1 base:** `a37df8c04033217b89c2a9ae6ae324c2455585e1`

## Goal

Continue the additive Go migration while preserving the existing HAWS experience and data. Close the confirmed safety gaps first, then make the distribution/runtime boundary usable without a developer checkout, complete lifecycle routing and recovery, refine shared-component ownership, and perform one combined audit after implementation.

## Binding constraints

- Keep the Go TUI and one shared codebase for Windows, macOS, and Linux.
- Keep three OS packages, CPU selection, GitHub Releases, and GitHub Actions.
- Do not introduce a download website, GUI, or speculative universal AI adapter engine.
- Preserve Claude Code, Codex, and Gemini CLI / Antigravity integrations and existing skills/source/catalog behavior.
- Do not overwrite unowned files. Do not stage broad Second Brain paths or publish personal notes automatically.
- Preserve settings, Second Brain data, enabled/disabled components, external sources, and ownership records during migration.
- Do not perform destructive tests against real user data or private Second Brain repositories.
- Keep the legacy runtime until the replacement passes relevant parity tests.
- Do not modify or push to `main`; do not publish a production release without authorization.
- Mark any platform or behavior not executed as `[Unverified]`.

## Confirmed Round 1 gaps to resolve

1. `haws.sh` explicitly replaces unowned canonical Gemini/Antigravity and Claude agent destinations.
2. Second Brain reconciliation can discard document text, uses broad `git add .`, and automatically pushes during normal HAWS Sync and connect.
3. Release packages contain launchers and Go binaries only; normal actions require a full HAWS checkout, and Linux root discovery can select its own launcher recursively.
4. Go startup omits first-time Setup and Repair, accepts only a narrow action set, and a nested Bash Home can bypass Go Sync.
5. A corrupt active Go version can block launcher recovery and rollback; base-package cleanup and full owned install-folder removal are incomplete.
6. Skills are shared through existing source/link machinery, but no general typed CLI/MCP component ownership and consumer lifecycle is present.
7. CI's packaged smoke test exercises only `--version`; its legacy migration fixture reads an old Git object without requesting complete history, and several existing safety suites are not wired into CI.

## Task List

### Task 1: Preserve unowned AI agent files

**Files:** `haws.sh`; `tests/cli/repository_skill_test.sh` (and the suite runner only if needed).

**Acceptance criteria:**
- An unowned regular file, symlink, or directory at an official AI agent destination remains unchanged after Sync.
- Exact legacy ownership adoption still works when the current file/link is provably HAWS-owned.
- Changed owned files remain preserved by fingerprint checks.
- A regression test fails against the Round 1 behavior and passes with the fix.

**Verification:** focused agent-link tests, relevant CLI suite, shell syntax, `git diff --check`.

### Task 2: Make Second Brain synchronization lossless and non-publishing by default

**Files:** `haws.sh`; focused Second Brain, Sync, and Settings tests; suite runner if needed.

**Acceptance criteria:**
- Normal HAWS Sync and Second Brain connect do not stage arbitrary files or push personal content.
- Remote updates apply only through a safe path; dirty or diverged local state is preserved and reported without destructive merge fallback.
- No reconciliation path reconstructs documents from partial extracts or selects a document side by length.
- Any user-initiated publish path previews exact files and requires explicit confirmation before staging/committing/pushing.
- Tests use temporary Git fixtures only and verify unchanged HEAD/index/worktree/origin on refusal or conflict.

**Verification:** `tests/test-secondbrain-merge.sh`, focused Settings/Sync suites, full CLI suite, shell syntax.

### Task 3: Package a runtime that does not require a developer checkout

**Files:** package script/workflows, runtime manifest and Go root resolution, package tests.

**Acceptance criteria:**
- Each OS package includes only allowlisted runtime resources required to operate; it excludes `.git`, tests, development plans, and build-only files.
- The Go application identifies its own packaged runtime without mistaking a launcher for `haws.sh` or recursing into itself.
- Existing checkout installs remain recognized; first-time package setup and runtime resources work without a complete source checkout.
- Package tests extract and invoke the actual launcher and exercise an application action beyond `--version`.
- The runtime/data boundary is explicit so uninstall can preserve personal state.

**Verification:** package assembly tests, isolated extracted-package lifecycle fixture, native artifacts where available, checksum verification.

### Task 4: Restore update recovery and complete ownership-safe uninstall

**Files:** `internal/update`, launchers, `internal/uninstall`, `internal/app/uninstall.go`, tests.

**Acceptance criteria:**
- A corrupt active version does not prevent selecting a separately validated previous version through a stable bootstrap path.
- The updater either transactionally updates launcher/runtime resources or keeps the launcher immutable and versions all changing resources.
- Uninstall removes only verified HAWS-owned program files and empty owned directories; it preserves personal state, checkout data, modified/unowned files, and independently installed third-party components.
- Running-process or permission limits are reported as remaining items; completion is never falsely reported.

**Verification:** corruption/rollback tests, ownership and parent-swap regressions, uninstall-to-empty-package fixture, platform-specific launcher checks.

### Task 5: Complete Go lifecycle and command routing

**Files:** Go entrypoint/TUI/legacy bridge and focused tests; minimal legacy hooks only where needed.

**Acceptance criteria:**
- First-time Setup, Home, Settings, Sync, Doctor, explicit Repair, component/skill management, AI integration management, Second Brain, and Uninstall remain reachable through one HAWS experience.
- Supported legacy command arguments and exit status are preserved while native replacements are incomplete.
- Returning from Settings or other delegated flows cannot bypass Go's authoritative Sync/update path.
- Doctor is read-only by default; Repair previews ownership-verified changes and reports the plan before applying.
- One Sync action completes the selected app/runtime transition and enabled component update path, with bounded re-entry and rollback on failure.

**Verification:** TUI unit tests, command-routing tests, isolated first-run and nested-Settings lifecycle tests, Sync transition/rollback tests.

### Task 6: Add constrained shared-component lifecycle boundaries

**Files:** focused component inventory/ownership code and tests; existing source/catalog integration only where required.

**Acceptance criteria:**
- A source can declare multiple supported component types without being forced into the skill-only category.
- One canonical managed resource can serve multiple AI clients through references/registrations where supported.
- Per-client configuration and MCP process lifecycle remain separate from shared installation.
- Dependencies/consumers are recorded; HAWS never removes a shared resource still in use.
- Only allowlisted, verifiable installation forms are supported; no arbitrary install scripts are executed.
- Existing pack, standalone, custom source, and skill catalog behavior remains intact.

**Verification:** local fixtures for mixed source contents, duplicate installation prevention, per-client registration, dependency-aware removal, and existing skill regression suites.

### Task 7: Refine docs, migration checks, and CI coverage

**Files:** `core/HAWS.md`, `core/WORK_INSTRUCTIONS.md`, relevant templates/docs, `.github/workflows/go-build.yml`, tests, `HANDOFF.md`.

**Acceptance criteria:**
- Principles remain universal and flexible; practical instructions stay separate and adaptive.
- Valuable existing templates, Second Brain structure, and established integrations remain present.
- CI has deterministic source history where tests require it, runs safety suites, and exercises actual extracted packages on native runners beyond `--version`.
- Documentation accurately distinguishes source repository, packaged runtime, persistent state, and migration behavior.

**Verification:** documentation diff review, all applicable Go/CLI/fixture tests, CI YAML and shell checks, real artifacts where available.

### Task 8: Combined Round 1 + Round 2 final audit

Audit all 16 areas from the user request after implementation, fix critical and high-confidence regressions within scope, rerun affected tests, update the handoff, and report the requirements matrix, actual platform evidence, limitations, risks, and prioritized next work.

## Dependencies and order

Task 1 precedes Task 2 because both touch `haws.sh` and its Sync behavior. Task 3 establishes the package/runtime/data boundary before Task 4 uninstall and Task 5 routing. Task 4 establishes recovery interfaces before Task 5's bounded Sync transition. Task 6 reuses the existing skill source/catalog and ownership model after state paths are stable. Task 7 follows implemented behavior. Task 8 is last.

## Progress

- Round 1 inspected; current branch clean at `a37df8c04033217b89c2a9ae6ae324c2455585e1`.
- Read-only Round 2 gap mapping complete; no code changed yet.
- Before implementation, complete the SDD preflight table in the plan ledger and record rulings.
