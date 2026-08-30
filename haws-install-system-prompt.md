# Prompt for AGY — Build HAWS Cross-Tool Install/Update System (Symlink-Based)

## Goal

Build a single, simple install mechanism for the `Human-AI-Working-Standard`
(HAWS) repo that makes its skills and subagents available **globally** (all
projects, not just one repo) in **both Google Antigravity and Claude Code**,
from one canonical source, with:

- First-time setup = one command, run by an AI agent on the user's behalf
  (not a manual multi-step process for the human).
- Updates = one command that pulls the latest content with no manual
  re-copying of files.
- Only the AI tools actually present on the machine get set up (no
  installing things for tools the user doesn't use).
- Skills usable as slash commands inside Antigravity.
- Everything global-scope (not tied to one project folder).

This **replaces** the earlier `plugins/haws/` + `.claude-plugin/marketplace.json`
approach as the primary install path. Do **not delete** the existing
`plugins/haws/` folder or `.claude-plugin/marketplace.json` — leave them in
place, untouched, dormant. We may revisit them later. This new system is
built alongside them, not on top of them.

## Context

- Repo: `https://github.com/apirak-k/Human-AI-Working-Standard`
- Two target tools right now: **Antigravity** (priority — this is what the
  user actively uses today) and **Claude Code** (will start using later).
  Design so more tools can be added later without restructuring.
- Confirmed global discovery paths:
  | | Claude Code | Antigravity |
  |---|---|---|
  | Skills | `~/.claude/skills/<name>/SKILL.md` | `~/.gemini/config/skills/<name>/SKILL.md` |
  | Subagents | `~/.claude/agents/<name>.md` | `~/.gemini/config/agents/<name>/agent.md` |
  | Rules | (handled separately, out of scope here) | `~/.gemini/GEMINI.md` or `~/.gemini/AGENTS.md` |
- **Critical Antigravity constraint**: Antigravity only scans **one folder
  level deep** under its skills discovery path. Each skill's `SKILL.md` must
  sit directly inside `<skills-dir>/<skill-name>/SKILL.md` — no deeper
  nesting, or Antigravity will not see it.
- `SKILL.md` format (YAML frontmatter with `name` + `description`, body
  content below) is shared/compatible between Claude Code and Antigravity.
  One file works for both.
- Subagent file format is **not** shared — frontmatter fields differ
  (Claude Code uses `tools:`, Antigravity uses fields like `model:`,
  `commandExecutionPolicy:`). Each tool needs its own agent file, even if
  the instructional body content is similar.
- The 3 subagent files already exist at `plugins/haws/agents/`
  (`frontend-engineer.md`, `backend-engineer.md`, `tester.md`) written in
  Claude Code's format. These are the source material to adapt for
  Antigravity's format — do not rewrite their role/responsibility content,
  only adapt the frontmatter + format to fit Antigravity's schema.
- `skills/` content is currently **empty on purpose** — do not author new
  skills or restore the old deleted ones (`grill-me.md`, `caveman.md`,
  `qa-edgecase.md`, `drawio.md`) as part of this task. This task is
  infrastructure only. The install script must work correctly with zero
  skills present (exit gracefully, not error) so it's ready the moment
  skill content is added later.

## Step-by-step

1. **Restructure the repo** to hold canonical, tool-agnostic source content
   at the root level (flat structure, required by the Antigravity 1-level
   scan rule):
   ```
   Human-AI-Working-Standard/
   ├── skills/                      ← canonical, shared between both tools
   │   └── <skill-name>/SKILL.md    (currently empty — no folders yet, that's fine)
   ├── agents-claude-code/          ← Claude Code subagent format
   │   ├── frontend-engineer.md
   │   ├── backend-engineer.md
   │   └── tester.md
   ├── agents-antigravity/          ← Antigravity subagent format
   │   ├── frontend-engineer/agent.md
   │   ├── backend-engineer/agent.md
   │   └── tester/agent.md
   ├── install.sh
   ├── update.sh
   └── (existing files unchanged: HAWS.md, WORK_INSTRUCTIONS.md,
        TEMPLATES.md, README.md, plugins/, .claude-plugin/)
   ```
   Move the 3 existing agent files from `plugins/haws/agents/` into
   `agents-claude-code/` (this is a move/copy of existing tracked files, not
   a deletion of unique content — proceed without a checkpoint). Create the
   3 corresponding files in `agents-antigravity/`, translating frontmatter
   to Antigravity's schema while keeping the same role/responsibility body
   text.

2. **Write `install.sh`** (bash, POSIX-compatible where possible). Logic:
   - Detect which tools are present: check for `~/.claude/` directory
     (Claude Code) and `~/.gemini/` directory (Antigravity). Only set up
     detected tools. Print which tools were detected.
   - Determine a canonical local clone location, e.g. `~/haws`. If it
     already exists and is a git repo pointing at this same remote, `cd`
     into it and `git pull`. If it exists but is NOT this repo, **stop and
     ask the user** what to do (checkpoint — do not overwrite silently). If
     it doesn't exist, `git clone` the repo there.
   - For each detected tool, for every folder found under
     `~/haws/skills/<name>/`, create a symlink:
     - Claude Code: `~/.claude/skills/<name>` → `~/haws/skills/<name>`
     - Antigravity: `~/.gemini/config/skills/<name>` → `~/haws/skills/<name>`
     - Symlink **each individual skill folder**, never the parent `skills/`
       directory as a whole (this is required by Antigravity's 1-level scan
       rule).
     - If `~/haws/skills/` is empty, print a clear message ("no skills to
       link yet") and continue — this must not be treated as an error.
   - For each detected tool, symlink the relevant agent files:
     - Claude Code: `~/.claude/agents/<name>.md` → `~/haws/agents-claude-code/<name>.md`
     - Antigravity: `~/.gemini/config/agents/<name>` → `~/haws/agents-antigravity/<name>`
   - Before creating any symlink, check if the target path already exists:
     - If it's already a symlink pointing at the same source, skip (already
       installed, no-op).
     - If it's a symlink pointing somewhere else, or a real file/folder,
       **do not overwrite** — print a warning listing the conflicting path
       and skip it, so the user can resolve manually.
   - At the end, print a summary: tools detected, skills linked, agents
     linked, anything skipped/warned.

3. **Write `update.sh`**:
   - `cd ~/haws && git pull`.
   - Since symlinks point at live files, most content updates need nothing
     further. But re-run the same "ensure symlinks exist for every folder
     under skills/ and agents-*/" logic from `install.sh` (extract this
     into a shared function/section used by both scripts) so that any
     **newly added** skill or agent folder since the last install also gets
     linked.
   - If a skill/agent folder that previously existed has been removed from
     the repo, its symlink target will now be broken (dangling). Detect
     dangling symlinks that point back into `~/haws/` and **list them for
     the user** rather than silently deleting — removing them is a
     destructive action and needs explicit confirmation first.

4. **Update `README.md`** — add a short "Quick Install" section near the
   top with the two commands a user (or an AI acting for them) would run:
   one-liner to fetch and run `install.sh`, and the equivalent for
   `update.sh`. Keep this concise — a few lines, not a new guide.

## Output format

- Actual working `install.sh` and `update.sh` files, committed.
- Moved/created agent files as described in step 1.
- Updated `README.md` with the Quick Install section.
- A plain-text summary of every file created, moved, or modified.

## Guardrails

- Do not delete `plugins/haws/`, `.claude-plugin/marketplace.json`, or
  `plugins/haws/agents/` originals until the move in step 1 is verified
  complete (verify the new locations have correct, complete content before
  removing the old copies — or just leave the old copies in place if
  removing them isn't necessary for this task).
- Do not author any new skill content or restore deleted skills.
- Do not overwrite any existing file/symlink at a user's global path
  without checking first, per step 2.
- Do not touch `~/.gemini/GEMINI.md` or `~/.gemini/AGENTS.md` (rules files)
  — out of scope for this task.
- Any point where a decision can't be made safely by the script logic
  itself (conflicting existing files, ambiguous clone location, dangling
  symlinks after an update) must **stop and surface it to the user**
  instead of guessing.

## Definition of done

- `install.sh` runs cleanly on a machine with Antigravity, Claude Code, or
  both present, correctly detecting and only setting up what's present.
- Running `install.sh` twice in a row is safe (idempotent — second run
  reports "already installed", doesn't error or duplicate).
- `update.sh` pulls latest content and links any newly added skill/agent
  folders.
- Both scripts behave correctly with an empty `skills/` folder (current
  state) — no errors.
- README has the Quick Install section.

## Report back

When done, report:
1. Exact paths created/moved/modified.
2. Whether `install.sh` was actually test-run, and on which tool(s)
   (Antigravity / Claude Code / both), with the output.
3. Any warnings or skipped items hit during testing.
4. Anything from the guardrails section that required stopping for a
   decision, and what was decided.
