# Custom In-House Skills (HAWS AI & User Authored)

This directory houses proprietary, project-specific, or AI-authored skills created directly within HAWS.

## 🏷️ Skill Metadata & Origin Standard

All skills in this directory MUST specify attribution metadata in `SKILL.md` YAML frontmatter:

```yaml
---
name: <skill-name>
description: <Concise, high-signal description without unnecessary bloat>
origin: ai-generated        # Required: "ai-generated" or "user-authored"
author: HAWS Multi-Agent System
created_at: YYYY-MM-DD
version: 1.0.0
---
```

## ⚖️ Precedence & Collision Rules

1. **Highest Priority**: Skills located in `skills/custom/` hold the highest linking precedence.
2. **Submodule Collision Protection**: If an upstream Git submodule adds a skill with the exact same name, the custom skill in this directory takes precedence and overrides the external submodule version.
3. **Token Discipline**: Keep descriptions under 150 words to preserve the Antigravity customization token budget.
