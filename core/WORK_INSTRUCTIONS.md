# Work Instructions

## Purpose

These instructions translate HAWS into the user's current practical working
procedures.

They are the recommended default, not a replacement for HAWS or confirmed
Project Specific requirements. They may be improved as tools, knowledge, and
working needs change.

## 1. Context loading

At the beginning of a new thread or work context:

1. read the latest `HAWS.md`
2. read the latest `WORK_INSTRUCTIONS.md`
3. inspect the current project source
4. inspect available skills (in `skills/` directory, plugin manifests, or environment catalog) and their descriptions
5. read `design.md` if it exists (system architecture & design blueprint)
6. read `PROJECT_SPECIFIC.md` if it exists
7. read `HANDOFF.md` when continuing existing work
8. report the understood goal, scope, current state, and starting point

Read HAWS and applicable project information once per thread or work context.

Do not reread them every message unless they were updated, the context changed,
or uncertainty exists.

Do not inspect Git history unless current information is insufficient,
conflicting, or historical verification is required.

Read only the Specific, Handoff, and reusable information relevant to the
current project and task.

### 1.1 Context window discipline

To prevent context rot and maintain high reasoning precision across long sessions:

- **Lean context principle**: Avoid flooding the active session with entire dumps
  of large unparsed files, build logs, or repetitive test output. Retrieve and
  quote only relevant snippets.
- **File-backed state over memory**: Do not rely on ephemeral chat history to track
  active plans or critical decisions. Always persist state into structured files
  (`HANDOFF.md`, task checklists, or implementation plans).
- **Proactive session compaction**: When a task phase completes or context grows
  excessively large, summarize progress, update `HANDOFF.md`, and clean temporary
  inspection artifacts before initiating the next phase.

## 2. Starting and performing work

For a new project or major feature:

- do not invent project rules blindly
- during ideation / architectural kickoff, formulate and preserve the technical design in `design.md`
- create or update `PROJECT_SPECIFIC.md` when stable project rules are
  confirmed
- create `HANDOFF.md` only when continuity information is needed

Before substantial changes:

1. confirm the intended scope
2. inspect the affected area and current state
3. identify dependencies, risks, and appropriate checks
4. follow confirmed instructions and methods

### 2.1 Autonomous skill selection and invocation (Flexible & Proportional)

Skill usage is **dynamic, non-rigid, and proportional** — evaluate each task against available skill descriptions:
1. **Simple / Trivial Tasks**: (e.g. quick typo fix, 1-2 line edits, direct Q&A, minor style tweaks) ➔ Execute directly and immediately without loading heavy skills or announcing tags.
2. **Substantial Work & Critical Milestones**:
   - **Project / Feature Kickoff**: Naturally invoke brainstorming capabilities (e.g. `superpowers/brainstorming`) to explore trade-offs and draft `design.md`.
   - **Checkpoint / Session Handoff**: Naturally invoke session persistence (e.g. `planning-with-files` / `HANDOFF.md`) to record state and resume points.
   - **Domain Tasks**: Proactively match task context with the description of domain skills (e.g. `taste-skill` / `ui-ux-pro-max` for UI, `superpowers` for TDD / debugging, `humanizer` for copy).
3. **Transparent Tagging**: For substantial tasks where a skill is auto-activated, prefix the turn with a concise tag: `[Auto-Skill: <skill-name>] <brief reason>`.


For substantial Git-based work, inspecting the current state includes verifying
the actual repository and active branch. Do not rely solely on a Handoff,
previous conversation, or expected branch name.

When diagnosing a problem, determine whether the cause is local or shared.
Within the confirmed scope, prefer the smallest responsible root-cause fix over
duplicated local workarounds. Before changing shared logic, report the affected
areas, risks, and why a shared change is appropriate.

When a better method is found:

1. compare it with the current method
2. identify benefits, disadvantages, risks, and affected scope
3. recommend it to the user
4. obtain confirmation before materially changing the agreed approach

Do not change the intended outcome merely because another method is easier.

## 3. Classifying and organizing information

Classify new information before documenting it:

- broadly reusable principle or safeguard → propose a HAWS update
- reusable general procedure → propose a Work Instructions update
- stable confirmed project rule or definition → `PROJECT_SPECIFIC.md`
- current status, pending matter, risk, or resume information → `HANDOFF.md`
- information worth preserving for repeated use → an appropriate organized
  reusable source
- superseded information → Git history by default

Do not promote temporary or unconfirmed information into current truth.

Use clear headings and separate, as relevant:

- current scope
- confirmed decisions
- assumptions
- recommendations
- pending questions
- completed and remaining work
- checks and results
- risks and blockers
- exact resume point
- next action

Do not add unnecessary files or documentation layers when clear sections are
sufficient.

## 4. Review, action, and reporting

When the user says **Review**:

1. inspect the relevant work
2. identify findings, risks, conflicts, and recommendations
3. distinguish confirmed, assumed, recommended, and pending information
4. do not modify anything

When the user clearly requests reversible work within an agreed scope, proceed
within that scope.

Request explicit confirmation before destructive, irreversible, external,
sensitive, permission-changing, or materially out-of-scope actions.

After significant work, report:

- what changed and where
- checks performed and results
- unverified areas
- remaining risks or blockers
- remaining work
- next recommended action

## 5. Testing and completion

Run checks proportional to the scope and risk.

Test the expected behavior and relevant empty, invalid, boundary, repeated,
blocked, restart, consistency, side-effect, and failure cases.

Do not report checks or work as completed unless they were performed.

Before treating work as complete:

1. verify the agreed scope and required outcomes
2. run appropriate final checks
3. preserve stable confirmed project information in the appropriate current
   source
4. resolve or clearly retain pending matters
5. remove or close obsolete active Handoff information
6. report the final state and remaining limitations

## 6. Checkpoint and resume

When work must continue in another session, machine, tool, or AI agent, create
a recoverable checkpoint.

For Git-based projects, the default procedure is:

1. verify the repository and active working branch
2. inspect the worktree
3. run appropriate checks
4. update `HANDOFF.md`
5. commit the work and Handoff together when appropriate
6. push when safe and permitted
7. report the branch and current HEAD commit

A useful Handoff includes, as relevant:

- current goal and scope
- completed and remaining work
- confirmed decisions
- assumptions, recommendations, and pending questions
- checks and results
- risks or blockers
- exact resume point
- next action

The Handoff does not need to contain the SHA of the commit that contains it.

When resuming:

1. read the latest HAWS and Work Instructions
2. retrieve the project and verify the intended checkpoint
3. inspect the actual current state
4. read Project Specific and Handoff
5. compare documented and actual states
6. report the resume point before modifying anything

Do not restart completed work unless verification or changed conditions require
it.

## 7. Updating the standards

When HAWS or Work Instructions change, the user may instruct the AI to read the
central files again.

Propose changes according to their scope:

- broadly reusable principle → HAWS
- current recurring procedure → Work Instructions
- one-project rule → Project Specific
- current work state → Handoff

Do not update these sources automatically. Propose the smallest necessary
change and wait for review and confirmation.

## 8. AI-generated patch workflow (local apply)

Use when code changes are drafted by an AI that has no direct write access to
the user's local repository or remote (e.g. a sandboxed AI session).

1. Confirm scope conversationally (use brainstorming or clarifying questions if underspecified) before
   requesting a patch.
2. The AI must state the exact base state the patch is generated from (e.g.
   "based on the file(s) you uploaded on [date]"). If the local repository may
   have diverged since, re-share the current file(s) before generating a new
   patch — do not assume the previous diff still applies cleanly.
3. The AI chooses the patch format appropriate to the change:
   - **Unified diff** (`git apply`-compatible) for small, targeted edits to
     existing files.
   - **Full file replacement** when the file is new, changes exceed roughly
     half the file, or diff-conflict risk is high.
   The AI states which format it used and why.
4. Apply changes on a dedicated feature branch, not directly on the default
   branch:
   ```
   git checkout -b feature/<short-name>
   git apply <patch-file>   # or manually replace full files
   ```
5. Run appropriate build/test checks locally before committing.
6. Before committing, verify no confidential or real production/factory data
   is staged, per applicable Project Specific confidentiality rules.
7. Commit and push the feature branch; merge to the default branch only after
   verification.
8. Update `HANDOFF.md` at the checkpoint. The next AI session must be given
   the latest actual file state (not solely the previous diff or prior
   conversation memory) before further changes are requested.
