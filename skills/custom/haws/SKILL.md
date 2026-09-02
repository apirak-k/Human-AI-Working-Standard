---
name: haws
description: Unified HAWS CLI and health inspector. Triggers on "/haws", "haws", "haws status", "haws doctor", "haws monitor", or "/haws-status". Fast audit of active skills, cross-platform synchronization, customization token budget, diagnostics, and web telemetry.
origin: ai-generated
author: HAWS Multi-Agent System
created_at: 2026-09-02
version: 2.0.0
---

# HAWS Master Orchestrator (`/haws`)

Unified CLI entrypoint and diagnostic gateway for the Human-AI Working Standard (HAWS). Provides sub-second health audits (< 0.2s), cross-platform synchronization, customization token accounting, and interactive telemetry dashboards.

---

## 🎯 Trigger Criteria
- Inspecting active skill counts across Claude Code and Google Antigravity.
- Verifying whether `~/.haws_manifest` is in 100% sync with filesystem stores.
- Auditing the current customization token budget (< 20k tokens).
- Running comprehensive 5-axis system diagnostics (`haws doctor`).
- Opening the interactive web telemetry dashboard (`haws monitor`).

---

## ⚡ Execution Commands

### 1. Instant Health & Token Budget Check (< 0.2s)
```bash
bash haws.sh status
```
*(On Windows, run within Git Bash: `bash haws.sh status`)*

### 2. Comprehensive System Diagnostics (haws doctor)
```bash
bash haws.sh doctor
# Or output pure JSON:
bash haws.sh doctor --json
```

### 3. Web Telemetry Dashboard
Open the accessible WCAG AA web dashboard:
```bash
# Path relative to repository root:
skills/custom/haws/web/index.html
```

---

## 📊 Diagnostic Thresholds

| Metric | Target / Safe (🟢) | Warning (🟡) | Critical Action Required (🔴) |
| :--- | :---: | :---: | :---: |
| **Execution Latency** | `< 0.3s (300ms)` | `0.3s – 0.5s` | `> 0.5s (Review shell loops)` |
| **Skill Count Parity** | `Antigravity == Claude == Manifest` | Count mismatch | Run `bash haws.sh` to re-sync |
| **Token Budget (20k max)** | `< 15,000 tokens (< 75%)` | `15,000 – 18,000 (75–90%)` | `> 18,000 (> 90%) ➔ Truncation Risk` |

---

## 🛠️ Remediation Runbook
When a parity mismatch or missing symlink is detected, run the universal sync command:
```bash
bash haws.sh
```
