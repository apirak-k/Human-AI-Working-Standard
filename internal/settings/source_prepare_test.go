package settings

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
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

func trackedGitlinkSourceFixture(t *testing.T) (Store, string, string, string, string) {
	t.Helper()
	root := fixtureRepo(t)
	seed := fixtureRepo(t)
	const sourcePath = "skills/packs/demo"
	fixtureFile(t, filepath.Join(seed, "SKILL.md"), "---\nname: demo\ndescription: fixture\n---\n\nSkill.\n")
	fixtureGit(t, seed, "add", ".")
	fixtureGit(t, seed, "commit", "-m", "source baseline")
	revision := fixtureGit(t, seed, "rev-parse", "HEAD")
	remote := filepath.Join(fixtureDir(t), "demo.git")
	fixtureGit(t, filepath.Dir(remote), "init", "--bare", remote)
	fixtureGit(t, seed, "remote", "add", "origin", remote)
	fixtureGit(t, seed, "push", "-u", "origin", "main")
	fixtureGit(t, remote, "symbolic-ref", "HEAD", "refs/heads/main")

	fixtureFile(t, filepath.Join(root, ".gitmodules"), "[submodule \"demo\"]\n\tpath = "+sourcePath+"\n\turl = "+remote+"\n")
	t.Setenv("GIT_CONFIG_COUNT", "1")
	t.Setenv("GIT_CONFIG_KEY_0", "protocol.file.allow")
	t.Setenv("GIT_CONFIG_VALUE_0", "always")
	fixtureGit(t, root, "add", ".gitmodules")
	fixtureGit(t, root, "update-index", "--add", "--cacheinfo", "160000,"+revision+","+sourcePath)
	fixtureGit(t, root, "commit", "-m", "register source gitlink")
	t.Setenv("HAWS_REPO_DIR", root)
	t.Setenv("HAWS_STATE_DIR", "")
	t.Setenv("HAWS_TEST_ALLOW_LOCAL_SOURCES", "1")
	return NewStore(root), "demo::" + sourcePath, remote, sourcePath, revision
}

func TestPrepareGitlinkSourceMaterializesAndReusesDeviceCheckout(t *testing.T) {
	store, sourceID, remote, sourcePath, revision := trackedGitlinkSourceFixture(t)
	checkout := filepath.Join(store.Dir, "skill-sources", filepath.FromSlash(sourcePath))

	handled, err := PrepareRegisteredSource(context.Background(), store, sourceID)
	if err != nil || !handled {
		t.Fatalf("PrepareRegisteredSource() = %v, %v; want native Gitlink preparation", handled, err)
	}
	if got := fixtureGit(t, checkout, "rev-parse", "HEAD"); got != revision {
		t.Fatalf("device source revision = %s, want pinned Gitlink revision %s", got, revision)
	}
	if got := fixtureGit(t, checkout, "remote", "get-url", "origin"); got != remote {
		t.Fatalf("device source origin = %q, want %q", got, remote)
	}
	if !independentBrain(context.Background(), checkout) {
		t.Fatal("Gitlink mirror is not an independent checkout")
	}

	handled, err = PrepareRegisteredSource(context.Background(), store, sourceID)
	if err != nil || !handled || fixtureGit(t, checkout, "rev-parse", "HEAD") != revision {
		t.Fatalf("repeat PrepareRegisteredSource() = %v, %v; checkout changed", handled, err)
	}
}

func TestPreparePackagedGitlinkUsesPinnedRevisionAndPreservesUnownedCheckout(t *testing.T) {
	root := fixtureDir(t)
	seed := fixtureRepo(t)
	const sourcePath = "skills/packs/demo"
	fixtureFile(t, filepath.Join(seed, "SKILL.md"), "---\nname: demo\ndescription: pinned\n---\n\nPinned skill.\n")
	fixtureGit(t, seed, "add", ".")
	fixtureGit(t, seed, "commit", "-m", "pinned source")
	pinned := fixtureGit(t, seed, "rev-parse", "HEAD")
	remote := filepath.Join(fixtureDir(t), "demo.git")
	fixtureGit(t, filepath.Dir(remote), "init", "--bare", remote)
	fixtureGit(t, seed, "remote", "add", "origin", remote)
	fixtureGit(t, seed, "push", "-u", "origin", "main")
	fixtureGit(t, remote, "symbolic-ref", "HEAD", "refs/heads/main")

	fixtureFile(t, filepath.Join(root, ".gitmodules"), "[submodule \"demo\"]\n\tpath = "+sourcePath+"\n\turl = "+remote+"\n")
	fixtureFile(t, filepath.Join(root, "source-revisions.tsv"), sourcePath+"\t"+pinned+"\n")
	t.Setenv("HAWS_REPO_DIR", root)
	t.Setenv("HAWS_STATE_DIR", "")
	t.Setenv("HAWS_TEST_ALLOW_LOCAL_SOURCES", "1")
	store := NewStore(root)
	checkout := filepath.Join(store.Dir, "skill-sources", filepath.FromSlash(sourcePath))
	marker := checkout + ".haws-owned"

	if err := os.MkdirAll(checkout, 0700); err != nil {
		t.Fatal(err)
	}
	userFile := filepath.Join(checkout, "private.txt")
	if err := os.WriteFile(userFile, []byte("keep"), 0600); err != nil {
		t.Fatal(err)
	}
	if handled, err := PrepareRegisteredSource(context.Background(), store, "demo::"+sourcePath); err == nil || !handled {
		t.Fatalf("unowned checkout PrepareRegisteredSource() = %v, %v; want handled conflict", handled, err)
	}
	if got, err := os.ReadFile(userFile); err != nil || string(got) != "keep" {
		t.Fatalf("unowned checkout changed: %q, %v", got, err)
	}
	if err := os.RemoveAll(checkout); err != nil {
		t.Fatal(err)
	}

	fixtureFile(t, filepath.Join(seed, "new.txt"), "upstream moved after packaging\n")
	fixtureGit(t, seed, "add", "new.txt")
	fixtureGit(t, seed, "commit", "-m", "move remote after package pin")
	fixtureGit(t, seed, "push", "origin", "main")
	latest := fixtureGit(t, seed, "rev-parse", "HEAD")

	handled, err := PrepareRegisteredSource(context.Background(), store, "demo::"+sourcePath)
	if err != nil || !handled {
		t.Fatalf("packaged PrepareRegisteredSource() = %v, %v; want native Gitlink preparation", handled, err)
	}
	if got := fixtureGit(t, checkout, "rev-parse", "HEAD"); got != pinned {
		t.Fatalf("packaged source revision = %s, want pinned revision %s (remote is %s)", got, pinned, latest)
	}
	if got, err := os.ReadFile(filepath.Join(checkout, "SKILL.md")); err != nil || !strings.Contains(string(got), "Pinned skill") {
		t.Fatalf("pinned skill = %q, %v", got, err)
	}
	if got, err := os.ReadFile(marker); err != nil || string(got) != remote+"\n" {
		t.Fatalf("ownership marker = %q, %v; want registered source URL", got, err)
	}
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

func TestPrepareRegisteredSourceRejectsUnsafeGitEnvironment(t *testing.T) {
	store, sourceID, _, _ := registeredSourceFixture(t, true)
	t.Setenv("GIT_DIR", t.TempDir())
	handled, err := PrepareRegisteredSource(context.Background(), store, sourceID)
	if err == nil || handled {
		t.Fatalf("PrepareRegisteredSource() = %v, %v; want unsafe Git environment rejection", handled, err)
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

func TestPrepareRegisteredSourceRejectsSkilllessCloneAndLeavesUnknownSourceUnhandled(t *testing.T) {
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
