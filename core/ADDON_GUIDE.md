# HAWS Add-on & Extensibility Guide

A comprehensive, step-by-step guide for extending HAWS with new **Skills** (Single & Packs) and new **Subagents**, deployed automatically across **Google Antigravity** and **Claude Code**.

---

## 1. How to Add a New Skill

HAWS supports two types of skills under the open **AgentSkills.io** / Anthropic specification:

### Option A: Custom In-House Skill (Single Skill)
Create a standalone skill directly inside `skills/`:

1. **Create the directory**:
   ```bash
   mkdir -p skills/my-new-skill
   ```
2. **Create `skills/my-new-skill/SKILL.md`** with standard YAML frontmatter:
   ```markdown
   ---
   name: my-new-skill
   description: Brief 1-2 sentence description of capabilities. Use when [explicit trigger conditions].
   ---

   # My New Skill Instructions

   Provide actionable instructions, standards, and examples here.
   ```
   > **Pro Tip**: Use the **Anthropic Skill Creator** methodology: write a clear `description` with explicit `"Use when..."` triggers so AI agents can discover it via Progressive Disclosure without loading the entire body into memory.

3. **Deploy Globally**:
   Run `bash install.sh`. The installer will detect your new skill and create symlinks for both Claude Code and Antigravity automatically.

---

### Option B: External Open-Source Skill or Pack (GitHub Submodule)
Add a community skill or multi-skill pack (e.g. from GitHub):

1. **Add as a Git Submodule**:
   ```bash
   git submodule add https://github.com/<owner>/<repo>.git skills/<pack-name>
   ```
2. **Commit the Submodule**:
   ```bash
   git add .gitmodules skills/<pack-name>
   git commit -m "feat(skills): add <pack-name> skill pack"
   ```
3. **Deploy Globally**:
   Run `bash install.sh`.
   - If it's a **Single Skill** (`skills/<pack-name>/SKILL.md`), it is linked directly.
   - If it's a **Multi-Skill Pack** (with nested folders like `skills/<pack-name>/skills/<subskill>/SKILL.md`), `install.sh` automatically **flattens** each sub-skill into 1-level deep symlinks (e.g. `<pack-name>-<subskill>`), making them 100% discoverable by Google Antigravity and Claude Code!

---

## 2. How to Add a New Subagent

HAWS uses the **"Author Once, Deploy Everywhere"** pattern. You only ever write a subagent file once in `agents/`.

1. **Create `agents/<agent-name>.md`**:
   ```markdown
   ---
   name: devops-engineer
   description: Manages CI/CD pipelines, Docker containers, Kubernetes manifests, and cloud deployments. Use for containerization and infrastructure tasks.
   tools:
     - Read
     - Write
     - Edit
     - Grep
     - Glob
     - Bash
   model: inherit
   commandExecutionPolicy: prompt
   ---

   You are a senior DevOps engineer specializing in infrastructure automation and CI/CD pipelines.

   ## Core Responsibilities
   - Manage Dockerfiles, container orchestration, and CI workflows.
   - Write reproducible build scripts and deployment manifests.

   ## Quality Standards & Engineering Bar
   - Never commit raw secrets or environment tokens.
   - Keep build images minimal and hermetic.

   ## Recommended Skills (Contextual & Flexible)
   Skill invocation is dynamic and non-rigid:
   - Consider applying `superpowers/systematic-debugging` when troubleshooting build failures.
   ```

2. **Deploy Globally**:
   Run `bash install.sh`. The installer automatically translates and links your agent to:
   - **Claude Code**: `~/.claude/agents/<agent-name>.md`
   - **Google Antigravity**: `~/.gemini/config/agents/<agent-name>/agent.md` (1-level folder structure)

---

## 3. How Updates Work (`update.sh`)

When skill authors publish updates to upstream GitHub repositories, or when you pull updates on another machine:

```bash
bash update.sh
```

**What `update.sh` does in one step**:
1. Pulls the latest commits from the main HAWS repository (`git pull`).
2. Recursively updates all embedded Git Submodule skill links (`git submodule update --init --recursive --remote`).
3. Re-runs `install.sh` to link any newly added skills or agents.
4. Audits and warns about any dangling or deleted symlinks.
