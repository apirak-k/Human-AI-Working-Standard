# Approved CLI UX implementation — task plan

## Goal

Implement the approved keyboard-first HAWS terminal UX while preserving draft-before-Apply, ownership-aware operations, and local-only Status and Doctor behavior.

## Phases

- [ ] Task 1: Cursor-menu and checklist primitives
- [ ] Task 2: Draft-only Settings flows
- [ ] Task 3: Reviewed Preview and Apply flows
- [ ] Task 4: Cursor Home and conditional Sync
- [ ] Task 5: Full regression and fixture acceptance

## Current state

Existing uncommitted candidate changes cover parts of Tasks 1 and 2. They must be verified before further behavioral changes. The implementation plan and approved UX design are the source of truth.

## Errors encountered

| Error | Attempt | Resolution |
| --- | --- | --- |
| Direct Git Bash script calls could not find `date`/`basename` | 1 | Invoke Git Bash with `-lc`, which restores its shell command path. |
| Planning/SDD initialization scripts could not create their target directories under this sandbox | 2 | Maintain an in-worktree `.planning` ledger with the required planning records. |
