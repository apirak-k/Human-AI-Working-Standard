# HAWS Go package: layout, lifecycle, and migration

The Go application is being added beside the existing HAWS runtime. The package
keeps the familiar HAWS behavior while Go owns the Home TUI, command routing,
release-managed application updates, rollback, and package cleanup.

## Distribution and files

The release workflow builds three archives: Windows, macOS, and Linux. Each
archive contains launchers for that operating system, `amd64` and `arm64` Go
binaries, a fixed list of HAWS runtime resources, source revision pins, and a
SHA-256 sidecar. The launcher selects a binary for the current CPU.

The installed package has two different areas:

- `runtime/` contains the package's base HAWS shell runtime, AI adapters,
  templates, and neutral Second Brain starter documents. Each installed
  release also keeps its own immutable runtime at
  `versions/<version>/runtime/` beside the matching Go binaries.
- `data/` contains mutable settings, source checkouts, caches, and personal
  Second Brain documents. Package updates do not replace `data/`; uninstall
  preserves it by default.

The package is self-contained with respect to HAWS source files. Users do not
need Go or a complete HAWS developer checkout.

## Current operation

The Go Home TUI routes Setup, Settings, Sync, Doctor, Repair, and Uninstall.
Existing skill, agent, AI integration, and Second Brain operations still run
through the included HAWS runtime. A Go Sync checks the configured release,
validates the package's complete allowlisted runtime and both CPU binaries,
stages them together under one version directory, and activates them with one
version marker. It then runs one HAWS Sync for enabled sources and integrations
using that version's runtime. If component Sync fails, the marker returns to
the previous Go and runtime pair. Installed runtime files are fingerprinted;
a modified runtime cannot be selected or removed as HAWS-owned. Older installed
Go versions without a versioned runtime continue using the package's base
`runtime/`.

Doctor is read-only. Repair shows deep diagnostics and a Sync-based operation
plan, asks before applying it, and then runs one Sync. The plan describes the
operation and ownership safeguards; it does not yet enumerate every source or
destination that Sync may update. Uninstall first uses the existing ownership-
aware cleanup, then removes only package files that still match the package
manifest. Modified or unowned package files and all `data/` files are kept.

The existing skill-source/catalog lifecycle is supported. General installation
and shared-consumer management for arbitrary CLI tools or MCP servers is not
implemented. A skill source is kept once in the managed source location and
exposed to supported AI clients through their existing links or registrations;
per-client configuration remains separate. The `kit add --tool` option is
rejected because it previously entered the skill-only registry without a real
tool lifecycle. HAWS does not execute installer scripts from external sources.

## Existing installation state

Package data defaults to the package's sibling `data/` directory. During
package startup, HAWS copies the legacy
`runtime/ai-configs/environments.disabled` setting into
`data/state/environments.disabled` with create-if-absent behavior; it leaves
the original file in place. New package Settings write that mutable file under
`data/state/`, outside the versioned runtime.

The package does not automatically copy a checkout's `.haws/state`, source
checkouts, ownership records, or personal Second Brain files into `data/`.
This avoids silently changing or merging existing state, but means the first
package launch can appear to have fresh settings.

To keep using existing state and personal Brain files without copying them,
start the package from a terminal with `HAWS_STATE_DIR` and
`HAWS_SECOND_BRAIN_DIR` set to their existing absolute paths. For a source
checkout, the state directory is usually `<checkout>/.haws/state`; use the same
Second Brain directory that the old installation actually used.

```bash
export HAWS_STATE_DIR="/path/to/Human-AI-Working-Standard/.haws/state"
export HAWS_SECOND_BRAIN_DIR="/path/to/the/existing/Second-Brain-directory"
./haws.command
```

On Windows PowerShell, set `$env:HAWS_STATE_DIR` and
`$env:HAWS_SECOND_BRAIN_DIR` to the absolute paths before running `haws.bat`.
An automatic migration preview and copy flow remain future work. Keep the old
checkout and `data/` backup until a migration has been reviewed.

## Platform tools and verification

The package does not require a Go installation. Because lifecycle operations
still use the existing runtime, Git and Bash 4.2 or newer are required for
those operations. Windows users need Git for Windows; macOS users need a newer
Bash such as Homebrew Bash because the built-in Bash is 3.2. The native Go
binary and launcher can start without a source checkout.

CI is configured to test on native Windows, macOS, and Linux runners and to run
an extracted package's version and status actions. A configured workflow is not
evidence that a run has completed; check the Actions results before treating a
platform as verified. Local cross-compilation alone does not verify native
runtime behavior.
