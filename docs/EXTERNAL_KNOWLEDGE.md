# External Knowledge & Starred Repositories Digest

> **Owner**: `@researcher` | **Status**: Active Reference | **Last Updated**: 2026-09-04

This document preserves actionable insights, architectural patterns, and engineering techniques extracted from external repositories and user-starred GitHub projects to continuously improve HAWS.

---

## 🧘‍♂️ 1. `DietrichGebert/ponytail` (Lazy Senior Dev Mode)
- **Repository**: [DietrichGebert/ponytail](https://github.com/DietrichGebert/ponytail)
- **Philosophy**: *"He says nothing. He writes one line. It works. The best code is the code you never wrote."*
- **Measured Empirical Impact**: Cuts lines of code by ~54% (up to 94% on over-built tasks), reduces token consumption by ~22%, saves 20% cost, speeds up execution by 27%, while maintaining 100% test safety.

### The 7-Rung Lazy Ladder (Adopted into HAWS Section 5.1):
1. **Does this need to exist?** (YAGNI) $\rightarrow$ Speculative need = skip it.
2. **Already in this codebase?** $\rightarrow$ Reuse existing helper/util/pattern; never rewrite.
3. **Stdlib does it?** $\rightarrow$ Use language standard library.
4. **Native platform feature covers it?** $\rightarrow$ Use browser/OS native features (e.g. `<input type="date">` over flatpickr, CSS over JS, DB constraints over application logic).
5. **Installed dependency solves it?** $\rightarrow$ Use existing packages; never add a new dependency if a few lines suffice.
6. **Can it be one line?** $\rightarrow$ Make it one line.
7. **Only then**: Write the minimum code that works.

### Key Takeaway for HAWS:
- **Lazy about the solution, NEVER about reading**: Read the problem and the affected codebase thoroughly first; trace callers end-to-end; then climb the ladder.
- **Bug Fix = Root Cause**: Grep callers and fix once at the shared boundary rather than patching symptoms across multiple call sites.

---

## 🏛️ 2. `tt-a1i/archify` (Interactive Architecture & System Maps)
- **Repository**: [tt-a1i/archify](https://github.com/tt-a1i/archify)
- **Philosophy**: *"Turn a codebase or system description into a polished, interactive system map — directly in chat."*

### Key Capabilities:
1. **Typed JSON IR $\rightarrow$ Standalone Interactive HTML/SVG**: Produces self-contained interactive maps with dark/light theme switching, route probing, semantic lenses, and 1200×630 share cards.
2. **5 Specialized Diagram Types**:
   - `architecture`: Component boundaries, services, databases, cloud infrastructure.
   - `workflow`: CI/CD pipelines, approval gates, agent tool calls.
   - `sequence`: API call chains, request lifecycles, async traces.
   - `dataflow`: Pipelines, ETL/ELT, lineage, governance.
   - `lifecycle`: State machine transitions, retries, terminal states.
3. **Architecture Before / Delta / After**: Enables diffing architectural changes before pull request merge.
4. **Deterministic Showcase Validation**: Strict compiler checking 9 composition constraints to prevent AI hallucinated topologies.

### Key Takeaway for HAWS:
- Directly empowers **Topic 3.2: Architecture Dependency Graph ("Graft")** and **Topic 5.6: HAWS Visual Dashboard**.
- Architecture maps in `templates/SOT.md` and `templates/ARCHITECTURE.md` can be represented as structured JSON specifications compiled into shareable interactive HTML diagrams.