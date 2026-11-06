package settings

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

func registeredSourceFixture(t *testing.T, withSkill bool) (Store, string, string, string) {
	t.Helper()
	root := fixtureRepo(t)
	seed := fixtureRepo(t)
	if withSkill {
		fixtureFile(t, filepath.Join(seed, "skills", "demo", "SKILL.md"), "---\nname: demo\ndescription: fixture\n---\n\nSkill.\n")
	} else {
		fixtureFile(t, filepath.Join(seed, "README.md"), "not a skill\n")
	}
	fixtureGit(t, seed, "add", ".")
	fixtureGit(t, seed, "commit", "-m", "source baseline")
	remote := filepath.Join(fixtureDir(t), "device-source.git")
	if output, err := exec.Command("git", "init", "--bare", remote).CombinedOutput(); err != nil {
		t.Fatalf("initialize device source remote: %v: %s", err, output)
	}
	fixtureGit(t, seed, "remote", "add", "origin", remote)
	fixtureGit(t, seed, "push", "-u", "origin", "main")
	if err := exec.Command("git", "--git-dir", remote, "symbolic-ref", "HEAD", "refs/heads/main").Run(); err != nil {
		t.Fatal(err)
	}
	t.Setenv("HAWS_TEST_ALLOW_LOCAL_SOURCES", "1")
	store := NewStore(root)
	if err := os.MkdirAll(filepath.Join(store.Dir, "skill-sources"), 0700); err != nil {
		t.Fatal(err)
	}
	const sourcePath = "skills/packs/demo"
	if err := os.WriteFile(filepath.Join(store.Dir, "skill-sources", "registry.tsv"), []byte("demo\t"+sourcePath+"\t"+remote+"\n"), 0600); err != nil {
		t.Fatal(err)
	}
	return store, "device-demo::" + sourcePath, remote, filepath.Join(store.Dir, "skill-sources", filepath.FromSlash(sourcePath))
}

func TestPrepareRegisteredSourceMaterializesAndReusesDeviceCheckout(t *testing.T) {
	store, sourceID, remote, checkout := registeredSourceFixture(t, true)

	handled, err := PrepareRegisteredSource(context.Background(), store, sourceID)
	if err != nil || !handled {
		t.Fatalf("PrepareRegisteredSource() = %v, %v; want handled success", handled, err)
	}
	if got := fixtureGit(t, checkout, "remote", "get-url", "origin"); got != remote {
		t.Fatalf("origin = %q, want %q", got, remote)
	}
	if _, err := os.Stat(filepath.Join(checkout, "skills", "demo", "SKILL.md")); err != nil {
		t.Fatalf("materialized source is missing its skill: %v", err)
	}
	if !independentBrain(context.Background(), checkout) {
		t.Fatal("materialized source is not an independent Git checkout")
	}

	head := fixtureGit(t, checkout, "rev-parse", "HEAD")
	handled, err = PrepareRegisteredSource(context.Background(), store, sourceID)
	if err != nil || !handled || fixtureGit(t, checkout, "rev-parse", "HEAD") != head {
		t.Fatalf("repeat PrepareRegisteredSource() = %v, %v; checkout changed", handled, err)
	}
}

func TestPrepareRegisteredSourcePreservesInvalidOrConflictingCheckout(t *testing.T) {
	store, sourceID, remote, checkout := registeredSourceFixture(t, true)
	wrong := fixtureRepo(t)
	fixtureFile(t, filepath.Join(wrong, "SKILL.md"), "wrong origin\n")
	fixtureGit(t, wrong, "add", ".")
	fixtureGit(t, wrong, "commit", "-m", "wrong source")
	if err := os.MkdirAll(filepath.Dir(checkout), 0700); err != nil {
		t.Fatal(err)
	}
	if output, err := exec.Command("git", "clone", "--quiet", wrong, checkout).CombinedOutput(); err != nil {
		t.Fatalf("create conflicting checkout: %v: %s", err, output)
	}
	before := fixtureGit(t, checkout, "rev-parse", "HEAD")

	handled, err := PrepareRegisteredSource(context.Background(), store, sourceID)
	if err == nil || !handled {
		t.Fatalf("PrepareRegisteredSource() = %v, %v; want handled conflict", handled, err)
	}
	if got := fixtureGit(t, checkout, "rev-parse", "HEAD"); got != before {
		t.Fatalf("conflicting checkout changed from %s to %s", before, got)
	}
	if got := fixtureGit(t, checkout, "remote", "get-url", "origin"); got == remote {
		t.Fatal("conflicting origin was silently replaced")
	}
}

func TestPrepareRegisteredSourceRejectsSkilllessCloneAndIgnoresSubmodules(t *testing.T) {
	store, sourceID, _, checkout := registeredSourceFixture(t, false)
	handled, err := PrepareRegisteredSource(context.Background(), store, sourceID)
	if err == nil || !handled {
		t.Fatalf("skillless PrepareRegisteredSource() = %v, %v; want handled error", handled, err)
	}
	if _, statErr := os.Lstat(checkout); !os.IsNotExist(statErr) {
		t.Fatalf("invalid clone was left at destination: %v", statErr)
	}

	handled, err = PrepareRegisteredSource(context.Background(), store, "demo::skills/packs/demo")
	if err != nil || handled {
		t.Fatalf("submodule PrepareRegisteredSource() = %v, %v; want legacy fallback", handled, err)
	}
}

func TestPrepareRegisteredSourceRejectsAmbiguousSubmoduleIdentity(t *testing.T) {
	store, sourceID, _, checkout := registeredSourceFixture(t, true)
	fixtureFile(t, filepath.Join(store.Root, ".gitmodules"), "[submodule \"device-demo\"]\n\tpath = skills/packs/demo\n\turl = https://github.com/example/other.git\n")
	handled, err := PrepareRegisteredSource(context.Background(), store, sourceID)
	if err == nil || !handled {
		t.Fatalf("ambiguous PrepareRegisteredSource() = %v, %v; want handled error", handled, err)
	}
	if _, statErr := os.Lstat(checkout); !os.IsNotExist(statErr) {
		t.Fatalf("ambiguous device source created a checkout: %v", statErr)
	}
}
