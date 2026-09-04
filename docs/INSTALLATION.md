# HAWS Installation & Quick Start Guide

> **Standard Version**: 2.0 | **Last Updated**: 2026-09-04  
> **Supported Platforms**: Windows 10/11 (Git Bash), macOS, Linux

HAWS (Human-AI Working Standard) is designed for zero-friction setup across all AI development environments (Google Antigravity, Claude Code, Cursor, Codex).

---

## ⚡ 1-Minute Quick Start (One-Liner)

Open your terminal (**Git Bash** on Windows, or standard shell on macOS/Linux) and run:

```bash
git clone https://github.com/apirak-k/Human-AI-Working-Standard.git
cd Human-AI-Working-Standard
bash haws.sh setup
```

The automated `setup` bootstrapper executes 5 phases in under 60 seconds:
1. **Bootstraps Second Brain**: Initializes an independent `secondbrain/` Git repository with zero-leak protection.
2. **Initializes Submodules**: Fetches all external curated skill packs (`superpowers`, `agent-skills`, `anthropics-skills`, `mattpocock-skills`) and plugins (`ponytail`).
3. **Configures Skill Junctions**: Integrates skills into Google Antigravity (`~/.gemini/config/skills.json`) and Claude Code (`~/.claude/skills/`).
4. **Installs Hardware Git Hooks**: Sets up `.githooks/pre-commit` and `.githooks/pre-push` to block unverified code and unauthorized remote pushes.
5. **Runs Diagnostic Verification**: Executes the 10-axis doctor suite (37 verification checks) to confirm 100% green status.

---

## 📋 Prerequisites

| Tool | Minimum Version | Purpose |
| :--- | :---: | :--- |
| **Git** | 2.30+ | Repository versioning, submodules, worktrees |
| **Node.js** | 20+ | Runtime for custom skills and CLI tools |
| **Python** | 3.10+ | Fast regex calculations and AST analysis |
| **Bash** | Standard / Git Bash | Unified command engine (`haws.sh`) |

---

## 💻 Cross-Platform Setup Details

### Windows 10 / 11
- Run all commands inside **Git Bash** (`C:\Program Files\Git\bin\bash.exe`).
- **1-Click Cloud Sync**: Double-click `brain-online.bat` in File Explorer to connect or disconnect your Second Brain to private GitHub storage without opening a terminal.
- **No Administrator Privileges Required**: HAWS leverages Antigravity's native `skills.json` declarative mapping and NTFS Junctions for Claude Code, which work without elevated permissions.
- **LF Line Ending Enforcement**: Git on Windows automatically converts line endings to Unix LF via `.gitattributes` to prevent phantom Git diffs.

### macOS & Linux
- Run commands directly in standard terminal (`zsh` or `bash`).
- Uses native Unix symlinks to link skills into `~/.claude/skills/` and declarative configuration for Antigravity.

---

## 🩺 System Verification & Health Check

At any time, you can verify that HAWS is 100% healthy:

```bash
# Instant sub-second skill count and token budget check (<0.2s)
bash haws.sh status

# Full 10-axis diagnostic audit (37 verification checks)
bash haws.sh doctor

# JSON output mode for programmatic consumption / dashboard
bash haws.sh doctor --json
```

---

## 🔄 Routine Maintenance & Updates

When upstream skills or HAWS core files are updated:

```bash
# Pull latest changes and re-sync
git pull origin main
bash haws.sh sync

# To purge unmanaged foreign skills from third-party tools
bash haws.sh sync --clean
```