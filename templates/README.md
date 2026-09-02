# HAWS Project Blueprint Templates

This directory contains standardized templates for scaffolding and managing individual software projects under the Human-AI Working Standard (HAWS).

---

## 📁 Available Templates

| Template | File | Purpose |
| :--- | :--- | :--- |
| **Project Scope** | `PROJECT.md` | Defines project identity, primary users, tech stack, conventions, and boundary rules. |
| **System Architecture** | `ARCHITECTURE.md` | System topology, data contracts, database schema, and component responsibilities. |
| **Design System** | `DESIGN.md` | Complete UI tokens, color palette, typography, spacing, and WCAG AA accessibility rules. |
| **Quality Constraints** | `CONSTRAINTS.md` | Non-negotiable quality gates: test coverage, linters, types, and automated verification. |
| **Session Handoff** | `HANDOFF.md` | Local project session checkpoint, active task lists, and exact resume points. |

---

## 🚀 How to Use in a Project

### Option 1: Full Project Scaffold
When initializing a new repository, copy all templates into the project's root or `.haws/` directory:
```bash
# Example copying all templates into a new project
cp -r /path/to/HAWS/templates/* /path/to/new-project/
```

### Option 2: Modular Invocation
AI agents and developers can reference individual templates as needed during development:
- Consult `templates/DESIGN.md` when building new UI components.
- Consult `templates/CONSTRAINTS.md` before finalizing a feature or PR.
- Update `templates/HANDOFF.md` at the conclusion of a work session.
