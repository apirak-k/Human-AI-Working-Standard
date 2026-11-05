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

func fixtureGit(t *testing.T, dir string, args ...string) string {
	t.Helper()
	cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
	cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0")
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("git %v: %v: %s", args, err, out)
	}
	return strings.TrimSpace(string(out))
}

func fixtureRepo(t *testing.T) string {
	t.Helper()
	dir := fixtureDir(t)
	fixtureGit(t, dir, "init", "-b", "main")
	fixtureGit(t, dir, "config", "user.email", "test@example.invalid")
	fixtureGit(t, dir, "config", "user.name", "Test")
	return dir
}

func fixtureDir(t *testing.T) string {
	t.Helper()
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return dir
}

func fixtureFile(t *testing.T, path, body string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0600); err != nil {
		t.Fatal(err)
	}
}

func TestBrainConnectPreservesLocalStateAndNeverPublishes(t *testing.T) {
	ctx := context.Background()
	remote := fixtureRepo(t)
	fixtureFile(t, filepath.Join(remote, "remote"), "remote history")
	fixtureGit(t, remote, "add", ".")
	fixtureGit(t, remote, "commit", "-m", "remote")
	brain := fixtureRepo(t)
	fixtureFile(t, filepath.Join(brain, "notes"), "original")
	fixtureFile(t, filepath.Join(brain, ".gitignore"), "ignored\n")
	fixtureGit(t, brain, "add", ".")
	fixtureGit(t, brain, "commit", "-m", "local")
	fixtureFile(t, filepath.Join(brain, "notes"), "staged")
	fixtureGit(t, brain, "add", "notes")
	fixtureFile(t, filepath.Join(brain, "notes"), "dirty")
	fixtureFile(t, filepath.Join(brain, "untracked"), "private")
	fixtureFile(t, filepath.Join(brain, "ignored"), "private ignored")
	before := fixtureGit(t, brain, "status", "--porcelain", "--ignored")
	head := fixtureGit(t, brain, "rev-parse", "HEAD")
	index, err := os.ReadFile(filepath.Join(brain, ".git", "index"))
	if err != nil {
		t.Fatal(err)
	}
	remoteHead := fixtureGit(t, remote, "rev-parse", "HEAD")
	if err := ConnectBrain(ctx, brain, remote); err != nil {
		t.Fatal(err)
	}
	if got, err := BrainRemote(ctx, brain); err != nil || got != remote {
		t.Fatalf("remote = %q, %v", got, err)
	}
	afterIndex, _ := os.ReadFile(filepath.Join(brain, ".git", "index"))
	if string(afterIndex) != string(index) {
		t.Fatal("index changed")
	}
	if fixtureGit(t, brain, "rev-parse", "HEAD") != head || fixtureGit(t, brain, "status", "--porcelain", "--ignored") != before {
		t.Fatal("local state changed")
	}
	if fixtureGit(t, remote, "rev-parse", "HEAD") != remoteHead {
		t.Fatal("remote changed")
	}
	if err := DisconnectBrain(ctx, brain, "wrong"); err == nil {
		t.Fatal("accepted stale remote confirmation")
	}
	if err := DisconnectBrain(ctx, brain, remote); err != nil {
		t.Fatal(err)
	}
	if got, err := BrainRemote(ctx, brain); err != nil || got != "" {
		t.Fatalf("disconnect remote = %q, %v", got, err)
	}
	if fixtureGit(t, brain, "status", "--porcelain", "--ignored") != before {
		t.Fatal("disconnect changed files")
	}
}

func TestBrainConnectFailureIsNoOp(t *testing.T) {
	brain := fixtureRepo(t)
	fixtureFile(t, filepath.Join(brain, "notes"), "private")
	fixtureGit(t, brain, "remote", "add", "origin", "/old/remote")
	config, _ := os.ReadFile(filepath.Join(brain, ".git", "config"))
	if err := ConnectBrain(context.Background(), brain, filepath.Join(fixtureDir(t), "missing")); err == nil {
		t.Fatal("missing remote accepted")
	}
	got, _ := os.ReadFile(filepath.Join(brain, ".git", "config"))
	if string(got) != string(config) {
		t.Fatal("failed connect mutated config")
	}
	absent := filepath.Join(fixtureDir(t), "brain")
	if err := ConnectBrain(context.Background(), absent, "invalid"); err == nil {
		t.Fatal("invalid remote accepted")
	}
	if _, err := os.Stat(absent); !os.IsNotExist(err) {
		t.Fatal("failed connect created brain")
	}
}

func TestBrainBoundaries(t *testing.T) {
	root := fixtureRepo(t)
	nested := filepath.Join(root, "secondbrain")
	fixtureFile(t, filepath.Join(nested, "notes"), "local")
	fixtureGit(t, root, "remote", "add", "origin", "/parent/remote")
	if got, err := BrainRemote(context.Background(), nested); err != nil || got != "" {
		t.Fatalf("nested remote = %q %v", got, err)
	}
	t.Setenv("GIT_DIR", "")
	if err := ConnectBrain(context.Background(), nested, root); err == nil {
		t.Fatal("Git override accepted")
	}
}

func TestBrainDirectoryAnchorsRelativeOverride(t *testing.T) {
	root := fixtureDir(t)
	t.Setenv("HAWS_SECOND_BRAIN_DIR", "private/brain")
	if got := BrainDirectory(root); got != filepath.Join(root, "private", "brain") {
		t.Fatalf("relative brain directory %q", got)
	}
}

func TestBrainConnectRejectsSymlinkAncestor(t *testing.T) {
	ctx := context.Background()
	root, target := fixtureDir(t), fixtureDir(t)
	link := filepath.Join(root, "linked")
	if err := os.Symlink(target, link); err != nil {
		t.Skip(err)
	}
	if err := ConnectBrain(ctx, filepath.Join(link, "brain"), fixtureRepo(t)); err == nil {
		t.Fatal("symlink ancestor accepted")
	}
	if _, err := os.Lstat(filepath.Join(target, "brain")); !os.IsNotExist(err) {
		t.Fatal("linked target changed")
	}
}

func TestBrainTransactionPreservesConcurrentChanges(t *testing.T) {
	brain := fixtureRepo(t)
	notes := filepath.Join(brain, "notes")
	fixtureFile(t, notes, "original")
	err := brainTransaction(context.Background(), brain, func(candidate string) error {
		fixtureFile(t, filepath.Join(candidate, "notes"), "candidate")
		fixtureFile(t, notes, "concurrent user edit")
		return nil
	})
	if err == nil {
		t.Fatal("concurrent edit overwritten")
	}
	body, _ := os.ReadFile(notes)
	if string(body) != "concurrent user edit" {
		t.Fatal("user edit lost")
	}
}

func TestBrainConnectInitializesIndependentCheckoutAndRejectsLinks(t *testing.T) {
	ctx := context.Background()
	remote := fixtureRepo(t)
	brain := filepath.Join(fixtureDir(t), "brain")
	fixtureFile(t, filepath.Join(brain, "notes"), "local-only")
	if err := ConnectBrain(ctx, brain, remote); err != nil {
		t.Fatal(err)
	}
	if !independentBrain(ctx, brain) {
		t.Fatal("brain was not initialized independently")
	}
	if fixtureGit(t, brain, "status", "--porcelain") != "?? notes" {
		t.Fatal("local notes were staged")
	}
	linked := filepath.Join(fixtureDir(t), "linked")
	if err := os.Symlink(brain, linked); err != nil {
		t.Skip(err)
	}
	if err := ConnectBrain(ctx, linked, remote); err == nil {
		t.Fatal("linked brain root accepted")
	}
	metadata := filepath.Join(brain, ".git", "config")
	config, err := os.ReadFile(metadata)
	if err != nil {
		t.Fatal(err)
	}
	external := filepath.Join(fixtureDir(t), "config")
	fixtureFile(t, external, string(config))
	if err := os.Remove(metadata); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(external, metadata); err != nil {
		t.Fatal(err)
	}
	if err := ConnectBrain(ctx, brain, remote); err == nil {
		t.Fatal("linked metadata accepted")
	}
	after, _ := os.ReadFile(external)
	if string(after) != string(config) {
		t.Fatal("external Git metadata changed")
	}
}

func TestSyncBrainFastForwardsOnlyCleanCheckout(t *testing.T) {
	seed, brain, remote := brainSyncFixture(t)
	before := fixtureGit(t, brain, "rev-parse", "HEAD")
	fixtureFile(t, filepath.Join(seed, "WORKFLOW.md"), "updated workflow\n")
	fixtureGit(t, seed, "add", "WORKFLOW.md")
	fixtureGit(t, seed, "commit", "-m", "update workflow")
	fixtureGit(t, seed, "push", "origin", "main")

	got := SyncBrain(context.Background(), brain, 10*time.Second)
	after := fixtureGit(t, brain, "rev-parse", "HEAD")
	if got.Status != "updated" || got.Revision != before+".."+after || got.Detail != "fast-forwarded from remote" {
		t.Fatalf("SyncBrain() = %#v", got)
	}
	body, err := os.ReadFile(filepath.Join(brain, "WORKFLOW.md"))
	if err != nil || strings.ReplaceAll(string(body), "\r\n", "\n") != "updated workflow\n" {
		t.Fatalf("fast-forwarded workflow = %q, %v", body, err)
	}
	if fixtureGit(t, remote, "rev-parse", "refs/heads/main") != after {
		t.Fatal("sync changed the remote")
	}
	if got := SyncBrain(context.Background(), brain, time.Second); got.Status != "up-to-date" || got.Revision != after {
		t.Fatalf("second SyncBrain() = %#v", got)
	}
}

func TestSyncBrainPreservesDirtyNotesAndRejectsConcurrentBrainOperation(t *testing.T) {
	seed, brain, _ := brainSyncFixture(t)
	fixtureFile(t, filepath.Join(seed, "WORKFLOW.md"), "upstream update\n")
	fixtureGit(t, seed, "add", "WORKFLOW.md")
	fixtureGit(t, seed, "commit", "-m", "update workflow")
	fixtureGit(t, seed, "push", "origin", "main")
	fixtureFile(t, filepath.Join(brain, "private-note.md"), "private\n")
	head := fixtureGit(t, brain, "rev-parse", "HEAD")
	if got := SyncBrain(context.Background(), brain, time.Second); got.Status != "failed" || got.Detail != "Second Brain has local changes" {
		t.Fatalf("dirty SyncBrain() = %#v", got)
	}
	if fixtureGit(t, brain, "rev-parse", "HEAD") != head {
		t.Fatal("dirty checkout advanced")
	}
	if body, err := os.ReadFile(filepath.Join(brain, "private-note.md")); err != nil || string(body) != "private\n" {
		t.Fatalf("private note = %q, %v", body, err)
	}
	if err := os.Remove(filepath.Join(brain, "private-note.md")); err != nil {
		t.Fatal(err)
	}
	lock := filepath.Join(filepath.Dir(brain), "."+filepath.Base(brain)+".haws-brain-lock")
	if err := os.Mkdir(lock, 0700); err != nil {
		t.Fatal(err)
	}
	if got := SyncBrain(context.Background(), brain, time.Second); got.Status != "failed" || got.Detail != "another Second Brain operation may be active" {
		t.Fatalf("locked SyncBrain() = %#v", got)
	}
}

func TestSyncBrainSkipsLocalOnlyAndUnavailableCheckouts(t *testing.T) {
	local := fixtureRepo(t)
	if got := SyncBrain(context.Background(), local, time.Second); got.Status != "skipped" || got.Detail != "Second Brain is local-only" {
		t.Fatalf("local-only SyncBrain() = %#v", got)
	}
	if got := SyncBrain(context.Background(), filepath.Join(t.TempDir(), "missing"), time.Second); got.Status != "failed" || got.Detail != "Second Brain checkout is unavailable" {
		t.Fatalf("missing SyncBrain() = %#v", got)
	}
}

func TestSyncBrainReleasesSharedLockAfterCancellation(t *testing.T) {
	_, brain, _ := brainSyncFixture(t)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if got := SyncBrain(ctx, brain, time.Second); got.Status != "failed" {
		t.Fatalf("cancelled SyncBrain() = %#v", got)
	}
	lock := filepath.Join(filepath.Dir(brain), "."+filepath.Base(brain)+".haws-brain-lock")
	if _, err := os.Lstat(lock); !os.IsNotExist(err) {
		t.Fatalf("Brain lock after cancellation: %v", err)
	}
}

func brainSyncFixture(t *testing.T) (seed, brain, remote string) {
	t.Helper()
	seed = fixtureRepo(t)
	fixtureFile(t, filepath.Join(seed, "WORKFLOW.md"), "baseline\n")
	fixtureGit(t, seed, "add", "WORKFLOW.md")
	fixtureGit(t, seed, "commit", "-m", "baseline")
	remote = filepath.Join(fixtureDir(t), "remote.git")
	if output, err := exec.Command("git", "init", "--bare", remote).CombinedOutput(); err != nil {
		t.Fatalf("git init remote: %v: %s", err, output)
	}
	if output, err := exec.Command("git", "--git-dir", remote, "symbolic-ref", "HEAD", "refs/heads/main").CombinedOutput(); err != nil {
		t.Fatalf("set remote HEAD: %v: %s", err, output)
	}
	fixtureGit(t, seed, "remote", "add", "origin", remote)
	fixtureGit(t, seed, "push", "-u", "origin", "main")
	brain = filepath.Join(fixtureDir(t), "secondbrain")
	if output, err := exec.Command("git", "clone", remote, brain).CombinedOutput(); err != nil {
		t.Fatalf("clone brain: %v: %s", err, output)
	}
	return seed, brain, remote
}
