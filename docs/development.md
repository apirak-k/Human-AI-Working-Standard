# Running HAWS from a development checkout

This runs the real Go HAWS application built from the current checkout. Each
launch rebuilds the Go executable and refreshes an isolated copy of the HAWS
runtime, so it does not open or modify the HAWS installation already on the
computer. The Go app starts Setup if it finds no saved setup marker or
settings, then opens Home. Later launches open Home directly. Existing saved
settings also count as an existing installation.

## macOS and Linux

From the repository directory, run:

```sh
./scripts/dev-haws.sh
```

On the first run, HAWS opens Setup in the development sandbox and then opens
the Home menu when Setup completes. A command can also be passed through for a
specific test, for example:

```sh
./scripts/dev-haws.sh doctor --deep
```

If Go 1.26 or newer is already available, the launcher uses it. Otherwise it
downloads the pinned Go 1.27.3 toolchain into the user's cache after checking
the official SHA-256. It does not add Go to the system PATH or install it for
other applications. Setup and Settings editing run in Go. Applying integration
changes still needs Git and Bash 4.2 or newer for component Sync. The launcher looks
for `~/.local/bin/bash`, Homebrew Bash, and then Bash on `PATH`.

## Windows

From PowerShell in the repository directory, run:

```powershell
.\scripts\dev-haws.ps1
```

If PowerShell blocks the local script, run it for this process only:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\dev-haws.ps1
```

The launcher uses Go 1.26 or newer when available; otherwise it verifies and
caches the pinned Go 1.27.3 toolchain under the current user's Local AppData.

## Isolation

The sandbox is stored in the user's cache under `HAWS/development-sandbox-live`
(override its location with `HAWS_DEV_HOME`). It contains its own runtime
checkout, settings, AI configuration home, state, and Second Brain directory.
The launcher also removes the current user's Git, SSH, GitHub, and AI API
credential overrides from the HAWS process. The sandbox persists across runs
so test settings remain available. Use only sandbox paths when trying
operations that accept an arbitrary destination.
Opening the app does not download all skill repositories. First-run Setup may
fetch them through HAWS's normal source flow, using the sandbox checkout and
without the user's Git credentials.

Setup and Settings now use native Go drafts, Preview, state persistence,
repository configuration, and Second Brain connect/disconnect. The existing
TSV formats and source-aware skill selections remain compatible with Bash.
Updating only configuration on an installed system needs no Bash executable.
When integration changes are required, Apply saves pending progress and runs
one Go-hosted component Sync; that component runtime still uses Bash.

If an apply was interrupted, Settings shows the approved plan and progress.
Choose Retry to finish those approved actions, or explicitly discard the
unfinished actions before editing a new draft. Personal files are retained.
A failed first installation is never marked complete; successful Sync retry
finishes its completion marker after all Settings actions have completed.

Doctor, Repair, component Sync, client integration application, and full
Uninstall remain legacy-backed. Native Windows/Linux execution is verified
separately through CI; cross-compilation alone is not runtime acceptance.
