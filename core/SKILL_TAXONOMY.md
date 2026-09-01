# HAWS Skill Taxonomy & Tooling Catalog

> **Status**: Active Standard | **Owner**: @organizer | **Version**: 2.0

This document defines the functional categorization, discovery rules, and subagent affinities for all skills managed under HAWS.

---

## 🧭 Dynamic Taxonomy Principles

1. **Base Baseline (5 Drawers)**: Current skills are organized into 5 primary functional drawers.
2. **Extensibility Rule**: As skills grow, new drawers can be added dynamically (e.g., DevOps & Infrastructure, Mobile & Native, AI/ML Engineering) whenever it improves discovery and usability.
3. **Progressive Disclosure**: Agents MUST NOT load all skills at once. They browse Level 1 metadata and load Level 2 (SKILL.md) only on demand.

---

## 🗄️ Active Tooling Drawers

### 🧠 Drawer 1: Thinking & Planning
* **Purpose**: Intent extraction, architectural design, requirements engineering, and decision stress-testing.
* **Primary Subagent**: Leader, @researcher
* **Core Skills**:
  - `brainstorming` - Explore user intent, requirements, and design before coding.
  - `writing-plans` - Break complex multi-step requirements into executable plans.
  - `spec-driven-development` - Create formal specs before coding.
  - `idea-refine` - Divergent & convergent thinking to sharpen vague ideas.
  - `interview-me` - One-question-at-a-time interview to extract true underlying intent.
  - `grill-me` / `grilling` - Relentless stress-testing of designs and architecture.
  - `domain-modeling` - Build domain models, glossaries, and ADRs.
  - `planning-with-files` - Persistent file-based planning across multi-turn sessions.

### 💻 Drawer 2: Code & Engineering
* **Purpose**: Core implementation, API design, database querying, and cloud pipelines.
* **Primary Subagent**: @backend
* **Core Skills**:
  - `test-driven-development` / `tdd` - Red-Green-Refactor development.
  - `api-and-interface-design` - Stable API contracts and module boundaries.
  - `bigquery-sql` - Optimized BigQuery SQL and performance tuning.
  - `bigquery-ai-ml` - BigQuery ML and GenAI capabilities.
  - `gcp-data-pipelines` / `gcp-spark` / `gcp-dataflow` - Cloud data engineering pipelines.
  - `mcp-builder` - FastMCP and TypeScript MCP server development.
  - `code-simplification` - Refactoring and removing unnecessary complexity.

### 🎨 Drawer 3: UX/UI & Frontend
* **Purpose**: Production UI design, design tokens, component architecture, and visual polish.
* **Primary Subagent**: @frontend
* **Core Skills**:
  - `ui-ux-pro-max` - Comprehensive UI/UX intelligence, palettes, font pairings, and responsive UX.
  - `taste-skill` - Anti-slop frontend design system enforcement for landing pages and apps.
  - `frontend-design` / `frontend-ui-engineering` - Accessible, responsive UI implementation.
  - `drawio-skill` - Flowcharts, architecture diagrams, sequence diagrams, and visual maps.
  - `browser-testing-with-devtools` / `webapp-testing` - Real browser inspection and testing.

### 🔍 Drawer 4: Audit & Verification
* **Purpose**: Code verification, root cause debugging, security hardening, and standard audits.
* **Primary Subagent**: @tester, @organizer
* **Core Skills**:
  - `verification-before-completion` - Mandatory empirical evidence verification before completion.
  - `systematic-debugging` / `diagnosing-bugs` - Systematic root-cause debugging without guesswork.
  - `code-review-and-quality` / `code-review` - Multi-axis standards and spec review.
  - `security-and-hardening` - Security auditing, input sanitization, and vulnerability checks.
  - `receiving-code-review` / `requesting-code-review` - Rigorous review handling.

### 📝 Drawer 5: Docs & Communication
* **Purpose**: Document processing, tabular manipulation, concise formatting, and humanizer.
* **Primary Subagent**: Leader, @organizer
* **Core Skills**:
  - `caveman` - Ultra-compressed token-efficient communication mode.
  - `humanizer` - Natural prose rewriting removing AI-sounding filler.
  - `docx` / `pdf` / `pptx` / `xlsx` - Professional file parsing, extraction, and generation.
  - `doc-coauthoring` / `internal-comms` - Structured technical writing and status reports.
  - `skill-creator` / `writing-skills` - Authoring and benchmarking new agent skills.

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

## 🔄 Maintenance Protocol for @organizer
1. **Anthropic Standard Gatekeeping**: Whenever creating new custom in-house skills, @organizer ensures they strictly follow the **Anthropic Skill Standard** (`skill-creator` / `writing-skills`) before mapping them to their appropriate Drawer.
2. **Skill Usage & Invocations Telemetry**: @organizer continuously monitors and records the usage metrics and exact invocation counts of every skill used by the Main Agent and Subagents across all tasks. This quantitative telemetry is analyzed to optimize drawer categorization, retire unused capabilities, and guide new skill creation when high-frequency workflows emerge.
3. If a drawer grows beyond ~30 skills or a new specialized domain emerges, @organizer proposes a new Drawer branch to the user for approval.
