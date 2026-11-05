# Work Instructions

These instructions describe practical defaults for applying HAWS. Adapt them
to the task, user's instructions, project requirements, and available tools.
They are not a fixed checklist for every request.

## 1. Context and current state

At the start of a new project or work context, inspect only the information
needed to understand the request:

1. read HAWS and these Work Instructions if they are not already known in this
   context
2. read relevant Second Brain documents, project instructions, and Handoff
3. inspect the actual project, branch, and worktree state before relying on a
   written handoff
4. check available tools or specialized instructions when the task needs them
5. summarize the goal, scope, current state, and starting point for substantial
   work

Do not reload large documents or dump whole repositories without a reason.
Use an architecture map, dependency view, or file-backed plan when it makes a
complex task easier to understand or resume.

## 2. Start and perform work

Infer the user's intent from the current request and conversation. Ask only
when missing information materially affects the result, and continue useful
work that does not depend on the answer.

Before substantial changes, inspect the relevant implementation and callers,
identify dependencies and risks, and choose checks that can verify the result.
Use project templates or create planning documents when they provide durable
value; simple work does not need project scaffolding.

For software and systems work, apply the relevant guidance in
[`../docs/technical-practices.md`](../docs/technical-practices.md). Use it only
where it fits the task.

### 2.1 Tools, skills, and specialized methods

- Use a skill, tool, or structured method when its purpose fits the task.
- Read its instructions before applying a specialized workflow.
- Carry out the useful steps and verify the result; do not report methods that
  were not used.
- Keep simple requests direct and avoid process overhead that does not improve
  the outcome.

Delegate independent work when it materially improves speed or review quality
and the task instructions permit it. Read the relevant agent role before
delegating. Keep one primary responder responsible for the combined result.

### 2.2 Git and workspace safety

- Verify the repository, branch, worktree, and existing changes before editing.
- Preserve unrelated or pre-existing user work. Use an isolated worktree when
  it materially reduces conflicts or risk.
- Stage changes intentionally by logical concern. Avoid broad staging when
  unrelated files may be present.
- Use history tools such as `git bisect` when they are likely to locate a
  regression more efficiently than direct inspection and reproduction.
- Before removing a submodule or managed checkout, verify its registration,
  local changes, ownership, and dependent links.
- Do not push, publish, deploy, or merge unless the user has authorized it.

### 2.3 External tools and state changes

Read-only inspection and appropriate local checks can be used within the
authorized task. Ask for explicit authorization before destructive,
irreversible, sensitive, permission-changing, or external actions unless that
authorization is already clear in the request.

When a tool operation changes files, configuration, or runtime state, inspect
its result and report any required restart or refresh using instructions that
match the user's application and operating system.

## 3. Classify and organize information

Put information in the source that matches its scope:

- broadly reusable principles and safeguards → `HAWS.md`
- reusable practical procedures → `WORK_INSTRUCTIONS.md`
- confirmed rules for one project → `PROJECT_SPECIFIC.md`
- current progress, risk, or resume point → `HANDOFF.md`
- personal knowledge → a private or local Second Brain

Keep one authoritative source for each rule or concept. Do not make temporary
status, an unconfirmed idea, or an assumption into settled project guidance.
Use Git history for superseded material unless current users still need it.

## 4. Review and report

When the user asks for a Review, inspect and report findings, risks, conflicts,
and recommendations without changing files, repositories, systems, or external
state.

For authorized implementation work, report the changes, why they were needed,
checks performed, remaining risks, and next action. Use exact paths, source
links, command output, or line references when they help the reader verify a
claim. Mark important unchecked platforms or behaviors `[Unverified]`.

If a check fails, report the failure, trace its cause, and keep the original
assertions intact while fixing it. Do not hide failures, weaken checks, or
claim success without evidence.

If a configuration or path change requires restarting an application, state
the specific action and the right menu or command for that application.

## 5. Testing and completion

Choose tests and checks based on the change's scope and risk. Cover expected
behavior and relevant invalid, boundary, repeated, blocked, recovery, and
side-effect cases. Use isolated fixtures for tests that change files or state.

Before completion:

1. check the requested outcome against the actual final state
2. run the required and appropriate checks from the final tree
3. record material limitations and `[Unverified]` items
4. update Handoff or project documentation when it will help future work
5. close or clearly retain pending matters
6. report the result in a form the user can understand and act on

## 6. Checkpoint and resume

When work will continue in another session, tool, machine, or person, preserve
a concise checkpoint. For Git work, include the actual repository and branch,
worktree status, completed and remaining changes, checks, risks, and exact next
action. Update `HANDOFF.md` when it is the project's continuity source.

When resuming, compare the Handoff with the actual checkout and current files.
Do not restart completed work unless verification or changed conditions
require it. Commit or push only as authorized by the user and project rules.

## 7. Improve HAWS and Work Instructions

Before updating these documents, determine whether the lesson is broadly
reusable, a practical procedure, or project-specific. Check existing coverage,
remove unnecessary duplication, preserve useful safeguards, and keep the
change as small as the need permits. Follow the user's authorization for the
requested edit and report the change.

## 8. Applying an externally prepared patch

Use this section only when a separate tool or agent produced a patch that must
be applied to the user's checkout.

1. verify the patch's stated base against the current files
2. choose a targeted diff or full-file replacement based on conflict risk
3. apply it on the authorized branch or worktree
4. review the resulting diff and run relevant local checks
5. inspect staged files for unrelated or confidential data before committing
6. update Handoff when the work needs a checkpoint

## 9. Planning artifacts

For substantial work, create a specification, task plan, or project roadmap
when it will clarify requirements, dependencies, acceptance checks, or future
handoff. Choose the artifact format that fits the repository. Do not require a
fixed prompt, file name, or execution tool for every feature.

## 10. Second Brain

The public `secondbrain/` files are neutral starter documents. Personal
preferences, notes, and history belong in a private repository or local copy.
Preserve personal data during updates and cleanup, and verify the configured
remote before any action that could publish it.
