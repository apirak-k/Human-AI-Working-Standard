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
- Each launcher selects `bin/<os>-<arch>/haws[.exe]` relative to its own package directory, then asks the base Go binary to validate and resolve the active version before dispatching it. This keeps marker, manifest, checksum, and reparse-path validation in one shared implementation.
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
- [x] Commit as `build: package HAWS for three operating systems` (`e4ddfc4`).

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

- [x] Add `httptest` cases for HTTP failure, malformed metadata, checksum mismatch, and truncated downloads.
- [x] Add filesystem cases for invalid archive paths, incomplete package, failed activation, rollback, and repeated update.
- [x] Implement download, validation, staging, activation, and rollback with the standard library.
- [x] Add active-binary resolution and verify installed manifests before launcher dispatch on all operating systems.
- [x] Run focused tests, the complete Go suite, vet, and cross-builds for all six targets.
- [x] Commit as part of the verified update/Sync/uninstall implementation stage.

### Task 5: One Sync flow and ownership-safe uninstall

**Files:**
- Modify: `cmd/haws/main.go`
- Create: `internal/app/sync.go`
- Create: `internal/legacy/settings.go`
- Create: `internal/ownership/manifest.go`
- Create: `internal/uninstall/uninstall.go`
- Test: `internal/app/sync_test.go`
- Test: `internal/legacy/settings_test.go`
- Test: `internal/ownership/manifest_test.go`
- Test: `internal/uninstall/uninstall_test.go`
- Test: `internal/update/owned_test.go`

**Interfaces:**
- Go Sync checks/downloads/activates the HAWS release, then invokes the existing full HAWS Sync exactly once; the legacy runtime remains responsible for checkout, skills, agents, AI integrations, and Second Brain behavior.
- App rollback restores the previous Go application version if the existing Sync fails after a release activation.
- Uninstall previews changes and removes only app files whose path, type, and recorded fingerprint still match; user state and all unowned or modified files are preserved.
- All three launchers ask the base Go binary to resolve the active version; the Go validation rejects changed binaries and junction/reparse paths before a launcher starts the versioned binary.

- [x] Add regression tests for one Sync call, failed release update, failed legacy Sync, and rollback.
- [x] Add uninstall tests for owned, unowned, modified, missing, symlink/junction, running executable, and personal-state paths.
- [x] Verify the new parent-path regression fails before the cleanup fix and passes after it.
- [x] Keep the existing full Sync as the compatibility bridge; no change to `haws.sh` or component behavior was needed.
- [x] Implement ownership-checked preview/apply and preserve user state by default.
- [x] Run focused tests, `go test ./...`, the 403-check HAWS suite, vet, and package/launcher checks.
- [x] Commit as part of the verified update/Sync/uninstall implementation stage.

### Task 6: Migration gate and final verification

**Files:**
- Modify: `README.md` only after all package paths and supported platforms are verified.
- Modify: `HANDOFF.md` with completed stages, test results, unresolved platform checks, and exact resume point.

- [x] Compare Go and legacy command coverage and confirm Sync, Settings, Doctor, and Uninstall remain reachable.
- [x] Run full Go and Bash suites from the final tree and inspect `git diff --check`.
- [ ] Execute each release artifact on a matching OS/CPU before declaring that target supported; only macOS/arm64 has been executed locally so far.
- [x] Keep the legacy runtime and old launchers in place until those host checks pass.
- [x] Do not push or merge; report the branch, commits, verified targets, incomplete targets, and next stage.

## Current verification boundary

- The native Go test, vet, Unix launcher, package assembly, and legacy HAWS suites pass on this macOS/arm64 host. The actual macOS package was built, checksum-verified, extracted, and run.
- All six release binaries cross-build, and Windows test binaries cross-compile for amd64 and arm64. Cross-compilation does not verify Windows or Linux runtime behavior.
- The Windows PowerShell launcher test now builds real Go fixtures and covers active-version selection and junction rejection, but it has not run in this Mac worktree. Linux runtime package smoke also remains pending until Linux CI runs.
- GitHub Actions has not run for this branch. Do not advertise OS/CPU support beyond macOS/arm64 until the matching native artifact test completes.
- An active Go version currently running during uninstall is preserved until it exits; ownership-verified cleanup is otherwise limited to the app package. Do not remove the legacy runtime yet.
