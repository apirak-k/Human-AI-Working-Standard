# HAWS Health & Analytics Monitor Backend Service

> **Status**: Production Ready | **Tier**: Core Infrastructure | **Latency Target**: Sub-Second (< 300ms)  
> **Author**: `@backend-engineer` | **Domain Spec**: `@researcher` | **Consumer**: `@frontend-engineer`

---

## 🚀 Overview

The **HAWS Health & Analytics Monitor Backend Service** (`health_service.py`) is a standalone, ultra-low-latency monitoring micro-utility. It directly ingests, cross-references, and verifies skill inventory across runtime environments without spawning external shell processes.

### Key Capabilities
- **Sub-Second Native Inspection**: Employs native `os.scandir` and sequential file reads to achieve typical latencies of **< 15ms** (far below the 300ms SLA).
- **5-Drawer Taxonomy Engine**: Parses `core/SKILL_TAXONOMY.md` dynamically into 5 functional Drawers (Thinking, Code, UI/UX, Audit, Docs) with full metadata, skill counts, and subagent affinities.
- **Hermetic Pokayoke Error-Proofing**: Gracefully handles missing files, unreadable directories, or permission denials without throwing unhandled exceptions.
- **Multi-Modal Presentation**: Provides structured JSON output, a clean ANSI terminal summary, and automated file exports for frontend dashboards (`health_data.json`).

---

## 🗄️ Architecture & Data Ingestion

```
                           +----------------------+
                           |  ~/.haws_manifest    |
                           +----------+-----------+
                                      |
+--------------------------+          |          +--------------------------+
| ~/.gemini/config/skills  |          v          |    ~/.claude/skills      |
+------------+-------------+   [HealthService]   +-------------+------------+
             |                        ^                        |
             +----------------+       |       +----------------+
                              |       |       |
                           +--+-------+-------+---+
                           | core/SKILL_TAXONOMY.md|
                           +----------------------+
                                      |
                                      v
                  +---------------------------------------+
                  |           SystemHealthReport          |
                  |  - executionTimeMs (< 300ms)          |
                  |  - overallStatus (HEALTHY / MISMATCH) |
                  |  - counts (gemini, claude, manifest)  |
                  |  - categories (5-Drawer Breakdown)    |
                  |  - diagnostics & discrepancies        |
                  +-------------------+-------------------+
                                      |
             +------------------------+------------------------+
             |                        |                        |
             v                        v                        v
      [--summary]                  [--json]             [--export-web]
     Terminal View            STDOUT JSON Pipeline    health_data.json
```

---

## 💻 CLI Usage

### 1. Terminal Summary (Default)
```bash
python tools/haws-monitor/src/health_service.py --summary
```
Prints a high-signal, human-readable terminal dashboard displaying overall status, count parity, and category progress bars.

### 2. JSON Output (Piping & Automation)
```bash
python tools/haws-monitor/src/health_service.py --json
```
Emits formatted JSON payload to STDOUT for automation scripts or `jq` pipelines.

### 3. Web Export for `@frontend-engineer`
```bash
python tools/haws-monitor/src/health_service.py --export-web tools/haws-monitor/web/health_data.json
```
Safely and atomically writes `health_data.json` to the target destination, ensuring parent directories are created automatically.

### 4. High-Precision Latency Benchmark
```bash
python tools/haws-monitor/src/health_service.py --benchmark 50
```
Runs 50 consecutive health checks to measure Min, P50, Avg, P95, and Max latency against the 300ms SLA.

---

## 📊 Data Schema (`SystemHealthReport`)

```json
{
  "executionTimeMs": 12.45,
  "overallStatus": "HEALTHY",
  "statusMessage": "100% HEALTHY & IN SYNC",
  "timestamp": "2026-09-02T13:46:34+07:00",
  "counts": {
    "gemini": 102,
    "claude": 102,
    "manifest": 102,
    "taxonomy": 102,
    "manifestAgents": 5,
    "activeUnique": 102,
    "synced": true,
    "inSyncWithTaxonomy": true
  },
  "categories": [
    {
      "id": "drawer-1",
      "drawerNumber": 1,
      "name": "Thinking & Planning",
      "shortName": "Thinking",
      "icon": "🧠",
      "declaredCount": 26,
      "activeCount": 26,
      "missingSkills": [],
      "skills": ["brainstorming", "writing-plans", "..."],
      "purpose": "Intent extraction, architectural design, requirements engineering...",
      "primarySubagents": ["Leader", "@researcher"]
    }
  ],
  "subagentAffinity": {
    "@organizer": {
      "primary": ["Drawer 4 (Audit)", "Drawer 5 (Docs)"],
      "secondary": ["Drawer 1 (Planning)"]
    }
  },
  "diagnostics": {
    "synced": true,
    "inSyncWithTaxonomy": true,
    "missingInGemini": [],
    "missingInClaude": [],
    "unregisteredSkills": [],
    "errors": [],
    "warnings": []
  }
}
```

---

## 🧪 Testing

Run the test suite with Python's built-in `unittest`:
```bash
python -m unittest discover -s tools/haws-monitor/tests
```
