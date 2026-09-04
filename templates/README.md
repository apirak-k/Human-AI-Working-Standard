# HAWS Project Blueprints and Templates

This directory contains 14 reusable blueprints and configuration templates for starting and maintaining software projects under the Human-AI Working Standard (HAWS).

---

## How to Use These Templates

1. **Pick the relevant blueprint**: Select templates based on your current project phase (see the workflow mapping below).
2. **Copy to your project**: Copy the template into your project directory.
3. **Strip `.template` extensions**: For configuration files (e.g., `Dockerfile.template`), remove the `.template` suffix after copying so tools recognize the file name.
4. **Fill in project values**: Replace bracketed placeholders such as `[Project Name]` with your actual project details.

---

## Complete Blueprint Catalog

### 1. Governance and Workflow Blueprints

| Template | Target Path | When to Use | Purpose |
| :--- | :--- | :--- | :--- |
| `PROJECT.md` | `PROJECT.md` | Phase 1 (Discovery) | Defines project scope, tech stack, in-scope features, explicit non-goals, and milestone roadmap. |
| `AGENTS.md` | `AGENTS.md` | Phase 1-3 (Setup) | Establishes the agent role matrix, authorized scopes, forbidden actions, and universal build/test commands. |
| `HANDOFF.md` | `HANDOFF.md` | Phase 6 (Handoff) | Preserves session continuity: active checklists, decisions made, unverified items, and exact resume points. |
| `SOT.md` | `SOT.md` | Phase 2-3 (Architecture) | Single Source of Truth for live runtime architecture, verified data schemas, and permanent invariant lessons. |

### 2. Architecture and Quality Contracts

| Template | Target Path | When to Use | Purpose |
| :--- | :--- | :--- | :--- |
| `ARCHITECTURE.md` | `ARCHITECTURE.md` | Phase 2 (Ideation) | System topology, Mermaid component diagrams, and machine-readable Archify JSON IR. |
| `DESIGN.md` | `DESIGN.md` | Phase 2 (UI/UX) | Design tokens, color palette, typography hierarchy, responsive breakpoints, and WCAG AA accessibility rules. |
| `CONSTRAINTS.md` | `CONSTRAINTS.md` | Phase 3 (Spec) | Non-negotiable quality contracts: coverage floors, linter rules, forbidden libraries, and verification runners. |

### 3. Stack, DevOps, and Container Blueprints

| Template | Target Path | When to Use | Purpose |
| :--- | :--- | :--- | :--- |
| `Dockerfile.template` | `Dockerfile` | Phase 4 (Implementation) | Multi-stage production container build with an unprivileged non-root user (`apprunner`). |
| `.dockerignore.template` | `.dockerignore` | Phase 4 (Implementation) | Leak-proof container ignore rules preventing `.git`, `.env*`, and build caches from entering images. |
| `docker-compose.yml.template` | `docker-compose.yml` | Phase 4 (Implementation) | Local multi-service development stack configuring the application service with PostgreSQL and Redis. |
| `vite.config.ts.template` | `vite.config.ts` | Phase 4 (Implementation) | Vite frontend configuration with path aliases, build optimization, and automated lint checkers. |
| `.devcontainer/devcontainer.json` | `.devcontainer/devcontainer.json` | Phase 1 (Setup) | Reproducible VS Code Dev Container with pre-installed Node.js, Python, Git, and development extensions. |

### 4. Personal Second Brain Scaffolding

| Template | Target Path | When to Use | Purpose |
| :--- | :--- | :--- | :--- |
| `USER_PREFERENCES.example.md` | `secondbrain/USER_PREFERENCES.md` | Initial Setup (`haws.sh setup`) | Scaffolding for developer habits, communication style, and preferred architectural patterns. |
| `ANTI_PATTERNS.example.md` | `secondbrain/ANTI_PATTERNS.md` | Initial Setup (`haws.sh setup`) | Scaffolding for recording learned mistakes, forbidden libraries, and operational constraints. |

---

## Workflow Phase Mapping

- **Phase 1 (Discovery & Clarification)**: Start with `PROJECT.md` to lock in scope and boundaries.
- **Phase 2 (Ideation & Architecture)**: Use `ARCHITECTURE.md` for system diagrams and `DESIGN.md` for UI tokens.
- **Phase 3 (Specification & Contracts)**: Establish `CONSTRAINTS.md` and `AGENTS.md` before writing code.
- **Phase 4 (Implementation & Build)**: Scaffold `Dockerfile`, `.dockerignore`, `docker-compose.yml`, or `vite.config.ts`.
- **Phase 5 (Verification & Quality)**: Validate your changes against the quality bar set in `CONSTRAINTS.md`.
- **Phase 6 (Delivery & Handoff)**: Update `HANDOFF.md` to summarize progress and record resume points.

