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
other applications. On macOS, this transitional Go application also needs Bash
4.2 or newer for actions that still use the legacy runtime; the launcher looks
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

This entry point makes the current transitional implementation testable; it
does not make the app fully native. Setup, Settings, Doctor, Repair, Sync
components, and Uninstall still call the legacy Bash runtime. The final Go
application must remove that dependency. Windows and Linux execution of this
development launcher remains `[Unverified]` until run on native systems.
