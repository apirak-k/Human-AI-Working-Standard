package settings

import (
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

func TestApplyLockRejectsContentionAndReleasesOnError(t *testing.T) {
	s := testStore(t)
	failure := errors.New("apply failed")
	err := s.WithApplyLock(func() error {
		for _, name := range []string{"pid", "timestamp"} {
			body, err := os.ReadFile(s.Path("settings-apply.lock/" + name))
			if err != nil {
				t.Fatal(err)
			}
			value, err := strconv.ParseInt(strings.TrimSpace(string(body)), 10, 64)
			if err != nil || value <= 0 {
				t.Fatalf("invalid %s: %q, %v", name, body, err)
			}
		}
		called := false
		if err := s.WithApplyLock(func() error { called = true; return nil }); err == nil || called {
			t.Fatal("contending operation ran")
		}
		// The coordinator lock must permit the existing Sync/progress lock.
		if err := s.WriteProgress("approved plan\n", "settings\tpending\n"); err != nil {
			t.Fatal(err)
		}
		return failure
	})
	if !errors.Is(err, failure) {
		t.Fatalf("callback error = %v", err)
	}
	if _, err := os.Lstat(s.Path("settings-apply.lock")); !os.IsNotExist(err) {
		t.Fatalf("lock remained: %v", err)
	}
	if err := s.WithApplyLock(func() error { return nil }); err != nil {
		t.Fatal(err)
	}
}

func TestApplyLockRefusesStaleAndSymlinkLocks(t *testing.T) {
	for _, kind := range []string{"stale", "symlink"} {
		t.Run(kind, func(t *testing.T) {
			s := testStore(t)
			if err := os.MkdirAll(s.Dir, 0700); err != nil {
				t.Fatal(err)
			}
			lock := s.Path("settings-apply.lock")
			if kind == "stale" {
				put(t, filepath.Join(lock, "pid"), "999999999\n")
			} else {
				target := filepath.Join(s.Root, "private")
				put(t, filepath.Join(target, "notes"), "preserve")
				if err := os.Symlink(target, lock); err != nil {
					t.Skip(err)
				}
			}
			called := false
			if err := s.WithApplyLock(func() error { called = true; return nil }); err == nil || called {
				t.Fatal("occupied lock accepted")
			}
			if _, err := os.Lstat(lock); err != nil {
				t.Fatal("foreign lock removed:", err)
			}
		})
	}
}

func TestApplyLockRefusesSymlinkAncestor(t *testing.T) {
	s := testStore(t)
	target := fixtureDir(t)
	link := filepath.Join(s.Root, "linked")
	if err := os.Symlink(target, link); err != nil {
		t.Skip(err)
	}
	s.Dir = filepath.Join(link, "state")
	if err := s.WithApplyLock(func() error { t.Fatal("operation ran through symlink"); return nil }); err == nil {
		t.Fatal("symlink ancestor accepted")
	}
	if _, err := os.Lstat(filepath.Join(target, "state")); !os.IsNotExist(err) {
		t.Fatal("external target changed")
	}
}

func TestApplyLockRetainsReplacementLock(t *testing.T) {
	s := testStore(t)
	moved := s.Path("retained-original-lock")
	canRename := true
	err := s.WithApplyLock(func() error {
		if err := os.Rename(s.Path("settings-apply.lock"), moved); err != nil {
			canRename = false
			return nil
		}
		put(t, s.Path("settings-apply.lock/private"), "foreign lock contents")
		return nil
	})
	if !canRename {
		t.Skip("OS prevents renaming an open lock directory")
	}
	if err == nil {
		t.Fatal("lock replacement was not reported")
	}
	body, err := os.ReadFile(s.Path("settings-apply.lock/private"))
	if err != nil || string(body) != "foreign lock contents" {
		t.Fatalf("foreign lock changed: %q %v", body, err)
	}
	if _, err := os.Lstat(filepath.Join(moved, "pid")); !os.IsNotExist(err) {
		t.Fatal("own lock metadata remained")
	}
}

func TestValidateLoadedIsReadOnlyAndRejectsExternalChanges(t *testing.T) {
	for _, change := range []string{"settings", "skills", "environment", "create", "delete", "symlink"} {
		t.Run(change, func(t *testing.T) {
			s := testStore(t)
			if change != "create" {
				put(t, s.Path("settings.tsv"), "schema_version\t1\n")
			}
			put(t, s.Path("skills.disabled"), "alpha\n")
			state, err := s.Load()
			if err != nil {
				t.Fatal(err)
			}
			if err := s.ValidateLoaded(state); err != nil {
				t.Fatal(err)
			}
			switch change {
			case "settings", "create":
				put(t, s.Path("settings.tsv"), "schema_version\t1\nauto_update\toff\n")
			case "skills":
				put(t, s.Path("skills.disabled"), "beta\n")
			case "environment":
				put(t, filepath.Join(s.Root, "ai-configs", "environments.disabled"), "codex\n")
			case "delete":
				if err := os.Remove(s.Path("skills.disabled")); err != nil {
					t.Fatal(err)
				}
			case "symlink":
				if err := os.Remove(s.Path("skills.disabled")); err != nil {
					t.Fatal(err)
				}
				target := filepath.Join(s.Root, "private")
				put(t, target, "private")
				if err := os.Symlink(target, s.Path("skills.disabled")); err != nil {
					t.Skip(err)
				}
			}
			if err := s.ValidateLoaded(state); err == nil {
				t.Fatal("stale draft accepted")
			}
			if _, err := os.Lstat(s.Path("settings.plan")); !os.IsNotExist(err) {
				t.Fatal("validation wrote journal")
			}
		})
	}
}

func TestValidateLoadedDoesNotCreateState(t *testing.T) {
	s := testStore(t)
	state, err := s.Load()
	if err != nil {
		t.Fatal(err)
	}
	if err := s.ValidateLoaded(state); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Lstat(s.Dir); !os.IsNotExist(err) {
		t.Fatal("validation created state")
	}
}
