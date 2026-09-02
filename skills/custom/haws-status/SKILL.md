---
name: haws-status
description: Instant HAWS environment, active skills, and token health status check. Triggers on "haws status", "/haws-status", "check skills", "token check", "health audit", or whenever inspecting cross-tool synchronization between Antigravity, Claude Code, and the manifest.
origin: ai-generated
author: HAWS Multi-Agent System
created_at: 2026-09-02
version: 1.0.0
---

# HAWS Status & Health Inspector (`/haws-status`)

Provides an immediate, sub-second audit (< 0.2s) of active skills, cross-platform synchronization, and Antigravity customization token consumption.

---

## 🎯 When to Use (Trigger Criteria)
- Inspecting active skill counts across Claude Code and Google Antigravity.
- Verifying whether `~/.haws_manifest` is in 100% sync with filesystem stores.
- Auditing the current customization token budget before adding new skills.
- Performing a fast pre-flight check before development or commits.

---

## ⚡ Execution Commands

### Windows (PowerShell)
```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\check-skills.ps1
```

### macOS / Linux / Git Bash (POSIX)
```bash
bash scripts/check-skills.sh
```

---

## 📊 Health Thresholds & Diagnostic Criteria

| Metric | Target / Safe (🟢) | Warning (🟡) | Critical Action Required (🔴) |
| :--- | :---: | :---: | :---: |
| **Execution Latency** | `< 0.3s (300ms)` | `0.3s – 0.5s` | `> 0.5s (Review shell loops)` |
| **Skill Count Parity** | `Antigravity == Claude == Manifest` | Count mismatch | Missing symlinks ➔ Run `./update.sh` |
| **Token Budget (20k max)** | `< 15,000 tokens (< 75%)` | `15,000 – 18,000 (75–90%)` | `> 18,000 (> 90%) ➔ Truncation Risk` |

---

## 🛠️ Remediation Runbook
1. **If Parity Mismatch Detected**:
   Run the unified updater to re-link missing symlinks and auto-prune dangling records:
   ```bash
   bash update.sh
   ```
2. **If Token Budget in Warning (>= 75%)**:
   Review the largest skill descriptions in `~/.gemini/config/skills` and compact them using `@organizer`.

