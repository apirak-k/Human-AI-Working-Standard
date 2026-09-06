# HAWS Project Blueprints and Templates

This directory contains the canonical documentation and governance blueprints for starting and maintaining software projects under the Human-AI Working Standard (HAWS), located in `docs/`.

---

## How to Use These Templates

1. **Pick the relevant blueprint**: Select templates based on your current project phase (see the workflow mapping below).
2. **Copy to your project**: Copy the template into your project root directory.
3. **Fill in project values**: Replace bracketed placeholders such as `[Project Name]` with your actual project details.

---

## Documentation & Governance Blueprints (`templates/docs/`)

| Template | Target Path | When to Use | Purpose |
| :--- | :--- | :--- | :--- |
| `docs/PROJECT.md` | `PROJECT.md` | Phase 1-2 (Discovery) | Defines project scope, tech stack, roadmap, and verified live system ground truth (Source of Truth). |
| `docs/ARCHITECTURE.md` | `ARCHITECTURE.md` | Phase 2 (Ideation) | System topology, component boundaries, Mermaid diagrams, and machine-readable Archify JSON IR. |
| `docs/DESIGN.md` | `DESIGN.md` | Phase 2 (UI/UX) | Design tokens, color palette, typography hierarchy, responsive breakpoints, and WCAG AA accessibility rules. |
| `docs/CONSTRAINTS.md` | `CONSTRAINTS.md` | Phase 3 (Spec) | Non-negotiable quality contracts: coverage floors, linter rules, forbidden libraries, and verification runners. |
| `docs/AGENTS.md` | `AGENTS.md` | Phase 1-3 (Setup) | Establishes the agent role matrix, authorized scopes, forbidden actions, and universal build/test commands. |
| `docs/HANDOFF.md` | `HANDOFF.md` | Phase 6 (Handoff) | Preserves session continuity: active checklists, decisions made, unverified items, and exact resume points. |

---

## Workflow Phase Mapping

- **Phase 1 (Discovery & Setup)**: Start with `docs/PROJECT.md` for project scope, source of truth, and system ground truth.
- **Phase 2 (Ideation & Architecture)**: Use `docs/ARCHITECTURE.md` for system diagrams and `docs/DESIGN.md` for UI tokens.
- **Phase 3 (Specification & Contracts)**: Establish `docs/CONSTRAINTS.md` and `docs/AGENTS.md` before writing code.
- **Phase 4 (Implementation & Build)**: Implement according to architecture and design specifications.
- **Phase 5 (Verification & Quality)**: Validate changes against the quality bar set in `CONSTRAINTS.md`.
- **Phase 6 (Delivery & Handoff)**: Update `docs/HANDOFF.md` to summarize progress and record resume points.

