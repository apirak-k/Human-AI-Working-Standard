# HAWS Home, Health, and Sync UX Design

## Goal

Make the terminal UI easier to scan by using the clear, staged presentation of
the legacy one-click batch launchers while preserving the current HAWS safety
and state semantics.

## Interaction contract

- The shared footer is the only place that documents the `Q` key.
- `Q` returns to the parent menu from child menus and exits HAWS from Home.
- Checklists keep their existing cancel behavior, documented only in the footer.
- Menu labels and descriptions use a calculated fixed label column so every
  description starts at the same position.
- Exit rows are removed from interactive menus; the footer remains the exit
  affordance at the application boundary.

## Home and Health

Home presents a banner, a compact current-state summary, and four actions:
Sync, Health, Settings, and Uninstall. Health is the only health-related Home
action. It combines the current-state summary with read-only diagnostic
findings grouped by Settings, AI Environments, Ownership, Sources, Skills, and
Hooks. The existing `status` and `doctor` CLI commands remain compatible.

Health does not repair, install, synchronize, fetch, or push. It explains why
the current state is Ready, Attention, or Blocked.

## Sync presentation

Sync reads local state first. A single bounded network attempt is allowed per
target; when it times out or the network is unavailable, the target remains at
its current local revision and the result says `Local fallback`.

Sync behavior, locking, validation, and state writes remain unchanged. The
human-facing output is reorganized into OPTIONS, TARGETS, and SUMMARY sections.
Target results use aligned Target, Result, and Detail columns and the existing
measured result states. A final count summary is always printed.

## Acceptance and verification

- Focused tests cover footer behavior, Home actions, aligned descriptions,
  Health output, and Sync summary formatting.
- Existing CLI behavior for `status` and `doctor` remains tested.
- Run the full CLI and Node regression suites once after implementation; do not
  attach the full suite to commits or rerun it without a code change.
- Settings behavior is outside this change.
