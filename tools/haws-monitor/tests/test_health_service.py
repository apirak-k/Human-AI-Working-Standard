#!/usr/bin/env python3
"""Unit and Integration Tests for HAWS Health & Analytics Backend Service.

Adheres to Test-Driven Development (TDD) principles and verifies:
1. Native directory scanning without subshells.
2. Safe parsing of manifests and taxonomy documents.
3. Accurate 5-Drawer category calculation.
4. Pokayoke resilience on missing/corrupt files.
5. CLI interface compliance (--json, --summary, --export-web).
6. Sub-second performance SLA (< 300ms).
"""

import io
import json
from pathlib import Path
import sys
import tempfile
import unittest

# Ensure src is importable
repo_root = Path(__file__).resolve().parents[3]
src_dir = repo_root / "tools" / "haws-monitor" / "src"
if str(src_dir) not in sys.path:
    sys.path.insert(0, str(src_dir))

from health_service import (
    DRAWER_METADATA,
    DataPaths,
    DrawerCategory,
    HealthService,
    ManifestReader,
    SkillCounts,
    SkillScanner,
    SystemHealthReport,
    TaxonomyReader,
    build_cli_parser,
    main,
)


class TestSkillScanner(unittest.TestCase):
    """Test native directory scanner (os.scandir)."""

    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_scan_existing_directories(self) -> None:
        # Create directories and a regular file
        (self.root / "skill-alpha").mkdir()
        (self.root / "skill-beta").mkdir()
        (self.root / "not-a-skill.txt").write_text("hello", encoding="utf-8")

        skills, err = SkillScanner.scan_directory(self.root)
        self.assertIsNone(err)
        self.assertEqual(skills, {"skill-alpha", "skill-beta"})
        self.assertNotIn("not-a-skill.txt", skills)

    def test_scan_empty_directory(self) -> None:
        skills, err = SkillScanner.scan_directory(self.root)
        self.assertIsNone(err)
        self.assertEqual(skills, set())

    def test_scan_missing_directory_pokayoke(self) -> None:
        missing_dir = self.root / "nonexistent"
        skills, err = SkillScanner.scan_directory(missing_dir)
        self.assertIsNotNone(err)
        self.assertEqual(skills, set())


class TestManifestReader(unittest.TestCase):
    """Test ~/.haws_manifest reader."""

    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.manifest_file = Path(self.temp_dir.name) / ".haws_manifest"

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_read_valid_manifest(self) -> None:
        content = (
            "# HAWS Manifest\n"
            "skill:tdd\n"
            "skill:brainstorming\n"
            "agent:backend-engineer\n"
            "agent:frontend-engineer\n"
            "\n"
            "# Comment line\n"
            "skill:code-review\n"
        )
        self.manifest_file.write_text(content, encoding="utf-8")

        skills, agents, err = ManifestReader.read_manifest(self.manifest_file)
        self.assertIsNone(err)
        self.assertEqual(skills, {"tdd", "brainstorming", "code-review"})
        self.assertEqual(agents, {"backend-engineer", "frontend-engineer"})

    def test_read_missing_manifest_pokayoke(self) -> None:
        missing_path = Path(self.temp_dir.name) / "does_not_exist"
        skills, agents, err = ManifestReader.read_manifest(missing_path)
        self.assertIsNotNone(err)
        self.assertEqual(skills, set())
        self.assertEqual(agents, set())


class TestTaxonomyReader(unittest.TestCase):
    """Test SKILL_TAXONOMY.md parser."""

    def setUp(self) -> None:
        self.taxonomy_path = repo_root / "core" / "SKILL_TAXONOMY.md"

    def test_read_real_repo_taxonomy(self) -> None:
        if not self.taxonomy_path.is_file():
            self.skipTest("core/SKILL_TAXONOMY.md not found in test environment")

        drawers, affinities, err = TaxonomyReader.read_taxonomy(self.taxonomy_path)
        self.assertIsNone(err)
        self.assertEqual(len(drawers), 5)

        # Check all 5 drawers
        self.assertIn(1, drawers)
        self.assertIn(2, drawers)
        self.assertIn(3, drawers)
        self.assertIn(4, drawers)
        self.assertIn(5, drawers)

        # Check declared counts match catalog
        self.assertEqual(drawers[1]["declared_count"], 26)
        self.assertEqual(drawers[2]["declared_count"], 25)
        self.assertEqual(drawers[3]["declared_count"], 13)
        self.assertEqual(drawers[4]["declared_count"], 15)
        self.assertEqual(drawers[5]["declared_count"], 25)

        # Total skills should be 104
        total_skills = sum(len(d["skills"]) for d in drawers.values())
        self.assertEqual(total_skills, 104)


        # Check affinities
        self.assertIn("@backend-engineer", affinities)
        self.assertIn("@frontend-engineer", affinities)
        self.assertIn("@organizer", affinities)
        self.assertIn("@tester", affinities)
        self.assertIn("@researcher", affinities)

    def test_missing_taxonomy_canonical_fallback(self) -> None:
        missing_path = Path("nonexistent_taxonomy.md")
        drawers, affinities, err = TaxonomyReader.read_taxonomy(missing_path)
        self.assertIsNotNone(err)
        self.assertEqual(len(drawers), 5)
        self.assertEqual(drawers[1]["declared_count"], 26)
        total_skills = sum(len(d["skills"]) for d in drawers.values())
        self.assertEqual(total_skills, 104)



class TestHealthService(unittest.TestCase):
    """Test HealthService business logic and Pokayoke error-handling."""

    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)

        self.gemini_dir = self.root / "gemini_skills"
        self.gemini_dir.mkdir()
        self.claude_dir = self.root / "claude_skills"
        self.claude_dir.mkdir()
        self.manifest_file = self.root / ".haws_manifest"

        self.paths = DataPaths(
            manifest_path=self.manifest_file,
            gemini_skills_dir=self.gemini_dir,
            claude_skills_dir=self.claude_dir,
            taxonomy_path=repo_root / "core" / "SKILL_TAXONOMY.md",
        )

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_healthy_full_parity(self) -> None:
        # Populate all 102 default skills
        all_skills: Set[str] = set()
        for d in DRAWER_METADATA.values():
            all_skills.update(d["default_skills"])

        for sk in all_skills:
            (self.gemini_dir / sk).mkdir()
            (self.claude_dir / sk).mkdir()

        manifest_lines = [f"skill:{s}" for s in sorted(all_skills)]
        manifest_lines.append("agent:backend-engineer")
        self.manifest_file.write_text("\n".join(manifest_lines) + "\n", encoding="utf-8")

        service = HealthService(paths=self.paths)
        report = service.check_health()

        self.assertEqual(report.overallStatus, "HEALTHY")
        self.assertTrue(report.counts.synced)
        self.assertTrue(report.counts.inSyncWithTaxonomy)
        self.assertEqual(report.counts.gemini, 104)
        self.assertEqual(report.counts.claude, 104)
        self.assertEqual(report.counts.manifest, 104)
        self.assertEqual(report.counts.manifestAgents, 1)
        self.assertLess(report.executionTimeMs, 300.0)


    def test_mismatch_detected(self) -> None:
        (self.gemini_dir / "skill-1").mkdir()
        (self.claude_dir / "skill-2").mkdir()
        self.manifest_file.write_text("skill:skill-1\n", encoding="utf-8")

        service = HealthService(paths=self.paths)
        report = service.check_health()

        self.assertEqual(report.overallStatus, "MISMATCH")
        self.assertFalse(report.counts.synced)
        self.assertIn("skill-2", report.diagnostics["unregisteredSkills"])

    def test_degraded_when_store_missing(self) -> None:
        # Pass non-existent manifest
        bad_paths = DataPaths(
            manifest_path=self.root / "does_not_exist",
            gemini_skills_dir=self.gemini_dir,
            claude_skills_dir=self.claude_dir,
            taxonomy_path=self.paths.taxonomy_path,
        )
        service = HealthService(paths=bad_paths)
        report = service.check_health()

        self.assertEqual(report.overallStatus, "DEGRADED")
        self.assertFalse(report.counts.synced)
        self.assertTrue(len(report.diagnostics["warnings"]) > 0)


class TestCLIAndExport(unittest.TestCase):
    """Test CLI interface and Web Export."""

    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def test_cli_parser_defaults(self) -> None:
        parser = build_cli_parser()
        args = parser.parse_args([])
        self.assertFalse(args.json)
        self.assertFalse(args.summary)
        self.assertIsNone(args.export_web)

    def test_export_web_generates_valid_json(self) -> None:
        service = HealthService()
        export_target = self.root / "subfolder" / "health_data.json"

        output_path = service.export_web(export_target)
        self.assertTrue(output_path.is_file())

        with open(output_path, "r", encoding="utf-8") as f:
            data = json.load(f)

        self.assertIn("executionTimeMs", data)
        self.assertIn("overallStatus", data)
        self.assertIn("counts", data)
        self.assertIn("categories", data)
        self.assertEqual(len(data["categories"]), 5)

        # Check drawer schema
        first_drawer = data["categories"][0]
        self.assertIn("id", first_drawer)
        self.assertIn("drawerNumber", first_drawer)
        self.assertIn("name", first_drawer)
        self.assertIn("shortName", first_drawer)
        self.assertIn("icon", first_drawer)
        self.assertIn("declaredCount", first_drawer)
        self.assertIn("activeCount", first_drawer)
        self.assertIn("skills", first_drawer)

    def test_main_json_flag(self) -> None:
        stdout_capture = io.StringIO()
        old_stdout = sys.stdout
        try:
            sys.stdout = stdout_capture
            main(["--json"])
        finally:
            sys.stdout = old_stdout

        raw_output = stdout_capture.getvalue()
        data = json.loads(raw_output)
        self.assertIn("executionTimeMs", data)
        self.assertIn("overallStatus", data)
        self.assertIn("categories", data)

    def test_performance_sla(self) -> None:
        """Verify that execution completes in sub-second latency (< 300ms)."""
        service = HealthService()
        latencies = []
        for _ in range(10):
            report = service.check_health()
            latencies.append(report.executionTimeMs)

        avg_latency = sum(latencies) / len(latencies)
        max_latency = max(latencies)
        self.assertLess(max_latency, 300.0, f"Max latency {max_latency}ms exceeded 300ms SLA")
        self.assertLess(avg_latency, 100.0, f"Average latency {avg_latency}ms exceeded 100ms")


if __name__ == "__main__":
    unittest.main()
