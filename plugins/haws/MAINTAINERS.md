# HAWS Plugin Maintenance Guide

This document is a concise working reference for maintaining and extending the HAWS plugin package.

---

## 1. How to Add Skills

HAWS supports both **custom in-house skills** and **external open-source skills repositories**.

### A. Custom In-House Skills (Local)
1. **Create the Skill File**:
   Create a dedicated directory: `plugins/haws/skills/<skill-name>/SKILL.md`.

2. **Define Required YAML Frontmatter**:
   Every skill must begin with `name` and `description`. The description must be concrete and actionable so an AI orchestrator can auto-invoke it when appropriate.
   
   ```yaml
   ---
   name: api-contract-designer
   description: Guides the design of RESTful and OpenAPI 3.0 specifications, ensuring standard URI patterns, semantic status codes, error payloads, and JSON schemas. Use when designing, reviewing, or modifying API interfaces.
   ---
   ```
   *Rule for effective descriptions*: Specify both what the skill provides and explicit trigger conditions ("Use when..."). Avoid vague summaries like "handles API design".

3. **Provide Instructions**:
   Write clear, modular instructions and quality standards directly in the markdown body.

4. **Automatic Discovery**:
   Skills located in `plugins/haws/skills/` are automatically discovered. No changes to `marketplace.json` or `plugin.json` are needed.

---

### B. Managing Embedded Open-Source Git Submodules

HAWS currently embeds **12 curated open-source skills repositories** (7 Single Skills + Top 5 Skill Packs) under `plugins/haws/skills/` via official Git Submodules (`.gitmodules`):

#### 1. Setup on a New Device (Initial Clone)
When cloning the HAWS repository to a new machine, always include `--recurse-submodules` to pull all embedded skills simultaneously:
```bash
git clone --recurse-submodules https://github.com/apirak-k/Human-AI-Working-Standard.git
```

If already cloned without submodules:
```bash
git submodule update --init --recursive
```

#### 2. Syncing & Updating Skills from Upstream GitHub
When original skill authors publish updates or bug fixes on their GitHub repositories:

```bash
# 1. Pull the latest commits from all upstream GitHub repositories
git submodule update --remote --merge

# 2. Stage and commit the updated submodule commit pointers
git add .
git commit -m "chore(skills): update submodules to latest upstream commits"
git push origin main
```

#### 3. Adding a New External Skill Submodule
To add a new open-source repository as an official submodule:
```bash
git submodule add https://github.com/<owner>/<repo>.git plugins/haws/skills/<skill-name>
git commit -m "feat(skills): add <skill-name> submodule"
git push
```

---

## 2. How to Add a New Subagent

1. **Create the Agent File**:
   Create `plugins/haws/agents/<agent-name>.md`.

2. **Define Required YAML Frontmatter**:
   Specify `name`, `description`, and scoped `tools`:
   
   ```yaml
   ---
   name: devops-engineer
   description: Manages CI/CD pipelines, Docker containers, Kubernetes manifests, infrastructure-as-code, and cloud deployment automation. Use for deployment configuration, containerization, and build scripts — not for core business logic or UI implementation.
   tools:
     - Read
     - Write
     - Edit
     - Grep
     - Glob
     - Bash
   ---
   ```

3. **Tool Scoping Reference**:
   - `frontend-engineer`: `Read, Write, Edit, Grep, Glob` (no shell execution)
   - `backend-engineer`: `Read, Write, Edit, Grep, Glob, Bash` (service/DB/API execution)
   - `tester`: `Read, Grep, Glob, Bash` (test execution & diagnostic verification)
   - `researcher`: `Read, Grep, Glob` (read-only codebase reconnaissance & documentation discovery)

4. **Write the System Prompt**:
   Define the role's domain responsibilities, engineering bar, and scope discipline.
   *Crucial rule*: Do **not** hardcode a fixed workflow or execution sequence relative to other agents. Delegation sequencing remains the dynamic judgment of the main orchestrating agent.

5. **Update the Orchestration Rule**:
   If the new agent introduces a new specialist domain, update `plugins/haws/rules/haws.md` under `## Role: Main Agent (Orchestrator)` to reflect its triage criteria.

---

## 3. How to Push & Pull Updates Across Devices

### On the Authoring Device (Making Changes)
```bash
# Stage changes (including submodules and rules)
git add .
git commit -m "Update HAWS: <summary of changes>"
git push origin main
```

### On Consumer / Client Devices (Receiving Updates)

#### Option A: Via AI Chat (Claude Code / Antigravity)
```text
/plugin marketplace update haws-marketplace
/plugin update haws@haws-marketplace
```

#### Option B: Via Git Terminal
```bash
git pull --recurse-submodules
```
