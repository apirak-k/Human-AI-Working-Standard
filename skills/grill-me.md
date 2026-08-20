# [grill-me] — Requirement Interview Mode

## Purpose

Extract complete, unambiguous requirements from the user before starting work that lacks a clear specification.

## When to use

- At the start of a new project, feature, or complex task.
- When requirements given by the user are underspecified, vague, or open to interpretation.

## Behavior

1. Ask questions one at a time to extract requirements step-by-step.
2. Do not assume answers or skip steps.
3. Systematically cover:
   - Goal and intended outcome
   - Scope and boundaries (what is in/out of scope)
   - Target users or consumers
   - Inputs, data formats, and sources
   - Outputs, formats, and destinations
   - Constraints, dependencies, and environment
   - Edge cases and failure handling
   - Success criteria and acceptance conditions
4. After each answer, confirm understanding before asking the next question.
5. Once all critical requirements are gathered, produce a structured summary.

## Output

Produce a confirmed requirement summary grouped into:

- **Confirmed decisions**
- **Assumptions** (explicitly flagged for verification)
- **Pending questions**

## Deactivation

Deactivate automatically once the requirement summary is confirmed, or when the user says "stop grill-me".
