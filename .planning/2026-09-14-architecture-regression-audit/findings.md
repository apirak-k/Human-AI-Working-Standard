# Findings

## Initial evidence

- Historical skill fixes `065296b`, `5ac8147`, `7c1b957`, `b42beb9`, and `b1cc486` are ancestors of the current checkpoint.
- The current source-aware catalog introduced in `7cca66f` enumerates every `SKILL.md` below each gitmodule source. It does not apply the historical logical-skill filtering/deduplication before classification.
- The current source catalog derives sources only from `.gitmodules`, so local custom skills require separate treatment.
- `recovery/clean-base` contains UX/runtime work not present in the current checkpoint. It is a selective reference, not a wholesale replacement.

## Cross-line comparison

- The current line retains historical logical-skill filtering in `get_repo_skills`, but the current Settings path uses the newer `catalog_skills` path instead. The new path indexes raw `SKILL.md` files and bypasses the earlier filter/deduplication boundary.
- The current and clean-base catalogs both derive registered sources from `.gitmodules` and enumerate raw `SKILL.md` files beneath them. This is not sufficient for logical-skill identity or custom-skill discovery.
- Clean-base provides useful UX contracts: details must call the detailed status mode; single skills should not show redundant aggregate counts; packs show active/total; loading is for real slow work only; and menus must not accumulate duplicate frames or flicker unnecessarily.
- Clean-base must not be copied wholesale: its own specification prohibits duplicating Settings/Sync/Doctor logic or state machines. Its modular boundaries and UX requirements are candidates; its raw catalog behavior is not canonical.

## Home and operations comparison

- Current Home routes `Status Details` to `run_status` without `--details`, so it cannot satisfy its documented detailed view. Clean-base routes the equivalent menu action to `status_run --details`.
- Current Sync has explicit, bounded, per-target reporting and current Uninstall has ownership-aware preview/apply behavior. Preserve those safety semantics.
- Clean-base is useful for operation presentation contracts (explicit Sync, read-only Status/Doctor, no duplicate Home presentation) but its historical auto-sync-on-exit behavior is explicitly excluded.

## Component inventory

- Current implementation is a single `haws.sh` containing health, catalog, state, sync, integrations, settings, and UI paths. It still contains legacy helper paths beside the new Settings/catalog flow.
- Clean-base separates these into `runtime/{catalog,health,integrations,operations,platform,settings,state,ui}.sh`. This is a useful dependency boundary, not a behavior reference by itself.
- Both implementations have focused catalog, state, status/doctor, sync, and uninstall tests. Current additionally has launcher/menu and repository-skill coverage; clean-base adds first-install and cross-platform coverage.

## New-chat handoff: post-Luna review state

- The user wants to start a new chat and continue from this audit.
- All screen/interaction proposals discussed after switching to Luna are explicitly unconfirmed. Do not treat them as locked requirements or implementation decisions.
- The intended process is: settle the high-level behavior first, then trace every interaction from launch to exit, recording each approved transition immediately. Only after the full trace is approved should the final spec and implementation plan be written.
- The trace must cover both not-installed and installed paths, default selection, Enter, arrow navigation, Space toggles, Back, Q/Cancel, Apply confirmation, loading/progress, errors, cancellation, persistence, and return transitions.
- Proposed but unconfirmed Settings semantics: one shared Settings surface before and after installation; before install the draft starts from defaults, after install it loads current settings; Apply is the only path that writes real state and must confirm first.
- Proposed but unconfirmed navigation semantics: visible Back should return while keeping changes in the parent draft; Q/Cancel should leave while discarding changes from the current page; Apply should persist to the machine. This still needs user confirmation.
- The Settings summary must retain all relevant state, including Repositories, Skills active/total, AI Environments, Second Brain Remote, Auto Update, and Last Sync.
- The user specifically corrected the Skills mockup: Single Skills are individual standalone/custom skills and may have multiple rows toggled with Space; pack repositories belong in Multi-Skill Packs. The earlier example using pack-like names under Single Skills was not accepted as final.
- Doctor and Sync outputs must be compared against the trusted old behavior before proposing the final trace. Uninstall behavior was provisionally viewed as good, but post-Luna proposals remain unconfirmed.

## Ponytail integration gate

- The real Ponytail submodule is clean and contains six `SKILL.md` files,
  `.codex-plugin/plugin.json`, and the declared Claude/Codex hook manifest.
- In an isolated HAWS project with Ponytail as the only registered source,
  the canonical catalog returned exactly six rows with source ID
  `ponytail::skills/packs/ponytail`; adapter/plugin/hook files were not
  classified as skills.
- With Claude, Codex, and Gemini fixture environments enabled, `run_sync`
  exited 0. It created six Claude junctions, six Codex junctions, and one
  Gemini skills-directory projection. The manifest contained six Ponytail
  skill entries and no hook/plugin/marketplace entries.
- The gate used a disposable HOME and `auto_update=off`; it did not perform a
  real remote fetch or mutate the user's global AI directories. The result
  does not by itself prove that a currently running Codex chat has reloaded
  the newly installed Ponytail runtime plugin.

## Checkpoint 2 baseline

- The Checkpoint 1 catalog emits the required six-column logical-skill rows;
  `_settings_ensure_skill_draft`, `_settings_skill_selector`, and the Settings
  preview/apply paths already parse that shape and store source-scoped IDs.
- The current draft-backed Skills page still prints an outer
  `Configure Active Skills (Enable / Disable)` frame before calling the shared
  menu with the same title, so one page open renders the title/frame twice.
- The current page renders a Single Skills aggregate status and only a total
  pack count. Pack selection rows do not yet expose per-pack `active / total`.
- The current selector already keeps skill changes in `HAWS_DRAFT_SKILLS` and
  only `settings_apply_skill_draft` writes `skills.disabled`; the new tests
  must preserve that boundary while exercising Back/cancel paths.
- The worktree `.gitmodules` registers standalone sources, but several
  submodule directories are empty. Checkpoint 2 must not initialize, update, or
  otherwise touch those submodules.
- Initial skill-path reads used an outdated directory layout and returned
  `PathNotFound`; the installed skills were then read from their actual
  `C:\\Users\\ai-project\\.agents\\skills\\...` paths. No repository files
  were changed by the failed reads.

## Checkpoint 3 evidence and cross-device continuation

- Checkpoint 3 is complete at `9ab4499` on
  `codex/old-base-selected-improvements`, after Checkpoint 1 `774cab1` and
  Checkpoint 2 `0671a2d`.
- Production changes are limited to `haws.bat` and `haws.sh`; test coverage is
  in `tests/cli/launcher_menu_test.sh`, `tests/cli/settings_flow_test.sh`, and
  `tests/windows_launcher_execution.test.mjs`.
- The executable tests passed with exit code 0. The Windows suite reported 10
  pass, 0 fail, and 1 skip because the host could not create a file symlink;
  this is the only automated `[Unverified]` item from that run.
- The handoff must preserve the distinction between completed code and the
  unverified host capability. Enabling Windows Developer Mode or granting the
  symlink privilege permits a later rerun; no production workaround is needed.
- The next planned implementation scope is Checkpoint 4 (Status Details and
  operation presentation), but it is explicitly not started. A future device
  should resume from user review, not silently advance the checkpoint.
