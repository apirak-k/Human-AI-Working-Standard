package settings

import (
	"context"
	"crypto/sha256"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
	"unicode"
)

type SyncResult struct{ Status, Revision, Detail string }

func BrainDirectory(root string) string {
	if dir := os.Getenv("HAWS_SECOND_BRAIN_DIR"); dir != "" {
		if !filepath.IsAbs(dir) {
			return filepath.Join(root, dir)
		}
		return dir
	}
	return filepath.Join(root, "secondbrain")
}

func safeSettingsGitEnvironment() error {
	for _, name := range []string{"GIT_DIR", "GIT_WORK_TREE", "GIT_COMMON_DIR", "GIT_INDEX_FILE", "GIT_OBJECT_DIRECTORY", "GIT_ALTERNATE_OBJECT_DIRECTORIES"} {
		if _, present := os.LookupEnv(name); present {
			return fmt.Errorf("Git override %s prevents safe repository operations", name)
		}
	}
	return nil
}

func settingsGit(ctx context.Context, dir string, args ...string) (string, error) {
	if err := safeSettingsGitEnvironment(); err != nil {
		return "", err
	}
	ctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "git", append([]string{"-C", dir}, args...)...)
	cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0", "GIT_OPTIONAL_LOCKS=0")
	output, err := cmd.CombinedOutput()
	if err != nil {
		if ctx.Err() != nil {
			return "", ctx.Err()
		}
		return "", fmt.Errorf("git %s: %w: %s", args[0], err, strings.TrimSpace(string(output)))
	}
	return strings.TrimSpace(string(output)), nil
}

func independentBrain(ctx context.Context, path string) bool {
	info, err := os.Lstat(path)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return false
	}
	info, err = os.Lstat(filepath.Join(path, ".git"))
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return false
	}
	root, err := settingsGit(ctx, path, "rev-parse", "--show-toplevel")
	if err != nil {
		return false
	}
	gitDir, err := settingsGit(ctx, path, "rev-parse", "--absolute-git-dir")
	if err != nil {
		return false
	}
	expectedRoot, err := filepath.EvalSymlinks(path)
	if err != nil {
		return false
	}
	expectedRoot, _ = filepath.Abs(expectedRoot)
	actualRoot, err := filepath.EvalSymlinks(root)
	if err != nil {
		return false
	}
	actualGit, err := filepath.EvalSymlinks(gitDir)
	return err == nil && actualRoot == expectedRoot && actualGit == filepath.Join(expectedRoot, ".git")
}

// BrainRemote returns local-only for directories belonging to a parent checkout.
func BrainRemote(ctx context.Context, path string) (string, error) {
	if err := safeSettingsGitEnvironment(); err != nil {
		return "", err
	}
	if err := ctx.Err(); err != nil {
		return "", err
	}
	if !independentBrain(ctx, path) {
		return "", nil
	}
	remote, err := settingsGit(ctx, path, "remote", "get-url", "origin")
	if err != nil {
		var exit *exec.ExitError
		if errors.As(err, &exit) && (exit.ExitCode() == 1 || exit.ExitCode() == 2) {
			return "", nil
		}
		return "", err
	}
	return remote, nil
}

// SyncBrain fast-forwards a clean, independently owned Second Brain checkout.
// It shares the connection lock so Settings cannot replace the checkout mid-sync.
func SyncBrain(ctx context.Context, path string, timeout time.Duration) SyncResult {
	fail := func(detail string) SyncResult { return SyncResult{Status: "failed", Revision: "-", Detail: detail} }
	if err := safeSettingsGitEnvironment(); err != nil {
		return fail("Git environment prevents safe synchronization")
	}
	if path == "" {
		return fail("Second Brain checkout is unavailable")
	}
	path, err := filepath.Abs(path)
	if err != nil {
		return fail("Second Brain checkout is unavailable")
	}
	if err := repositoryPathUnlinked(filepath.Dir(path), filepath.Base(path)); err != nil {
		return fail("Second Brain checkout is unavailable")
	}
	info, err := os.Lstat(path)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return fail("Second Brain checkout is unavailable")
	}
	lock := filepath.Join(filepath.Dir(path), "."+filepath.Base(path)+".haws-brain-lock")
	if err := os.Mkdir(lock, 0700); err != nil {
		return fail("another Second Brain operation may be active")
	}
	defer os.Remove(lock)
	if !independentBrain(ctx, path) {
		return fail("Second Brain checkout is unavailable")
	}
	remote, err := BrainRemote(ctx, path)
	if err != nil {
		return fail("Second Brain checkout is unavailable")
	}
	if remote == "" {
		return SyncResult{Status: "skipped", Revision: "-", Detail: "Second Brain is local-only"}
	}
	status, err := settingsGit(ctx, path, "status", "--porcelain", "--untracked-files=all")
	if err != nil {
		return fail("Second Brain preflight failed")
	}
	if status != "" {
		return fail("Second Brain has local changes")
	}
	before, err := settingsGit(ctx, path, "rev-parse", "--verify", "HEAD")
	if err != nil {
		return fail("Second Brain checkout is unavailable")
	}
	if timeout > 0 {
		var cancel context.CancelFunc
		ctx, cancel = context.WithTimeout(ctx, timeout)
		defer cancel()
	}
	if _, err := settingsGit(ctx, path, "pull", "--ff-only", "origin", "main"); err != nil {
		return fail("fast-forward pull failed")
	}
	after, err := settingsGit(ctx, path, "rev-parse", "--verify", "HEAD")
	if err != nil {
		return fail("Second Brain checkout is unavailable")
	}
	if before == after {
		return SyncResult{Status: "up-to-date", Revision: after, Detail: "no new commits on remote"}
	}
	return SyncResult{Status: "updated", Revision: before + ".." + after, Detail: "fast-forwarded from remote"}
}

func validBrainURL(url string) bool {
	if url == "" || strings.HasPrefix(url, "-") || strings.IndexFunc(url, unicode.IsControl) >= 0 || strings.IndexFunc(url, unicode.IsSpace) >= 0 {
		return false
	}
	return filepath.IsAbs(url) || strings.HasPrefix(url, "./") || strings.HasPrefix(url, "../") || validCatalogRemote(url) || strings.HasPrefix(url, "file://")
}

func ValidateBrainURL(raw string) error {
	if !validBrainURL(raw) {
		return errors.New("invalid Second Brain repository URL")
	}
	return nil
}

// ConnectBrain fetches only into a disposable snapshot. It never stages or publishes notes.
func ConnectBrain(ctx context.Context, path, url string) error {
	if err := safeSettingsGitEnvironment(); err != nil {
		return err
	}
	if !validBrainURL(url) {
		return errors.New("invalid Second Brain repository URL")
	}
	if strings.HasPrefix(url, "./") || strings.HasPrefix(url, "../") {
		absolute, err := filepath.Abs(url)
		if err != nil {
			return err
		}
		url = absolute
	}
	return brainTransaction(ctx, path, func(candidate string) error {
		if _, err := os.Lstat(filepath.Join(candidate, ".git")); errors.Is(err, os.ErrNotExist) {
			if _, err := settingsGit(ctx, candidate, "init", "-b", "main", "--quiet"); err != nil {
				return err
			}
		}
		if !independentBrain(ctx, candidate) {
			return errors.New("Second Brain is not independently rooted")
		}
		if _, err := settingsGit(ctx, candidate, "config", "--local", "--replace-all", "remote.origin.url", url); err != nil {
			return err
		}
		if _, err := settingsGit(ctx, candidate, "config", "--local", "--replace-all", "remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*"); err != nil {
			return err
		}
		if _, err := settingsGit(ctx, candidate, "config", "--local", "--unset-all", "remote.origin.pushurl"); err != nil {
			var exit *exec.ExitError
			if !errors.As(err, &exit) || exit.ExitCode() != 5 {
				return err
			}
		}
		if _, err := settingsGit(ctx, candidate, "ls-remote", "origin"); err != nil {
			return err
		}
		_, err := settingsGit(ctx, candidate, "-c", "core.hooksPath=", "fetch", "--quiet", "origin")
		return err
	})
}

func DisconnectBrain(ctx context.Context, path, expectedURL string) error {
	if err := safeSettingsGitEnvironment(); err != nil {
		return err
	}
	if !independentBrain(ctx, path) {
		return errors.New("Second Brain is not independently rooted")
	}
	return brainTransaction(ctx, path, func(candidate string) error {
		current, err := BrainRemote(ctx, candidate)
		if err != nil {
			return err
		}
		if current != expectedURL {
			return errors.New("Second Brain remote changed after confirmation")
		}
		if current == "" {
			return nil
		}
		_, err = settingsGit(ctx, candidate, "remote", "remove", "origin")
		return err
	})
}

func brainTransaction(ctx context.Context, path string, mutate func(string) error) error {
	if path == "" {
		return errors.New("Second Brain directory is required")
	}
	path, err := filepath.Abs(path)
	if err != nil {
		return err
	}
	if err := repositoryPathUnlinked(filepath.Dir(path), filepath.Base(path)); err != nil {
		return err
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	lock := filepath.Join(filepath.Dir(path), "."+filepath.Base(path)+".haws-brain-lock")
	if err := os.Mkdir(lock, 0700); err != nil {
		return fmt.Errorf("another Second Brain operation may be active (lock %s): %w", lock, err)
	}
	defer os.Remove(lock)
	// Inspect the root after acquiring the lock; another completed operation may
	// have replaced it while this call was waiting to start.
	info, err := os.Lstat(path)
	exists := err == nil
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if exists {
		if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
			return errors.New("Second Brain root must be a real directory")
		}
		if git, err := os.Lstat(filepath.Join(path, ".git")); err == nil && (!git.IsDir() || git.Mode()&os.ModeSymlink != 0) {
			return errors.New("linked Second Brain worktrees are unsupported")
		} else if err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
	}
	stage, err := os.MkdirTemp(filepath.Dir(path), "."+filepath.Base(path)+".haws-connect-")
	if err != nil {
		return err
	}
	cleanup := true
	defer func() {
		if cleanup {
			_ = os.RemoveAll(stage)
		}
	}()
	candidate, baseline, backup := filepath.Join(stage, "candidate"), filepath.Join(stage, "baseline"), filepath.Join(stage, "original")
	if exists {
		if err := copyBrainTree(ctx, path, baseline); err != nil {
			return err
		}
		if err := copyBrainTree(ctx, baseline, candidate); err != nil {
			return err
		}
	} else if err := os.Mkdir(candidate, 0700); err != nil {
		return err
	}
	headBefore, indexBefore := "", ""
	preserveGitState := independentBrain(ctx, candidate)
	if preserveGitState {
		headBefore, _ = settingsGit(ctx, candidate, "rev-parse", "--verify", "HEAD")
		index, err := os.ReadFile(filepath.Join(candidate, ".git", "index"))
		if err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
		indexBefore = string(index)
	}
	if err := mutate(candidate); err != nil {
		return err
	}
	if preserveGitState {
		headAfter, _ := settingsGit(ctx, candidate, "rev-parse", "--verify", "HEAD")
		index, err := os.ReadFile(filepath.Join(candidate, ".git", "index"))
		if err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
		if headAfter != headBefore || string(index) != indexBefore {
			return errors.New("Second Brain operation changed HEAD or index; local checkout preserved")
		}
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	if exists {
		before, err := brainFingerprint(ctx, baseline)
		if err != nil {
			return err
		}
		current, err := brainFingerprint(ctx, path)
		if err != nil {
			return err
		}
		if before != current {
			return errors.New("Second Brain changed during connection; local checkout preserved")
		}
		if err := os.Rename(path, backup); err != nil {
			return err
		}
	} else if _, err := os.Lstat(path); !errors.Is(err, os.ErrNotExist) {
		return errors.New("Second Brain appeared during connection")
	}
	if err := os.Rename(candidate, path); err != nil {
		if exists {
			if rollback := os.Rename(backup, path); rollback != nil {
				cleanup = false
				return fmt.Errorf("activation failed: %v; original preserved at %s: %w", err, backup, rollback)
			}
		}
		return err
	}
	return nil
}

func copyBrainTree(ctx context.Context, source, destination string) error {
	type copiedDirectory struct {
		path string
		info fs.FileInfo
	}
	var directories []copiedDirectory
	err := filepath.WalkDir(source, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		relative, err := filepath.Rel(source, path)
		if err != nil {
			return err
		}
		target := filepath.Join(destination, relative)
		info, err := entry.Info()
		if err != nil {
			return err
		}
		switch {
		case info.IsDir():
			directories = append(directories, copiedDirectory{target, info})
			return os.Mkdir(target, info.Mode().Perm()|0700)
		case info.Mode()&os.ModeSymlink != 0:
			if relative == ".git" || strings.HasPrefix(relative, ".git"+string(filepath.Separator)) {
				return errors.New("linked Git metadata cannot be connected transactionally")
			}
			link, err := os.Readlink(path)
			if err != nil {
				return err
			}
			return os.Symlink(link, target)
		case info.Mode().IsRegular():
			input, err := os.Open(path)
			if err != nil {
				return err
			}
			defer input.Close()
			output, err := os.OpenFile(target, os.O_CREATE|os.O_EXCL|os.O_WRONLY, info.Mode().Perm())
			if err != nil {
				return err
			}
			_, copyErr := io.Copy(output, input)
			closeErr := output.Close()
			if copyErr != nil {
				return copyErr
			}
			if closeErr != nil {
				return closeErr
			}
			return os.Chtimes(target, info.ModTime(), info.ModTime())
		default:
			return fmt.Errorf("unsupported file in Second Brain snapshot: %s", path)
		}
	})
	if err != nil {
		return err
	}
	for i := len(directories) - 1; i >= 0; i-- {
		dir := directories[i]
		if err := os.Chmod(dir.path, dir.info.Mode().Perm()); err != nil {
			return err
		}
		if err := os.Chtimes(dir.path, dir.info.ModTime(), dir.info.ModTime()); err != nil {
			return err
		}
	}
	return nil
}

func brainFingerprint(ctx context.Context, root string) ([32]byte, error) {
	hash := sha256.New()
	err := filepath.WalkDir(root, func(path string, entry fs.DirEntry, walkErr error) error {
		if walkErr != nil {
			return walkErr
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		relative, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		// Directory permissions are not changed by Git and need not affect conflict detection.
		mode := info.Mode()
		size := info.Size()
		if info.IsDir() {
			mode = fs.ModeDir
			size = 0
		}
		fmt.Fprintf(hash, "%q %d %d\n", relative, mode, size)
		if info.Mode().IsRegular() {
			file, err := os.Open(path)
			if err != nil {
				return err
			}
			_, err = io.Copy(hash, file)
			closeErr := file.Close()
			if err != nil {
				return err
			}
			return closeErr
		}
		if info.Mode()&os.ModeSymlink != 0 {
			link, err := os.Readlink(path)
			if err != nil {
				return err
			}
			fmt.Fprintf(hash, "%q\n", link)
		}
		return nil
	})
	var result [32]byte
	copy(result[:], hash.Sum(nil))
	return result, err
}
