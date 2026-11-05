package settings

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestRepositoryPreflightRejectsMalformedAndConflictingSources(t *testing.T) {
	s := Store{Root: fixtureDir(t), Dir: fixtureDir(t)}
	ctx := context.Background()
	for _, url := range []string{"http://github.com/a/b", "https://github.com/a/..", "https://github.com/../b", "https://github.com/a/b?x", "https://github.com/a/b\n", "-upload-pack=bad"} {
		if err := s.PreflightRepositories(ctx, []RepositoryAction{{Kind: "add-source", URL: url, Path: "skills/packs/b"}}); err == nil {
			t.Errorf("accepted %q", url)
		}
	}
	for _, path := range []string{"../outside", "skills/packs/../bad", "skills/packs/./bad", "skills/packs/x/../../bad", "skills/packs/b\tbad"} {
		if err := s.PreflightRepositories(ctx, []RepositoryAction{{Kind: "add-source", URL: "https://github.com/a/b", Path: path}}); err == nil {
			t.Errorf("accepted path %q", path)
		}
	}
	actions := []RepositoryAction{{Kind: "add-source", URL: "https://github.com/a/b.git", Path: "skills/packs/b"}, {Kind: "add-source", URL: "https://github.com/a/b", Path: "skills/packs/other"}}
	if err := s.PreflightRepositories(ctx, actions); err == nil {
		t.Fatal("accepted duplicate URL identity")
	}
	actions[1].URL = "https://github.com/other/b"
	actions[1].Path = actions[0].Path
	if err := s.PreflightRepositories(ctx, actions); err == nil {
		t.Fatal("accepted duplicate path")
	}
}

func TestRepositoryRemovalProtectsDirtyAndUnownedCheckouts(t *testing.T) {
	ctx := context.Background()
	s := Store{Root: fixtureDir(t), Dir: fixtureDir(t)}
	path := "skills/packs/demo"
	checkout := filepath.Join(s.Dir, "skill-sources", filepath.FromSlash(path))
	if err := os.MkdirAll(checkout, 0700); err != nil {
		t.Fatal(err)
	}
	fixtureGit(t, checkout, "init")
	fixtureGit(t, checkout, "remote", "add", "origin", "https://github.com/a/demo")
	registry := filepath.Join(s.Dir, "skill-sources", "registry.tsv")
	fixtureFile(t, registry, "demo\t"+path+"\thttps://github.com/a/demo\n")
	action := RepositoryAction{Kind: "remove-source", ID: "device-demo::" + path, Path: path}
	fixtureFile(t, filepath.Join(checkout, "notes"), "keep me")
	if err := s.ApplyRepository(ctx, action); err == nil {
		t.Fatal("removed dirty checkout")
	}
	if _, err := os.Stat(filepath.Join(checkout, "notes")); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(filepath.Join(checkout, "notes")); err != nil {
		t.Fatal(err)
	}
	fixtureGit(t, checkout, "remote", "set-url", "origin", "https://github.com/other/demo")
	if err := s.ApplyRepository(ctx, action); err == nil {
		t.Fatal("removed unowned checkout")
	}
	fixtureGit(t, checkout, "remote", "set-url", "origin", "https://github.com/a/demo")
	if err := s.ApplyRepository(ctx, action); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(checkout); !os.IsNotExist(err) {
		t.Fatal("clean checkout remains")
	}
	body, err := os.ReadFile(registry)
	if err != nil || len(body) != 0 {
		t.Fatalf("registry %q %v", body, err)
	}
}

func TestRepositoryCloneValidatesSkillsBeforeRegistration(t *testing.T) {
	t.Setenv("HAWS_TEST_ALLOW_LOCAL_SOURCES", "1")
	ctx := context.Background()
	remote := fixtureRepo(t)
	fixtureFile(t, filepath.Join(remote, "SKILL.md"), "---\nname: useful\n---\nUseful skill\n")
	fixtureGit(t, remote, "add", ".")
	fixtureGit(t, remote, "commit", "-m", "skill")
	s := Store{Root: fixtureDir(t), Dir: fixtureDir(t)}
	action := RepositoryAction{Kind: "add-source", URL: remote, Path: "skills/packs/useful"}
	if err := s.ApplyRepository(ctx, action); err != nil {
		t.Fatal(err)
	}
	sources, err := s.Sources(ctx)
	if err != nil || len(sources) != 1 {
		t.Fatalf("sources %v, %v", sources, err)
	}
	if err := s.PreflightRepositories(ctx, []RepositoryAction{action}); err == nil {
		t.Fatal("duplicate clone accepted")
	}
	checkout := sources[0].Dir
	fixtureFile(t, filepath.Join(checkout, ".gitignore"), "ignored\n")
	fixtureGit(t, checkout, "config", "user.email", "test@example.invalid")
	fixtureGit(t, checkout, "config", "user.name", "Test")
	fixtureGit(t, checkout, "add", ".gitignore")
	fixtureGit(t, checkout, "commit", "-m", "ignore")
	fixtureFile(t, filepath.Join(checkout, "ignored"), "private")
	if err := s.ApplyRepository(ctx, RepositoryAction{Kind: "remove-source", ID: sources[0].ID, Path: sources[0].Path}); err == nil {
		t.Fatal("ignored file was discarded")
	}
	empty := fixtureRepo(t)
	fixtureFile(t, filepath.Join(empty, "README.md"), "no skills")
	fixtureGit(t, empty, "add", ".")
	fixtureGit(t, empty, "commit", "-m", "empty")
	before, _ := os.ReadFile(filepath.Join(s.Dir, "skill-sources", "registry.tsv"))
	if err := s.ApplyRepository(ctx, RepositoryAction{Kind: "add-source", URL: empty, Path: "skills/packs/empty"}); err == nil {
		t.Fatal("skill-less clone accepted")
	}
	after, _ := os.ReadFile(filepath.Join(s.Dir, "skill-sources", "registry.tsv"))
	if string(before) != string(after) {
		t.Fatal("invalid clone changed registry")
	}
	if _, err := os.Lstat(filepath.Join(s.Dir, "skill-sources", "skills", "packs", "empty")); !os.IsNotExist(err) {
		t.Fatal("invalid clone activated")
	}
}

func TestTrackedRemovalChecksOwnershipAndPreservesCache(t *testing.T) {
	ctx := context.Background()
	remote := fixtureRepo(t)
	fixtureFile(t, filepath.Join(remote, "SKILL.md"), "name: example\n")
	fixtureGit(t, remote, "add", ".")
	fixtureGit(t, remote, "commit", "-m", "skill")
	root := fixtureRepo(t)
	path := "skills/packs/example"
	fixtureGit(t, root, "-c", "protocol.file.allow=always", "submodule", "add", remote, path)
	fixtureGit(t, root, "commit", "-m", "source")
	s := Store{Root: root, Dir: fixtureDir(t)}
	sources, err := s.Sources(ctx)
	if err != nil || len(sources) != 1 {
		t.Fatalf("sources %v %v", sources, err)
	}
	action := RepositoryAction{Kind: "remove-source", ID: sources[0].ID, Path: path}
	checkout := filepath.Join(root, filepath.FromSlash(path))
	gitFile := filepath.Join(checkout, ".git")
	original, err := os.ReadFile(gitFile)
	if err != nil {
		t.Fatal(err)
	}
	other := fixtureRepo(t)
	fixtureFile(t, gitFile, "gitdir: "+filepath.Join(other, ".git")+"\n")
	if err := s.PreflightRepositories(ctx, []RepositoryAction{action}); err == nil {
		t.Fatal("unowned replacement accepted")
	}
	fixtureFile(t, gitFile, string(original))
	fixtureFile(t, filepath.Join(checkout, "private"), "preserve")
	if err := s.ApplyRepository(ctx, action); err == nil {
		t.Fatal("dirty submodule removed")
	}
	if err := os.Remove(filepath.Join(checkout, "private")); err != nil {
		t.Fatal(err)
	}
	cache := fixtureGit(t, root, "rev-parse", "--path-format=absolute", "--git-path", "modules/"+path)
	if err := s.ApplyRepository(ctx, action); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(cache); err != nil {
		t.Fatal("owned cache was discarded:", err)
	}
	if got := fixtureGit(t, root, "ls-files", "--stage", "--", path); got != "" {
		t.Fatalf("gitlink remains: %q", got)
	}
}

func TestRepositoryPreflightRejectsSymlinkParents(t *testing.T) {
	s := Store{Root: fixtureDir(t), Dir: fixtureDir(t)}
	if err := os.Symlink(t.TempDir(), filepath.Join(s.Root, "skills")); err != nil {
		t.Skip(err)
	}
	if err := s.PreflightRepositories(context.Background(), []RepositoryAction{{Kind: "add-source", URL: "https://github.com/a/b", Path: "skills/packs/b"}}); err == nil {
		t.Fatal("symlink parent accepted")
	}
}

func TestRejectedRepositoryPreflightPreservesIndex(t *testing.T) {
	s := Store{Root: fixtureDir(t), Dir: fixtureDir(t)}
	path := "skills/packs/readonly"
	checkout := filepath.Join(s.Dir, "skill-sources", filepath.FromSlash(path))
	if err := os.MkdirAll(checkout, 0700); err != nil {
		t.Fatal(err)
	}
	fixtureGit(t, checkout, "init")
	fixtureGit(t, checkout, "config", "user.name", "Test")
	fixtureGit(t, checkout, "config", "user.email", "test@example.invalid")
	fixtureGit(t, checkout, "remote", "add", "origin", "https://github.com/a/readonly")
	tracked := filepath.Join(checkout, "tracked")
	fixtureFile(t, tracked, "unchanged content")
	fixtureGit(t, checkout, "add", "tracked")
	fixtureGit(t, checkout, "commit", "-m", "tracked file")
	indexPath := filepath.Join(checkout, ".git", "index")
	before, err := os.ReadFile(indexPath)
	if err != nil {
		t.Fatal(err)
	}
	// An unchanged tracked file with a new timestamp makes ordinary git status
	// refresh its cached stat information, even when removal is then rejected.
	future := time.Now().Add(time.Hour)
	if err := os.Chtimes(tracked, future, future); err != nil {
		t.Fatal(err)
	}
	fixtureFile(t, filepath.Join(checkout, "private"), "untracked notes")
	fixtureFile(t, filepath.Join(s.Dir, "skill-sources", "registry.tsv"), "readonly\t"+path+"\thttps://github.com/a/readonly\n")
	action := RepositoryAction{Kind: "remove-source", ID: "device-readonly::" + path, Path: path}
	if err := s.PreflightRepositories(context.Background(), []RepositoryAction{action}); err == nil {
		t.Fatal("dirty removal accepted")
	}
	after, err := os.ReadFile(indexPath)
	if err != nil {
		t.Fatal(err)
	}
	if string(before) != string(after) {
		t.Fatal("rejected preflight changed checkout index")
	}
}
