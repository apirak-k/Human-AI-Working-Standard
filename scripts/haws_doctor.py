#!/usr/bin/env python3
"""HAWS System Diagnostics Utility (haws doctor).

Comprehensive diagnostic utility for verifying HAWS system health:
- Core files existence and integrity (8 core files)
- Subagent configurations and YAML frontmatter (5 subagents)
- Skill counts parity and Antigravity token budget utilization
- Git repository working tree and submodule initialization
- Required automation and maintenance scripts

Outputs clean terminal text with [PASS], [WARN], [FAIL] indicators,
or pure JSON via the --json flag.
Exit code: 0 when all critical checks pass, non-zero on critical failure.

Author: @backend-engineer
Standard: Human-AI Working Standard (HAWS)
"""

from __future__ import annotations

import argparse
from dataclasses import asdict, dataclass, field
import datetime
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
from typing import Any, Dict, List, Optional, Tuple

# Try to import yaml if available; fallback to lightweight regex parser
try:
    import yaml
    HAS_YAML = True
except ImportError:
    HAS_YAML = False

# ==============================================================================
# Domain Constants
# ==============================================================================

STATUS_PASS = "PASS"
STATUS_WARN = "WARN"
STATUS_FAIL = "FAIL"

CORE_FILES: List[str] = [
    "ANTI_PATTERNS.md",
    "DESIGN.md",
    "HANDOFF.md",
    "HAWS.md",
    "SKILL_TAXONOMY.md",
    "TEMPLATES.md",
    "USER_PREFERENCES.md",
    "WORK_INSTRUCTIONS.md",
]

SUBAGENTS: List[str] = [
    "backend-engineer.md",
    "frontend-engineer.md",
    "organizer.md",
    "researcher.md",
    "tester.md",
]

REQUIRED_SCRIPTS: List[str] = [
    "install.sh",
    "update.sh",
    "scripts/check-skills.sh",
    "scripts/check-skills.ps1",
]

TOKEN_LIMIT = 20000
TOKEN_WARN_THRESHOLD = 15000     # 75%
TOKEN_CRITICAL_THRESHOLD = 18000 # 90%
CHARS_PER_TOKEN = 3.8


# ==============================================================================
# Data Models
# ==============================================================================

@dataclass
class CheckResult:
    """Represents the outcome of a single diagnostic check."""
    name: str
    status: str  # PASS, WARN, FAIL
    message: str
    details: Dict[str, Any] = field(default_factory=dict)
    duration_ms: float = 0.0

    def to_dict(self) -> Dict[str, Any]:
        return {
            "name": self.name,
            "status": self.status,
            "message": self.message,
            "duration_ms": round(self.duration_ms, 2),
            "details": self.details,
        }


@dataclass
class DoctorReport:
    """Full diagnostic report container."""
    status: str  # Overall PASS, WARN, FAIL
    timestamp: str
    summary: Dict[str, int]
    checks: Dict[str, Dict[str, Any]]
    duration_ms: float = 0.0

    def to_dict(self) -> Dict[str, Any]:
        return {
            "status": self.status,
            "timestamp": self.timestamp,
            "duration_ms": round(self.duration_ms, 2),
            "summary": self.summary,
            "checks": self.checks,
        }

    def to_json(self, indent: int = 2) -> str:
        return json.dumps(self.to_dict(), indent=indent, ensure_ascii=False)


# ==============================================================================
# Helper Utilities
# ==============================================================================

def parse_yaml_frontmatter(content: str) -> Tuple[bool, Optional[Dict[str, Any]], str]:
    """Extract and parse YAML frontmatter from markdown content.
    
    Returns: (is_valid, parsed_dict, error_message)
    """
    match = re.search(r"(?s)^---\r?\n(.*?)\r?\n---", content.strip())
    if not match:
        return False, None, "Missing opening or closing '---' YAML frontmatter delimiters"

    raw_yaml = match.group(1).strip()
    if not raw_yaml:
        return False, None, "YAML frontmatter is empty"

    if HAS_YAML:
        try:
            parsed = yaml.safe_load(raw_yaml)
            if not isinstance(parsed, dict):
                return False, None, "YAML frontmatter did not parse into a key-value mapping"
            return True, parsed, ""
        except Exception as exc:
            return False, None, f"YAML parse error: {exc}"
    else:
        # Fallback key-value parser for simple frontmatter
        parsed: Dict[str, Any] = {}
        current_key = None
        for line in raw_yaml.splitlines():
            line_str = line.strip()
            if not line_str or line_str.startswith("#"):
                continue
            if ":" in line:
                key, val = line.split(":", 1)
                key = key.strip()
                val = val.strip()
                current_key = key
                if val:
                    parsed[key] = val
                else:
                    parsed[key] = []
            elif line_str.startswith("- ") and current_key:
                val = line_str[2:].strip()
                if isinstance(parsed.get(current_key), list):
                    parsed[current_key].append(val)
        if not parsed:
            return False, None, "Failed to parse frontmatter key-values"
        return True, parsed, ""


# ==============================================================================
# Core Diagnostic Service
# ==============================================================================

class HawsDoctor:
    """HAWS Diagnostic Engine for health verification."""

    def __init__(
        self,
        repo_root: Optional[Path | str] = None,
        gemini_skills_dir: Optional[Path | str] = None,
        claude_skills_dir: Optional[Path | str] = None,
        manifest_path: Optional[Path | str] = None,
    ):
        if repo_root is not None:
            self.repo_root = Path(repo_root).resolve()
        else:
            # Default to repo root (parent directory of scripts/)
            self.repo_root = Path(__file__).resolve().parent.parent

        home = Path.home()
        self.gemini_skills_dir = (
            Path(gemini_skills_dir).resolve()
            if gemini_skills_dir is not None
            else (home / ".gemini" / "config" / "skills").resolve()
        )
        self.claude_skills_dir = (
            Path(claude_skills_dir).resolve()
            if claude_skills_dir is not None
            else (home / ".claude" / "skills").resolve()
        )
        self.manifest_path = (
            Path(manifest_path).resolve()
            if manifest_path is not None
            else (home / ".haws_manifest").resolve()
        )

    def check_core_files(self) -> CheckResult:
        """Verify all 8 core standard files exist and have non-zero size."""
        start_time = time.perf_counter()
        core_dir = self.repo_root / "core"

        files_info: Dict[str, Dict[str, Any]] = {}
        missing: List[str] = []
        zero_size: List[str] = []

        if not core_dir.is_dir():
            duration_ms = (time.perf_counter() - start_time) * 1000
            return CheckResult(
                name="core_files",
                status=STATUS_FAIL,
                message=f"Core directory missing at {core_dir}",
                details={"expected": len(CORE_FILES), "found": 0, "files": {}},
                duration_ms=duration_ms,
            )

        found_count = 0
        for filename in CORE_FILES:
            target = core_dir / filename
            if not target.exists():
                missing.append(filename)
                files_info[filename] = {"exists": False, "size": 0}
            else:
                try:
                    size = target.stat().st_size
                except OSError:
                    size = 0

                if size == 0:
                    zero_size.append(filename)
                    files_info[filename] = {"exists": True, "size": 0}
                else:
                    found_count += 1
                    files_info[filename] = {"exists": True, "size": size}

        duration_ms = (time.perf_counter() - start_time) * 1000

        if missing or zero_size:
            err_parts = []
            if missing:
                err_parts.append(f"missing: {', '.join(missing)}")
            if zero_size:
                err_parts.append(f"zero-size: {', '.join(zero_size)}")
            return CheckResult(
                name="core_files",
                status=STATUS_FAIL,
                message=f"Core files check failed ({'; '.join(err_parts)}). Restore required files from git.",
                details={
                    "expected": len(CORE_FILES),
                    "found": found_count,
                    "missing": missing,
                    "zero_size": zero_size,
                    "files": files_info,
                },
                duration_ms=duration_ms,
            )

        return CheckResult(
            name="core_files",
            status=STATUS_PASS,
            message=f"All {len(CORE_FILES)} core files exist and are non-empty",
            details={
                "expected": len(CORE_FILES),
                "found": found_count,
                "files": files_info,
            },
            duration_ms=duration_ms,
        )

    def check_subagents(self) -> CheckResult:
        """Verify all 5 subagents in agents/ exist with valid YAML frontmatter."""
        start_time = time.perf_counter()
        agents_dir = self.repo_root / "agents"

        agents_info: Dict[str, Dict[str, Any]] = {}
        missing: List[str] = []
        invalid: List[str] = []
        found_count = 0

        if not agents_dir.is_dir():
            duration_ms = (time.perf_counter() - start_time) * 1000
            return CheckResult(
                name="subagents",
                status=STATUS_FAIL,
                message=f"Agents directory missing at {agents_dir}",
                details={"expected": len(SUBAGENTS), "found": 0, "agents": {}},
                duration_ms=duration_ms,
            )

        for filename in SUBAGENTS:
            target = agents_dir / filename
            if not target.exists():
                missing.append(filename)
                agents_info[filename] = {"exists": False}
                continue

            try:
                content = target.read_text(encoding="utf-8", errors="ignore")
            except OSError as err:
                invalid.append(f"{filename} (read error: {err})")
                agents_info[filename] = {"exists": True, "valid_frontmatter": False, "error": str(err)}
                continue

            valid, parsed, err_msg = parse_yaml_frontmatter(content)
            if not valid:
                invalid.append(f"{filename} ({err_msg})")
                agents_info[filename] = {"exists": True, "valid_frontmatter": False, "error": err_msg}
            else:
                agent_name = parsed.get("name", "") if parsed else ""
                if not agent_name:
                    invalid.append(f"{filename} (missing 'name' in YAML frontmatter)")
                    agents_info[filename] = {"exists": True, "valid_frontmatter": False, "error": "missing name"}
                else:
                    found_count += 1
                    agents_info[filename] = {
                        "exists": True,
                        "valid_frontmatter": True,
                        "name": agent_name,
                        "description": parsed.get("description", ""),
                    }

        duration_ms = (time.perf_counter() - start_time) * 1000

        if missing or invalid:
            err_parts = []
            if missing:
                err_parts.append(f"missing: {', '.join(missing)}")
            if invalid:
                err_parts.append(f"invalid frontmatter: {', '.join(invalid)}")
            return CheckResult(
                name="subagents",
                status=STATUS_FAIL,
                message=f"Subagents check failed ({'; '.join(err_parts)})",
                details={
                    "expected": len(SUBAGENTS),
                    "found": found_count,
                    "missing": missing,
                    "invalid": invalid,
                    "agents": agents_info,
                },
                duration_ms=duration_ms,
            )

        return CheckResult(
            name="subagents",
            status=STATUS_PASS,
            message=f"All {len(SUBAGENTS)} subagents exist with valid YAML frontmatter",
            details={
                "expected": len(SUBAGENTS),
                "found": found_count,
                "agents": agents_info,
            },
            duration_ms=duration_ms,
        )

    def check_skills_and_tokens(self) -> CheckResult:
        """Check active skills in Gemini, Claude, manifest, and calculate token budget."""
        start_time = time.perf_counter()

        gemini_dirs = []
        if self.gemini_skills_dir.is_dir():
            try:
                gemini_dirs = [
                    d for d in self.gemini_skills_dir.iterdir()
                    if d.is_dir()
                ]
            except OSError:
                gemini_dirs = []

        claude_dirs = []
        if self.claude_skills_dir.is_dir():
            try:
                claude_dirs = [
                    d for d in self.claude_skills_dir.iterdir()
                    if d.is_dir()
                ]
            except OSError:
                claude_dirs = []

        manifest_skills = []
        if self.manifest_path.is_file():
            try:
                with open(self.manifest_path, "r", encoding="utf-8", errors="ignore") as fp:
                    for line in fp:
                        clean = line.strip()
                        if clean.startswith("skill:"):
                            manifest_skills.append(clean[6:].strip())
            except OSError:
                manifest_skills = []

        gemini_count = len(gemini_dirs)
        claude_count = len(claude_dirs)
        manifest_count = len(manifest_skills)

        # Token estimation matching Antigravity YAML description parsing
        total_chars = 0
        largest_skills: List[Tuple[str, int, int]] = []  # (name, chars, tokens)

        for sdir in gemini_dirs:
            skill_file = sdir / "SKILL.md"
            if not skill_file.exists():
                skill_file = sdir / "skill.md"

            if skill_file.exists():
                try:
                    content = skill_file.read_text(encoding="utf-8", errors="ignore")
                    fm_match = re.search(r"(?s)^---\r?\n(.*?)\r?\n---", content)
                    if fm_match:
                        fm = fm_match.group(1)
                        desc_match = re.search(r"(?s)description:\s*(.*?)(?=\r?\n[a-zA-Z0-9_-]+:|\Z)", fm)
                        if desc_match:
                            desc_text = desc_match.group(1).strip()
                            chars = len(desc_text)
                            total_chars += chars
                            largest_skills.append((sdir.name, chars, round(chars / CHARS_PER_TOKEN)))
                except OSError:
                    pass

        largest_skills.sort(key=lambda item: item[1], reverse=True)

        est_tokens = round(total_chars / CHARS_PER_TOKEN)
        token_percent = round((est_tokens / TOKEN_LIMIT) * 100, 1)

        # Parity check
        sync_parity = (gemini_count == claude_count == manifest_count)

        # Budget status determination
        if est_tokens >= TOKEN_CRITICAL_THRESHOLD:
            token_budget_status = "CRITICAL"
        elif est_tokens >= TOKEN_WARN_THRESHOLD:
            token_budget_status = "WARNING"
        else:
            token_budget_status = "SAFE"

        # Overall check status
        if token_budget_status == "CRITICAL":
            status = STATUS_FAIL
            message = (
                f"Token budget CRITICAL: ~{est_tokens:,} / {TOKEN_LIMIT:,} tokens ({token_percent}%) "
                f"exceeds 90% threshold. Prune inactive skills or shorten descriptions in SKILL.md."
            )
        elif token_budget_status == "WARNING":
            status = STATUS_WARN
            message = (
                f"Token budget WARNING: ~{est_tokens:,} / {TOKEN_LIMIT:,} tokens ({token_percent}%) "
                f"exceeds 75% threshold. Run with -v to inspect largest skills."
            )
        elif not sync_parity:
            status = STATUS_WARN
            message = (
                f"Skill count mismatch: Antigravity ({gemini_count}), "
                f"Claude Code ({claude_count}), Manifest ({manifest_count}). "
                f"Run './update.sh' to re-synchronize."
            )
        else:
            status = STATUS_PASS
            message = (
                f"Active skills synchronized ({gemini_count} skills) with healthy token budget "
                f"(~{est_tokens:,} / {TOKEN_LIMIT:,} tokens, {token_percent}%)"
            )

        duration_ms = (time.perf_counter() - start_time) * 1000

        details = {
            "gemini_skills_path": str(self.gemini_skills_dir),
            "claude_skills_path": str(self.claude_skills_dir),
            "manifest_path": str(self.manifest_path),
            "gemini_count": gemini_count,
            "claude_count": claude_count,
            "manifest_count": manifest_count,
            "sync_parity": sync_parity,
            "estimated_tokens": est_tokens,
            "token_limit": TOKEN_LIMIT,
            "token_utilization_percent": token_percent,
            "token_budget_status": token_budget_status,
            "top_5_largest_skills": [
                {"name": name, "chars": chars, "tokens": tokens}
                for name, chars, tokens in largest_skills[:5]
            ],
        }

        return CheckResult(
            name="skills_and_tokens",
            status=status,
            message=message,
            details=details,
            duration_ms=duration_ms,
        )

    def check_git_and_submodules(self) -> CheckResult:
        """Verify git working tree status and that all submodules are initialized."""
        start_time = time.perf_counter()
        git_dir = self.repo_root / ".git"

        if not git_dir.exists():
            duration_ms = (time.perf_counter() - start_time) * 1000
            return CheckResult(
                name="git_and_submodules",
                status=STATUS_FAIL,
                message=f"Not a git repository (missing .git at {self.repo_root})",
                details={"is_git_repo": False},
                duration_ms=duration_ms,
            )

        # 1. Branch check
        branch_name = "unknown"
        try:
            res = subprocess.run(
                ["git", "rev-parse", "--abbrev-ref", "HEAD"],
                cwd=str(self.repo_root),
                capture_output=True,
                text=True,
                check=False,
            )
            if res.returncode == 0:
                branch_name = res.stdout.strip()
        except Exception:
            pass

        # 2. Working tree cleanliness
        working_tree_clean = True
        uncommitted_files: List[str] = []
        try:
            res = subprocess.run(
                ["git", "status", "--porcelain", "--ignore-submodules=dirty"],
                cwd=str(self.repo_root),
                capture_output=True,
                text=True,
                check=False,
            )
            if res.returncode == 0:
                lines = [line.strip() for line in res.stdout.splitlines() if line.strip()]
                if lines:
                    working_tree_clean = False
                    uncommitted_files = lines
        except Exception:
            pass

        # 3. Submodules check
        gitmodules_file = self.repo_root / ".gitmodules"
        has_submodules = gitmodules_file.exists()
        submodule_items: List[Dict[str, Any]] = []
        all_initialized = True
        uninitialized_submodules: List[str] = []

        if has_submodules:
            try:
                res = subprocess.run(
                    ["git", "submodule", "status"],
                    cwd=str(self.repo_root),
                    capture_output=True,
                    text=True,
                    check=False,
                )
                if res.returncode == 0:
                    for raw_line in res.stdout.splitlines():
                        line = raw_line.strip()
                        if not line:
                            continue
                        # First char indicates status: ' ' (ok), '-' (uninitialized), '+' (different commit), 'U' (merge conflict)
                        flag = raw_line[0] if len(raw_line) > 0 else " "
                        parts = line.split()
                        commit = parts[0].lstrip("-+U") if len(parts) > 0 else ""
                        sub_path = parts[1] if len(parts) > 1 else ""
                        describe = parts[2] if len(parts) > 2 else ""

                        is_init = (flag != "-")
                        sub_dir = self.repo_root / sub_path
                        dir_exists = sub_dir.is_dir()
                        has_files = False
                        if dir_exists:
                            try:
                                has_files = any(sub_dir.iterdir())
                            except OSError:
                                has_files = False

                        if not is_init or not dir_exists or not has_files:
                            all_initialized = False
                            uninitialized_submodules.append(sub_path)

                        submodule_items.append({
                            "path": sub_path,
                            "commit": commit,
                            "describe": describe,
                            "flag": flag,
                            "initialized": is_init and dir_exists and has_files,
                        })
            except Exception as exc:
                all_initialized = False
                uninitialized_submodules.append(f"submodule status query failed: {exc}")

        duration_ms = (time.perf_counter() - start_time) * 1000

        # Status determination
        if not all_initialized:
            status = STATUS_FAIL
            message = (
                f"Uninitialized git submodules detected: {', '.join(uninitialized_submodules)}. "
                "Run 'git submodule update --init --recursive'"
            )
        elif not working_tree_clean:
            status = STATUS_WARN
            change_word = "change" if len(uncommitted_files) == 1 else "changes"
            message = (
                f"Git working tree on branch '{branch_name}' has "
                f"{len(uncommitted_files)} uncommitted {change_word}"
            )
        else:
            status = STATUS_PASS
            if submodule_items:
                sub_msg = f"all {len(submodule_items)} submodules initialized"
            else:
                sub_msg = "no submodules configured"
            message = (
                f"Git working tree clean on branch '{branch_name}'; "
                f"{sub_msg}"
            )

        details = {
            "is_git_repo": True,
            "branch": branch_name,
            "working_tree_clean": working_tree_clean,
            "uncommitted_changes_count": len(uncommitted_files),
            "uncommitted_files": uncommitted_files[:10],
            "submodules": {
                "present": has_submodules,
                "total": len(submodule_items),
                "all_initialized": all_initialized,
                "uninitialized": uninitialized_submodules,
                "items": submodule_items,
            },
        }

        return CheckResult(
            name="git_and_submodules",
            status=status,
            message=message,
            details=details,
            duration_ms=duration_ms,
        )

    def check_scripts(self) -> CheckResult:
        """Verify essential execution, installation, and health scripts exist and are non-empty."""
        start_time = time.perf_counter()
        scripts_info: Dict[str, Dict[str, Any]] = {}
        missing: List[str] = []
        zero_size: List[str] = []
        found_count = 0

        for rel_path in REQUIRED_SCRIPTS:
            target = self.repo_root / rel_path
            if not target.exists():
                missing.append(rel_path)
                scripts_info[rel_path] = {"exists": False, "size": 0}
            else:
                try:
                    size = target.stat().st_size
                except OSError:
                    size = 0

                if size == 0:
                    zero_size.append(rel_path)
                    scripts_info[rel_path] = {"exists": True, "size": 0}
                else:
                    found_count += 1
                    scripts_info[rel_path] = {"exists": True, "size": size}

        duration_ms = (time.perf_counter() - start_time) * 1000

        if missing or zero_size:
            err_parts = []
            if missing:
                err_parts.append(f"missing: {', '.join(missing)}")
            if zero_size:
                err_parts.append(f"zero-size: {', '.join(zero_size)}")
            return CheckResult(
                name="scripts",
                status=STATUS_FAIL,
                message=f"Scripts check failed ({'; '.join(err_parts)}). Restore required scripts from git.",
                details={
                    "expected": len(REQUIRED_SCRIPTS),
                    "found": found_count,
                    "missing": missing,
                    "zero_size": zero_size,
                    "scripts": scripts_info,
                },
                duration_ms=duration_ms,
            )

        return CheckResult(
            name="scripts",
            status=STATUS_PASS,
            message=f"All {len(REQUIRED_SCRIPTS)} required scripts exist and are non-empty",
            details={
                "expected": len(REQUIRED_SCRIPTS),
                "found": found_count,
                "scripts": scripts_info,
            },
            duration_ms=duration_ms,
        )

    def run_all_checks(self) -> DoctorReport:
        """Execute the full suite of diagnostic checks and compile a DoctorReport."""
        overall_start = time.perf_counter()
        timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat()

        check_functions = [
            self.check_core_files,
            self.check_subagents,
            self.check_skills_and_tokens,
            self.check_git_and_submodules,
            self.check_scripts,
        ]

        checks_dict: Dict[str, Dict[str, Any]] = {}
        passed = 0
        warnings = 0
        failures = 0

        for fn in check_functions:
            result = fn()
            checks_dict[result.name] = result.to_dict()
            if result.status == STATUS_PASS:
                passed += 1
            elif result.status == STATUS_WARN:
                warnings += 1
            elif result.status == STATUS_FAIL:
                failures += 1

        if failures > 0:
            overall_status = STATUS_FAIL
        elif warnings > 0:
            overall_status = STATUS_WARN
        else:
            overall_status = STATUS_PASS

        duration_ms = (time.perf_counter() - overall_start) * 1000

        summary = {
            "total_checks": len(check_functions),
            "passed": passed,
            "warnings": warnings,
            "failures": failures,
        }

        return DoctorReport(
            status=overall_status,
            timestamp=timestamp,
            summary=summary,
            checks=checks_dict,
            duration_ms=duration_ms,
        )


# ==============================================================================
# Presentation & CLI Formatting
# ==============================================================================

class TerminalFormatter:
    """Formats DoctorReport for clean human-readable terminal output."""

    # ANSI color codes
    CYAN = "\033[96m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    RED = "\033[91m"
    BOLD = "\033[1m"
    DIM = "\033[2m"
    RESET = "\033[0m"

    def __init__(self, use_color: bool = True):
        self.use_color = use_color and sys.stdout.isatty() and "NO_COLOR" not in os.environ

    def _c(self, text: str, color_code: str) -> str:
        return f"{color_code}{text}{self.RESET}" if self.use_color else text

    def format(self, report: DoctorReport, verbose: bool = False) -> str:
        lines: List[str] = []
        lines.append(self._c("=== HAWS System Diagnostics (haws doctor) ===", self.BOLD + self.CYAN))
        lines.append(f"Timestamp : {report.timestamp}")
        lines.append(f"Scan Time : {report.duration_ms:.1f}ms")
        lines.append("-" * 60)

        for check_name, check_data in report.checks.items():
            status = check_data.get("status", "UNKNOWN")
            message = check_data.get("message", "")
            duration = check_data.get("duration_ms", 0.0)

            if status == STATUS_PASS:
                tag = self._c("[PASS]", self.BOLD + self.GREEN)
            elif status == STATUS_WARN:
                tag = self._c("[WARN]", self.BOLD + self.YELLOW)
            else:
                tag = self._c("[FAIL]", self.BOLD + self.RED)

            CHECK_TITLES = {
                "core_files": "Core Files",
                "subagents": "Subagents",
                "skills_and_tokens": "Skills and Tokens",
                "git_and_submodules": "Git and Submodules",
                "scripts": "Scripts",
            }
            name_title = CHECK_TITLES.get(check_name, check_name.replace("_", " ").title())
            lines.append(f"{tag} {self._c(name_title, self.BOLD)}: {message} {self._c(f'({duration:.1f}ms)', self.DIM)}")

            # Show details if requested or if status is not PASS
            if verbose or status in (STATUS_WARN, STATUS_FAIL):
                details = check_data.get("details", {})
                if check_name == "skills_and_tokens" and "top_5_largest_skills" in details:
                    top5 = details["top_5_largest_skills"]
                    if top5:
                        lines.append(self._c("       Top skill descriptions by token usage:", self.DIM))
                        for item in top5:
                            lines.append(self._c(f"         - {item['name']}: ~{item['tokens']} tokens ({item['chars']} chars)", self.DIM))
                if check_name == "git_and_submodules" and details.get("uncommitted_files"):
                    lines.append(self._c("       Uncommitted files:", self.DIM))
                    uncommitted = details["uncommitted_files"]
                    shown = uncommitted[:5]
                    for uf in shown:
                        lines.append(self._c(f"         {uf}", self.DIM))
                    remaining = len(uncommitted) - len(shown)
                    if remaining > 0:
                        lines.append(self._c(f"         ... and {remaining} more", self.DIM))

        lines.append("-" * 60)

        # Summary line
        overall = report.status
        s = report.summary
        warn_word = "warning" if s['warnings'] == 1 else "warnings"
        fail_word = "failure" if s['failures'] == 1 else "failures"
        summary_str = f"{s['passed']} passed, {s['warnings']} {warn_word}, {s['failures']} {fail_word}"

        if overall == STATUS_PASS:
            res_tag = self._c("[PASS] SYSTEM HEALTHY", self.BOLD + self.GREEN)
        elif overall == STATUS_WARN:
            res_tag = self._c("[WARN] SYSTEM HAS WARNINGS (REVIEW RECOMMENDED)", self.BOLD + self.YELLOW)
        else:
            res_tag = self._c("[FAIL] SYSTEM ISSUES DETECTED - REMEDIATION REQUIRED", self.BOLD + self.RED)

        lines.append(f"Result    : {res_tag} ({summary_str})")

        return "\n".join(lines)


# ==============================================================================
# CLI Entrypoint
# ==============================================================================

def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        prog="haws doctor",
        description="Diagnostic health check for the Human-AI Working Standard (HAWS) environment.",
    )
    parser.add_argument(
        "--json",
        "-j",
        action="store_true",
        help="Emit structured JSON report instead of terminal text.",
    )
    parser.add_argument(
        "--repo-root",
        type=str,
        default=None,
        help="Path to repository root directory (default: parent of scripts/).",
    )
    parser.add_argument(
        "--gemini-skills",
        type=str,
        default=None,
        help="Path to Antigravity/Gemini active skills directory (default: ~/.gemini/config/skills).",
    )
    parser.add_argument(
        "--claude-skills",
        type=str,
        default=None,
        help="Path to Claude Code active skills directory (default: ~/.claude/skills).",
    )
    parser.add_argument(
        "--manifest",
        type=str,
        default=None,
        help="Path to skill manifest file (default: ~/.haws_manifest).",
    )
    parser.add_argument(
        "--no-color",
        action="store_true",
        help="Disable ANSI colors in terminal output.",
    )
    parser.add_argument(
        "-v",
        "--verbose",
        action="store_true",
        help="Display detailed diagnostic breakdowns (e.g. largest skills, uncommitted files).",
    )

    args = parser.parse_args(argv)

    doctor = HawsDoctor(
        repo_root=args.repo_root,
        gemini_skills_dir=args.gemini_skills,
        claude_skills_dir=args.claude_skills,
        manifest_path=args.manifest,
    )

    report = doctor.run_all_checks()

    if args.json:
        print(report.to_json())
    else:
        formatter = TerminalFormatter(use_color=not args.no_color)
        print(formatter.format(report, verbose=args.verbose))

    # Exit code: 0 when all critical checks pass (PASS or WARN), non-zero on FAIL
    return 1 if report.status == STATUS_FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
