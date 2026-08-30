# HAWS Plugin Maintenance Guide

This document is a concise working reference for maintaining and extending the HAWS plugin.

---

## 1. How to Add a New Skill

1. **Create the Skill File**:
   Create `plugins/haws/skills/<skill-name>/SKILL.md`.

2. **Define Required YAML Frontmatter**:
   Every skill must begin with `name` and `description`. The description must be concrete and actionable so an AI orchestrator can auto-invoke it when appropriate.
   
   ```yaml
   ---
   name: api-contract-designer
   description: Guides the design of RESTful and OpenAPI 3.0 API specifications, ensuring standard URI patterns, semantic status codes, error payloads, and JSON schemas. Use when designing, reviewing, or modifying API interfaces.
   ---
   ```
   *Good description rule*: Specify both what the skill provides and explicit trigger contexts ("Use when..."). Avoid vague summaries like "handles API design".

3. **Provide System Prompt / Instructions**:
   Write clear, modular instructions and quality standards directly in the markdown body.

4. **No Manifest Changes Needed**:
   Skills inside `plugins/haws/skills/` are automatically discovered by plugin loaders. No updates to `marketplace.json` or `plugin.json` are required.

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
   - `frontend-engineer`: `Read, Write, Edit, Grep, Glob` (no shell access needed)
   - `backend-engineer`: `Read, Write, Edit, Grep, Glob, Bash`
   - `tester`: `Read, Grep, Glob, Bash` (verification-focused)

4. **Write the Agent's System Prompt**:
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
