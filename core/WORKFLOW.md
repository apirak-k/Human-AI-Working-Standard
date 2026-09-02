# HAWS Core Engineering Workflow & Skill Mapping

This document specifies the standard 6-phase software engineering lifecycle under HAWS and defines the primary and secondary skills to be executed during each phase.

---

## 🧭 The 6-Phase Lifecycle Overview

```text
[Phase 1: Discovery] ➔ [Phase 2: Ideation] ➔ [Phase 3: Spec & Plan]
       │
       ▼
[Phase 6: Handoff]   ◀─ [Phase 5: Verification] ◀─ [Phase 4: Implementation]
```

---

## 📋 Phase-by-Phase Skill Mapping

### Phase 1: Discovery & Clarification
- **Goal**: Uncover true intent, eliminate unexamined assumptions, probe ambiguities, and establish clear scope.
- **Primary Skills**:
  - `/interview-me` ➔ Extract what the user actually wants through focused questions before planning.
  - `/grill-me` ➔ Stress-test assumptions and probe potential pitfalls.
  - `/research` ➔ Investigate primary documentation and codebase facts.
- **Exit Criteria**: Problem statement, non-goals, and boundary constraints confirmed.

### Phase 2: Ideation & System Architecture
- **Goal**: Explore alternative approaches, model domains, and design resilient systems.
- **Primary Skills**:
  - `/brainstorming` ➔ Collaborative design, trade-off evaluation, and architecture exploration.
  - `/idea-refine` ➔ Divergent and convergent conceptual refinement.
  - `/domain-modeling` ➔ Define ubiquitous domain vocabulary, entities, and relationships.
  - `/drawio-skill` ➔ Generate architecture diagrams, sequence diagrams, and component flows.
- **Exit Criteria**: Architecture approach chosen, domain models documented in `templates/ARCHITECTURE.md` or design artifacts.

### Phase 3: Specification & Task Breakdown
- **Goal**: Write deterministic specifications and break work into ordered, testable increments.
- **Primary Skills**:
  - `/writing-plans` ➔ Structured implementation plans with clear review checkpoints.
  - `/planning-with-files` ➔ Persistent file-based task tracking for multi-step work.
  - `/spec-driven-development` ➔ Formal capability mapping before touching code.
- **Exit Criteria**: Approved implementation plan and task checklist.

### Phase 4: Implementation (Test-Driven & Disciplined)
- **Goal**: Execute changes incrementally with automated tests, clean boundaries, and zero unrequested churn.
- **Primary Skills**:
  - `/tdd` / `/test-driven-development` ➔ Red-Green-Refactor cycle; unit and integration test-first.
  - `/incremental-implementation` ➔ Small, reviewable, verifiable slices.
  - `/frontend-design` / `/ui-ux-pro-max` ➔ Production UI/UX components matching design tokens.
  - `/source-driven-development` ➔ Ground all framework patterns in verified official docs.
- **Exit Criteria**: Code builds cleanly, tests pass, and functionality matches spec.

### Phase 5: Verification & Quality Audit
- **Goal**: Prove correctness with empirical evidence before declaring completion.
- **Primary Skills**:
  - `/verification-before-completion` ➔ Evidence before assertions; run test suites and verify outputs.
  - `/systematic-debugging` ➔ Root-cause debugging when behavior deviates from expectations.
  - `/code-review` / `/code-review-and-quality` ➔ Multi-axis review (Standards, Spec, Security, Performance).
- **Exit Criteria**: 100% tests passing, zero lint regressions, security verified.

### Phase 6: Delivery, Documentation & Handoff
- **Goal**: Finalize documentation, capture learned lessons in Second Brain, and record clean project handoff.
- **Primary Skills**:
  - `/humanizer` ➔ Refine prose to eliminate artificial AI boilerplate.
  - `/caveman` ➔ Ultra-terse summaries and compressed status reports.
  - `/documentation-and-adrs` ➔ Record architectural decisions and user documentation.
  - `/haws-status` ➔ Verify skill health, token budget, and platform synchronization.
- **Exit Criteria**: Second Brain updated (`USER_PREFERENCES.md` / `ANTI_PATTERNS.md`), and local project `HANDOFF.md` updated.
