# HAWS Project Blueprints and Templates

This directory contains 14 reusable blueprints and configuration templates for starting and maintaining software projects under the Human-AI Working Standard (HAWS), cleanly organized into three functional categories: `docs/`, `ai-configs/`, and `containers/`.

---

## How to Use These Templates

1. **Pick the relevant blueprint**: Select templates based on your current project phase (see the workflow mapping below).
2. **Copy to your project**: Copy the template into your project directory.
3. **Strip `.template` extensions**: For configuration files (e.g., `Dockerfile.template`), remove the `.template` suffix after copying so tools recognize the file name.
4. **Fill in project values**: Replace bracketed placeholders such as `[Project Name]` with your actual project details.

---

## Complete Blueprint Catalog

### 1. Documentation & Governance Blueprints (`templates/docs/`)

| Template | Target Path | When to Use | Purpose |
| :--- | :--- | :--- | :--- |
| `docs/PROJECT.md` | `PROJECT.md` | Phase 1-2 (Discovery) | Defines project scope, tech stack, roadmap, and verified live system ground truth (Source of Truth). |
| `docs/ARCHITECTURE.md` | `ARCHITECTURE.md` | Phase 2 (Ideation) | System topology, component boundaries, Mermaid diagrams, and machine-readable Archify JSON IR. |
| `docs/DESIGN.md` | `DESIGN.md` | Phase 2 (UI/UX) | Design tokens, color palette, typography hierarchy, responsive breakpoints, and WCAG AA accessibility rules. |
| `docs/CONSTRAINTS.md` | `CONSTRAINTS.md` | Phase 3 (Spec) | Non-negotiable quality contracts: coverage floors, linter rules, forbidden libraries, and verification runners. |
| `docs/AGENTS.md` | `AGENTS.md` | Phase 1-3 (Setup) | Establishes the agent role matrix, authorized scopes, forbidden actions, and universal build/test commands. |
| `docs/HANDOFF.md` | `HANDOFF.md` | Phase 6 (Handoff) | Preserves session continuity: active checklists, decisions made, unverified items, and exact resume points. |

### 2. Multi-AI Environment Adapters (`templates/ai-configs/`)

| Template | Target Path | When to Use | Purpose |
| :--- | :--- | :--- | :--- |
| `ai-configs/gemini/GEMINI.md.template` | `.gemini/GEMINI.md` | Phase 1 (Setup) | Workspace instructions blueprint for Google Antigravity (AGY) sessions. |
| `ai-configs/claude/CLAUDE.md.template` | `CLAUDE.md` | Phase 1 (Setup) | Workspace instructions blueprint for Claude Code CLI and web sessions. |
| `ai-configs/cursor/haws.mdc.template` | `.cursor/rules/haws.mdc` | Phase 1 (Setup) | Modern Cursor IDE rule configuration using MDC schema (`alwaysApply: true`, `globs: *`). |
| `ai-configs/copilot/copilot-instructions.md.template` | `.github/copilot-instructions.md` | Phase 1 (Setup) | Hooks GitHub Copilot and OpenAI Codex into HAWS core rules and project contracts. |

### 3. Container & Development Environment Blueprints (`templates/containers/`)

| Template | Target Path | When to Use | Purpose |
| :--- | :--- | :--- | :--- |
| `containers/devcontainer.json` | `.devcontainer/devcontainer.json` | Phase 1 (Setup) | Reproducible VS Code Dev Container with pre-installed Node.js, Python, Git, and development extensions. |
| `containers/Dockerfile.template` | `Dockerfile` | Phase 4 (Implementation) | Multi-stage production container build with an unprivileged non-root user (`apprunner`). |
| `containers/.dockerignore.template` | `.dockerignore` | Phase 4 (Implementation) | Leak-proof container ignore rules preventing `.git`, `.env*`, and build caches from entering images. |
| `containers/docker-compose.yml.template` | `docker-compose.yml` | Phase 4 (Implementation) | Local multi-service development stack configuring the application service with PostgreSQL and Redis. |

---

## Workflow Phase Mapping

- **Phase 1 (Discovery & Setup)**: Start with `docs/PROJECT.md` for scope and source of truth, and copy the relevant AI adapter from `ai-configs/` (`gemini/GEMINI.md.template`, `claude/CLAUDE.md.template`, `cursor/haws.mdc.template`, or `copilot/copilot-instructions.md.template`).
- **Phase 2 (Ideation & Architecture)**: Use `docs/ARCHITECTURE.md` for system diagrams and `docs/DESIGN.md` for UI tokens.
- **Phase 3 (Specification & Contracts)**: Establish `docs/CONSTRAINTS.md` and `docs/AGENTS.md` before writing code.
- **Phase 4 (Implementation & Build)**: Scaffold container configurations from `containers/` (`Dockerfile.template`, `.dockerignore.template`, `docker-compose.yml.template`).
- **Phase 5 (Verification & Quality)**: Validate changes against the quality bar set in `CONSTRAINTS.md`.
- **Phase 6 (Delivery & Handoff)**: Update `docs/HANDOFF.md` to summarize progress and record resume points.

