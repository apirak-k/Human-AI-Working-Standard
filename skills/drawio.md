# [drawio-skill] — Diagram & Visualization Authoring

## Purpose

Turn natural-language descriptions, process workflows, architecture designs, and codebase/infrastructure structures into clean `.drawio` XML files and professional diagrams (PNG/SVG/PDF/JPG).

## When to use

- When the user requests diagrams, flowcharts, architecture diagrams, ER diagrams, UML/sequence diagrams, BPMN, swimlane flowcharts, or 5-Whys root-cause trees.
- Proactively when explaining complex multi-component systems, cost data flows, or manufacturing line balances.
- When generating visual figures and charts for project reports and presentation decks.

## Behavior & Standards

1. **Format & Integrity**:
   - Generate standard `.drawio` XML compatible with [app.diagrams.net](https://app.diagrams.net) and desktop Draw.io.
   - Use clean, fluid grid-aligned layouts without overlapping lines or text collisions.
2. **Palette & Style**:
   - Use professional industrial palettes (Slate, Emerald, Amber, Rose, Neutral Gray).
   - Avoid excessive glow/neon effects. Maintain clear typographic hierarchy.
3. **IE & Manufacturing Vocabulary**:
   - Support Process Operations, Work Centers, Quality Inspection Gates, Buffer Storages, and Material Flow arrows.
4. **Execution Flow**:
   - Plan node hierarchy and relationships (Left-to-Right or Top-to-Bottom).
   - Produce the `.drawio` file locally in the project workspace.
   - Export to PNG/SVG/PDF when required.

## Deactivation

Deactivate automatically when the diagram generation is completed, or when the user changes context.
