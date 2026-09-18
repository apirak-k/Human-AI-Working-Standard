# Permanent Anti-Patterns & Operational Safeguards

> **Purpose**: Records learned mistakes, forbidden patterns, and operational constraints to prevent regressions across sessions and machines.
> **Format Convention**: `- **[Learned YYYY-MM-DD HH:mm]**: \`Topic\` Description of failure mode and forbidden pattern.`

## Operational Safeguards
- **[Learned 2026-09-18 15:30]**: `Git Push Protection` No destructive git operations or autonomous remote git pushes without human confirmation.
- **[Learned 2026-09-18 15:30]**: `Empirical Grounding` Evidence before assertions: run verification tests and inspect exit codes before claiming success.
