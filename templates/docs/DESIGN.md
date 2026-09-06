# Design System Specification (DESIGN.md Template)

> **Official Spec**: [getdesign.md](https://getdesign.md) & [awesome-design-md](https://github.com/voltagent/awesome-design-md)
> **Purpose**: Provide AI coding agents with an exact design reference (colors, typography, spacing, components) to ensure production-grade visual fidelity without generic AI layouts.

---

## 1. Visual Theme & Philosophy
* **Aesthetic Direction**: [e.g. Modern Minimalist, High-Tech Dark Mode, Editorial Clean, Apple-like Craft]
* **Mood & Atmosphere**: [e.g. Professional, high contrast, subtle borders, crisp micro-interactions]
* **Target Reference**: [e.g. Linear.app, Vercel, Stripe, Raycast]

---

## 2. Color Palette & Semantic Tokens (WCAG AA Compliant)

| Token | Light Mode | Dark Mode | Usage |
| :--- | :--- | :--- | :--- |
| `bg-background` | #ffffff | #09090b | Main page background |
| `bg-surface` | #f4f4f5 | #18181b | Cards, modals, containers |
| `bg-surface-elevated` | #ffffff | #27272a | Tooltips, dropdowns |
| `text-primary` | #09090b | #f4f4f5 | Main headings, body text |
| `text-muted` | #71717a | #a1a1aa | Captions, secondary labels |
| `border-subtle` | rgba(0,0,0,0.08) | rgba(255,255,255,0.08) | Card borders, dividers |
| `brand-primary` | #2563eb | #3b82f6 | Primary action buttons, active states |
| `accent-glow` | #60a5fa | #93c5fd | Hover focus rings, highlights |
| `status-success` | #16a34a | #22c55e | Success alerts, confirmations |
| `status-danger` | #dc2626 | #ef4444 | Errors, destructive actions |

---

## 3. Typography & Hierarchy

* **Font Families**:
  - *Primary Sans*: Inter, Geist Sans, or system sans-serif (`font-sans`)
  - *Code & Data Mono*: JetBrains Mono, Geist Mono (`font-mono`)
* **Type Scale**:
  - Hero Title: `text-4xl sm:text-5xl lg:text-6xl font-bold tracking-tight leading-none`
  - Section Heading (H2): `text-2xl sm:text-3xl font-semibold tracking-tight`
  - Card Title (H3): `text-lg font-medium text-primary`
  - Body Text: `text-sm sm:text-base leading-relaxed text-muted`
  - Caption / Badge: `text-xs font-mono uppercase tracking-wider`

---

## 4. Spacing, Radius & Elevation

* **Spacing Scale**: 4px base (`p-2` 8px, `p-4` 16px, `p-6` 24px, `p-8` 32px)
* **Container Widths**: Content max-width `max-w-7xl mx-auto px-4 sm:px-6 lg:px-8`
* **Border Radiuses**:
  - Buttons & Inputs: `rounded-md` (6px) or `rounded-lg` (8px)
  - Cards & Containers: `rounded-xl` (12px) or `rounded-2xl` (16px)
* **Elevation & Shadows**:
  - Flat with subtle border: `border border-subtle shadow-sm`
  - Floating Modal / Popover: `shadow-xl border border-subtle`

---

## 5. Component Anatomy & UI Guidelines

### Buttons
* **Primary**: `bg-brand-primary text-white font-medium px-4 py-2 rounded-lg hover:opacity-90 transition-all shadow-sm active:scale-[0.98]`
* **Secondary / Outline**: `border border-subtle bg-surface text-primary hover:bg-surface-elevated transition-colors`
* **Ghost**: `text-muted hover:text-primary hover:bg-surface transition-colors`

### Cards & Containers
* Background `bg-surface`, border `border-subtle`, padding `p-6`, rounded `rounded-xl`
* Interactive hover card: `hover:border-accent-glow hover:shadow-md transition-all duration-200`

### Forms & Inputs
* `bg-background border border-subtle rounded-lg px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-brand-primary/50`

---

## 6. Frontend Execution Rule for AI Agents
1. Whenever writing frontend UI (React, Tailwind, CSS), the agent MUST strictly conform to the tokens and styles defined in this DESIGN.md.
2. NEVER generate default generic AI layouts when a DESIGN.md exists.
