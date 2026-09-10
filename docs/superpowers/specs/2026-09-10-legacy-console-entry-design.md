# HAWS Legacy Console Entry Design

**Status:** Approved outcome; implementation pending.

## Goal

Keep the historic Setup experience as the user-facing baseline and add the
completed Task 1–5 capabilities without requiring the user to open Git Bash,
use a `.bat` file, or run an `.exe` launcher.

## User Contract

On every supported system the user opens the system terminal and runs:

```text
haws
```

On Windows this is Command Prompt and the visible session is a Windows console
with the historic HAWS layout and prompt-driven interaction. On macOS and
Linux this is the native user terminal. The Bash core may remain an internal
runtime dependency on Windows; the user is never directed to launch Git Bash.

Historic Setup flow and behavior remain the baseline. Task 1–5 additions
(draft settings, Preview before Apply, Home, Sync, Status, and Doctor) are
added to that flow; they do not replace it with a Git-Bash cursor-menu UX.

## Command Integration

Command integration is installed only after Preview and Apply, is shown in
Preview, is scoped to the current user, and is fully removed only when HAWS
owns it.

- Windows: preserve any existing `HKCU\\Software\\Microsoft\\Command Processor`
  `AutoRun` value, append one HAWS-owned `doskey haws=...` macro that invokes
  the discovered Git-for-Windows `bash.exe` and HAWS `haws.sh`, and record the
  exact prior value in HAWS state. Uninstall restores that exact prior value.
- macOS: add a marked HAWS function to the active supported shell profile
  (`.zshrc` for zsh, `.bashrc` for bash); the function invokes the absolute
  HAWS core path. Uninstall removes only the marked block.
- Linux: add the same marked function to `.bashrc` or `.zshrc` for the active
  supported shell. Uninstall removes only the marked block.

If Bash is unavailable, Preview reports Command Access as Blocked with the
reason and Apply does not create partial integration.

## Legacy Presentation Contract

The terminal renderer follows the historic Setup model: textual headings,
status lines, numbered prompts, loading messages, aligned status columns, and
one continuous session. It must not use full-screen ANSI cursor redraw as the
primary interaction model. Existing draft/Preview/Apply safety is retained.

## Acceptance

Windows manual acceptance is:

1. Open Command Prompt, run `haws`.
2. Confirm the historic-style HAWS screen appears without Git Bash/Mintty.
3. Enter Skills, choose a pack, change a draft selection, Preview, Apply, and
   enter Home.
4. Open a new Command Prompt and run `haws` again.

macOS/Linux acceptance is the equivalent native-terminal `haws` command.

## Non-goals

- Do not delete, replace, or require removal of historic `.bat` entrypoints.
- Do not add a `.bat` or `.exe` as the new required entrypoint.
- Do not rewrite the HAWS Bash core or Task 1–5 features.
- Do not push, contact a remote, or modify a real user profile in automated
  tests.
