# HAWS Recovery Plan for Antigravity

**Status:** Locked implementation plan  
**Execution style:** Strictly sequential — **one task at a time**  
**Recovery branch:** `recovery/clean-base`  
**Recovery parent:** `99c0d9d`  
**Mixed reference commit:** `40f8fad` on `codex/haws-cli-task1`  
**Old known-good UX reference:** `codex/haws-bootstrap`  
**Known-good interactive TUI reference:** `40f5f5a`

---

# 1. Core Goal

Recover HAWS into a clean baseline that preserves:

- the **newer HAWS flow and system**
- the **good UX improvements made later**
- the **pre-commit / Doctor loop fixes**
- the **known-good old interactive TUI experience**

while removing work that came from the wrong cross-platform architectural assumption.

The final direction is:

> Keep the old good Windows 1-click entry experience and old good interactive TUI behavior, but use the newer HAWS product flow, newer state model, newer UX, and shared HAWS core.

---

# 2. Important Architecture Rule

Different operating systems may use different native entrypoints.

That is allowed.

Expected final direction:

```text
Windows
haws.bat
    \
     \
      → Shared HAWS behavior/core → Same TUI → Same product flow

macOS / Linux
haws.sh
     /
```

The entrypoint may differ.

The following must remain equivalent across platforms:

- features
- product flow
- state semantics
- commands
- user-visible results
- TUI interaction quality

Do **not** force every OS to use the exact same launcher implementation.

---

# 3. What the User Means by “Old Good TUI”

The user specifically wants the interaction experience from the old 1-click Windows workflow.

Reference sources:

- Branch: `codex/haws-bootstrap`
- Windows launcher references:
  - `1-CLICK-SYNC.bat`
  - `SETUP.bat`
- Known-good interactive TUI reference:
  - commit `40f5f5a`

Desired behavior includes:

- `↑` / `↓` arrow-key navigation
- Enter to select
- Space to toggle checklist items where appropriate
- selection changes interactively in the same visible menu surface
- menu frames do **not** accumulate down the terminal
- no fake approximation of the old behavior using a degraded mechanism
- no unnecessary flicker
- the terminal should feel like an actual interactive TUI application

Important distinction:

> Preserve the **old interaction experience**, not the old product flow.

Do **not** restore old behavior such as:

```text
double-click
→ automatically sync
→ automatically run Doctor
```

The old `.bat` files are launcher/interaction references only.

---

# 4. New Product Flow That Must Be Preserved

## First run

```text
Launch HAWS
    ↓
Settings
    ↓
Edit Draft
    ↓
Preview
    ↓
Save & Apply
    ↓
Home
```

## Already installed

```text
Launch HAWS
    ↓
Home
    ├─ Settings
    ├─ Sync
    ├─ Status
    ├─ Doctor
    └─ Exit
```

Required semantics:

- Settings edits a draft first.
- Persistent state must not change before Apply.
- Preview must support clear Apply / Back / Cancel behavior.
- Back keeps the draft.
- Cancel discards the draft.
- Bare launch must not automatically sync.
- Sync is an explicit user action.
- Status is local/read-only.
- Doctor is local/read-only diagnostics.
- Doctor must not recursively invoke itself.
- Opening Settings alone should not trigger unnecessary network activity.

---

# 5. What Must Be Preserved From the Newer System

The recovery starts from `99c0d9d`.

Do not redesign these systems unless the current task explicitly requires it:

- install state
- settings state
- draft-before-Apply behavior
- ownership-aware behavior
- AI Environment selection
- Skills state
- Repository configuration
- Sync / Status / Doctor semantics
- Second Brain configuration
- Auto Update configuration
- newer Home / Settings flow

From work after `99c0d9d`, preserve only good changes that match the approved product direction, such as:

- loading/progress feedback
- short explanations and useful counts
- Skills UX improvements
- Single Skills / Multi-Skill Packs hierarchy
- clearer Preview / Apply / Back / Cancel behavior
- correct Apply → Home behavior
- responsiveness improvements
- lazy loading / caching where appropriate
- loop fixes
- regression tests that protect approved behavior

---

# 6. What Must NOT Be Carried Forward

Do not carry forward work that exists only because of the wrong architectural assumption that every OS must enter HAWS the same way.

Exclude or treat as reference-only:

- forcing Windows users to manually open Git Bash
- forcing Windows to behave like Unix at the launcher layer
- old command-integration experiments
- DOSKey / AutoRun work used to hide launcher differences
- platform-unification work that exists only to avoid native launchers
- old 1-click automatic sync flow
- business logic duplicated inside `.bat`
- tests/docs that require “one launcher implementation for every OS”
- the mixed `40f8fad` commit as a whole

Important:

> Recover behavior by concern. Do not recover entire mixed commits.

---

# 7. Git Safety Rules

Current intended starting state:

```text
branch: recovery/clean-base
HEAD:   99c0d9d
working tree: clean
```

Reference branch:

```text
codex/haws-cli-task1 @ 40f8fad
```

Old UX references:

```text
codex/haws-bootstrap
40f5f5a
```

Do not:

- rewrite old history
- reset old reference branches
- rebase old reference branches
- delete old branches
- force-push old history
- cherry-pick `40f8fad` as a whole

Old branches are historical/reference material.

---

# 8. STRICT EXECUTION RULE

## This rule is mandatory.

Antigravity must work on **exactly one task at a time**.

For every task:

1. Read the task scope.
2. Inspect only the references needed for that task.
3. Make only the changes allowed by that task.
4. Run the specified tests.
5. Report exactly what changed.
6. **STOP.**
7. Tell the user that the task is finished.
8. Wait for the user to explicitly say to continue.

Do **not** automatically start the next task.

Do **not** “helpfully” fix unrelated failures.

If an unrelated problem is discovered:

> Report it, but do not fix it unless the user explicitly starts a task for it.

If a task appears to require redesigning an already approved layer:

> STOP and report the conflict before making that redesign.

---

# 9. Work Breakdown

## TASK 1 — Loop Fix Only

### Goal

Fix only the recursion/hang problem that prevents reliable commits and Doctor execution.

### Allowed changes

Only changes required for:

- pre-commit recursion/hang fix
- `run_doctor` recursion fix

### Reference

Compare:

- base: `99c0d9d`
- mixed reference: `40f8fad`

Extract only the minimal loop-related fix.

### MUST NOT change

- TUI
- loading/progress UX
- Skills UX
- Settings UX
- Preview/Home behavior
- `.bat`
- command integration
- OS architecture
- unrelated test failures

### Tests

Run targeted tests that demonstrate:

- pre-commit does not hang/loop
- Doctor does not recursively invoke itself

Broader tests may be run for observation, but unrelated failures must only be reported.

### Deliverable

Report:

1. files changed
2. exact reason for each change
3. test commands
4. test results
5. any unrelated failures discovered

Then:

> **STOP and wait for user approval.**

---

## TASK 2 — Approved UX Improvements Only

Start this task **only after the user approves Task 1**.

### Goal

Recover approved UX improvements made after `99c0d9d`, without changing the TUI mechanism yet and without touching OS launchers.

### Include

- visible loading/progress feedback
- short descriptions
- useful counts
- Skills hierarchy improvements
- Single Skills / Multi-Skill Packs UX
- pack selection UX
- Preview / Apply / Back / Cancel corrections
- correct Apply → Home behavior
- no duplicate Home presentation
- responsiveness / lazy loading / caching improvements that are not OS-specific

### MUST NOT change

- loop fix unless a regression is directly caused by this task
- known-good TUI implementation/mechanism
- Windows `.bat`
- command integration
- OS architecture

If changing UX appears to require changing TUI behavior, stop and report that dependency rather than implementing it here.

### Tests

Run UX/state tests relevant to the changed behavior.

### Deliverable

Report:

1. files changed
2. UX behavior recovered
3. tests run
4. test results
5. any conflicts or unrelated failures

Then:

> **STOP and wait for user approval.**

---

## TASK 3 — Known-Good TUI Behavior Only

Start this task **only after the user approves Task 2**.

### Goal

Restore/preserve the known-good interactive TUI behavior.

### Required references

Inspect:

- `codex/haws-bootstrap`
- commit `40f5f5a`
- old known-good interactive checklist/menu implementation

### Required behavior

- arrow-key navigation
- Enter selection
- Space toggle where appropriate
- in-place interactive menu experience
- no accumulating duplicate menu frames
- no unnecessary flicker
- preserve the old good TUI feel

### Critical rule

Do not invent a new mechanism merely to imitate the visual result if the known-good historical mechanism can be reused or adapted.

This is the user's “video vs fast-scrolling paper” rule:

> If the old good behavior was the equivalent of a real video, do not replace it with rapidly scrolling paper just because the output looks similar.

### MUST NOT change

- Windows `.bat`
- OS launcher architecture
- approved flow
- approved state model
- Task 1 loop fix
- Task 2 UX semantics unless necessary to integrate the TUI correctly

If integration requires changing an approved layer, stop and report first.

### Tests

- automated TUI tests where feasible
- manual test instructions for real terminal interaction

### Deliverable

Report:

1. historical mechanism used as reference
2. files changed
3. exact TUI behavior achieved
4. automated tests
5. manual acceptance steps

Then:

> **STOP and wait for user approval.**

---

## TASK 4 — Clean Base Validation Only

Start this task **only after the user approves Task 3**.

### Goal

Validate the recovered Clean Base.

### No new features

Do not add new functionality in this task.

### Validate

- loop fix
- new product flow
- Settings draft behavior
- Preview / Apply / Back / Cancel
- Home behavior
- loading/progress UX
- Skills UX
- known-good TUI interaction
- Status semantics
- Doctor semantics
- no OS wrong-turn work included
- no new `.bat` implementation yet

Run the relevant regression suite.

### Deliverable

Report:

- complete test results
- remaining failures
- whether each failure is in-scope or pre-existing
- manual acceptance checklist

Then:

> **STOP. The user must approve the Clean Base before any Windows launcher work begins.**

---

## TASK 5 — Windows `.bat` Entry Only

Start this task **only after the user explicitly approves the Clean Base**.

### Goal

Create a first-class Windows launcher that preserves the convenience of the old 1-click experience but enters the new HAWS flow.

Desired behavior:

```text
double-click haws.bat
        ↓
locate required runtime automatically
        ↓
invoke shared HAWS behavior/core
        ↓
new TUI / new flow
```

### Reference

Use the old launcher patterns from:

- `codex/haws-bootstrap`
- `1-CLICK-SYNC.bat`
- `SETUP.bat`

as implementation references only.

### `.bat` may

- locate Bash/runtime
- locate repository root
- forward arguments
- invoke shared HAWS
- propagate exit codes
- display clear missing-dependency errors

### `.bat` must not

- implement Settings logic
- implement Sync logic
- implement Doctor logic
- duplicate state management
- create a separate TUI engine
- automatically sync on bare launch

### Required command parity

```text
Windows                 macOS/Linux
haws.bat                ./haws.sh
haws.bat settings       ./haws.sh settings
haws.bat sync           ./haws.sh sync
haws.bat status         ./haws.sh status
haws.bat doctor         ./haws.sh doctor
```

Bare launch:

```text
First run  → Settings
Installed  → Home
```

### Deliverable

Report Windows tests and manual acceptance steps.

Then:

> **STOP and wait for user approval.**

---

## TASK 6 — Cross-Platform Parity

Start only after Task 5 approval.

Verify equivalent behavior across Windows and macOS/Linux.

Check:

- first run
- Home
- TUI
- Settings
- Preview/Apply
- Sync
- Status
- Doctor
- error handling

Different platform implementation is acceptable.

Different product behavior is not.

Then:

> **STOP and wait for user approval.**

---

## TASK 7 — Documentation and Final Validation

Start only after cross-platform parity is approved.

Update documentation to:

- give OS-specific launch instructions
- explain that launchers differ by platform
- explain that HAWS behavior/core is shared
- remove instructions that force Windows users to manually launch Git Bash
- preserve clear Windows/macOS/Linux instructions

Run final regression tests.

Do not merge to `main` automatically.

Report final status and wait for the user to decide whether to merge.

---

# 10. Antigravity Start Instruction

When first given this plan, do **not** execute the entire plan.

Start with:

> **TASK 1 — Loop Fix Only**

Before editing, confirm:

```text
branch = recovery/clean-base
HEAD   = 99c0d9d
```

If either is different:

> STOP and report the current Git state.

After Task 1 is finished:

> Report results and STOP.  
> Do not begin Task 2 until the user explicitly asks you to continue.

---

# 11. Global Stop Rule

At every stage:

> If you discover something outside the current task scope, report it without fixing it.

> If completing the task requires redesigning a previously approved layer, stop and ask the user.

> Never advance to the next task automatically.

---

# 12. One-Line Project Summary

> Recover the new HAWS system and flow from `99c0d9d`, selectively keep good later UX and loop fixes, preserve the old known-good 1-click TUI experience, discard the OS wrong-turn work, validate the Clean Base, and only then add a thin Windows `.bat` entrypoint for the new system.
