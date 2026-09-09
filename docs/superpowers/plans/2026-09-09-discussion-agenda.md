# HAWS Discussion Agenda

## Purpose

This agenda is a discussion index, not an acceptance record and not an
implementation plan. Review each topic with the user before deciding whether
it is accepted, changed, deferred, or removed. Only after discussion should
the result be compared with the nine-task CLI redesign plan.

## Current Review Point

The baseline is the user's original 39 topics. The next conversation starts
with the items added **after** that baseline. Every item remains discussable;
this document must never use an anchor or a status label to silently exclude an
item.

For this review:

- **Baseline** means it is in the original 39-topic source.
- **After 39** means it was introduced by later handoff/design history, a
  starred-repository follow-up, or the user's later list.
- A topic may overlap a baseline topic, but remains an After-39 discussion item
  until the user decides to merge or remove it.

## Evidence Sources

1. Baseline raw topics: `git show cceb211:task_plan.md`.
2. Baseline-to-current change record: `HANDOFF.md` and its Git history after
   `cceb211`.
3. Current CLI redesign: `docs/superpowers/specs/2026-09-09-haws-cli-design.md`
   and `docs/superpowers/plans/2026-09-09-haws-cli-implementation.md`.
4. Installed source inventory: `.gitmodules`.
5. User-provided topics not yet recorded in the repository.

## Review Method

For every agenda item, capture one of: `accepted`, `change`, `defer`, or
`remove`. Do not mark an item implemented merely because an earlier handoff
claims it was completed. After this review, map the resolved item to one or
more CLI tasks, or mark it outside the CLI redesign scope.

## Master Discussion Agenda — 66 Unique Topics

This is the list to discuss. Items 1–39 are the original baseline, preserved
as individual user topics. Items 40–66 were added afterwards. A later item is
only appended when it is materially distinct; duplicate wording stays merged
into its earlier topic rather than receiving a second number.

### Original 39 Topics

1. React Component
2. Markdown organization to reduce context window
3. Frequently used skill categories
4. Review repositories starred by the user
5. Complete HAWS installation guide
6. What installation/update checks and reports must include
7. Standard `design.md`
8. Automatic skill and subagent use
9. Anti-hallucination: report actual latest task results
10. Organizer quality
11. Skill bloat management
12. Declare the skill used by every agent
13. Best practices
14. Subagents
15. Ponytail repository
16. Project, agent, source-of-truth, roadmap, and UX Markdown files
17. Code dependency map (Graft)
18. `.env`
19. Wayfinder / SEO skill
20. Reload-window notification
21. Normalization
22. Wrong-keyboard-layout / CapsLock fixer skill
23. Real token status
24. Context window
25. RAG
26. HAWS dashboard
27. SWE fundamentals
28. Caveman answers for closed questions
29. MCP
30. Agent persona
31. Thinking-time and skill-use-count analysis
32. Good testing
33. Loop engineering
34. Token management
35. On-demand loading
36. Agent harness
37. Human approval before GitHub push
38. Caveman levels
39. Relevant skills and commands

### Added After 39 — Unique Topics Only

40. Private, decoupled Second Brain and local/cloud synchronization
41. Git hooks, safe uninstall, and lifecycle ownership
42. Cross-platform launcher and installation evolution
43. Multi-AI adapters, native Codex roles, and Graphify discovery compatibility
44. Source/KIT selection, skill enablement, and provenance
45. Device-local AI environment and AI-provider configuration selection
46. Change-aware sync/update: independent targets, offline/timeout behavior,
    and update only what changed or is active
47. Skill-first source layout and Figma integration
48. Handoff Pro Max
49. 3.8 Flash
50. `.enc` / HAWS encryption
51. Essential Git usage
52. Package and dependency policy
53. Docker container policy
54. Legacy project-server hardware
55. Second Brain template quality
56. Emoji-removal policy
57. Human-readable skill descriptions
58. Workflow, Work Instructions, and README coverage
59. Automatic plugin use
60. Anti-AI-slop quality standard
61. Action log, Git history, and progressive disclosure
62. Use HAWS to improve HAWS
63. Evidence-based 100% pass wording; do not use vague "green" claims
64. Todo / Doing / Done status model
65. Skill-to-model recommendations
66. Cross-device resume: source priority and disclosure of what was read

### Explicitly Merged Rather Than Added Again

These later phrasings are already represented above and therefore do not add a
new agenda number: skill reporting; direct concise answers and relevant
recommendations; targeted/exhaustive testing; Loop Engineering with GitHub;
autonomous subagents; skill recommendation; status checks; and starred-repo
review. Their original wording remains in section E for traceability.

Sections A–E below are evidence and the raw-wording crosswalk. They are not a
second agenda and must not be used to change the 66-topic count silently.

## A. Baseline: 39 Raw Topics

Keep the raw IDs so the user can review them individually. Historic documents
call the grouping "22 topics", but their own checklist contains 24 themed
rows; `HANDOFF.md` also lists remote-push control as a separate guardrail.
This agenda therefore uses 25 discussion rows without treating either historic
summary count as authoritative.

| Review topic | Raw IDs | Discussion label |
|---|---:|---|
| A1 | 9, 13 | Grounding, evidence, and anti-hallucination behavior |
| A2 | 8, 12 | Automatic skill and subagent use; skill-use transparency |
| A3 | 28, 38 | Caveman communication levels |
| A4 | 20 | Reload-window notification |
| A5 | 2, 24 | Markdown organization and context-window management |
| A6 | 23, 34 | Real token status and token management |
| A7 | 35 | On-demand loading |
| A8 | 31 | Thinking-time and skill-use metrics |
| A9 | 16 | Project, agent, source-of-truth, roadmap, and UX documents |
| A10 | 17 | Architecture graph |
| A11 | 18 | Environment-file and secret handling |
| A12 | 1, 7 | React components and design standard |
| A13 | 21 | Repository normalization |
| A14 | 3, 11 | Skill taxonomy and bloat management |
| A15 | 10 | Organizer role and system hygiene |
| A16 | 14, 30, 36 | Subagent roles, personas, and harness |
| A17 | 33, 39 | Engineering loop and relevant commands/skills |
| A18 | 19, 22 | Wayfinder and keyboard-layout-fixer skills |
| A19 | 5 | Complete HAWS installation experience |
| A20 | 6 | Install/update diagnostics and reporting |
| A21 | 27, 32 | SWE fundamentals and testing |
| A22 | 25, 29 | MCP and RAG integrations |
| A23 | 4, 15 | Starred repositories and Ponytail |
| A24 | 26 | HAWS dashboard |
| A25 | 37 | Human approval before remote push |

The rows preserve discussion boundaries, not a new count of raw inputs.

## B. Additions After 39 Recorded in History and Design

These are candidate discussion topics derived from handoff history and later
design records. They may overlap the baseline topics. Do not assume they are
new requirements until reviewed with the user.

| ID | Candidate topic | Primary evidence |
|---|---|---|
| B1 | Private, decoupled Second Brain and its local/cloud synchronization model | `HANDOFF.md`; commits after `840ca9f` and `10f5f0d` |
| B2 | Git hooks, safe uninstall, and lifecycle ownership | `HANDOFF.md`; commits `e485453` and `6f54cce` |
| B3 | Cross-platform launcher and installation evolution | `HANDOFF.md`; launcher and setup commits after `403f130` |
| B4 | Multi-AI adapters, native Codex roles, and Graphify discovery compatibility | `HANDOFF.md`; commits `82a1cdb`, `535d36f`, `7179722`, and `efcd6f0` |
| B5 | Source/KIT selection, skill enablement, and provenance | `HANDOFF.md`; KIT and setup commits after `ab260e9` |
| B6 | Device-local AI-environment selection and preservation | `HANDOFF.md` Category B; commit `689d52f` |
| B7 | Offline/timeout behavior and independent sync outcomes | `HANDOFF.md` Category B; commits `77d3fc1` and `ae052e1` |
| B8 | Skill-first source layout for tools that include a `SKILL.md` entrypoint | `HANDOFF.md` Category C |
| B9 | CLI redesign: safe first install, settings, guarded sync, read-only health checks, ownership-aware uninstall, and batch-launcher retirement | 2026-09-09 CLI design and nine-task implementation plan |

## C. Starred-Repository Follow-Up After 39

The baseline has one explicit raw topic for reviewing starred repositories and
one for Ponytail. The repository has no canonical list of the user’s starred
repositories or their review outcomes. Treat the following only as installed
source inventory, not proof that every source was starred by the user:

- Packs: `superpowers`, `agent-skills`, `anthropics-skills`,
  `mattpocock-skills`, `ponytail`.
- Standalone sources: `archify`, `caveman`, `drawio-skill`, `graphify`,
  `humanizer`, `planning-with-files`, `taste-skill`, and `ui-ux-pro-max`.

For each actual starred repository, decide: `adopt as source`, `keep as
reference`, `defer`, or `reject`. Record the repository URL, intended use,
and reason only after user review.

## D. Additional User Topics After 39

The distinct topic groups from the supplied list are captured as `D1` through
`D20` below. They are groups for navigation only: the raw wording and every
individual supplied item remain preserved in the crosswalk.

## E. User-Supplied List Crosswalk

This section preserves the user's raw list. It does not decide scope or
implementation. Its former `Existing` / `Split` / `Clarify` labels are working
notes from the first draft, not a rule for what is in the original 39 and not a
rule to skip discussion. Use sections B, C, and D as the After-39 starting
list; use this crosswalk only to confirm that no raw user item was lost.

| User ID | User topic, normalized for indexing | Current anchor | Result |
|---|---|---|---|
| U1 | React components | A12 | Existing |
| U2 | Markdown and context-window management | A5 | Existing |
| U3 | Frequently used skill organization | A14 | Existing |
| U4 | Read repositories | A23, C | Existing |
| U5 | Skill reporting | A2, A8 | Split: distinguish reporting from metrics |
| U6 | Complete installation guide | A19 | Existing |
| U7 | Install/update checks and reporting | A20 | Existing |
| U8 | Design standard | A12 | Existing |
| U9 | Automatic skill use or skill recommendation | A2 | Existing |
| U10 | Anti-hallucination and actual latest-task results | A1 | Existing |
| U11 | Organizer speed and excessive skills | A14, A15 | Existing |
| U12 | State which skill is used | A2 | Existing |
| U13 | Best practices | A1 | Split: define intended boundary |
| U14 | Subagents | A16 | Existing |
| U15 | Ponytail | A23, C | Existing |
| U16 | Handoff Pro Max | D1 | Split |
| U17 | 3.8 Flash | D2 | Clarify |
| U18 | `.enc` / HAWS encryption | D3 | Clarify |
| U19 | Wayfinder | A18 | Existing |
| U20 | SEO | D4 | Split |
| U21 | Restart notification | A4 | Existing |
| U22 | Normalization | A13 | Existing |
| U23 | Wrong-keyboard-layout skill | A18 | Existing |
| U24 | Real token status | A6 | Existing |
| U25 | Context window | A5 | Existing |
| U26 | RAG | A22 | Existing |
| U27 | HAWS dashboard | A24 | Existing |
| U28 | SWE fundamentals | A21 | Existing |
| U29 | Short direct answers, targeted recommendations | A3 | Split: response policy |
| U30 | MCP | A22 | Existing |
| U31 | Persona | A16 | Existing |
| U32 | Prompt-time analysis and skill-use count | A8 | Existing |
| U33 | Test only the changed area | A21 | Split: test-scope policy |
| U34 | Loop engineering and GitHub | A17, A25 | Split |
| U35 | Token management | A6 | Existing |
| U36 | On-demand loading | A7 | Existing |
| U37 | Agent harness | A16 | Existing |
| U38 | GitHub push approval | A25 | Existing |
| U39 | Essential Git usage | D5 | Split |
| U40 | Package policy | D6 | Split |
| U41 | Dependency policy | D6 | Split |
| U42 | Docker containers | D7 | Split |
| U43 | Legacy project-server hardware | D8 | Clarify |
| U44 | Good Second Brain template | D9 | Split |
| U45 | Remove emojis | D10 | Split |
| U46 | Human-readable skill descriptions | D11 | Split |
| U47 | Workflow, Work Instructions, and README coverage | D12 | Split |
| U48 | Autonomous subagent use | A16, B4 | Existing |
| U49 | Figma connection | B8 | Split |
| U50 | Improve HAWS | B9 | Existing |
| U51 | Installation scripts | A19, B3 | Existing |
| U52 | Starred repositories | A23, C | Existing |
| U53 | Automatic plugin use | D13 | Split |
| U54 | Anti-AI-slop quality standard | D14 | Split |
| U55 | Skill that recommends skills | A2 | Split |
| U56 | Status checks | A20, B9 | Existing |
| U57 | Action log, Git history, and progressive disclosure | D15 | Split |
| U58 | Change-aware sync/update architecture | B7, B9 | Existing |
| U59 | Exhaustive testing | A21 | Split: quality threshold |
| U60 | Use HAWS to improve HAWS | D16 | Split |
| U61 | Do not lock skill use; require contextual skill selection | A2 | Existing |
| U62 | Genuine 100% pass; do not use vague green claims | D17 | Split |
| U63 | Todo / Doing / Done status | D18 | Split |
| U64 | Update only active skills | B5, B7 | Existing |
| U65 | Skills that recommend a suitable model | D19 | Split |
| U66 | Cross-device resume: source priority and reading disclosure | D20 | Clarify |
| U67 | Select AI-provider configurations | B6, B9 | Existing |

### D.1 Distinct User-Supplied Topic Groups After 39

| ID | Topic |
|---|---|
| D1 | Handoff Pro Max |
| D2 | 3.8 Flash |
| D3 | `.enc` / HAWS encryption |
| D4 | SEO |
| D5 | Essential Git usage |
| D6 | Package and dependency policy |
| D7 | Docker container policy |
| D8 | Legacy project-server hardware |
| D9 | Second Brain template quality |
| D10 | Emoji-removal policy |
| D11 | Human-readable skill descriptions |
| D12 | Workflow, Work Instructions, and README coverage |
| D13 | Automatic plugin use |
| D14 | Anti-AI-slop quality standard |
| D15 | Action log, Git history, and progressive disclosure |
| D16 | HAWS self-improvement workflow |
| D17 | Genuine-pass wording and evidence |
| D18 | Todo / Doing / Done status model |
| D19 | Skill-to-model recommendations |
| D20 | Cross-device resume sources and reading disclosure |

## Next Review Order

1. Review B1 through B9, then the starred-repository follow-up in C, then D1
   through D20.
2. Use section E only to confirm that every raw user item is represented.
3. Decide with the user whether each After-39 item is kept separate, merged
   into one of the original 39, deferred, or removed.
4. Only then compare resolved items with the nine-task CLI redesign plan.
