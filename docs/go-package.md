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

The Go Home TUI routes Setup, Settings, Sync, Doctor, Repair, Uninstall, and
Migrate existing installation. Existing skill, agent, AI integration, and
Second Brain operations still run through the included HAWS runtime. A Go Sync
checks the configured release, validates the package's complete allowlisted
runtime and both CPU binaries, stages them together under one version
directory, and activates them with one version marker. It then runs one HAWS
Sync for enabled sources and integrations using that version's runtime. If
component Sync fails, the marker returns to the previous Go and runtime pair.
Installed runtime files are fingerprinted; a modified runtime cannot be
selected or removed as HAWS-owned. Older installed Go versions without a
versioned runtime continue using the package's base `runtime/`.

Doctor is read-only. Repair shows deep diagnostics and a Sync-based operation
plan, asks before applying it, and then runs one Sync. The plan describes the
operation and ownership safeguards; it does not yet enumerate every source or
destination that Sync may update. Uninstall first uses the existing ownership-
aware cleanup, then removes only package files that still match the package
manifest. Modified or unowned package files and all `data/` files are kept.

The existing skill-source/catalog lifecycle is supported. A skill source is
kept once in the managed source location and exposed to supported AI clients
through their existing links or registrations; per-client configuration
remains separate. The `kit add --tool` option is rejected because it previously
entered the skill-only registry without a real tool lifecycle. General
installation, consumer tracking, and shared removal for arbitrary CLI tools or
MCP servers are not implemented. HAWS does not execute installer scripts from
external sources.

## Existing installation migration

Package data defaults to the package's sibling `data/` directory. During
package startup, HAWS copies the legacy
`runtime/ai-configs/environments.disabled` setting into
`data/state/environments.disabled` with create-if-absent behavior; it leaves the
original file in place. New package Settings write that mutable file under
`data/state/`, outside the versioned runtime.

To keep using an existing HAWS install, choose **Migrate existing installation**
in Home or run the package launcher from a terminal:

```bash
./haws.command migrate --from "/path/to/Human-AI-Working-Standard"
```

On Windows use `haws.bat migrate --from "C:\path\to\Human-AI-Working-Standard"`;
on Linux use `./haws.sh migrate --from "/path/to/Human-AI-Working-Standard"`.
The command shows the checkout, state, and Second Brain paths, then asks before
saving one reference in package `data/state/legacy-migration.json`. Optional
`--state DIR` and `--second-brain DIR` flags select non-default data locations.
For the normal checkout layout, HAWS reuses `<checkout>/.haws/state` and
`<checkout>/secondbrain/` in place. Existing settings, skill-source checkouts,
enabled/disabled skill selections, ownership records, AI integration state,
and personal Second Brain files stay at their current paths. Migration does not
copy, move, or delete files from the legacy installation. AI integrations
continue to use the current user Home directory.

When a migration reference is active, Sync updates the Go application from
GitHub Releases and skips self-updating the old HAWS checkout. It continues
updating enabled sources using the existing Sync implementation. Keep the old
checkout available while migrated skill sources are in use. Use
`haws migrate --show` to inspect the saved reference or `haws migrate --clear`
to preview removing just that reference. `--yes` confirms the displayed
operation. Clearing the reference does not delete the old checkout, state, or
Second Brain; it can also recover when the old checkout is no longer available.
`HAWS_REPO_DIR`, `HAWS_STATE_DIR`, and `HAWS_SECOND_BRAIN_DIR` remain
supported as explicit per-process overrides.

## Platform tools and verification

The package does not require a Go installation. Because component lifecycle
operations still use the existing runtime, Git and Bash 4.2 or newer are
required for Sync, setup, and integration work. Windows users need Git for
Windows; macOS users need a newer Bash such as Homebrew Bash because the
built-in Bash is 3.2. The shell runtime also uses standard POSIX tools such as
`awk`, `sed`, `grep`, `find`, `sort`, and `cmp`. Node.js is optional for the
core launcher and Sync, but is needed for native Codex agent profiles and some
AI-specific generated configuration. No production runtime Python dependency
was found in the inspected HAWS shell, Go, launcher, and adapter code.

The native Go binary and launcher can start without a source checkout. HAWS
does not install these system tools automatically.

CI is configured to test on native Windows, macOS, and Linux runners and to run
an extracted package lifecycle. A configured workflow is not evidence that a
run has completed; check the Actions results before treating a platform as
verified. Local cross-compilation alone does not verify native runtime
behavior.
