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

func hawsSyncFixture(t *testing.T) (root, seed, remote string) {
	t.Helper()
	t.Setenv("HAWS_SYNC_CANDIDATE_REF", "")
	t.Setenv("HAWS_SYNC_PREFETCH_DONE", "")
	root = fixtureRepo(t)
	fixtureFile(t, filepath.Join(root, "haws.sh"), "#!/usr/bin/env bash\n")
	fixtureGit(t, root, "add", "haws.sh")
	fixtureGit(t, root, "commit", "-m", "baseline")
	remote = filepath.Join(fixtureDir(t), "haws.git")
	if output, err := exec.Command("git", "init", "--bare", remote).CombinedOutput(); err != nil {
		t.Fatalf("git init remote: %v: %s", err, output)
	}
	fixtureGit(t, root, "remote", "add", "origin", remote)
	fixtureGit(t, root, "push", "-u", "origin", "main")
	if err := exec.Command("git", "--git-dir", remote, "symbolic-ref", "HEAD", "refs/heads/main").Run(); err != nil {
		t.Fatal(err)
	}
	seed = filepath.Join(fixtureDir(t), "seed")
	if output, err := exec.Command("git", "clone", remote, seed).CombinedOutput(); err != nil {
		t.Fatalf("git clone seed: %v: %s", err, output)
	}
	fixtureGit(t, seed, "config", "user.email", "test@example.invalid")
	fixtureGit(t, seed, "config", "user.name", "Test")
	return root, seed, remote
}

func advanceHawsSyncSeed(t *testing.T, seed, name, body string) string {
	t.Helper()
	fixtureFile(t, filepath.Join(seed, name), body)
	fixtureGit(t, seed, "add", name)
	fixtureGit(t, seed, "commit", "-m", "advance remote")
	fixtureGit(t, seed, "push", "origin", "main")
	return fixtureGit(t, seed, "rev-parse", "HEAD")
}

func TestSyncHawsRootFastForwardsAndLeavesRemoteUnchanged(t *testing.T) {
	root, seed, remote := hawsSyncFixture(t)
	want := advanceHawsSyncSeed(t, seed, "release.txt", "release\n")
	got := SyncHawsRoot(context.Background(), root, 10*time.Second)
	if got.Status != "updated" || got.Revision != want || got.Detail != "final HEAD equals candidate" {
		t.Fatalf("SyncHawsRoot() = %#v", got)
	}
	if fixtureGit(t, root, "rev-parse", "HEAD") != want || fixtureGit(t, root, "symbolic-ref", "--short", "HEAD") != "main" {
		t.Fatal("HAWS update did not fast-forward the current branch")
	}
	if fixtureGit(t, remote, "rev-parse", "refs/heads/main") != want {
		t.Fatal("HAWS sync changed the remote")
	}
	if refs := fixtureGit(t, root, "for-each-ref", "refs/haws-sync"); refs != "" {
		t.Fatalf("candidate refs were not cleaned: %s", refs)
	}
	if got := SyncHawsRoot(context.Background(), root, time.Second); got.Status != "up-to-date" || got.Revision != want {
		t.Fatalf("repeat SyncHawsRoot() = %#v", got)
	}
}

func TestSyncHawsRootBlocksDirtyCheckoutButAllowsDeviceLocalSkills(t *testing.T) {
	root, seed, _ := hawsSyncFixture(t)
	advanceHawsSyncSeed(t, seed, "release.txt", "release\n")
	fixtureFile(t, filepath.Join(root, "skills", "custom", "mine", "SKILL.md"), "private skill\n")
	if got := SyncHawsRoot(context.Background(), root, time.Second); got.Status != "updated" {
		t.Fatalf("SyncHawsRoot() with device-local skill = %#v", got)
	}
	before := fixtureGit(t, root, "rev-parse", "HEAD")
	fixtureFile(t, filepath.Join(root, "user-data.txt"), "keep me\n")
	got := SyncHawsRoot(context.Background(), root, time.Second)
	if got.Status != "blocked" || !strings.Contains(got.Detail, "user-data.txt") {
		t.Fatalf("dirty SyncHawsRoot() = %#v", got)
	}
	if fixtureGit(t, root, "rev-parse", "HEAD") != before {
		t.Fatal("dirty HAWS checkout advanced")
	}
	if body, err := os.ReadFile(filepath.Join(root, "user-data.txt")); err != nil || string(body) != "keep me\n" {
		t.Fatalf("user data = %q, %v", body, err)
	}
}

func TestSyncHawsRootIgnoresWorktreeDriftInTrackedGitlinks(t *testing.T) {
	root, _, _ := hawsSyncFixture(t)
	submodule := filepath.Join(root, "skills", "packs", "fixture")
	if err := os.MkdirAll(filepath.Dir(submodule), 0700); err != nil {
		t.Fatal(err)
	}
	if output, err := exec.Command("git", "init", "-b", "main", submodule).CombinedOutput(); err != nil {
		t.Fatalf("git init submodule: %v: %s", err, output)
	}
	fixtureGit(t, submodule, "config", "user.email", "test@example.invalid")
	fixtureGit(t, submodule, "config", "user.name", "Test")
	fixtureFile(t, filepath.Join(submodule, "skill.txt"), "baseline\n")
	fixtureGit(t, submodule, "add", "skill.txt")
	fixtureGit(t, submodule, "commit", "-m", "baseline")
	submoduleHead := fixtureGit(t, submodule, "rev-parse", "HEAD")
	fixtureGit(t, root, "update-index", "--add", "--cacheinfo", "160000,"+submoduleHead+",skills/packs/fixture")
	fixtureGit(t, root, "commit", "-m", "add tracked source")
	fixtureFile(t, filepath.Join(submodule, "skill.txt"), "local source worktree change\n")

	status, err := exec.Command("git", "-C", root, "status", "--porcelain=v1", "--untracked-files=all", "--ignore-submodules=none", "-z").Output()
	if err != nil || !strings.Contains(string(status), "skills/packs/fixture") {
		t.Fatalf("fixture did not create gitlink worktree drift: %q, %v", status, err)
	}
	if got := SyncHawsRoot(context.Background(), root, time.Second); got.Status != "up-to-date" {
		t.Fatalf("SyncHawsRoot() with tracked gitlink drift = %#v", got)
	}
}

func TestSyncHawsRootKeepsLocalAheadAndRejectsDetachedOrInvalidCandidate(t *testing.T) {
	root, seed, _ := hawsSyncFixture(t)
	base := fixtureGit(t, root, "rev-parse", "HEAD")
	fixtureFile(t, filepath.Join(root, "local.txt"), "local\n")
	fixtureGit(t, root, "add", "local.txt")
	fixtureGit(t, root, "commit", "-m", "local ahead")
	localHead := fixtureGit(t, root, "rev-parse", "HEAD")
	if got := SyncHawsRoot(context.Background(), root, time.Second); got.Status != "up-to-date" || got.Revision != localHead || !strings.Contains(got.Detail, "local HEAD is ahead") {
		t.Fatalf("local-ahead SyncHawsRoot() = %#v", got)
	}
	if fixtureGit(t, root, "rev-parse", "HEAD") != localHead || base == localHead {
		t.Fatal("local-ahead HAWS checkout changed")
	}

	advanceHawsSyncSeed(t, seed, "release.txt", "divergent remote release\n")
	if got := SyncHawsRoot(context.Background(), root, time.Second); got.Status != "failed" || got.Detail != "candidate activation failed" {
		t.Fatalf("diverged SyncHawsRoot() = %#v", got)
	}
	if fixtureGit(t, root, "rev-parse", "HEAD") != localHead {
		t.Fatal("diverged candidate changed HAWS checkout")
	}

	fixtureGit(t, seed, "rm", "haws.sh")
	fixtureGit(t, seed, "commit", "-m", "invalid candidate")
	fixtureGit(t, seed, "push", "origin", "main")
	if got := SyncHawsRoot(context.Background(), root, time.Second); got.Status != "failed" || got.Detail != "candidate validation failed" {
		t.Fatalf("invalid candidate SyncHawsRoot() = %#v", got)
	}
	if fixtureGit(t, root, "rev-parse", "HEAD") != localHead {
		t.Fatal("invalid candidate changed HAWS checkout")
	}
}

func TestSyncHawsRootReportsDetachedAndUntrackedBranches(t *testing.T) {
	root, _, _ := hawsSyncFixture(t)
	fixtureGit(t, root, "checkout", "--detach")
	if got := SyncHawsRoot(context.Background(), root, time.Second); got.Status != "blocked" || got.Detail != "HAWS checkout is detached" {
		t.Fatalf("detached SyncHawsRoot() = %#v", got)
	}
	fixtureGit(t, root, "checkout", "-b", "without-upstream")
	if got := SyncHawsRoot(context.Background(), root, time.Second); got.Status != "failed" || got.Detail != "HAWS branch has no tracked remote" {
		t.Fatalf("untracked branch SyncHawsRoot() = %#v", got)
	}
}

func TestSyncHawsRootHonorsCancellationBeforeGitMutation(t *testing.T) {
	root, _, _ := hawsSyncFixture(t)
	before := fixtureGit(t, root, "rev-parse", "HEAD")
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if got := SyncHawsRoot(ctx, root, time.Second); got.Status != "failed" || got.Detail != "HAWS synchronization was canceled" {
		t.Fatalf("cancelled SyncHawsRoot() = %#v", got)
	}
	if fixtureGit(t, root, "rev-parse", "HEAD") != before {
		t.Fatal("cancelled HAWS sync changed HEAD")
	}
}
