# Technical practices

Use these practices when a task involves software, technical systems, or
automation. They supplement HAWS and Work Instructions; they do not prescribe
a workflow for unrelated tasks.

## Software and systems

- Inspect the current implementation and relevant callers before changing
  behavior. Prefer the smallest reliable change that fixes the underlying
  problem and fits established conventions.
- Verify APIs and dependencies against the versions actually used. Prefer an
  existing project capability or the standard library when it is sufficient.
  Preserve lockfiles; pin production dependencies. Run a vulnerability check
  when adding or materially updating dependencies, or when the project asks.
- Check affected callers and state boundaries before changing a public
  interface, shared utility, schema, or central module. Use an architecture or
  dependency map when it makes a complex system easier to understand.
- When a project builds containers, keep credentials and local build material
  out of the image, use a non-root runtime where practical, and use separate
  build stages when they reduce the shipped image safely.

## Interfaces and calculations

- Match interface layout to the devices and screen sizes the project
  supports. Keep important actions usable at narrow sizes and provide
  appropriate keyboard and assistive-technology access.
- When the same business rule is implemented in more than one place, verify
  that the results agree for the same inputs or establish one authoritative
  implementation.
- Handle expected missing, invalid, or zero inputs explicitly. Show a safe,
  truthful fallback instead of a misleading value.

## Tools and collaboration

- Select tools, skills, and methods when they fit the task. Read the relevant
  instructions before applying a specialized workflow, then verify its result.
- Delegate independent work when it materially improves speed or review
  quality and the task's instructions permit it. Keep one primary responder
  responsible for the combined result.
- Run read-only checks and isolated tests when useful. Follow the applicable
  authorization boundary before external, destructive, or high-impact actions.

## Technical documentation

- Keep one authoritative source for each technical rule. Put general
  principles in `core/HAWS.md`, reusable working procedures in
  `core/WORK_INSTRUCTIONS.md`, and project state or decisions in the
  appropriate project documentation.
- Record important design choices when they affect interfaces, state,
  compatibility, security, or future maintenance. Include the reason and
  meaningful trade-offs; do not document self-evident implementation details.
