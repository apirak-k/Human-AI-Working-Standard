#!/usr/bin/env python3
"""HAWS Health & Analytics Monitor Backend Service.

High-performance, standalone health check service for the Human-AI Working Standard (HAWS).
Adheres to Clean Architecture, Pokayoke error-proofing, and sub-second execution (< 300ms).

Author: @backend-engineer
Specification: @researcher
Target: HAWS-E2E-PHASE2-BACKEND
"""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass, field
import datetime
import json
import os
from pathlib import Path
import re
import sys
import time
from typing import Any, Dict, List, Optional, Set, Tuple

# ==============================================================================
# Domain Constants & Canonical Fallback Metadata
# ==============================================================================

DRAWER_METADATA = {
    1: {
        "id": "drawer-1",
        "name": "Thinking & Planning",
        "short_name": "Thinking",
        "icon": "🧠",
        "declared_count": 26,
        "purpose": "Intent extraction, architectural design, requirements engineering, decision stress-testing, and vertical task breakdown.",
        "primary_subagents": ["Leader", "@researcher"],
        "default_skills": [
            "brainstorming", "writing-plans", "executing-plans",
            "planning-and-task-breakdown", "planning-with-files",
            "spec-driven-development", "to-spec", "to-tickets",
            "to-questionnaire", "idea-refine", "interview-me",
            "grill-me", "grilling", "grill-with-docs", "domain-modeling",
            "codebase-design", "graphify", "prototype", "research",
            "discernment-nudge", "doubt-driven-development", "ask-matt",
            "wayfinder", "wait-what", "wizard", "triage",
        ],
    },
    2: {
        "id": "drawer-2",
        "name": "Code & Engineering",
        "short_name": "Code",
        "icon": "💻",
        "declared_count": 25,
        "purpose": "Core implementation, API design, database querying, refactoring, and cloud pipelines.",
        "primary_subagents": ["@backend-engineer"],
        "default_skills": [
            "test-driven-development", "tdd", "implement", "implement-spec",
            "api-and-interface-design", "code-simplification",
            "improve-codebase-architecture", "source-driven-development",
            "incremental-implementation", "constraint-driven-development",
            "mcp-builder", "claude-api", "migrate-to-shoehorn",
            "setup-ts-deep-modules", "setup-pre-commit",
            "subagent-driven-development", "dispatching-parallel-agents",
            "using-git-worktrees", "git-workflow-and-versioning",
            "git-guardrails-claude-code", "resolving-merge-conflicts",
            "deprecation-and-migration", "finishing-a-development-branch",
            "shipping-and-launch", "ci-cd-and-automation",
        ],
    },
    3: {
        "id": "drawer-3",
        "name": "UX/UI & Frontend",
        "short_name": "UI/UX",
        "icon": "🎨",
        "declared_count": 13,
        "purpose": "Production UI design, design tokens, component architecture, visual polish, and diagrams.",
        "primary_subagents": ["@frontend-engineer"],
        "default_skills": [
            "ui-ux-pro-max", "taste-skill", "frontend-design",
            "frontend-ui-engineering", "drawio-skill", "canvas-design",
            "brand-guidelines", "theme-factory", "web-artifacts-builder",
            "browser-testing-with-devtools", "webapp-testing",
            "slack-gif-creator", "algorithmic-art",
        ],
    },
    4: {
        "id": "drawer-4",
        "name": "Audit & Verification",
        "short_name": "Audit",
        "icon": "🔍",
        "declared_count": 15,
        "purpose": "Code verification, root cause debugging, security hardening, performance audits, and QA.",
        "primary_subagents": ["@tester", "@organizer"],
        "default_skills": [
            "verification-before-completion", "systematic-debugging",
            "diagnosing-bugs", "debugging-and-error-recovery",
            "code-review-and-quality", "code-review", "requesting-code-review",
            "receiving-code-review", "security-and-hardening",
            "performance-optimization", "observability-and-instrumentation",
            "retro", "loop-me", "haws", "haws-status",
        ],

    },
    5: {
        "id": "drawer-5",
        "name": "Docs & Communication",
        "short_name": "Docs",
        "icon": "📝",
        "declared_count": 25,
        "purpose": "Document processing, token compression, humanizer, meta-tools, and skill authoring.",
        "primary_subagents": ["Leader", "@organizer"],
        "default_skills": [
            "caveman", "humanizer", "doc-coauthoring",
            "documentation-and-adrs", "internal-comms", "docx", "pdf",
            "pptx", "xlsx", "writing-for-agents", "writing-beats",
            "writing-shape", "writing-fragments", "skill-creator",
            "writing-skills", "using-superpowers", "using-agent-skills",
            "context-engineering", "claude-handoff", "handoff", "teach",
            "scaffold-exercises", "academy-guide", "setup-matt-pocock-skills",
            "template-skill",
        ],
    },
}

DEFAULT_SUBAGENT_AFFINITIES = {
    "@organizer": {
        "primary": ["Drawer 4 (Audit)", "Drawer 5 (Docs)"],
        "secondary": ["Drawer 1 (Planning)"],
    },
    "@tester": {
        "primary": ["Drawer 4 (Audit)", "Drawer 2 (Code)"],
        "secondary": ["Drawer 3 (UI Testing)"],
    },
    "@frontend-engineer": {
        "primary": ["Drawer 3 (UX/UI)", "Drawer 2 (Code)"],
        "secondary": ["Drawer 5 (Docs)"],
    },
    "@backend-engineer": {
        "primary": ["Drawer 2 (Code)", "Drawer 4 (Audit)"],
        "secondary": ["Drawer 1 (Architecture)"],
    },
    "@researcher": {
        "primary": ["Drawer 1 (Thinking)", "Drawer 5 (Docs)"],
        "secondary": ["Drawer 2 (Code Exploration)"],
    },
}

# ==============================================================================
# Domain Models & Data Transfer Objects
# ==============================================================================

@dataclass(frozen=True)
class DataPaths:
    """Configurable system paths for data sources."""
    manifest_path: Path
    gemini_skills_dir: Path
    claude_skills_dir: Path
    taxonomy_path: Path

    @classmethod
    def default(cls, repo_root: Optional[Path] = None) -> DataPaths:
        """Create default paths based on user environment and repo topology."""
        home = Path.home()
        if repo_root is None:
            # Walk up to locate repo root containing core/SKILL_TAXONOMY.md
            current = Path(__file__).resolve().parent
            repo_candidate = None
            for p in [current, *current.parents]:
                if (p / "core" / "SKILL_TAXONOMY.md").is_file():
                    repo_candidate = p
                    break
            repo_root = repo_candidate or Path.cwd()

        return cls(
            manifest_path=home / ".haws_manifest",
            gemini_skills_dir=home / ".gemini" / "config" / "skills",
            claude_skills_dir=home / ".claude" / "skills",
            taxonomy_path=repo_root / "core" / "SKILL_TAXONOMY.md",
        )


@dataclass
class DrawerCategory:
    """Detailed category breakdown for a HAWS drawer."""
    id: str
    drawerNumber: int
    name: str
    shortName: str
    icon: str
    declaredCount: int
    activeCount: int
    missingSkills: List[str]
    skills: List[str]
    purpose: str
    primarySubagents: List[str]
    skillDescriptions: Dict[str, str] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "id": self.id,
            "drawerNumber": self.drawerNumber,
            "name": self.name,
            "shortName": self.shortName,
            "icon": self.icon,
            "declaredCount": self.declaredCount,
            "activeCount": self.activeCount,
            "missingSkills": self.missingSkills,
            "skills": self.skills,
            "purpose": self.purpose,
            "primarySubagents": self.primarySubagents,
            "skillDescriptions": self.skillDescriptions,
        }


@dataclass
class SkillCounts:
    """Consolidated skill counts across environments."""
    gemini: int
    claude: int
    manifest: int
    taxonomy: int
    manifestAgents: int
    activeUnique: int
    synced: bool
    inSyncWithTaxonomy: bool

    def to_dict(self) -> Dict[str, Any]:
        return asdict(self)


@dataclass
class SystemHealthReport:
    """Comprehensive HAWS system health report."""
    timestamp: str
    executionTimeMs: float
    overallStatus: str
    statusMessage: str
    counts: SkillCounts
    categories: List[DrawerCategory]
    subagentAffinity: Dict[str, Dict[str, List[str]]]
    diagnostics: Dict[str, Any]
    paths: Dict[str, str]

    # Redundant snake_case getters/aliases for interoperability
    @property
    def execution_time_ms(self) -> float:
        return self.executionTimeMs

    @property
    def overall_status(self) -> str:
        return self.overallStatus

    @property
    def status_message(self) -> str:
        return self.statusMessage

    def to_dict(self) -> Dict[str, Any]:
        """Convert report to JSON-serializable dictionary."""
        return {
            # Top-level requested fields
            "executionTimeMs": self.executionTimeMs,
            "overallStatus": self.overallStatus,
            "statusMessage": self.statusMessage,
            "timestamp": self.timestamp,
            # Redundant keys for snake_case callers
            "execution_time_ms": self.executionTimeMs,
            "overall_status": self.overallStatus,
            "status_message": self.statusMessage,
            # Core structured payload
            "systemHealth": {
                "executionTimeMs": self.executionTimeMs,
                "overallStatus": self.overallStatus,
                "statusMessage": self.statusMessage,
                "timestamp": self.timestamp,
            },
            "counts": self.counts.to_dict(),
            "categories": [c.to_dict() for c in self.categories],
            "drawers": [c.to_dict() for c in self.categories],  # drawer alias
            "subagentAffinity": self.subagentAffinity,
            "diagnostics": self.diagnostics,
            "paths": self.paths,
        }

    def to_json(self, indent: int = 2) -> str:
        """Serialize report to formatted JSON string."""
        return json.dumps(self.to_dict(), indent=indent, ensure_ascii=False)

    def to_summary_text(self) -> str:
        """Render clean terminal summary text."""
        status_color = "🟢" if self.overallStatus == "HEALTHY" else "🔴"
        if self.overallStatus == "WARNING":
            status_color = "🟡"

        lines = [
            "================================================================================",
            f" HAWS Health & Analytics Monitor — Sub-Second Status ({self.executionTimeMs:.2f} ms)",
            "================================================================================",
            f"Overall Status : {status_color} [{self.overallStatus}] {self.statusMessage}",
            f"Timestamp      : {self.timestamp}",
            "",
            "--- Inventory & Parity Check ---",
            f"Antigravity Active Skills : {self.counts.gemini:>4}",
            f"Claude Code Active Skills : {self.counts.claude:>4}",
            f"Manifest Registered Skills: {self.counts.manifest:>4} (Agents: {self.counts.manifestAgents})",
            f"Taxonomy Catalog Skills   : {self.counts.taxonomy:>4}",
            f"Unique Active Skills      : {self.counts.activeUnique:>4}",
            f"Runtime Parity Synced     : {'YES [100% IN SYNC]' if self.counts.synced else 'NO [MISMATCH DETECTED]'}",
            "",
            "--- 5-Drawer Skill Taxonomy Breakdown ---",
        ]

        for cat in self.categories:
            pct = (cat.activeCount / cat.declaredCount * 100) if cat.declaredCount > 0 else 0.0
            subagents_str = ", ".join(cat.primarySubagents) if cat.primarySubagents else "Unassigned"
            lines.append(
                f"{cat.icon} Drawer {cat.drawerNumber}: {cat.name:<25} "
                f"[{cat.activeCount:>2}/{cat.declaredCount:>2} Skills - {pct:>5.1f}%] "
                f"(Primary: {subagents_str})"
            )
            if cat.missingSkills:
                lines.append(f"   ⚠️ Missing: {', '.join(cat.missingSkills)}")

        if self.diagnostics.get("warnings") or self.diagnostics.get("errors"):
            lines.append("")
            lines.append("--- Diagnostics & Alerts ---")
            for w in self.diagnostics.get("warnings", []):
                lines.append(f"  [WARN] {w}")
            for e in self.diagnostics.get("errors", []):
                lines.append(f"  [ERR]  {e}")

        lines.append("================================================================================")
        return "\n".join(lines)


# ==============================================================================
# Data Ingestion Layer (Pokayoke & Sub-Second Native Scanning)
# ==============================================================================

class SkillScanner:
    """High-speed native directory scanner using os.scandir."""

    @staticmethod
    def scan_directory(dir_path: Path) -> Tuple[Set[str], Optional[str]]:
        """Scan directory for skill folders without spawning subshells.

        Returns (skill_names_set, optional_error_message).
        """
        skills: Set[str] = set()
        if not dir_path.exists():
            return skills, f"Directory does not exist: {dir_path}"

        try:
            with os.scandir(dir_path) as it:
                for entry in it:
                    try:
                        if entry.is_dir():
                            skills.add(entry.name)
                    except (PermissionError, OSError):
                        # Pokayoke: skip individual unreadable entries without crashing
                        continue
            return skills, None
        except (PermissionError, OSError) as e:
            return skills, f"Cannot read directory {dir_path}: {e}"


class ManifestReader:
    """Reads and parses ~/.haws_manifest safely."""

    @staticmethod
    def read_manifest(manifest_path: Path) -> Tuple[Set[str], Set[str], Optional[str]]:
        """Extract skill and agent entries from manifest.

        Returns (skills_set, agents_set, optional_warning).
        """
        skills: Set[str] = set()
        agents: Set[str] = set()

        if not manifest_path.is_file():
            return skills, agents, f"Manifest file not found at: {manifest_path}"

        try:
            with open(manifest_path, "r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    if line.startswith("skill:"):
                        name = line[6:].strip()
                        if name:
                            skills.add(name)
                    elif line.startswith("agent:"):
                        agent = line[6:].strip()
                        if agent:
                            agents.add(agent)
            return skills, agents, None
        except (PermissionError, OSError) as e:
            return skills, agents, f"Failed to read manifest at {manifest_path}: {e}"


class TaxonomyReader:
    """Reads core/SKILL_TAXONOMY.md and builds structured drawer catalog."""

    @classmethod
    def read_taxonomy(
        cls, taxonomy_path: Path
    ) -> Tuple[Dict[int, Dict[str, Any]], Dict[str, Dict[str, List[str]]], Optional[str]]:
        """Parse drawers and subagent affinities from SKILL_TAXONOMY.md.

        Returns (drawers_map, subagent_affinities_map, optional_warning).
        """
        if not taxonomy_path.is_file():
            # Graceful Pokayoke fallback: return default canonical metadata
            return (
                cls._get_canonical_drawers(),
                DEFAULT_SUBAGENT_AFFINITIES.copy(),
                f"Taxonomy file not found at {taxonomy_path}; using canonical fallback.",
            )

        try:
            with open(taxonomy_path, "r", encoding="utf-8", errors="replace") as f:
                content = f.read()
            drawers, affinities = cls._parse_markdown(content)
            return drawers, affinities, None
        except (PermissionError, OSError) as e:
            return (
                cls._get_canonical_drawers(),
                DEFAULT_SUBAGENT_AFFINITIES.copy(),
                f"Error reading taxonomy file {taxonomy_path}: {e}; using canonical fallback.",
            )

    @classmethod
    def _get_canonical_drawers(cls) -> Dict[int, Dict[str, Any]]:
        """Produce deep copy of default drawer metadata."""
        drawers: Dict[int, Dict[str, Any]] = {}
        for num, meta in DRAWER_METADATA.items():
            drawers[num] = {
                "id": meta["id"],
                "name": meta["name"],
                "short_name": meta["short_name"],
                "icon": meta["icon"],
                "declared_count": meta["declared_count"],
                "purpose": meta["purpose"],
                "primary_subagents": list(meta["primary_subagents"]),
                "skills": list(meta["default_skills"]),
                "skill_descriptions": {},
            }
        return drawers

    @classmethod
    def _parse_markdown(
        cls, content: str
    ) -> Tuple[Dict[int, Dict[str, Any]], Dict[str, Dict[str, List[str]]]]:
        """Parse markdown content with regex extracting 5 drawers and affinities."""
        drawers = cls._get_canonical_drawers()
        affinities: Dict[str, Dict[str, List[str]]] = DEFAULT_SUBAGENT_AFFINITIES.copy()

        # Drawer header pattern: ### [icon] Drawer <num>: <Name> (<count> Skills)
        drawer_header_regex = re.compile(
            r"^###\s+([^\s\w]*\s*)?Drawer\s+(\d+)[:\s]+([^(]+?)(?:\s*\((?:Complete\s*)?(\d+)\s*Skills?\))?\s*$",
            re.IGNORECASE | re.MULTILINE,
        )

        matches = list(drawer_header_regex.finditer(content))
        for i, match in enumerate(matches):
            icon = (match.group(1) or "").strip()
            num = int(match.group(2))
            name = match.group(3).strip()
            declared_str = match.group(4)
            declared_count = int(declared_str) if declared_str else None

            start_pos = match.end()
            end_pos = matches[i + 1].start() if i + 1 < len(matches) else len(content)
            section = content[start_pos:end_pos]

            purpose = ""
            primary_subagents: List[str] = []
            skills: List[str] = []
            skill_descriptions: Dict[str, str] = {}

            for line in section.splitlines():
                line = line.strip()
                # Purpose
                purpose_match = re.match(r"^\*\s+\*\*Purpose\*\*:\s*(.+)$", line, re.IGNORECASE)
                if purpose_match:
                    purpose = purpose_match.group(1).strip()
                    continue

                # Primary Subagent
                agent_match = re.match(r"^\*\s+\*\*Primary Subagent\*\*:\s*(.+)$", line, re.IGNORECASE)
                if agent_match:
                    raw_agents = agent_match.group(1).strip()
                    primary_subagents = [a.strip() for a in raw_agents.split(",") if a.strip()]
                    continue

                # Catalog lines: - `skill-name` / `alias` — description
                if line.startswith("-") and "`" in line:
                    sep_match = re.search(r"\s+[—–-]\s+", line)
                    if sep_match:
                        skill_part = line[: sep_match.start()]
                        desc = line[sep_match.end() :].strip()
                    else:
                        skill_part = line
                        desc = ""
                    skill_names = re.findall(r"`([a-zA-Z0-9_-]+)`", skill_part)
                    if skill_names:
                        for sk in skill_names:
                            skills.append(sk)
                            if desc:
                                skill_descriptions[sk] = desc


            # Merge with existing drawer defaults
            if num in drawers:
                drawer = drawers[num]
                if name:
                    drawer["name"] = name
                if icon:
                    drawer["icon"] = icon
                if declared_count is not None:
                    drawer["declared_count"] = declared_count
                if purpose:
                    drawer["purpose"] = purpose
                if primary_subagents:
                    drawer["primary_subagents"] = primary_subagents
                if skills:
                    drawer["skills"] = skills
                if skill_descriptions:
                    drawer["skill_descriptions"] = skill_descriptions
            else:
                drawers[num] = {
                    "id": f"drawer-{num}",
                    "name": name,
                    "short_name": DRAWER_METADATA.get(num, {}).get("short_name", f"Drawer {num}"),
                    "icon": icon or "📁",
                    "declared_count": declared_count or len(skills),
                    "purpose": purpose,
                    "primary_subagents": primary_subagents,
                    "skills": skills,
                    "skill_descriptions": skill_descriptions,
                }

        # Parse Affinity Matrix Table
        # Format: | **@agent** | Primary | Secondary |
        table_regex = re.compile(
            r"\|\s*\*\*(@[\w-]+)\*\*\s*\|\s*([^|]+)\|\s*([^|]+)\|",
            re.MULTILINE,
        )
        for row in table_regex.finditer(content):
            agent = row.group(1).strip()
            primaries = [p.strip() for p in row.group(2).split(",") if p.strip()]
            secondaries = [s.strip() for s in row.group(3).split(",") if s.strip()]
            affinities[agent] = {
                "primary": primaries,
                "secondary": secondaries,
            }

        return drawers, affinities


# ==============================================================================
# Service Orchestrator (Core Business Logic)
# ==============================================================================

class HealthService:
    """Core standalone HAWS Health & Analytics Backend Service."""

    def __init__(self, paths: Optional[DataPaths] = None) -> None:
        self.paths = paths or DataPaths.default()

    def check_health(self) -> SystemHealthReport:
        """Execute full health check with sub-second high-precision timer."""
        t_start = time.perf_counter()

        warnings: List[str] = []
        errors: List[str] = []

        # 1. Native directory scan of Gemini & Claude skills
        gemini_skills, gemini_err = SkillScanner.scan_directory(self.paths.gemini_skills_dir)
        if gemini_err:
            warnings.append(gemini_err)

        claude_skills, claude_err = SkillScanner.scan_directory(self.paths.claude_skills_dir)
        if claude_err:
            warnings.append(claude_err)

        # 2. Ingest manifest
        manifest_skills, manifest_agents, manifest_err = ManifestReader.read_manifest(
            self.paths.manifest_path
        )
        if manifest_err:
            warnings.append(manifest_err)

        # 3. Ingest taxonomy
        drawers_data, subagent_affinities, tax_err = TaxonomyReader.read_taxonomy(
            self.paths.taxonomy_path
        )
        if tax_err:
            warnings.append(tax_err)

        # Union of all active skills across runtime environments
        active_skills_union = gemini_skills | claude_skills
        all_known_active = active_skills_union or manifest_skills

        # 4. Compute Drawer Breakdown
        taxonomy_skill_set: Set[str] = set()
        categories: List[DrawerCategory] = []

        for num in sorted(drawers_data.keys()):
            data = drawers_data[num]
            declared_skills: List[str] = data.get("skills", [])
            taxonomy_skill_set.update(declared_skills)

            # Check presence in active skills
            active_for_drawer = [s for s in declared_skills if s in all_known_active]
            missing_for_drawer = [s for s in declared_skills if s not in all_known_active]

            category = DrawerCategory(
                id=data.get("id", f"drawer-{num}"),
                drawerNumber=num,
                name=data.get("name", f"Drawer {num}"),
                shortName=data.get("short_name", DRAWER_METADATA.get(num, {}).get("short_name", f"Drawer {num}")),
                icon=data.get("icon", "📁"),
                declaredCount=data.get("declared_count", len(declared_skills)),
                activeCount=len(active_for_drawer),
                missingSkills=missing_for_drawer,
                skills=declared_skills,
                purpose=data.get("purpose", ""),
                primarySubagents=data.get("primary_subagents", []),
                skillDescriptions=data.get("skill_descriptions", {}),
            )
            categories.append(category)

        # 5. Compute Counts & Parity
        gemini_count = len(gemini_skills)
        claude_count = len(claude_skills)
        manifest_count = len(manifest_skills)
        taxonomy_count = len(taxonomy_skill_set)
        active_unique_count = len(all_known_active)

        synced = (
            gemini_count == claude_count == manifest_count
            and gemini_skills == claude_skills == manifest_skills
            if (gemini_count > 0 or claude_count > 0 or manifest_count > 0)
            else False
        )
        in_sync_with_taxonomy = (
            active_unique_count == taxonomy_count
            and all_known_active == taxonomy_skill_set
        )

        counts = SkillCounts(
            gemini=gemini_count,
            claude=claude_count,
            manifest=manifest_count,
            taxonomy=taxonomy_count,
            manifestAgents=len(manifest_agents),
            activeUnique=active_unique_count,
            synced=synced,
            inSyncWithTaxonomy=in_sync_with_taxonomy,
        )

        # 6. Diagnostics & Discrepancies
        missing_in_gemini = sorted(list(manifest_skills - gemini_skills))
        missing_in_claude = sorted(list(manifest_skills - claude_skills))
        unregistered_skills = sorted(list(active_skills_union - manifest_skills))

        # 7. Evaluate Overall Status (Pokayoke rules)
        if synced and in_sync_with_taxonomy and not errors and not warnings:
            overall_status = "HEALTHY"
            status_message = "100% HEALTHY & IN SYNC"
        elif synced and in_sync_with_taxonomy:
            overall_status = "HEALTHY"
            status_message = "100% HEALTHY & IN SYNC (with path warnings)"
        elif not synced and (gemini_count == 0 or claude_count == 0 or manifest_count == 0):
            overall_status = "DEGRADED"
            status_message = "ONE OR MORE SKILL STORES UNAVAILABLE"
        elif not synced:
            overall_status = "MISMATCH"
            status_message = "MISMATCH DETECTED ACROSS RUNTIMES - Run update.sh"
        elif not in_sync_with_taxonomy:
            overall_status = "WARNING"
            status_message = "RUNTIME SYNCED BUT TAXONOMY DISCREPANCY DETECTED"
        else:
            overall_status = "UNKNOWN"
            status_message = "CHECK LOGS"

        diagnostics = {
            "synced": synced,
            "inSyncWithTaxonomy": in_sync_with_taxonomy,
            "missingInGemini": missing_in_gemini,
            "missingInClaude": missing_in_claude,
            "unregisteredSkills": unregistered_skills,
            "errors": errors,
            "warnings": warnings,
        }

        # Calculate high-precision elapsed time in milliseconds
        t_elapsed_ms = (time.perf_counter() - t_start) * 1000.0

        return SystemHealthReport(
            timestamp=datetime.datetime.now().astimezone().isoformat(),
            executionTimeMs=round(t_elapsed_ms, 2),
            overallStatus=overall_status,
            statusMessage=status_message,
            counts=counts,
            categories=categories,
            subagentAffinity=subagent_affinities,
            diagnostics=diagnostics,
            paths={
                "manifest": str(self.paths.manifest_path),
                "geminiSkills": str(self.paths.gemini_skills_dir),
                "claudeSkills": str(self.paths.claude_skills_dir),
                "taxonomy": str(self.paths.taxonomy_path),
            },
        )

    def export_web(self, output_path: Path) -> Path:
        """Export health data report to a web-ready JSON file for @frontend-engineer.

        Creates parent directories automatically and writes safely.
        """
        report = self.check_health()
        output_path = output_path.resolve()
        output_path.parent.mkdir(parents=True, exist_ok=True)

        # Atomic/Safe write
        temp_path = output_path.with_suffix(".tmp")
        try:
            with open(temp_path, "w", encoding="utf-8") as f:
                f.write(report.to_json(indent=2))
            if output_path.exists():
                output_path.unlink()
            temp_path.rename(output_path)
        except Exception:
            # Fallback direct write
            with open(output_path, "w", encoding="utf-8") as f:
                f.write(report.to_json(indent=2))
            if temp_path.exists():
                try:
                    temp_path.unlink()
                except OSError:
                    pass

        return output_path


# ==============================================================================
# CLI Entrypoint
# ==============================================================================

def build_cli_parser() -> argparse.ArgumentParser:
    """Configure command-line arguments."""
    parser = argparse.ArgumentParser(
        prog="health_service.py",
        description="HAWS Standalone Health & Analytics Backend Service",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output raw JSON payload to stdout",
    )
    parser.add_argument(
        "--summary",
        action="store_true",
        help="Print clean human-readable terminal summary",
    )
    parser.add_argument(
        "--export-web",
        type=Path,
        metavar="OUTPUT_PATH",
        help="Generate web-ready health_data.json at specified output path",
    )
    parser.add_argument(
        "--benchmark",
        type=int,
        nargs="?",
        const=20,
        metavar="ITERATIONS",
        help="Run high-precision benchmark for N iterations (default: 20)",
    )
    parser.add_argument(
        "--manifest-path",
        type=Path,
        help="Custom path to .haws_manifest",
    )
    parser.add_argument(
        "--gemini-path",
        type=Path,
        help="Custom path to ~/.gemini/config/skills",
    )
    parser.add_argument(
        "--claude-path",
        type=Path,
        help="Custom path to ~/.claude/skills",
    )
    parser.add_argument(
        "--taxonomy-path",
        type=Path,
        help="Custom path to core/SKILL_TAXONOMY.md",
    )
    return parser


def run_benchmark(service: HealthService, iterations: int = 20) -> None:
    """Benchmark execution time over N iterations to empirically prove sub-second latency."""
    times_ms: List[float] = []
    for _ in range(iterations):
        report = service.check_health()
        times_ms.append(report.executionTimeMs)

    times_ms.sort()
    min_t = times_ms[0]
    avg_t = sum(times_ms) / len(times_ms)
    p50_t = times_ms[len(times_ms) // 2]
    p95_idx = int(len(times_ms) * 0.95)
    p95_t = times_ms[p95_idx]
    max_t = times_ms[-1]

    print("================================================================================")
    print(f" HAWS High-Precision Benchmark Results ({iterations} Iterations)")
    print("================================================================================")
    print(f"Min Latency  : {min_t:>6.2f} ms")
    print(f"P50 Latency  : {p50_t:>6.2f} ms")
    print(f"Avg Latency  : {avg_t:>6.2f} ms")
    print(f"P95 Latency  : {p95_t:>6.2f} ms")
    print(f"Max Latency  : {max_t:>6.2f} ms")
    sub_second_pass = max_t < 300.0
    print(f"Sub-Second SLA (< 300ms) : {'🟢 PASS (VERIFIED)' if sub_second_pass else '🔴 FAIL'}")
    print("================================================================================")


def main(argv: Optional[List[str]] = None) -> int:
    """CLI main function."""
    parser = build_cli_parser()
    args = parser.parse_args(argv)

    default_paths = DataPaths.default()
    paths = DataPaths(
        manifest_path=args.manifest_path or default_paths.manifest_path,
        gemini_skills_dir=args.gemini_path or default_paths.gemini_skills_dir,
        claude_skills_dir=args.claude_path or default_paths.claude_skills_dir,
        taxonomy_path=args.taxonomy_path or default_paths.taxonomy_path,
    )

    service = HealthService(paths=paths)

    if args.benchmark is not None:
        run_benchmark(service, iterations=args.benchmark)
        return 0

    if args.export_web:
        exported_file = service.export_web(args.export_web)
        report = service.check_health()
        size_bytes = exported_file.stat().st_size if exported_file.exists() else 0
        print(f"[OK] Health data exported successfully:")
        print(f"     Destination: {exported_file}")
        print(f"     Payload Size: {size_bytes:,} bytes")
        print(f"     Execution Time: {report.executionTimeMs:.2f} ms")
        print(f"     Status: [{report.overallStatus}] {report.statusMessage}")
        return 0

    if args.json:
        report = service.check_health()
        sys.stdout.write(report.to_json(indent=2) + "\n")
        return 0

    # Default action or --summary: output human-readable terminal summary
    report = service.check_health()
    sys.stdout.write(report.to_summary_text() + "\n")
    return 0 if report.overallStatus == "HEALTHY" else 1


if __name__ == "__main__":
    sys.exit(main())
