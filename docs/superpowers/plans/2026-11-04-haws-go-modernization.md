# HAWS Go Modernization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a cross-platform Go HAWS application and migrate distribution, Sync, rollback, and uninstall in verified stages while preserving the existing implementation as a fallback.

**Architecture:** Add a small Go module and Terminal UI beside the existing Bash runtime. Start with a compatibility runner and separate OS launchers; add release packaging and versioned activation only after that foundation passes tests. Preserve existing skills, AI integrations, Second Brain data, state formats, and legacy launchers.

**Tech Stack:** Go standard library, Bash and batch launchers, GitHub Actions, existing HAWS regression suite.

**Spec:** `docs/superpowers/specs/2026-11-04-haws-go-modernization-design.md`

## Global Constraints

- Use one Go source codebase for Windows, macOS, and Linux.
- Produce exactly three user-facing packages, one per OS, with CPU selection in the package launcher.
- Use GitHub Releases to distribute HAWS application packages and GitHub Actions to build them.
- Keep one user-facing Sync action for HAWS and enabled components, with a tested application rollback path.
- Preserve personal data by default; never overwrite or remove unowned files.
- Do not redesign AI Compatibility, Skills, Agents, Second Brain content, or HAWS instructions in this task.
- Keep the legacy runtime until its replacement passes the relevant tests.
- Do not push to `main`, perform destructive migration, or claim an OS/CPU pair supported before testing its corresponding artifact.

## Review Focus

- Menu EOF, invalid choices, and repeated navigation leave user state unchanged.
- Legacy action delegation preserves arguments, environment, stdin/stdout/stderr, and exit status.
- A launcher never runs a binary outside its package root and rejects unsupported CPUs clearly.
- Corrupt, partial, or incompatible release downloads never change the active version.
- Rollback and uninstall preserve modified, unowned, and personal files.

---

### Task 1: Go foundation and compatible Home TUI

**Files:**
- Create: `go.mod`
- Create: `cmd/haws/main.go`
- Create: `internal/tui/home.go`
- Create: `internal/legacy/runner_unix.go`
- Create: `internal/legacy/runner_windows.go`
- Test: `internal/tui/home_test.go`
- Test: `internal/legacy/runner_test.go`

**Interfaces:**
- `internal/tui.Action` has `sync`, `settings`, `doctor`, and `uninstall` values.
- `internal/tui.Run(in, out, runAction)` owns menu navigation and invokes one action callback at a time.
- `internal/legacy.Run(ctx, root, action, stdin, stdout, stderr)` invokes the corresponding existing HAWS command without changing the legacy runtime.
- `HAWS_ROOT` may select a checkout explicitly; otherwise locate a root containing `haws.sh` by walking from the current directory and executable directory.

- [x] Write tests for every menu action, invalid input, EOF, action failure, and return-to-menu behavior.
- [x] Implement the minimal standard-library menu and action routing.
- [x] Add legacy command execution for Unix and Windows with inherited terminal streams and preserved exit status.
- [x] Run `go test ./...` and the existing `bash tests/cli/run.sh`.
- [x] Commit as `feat: add Go HAWS terminal entrypoint` (`ee9e59b`).

### Task 2: OS launchers and CPU selection

**Files:**
- Create: `launchers/windows/haws.bat`
- Create: `launchers/macos/haws.command`
- Create: `launchers/linux/haws.sh`
- Test: `tests/go/launchers_test.sh`
- Test: `tests/windows/go-launcher.test.ps1`

**Interfaces:**
- Each launcher invokes `bin/<os>-<arch>/haws[.exe]` relative to its own package directory.
- macOS/Linux map `arm64|aarch64` and `x86_64|amd64`; Windows maps `ARM64` and `AMD64` including `PROCESSOR_ARCHITEW6432`.

- [x] Add hermetic launcher fixtures with fake architecture values and sentinel binaries.
- [x] Run the Unix launcher tests and confirm missing/unsupported binary cases fail safely.
- [x] Implement the three launchers without changing `haws.bat` or `haws.sh`.
- [ ] Run the PowerShell launcher tests on a native Windows host; this Mac worktree has no PowerShell runtime.
- [x] Cross-build `cmd/haws` for all six OS/CPU targets. Cross-build is compile-only, not runtime verification.
- [x] Commit as `feat: add cross-platform Go launchers` (Windows runtime check remains pending).

### Task 3: Three release packages and automated builds

**Files:**
- Create: `scripts/package-release.sh`
- Create: `.github/workflows/go-build.yml`
- Create: `.github/workflows/release.yml`
- Test: `tests/go/package_release_test.sh`

**Interfaces:**
- Build outputs are staged under `dist/<os>/` and contain the OS launcher plus its `amd64` and `arm64` binaries.
- Release outputs are `haws-windows.zip`, `haws-macos.tar.gz`, and `haws-linux.tar.gz`, each with a SHA-256 manifest.
- Release workflow runs only for version tags; build/test workflow also runs on pull requests and development branches.

- [x] Add package-layout and checksum tests using fixture binaries.
- [x] Run the packaging test and confirm it fails before the packager exists.
- [x] Build each binary with explicit `GOOS` and `GOARCH`, then assemble exactly three OS packages.
- [x] Verify archive paths, launcher permissions, CPU binaries, and checksums. The actual macOS/arm64 package was extracted and run locally.
- [x] Add CI for native OS tests and artifact smoke tests, with cross-builds for all six OS/CPU targets.
- [ ] Observe the GitHub Actions workflow on this branch; native Windows and Linux runtime checks remain pending until it runs.
- [ ] Commit as `build: package HAWS for three operating systems`.

### Task 4: Release update and rollback

**Files:**
- Create: `internal/update/release.go`
- Create: `internal/update/install.go`
- Test: `internal/update/release_test.go`
- Test: `internal/update/install_test.go`

**Interfaces:**
- Release discovery uses GitHub Releases and a pinned repository identity.
- Package bytes are checked against the release checksum manifest before extraction.
- Install stages a version under the app directory, validates expected files, and atomically changes the active-version marker only after validation.
- The previous version remains available for explicit rollback; failed stages leave the active marker unchanged.

- [ ] Add `httptest` cases for HTTP failure, malformed metadata, checksum mismatch, and truncated downloads.
- [ ] Add filesystem cases for invalid archive paths, incomplete package, failed activation, rollback, and repeated update.
- [ ] Run the focused tests and confirm they fail before implementation.
- [ ] Implement download, validation, staging, activation, and rollback with the standard library.
- [ ] Run `go test ./...`, cross-build all six targets, and run the legacy regression suite.
- [ ] Commit as `feat: update HAWS from verified releases with rollback`.

### Task 5: One Sync flow and ownership-safe uninstall

**Files:**
- Modify: `internal/app/app.go`
- Create: `internal/ownership/manifest.go`
- Create: `internal/uninstall/uninstall.go`
- Modify: `haws.sh` only to add a components-only bridge needed by Go orchestration.
- Test: `internal/ownership/manifest_test.go`
- Test: `internal/uninstall/uninstall_test.go`
- Test: `tests/cli/sync_test.sh`

**Interfaces:**
- Go Sync checks/downloads/activates the HAWS release, then invokes existing component synchronization without allowing the legacy runtime to update HAWS from Git a second time.
- App rollback restores the previous Go application version if release activation or the Go-managed phase fails.
- Uninstall previews changes and removes only app files whose path, type, and recorded fingerprint still match; user state and all unowned or modified files are preserved.

- [ ] Add regression tests for one Sync call, component-only delegation, failed release update, failed legacy component sync, and rollback.
- [ ] Add uninstall tests for owned, unowned, modified, missing, symlink, and personal-state paths.
- [ ] Run the new tests red before implementation.
- [ ] Add the smallest legacy bridge that reuses existing component logic and skips only the duplicate root update.
- [ ] Implement ownership-checked preview, apply, and rollback; never delete user state by default.
- [ ] Run focused tests, `go test ./...`, the full HAWS suite, and cross-platform build/launcher checks.
- [ ] Commit as `feat: add safe Sync and ownership-aware uninstall`.

### Task 6: Migration gate and final verification

**Files:**
- Modify: `README.md` only after all package paths and supported platforms are verified.
- Modify: `HANDOFF.md` with completed stages, test results, unresolved platform checks, and exact resume point.

- [ ] Compare Go and legacy command coverage and confirm all legacy actions remain reachable.
- [ ] Run full Go and Bash suites from the final tree and inspect `git diff --check`.
- [ ] Execute each release artifact on a matching OS/CPU before declaring that target supported.
- [ ] Keep the legacy runtime and old launchers in place until those host checks pass.
- [ ] Do not push or merge; report the branch, commits, verified targets, incomplete targets, and next stage.
