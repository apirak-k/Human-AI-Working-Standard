# HAWS Recovery and UX/TUI Implementation Specification

**Document status:** Authoritative implementation contract for the current HAWS recovery work  
**Language:** English  
**Primary executor:** Antigravity  
**Execution model:** Strictly sequential, one task at a time  
**Recovery branch:** `recovery/clean-base`  
**Recovery parent:** `99c0d9d`  
**Mixed historical reference:** `40f8fad` on `codex/haws-cli-task1`  
**Old known-good UX/TUI reference branch:** `codex/haws-bootstrap`  
**Known-good interactive TUI reference:** `40f5f5a`  
**Old Windows launcher references:** `1-CLICK-SYNC.bat`, `SETUP.bat`

---

# 0. READ THIS FIRST — EXECUTION CONTRACT

This document is not a suggestion. It is the implementation contract for the HAWS recovery.

Antigravity must follow these rules exactly:

1. **Do one task only.** Never start the next numbered task automatically.
2. **Stop after every task and report.** Wait for explicit user approval before continuing.
3. **Do not redesign approved behavior.** If implementation appears to require redesigning an approved layer, STOP and report the conflict.
4. **Do not restore old code wholesale.** Historical branches, commits, and files are references, not patches to copy blindly.
5. **Inspect historical known-good implementations before inventing a replacement.** If a behavior already worked well historically, reuse or minimally adapt that mechanism.
6. **Keep good historical mechanisms, not bad historical product behavior.** Old interaction quality may be reused; old automatic setup/sync/Doctor flows must not be restored.
7. **Never cherry-pick `40f8fad` wholesale.** It contains unrelated UX, loop, console-entry, and OS experiment work mixed together.
8. **Do not mix OS launcher work into the shared core recovery.** Windows launcher work belongs to Task 5 only.
9. **Do not make persistent state changes from Settings before final Install/Update confirmation.** Settings edits a draft.
10. **Do not mutate user-owned files outside HAWS ownership.** HAWS may clean up only HAWS-owned files/state according to this spec.
11. **Do not silently broaden scope to fix unrelated failures.** Report unrelated failures separately.
12. **Do not implement future ideas that are not explicitly specified here.** Preserve current approved behavior where this document is silent.

If any instruction in an older recovery plan conflicts with this document, **this document wins** because it contains the latest approved product/UX decisions.

---

# 1. PROJECT DIRECTION

HAWS must combine:

- the newer HAWS product flow and state model,
- approved later UX improvements,
- the pre-commit / Doctor loop fixes,
- the known-good old interactive TUI experience,
- a shared HAWS behavior/core across platforms,
- platform-appropriate thin launchers.

The final architecture direction is:

```text
Windows
haws.bat
    \
     \
      -> Shared HAWS behavior/core -> Same TUI behavior -> Same product flow

macOS / Linux
haws.sh
     /
```

The launcher implementation may differ by OS.

The following must remain equivalent across supported platforms:

- features,
- product flow,
- state semantics,
- commands,
- user-visible results,
- TUI interaction quality.

Do **not** force Windows to enter HAWS through the same native mechanism as macOS/Linux.

---

# 2. HISTORICAL REUSE POLICY

## 2.1 General rule

For every historical behavior referenced in this document:

```text
Inspect old implementation
        ↓
Identify the known-good mechanism
        ↓
Compare with this specification
        ↓
Reuse directly if compatible
        OR
Minimally adapt if required
        ↓
Do not restore unrelated old behavior
```

Do not copy an entire historical file just because one useful behavior exists inside it.

## 2.2 Known-good references and what they are for

### `codex/haws-bootstrap`
Use as a reference for:

- old good Windows 1-click interaction quality,
- historical launcher behavior/patterns,
- known-good terminal interaction patterns.

Do **not** restore its old product flow automatically.

### Commit `40f5f5a`
Use as the primary interactive TUI/checklist reference for:

- `↑` / `↓` navigation,
- Enter selection,
- Space checklist toggle,
- `q` / `Q` handling,
- interactive selection changes on the same visible menu surface,
- multi-selection behavior where historically applicable,
- avoiding duplicate menu frames accumulating down the terminal.

Reuse/adapt the mechanism rather than recreating a visually similar approximation.

### `1-CLICK-SYNC.bat` and `SETUP.bat`
Use only for Task 5 launcher reference such as:

- finding required runtime/tooling,
- locating repository/root paths,
- convenient Windows double-click entry,
- forwarding into shared HAWS behavior.

Do not copy old Settings, Sync, Doctor, or product-flow logic into the new launcher.

### Commit `40f8fad`
Use selectively as a source/reference for good later work such as:

- loop-related fixes,
- loading feedback,
- responsiveness improvements,
- useful descriptions/counts,
- Skills UX improvements,
- Preview/Apply/Back/Cancel corrections,
- correct post-apply behavior,
- lazy loading/caching where appropriate.

Do not cherry-pick the commit wholesale.

## 2.3 Historical behavior that must NOT be restored

Do not restore old flows such as:

```text
double-click
-> automatic setup or automatic sync
-> automatic Doctor
```

Do not restore:

- bare-launch auto-sync,
- automatic Doctor after launch,
- duplicated Settings logic inside `.bat`,
- duplicated Sync logic inside `.bat`,
- duplicated state machines per OS,
- forcing Windows users to manually use Git Bash as the normal launcher experience,
- OS work created only from the incorrect assumption that every OS must enter HAWS the same way,
- degraded TUI mechanisms that only imitate the old appearance.

---

# 3. LOCKED PRODUCT FLOW

## 3.1 First install

The latest approved first-install flow is:

```text
Launch HAWS
    ↓
HAWS Setup
    │
    ├─ Use Default Setup
    │       ↓
    │   create draft
    │       ↓
    │   Preview Install
    │       ↓
    │     Install
    │       ↓
    │    HAWS Home
    │
    └─ Customize Settings
            ↓
        HAWS Settings
            ↓
           Apply
            ↓
       Preview Install
            ↓
          Install
            ↓
         HAWS Home
```

The Setup landing page is intentionally lifecycle-specific. The Settings page itself is not.

## 3.2 Already installed

```text
Launch HAWS
    ↓
HAWS Home
    ├─ Sync
    ├─ Settings
    ├─ Doctor
    ├─ Status Details
    └─ Exit

Settings path:

HAWS Home
    ↓
Settings
    ↓
HAWS Settings
    ↓
Apply
    ↓
Preview Update
    ↓
Update
    ↓
HAWS Home
```

There must not be an `Apply Update` after an `Apply` button. The approved vocabulary is:

```text
Settings -> Apply -> Preview Install -> Install
Settings -> Apply -> Preview Update  -> Update
```

---

# 4. STATE MODEL — LOCKED

HAWS must distinguish persistent state from editable draft state.

```text
Persistent Configuration
        ↓ copy
Settings Draft
        ↓ optional local working state
Subpage Working State
```

Rules:

1. Opening Settings creates/loads a Settings Draft.
2. Changes inside Settings modify the draft only.
3. Some subpages may use temporary local working state until the user confirms that subpage.
4. Returning from a subpage after confirmation writes the subpage result into the Settings Draft only.
5. `Apply` from the main Settings page does **not** persist changes. It proceeds to Preview.
6. `Back to Settings` from Preview preserves the draft.
7. Final `Install` or `Update` is the point where approved changes may become persistent.
8. `Discard Changes` destroys the Settings Draft and returns to the caller.
9. No network sync should start merely because Settings was opened.
10. No persistent mutation should occur just because a checkbox/toggle was changed in Settings.

---

# 5. FIRST-INSTALL SETUP PAGE — LOCKED

Use consistent `Default` terminology. Do not use `Recommended` terminology on this page.

Example target presentation:

```text
HAWS Setup

No changes have been made to this computer.

Default Setup

Repositories        Default
Skills              Default
AI Environments     Default
Second Brain Remote Off
Auto Update         On

> Use Default Setup
  Customize Settings
  Exit

↑/↓ Move   Enter Select   Q Exit
```

Notes:

- `Repositories`, `Skills`, and `AI Environments` all use the word `Default` here.
- Do not prematurely show invented counts if the metadata has not actually been loaded.
- `Use Default Setup` creates the default draft and moves to Preview Install.
- `Customize Settings` creates the default draft and opens the shared HAWS Settings page.
- No computer changes occur before Install.

---

# 6. HAWS SETTINGS — AUTHORITATIVE LOCKED SPEC

The Settings specification is closed and approved. Do not redesign it during implementation.

## 6.1 Lifecycle-neutral Settings

The Settings page must not present itself as a different page before vs. after installation.

Do not use titles such as:

- `HAWS Settings — First Install`
- `Installed Settings`

Use:

```text
HAWS Settings
```

The page should not need separate user-visible wording such as `Preview Install` vs. `Preview Update` inside the main Settings page.

The lifecycle-aware controller/flow decides which Preview is shown after `Apply`.

## 6.2 Main Settings page

Target information architecture:

```text
HAWS Settings

> Repositories             8 sources
  Skills                 127 active
  AI Environments          2 selected
  Second Brain Remote    [ Off ]
  Auto Update            [ On  ]

  Apply
  Reset to Defaults
  Discard Changes

↑/↓ Move   Enter Select   Space Toggle   Q Back
```

The exact counts are data-driven; do not hard-code the example numbers.

## 6.3 Main Settings vocabulary

Use:

- `Apply`
- `Reset to Defaults`
- `Discard Changes`

Do not use on the main Settings page:

- `Save`
- `Preview Install`
- `Preview Update`
- `Apply Update`
- `Cancel Setup`
- `Restore Recommended Defaults`
- `Reset to Recommended Defaults`
- `Uninstall HAWS`

`Uninstall` is a lifecycle/destructive operation and is not part of this shared Settings page.

## 6.4 Meaning of Apply

`Apply` means:

> Accept the current Settings Draft as the draft to preview next.

It does **not** mean:

> Modify the computer now.

Flow:

```text
HAWS Settings
   ↓ Apply
Preview
   ↓ Install OR Update
Persistent changes
```

## 6.5 Reset to Defaults

`Reset to Defaults` must require confirmation.

Example:

```text
Reset Settings to Defaults?

This will replace the current draft.
Nothing will be changed on this computer yet.

> Reset
  Cancel
```

After confirmation:

- replace the Settings Draft with Default values,
- do not persist anything yet,
- remain within the draft/Settings flow.

## 6.6 Discard Changes

`Discard Changes` means:

- destroy the current Settings Draft,
- do not persist it,
- return to the caller.

Caller behavior:

```text
First install:
Setup -> Settings -> Discard Changes -> Setup

Installed:
Home -> Settings -> Discard Changes -> Home
```

The Settings page does not need different wording for these callers.

## 6.7 `q` and `Q`

Both lowercase `q` and uppercase `Q` must be accepted as the same action.

On main Settings:

### If draft is unchanged

```text
q/Q -> Back immediately
```

### If draft has unsaved/unapplied changes

Do not silently discard.

Prompt before leaving, for example:

```text
Discard Changes?

You have unapplied changes in Settings.

> Keep Editing
  Discard Changes
```

The exact visual wording may be adjusted only for clarity, but the semantic requirement is fixed:

- dirty draft -> ask before discard,
- unchanged draft -> Back is allowed immediately.

Do not invent different behavior for lowercase vs. uppercase Q.

---

# 7. REPOSITORY MODEL — LOCKED

## 7.1 What a Repository means in HAWS

A Repository in Settings is a **GitHub repository source URL used by HAWS**, for example:

```text
https://github.com/owner/repo-a
https://github.com/owner/repo-b
```

It is not automatically the same thing as a user-owned local clone outside HAWS.

### Locked Task 3 additions

When adding a repository, Settings accepts only its GitHub source URL. HAWS
derives the managed destination deterministically as
`skills/packs/<repository-name>`, using the URL's final path component without
the `.git` suffix and with unsupported characters normalized. Duplicate URLs
must be rejected in the draft. A destination collision with a different
repository must fail clearly without overwriting existing data. Clone or
submodule creation occurs only during final Install/Update.

If multiple enabled repositories provide the same skill, the skill remains
active while at least one provider remains enabled. Auto-prune occurs only
when no enabled provider remains. This uses the existing source/skill catalog;
if provider identity cannot be determined reliably, HAWS must report the
limitation rather than inventing a new provider-selection model.

## 7.2 All repository sources may be removed

Removal is not restricted by repository type.

The user must be able to remove any configured repository source, including multiple repositories in one operation.

Do not implement a rule such as “only single-skill repositories can be removed” or “only packs can be removed.”

## 7.3 Multi-select removal

Historical multi-selection behavior is known-good and should be reused/adapted from the old implementation where appropriate.

Target behavior:

```text
Select repositories to remove:

> [ ] repo-a                         24 skills
  [x] repo-b                         18 skills
  [ ] repo-c                         31 skills
  [x] repo-d                         12 skills

  Remove Selected
  Cancel

2 repositories selected
```

Exact layout may adapt to terminal width, but behavior is fixed:

- arrow navigation,
- Space toggle,
- multiple selected items,
- explicit confirmation/action,
- no immediate persistent mutation while still editing the draft.

## 7.4 Remove before first install

If a repository is removed from the first-install draft before HAWS has installed it:

```text
Remove source from draft
-> do not fetch/download that source
-> do not install/activate skills from that source
```

There is no installed HAWS-owned repository data to prune yet.

## 7.5 Remove after installation

If the repository has already been installed/managed by HAWS, removal is a complete HAWS-side detach operation.

After final Update confirmation, HAWS should:

1. remove the repository source from HAWS persistent configuration,
2. remove HAWS-owned references/integration state tied only to that source,
3. re-resolve active skills against the remaining enabled sources,
4. auto-prune skills that no longer have any enabled provider/source,
5. keep a skill active if another enabled source still provides it and that resolution is valid,
6. remove HAWS-managed downloaded/cached/repository files belonging to the removed source,
7. avoid leaving orphaned HAWS-owned data when safe cleanup is possible,
8. never delete unrelated user-owned local clones or arbitrary user files outside HAWS ownership.

## 7.6 Auto Prune definition

For this specification, **Auto Prune** means cleanup of HAWS-owned state after a source is removed.

It is not merely hiding or disabling a reference.

Auto Prune includes, where applicable:

- orphaned active skill state,
- HAWS-created references/links owned by the removed source,
- HAWS-managed downloaded/cached repository data,
- other HAWS-owned state that would otherwise become invalid/orphaned.

Historical repository cleanup/prune behavior should be inspected and reused/adapted if compatible with the newer ownership model.

## 7.7 Preview requirement for removal

Actual pruning must not occur during draft editing.

Flow:

```text
Settings Draft
-> mark repositories for removal
-> resolve expected effects in draft/preview
-> Preview Update shows what will be removed/pruned
-> Update
-> perform persistent removal + prune
```

Preview should clearly distinguish:

```text
Repositories to remove
Skills that will be auto-pruned
HAWS-managed files/data that will be cleaned up
User-owned data that will NOT be touched
```

Do not mislabel HAWS source removal as deleting the repository from GitHub.

---

# 8. REPOSITORY COUNTS — LOCKED

Repository entries should show how many skills that repository provides when the information is available.

Example:

```text
repo-a                         24 skills
repo-b                         18 skills
repo-c                          1 skill
```

This count belongs to the repository view because it helps the user understand the value/impact of each source.

Do not add decorative counts that have no decision value.

---

# 9. SKILLS UX — LOCKED SEMANTICS

## 9.1 Main Settings count

Main Settings may remain concise:

```text
Skills                 127 active
```

Do not force an `active / available` aggregate everywhere merely for consistency.

## 9.2 Skills hierarchy

Preserve/adapt the approved hierarchy:

```text
HAWS Settings — Skills

> Single Skills
  Multi-Skill Packs
  Back to Settings
```

## 9.3 Single Skills

Single Skills are shown individually with their own checkbox/state.

Example:

```text
HAWS Settings — Single Skills

> [x] Git Workflow
  [x] Code Review
  [ ] Research
  [x] Documentation
  [ ] API Design
  ...

  Apply Selection
  Back to Skills
```

An aggregate `x / n active` count is not required here because individual state is already directly visible.

If an existing useful count is already present and does not clutter the page, preserve it only if it has clear value; do not add one merely because another page has one.

## 9.4 Multi-Skill Packs

Packs should show active/total counts because that count communicates partial activation meaningfully.

Example:

```text
HAWS Settings — Multi-Skill Packs

> Web Development Pack          8 / 12 active
  Product Design Pack            3 / 8 active
  Documentation Pack             6 / 6 active
  Back to Skills
```

Pack detail may show:

```text
HAWS Settings — Web Development Pack

8 / 12 active

> [-] Select All
  [x] Frontend Development
  [x] Backend Development
  [ ] API Design
  [x] Testing
  ...

  Apply Selection
  Back to Packs
```

## 9.5 Subpage working state

Selection screens may use a local working state.

```text
Open selection page
-> copy relevant Settings Draft state
-> Space toggles local working state
-> Apply Selection writes result into Settings Draft
-> q/Q backs out without committing that local working state
```

`q/Q` from a nested selection page must not erase unrelated changes already present in the parent Settings Draft.

## 9.6 Select All

Where the historical tri-state checklist mechanism is useful, reuse/adapt it:

```text
[ ] none selected
[x] all selected
[-] partially selected
```

Do not create a redundant extra `Bulk Actions` submenu if `Select All` directly provides the needed interaction cleanly.

---

# 10. AI ENVIRONMENTS — LOCKED

## 10.1 Detection rule

The user may select/use only AI environments that are actually available/detected on the machine.

Example:

```text
HAWS Settings — AI Environments

> [-] Select All
  [x] Codex             Detected
  [x] Claude Code       Detected
  [ ] Gemini CLI        Not detected
  [ ] Cursor            Not detected
```

`Not detected` entries may be displayed for information but must not be selectable as active integrations.

Do not configure an unavailable AI tool as though it exists.

Do not silently install third-party AI tools as a side effect of selecting integrations.

## 10.2 Vertical presentation

When listing AI environments in Settings or Preview, display names vertically rather than as a long comma-separated horizontal line.

Preferred Preview structure:

```text
AI Environments

Current
  Codex
  Claude Code

New
  Codex
  Claude Code
  Gemini CLI

Added
+ Gemini CLI
```

Use equivalent vertical presentation for removals if necessary.

---

# 11. SECOND BRAIN REMOTE — LOCKED

If Second Brain Remote has not been configured yet, opening its configuration should allow the user to provide the repository/remote URL.

Target conceptual flow:

```text
HAWS Settings — Second Brain Remote

Remote repository
> Paste GitHub repository URL
  Back
```

Then:

```text
URL entered
-> verify connection/repository
-> report verification result
-> save verified configuration into Settings Draft
```

Rules:

- verification is allowed to perform the minimum network work necessary,
- verification must not automatically start a full sync,
- no persistent Second Brain configuration change happens until final Install/Update,
- reuse/adapt historical connection/validation behavior if it is still compatible,
- do not copy old flow that performs unrelated automatic actions.

If an existing remote is configured, preserve the currently approved editing/disconnect semantics unless they conflict with this document. If a conflict is discovered, STOP and report instead of improvising.

---

# 12. AUTO UPDATE — LOCKED

Auto Update is a draft-editable boolean setting.

Example:

```text
Auto Update            [ On ]
```

Changing it inside Settings changes the Settings Draft only.

It should be a fast local UI action and should not trigger network work merely because the toggle changed.

Persistence occurs only after final Install/Update.

---

# 13. LOADING, NETWORK WAIT, RESPONSIVENESS — LOCKED DIRECTION

## 13.1 Answer to the core behavior question

Yes, some real actions may legitimately take time because they require network access, repository inspection, filesystem work, environment detection, or other I/O.

This is expected.

## 13.2 Reuse existing good historical work

Do not reinvent the loading mechanism if known-good behavior already exists.

Inspect and selectively reuse/adapt:

- good loading/progress feedback from later work after `99c0d9d`, including relevant pieces of `40f8fad`,
- responsiveness improvements,
- lazy loading/caching where appropriate,
- local-first/bounded-wait behavior from historical HAWS implementations where still applicable,
- known-good terminal update behavior.

## 13.3 Actions that may legitimately show loading/wait feedback

Examples include:

- adding a repository,
- verifying a repository,
- loading repository metadata/skills,
- AI environment detection when actual detection work is required,
- Second Brain verification,
- creating Preview if resolution requires real work,
- Install,
- Update,
- Sync,
- Doctor.

## 13.4 Actions that should normally be immediate/local

Examples:

- toggling an already-loaded skill checkbox,
- toggling Auto Update,
- moving selection,
- Back,
- local Discard action,
- switching between already-loaded cached views.

## 13.5 Presentation requirements

Loading feedback should be useful and non-spammy.

Simple textual feedback is sufficient, for example:

```text
Checking repository...
Loading skill metadata...
Resolving configuration...
```

Do **not** add decorative progress bars such as:

```text
[██████████░░░░] 7 / 10 repositories
```

unless there is a separate future approved requirement for such a progress bar.

Do not repeatedly print whole menu frames down the terminal during loading.

Opening Settings alone should not trigger unnecessary network operations.

Use lazy loading/caching when it improves responsiveness without making state stale or incorrect.

---

# 14. TUI INTERACTION — LOCKED

The TUI requirement is not merely a visual redraw requirement. It is the known-good historical interactive terminal experience.

## 14.1 Required interaction

Use/adapt the known-good mechanism so that:

- `↑` / `↓` moves selection,
- Enter selects/opens,
- Space toggles checklist items where appropriate,
- lowercase `q` and uppercase `Q` are accepted equivalently,
- selection visibly changes on the same menu surface,
- menu copies do not accumulate down the terminal,
- no unnecessary flicker/clear behavior is introduced,
- interaction feels like an actual interactive TUI application.

## 14.2 Primary reference

Before modifying the mechanism, inspect:

- branch `codex/haws-bootstrap`,
- commit `40f5f5a`,
- the old known-good interactive checklist/menu implementation.

## 14.3 Critical reuse rule

Do not build a new mechanism just to imitate the final pixels/text if the historical mechanism can be reused or minimally adapted.

Conceptually:

> If the old good behavior is a real video, do not replace it with rapidly scrolling paper that only looks similar at a glance.

## 14.4 What to adapt

Adapt the old interaction mechanism to the new product pages and state flow:

```text
Old interaction quality
+
New Setup / Settings / Preview / Home semantics
=
Target HAWS TUI
```

Do not restore the old automatic workflow around it.

## 14.5 Do not invent unapproved keys

This document explicitly locks `↑`, `↓`, Enter, Space where applicable, and `q/Q` semantics.

Do not redesign Escape/Ctrl+C semantics during the current Settings/TUI recovery unless an existing approved implementation must be preserved or a defect requires it. If a semantic decision is necessary and not already approved, STOP and ask/report instead of inventing behavior.

---

# 15. PREVIEW INSTALL — LOCKED SEMANTICS

Target structure:

```text
HAWS — Preview Install

No changes have been made yet.

Repositories
8 sources

Skills
127 active

AI Environments
  Codex
  Claude Code

Second Brain Remote
Off

Auto Update
On

> Install
  Back to Settings
  Cancel
```

Rules:

- use real data, not the example counts,
- AI names are vertical,
- `Back to Settings` preserves the Settings Draft,
- `Cancel` discards the installation draft/flow and returns to Setup,
- `Install` is the final action that may create persistent HAWS installation state,
- remote sync must not automatically start merely because Install runs unless explicitly part of an approved install requirement.

If repository removals occurred before first install, those sources must simply be absent from what will be installed/fetched.

---

# 16. PREVIEW UPDATE — LOCKED SEMANTICS

Target structure should communicate actual change impact, not merely a summary count.

Example:

```text
HAWS — Preview Update

No changes have been applied yet.

Repositories

Remove
- repo-b
- repo-d

Add
+ repo-e

Skills

Removed automatically
- Skill B1
- Skill B2

AI Environments

Current
  Codex
  Claude Code

New
  Codex
  Claude Code
  Gemini CLI

Second Brain Remote
Off -> On

Auto Update
On -> Off

> Update
  Back to Settings
  Cancel
```

Rules:

- final action is `Update`, not `Apply Update`,
- `Back to Settings` preserves the draft,
- `Cancel` discards the update draft and returns to Home,
- no persistent mutation occurs before `Update`,
- repository prune impact must be visible before Update,
- user-owned data that will not be touched should be made clear when repository cleanup is involved,
- do not use long comma-separated AI lists.

## 16.1 No changes case

If the draft is semantically identical to persistent state:

```text
HAWS — Preview Update

No settings have changed.

> Back to Settings
  Back to Home
```

Do not show a meaningless `Update` action when there is nothing to update.

---

# 17. HOME — PRESERVE NEWER PRODUCT FLOW

After installation, bare launch goes to Home.

Conceptual target:

```text
HAWS Home

Status: Ready
Last Sync: ...

Repositories:          8 sources
Skills:              127 active
AI Environments:       2 active
Second Brain Remote:   Off
Auto Update:           On

> Sync
  Settings
  Doctor
  Status Details
  Exit
```

Rules:

- Home reads persistent state, not an abandoned draft,
- Sync is explicit,
- bare launch must not auto-sync,
- Doctor is explicit,
- no duplicate Home presentation after Apply/Install/Update,
- preserve newer approved Home flow rather than restoring old 1-click automatic behavior.

---

# 18. STATUS / DOCTOR / SYNC — CORE SEMANTICS TO PRESERVE

## Sync

- explicit user action,
- not automatically triggered by bare launch,
- not automatically triggered merely by opening Settings,
- preserve shared core behavior across OS launchers.

## Status

- local/read-only status presentation,
- no mutation merely to display status.

## Doctor

- local/read-only diagnostic semantics unless an already-approved explicit repair action exists separately,
- must not recursively invoke itself,
- must not recreate the loop fixed in Task 1.

---

# 19. OWNERSHIP RULE — CRITICAL

HAWS may manage/remove files only when HAWS owns/manages those files according to the product state model.

Examples of potentially HAWS-owned state:

- HAWS-managed downloaded repository copies,
- HAWS cache for repository sources,
- HAWS-created references/links,
- HAWS configuration/state files.

Examples HAWS must not delete automatically during repository removal:

- unrelated local repositories cloned manually by the user outside HAWS ownership,
- arbitrary user project directories,
- user-owned configuration unrelated to the removed HAWS source,
- remote GitHub repositories themselves.

Removing a repository source from HAWS must never mean deleting the remote GitHub repository.

---

# 20. CURRENT EXECUTION STATUS

Live task status is maintained only in [PROJECT_STATE.md](PROJECT_STATE.md).
This specification is the product and execution contract; do not duplicate
changing branch, test, or acceptance status here. If this contract conflicts
with the live state, the contract governs product requirements and
`PROJECT_STATE.md` governs the current checkpoint.

---

# 21. TASK 1 — LOOP FIX ONLY

**Current status:** Done. Preserve it. Do not redo unless a regression is discovered.

## Goal

Fix only recursion/hang behavior that prevents reliable commits and Doctor execution.

## Historical comparison

Compare:

- base: `99c0d9d`,
- mixed reference: `40f8fad`.

Extract/reuse only minimal loop-related fixes.

## Allowed scope

- pre-commit recursion/hang fix,
- `run_doctor` recursion fix,
- tests directly protecting those fixes.

## Must not change

- TUI mechanism,
- loading UX,
- Skills UX,
- Settings UX,
- Preview/Home behavior,
- `.bat`,
- command integration unrelated to the loop,
- OS architecture,
- unrelated failures.

## Acceptance

- pre-commit does not hang or loop,
- Doctor does not recursively invoke itself,
- targeted tests pass,
- unrelated failures are reported, not opportunistically fixed.

## Deliverable/report

Report:

1. files changed,
2. exact reason for each change,
3. tests run,
4. results,
5. unrelated failures observed.

## STOP CONDITION

STOP after Task 1. Do not begin Task 2 without explicit user approval.

---

# 22. TASK 2 — APPROVED UX IMPROVEMENTS ONLY

**Current status:** Done. Preserve it. Do not broaden it while doing Task 3.

## Goal

Recover approved UX improvements made after `99c0d9d` without yet replacing the known-good TUI mechanism and without touching OS launchers.

## Include

- visible useful loading feedback,
- short useful descriptions,
- useful counts,
- Skills hierarchy improvements,
- Single Skills / Multi-Skill Packs UX,
- pack selection UX,
- Preview / Apply / Back / Cancel corrections,
- correct post-apply/home behavior,
- no duplicate Home presentation,
- responsiveness improvements,
- lazy loading/caching where appropriate,
- state behavior required by this current authoritative spec.

## Historical reference

Use `40f8fad` selectively, but extract only behavior matching this specification.

## Must not change

- Task 1 loop fixes except to repair an actual regression directly caused by Task 2,
- known-good TUI mechanism,
- Windows `.bat`,
- OS launcher architecture,
- unrelated command integration.

If a UX correction appears to require changing the TUI mechanism, STOP and defer that work to Task 3 instead of mixing scopes.

## Acceptance

- Settings edits draft only,
- Preview semantics are correct,
- Apply/Back/Cancel semantics match approved flow,
- Skills hierarchy is usable,
- counts appear only where useful,
- loading feedback exists for genuinely slow operations,
- opening Settings alone avoids unnecessary network activity,
- Home behavior is not duplicated.

## STOP CONDITION

STOP after Task 2 and wait for user approval before Task 3.

---

# 23. TASK 3 — KNOWN-GOOD TUI BEHAVIOR ONLY

**Current status:** Resume from here after using this spec. Settings behavior is now approved and must not be redesigned.

## Goal

Restore/preserve the known-good interactive TUI mechanism and integrate it with the approved newer product/state behavior in this specification.

## Required historical inspection BEFORE editing

Inspect:

- branch `codex/haws-bootstrap`,
- commit `40f5f5a`,
- old interactive checklist/menu implementation,
- relevant good TUI/loading pieces in later work only where necessary.

Do not assume the current implementation matches the historical mechanism merely because the output looks similar.

## Required TUI behavior

- `↑` / `↓` navigation,
- Enter selection/open,
- Space toggle where appropriate,
- `q` and `Q` accepted equivalently,
- same-surface interactive menu behavior,
- no duplicate menu frames accumulating down the terminal,
- no unnecessary flicker,
- multi-select checklist behavior where required,
- preserve current approved Settings draft semantics,
- preserve current approved Setup / Preview / Home semantics.

## Required product integration

Adapt the old mechanism to:

- HAWS Setup,
- lifecycle-neutral HAWS Settings,
- repository multi-select removal,
- Skills selection,
- AI Environment selection,
- Second Brain configuration,
- Preview Install,
- Preview Update,
- Home.

Do not restore old automatic sync/Doctor flow.

## Must preserve from Task 1/2

- loop fix,
- Settings draft model,
- loading/responsiveness work,
- Skills UX semantics,
- Preview behavior,
- Home behavior,
- Status semantics,
- Doctor semantics.

## Must not change in Task 3

- Windows `.bat`,
- platform launcher architecture,
- cross-platform entry design,
- approved Settings semantics,
- approved repository removal semantics,
- approved AI detection rule,
- approved Second Brain first-time setup behavior,
- approved Apply -> Preview -> Install/Update vocabulary,
- unrelated command architecture.

If the TUI integration appears to require changing any approved semantic layer, STOP and report before doing it.

## Tests

Perform automated TUI/state tests where feasible and provide manual terminal acceptance steps.

At minimum verify:

- arrow navigation,
- Enter behavior,
- Space toggle behavior,
- q/Q equivalence,
- nested page cancel/back behavior,
- dirty Settings q/Q confirmation,
- repository multi-select UI,
- no duplicate menu frame accumulation,
- no obvious unnecessary flicker,
- loading messages coexist correctly with interactive surfaces,
- Settings changes remain draft-only until Install/Update.

## Deliverable/report

Report:

1. exact historical mechanism inspected,
2. which parts were reused unchanged,
3. which parts were minimally adapted and why,
4. files changed,
5. exact TUI behavior achieved,
6. automated tests and results,
7. manual acceptance checklist,
8. any conflict with approved product semantics.

## STOP CONDITION

STOP after Task 3. Do not begin Task 4 until the user manually reviews/approves the TUI behavior.

---

# 24. TASK 4 — CLEAN BASE VALIDATION ONLY

## Goal

Validate the recovered shared HAWS Clean Base after Tasks 1–3.

## No new features

Do not add new functionality during Task 4.

Do not use validation as an excuse to redesign UX.

## Validate all of the following

### Loop safety

- pre-commit does not recurse/hang,
- Doctor does not recursively invoke itself.

### Product flow

- first install enters HAWS Setup,
- Use Default Setup works through draft -> Preview Install -> Install,
- Customize Settings opens the shared Settings page,
- installed bare launch enters Home,
- bare launch does not auto-sync.

### Settings/state

- lifecycle-neutral Settings page,
- Settings Draft semantics,
- Apply -> Preview behavior,
- Back preserves draft,
- Cancel/Discard semantics,
- Reset to Defaults confirmation,
- q/Q semantics,
- no persistent mutation before Install/Update.

### Repositories

- Repository = GitHub source URL,
- multiple repository selection/removal,
- before-install source removal prevents fetching/installing that source,
- after-install Update performs source detach + HAWS-owned prune,
- orphan skill pruning is correct,
- alternate provider keeps valid skills active where applicable,
- user-owned data outside HAWS remains untouched,
- repository skill counts are correct where shown.

### Skills

- Single Skills hierarchy works,
- Multi-Skill Packs hierarchy works,
- pack x/n active count is correct,
- Single Skills do not require a redundant aggregate count,
- selection confirmation/back semantics are correct.

### AI Environments

- detection is accurate,
- only detected tools are selectable/active,
- Preview lists names vertically,
- unavailable tools are not silently configured/installed.

### Second Brain

- first-time URL entry works,
- verification works,
- verification does not automatically sync,
- persistent changes wait for Install/Update.

### Loading/responsiveness

- useful loading feedback exists for real slow operations,
- no decorative progress bar was added,
- unnecessary network activity is avoided,
- lazy loading/caching behavior is correct,
- menu output does not spam duplicate frames.

### TUI

- arrows,
- Enter,
- Space,
- q/Q,
- same-surface interaction,
- no degraded fake approximation of old known-good behavior.

### Home / Sync / Status / Doctor

- Home shows persistent state,
- Sync explicit only,
- Status read-only,
- Doctor diagnostic/read-only semantics preserved,
- no duplicate Home presentation.

### Architecture

- no OS wrong-turn work included,
- no new Windows `.bat` implementation yet,
- shared core remains platform-neutral.

## Regression suite

Run the relevant full/shared regression suite after targeted checks.

Classify every failure as:

- regression introduced by recovery,
- in-scope defect,
- pre-existing/unrelated failure.

Do not silently fix unrelated failures.

## Deliverable/report

Report:

1. complete test commands,
2. results,
3. remaining failures,
4. classification of every failure,
5. manual acceptance checklist,
6. whether Clean Base is ready for user approval.

## STOP CONDITION

STOP. The user must explicitly approve the Clean Base before Task 5.

---

# 25. TASK 5 — WINDOWS `.bat` ENTRY ONLY

## Goal

Create a first-class Windows native entrypoint that preserves the convenience of the historical 1-click experience while entering the shared new HAWS system.

Target:

```text
double-click haws.bat
        ↓
locate required runtime automatically
        ↓
locate shared HAWS/repository root
        ↓
invoke shared HAWS behavior/core
        ↓
new Setup/Home/TUI/product flow
```

## Required references

Inspect historical launcher patterns from:

- `codex/haws-bootstrap`,
- `1-CLICK-SYNC.bat`,
- `SETUP.bat`.

Reuse/adapt only launcher conveniences/patterns that still fit the new architecture.

## `.bat` may

- locate required Bash/runtime/tooling,
- locate repository root,
- normalize/forward arguments,
- invoke shared HAWS core/entrypoint,
- propagate exit codes,
- show clear missing-dependency errors,
- support convenient double-click launch.

## `.bat` must NOT

- implement Settings logic,
- implement repository business logic,
- implement Skills logic,
- implement Sync logic,
- implement Doctor logic,
- duplicate state management,
- create a separate Windows-only TUI engine,
- automatically sync merely because the user double-clicked,
- automatically run Doctor on bare launch,
- create behavior that differs from macOS/Linux shared core.

## Required command parity

```text
Windows                 macOS/Linux
haws.bat                ./haws.sh
haws.bat settings       ./haws.sh settings
haws.bat sync           ./haws.sh sync
haws.bat status         ./haws.sh status
haws.bat doctor         ./haws.sh doctor
```

If actual final command names differ in the repository, preserve equivalent shared behavior and document the exact final commands; do not create duplicated logic just to match spelling.

## Bare launch behavior

```text
First run  -> HAWS Setup
Installed  -> HAWS Home
```

The launcher itself should not own this decision beyond invoking the shared logic that owns install-state behavior.

## Tests

At minimum test:

- double-click/manual Windows entry,
- runtime detection,
- missing runtime failure message,
- correct working directory/root resolution,
- argument forwarding,
- exit-code propagation,
- first-run entry,
- installed entry,
- settings command,
- sync command,
- status command,
- doctor command,
- no automatic sync on bare launch,
- same TUI interaction quality through Windows entry.

## Deliverable/report

Report:

1. historical launcher behavior reused/adapted,
2. files changed,
3. exact launcher responsibilities,
4. tests/results,
5. manual Windows acceptance steps.

## STOP CONDITION

STOP after Task 5. Wait for user approval before cross-platform parity work.

---

# 26. TASK 6 — CROSS-PLATFORM PARITY

## Goal

Verify and correct platform-specific entry integration so Windows and macOS/Linux expose the same HAWS product behavior through platform-appropriate launchers.

## Architecture rule

Different launcher implementations are acceptable.

Different product behavior is not.

## Compare at minimum

| Behavior | Windows | macOS/Linux | Requirement |
|---|---|---|---|
| First install entry | HAWS Setup | HAWS Setup | Equivalent |
| Installed bare launch | Home | Home | Equivalent |
| Settings | Shared behavior | Shared behavior | Equivalent |
| Draft state | Same semantics | Same semantics | Equivalent |
| Preview/Apply | Same semantics | Same semantics | Equivalent |
| Repository removal/prune | Same semantics | Same semantics | Equivalent |
| Skills UX | Same semantics | Same semantics | Equivalent |
| AI selection | Same semantics | Same semantics | Equivalent |
| Second Brain | Same semantics | Same semantics | Equivalent |
| Sync | Explicit | Explicit | Equivalent |
| Status | Read-only | Read-only | Equivalent |
| Doctor | Diagnostic | Diagnostic | Equivalent |
| TUI quality | Known-good | Known-good | Equivalent experience |
| Errors | Clear | Clear | Equivalent meaning |
| Exit codes | Correct | Correct | Equivalent meaning |

## Must not do

- do not force both OS families to use identical launcher source code,
- do not move business logic into launchers,
- do not degrade one platform to make implementation superficially uniform,
- do not change approved product semantics merely to simplify parity testing.

## Tests

Run equivalent command/flow acceptance tests on each supported platform/environment available.

If a platform cannot be tested directly, clearly report what was automated, what was statically inspected, and what requires manual user validation.

## Deliverable/report

Report:

1. parity matrix,
2. platform-specific differences that are intentionally allowed,
3. product behaviors verified equivalent,
4. tests/results,
5. remaining platform-specific risks/manual checks.

## STOP CONDITION

STOP after Task 6. Wait for explicit user approval before documentation/final validation.

---

# 27. TASK 7 — DOCUMENTATION AND FINAL VALIDATION

## Goal

Document the final architecture/usage accurately, run final regression/acceptance validation, and leave merge control to the user.

## Documentation requirements

Update documentation to:

- give clear OS-specific launch instructions,
- explain that native launchers may differ by platform,
- explain that HAWS behavior/core is shared,
- describe first-install Setup vs. installed Home behavior,
- describe Settings draft -> Apply -> Preview -> Install/Update semantics,
- document explicit Sync behavior,
- document repository source/remove semantics if user-facing docs require it,
- document Windows `.bat` usage,
- remove obsolete instructions that require Windows users to manually open Git Bash as the normal workflow,
- remove descriptions of old auto-sync/auto-Doctor bare-launch behavior,
- avoid claiming cross-platform equivalence that was not actually tested.

## Final validation

Run:

- full relevant regression suite,
- core flow tests,
- Windows launcher tests,
- available macOS/Linux tests,
- manual acceptance checklist where required.

Confirm:

- no regression of Task 1 loop fix,
- no regression of approved Settings behavior,
- no regression of repository prune ownership rules,
- no regression of known-good TUI quality,
- no automatic sync on bare launch,
- no duplicated launcher business logic,
- documentation matches actual final behavior.

## Git/merge rule

Do not merge to `main` automatically.

Do not force-push or rewrite historical branches merely to make history look cleaner.

Leave the final merge decision to the user.

## Deliverable/report

Report:

1. docs changed,
2. tests/results,
3. final architecture summary,
4. remaining known limitations,
5. exact branch/commit state,
6. whether the work is ready for user merge decision.

## STOP CONDITION

STOP and wait for the user to decide whether/how to merge.

---

# 28. ANTIGRAVITY PER-TASK START TEMPLATE

At the start of every task, print/check a compact execution contract before editing:

```text
CURRENT BRANCH:
<actual branch>

CURRENT HEAD:
<actual commit>

CURRENT TASK:
<Task N — exact title>

GOAL:
<one narrow goal>

MUST KEEP:
<approved behavior/state from prior tasks>

HISTORICAL REFERENCES TO INSPECT:
<specific branch / commit / file>

REUSE/ADAPT:
<exact known-good mechanisms relevant to this task>

DO NOT CARRY FORWARD:
<old/bad/unrelated behavior>

MUST NOT CHANGE:
<approved layers outside this task>

ACCEPTANCE:
<targeted tests/behaviors>

STOP WHEN:
<task-specific stop condition>
```

If the actual branch/HEAD is unexpected, STOP before editing and report it.

---

# 29. ANTIGRAVITY CHANGE-DISCIPLINE RULES

For every patch:

1. Inspect before editing.
2. Identify the smallest relevant files/functions.
3. Check historical reference before inventing a new mechanism.
4. Explain what historical piece is being reused/adapted.
5. Explain exactly how it is being adapted to the current product semantics.
6. Avoid unrelated cleanup/refactors.
7. Keep diffs scoped and reviewable.
8. Run targeted tests first.
9. Run broader tests only after the targeted behavior is correct.
10. Report unrelated failures without expanding scope.
11. Stop at the task boundary.

A commit/file being historical reference does **not** grant permission to copy unrelated code from it.

---

# 30. FINAL PRODUCT INVARIANTS

These must remain true at the end of Task 7:

```text
1. First install begins with HAWS Setup.
2. Installed bare launch begins with HAWS Home.
3. Bare launch never auto-syncs.
4. Settings is lifecycle-neutral.
5. Settings edits a draft.
6. Apply goes to Preview; it does not persist immediately.
7. Final action is Install or Update.
8. Back from Preview keeps the draft.
9. Cancel/Discard drops the draft according to context.
10. Reset to Defaults requires confirmation and affects draft only.
11. q and Q are equivalent.
12. Dirty main Settings asks before discard on q/Q.
13. Repository means a GitHub source URL managed by HAWS.
14. Any configured repository may be removed.
15. Multiple repositories may be selected for removal.
16. Removing a source before install prevents it from being fetched/installed.
17. Removing an installed source performs HAWS-owned cleanup/prune after Update.
18. User-owned files outside HAWS ownership are never silently deleted.
19. Repository views show meaningful skill counts where available.
20. Multi-Skill Packs show x/n active.
21. Single Skills do not require a redundant aggregate count.
22. Only detected AI environments may be active/selectable.
23. AI names are listed vertically in Preview/details.
24. First-time Second Brain configuration accepts a repository URL and verifies it.
25. Verification does not automatically sync.
26. Real slow operations may show useful loading feedback.
27. Decorative progress bars are not required and must not be added without approval.
28. Opening Settings does not perform unnecessary network work.
29. Known-good old TUI interaction mechanism is reused/adapted where possible.
30. ↑/↓, Enter, Space where applicable, and q/Q behave consistently.
31. Menu frames do not accumulate down the terminal during interaction.
32. Windows .bat is a thin launcher, not a second HAWS implementation.
33. Windows/macOS/Linux may have different native entry implementations.
34. Product behavior/state/results/TUI quality remain equivalent across platforms.
35. Status remains read-only.
36. Doctor remains diagnostic and non-recursive.
37. Sync remains explicit.
38. Historical good mechanisms are reused selectively; historical bad flows are not restored.
39. No task automatically starts the next task.
40. Final merge remains a user decision.
```

---

# 31. ONE-LINE PROJECT SUMMARY

> Recover the newer HAWS system from `99c0d9d`, preserve the already-fixed loop and approved UX/state model, selectively reuse and minimally adapt known-good historical TUI/loading/repository/launcher mechanisms, reject obsolete automatic flows and OS wrong-turn work, validate a clean shared core, then add a thin Windows `.bat`, verify cross-platform parity, document the final behavior, and stop for the user's merge decision.
