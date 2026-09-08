# HAWS CLI Redesign — Design Specification

> **Status:** Draft for user review. This document records confirmed decisions from the 2026-09-09 design discussion. It authorizes no implementation by itself.

## Goal

Redesign HAWS as a cross-platform interactive command-line application with one user entry point, `haws.sh`. It must make installation, configuration, synchronization, diagnosis, and device detachment clear without forcing choices or silently changing remote or user-owned data.

## Scope

This specification covers the HAWS command flow, interactive UX, persisted local state, source synchronization, status and diagnostics, and uninstall behavior.

It does not redesign individual skill content or solve agent-specific skill compatibility. Those issues are explicitly deferred until the end of the HAWS redesign.

## Confirmed Principles

- `haws.sh` is the one user-facing launcher on Windows (through Git Bash), macOS, and Linux. Windows `.bat` launchers are not part of the target design.
- A user is never forced to choose a configuration path. Every selection screen starts with useful HAWS defaults.
- Bulk selections support multiple items. The UI uses the existing terminal interaction style: arrow keys to move, Space to toggle, Enter to continue, plus Select all and Clear all.
- A default is a preselected value, not an action that runs immediately.
- `ai-configs/` contains only per-AI adapters, links, and registration compatibility. It must not duplicate HAWS rules, skills, agents, or personal context.
- Skills remain skill-first: an external source containing `SKILL.md` belongs under `skills/`, even when it also includes a CLI, MCP server, templates, or references.
- A newly downloaded source has all discovered skills active by default. An active skill is available to an AI; the AI selects it only when it matches the task. HAWS does not force every active skill to run for every task.
- Second Brain remains private and separate from the public HAWS repository.
- `README.md` is intentionally deferred until the product flow is stable.

## Current Behavior That Must Change

The current implementation is command-first:

```text
./haws.sh                 runs sync immediately
./haws.sh setup           opens the legacy setup menu
./haws.sh sync            runs sync
./haws.sh status          reports mostly skill counts
./haws.sh doctor          runs structural checks
./haws.sh uninstall       removes integrations
```

The current default command is `sync` (`COMMAND="${1:-sync}"` in `haws.sh`). It can contact remotes and change links/configuration merely by launching `haws.sh`; this is not the target behavior.

## Target User Flow

### First installation

```text
haws.sh
  -> Settings, populated with HAWS defaults
  -> Save & Apply
  -> Download selected sources and required dependencies
  -> Configure selected AI integrations and skill links
  -> Run Doctor
  -> Home
```

There is no separate Quick Setup versus Customize branch, and no separate Install button. `Save & Apply` is the action that installs a first-time setup.

### Normal use after installation

```text
haws.sh
  -> Home: compact Status summary
  -> Sync | Settings | Doctor | Status details | Exit
```

`Uninstall` is reached from Settings, not shown as a primary Home action.

Direct terminal commands remain available for automation and advanced users:

```text
haws.sh sync
haws.sh status
haws.sh doctor
haws.sh uninstall
```

### Settings

The same Settings interface is used for first installation and later changes. It contains:

```text
Default Setup
Source Repositories / KIT
Skills
AI Environments
Second Brain
Auto Update when Syncing
Save & Apply
Uninstall                 (only after installation)
```

`Default Setup` restores the HAWS defaults into the current Settings screen. It does not install, fetch, link, or overwrite anything until the user chooses `Save & Apply`.

KIT means a HAWS-provided selectable set of source repositories and skills. It does not mean every configuration default.

Later `Save & Apply` applies the local selections that changed. It is not a remote update command. A newly selected source may need to be downloaded, but existing sources are not updated merely because settings were saved.

### Selection UX

Use one predictable interaction model:

```text
Navigation:      Up/Down, Enter
Bulk checklist:  Up/Down, Space, A = Select all, C = Clear all, Enter
Boolean:         explicit On / Off control
Mutation:        Review screen, then Save & Apply or Confirm
```

Example:

```text
Select AI environments
Space: toggle   A: all   C: clear   Enter: continue

[x] Antigravity
[x] Codex
[x] Claude Code
[ ] Cursor
```

## Target Repository Layout

```text
Human-AI-Working-Standard/
├─ haws.sh                 # single public launcher
├─ .gitmodules             # external source registry / KIT sources
├─ .gitignore
├─ .gitattributes
├─ .githooks/
├─ core/                   # HAWS standards
├─ runtime/                # internal shell modules sourced by haws.sh
├─ ai-configs/             # AI-specific adapters only
├─ skills/                 # external skill sources and local skills
├─ agents/                 # agent role definitions
├─ templates/              # reusable project templates
├─ secondbrain/            # private, separate working context
└─ containers/             # container assets when needed
```

`runtime/` is an internal code boundary, not another launcher and not a platform-specific scripts directory. It may be kept small, for example:

```text
runtime/ui.sh              # navigation, checklist, review rendering
runtime/settings.sh        # settings and Save & Apply
runtime/operations.sh      # sync and uninstall orchestration
runtime/health.sh          # status and doctor checks
```

Platform differences must be isolated in one shared helper if needed; do not create separate Windows/macOS/Linux user workflows.

`HANDOFF.md` content belongs in Second Brain, for example `secondbrain/PROJECT_STATE.md`, after every template/reference that points at it has been updated. The root `HANDOFF.md` must not be moved until those references are migrated.

## Local State and Sources of Truth

| Concern | Target source of truth | Notes |
|---|---|---|
| Source repositories and KIT sources | `.gitmodules` | Versioned repository configuration. |
| Disabled AI environments | `ai-configs/environments.disabled` | Device-local and Git-ignored. Empty or absent means all detected environments are enabled. |
| Disabled skills | `skills/skills.disabled` | Holds disabled skill identifiers; empty or absent means all discovered skills are active. It must be treated as local selection state, not a shared accidental edit. |
| Second Brain and Auto Update choices | local HAWS settings file | Git-ignored and device-local. Exact serialization is an implementation decision. |
| Last sync outcome | local HAWS sync-state file | Git-ignored. Status reads it and never needs to contact remotes. |
| Sync mutual exclusion | local HAWS lock | Created only while a sync is running; released on completion or safe recovery. |
| HAWS-owned integrations | ownership record | Used by Uninstall to remove only links/configuration created by HAWS. |

The exact local settings and state filenames may be finalized in the implementation plan. They must live in one clear Git-ignored HAWS state location and must not be mixed into `ai-configs/`, except for the existing `environments.disabled` compatibility file.

## Skills and Sources

- Discover a skill through its accepted entrypoint, normally `SKILL.md`.
- Preserve source provenance: the UI must be able to identify the repository supplying each discovered skill and handle duplicate names without ambiguity.
- A source may contain multiple skills. The user can enable/disable individual skills after discovery.
- Sync decisions operate at repository revision level, but remote change relevance is evaluated by changed paths affecting active skills or files shared by them.
- A source with no active skills is skipped.
- If an incoming revision changes only inactive skills, skip updating that source.
- If an active skill update introduces a dependency, report it. Do not install packages silently.

## Sync

`Sync` is the cross-device/remote operation. It is the replacement for the old concept of a Windows-only “1-Click Sync.” It can be launched from Home or with `haws.sh sync`.

### Settings-controlled targets

- **Second Brain enabled:** sync the private Second Brain remote.
- **Second Brain disabled:** do not contact its remote and do not delete local notes.
- **Auto Update enabled:** check HAWS and eligible active-skill sources for updates.
- **Auto Update disabled:** do not perform source update checks.
- **Both disabled:** report `No remote targets enabled`; do not make a network request.

The Default Setup value for Auto Update is **On**.

### Required sync safeguards

1. Acquire the sync lock before any work. A second request must report that sync is already running rather than start a competing Git/link operation.
2. Inspect each eligible source for local staged, unstaged, or untracked changes before attempting an update. Skip only that source as `Blocked: local changes`; other targets continue.
3. Validate the candidate revision before making it active. An active skill must retain a usable entrypoint such as a nonempty `SKILL.md`. On validation failure, retain the last known usable revision and report `Failed: validation`.
4. Never install a newly required dependency without visible user action.
5. Run independent remote checks with bounded failure handling. A timeout/offline result affects only that target and must be reported truthfully.
6. Refresh links only after a relevant source update or a local selection change.

### Second Brain merge

Second Brain records use stable format and timestamps so independent records can merge automatically as a chronological union. A conflict is only an incompatible edit to the same logical record. That record reports `Needs resolution`; unrelated records and other sync targets continue.

### Per-target results

```text
Updated
Up to date
Skipped: no active skills
Skipped: inactive skills only changed
Offline / timeout
Blocked: local changes
Failed: validation
Disabled
Needs resolution
```

## Status and Doctor

Both commands use the same health classification:

```text
Ready       usable with no actionable problem
Attention   usable, but action is recommended
Blocked     an enabled function cannot continue safely
```

### Status

`Status` is the normal, fast, read-only overview. It does not contact a remote. It shows local configuration and the recorded outcome of the last sync.

```text
HAWS Status
Overall: Ready | Attention | Blocked
Last sync: result and timestamp

AI Environments
  Active: list of enabled AI environments
  Disabled: list of disabled AI environments

Skills: active count, disabled count, source count
Second Brain: enabled/disabled and last known result
Auto Update: on/off
Actions needed: concise list, if any
```

`haws.sh status --details` may show per-AI, per-source, and per-skill details.

### Doctor

`Doctor` is detailed, read-only diagnosis. It runs automatically after first installation and after a Sync that changed sources or links. It does not silently sync, repair, change configuration, or install packages.

Doctor checks only enabled/relevant components:

- configuration validity;
- selected AI adapter/link integrity;
- active skill entrypoints and destination links;
- active-skill source availability and local changes;
- Second Brain record format and Git state when enabled;
- required runtime dependencies, when an enabled integration requires them;
- ownership records needed for safe Uninstall.

Each finding states its level, the affected item, the cause, and a concrete next action.

## Uninstall

Uninstall is a Settings action:

```text
Settings -> Uninstall -> Preview -> Confirm -> Report
```

The default selection detaches every HAWS integration created on the current device:

- AI pointers/adapters;
- skill links;
- agent profiles;
- HAWS Git hooks;
- HAWS-owned local integration metadata.

The user may deselect individual groups before confirmation.

Uninstall preserves by default:

- the HAWS repository;
- downloaded skill source repositories;
- Second Brain files and its remote configuration;
- unrelated user AI configuration and user-owned files.

Before mutation, show the exact owned paths/actions. If a target is shared, user-modified, or cannot be proven HAWS-owned, preserve it and report the reason. After completion, verify that selected HAWS-owned integrations are absent and report removed and preserved items separately.

Deleting downloaded source repositories is a separate, explicitly selected destructive operation with an exact repository list; it is not part of default Uninstall.

## Migration Constraints

- Preserve existing device-local `ai-configs/environments.disabled` choices. Empty means all detected environments are enabled.
- Do not run setup, sync, brain sync, or push merely to inspect the codebase.
- Do not push any repository without explicit user authorization.
- Do not treat old `status` counts or `doctor` passes as end-to-end proof.
- The current `notify` command points at a missing `tools/notify.sh`; either supply a concrete shared implementation or remove the command from the redesign. Do not create a root `tools/` directory speculatively.
- Current direct root launchers (`SETUP.bat`, `1-CLICK-SYNC.bat`) are legacy Windows wrappers and must be retired only as part of the cross-platform migration, with documentation updated later.

## Acceptance Criteria

- First launch opens default-populated Settings and never syncs automatically.
- First `Save & Apply` installs only selected sources/integrations, then runs Doctor and reaches Home.
- Subsequent `Save & Apply` changes local selections without performing unrelated remote updates.
- Bulk selection screens support arrows, Space, Select all, Clear all, and defaults.
- Home provides Status summary and navigation to Sync, Settings, Doctor, Status details, and Exit.
- Status makes no network request and clearly distinguishes recorded last-sync state from current local state.
- Doctor reports actionable diagnostics without mutating configuration or installing packages.
- Sync honors Second Brain and Auto Update settings, locks concurrent runs, isolates per-source failures, and never overwrites local source changes.
- Inactive-only source changes do not cause a repository update.
- A candidate update that invalidates an active skill does not replace the usable revision.
- Uninstall previews targets, removes only HAWS-owned selected integrations, and preserves repositories, Second Brain, and user-owned files by default.
- The same `haws.sh` flow works through Bash on Windows, macOS, and Linux without platform-specific user launchers.

## Deferred Work

- Cross-agent skill compatibility, including sources that do not use the expected `SKILL.md` convention and agent-specific adapters.
- The final display naming, duplicate-name interaction details, and dependency presentation for newly discovered skills.
- README rewrite after the implementation and user-facing behavior are stable.

## Review Gate

The next chat must read this specification and inspect the current implementation before creating an implementation plan. It must not modify HAWS code until the user approves that plan.
