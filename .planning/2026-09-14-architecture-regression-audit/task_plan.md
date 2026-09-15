# Architecture Regression Audit

## Goal

Compare the current old-base implementation with the trusted historical line and selected clean-base improvements. Identify root-cause regressions, agree decisions with the user one topic at a time, then produce an implementation plan. Do not implement fixes during the audit.

## Phases

1. In progress — map old/current/clean-base architecture and commit lineage.
2. Pending — compare skill source, catalog, identity, state, and adapter-link boundaries.
3. Pending — compare Home actions and reporting flows: Status, Doctor, Sync, Uninstall, and menu semantics.
4. Pending — audit interaction safety across the whole lifecycle: default selection, Enter, q/Q, Back, cancellation, EOF, and destructive confirmation.
5. Pending — present decision matrix and obtain user decisions one topic at a time, with screen/flow examples after the user switches to Luna.
6. Complete — draft specification approved; checkpointed implementation plan
   written at `docs/superpowers/plans/2026-09-14-haws-selected-improvements.md`.
7. Complete for Checkpoints 1–5 automated evidence. The selected-improvements
   implementation and continuity documentation are complete through
   `500b59e`; physical Windows/human acceptance remains `[Unverified]` and is
   a separate follow-up.

8. In progress — follow-up performance and UI consistency audit requested on
   2026-09-15. Inspect every blocking trace, Settings/nested-page header,
   secondary separator, and Auto Update presentation before proposing fixes.
   Do not implement during this audit.
9. Pending — present confirmed findings, architecture recommendation, and a
   checkpointed implementation plan after the audit is complete and reviewed.

## Cross-device continuation status

- Branch: `codex/old-base-selected-improvements`
- Checkpoint 1: `774cab1`
- Checkpoint 2: `0671a2d`
- Checkpoint 3: `9ab4499`
- Checkpoint 4: `500b59e`
- Handoff record: `docs/superpowers/2026-09-14-selected-improvements-cross-device-handoff.md`
- Current local HEAD is `500b59e`; tracking remote remains at `614bdb4`.
- No main-branch change, push, merge, or dirty-submodule change is included.

## Confirmed decisions

- Keep the current line as the trusted behavior and safety baseline.
- Select only proven improvements from `recovery/clean-base`; do not copy its architecture wholesale.
- A logical skill is source-scoped. Deduplicate adapter/vendor copies within one source only; show same-name skills from different sources separately.
- Enter defaults must be safe and context-specific. A shortcut such as q/Q for keyboard-layout recovery must not make accidental Enter trigger a network, persistent, or destructive action.
- Status summaries show Skills as `active / total`; in first-install draft this is explicitly labeled as the default draft, not as an already-installed result.
- `Auto Update` and `Last Sync` are separate facts. Disabling Auto Update must not erase the last manual/automatic sync result; if no sync has occurred, show `Never` with Auto Update state separately.
- Review decisions can be approved at subtopic level. Each approved subtopic is recorded immediately, and the next screen/transition is stated before continuing.
- **Interaction trace — Step 1: Launch (approved 2026-09-14):** Launching `haws.bat` is inert: it must not sync, run Doctor, write state, or use the network automatically. It may read local state only, then route **not installed → Setup** and **installed → Home**. The terminal/tab title identifies the product as `HAWS — Human-AI Working Standard`, rather than the generic `C:\WINDOWS\system32\cmd...` path.
- Handoff note: the user later clarified that all screen/interaction discussions since switching to Luna are unconfirmed. Treat the Home screen discussion, Settings lifecycle, Q/Back/Apply semantics, and all subsequent mockups as proposals only until reconfirmed in the new chat.

## Implementation completion status — 2026-09-14

- Checkpoints 1–4 are committed on `codex/old-base-selected-improvements`.
- Final automated verification exited 0 with CLI 101/101 and Node 26 passed,
  1 `[Unverified]` file-symlink privilege skip.
- The final verification command and evidence are recorded in `spec.md`,
  `README.md`, and `HANDOFF.md`.
- Physical Explorer launch, full disposable Windows traversal, external
  authenticated remotes, and human acceptance remain `[Unverified]`.
- The audit implementation phase is complete; merge, push, and retirement of
  checkouts remain separately unauthorized actions.
