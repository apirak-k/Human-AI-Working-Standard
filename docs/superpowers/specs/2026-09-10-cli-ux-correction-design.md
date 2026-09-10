# HAWS CLI UX Correction Design

**Status:** Draft for user review. This document refines, but does not replace,
the approved CLI UX design dated 2026-09-10.

## Purpose

Correct the terminal interaction defects discovered during manual Windows Git
Bash use while retaining the approved safe runtime model: draft settings,
Preview before Apply, separate Sync, and read-only Status and Doctor.

This work changes the UI only after `haws.sh` is running. Cross-platform
launchers, `.bat` files, Go, and adapters are out of scope.

## Interaction Contract

- A cursor menu is one screen. Up/Down redraws that screen in place and moves
  only the `>` marker; it must not append another copy of the menu.
- Catalog work visibly reports its current phase, for example `Loading skills
  catalog...`, before the selectable screen is available. A completed scan
  replaces that transient message with the resulting screen.
- Checklist controls are Up/Down to move, Space to toggle, Enter to confirm
  that screen's draft, and Q/Back to abandon unconfirmed edits on that screen.
- Confirmed checklist selections remain in the overall Settings draft until
  Preview followed by Apply. They are not persisted by checklist confirmation.
- A Back action preserves confirmed Settings draft values. Cancel Setup or
  Cancel Update discards the entire Settings draft.

## Skills Navigation

The Skills page shows only two category rows and their aggregate active
counts. It does not display individual pack names.

```text
HAWS Settings — Skills

> Single Skills             5 / 5 active
  Multi-Skill Packs        40 / 45 active
  Back to Settings
```

`Single Skills` opens one checklist containing every single skill.

`Multi-Skill Packs` opens a pack picker. This is the first and only screen
that lists pack names and their per-pack counts.

```text
HAWS Settings — Multi-Skill Packs

> agent-skills          25 / 25 active
  superpowers           14 / 14 active
  planning-with-files    1 /  6 active
  Back to Skills
```

Selecting a pack opens a checklist containing only that pack's skills. Enter
returns to the pack picker and updates the in-memory Settings draft. Q/Back
returns to the pack picker without applying changes made since entering that
checklist. Counts on both parent screens reflect the current draft whenever
they are redrawn.

The catalog remains the only source of skill IDs, names, descriptions,
provenance, pack membership, and active state. Aggregate Multi-Skill Pack
counts are the sum of every skill whose catalog source has more than one skill.

## Review, Apply, and Home Corrections

- Review must present three explicit actions: Apply, Back to Settings, and
  Cancel. Back retains the full draft; Cancel discards it.
- Apply reports only actions actually performed and ends each with Done,
  Skipped, Blocked, or Failed plus a reason.
- Choosing Home after a successful Apply enters the Home menu immediately.
- Home renders exactly one cursor menu; it must not print a static list before
  rendering the interactive list.

## Verification

Fixture-only tests must cover in-place menu redraw, transient loading output,
category aggregate counts, pack picker membership, pack-local checklist
selection, draft preservation and discard behavior, Review Back/Cancel, and
the Apply-to-Home transition. Manual acceptance remains a separate Windows
Git Bash session: one `bash haws.sh settings` process, arrow navigation,
pack-level selection, Preview, Apply, and Home.

## Non-goals

- No launcher or shell selection work.
- No `.bat`, Go, or adapter implementation.
- No real-home installation, remote calls, or push.
- No change to the Task 1–9 safety model or catalog data model.
