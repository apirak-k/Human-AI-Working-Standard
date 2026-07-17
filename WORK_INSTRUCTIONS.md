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
4. read `PROJECT_SPECIFIC.md` if it exists
5. read `HANDOFF.md` when continuing existing work
6. report the understood goal, scope, current state, and starting point

Read HAWS and applicable project information once per thread or work context.

Do not reread them every message unless they were updated, the context changed,
or uncertainty exists.

Do not inspect Git history unless current information is insufficient,
conflicting, or historical verification is required.

Read only the Specific, Handoff, and reusable information relevant to the
current project and task.

## 2. Starting and performing work

For a new project:

- do not invent project rules
- create or update `PROJECT_SPECIFIC.md` when stable project rules are
  confirmed
- create `HANDOFF.md` only when continuity information is needed

Before substantial changes:

1. confirm the intended scope
2. inspect the affected area and current state
3. identify dependencies, risks, and appropriate checks
4. follow confirmed instructions and methods

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
