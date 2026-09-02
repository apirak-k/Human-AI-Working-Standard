"""Unit tests for HAWS Doctor System Diagnostics Utility.

Tests diagnostic checks:
- Core files verification (all 8 files, non-zero size)
- Subagent verification (all 5 agents, valid YAML frontmatter)
- Skills & Token Budget estimation and parity
- Git & Submodules initialization
- Scripts existence
- CLI output modes (human-readable and --json)
- Exit code determination (0 on PASS/WARN, non-zero on FAIL)
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

# Add repo root and scripts directory to sys.path
REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

try:
    import haws_doctor
    from haws_doctor import HawsDoctor, DoctorReport, CheckResult
except ImportError:
    haws_doctor = None
    HawsDoctor = None
    DoctorReport = None
    CheckResult = None


class TestHawsDoctorCoreFiles(unittest.TestCase):
    """Tests for core files diagnostic check."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.repo_dir = Path(self.test_dir)
        self.core_dir = self.repo_dir / "core"
        self.core_dir.mkdir(parents=True)

        self.expected_files = [
            "ANTI_PATTERNS.md",
            "DESIGN.md",
            "HANDOFF.md",
            "HAWS.md",
            "SKILL_TAXONOMY.md",
            "TEMPLATES.md",
            "USER_PREFERENCES.md",
            "WORK_INSTRUCTIONS.md",
        ]

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_core_files_all_present_and_non_empty(self):
        """Should PASS when all 8 core files exist with non-zero size."""
        for name in self.expected_files:
            file_path = self.core_dir / name
            file_path.write_text(f"# {name}\nSample content", encoding="utf-8")

        doctor = HawsDoctor(repo_root=self.repo_dir)
        result = doctor.check_core_files()

        self.assertEqual(result.status, "PASS")
        self.assertEqual(result.details["found"], 8)
        self.assertEqual(result.details["expected"], 8)

    def test_core_files_missing_one(self):
        """Should FAIL when any core file is missing."""
        for name in self.expected_files[:-1]:
            file_path = self.core_dir / name
            file_path.write_text(f"# {name}\nSample content", encoding="utf-8")

        doctor = HawsDoctor(repo_root=self.repo_dir)
        result = doctor.check_core_files()

        self.assertEqual(result.status, "FAIL")
        self.assertEqual(result.details["found"], 7)
        self.assertIn("missing", result.message.lower())

    def test_core_files_empty_file(self):
        """Should FAIL when a core file is 0 bytes."""
        for name in self.expected_files:
            file_path = self.core_dir / name
            if name == "HAWS.md":
                file_path.write_text("", encoding="utf-8")
            else:
                file_path.write_text("content", encoding="utf-8")

        doctor = HawsDoctor(repo_root=self.repo_dir)
        result = doctor.check_core_files()

        self.assertEqual(result.status, "FAIL")
        self.assertIn("zero-size", result.message.lower())


class TestHawsDoctorSubagents(unittest.TestCase):
    """Tests for subagents diagnostic check."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.repo_dir = Path(self.test_dir)
        self.agents_dir = self.repo_dir / "agents"
        self.agents_dir.mkdir(parents=True)

        self.expected_agents = [
            "backend-engineer.md",
            "frontend-engineer.md",
            "organizer.md",
            "researcher.md",
            "tester.md",
        ]

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_subagents_all_valid(self):
        """Should PASS when all 5 subagents exist with valid YAML frontmatter."""
        for name in self.expected_agents:
            agent_name = name.replace(".md", "")
            content = f"---\nname: {agent_name}\ndescription: Responsible for {agent_name} tasks\ntools:\n  - Read\n---\n# {agent_name}\n"
            (self.agents_dir / name).write_text(content, encoding="utf-8")

        doctor = HawsDoctor(repo_root=self.repo_dir)
        result = doctor.check_subagents()

        self.assertEqual(result.status, "PASS")
        self.assertEqual(result.details["found"], 5)
        self.assertEqual(result.details["expected"], 5)

    def test_subagents_invalid_yaml(self):
        """Should FAIL when a subagent has malformed YAML frontmatter."""
        for name in self.expected_agents:
            agent_name = name.replace(".md", "")
            if name == "tester.md":
                # Malformed frontmatter (no closing ---)
                content = f"---\nname: {agent_name}\ndescription: no closing frontmatter\n"
            else:
                content = f"---\nname: {agent_name}\ndescription: Valid\n---\n# Agent\n"
            (self.agents_dir / name).write_text(content, encoding="utf-8")

        doctor = HawsDoctor(repo_root=self.repo_dir)
        result = doctor.check_subagents()

        self.assertEqual(result.status, "FAIL")
        self.assertIn("tester.md", result.message)

    def test_subagents_missing_one(self):
        """Should FAIL when an expected subagent file is missing."""
        for name in self.expected_agents[:-1]:
            agent_name = name.replace(".md", "")
            content = f"---\nname: {agent_name}\ndescription: Valid\n---\n# Agent\n"
            (self.agents_dir / name).write_text(content, encoding="utf-8")

        doctor = HawsDoctor(repo_root=self.repo_dir)
        result = doctor.check_subagents()

        self.assertEqual(result.status, "FAIL")
        self.assertIn("missing", result.message.lower())


class TestHawsDoctorSkillsAndTokens(unittest.TestCase):
    """Tests for active skills parity and token budget calculation."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.base = Path(self.test_dir)
        self.gemini_dir = self.base / "gemini" / "skills"
        self.claude_dir = self.base / "claude" / "skills"
        self.manifest_file = self.base / ".haws_manifest"

        self.gemini_dir.mkdir(parents=True)
        self.claude_dir.mkdir(parents=True)

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def _create_skill(self, parent_dir, skill_name, description):
        sdir = parent_dir / skill_name
        sdir.mkdir(parents=True, exist_ok=True)
        skill_md = sdir / "SKILL.md"
        content = f"---\nname: {skill_name}\ndescription: {description}\n---\n# {skill_name}\n"
        skill_md.write_text(content, encoding="utf-8")

    def test_skills_and_tokens_safe_and_parity(self):
        """Should PASS when counts match and token budget is well within limit (< 15,000)."""
        manifest_lines = []
        for i in range(5):
            sname = f"skill-{i}"
            desc = "Short description for testing."
            self._create_skill(self.gemini_dir, sname, desc)
            self._create_skill(self.claude_dir, sname, desc)
            manifest_lines.append(f"skill:{sname}")

        self.manifest_file.write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")

        doctor = HawsDoctor(
            gemini_skills_dir=self.gemini_dir,
            claude_skills_dir=self.claude_dir,
            manifest_path=self.manifest_file,
        )
        result = doctor.check_skills_and_tokens()

        self.assertEqual(result.status, "PASS")
        self.assertEqual(result.details["gemini_count"], 5)
        self.assertEqual(result.details["claude_count"], 5)
        self.assertEqual(result.details["manifest_count"], 5)
        self.assertEqual(result.details["sync_parity"], True)
        self.assertEqual(result.details["token_budget_status"], "SAFE")

    def test_skills_token_budget_warning(self):
        """Should WARN when token count reaches >= 15,000 (75%)."""
        manifest_lines = []
        # 15,000 tokens * 3.8 = ~57,000 chars
        large_desc = "x" * 58000
        self._create_skill(self.gemini_dir, "big-skill", large_desc)
        self._create_skill(self.claude_dir, "big-skill", large_desc)
        manifest_lines.append("skill:big-skill")
        self.manifest_file.write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")

        doctor = HawsDoctor(
            gemini_skills_dir=self.gemini_dir,
            claude_skills_dir=self.claude_dir,
            manifest_path=self.manifest_file,
        )
        result = doctor.check_skills_and_tokens()

        self.assertEqual(result.status, "WARN")
        self.assertEqual(result.details["token_budget_status"], "WARNING")
        self.assertGreaterEqual(result.details["estimated_tokens"], 15000)

    def test_skills_token_budget_critical(self):
        """Should FAIL when token count reaches >= 18,000 (90%)."""
        manifest_lines = []
        # 18,500 tokens * 3.8 = ~70,300 chars
        critical_desc = "x" * 71000
        self._create_skill(self.gemini_dir, "huge-skill", critical_desc)
        self._create_skill(self.claude_dir, "huge-skill", critical_desc)
        manifest_lines.append("skill:huge-skill")
        self.manifest_file.write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")

        doctor = HawsDoctor(
            gemini_skills_dir=self.gemini_dir,
            claude_skills_dir=self.claude_dir,
            manifest_path=self.manifest_file,
        )
        result = doctor.check_skills_and_tokens()

        self.assertEqual(result.status, "FAIL")
        self.assertEqual(result.details["token_budget_status"], "CRITICAL")
        self.assertGreaterEqual(result.details["estimated_tokens"], 18000)

    def test_skills_count_mismatch(self):
        """Should WARN when skill counts differ across stores."""
        self._create_skill(self.gemini_dir, "skill-a", "desc")
        self._create_skill(self.gemini_dir, "skill-b", "desc")
        self._create_skill(self.claude_dir, "skill-a", "desc")
        self.manifest_file.write_text("skill:skill-a\n", encoding="utf-8")

        doctor = HawsDoctor(
            gemini_skills_dir=self.gemini_dir,
            claude_skills_dir=self.claude_dir,
            manifest_path=self.manifest_file,
        )
        result = doctor.check_skills_and_tokens()

        self.assertEqual(result.status, "WARN")
        self.assertEqual(result.details["sync_parity"], False)


class TestHawsDoctorScripts(unittest.TestCase):
    """Tests for required scripts verification."""

    def setUp(self):
        self.test_dir = tempfile.mkdtemp()
        self.repo_dir = Path(self.test_dir)
        (self.repo_dir / "scripts").mkdir(parents=True)

        self.expected_scripts = [
            "install.sh",
            "update.sh",
            "scripts/check-skills.sh",
            "scripts/check-skills.ps1",
        ]

    def tearDown(self):
        shutil.rmtree(self.test_dir, ignore_errors=True)

    def test_scripts_all_present(self):
        """Should PASS when all 4 required scripts exist and are non-empty."""
        for rel_path in self.expected_scripts:
            full_path = self.repo_dir / rel_path
            full_path.write_text("#!/bin/sh\necho test\n", encoding="utf-8")

        doctor = HawsDoctor(repo_root=self.repo_dir)
        result = doctor.check_scripts()

        self.assertEqual(result.status, "PASS")
        self.assertEqual(result.details["found"], 4)

    def test_scripts_missing_one(self):
        """Should FAIL when any required script is missing."""
        for rel_path in self.expected_scripts[:-1]:
            full_path = self.repo_dir / rel_path
            full_path.write_text("#!/bin/sh\necho test\n", encoding="utf-8")

        doctor = HawsDoctor(repo_root=self.repo_dir)
        result = doctor.check_scripts()

        self.assertEqual(result.status, "FAIL")
        self.assertIn("check-skills.ps1", result.message)


class TestHawsDoctorGitAndSubmodules(unittest.TestCase):
    """Tests for git working tree and submodule checks."""

    def test_real_git_and_submodules(self):
        """Should run against the real repository and return a valid result."""
        doctor = HawsDoctor(repo_root=REPO_ROOT)
        result = doctor.check_git_and_submodules()

        self.assertIn(result.status, ["PASS", "WARN"])
        self.assertTrue(result.details["is_git_repo"])
        self.assertTrue(result.details["submodules"]["all_initialized"])


class TestHawsDoctorCLIAndReport(unittest.TestCase):
    """Tests for CLI execution, --json output, and report structure."""

    def test_report_structure(self):
        """DoctorReport must contain status, timestamp, summary, and checks."""
        doctor = HawsDoctor(repo_root=REPO_ROOT)
        report = doctor.run_all_checks()

        self.assertIn(report.status, ["PASS", "WARN", "FAIL"])
        self.assertTrue(report.timestamp)
        self.assertIn("total_checks", report.summary)
        self.assertIn("passed", report.summary)
        self.assertIn("warnings", report.summary)
        self.assertIn("failures", report.summary)

        # 5 required checks
        self.assertIn("core_files", report.checks)
        self.assertIn("subagents", report.checks)
        self.assertIn("skills_and_tokens", report.checks)
        self.assertIn("git_and_submodules", report.checks)
        self.assertIn("scripts", report.checks)

    def test_cli_json_mode(self):
        """CLI with --json should output valid JSON with top-level keys."""
        script_path = REPO_ROOT / "scripts" / "haws_doctor.py"
        proc = subprocess.run(
            [sys.executable, str(script_path), "--json"],
            capture_output=True,
            text=True,
            cwd=str(REPO_ROOT),
        )

        self.assertEqual(proc.returncode, 0, f"Stderr: {proc.stderr}")
        data = json.loads(proc.stdout)
        self.assertIn("status", data)
        self.assertIn("timestamp", data)
        self.assertIn("summary", data)
        self.assertIn("checks", data)

    def test_cli_human_readable_mode(self):
        """CLI without --json should output clean text with status indicators."""
        script_path = REPO_ROOT / "scripts" / "haws_doctor.py"
        proc = subprocess.run(
            [sys.executable, str(script_path)],
            capture_output=True,
            text=True,
            cwd=str(REPO_ROOT),
        )

        self.assertEqual(proc.returncode, 0, f"Stderr: {proc.stderr}")
        self.assertIn("HAWS System Diagnostics", proc.stdout)
        self.assertTrue(
            "[PASS]" in proc.stdout or "[WARN]" in proc.stdout or "[FAIL]" in proc.stdout
        )

    def test_cli_exit_code_failure(self):
        """CLI should return non-zero exit code when critical checks fail."""
        with tempfile.TemporaryDirectory() as empty_dir:
            script_path = REPO_ROOT / "scripts" / "haws_doctor.py"
            proc = subprocess.run(
                [sys.executable, str(script_path), "--repo-root", empty_dir, "--json"],
                capture_output=True,
                text=True,
            )

            self.assertEqual(proc.returncode, 1)
            data = json.loads(proc.stdout)
            self.assertEqual(data["status"], "FAIL")
            self.assertGreater(data["summary"]["failures"], 0)

    def test_cli_custom_paths(self):
        """CLI should accept custom skill directories and manifest path."""
        with tempfile.TemporaryDirectory() as temp_dir:
            td = Path(temp_dir)
            gdir = td / "gemini"
            cdir = td / "claude"
            mpath = td / "manifest"
            gdir.mkdir()
            cdir.mkdir()
            mpath.write_text("", encoding="utf-8")

            script_path = REPO_ROOT / "scripts" / "haws_doctor.py"
            proc = subprocess.run(
                [
                    sys.executable,
                    str(script_path),
                    "--gemini-skills",
                    str(gdir),
                    "--claude-skills",
                    str(cdir),
                    "--manifest",
                    str(mpath),
                    "--json",
                ],
                capture_output=True,
                text=True,
                cwd=str(REPO_ROOT),
            )

            data = json.loads(proc.stdout)
            skills_check = data["checks"]["skills_and_tokens"]
            self.assertEqual(skills_check["details"]["gemini_count"], 0)
            self.assertEqual(skills_check["details"]["claude_count"], 0)
            self.assertEqual(skills_check["details"]["manifest_count"], 0)


class TestHawsDoctorEdgeCases(unittest.TestCase):
    """Additional edge cases for error recovery and Pokayoke."""

    def test_scripts_empty_file(self):
        """Should FAIL when any required script has size 0."""
        with tempfile.TemporaryDirectory() as temp_dir:
            repo_dir = Path(temp_dir)
            (repo_dir / "scripts").mkdir(parents=True)
            for rel in [
                "install.sh",
                "update.sh",
                "scripts/check-skills.sh",
                "scripts/check-skills.ps1",
            ]:
                target = repo_dir / rel
                if rel == "update.sh":
                    target.write_text("", encoding="utf-8")  # Empty!
                else:
                    target.write_text("#!/bin/sh\n", encoding="utf-8")

            doctor = HawsDoctor(repo_root=repo_dir)
            result = doctor.check_scripts()

            self.assertEqual(result.status, "FAIL")
            self.assertIn("update.sh", result.message)
            self.assertIn("zero-size", result.message)


if __name__ == "__main__":
    unittest.main()
