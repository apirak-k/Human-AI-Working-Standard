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

The default Health view uses compact section summaries and `[PASS]` markers
without alignment padding inside the brackets. Long paths stay available to
the CLI detail view, while the interactive result screens use one-key return
navigation so the user always has a clear next action.

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
Target results use aligned Target, Result, and Detail columns, with batch-style
`[PASS]`, `[WARN]`, `[BLOCKED]`, and `[FAIL]` markers paired with the existing
measured result states. A final count summary is always printed.

## Bootstrap-aligned orchestration

The bootstrap checkout is a workflow reference, not a source-code replacement.
The current implementation keeps its settings draft/apply boundary,
source-aware catalog, ownership checks, sync lock, deadline, candidate
validation, branch preservation, and read-only Health behavior.

Explicit integration and Sync expose one concise sequence:

1. Prepare local state and synchronize bounded source work.
2. Detect environments and configure their HAWS pointers.
3. Link active skills, native profiles, commands, and prune removed entries.
4. Configure the `commit-msg` Git hook when `.githooks` is present.
5. Show the final summary and result.

Opening HAWS does not run Sync or Doctor automatically. Settings still writes
only at final Apply/Install/Update; the legacy `skills`, `status`, and `doctor`
CLI routes remain for compatibility. Settings Single Skills uses the same
checklist renderer as the other selectors, including a redraw frame that
contains every row and the footer together.

## Acceptance and verification

- Focused tests cover footer behavior, Home actions, aligned descriptions,
  Health output, and Sync summary formatting.
- Existing CLI behavior for `status` and `doctor` remains tested.
- Run the full CLI and Node regression suites once after implementation; do not
  attach the full suite to commits or rerun it without a code change.
- Settings behavior is outside this change.
