package settings

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func sourceSyncFixture(t *testing.T) (Store, string, string, string, string) {
	t.Helper()
	root := fixtureRepo(t)
	const sourcePath = "skills/packs/demo"
	sourceDir := filepath.Join(root, filepath.FromSlash(sourcePath))
	if err := os.MkdirAll(sourceDir, 0700); err != nil {
		t.Fatal(err)
	}
	fixtureGit(t, sourceDir, "init", "-b", "main")
	fixtureGit(t, sourceDir, "config", "user.email", "test@example.invalid")
	fixtureGit(t, sourceDir, "config", "user.name", "Test")
	fixtureFile(t, filepath.Join(sourceDir, "skills", "demo", "SKILL.md"), "---\nname: demo\ndescription: fixture\n---\n\nInitial skill.\n")
	fixtureFile(t, filepath.Join(sourceDir, "skills", "other", "SKILL.md"), "---\nname: other\ndescription: fixture\n---\n\nOther active skill.\n")
	fixtureFile(t, filepath.Join(root, ".gitmodules"), "[submodule \"demo\"]\n\tpath = "+sourcePath+"\n\turl = https://example.invalid/demo.git\n")
	fixtureGit(t, sourceDir, "add", ".")
	fixtureGit(t, sourceDir, "commit", "-m", "baseline")

	remote := filepath.Join(fixtureDir(t), "demo.git")
	if output, err := exec.Command("git", "init", "--bare", remote).CombinedOutput(); err != nil {
		t.Fatalf("initialize source remote: %v: %s", err, output)
	}
	fixtureGit(t, sourceDir, "remote", "add", "origin", remote)
	fixtureGit(t, sourceDir, "push", "-u", "origin", "main")
	if err := exec.Command("git", "--git-dir", remote, "symbolic-ref", "HEAD", "refs/heads/main").Run(); err != nil {
		t.Fatal(err)
	}
	seed := filepath.Join(fixtureDir(t), "seed")
	if output, err := exec.Command("git", "clone", remote, seed).CombinedOutput(); err != nil {
		t.Fatalf("clone source seed: %v: %s", err, output)
	}
	fixtureGit(t, seed, "config", "user.email", "test@example.invalid")
	fixtureGit(t, seed, "config", "user.name", "Test")
	return NewStore(root), sourceDir, seed, remote, "demo::" + sourcePath
}

func advanceSourceSyncSeed(t *testing.T, seed, path, contents string) string {
	t.Helper()
	fixtureFile(t, filepath.Join(seed, filepath.FromSlash(path)), contents)
	fixtureGit(t, seed, "add", path)
	fixtureGit(t, seed, "commit", "-m", "advance source")
	fixtureGit(t, seed, "push", "origin", "main")
	return fixtureGit(t, seed, "rev-parse", "HEAD")
}

func TestSyncSourceUpdatesChangedActiveSkillAndCleansCandidateRef(t *testing.T) {
	store, sourceDir, seed, remote, sourceID := sourceSyncFixture(t)
	t.Setenv("HAWS_SYNC_CANDIDATE_REF", "refs/haws-sync/test-source")
	t.Setenv("HAWS_SYNC_PREFETCH_DONE", "")
	want := advanceSourceSyncSeed(t, seed, "skills/demo/SKILL.md", "---\nname: demo\ndescription: fixture\n---\n\nUpdated skill.\n")

	got := SyncSource(context.Background(), store, sourceID, nil, 10*time.Second)
	if got.Status != "updated" || got.Revision != want || got.Detail != "final HEAD equals candidate" {
		t.Fatalf("SyncSource() = %#v", got)
	}
	if fixtureGit(t, sourceDir, "rev-parse", "HEAD") != want {
		t.Fatal("active skill source did not advance to candidate")
	}
	if _, err := fixtureGitOutput(t, sourceDir, "symbolic-ref", "--quiet", "--short", "HEAD"); err == nil {
		t.Fatal("updated skill source should remain detached")
	}
	if fixtureGit(t, remote, "rev-parse", "refs/heads/main") != want {
		t.Fatal("source sync changed the upstream remote")
	}
	if refs := fixtureGit(t, sourceDir, "for-each-ref", "refs/haws-sync"); refs != "" {
		t.Fatalf("candidate refs were not cleaned: %s", refs)
	}

	if got := SyncSource(context.Background(), store, sourceID, nil, time.Second); got.Status != "up-to-date" || got.Revision != want {
		t.Fatalf("repeat SyncSource() = %#v", got)
	}
}

func TestSyncSourceLeavesRepositoryAloneWhenActiveSkillsDidNotChange(t *testing.T) {
	store, sourceDir, seed, _, sourceID := sourceSyncFixture(t)
	current := fixtureGit(t, sourceDir, "rev-parse", "HEAD")
	advanceSourceSyncSeed(t, seed, "README.md", "documentation only\n")
	t.Setenv("HAWS_SYNC_CANDIDATE_REF", "refs/haws-sync/test-source-readme")
	t.Setenv("HAWS_SYNC_PREFETCH_DONE", "")

	got := SyncSource(context.Background(), store, sourceID, nil, 10*time.Second)
	if got.Status != "up-to-date" || got.Revision != current || got.Detail != "active skills unchanged" {
		t.Fatalf("SyncSource() = %#v", got)
	}
	if fixtureGit(t, sourceDir, "rev-parse", "HEAD") != current {
		t.Fatal("documentation-only candidate changed the installed source")
	}
}

func TestSyncSourcePreservesLocalAheadCommit(t *testing.T) {
	store, sourceDir, _, _, sourceID := sourceSyncFixture(t)
	fixtureFile(t, filepath.Join(sourceDir, "skills", "demo", "SKILL.md"), "---\nname: demo\ndescription: local\n---\n\nLocal ahead.\n")
	fixtureGit(t, sourceDir, "add", "skills/demo/SKILL.md")
	fixtureGit(t, sourceDir, "commit", "-m", "local source update")
	localHead := fixtureGit(t, sourceDir, "rev-parse", "HEAD")
	t.Setenv("HAWS_SYNC_CANDIDATE_REF", "refs/haws-sync/test-source-ahead")
	t.Setenv("HAWS_SYNC_PREFETCH_DONE", "")

	got := SyncSource(context.Background(), store, sourceID, nil, 10*time.Second)
	if got.Status != "up-to-date" || got.Revision != localHead || got.Detail != "local HEAD is ahead of remote candidate" {
		t.Fatalf("local-ahead SyncSource() = %#v", got)
	}
	if fixtureGit(t, sourceDir, "rev-parse", "HEAD") != localHead {
		t.Fatal("local-ahead source checkout changed")
	}
}

func TestSyncSourceUpdatesNewSkillStructureButNotDisabledSkillSupportFiles(t *testing.T) {
	store, sourceDir, seed, _, sourceID := sourceSyncFixture(t)
	current := fixtureGit(t, sourceDir, "rev-parse", "HEAD")
	advanceSourceSyncSeed(t, seed, "skills/demo/guide.md", "disabled skill support file\n")
	t.Setenv("HAWS_SYNC_CANDIDATE_REF", "refs/haws-sync/test-source-disabled")
	t.Setenv("HAWS_SYNC_PREFETCH_DONE", "")
	got := SyncSource(context.Background(), store, sourceID, []string{"demo"}, 10*time.Second)
	if got.Status != "up-to-date" || got.Revision != current || got.Detail != "active skills unchanged" {
		t.Fatalf("disabled support-file SyncSource() = %#v", got)
	}
	if fixtureGit(t, sourceDir, "rev-parse", "HEAD") != current {
		t.Fatal("disabled skill support-file change advanced the source")
	}

	advanceSourceSyncSeed(t, seed, "skills/new/SKILL.md", "---\nname: new\ndescription: new skill\n---\n\nNew.\n")
	t.Setenv("HAWS_SYNC_CANDIDATE_REF", "refs/haws-sync/test-source-new-skill")
	got = SyncSource(context.Background(), store, sourceID, nil, 10*time.Second)
	if got.Status != "updated" || got.Revision == current {
		t.Fatalf("new skill structure SyncSource() = %#v", got)
	}
	if fixtureGit(t, sourceDir, "rev-parse", "HEAD") != got.Revision {
		t.Fatal("new eligible skill structure did not advance the source")
	}
}

func TestSyncSourceBlocksDirtySourceAndSkipsWhenNoSkillIsActive(t *testing.T) {
	store, sourceDir, _, _, sourceID := sourceSyncFixture(t)
	fixtureFile(t, filepath.Join(sourceDir, "local.txt"), "preserve me\n")
	if got := SyncSource(context.Background(), store, sourceID, nil, time.Second); got.Status != "blocked" || !strings.Contains(got.Detail, "local.txt") {
		t.Fatalf("dirty SyncSource() = %#v", got)
	}

	if err := os.Remove(filepath.Join(sourceDir, "local.txt")); err != nil {
		t.Fatal(err)
	}
	if got := SyncSource(context.Background(), store, sourceID, []string{"demo", "other"}, time.Second); got.Status != "skipped" || got.Detail != "source has no active skills" {
		t.Fatalf("inactive SyncSource() = %#v", got)
	}
}

func TestSyncSourceRejectsCandidateWithoutAnyEligibleSkill(t *testing.T) {
	store, sourceDir, seed, _, sourceID := sourceSyncFixture(t)
	fixtureGit(t, seed, "rm", "skills/demo/SKILL.md", "skills/other/SKILL.md")
	fixtureGit(t, seed, "commit", "-m", "remove all skills")
	fixtureGit(t, seed, "push", "origin", "main")
	want := fixtureGit(t, seed, "rev-parse", "HEAD")
	t.Setenv("HAWS_SYNC_CANDIDATE_REF", "refs/haws-sync/test-source-invalid")
	t.Setenv("HAWS_SYNC_PREFETCH_DONE", "")

	got := SyncSource(context.Background(), store, sourceID, nil, 10*time.Second)
	if got.Status != "failed" || got.Revision != want || got.Detail != "candidate validation failed" {
		t.Fatalf("invalid candidate SyncSource() = %#v", got)
	}
	if fixtureGit(t, sourceDir, "rev-parse", "HEAD") == want {
		t.Fatal("invalid candidate changed source HEAD")
	}
	if refs := fixtureGit(t, sourceDir, "for-each-ref", "refs/haws-sync"); refs != "" {
		t.Fatalf("candidate ref was not cleaned: %s", refs)
	}
}

func fixtureGitOutput(t *testing.T, dir string, args ...string) (string, error) {
	t.Helper()
	cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
	output, err := cmd.CombinedOutput()
	return strings.TrimSpace(string(output)), err
}
