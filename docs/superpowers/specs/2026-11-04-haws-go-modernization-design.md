# HAWS Go Modernization Design

## Intent

Introduce a Go-based HAWS application and move distribution, synchronization,
rollback, and uninstall toward a cross-platform release package while keeping
the existing Bash implementation usable until its behavior has been replaced
and verified. The work is staged so each part can be reviewed and reverted on
its own.

## Goals

- One Go source codebase with a Terminal UI for Windows, macOS, and Linux.
- One downloadable package per operating system; each package selects the
  matching CPU binary at launch.
- GitHub Releases distribute the application. GitHub Actions build and verify
  the platform artifacts.
- One user-facing Sync action updates HAWS and enabled components, with a
  recoverable application update.
- Uninstall removes only verified HAWS-owned files and preserves personal data
  by default.
- Keep the current HAWS implementation as a working fallback until replacement
  coverage is adequate.

## Non-goals

- Redesigning AI compatibility, Skills, Agents, Second Brain content, or HAWS
  instructions in this change.
- Replacing the Terminal UI with a web or graphical interface.
- Download-page OS detection, package-manager integrations, or changing the
  public skill catalog.
- Removing the legacy runtime before its replacement passes relevant tests.

## Approaches

1. **Replace the shell runtime in one change.** Rejected because it conflicts
   with the requested staged rollout and would increase data-loss and
   compatibility risk.
2. **Keep the shell interface and add Go only for packaging.** Rejected because
   it would not provide the requested Go Terminal UI.
3. **Add Go alongside the current runtime, then replace behavior in tested
   slices.** Selected by the user. The initial Go UI routes existing actions to
   the legacy implementation; later slices move release update/rollback and
   uninstall into Go while keeping AI/skill component behavior intact.

## Architecture

- Keep `haws.sh` and `haws.bat` intact as the reference implementation and
  fallback during the migration.
- Add a small root Go module with `cmd/haws` as the entry point. Keep the UI,
  action routing, release update, and ownership-aware uninstall in focused
  internal packages only when each has a real caller.
- Use the Go standard library for the first Terminal UI and core application
  logic. The UI retains the existing Home actions and passes their results to
  the legacy command runner during the compatibility phase.
- Add OS-specific double-click launchers under `launchers/`; each launcher
  selects a packaged binary by OS and CPU and leaves current legacy launchers
  unchanged until the Go package is ready to become the default.
- Package and update data formats must preserve existing user state and current
  Git-backed skill integration. Before packaging, verify which legacy files
  require a real Git checkout and choose a compatible package layout; do not
  silently convert or delete the current checkout.
- Stage application updates separately from activation. Verify the staged
  version before changing the active-version marker, retain the previous
  version for rollback, and do not touch user-owned files.
- The Go uninstall path owns only its recorded application files. Existing HAWS
  state, skill checkouts, external AI files, and Second Brain data remain
  preserved unless a verified ownership record and explicit user choice permit
  removal.

## Implementation calls

- Use a standard-library, numbered Terminal UI first to avoid a new runtime
  dependency and keep it testable with ordinary input/output streams.
- Keep the initial launchers separate from `haws.bat` and `haws.sh`; the
  default entry point changes only after Go and package parity checks pass.
- Build both `amd64` and `arm64` variants into each OS package where supported;
  a small OS launcher chooses the correct binary.
- Put release payloads under `haws-go/<os>/` when extracted into a checkout.
  This prevents the new `haws.sh` and `haws.bat` launchers from replacing the
  existing root launchers. Include an archive README that explains this
  compatibility-stage install layout and delegation behavior.
- Install and update Go-managed app versions alongside the existing HAWS
  checkout. Do not replace the checkout or move its state during the initial
  migration; the existing directory remains a usable fallback.
- Pin release discovery to the official HAWS GitHub repository, require HTTPS,
  and verify package SHA-256 before activation. Signed release provenance is
  deferred because the repository has no signing-key or rotation policy; this
  does not protect against compromise of the GitHub repository or publisher.
- Keep temporary compiler tooling outside the repository and remove it after
  verification.

## Review and verification focus

- Empty input, EOF, invalid menu choices, and repeated menu navigation must not
  mutate HAWS state.
- Legacy action execution must preserve command arguments, exit status, and
  inherited terminal input/output.
- Launchers must reject unsupported CPUs clearly and invoke only a binary under
  their own package root.
- Update failures before activation must leave the active version unchanged;
  failures after activation must permit restoring the previous version.
- Uninstall must preserve modified, unowned, and personal files, including
  state outside the application package.

## Decisions left to the implementation

- Keep the compatibility bridge until release packaging and the installed
  source/data boundary have been verified with fixtures.
- Release archives are overlays for an existing HAWS checkout, not standalone
  replacements yet: the Go compatibility runner still delegates to that
  checkout. The archive layout preserves its legacy launchers and state.
- Select archive formats and release workflow triggers that are simple to
  validate on all three operating systems.
- Do not claim any OS/CPU pair supported until its built artifact has been
  executed by the corresponding CI runner or a real host.
