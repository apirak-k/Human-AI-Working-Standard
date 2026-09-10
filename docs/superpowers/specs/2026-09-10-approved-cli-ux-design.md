# HAWS Approved CLI UX Design

**Status:** Approved for implementation on 2026-09-10.

## Purpose

Restore the clear, keyboard-first terminal experience the user approved in
the historic Windows batch-launched HAWS flow while keeping the safe Task 1–9
runtime model: draft settings, Preview before Apply, ownership-aware
uninstall, separate Sync, and read-only Status and Doctor.

The Windows launcher decision (`.bat` versus opening Git Bash) is explicitly
deferred. This design covers only the UI after `haws.sh` is running.

## Global interaction contract

- Menus use Up/Down to move and Enter to open or activate the focused row.
- Multi-select screens use Up/Down, Space to toggle, Enter to confirm, and a
  visible `Select All` row. It shows `[ ]`, `[-]`, or `[x]`.
- `Back` returns to the parent screen without discarding choices already
  confirmed in the current Settings draft.
- `Cancel Setup` / `Cancel Update` discards the entire in-memory draft and
  makes no change.
- Settings changes are drafts. Only Preview followed by `Install HAWS` or
  `Apply Update` may change local state, integrations, repository registry,
  or a Second Brain remote.
- Every operation that loads, checks, connects, installs, updates, skips, or
  fails reports truthful progress and a useful reason. Read-only screens must
  not claim that they are synchronizing.

## First install and Settings

The first launch enters `HAWS Settings — First Install` directly; it does not
offer a separate Quick Setup landing page and never syncs or writes merely by
opening.

```text
HAWS Settings — First Install

> Repositories            8 sources
  Skills                  127 active
  AI Environments         2 selected
  Second Brain Remote     [ Off ]
  Auto Update             [ On ]
  Preview Install
  Restore Recommended Defaults
  Cancel Setup

Up/Down Move   Enter Open/Toggle   Q Cancel
```

The installed Settings screen has the same rows and behavior, changes
`Preview Install` to `Preview Update`, and includes `Uninstall HAWS` as a
separate guarded action. Recommended defaults change the draft only.

## Repositories

`Repositories` reports a count of configured sources; it is never a
checklist of selected repositories.

```text
HAWS Settings — Repositories

> Add Repository
  Remove Repository
  Back to Settings
```

Add collects a repository URL into the draft. Remove uses a multi-select list
of current sources and records intended removals in the draft. Neither action
edits `.gitmodules`, initializes a source, deletes a checkout, or contacts a
remote before Preview and Apply.

## Skills

Skills retain the historic category-first flow:

```text
HAWS Settings — Skills

> Single Skills
  Multi-Skill Packs
  Back to Settings
```

Each category opens a checklist with `Select All`, skill rows, `Apply
Selection`, and `Back`. Applying a selection updates only the Settings draft.
The existing catalog remains the source of IDs, names, provenance, active
state, and the classification required to render the two categories.

## AI Environments

AI environments are a checklist of all supported adapters. Each row displays
`Detected` or `Not detected`. Both kinds remain selectable so a user can
prepare a configuration before installing an environment. Confirming changes
only the draft.

## Second Brain Remote and Auto Update

`Second Brain Remote` does not turn the local Second Brain on or off. Off
means local-only: its local files remain intact and its remote is not
contacted. On means the private remote is eligible for Sync.

If the user turns it On and this device has no configured remote, the UI asks
for a remote URL, tests connectivity without saving it, and holds the URL and
test result in the draft. The remote is created or changed only after Preview
and Apply.

`Auto Update` remains a single On/Off toggle and includes HAWS itself together
with eligible source updates. A user-initiated `Sync Now` always checks HAWS
for an available update; with Auto Update Off it does not update skill/source
repositories. This explicit manual-Sync exception replaces the narrower
Task 1–9 interpretation that both Off disables every remote target.

## Preview and Apply

First installation uses `Preview Install`; later changes use `Preview Update`.
The review compares current and draft values, separates additions, removals,
and setting changes, and explicitly lists what will not be changed. It offers
Apply, Back to Settings, and Cancel. Existing sources are not remotely updated
as a side effect of Settings Apply.

Apply shows only actions that actually occur, each ending in Done, Skipped,
Blocked, or Failed with a reason. On success it offers Home, Settings, and
Exit. It must enter Home immediately when the user chooses that action.

## Home, Sync, Status, and Doctor

```text
HAWS Home

Status: Ready
Last sync: ...
Repositories: 8 sources
Skills: 127 active
AI Environments: 2 active
Second Brain Remote: Off
Auto Update: On

> Sync Now
  Settings
  Doctor
  Status Details
  Exit
```

`Sync Now` is an explicit remote operation. Its visible steps are conditional:

- It always checks HAWS for an update because the user explicitly invoked it.
- When Auto Update is On, it also checks eligible active-skill source
  repositories and updates only validated, safe candidates.
- When Second Brain Remote is On, it also synchronizes the private Second
  Brain remote.
- When both toggles are Off, it still performs the HAWS check and clearly
  reports that local-only Second Brain and source updates were skipped.

`Status Details` renders locally recorded installation, configuration, and
last-sync facts only. `Doctor` performs detailed, read-only local diagnostics.
Neither makes a network request or changes files.

## Non-goals and safeguards

- Do not restore immediate legacy Quick Setup, destructive cleanup, direct
  `.gitmodules` editing, or manifest-driven deletion.
- Do not restore multiple `.bat` launchers in this work; launcher choice is
  deferred.
- Do not alter locked HAWS standards, AI-config architecture, skills
  architecture, or root repository structure.
- Do not test against the user’s actual home directory or remotes without a
  separate explicit authorization.
