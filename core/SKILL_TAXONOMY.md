# HAWS Skill Taxonomy & Tooling Catalog

> **Status**: Active Standard | **Owner**: @organizer | **Version**: 2.0

This document defines the functional categorization, discovery rules, and subagent affinities for all skills managed under HAWS.

---

## 🧭 Dynamic Purpose-Driven Taxonomy Principles

1. **Usage-Driven Categorization**: Taxonomy is NOT dogmatically restricted to an arbitrary fixed number of drawers. `@organizer` continuously structures, merges, splits, or creates new domain drawers (e.g., Cloud & DevOps, AI/ML, Mobile & Native) dynamically according to real-world workflows.
2. **Autonomous Governance by `@organizer`**: Subagent `@organizer` has full authority to evaluate and assign skills to the best-fitting drawer, always providing a transparent post-action summary in chat.
3. **Sub-Second Native Inspection**: Health auditing and skill counting must execute instantly via `bash haws.sh status` (< 0.5s) without slow shell loops.
4. **Progressive Disclosure**: Agents MUST NOT load all skills at once. They browse Level 1 metadata and load Level 2 (`SKILL.md`) only on demand.


---

## 🗄️ Active Tooling Drawers & Complete 102 Skills Mapping

### 🧠 Drawer 1: Thinking & Planning (26 Skills)
* **Purpose**: Intent extraction, architectural design, requirements engineering, decision stress-testing, and vertical task breakdown.
* **Primary Subagent**: Leader, @researcher
* **Catalog**:
  - `brainstorming` — Explore user intent, requirements, and design before coding.
  - `writing-plans` — Break complex multi-step requirements into executable plans.
  - `executing-plans` — Execute multi-step implementation plans systematically.
  - `planning-and-task-breakdown` — Vertical slice task breakdown with checkpoints.
  - `planning-with-files` — Persistent file-based planning across multi-turn sessions (`task_plan.md`).
  - `spec-driven-development` — Create formal specifications before coding.
  - `to-spec` — Convert unstructured thoughts and conversations into structured specs.
  - `to-tickets` — Break design specs down into granular engineering tickets.
  - `to-questionnaire` — Generate targeted questionnaires for stakeholders.
  - `idea-refine` — Divergent & convergent thinking to sharpen vague ideas.
  - `interview-me` — One-question-at-a-time interview to extract true underlying intent.
  - `grill-me` / `grilling` — Relentless stress-testing of designs and architecture.
  - `grill-with-docs` — Stress-test designs against official documentation and primary sources.
  - `domain-modeling` — Build domain models, ubiquitous language, and ADRs.
  - `codebase-design` — Evaluate architectural patterns and component boundaries.
  - `graphify` — Codebase knowledge graph, community detection, and architectural relationship mapping.
  - `prototype` — Fast spike prototypes to validate technical feasibility.
  - `research` — High-trust primary source investigation and Markdown synthesis.
  - `discernment-nudge` — Strategic sanity-checking of engineering decisions.
  - `doubt-driven-development` — Rigorous questioning of architectural assumptions.
  - `ask-matt` — Domain consultation on TypeScript and modern software architecture.
  - `wayfinder` — Route complex requests to the right engineering workflow.
  - `wait-what` — Intercept ambiguous requirements before making mistaken assumptions.
  - `wizard` — Interactive multi-step setup and wizard workflows.
  - `triage` — Rapid assessment and priority triage of bugs and tasks.

### 💻 Drawer 2: Code & Engineering (25 Skills)
* **Purpose**: Core implementation, API design, database querying, refactoring, and cloud pipelines.
* **Primary Subagent**: @backend-engineer
* **Catalog**:
  - `test-driven-development` / `tdd` — Red-Green-Refactor implementation discipline.
  - `implement` — Direct, focused execution of approved specifications.
  - `implement-spec` — Spec-compliant vertical implementation workflow.
  - `api-and-interface-design` — Stable REST/RPC contracts and module boundaries.
  - `code-simplification` — Refactoring and removing unnecessary boilerplate (YAGNI).
  - `improve-codebase-architecture` — Structural codebase refactoring and modernization.
  - `source-driven-development` — Documentation-grounded implementation with official sources.
  - `incremental-implementation` — Delivering complex features in small, verifiable steps.
  - `constraint-driven-development` — Building software within explicit system constraints.
  - `mcp-builder` — FastMCP and TypeScript Model Context Protocol server development.
  - `claude-api` — Direct SDK integration with Anthropic Claude API.
  - `migrate-to-shoehorn` — Type-safe test fixture migrations without `as` casting.
  - `setup-ts-deep-modules` — Clean TypeScript project layouts and deep module exports.
  - `setup-pre-commit` — Automated Git pre-commit hooks configuration.
  - `subagent-driven-development` — Coordinated multi-step task execution via subagents.
  - `dispatching-parallel-agents` — Parallel subagent execution for independent tasks.
  - `using-git-worktrees` — Isolated Git worktrees for safe parallel development.
  - `git-workflow-and-versioning` — Branching strategies, SemVer, and commit hygiene.
  - `git-guardrails-claude-code` — Safeguards preventing uncommitted data loss.
  - `resolving-merge-conflicts` — Structured Git merge and rebase conflict resolution.
  - `deprecation-and-migration` — Safe sunsetting and migration of legacy systems.
  - `finishing-a-development-branch` — Verification, squashing, and merging workflows.
  - `shipping-and-launch` — Production launch checklists and deployment strategies.
  - `ci-cd-and-automation` — Automated build pipelines, GitHub Actions, and quality gates.

### 🎨 Drawer 3: UX/UI & Frontend (13 Skills)
* **Purpose**: Production UI design, design tokens, component architecture, visual polish, and diagrams.
* **Primary Subagent**: @frontend-engineer
* **Catalog**:
  - `ui-ux-pro-max` — Comprehensive UI/UX intelligence, palettes, font pairings, and responsive UX.
  - `taste-skill` — Anti-slop frontend design system enforcement for landing pages and apps.
  - `frontend-design` — Accessible, distinctive visual design and typography.
  - `frontend-ui-engineering` — High-performance frontend component architecture.
  - `drawio-skill` — Flowcharts, architecture diagrams, sequence diagrams, and visual maps.
  - `canvas-design` — Canvas rendering, graphics manipulation, and visual layout.
  - `brand-guidelines` — Official brand colors, typography, and visual design standards.
  - `theme-factory` — Multi-theme management (dark/light mode, custom palettes).
  - `web-artifacts-builder` — Interactive HTML/React web artifact development.
  - `browser-testing-with-devtools` — Real browser inspection and DevTools debugging.
  - `webapp-testing` — End-to-end browser automation and interaction testing with Playwright.
  - `slack-gif-creator` — Animated GIF generation and optimization for Slack.
  - `algorithmic-art` — Procedural and algorithmic visual art generation.

### 🔍 Drawer 4: Audit & Verification (13 Skills)
* **Purpose**: Code verification, root cause debugging, security hardening, performance audits, and QA.
* **Primary Subagent**: @tester, @organizer
* **Catalog**:
  - `verification-before-completion` — Mandatory empirical evidence verification before completion.
  - `systematic-debugging` — Systematic root-cause debugging without guesswork (`Input ➔ State ➔ Output`).
  - `diagnosing-bugs` — Hard bug and performance regression diagnosis loop.
  - `debugging-and-error-recovery` — Contained error recovery and fault isolation.
  - `receiving-code-review` — Technical verification of code review feedback.
  - `requesting-code-review` — Pre-merge quality and specification adherence audits.
  - `doubt-driven-development` — Adversarial decision verification before standing.
  - `code-review` — Two-axis review against local standards and originating specs.
  - `code-review-and-quality` — Multi-axis code review across correctness, security, and style.
  - `security-and-hardening` — Security auditing, input sanitization, and vulnerability checks.
  - `performance-optimization` — Profiling, latency optimization, and memory tuning.
  - `observability-and-instrumentation` — Metrics, structured logging, and tracing.
  - `retro` — Engineering retrospectives and continuous process improvement.
  - `loop-me` — Autonomous iterative testing and verification loops.

### 📝 Drawer 5: Docs & Communication (25 Skills)
* **Purpose**: Document processing, token compression, humanizer, meta-tools, and skill authoring.
* **Primary Subagent**: Leader, @organizer
* **Catalog**:
  - `caveman` — Ultra-compressed token-efficient communication mode.
  - `humanizer` — Natural prose rewriting removing AI-sounding filler.
  - `doc-coauthoring` — Structured technical writing and collaborative documentation.
  - `documentation-and-adrs` — Architecture Decision Records and public API documentation.
  - `internal-comms` — Team announcements, status updates, and release notes.
  - `docx` — Microsoft Word document parsing, formatting, and generation.
  - `pdf` — PDF extraction, form filling, and report compilation.
  - `pptx` — Presentation slides creation and styling.
  - `xlsx` — Spreadsheet creation, formulas, and tabular data manipulation.
  - `writing-for-agents` — Authoring clear, deterministic documentation for AI agents.
  - `writing-beats` — Narrative rhythm and pacing for technical writing.
  - `writing-shape` — Structural shaping of long-form essays and documentation.
  - `writing-fragments` — Modular writing pieces and reusable documentation snippets.
  - `skill-creator` — Authoring and benchmarking new agent skills (Anthropic Standard).
  - `writing-skills` — Step-by-step skill authoring, TDD, and validation.
  - `using-superpowers` — Meta-skill for skill discovery and invocation protocols.
  - `using-agent-skills` — Discovery engine for Addy Osmani agent skills.
  - `context-engineering` — Context window optimization and rule file structuring.
  - `claude-handoff` — Multi-session continuity and handoff document generation.
  - `handoff` — Project checkpointing and session state persistence.
  - `teach` — Interactive technical tutorial generation and concept explanation.
  - `scaffold-exercises` — Coding exercise generation with tests and solutions.
  - `academy-guide` — Interactive learning guides and curriculum authoring.
  - `setup-matt-pocock-skills` — Configuration and environment setup for Matt Pocock skills.
  - `template-skill` — Standardized skill and document templating.

---

## 🎯 Subagent Affinity Matrix

| Subagent | Primary Drawers | Secondary Drawers |
| :--- | :--- | :--- |
| **@organizer** | Drawer 4 (Audit), Drawer 5 (Docs) | Drawer 1 (Planning) |
| **@tester** | Drawer 4 (Audit), Drawer 2 (Code) | Drawer 3 (UI Testing) |
| **@frontend** | Drawer 3 (UX/UI), Drawer 2 (Code) | Drawer 5 (Docs) |
| **@backend** | Drawer 2 (Code), Drawer 4 (Audit) | Drawer 1 (Architecture) |
| **@researcher**| Drawer 1 (Thinking), Drawer 5 (Docs) | Drawer 2 (Code Exploration) |

---

## 🔄 Autonomous Maintenance Protocol for @organizer
1. **Full Autonomous Authority**: @organizer operates with full autonomous authority to dynamically categorize new skills, adjust drawer mappings, and optimize the taxonomy across `SKILL_TAXONOMY.md` whenever new skills or tooling packages are installed (e.g. via `bash haws.sh sync`, submodule updates, or `skill-creator`).
2. **Mandatory Post-Action Reporting**: After performing any taxonomy modifications, drawer adjustments, or skill categorizations, @organizer MUST always deliver a structured, transparent change summary directly in chat for human awareness (`[Taxonomy Update] <skills categorized / drawers created>`).
3. **Anthropic Standard Gatekeeping**: Whenever creating new custom in-house skills, @organizer ensures they strictly follow the **Anthropic Skill Standard** (`skill-creator` / `writing-skills`) before mapping them to their appropriate Drawer.
4. **Skill Usage & Invocations Telemetry**: @organizer continuously monitors and records the usage metrics and exact invocation counts of every skill used by the Main Agent and Subagents across all tasks. This quantitative telemetry is analyzed to dynamically optimize drawer categorization, retire unused capabilities, or expand new Drawers (e.g., DevOps & Cloud, AI/ML Engineering, Mobile & Native) when high-frequency domain clusters emerge.

