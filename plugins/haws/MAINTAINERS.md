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

### B. Integrating Open-Source / External Skills Repositories

You can incorporate external community or open-source skills using one of three approaches:

#### Approach 1: Reference as an External Plugin via Marketplace (Recommended for Whole Repos)
If the open-source skills repo is packaged as a plugin, add it as an additional entry in `.claude-plugin/marketplace.json`:

```json
{
  "name": "haws-marketplace",
  "owner": { "name": "apirak-k" },
  "plugins": [
    {
      "name": "haws",
      "source": "./plugins/haws",
      "description": "Human-AI Working Standard"
    },
    {
      "name": "community-skills",
      "source": "github:organization/community-skills-repo",
      "description": "Curated open-source skills collection"
    }
  ]
}
```

#### Approach 2: Git Submodule (Recommended for Version-Locked Upstream Sync)
Embed an upstream open-source skills repository directly under `plugins/haws/skills/`:

```bash
git submodule add https://github.com/organization/skill-repo.git plugins/haws/skills/skill-repo
```
To update upstream changes later:
```bash
git submodule update --remote --merge
```

#### Approach 3: Standalone Import (Recommended for Individual Skills)
Copy individual open-source `SKILL.md` files directly into `plugins/haws/skills/<skill-name>/SKILL.md`, ensuring frontmatter compatibility (`name`, `description`) and preserving upstream attribution/license comments.

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

4. **Write the System Prompt**:
   Define the role's domain responsibilities, engineering bar, and scope discipline.
   *Crucial rule*: Do **not** hardcode a fixed workflow or execution sequence relative to other agents. Delegation sequencing remains the dynamic judgment of the main orchestrating agent.

5. **Update the Orchestration Rule**:
   If the new agent introduces a new specialist domain, update `plugins/haws/rules/haws.md` under `## Role: Main Agent (Orchestrator)` to reflect its triage criteria.

---

## 3. How to Push Updates to All Devices

1. **On the authoring device**:
   ```bash
   git add .
   git commit -m "Update HAWS plugin: <summary of changes>"
   git push
   ```

2. **On consumer/client devices**:
   ```text
   /plugin marketplace update haws-marketplace
   /plugin update haws@haws-marketplace
   ```
