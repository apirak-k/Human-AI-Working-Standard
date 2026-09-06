# Engineering Quality Constraints & Contracts — [Project Name]

This document establishes the non-negotiable quality bar and automated verification contract for this project.

---

## 1. Non-Negotiable Quality Gates

| Dimension | Threshold / Standard | Verification Command | Enforcement Policy |
| :--- | :--- | :--- | :--- |
| **Unit Test Coverage** | >= 80% line coverage | `npm run test:coverage` / `pytest --cov` | Block PR / Commit |
| **Linting & Formatting** | 0 errors, 0 warnings (ESLint/Biome) | `npm run lint` / `npx biome check` | Strict CI fail |
| **Type Safety** | 0 TypeScript/Mypy errors | `npm run typecheck` / `mypy` | Zero `@ts-ignore` without review |
| **Dependency Security** | Zero High/Critical CVEs | `npm audit --audit-level=high` | Block PR / Build |
| **Lockfile Invariant** | Lockfiles committed & immutable | `git status --porcelain` | Must commit with dependencies |
| **Container Standards** | Non-root user, .dockerignore | `docker build --check .` | Mandatory for container images |
| **Build Integrity** | Clean build (exit code 0) | `npm run build` | Must pass locally before commit |
| **Accessibility** | WCAG 2.1 AA compliant | Automated axe-core / linter | Mandatory for UI components |

---

## 2. Hard Anti-Patterns in this Codebase
- **No Suppressions**: Never quietly add `@ts-ignore`, `eslint-disable`, `# type: ignore`, or skip tests to turn CI green.
- **Dependency Gate (Ponytail Rung 5)**: Never add external libraries when language standard library or concise code achieves the same result.
- **Lockfile Protection**: Never ignore, delete, or regenerate lockfiles to mask dependency conflicts.
- **Container Hygiene**: Never run containers as root in production; never build container images without a strict `.dockerignore`.
- **Documentation Preservation**: Never delete, truncate, or strip existing comments, docstrings, or type annotations.
- **Targeted Edits Over Broad Churn**: Limit edits strictly to the necessary functional scope; no unprompted rewrites of surrounding code.
- **No Synthetic Mocks in Prod Code**: Production logic must rely on verified interfaces, never placeholder stubs.

---

## 3. Automated Verification Script
Run the project's single-command verification runner before every commit:
```bash
# Example verification pipeline
npm run lint && npm run typecheck && npm test
```
