---
name: haws
description: HAWS master slash command. Triggers on "/haws", "haws", "haws status", or "haws health". Provides immediate sub-second audit of active skills, cross-platform synchronization, and customization token budget.
origin: ai-generated
author: HAWS Multi-Agent System
created_at: 2026-09-02
version: 1.0.0
---

# HAWS Master Slash Command (`/haws`)

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
# Full System Diagnostics:
powershell -ExecutionPolicy Bypass -File .\scripts\haws.ps1 doctor
powershell -ExecutionPolicy Bypass -File .\scripts\haws.ps1 doctor -Json
```

### macOS / Linux / Git Bash (POSIX)
```bash
bash scripts/check-skills.sh
# Full System Diagnostics:
bash scripts/haws doctor
bash scripts/haws doctor --json
```

---

## 📊 Health Thresholds & Diagnostic Criteria

| Metric | Target / Safe (🟢) | Warning (🟡) | Critical Action Required (🔴) |
| :--- | :---: | :---: | :---: |
| **Execution Latency** | `< 0.3s (300ms)` | `0.3s – 0.5s` | `> 0.5s (Review shell loops)` |
| **Skill Count Parity** | `Antigravity == Claude == Manifest` | Count mismatch | Missing symlinks ➔ Run `./update.sh` |
| **Token Budget (20k max)** | `< 15,000 tokens (< 75%)` | `15,000 – 18,000 (75–90%)` | `> 18,000 (> 90%) ➔ Truncation Risk` |
