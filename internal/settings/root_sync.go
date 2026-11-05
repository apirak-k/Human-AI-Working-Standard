package settings

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// SyncHawsRoot fast-forwards the current clean HAWS branch to its tracked remote.
func SyncHawsRoot(ctx context.Context, root string, timeout time.Duration) SyncResult {
	fail := func(detail string) SyncResult { return SyncResult{Status: "failed", Revision: "-", Detail: detail} }
	if ctx.Err() != nil {
		return fail("HAWS synchronization was canceled")
	}
	if err := safeSettingsGitEnvironment(); err != nil {
		return fail("Git environment prevents safe synchronization")
	}
	if root == "" {
		return fail("HAWS checkout is unavailable")
	}
	root, err := filepath.Abs(root)
	if err != nil {
		return fail("HAWS checkout is unavailable")
	}
	info, err := os.Lstat(root)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return fail("HAWS checkout is unavailable")
	}
	if resolved, err := filepath.EvalSymlinks(root); err == nil {
		root = resolved
	}
	top, err := settingsGit(ctx, root, "rev-parse", "--show-toplevel")
	if err != nil || filepath.Clean(top) != root {
		return fail("HAWS checkout is unavailable")
	}
	if _, err := settingsGit(ctx, root, "rev-parse", "--is-inside-work-tree"); err != nil {
		return fail("HAWS checkout is unavailable")
	}

	ref := os.Getenv("HAWS_SYNC_CANDIDATE_REF")
	if ref == "" {
		ref = fmt.Sprintf("refs/haws-sync/native-%d-%d", os.Getpid(), time.Now().UnixNano())
	}
	if !strings.HasPrefix(ref, "refs/haws-sync/") {
		return fail("source preflight failed")
	}
	if _, err := settingsGit(ctx, root, "check-ref-format", ref); err != nil {
		return fail("source preflight failed")
	}
	defer func() { _, _ = settingsGit(context.Background(), root, "update-ref", "-d", ref) }()

	branch, err := settingsGit(ctx, root, "symbolic-ref", "--quiet", "--short", "HEAD")
	if err != nil || branch == "" {
		return SyncResult{Status: "blocked", Revision: "-", Detail: "HAWS checkout is detached"}
	}
	remote, remoteErr := settingsGit(ctx, root, "config", "--get", "branch."+branch+".remote")
	fetchSource, sourceErr := settingsGit(ctx, root, "config", "--get", "branch."+branch+".merge")
	if remoteErr != nil || sourceErr != nil || remote == "" || strings.HasPrefix(remote, "-") || !strings.HasPrefix(fetchSource, "refs/") {
		return fail("HAWS branch has no tracked remote")
	}
	if _, err := settingsGit(ctx, root, "check-ref-format", fetchSource); err != nil {
		return fail("HAWS branch has no tracked remote")
	}
	changes, err := hawsRootChanges(ctx, root)
	if err != nil {
		return fail("HAWS checkout is unavailable")
	}
	if len(changes) != 0 {
		return SyncResult{Status: "blocked", Revision: "-", Detail: "HAWS root local changes: " + strings.Join(changes[:min(len(changes), 4)], "; ") + hawsRootExtraChanges(len(changes))}
	}
	current, err := settingsGit(ctx, root, "rev-parse", "--verify", "HEAD")
	if err != nil {
		return fail("current revision could not be read")
	}

	candidate, candidateErr := settingsGit(ctx, root, "rev-parse", "--verify", ref)
	if candidateErr != nil {
		if os.Getenv("HAWS_SYNC_PREFETCH_DONE") == "1" {
			return SyncResult{Status: "skipped", Revision: "-", Detail: "Local fallback; network unavailable"}
		}
		if timeout > 0 {
			var cancel context.CancelFunc
			ctx, cancel = context.WithTimeout(ctx, timeout)
			defer cancel()
		}
		_, fetchErr := settingsGit(ctx, root, "-c", "http.connectTimeout=3", "-c", "http.lowSpeedLimit=1000", "-c", "http.lowSpeedTime=4", "fetch", "--quiet", remote, "+"+fetchSource+":"+ref)
		if fetchErr != nil {
			if errors.Is(ctx.Err(), context.Canceled) {
				return fail("HAWS synchronization was canceled")
			}
			if errors.Is(ctx.Err(), context.DeadlineExceeded) {
				seconds := int64(timeout / time.Second)
				if seconds <= 0 {
					seconds = 30
				}
				return SyncResult{Status: "skipped", Revision: "-", Detail: fmt.Sprintf("Local fallback; remote fetch exceeded %ds", seconds)}
			}
			return SyncResult{Status: "skipped", Revision: "-", Detail: "Local fallback; network unavailable"}
		}
		candidate, err = settingsGit(ctx, root, "rev-parse", "--verify", ref)
		if err != nil {
			return fail("remote candidate could not be read")
		}
	}
	if candidate == "" {
		return fail("remote candidate could not be read")
	}
	if size, err := settingsGit(ctx, root, "cat-file", "-s", candidate+":haws.sh"); err != nil {
		return fail("candidate validation failed")
	} else if n, err := strconv.ParseInt(size, 10, 64); err != nil || n <= 0 {
		return fail("candidate validation failed")
	}
	if current != candidate {
		if _, err := settingsGit(ctx, root, "merge-base", "--is-ancestor", candidate, current); err == nil {
			return SyncResult{Status: "up-to-date", Revision: current, Detail: "local HEAD is ahead of remote candidate"}
		} else {
			var exit *exec.ExitError
			if !errors.As(err, &exit) || exit.ExitCode() != 1 {
				return fail("current revision could not be compared")
			}
		}
		if _, err := settingsGit(ctx, root, "merge", "--ff-only", candidate); err != nil {
			return fail("candidate activation failed")
		}
	}
	final, err := settingsGit(ctx, root, "rev-parse", "--verify", "HEAD")
	if err != nil {
		return fail("final revision could not be read")
	}
	if final != candidate {
		return fail("final HEAD did not equal candidate")
	}
	if current == candidate {
		return SyncResult{Status: "up-to-date", Revision: candidate, Detail: "final HEAD equals candidate"}
	}
	return SyncResult{Status: "updated", Revision: candidate, Detail: "final HEAD equals candidate"}
}

func hawsRootChanges(ctx context.Context, root string) ([]string, error) {
	status, err := hawsRootGitOutput(ctx, root, "status", "--porcelain=v1", "--untracked-files=all", "--ignore-submodules=none", "-z")
	if err != nil {
		return nil, err
	}
	index, err := hawsRootGitOutput(ctx, root, "ls-files", "--stage", "-z")
	if err != nil {
		return nil, err
	}
	gitlinks := make(map[string]bool)
	for _, record := range strings.Split(string(index), "\x00") {
		header, path, ok := strings.Cut(record, "\t")
		fields := strings.Fields(header)
		if ok && len(fields) > 0 && fields[0] == "160000" {
			gitlinks[path] = true
		}
	}
	var changes []string
	records := strings.Split(string(status), "\x00")
	for i := 0; i < len(records); i++ {
		record := records[i]
		if record == "" {
			continue
		}
		if len(record) < 4 {
			return nil, errors.New("malformed Git status")
		}
		code, path := record[:2], record[3:]
		if code == "??" && strings.HasPrefix(path, "skills/custom/") {
			continue
		}
		if code[0] == ' ' && gitlinks[path] && safeSourcePath(path) {
			if _, err := settingsGit(ctx, filepath.Join(root, filepath.FromSlash(path)), "rev-parse", "--is-inside-work-tree"); err == nil {
				continue
			}
		}
		changes = append(changes, code+" "+path)
		if code[0] == 'R' || code[0] == 'C' || code[1] == 'R' || code[1] == 'C' {
			i++
		}
	}
	return changes, nil
}

func hawsRootGitOutput(ctx context.Context, root string, args ...string) ([]byte, error) {
	if err := safeSettingsGitEnvironment(); err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "git", append([]string{"-C", root}, args...)...)
	cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0", "GIT_OPTIONAL_LOCKS=0")
	output, err := cmd.CombinedOutput()
	if err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("git %s: %w: %s", args[0], err, strings.TrimSpace(string(output)))
	}
	return output, nil
}

func hawsRootExtraChanges(count int) string {
	if count > 4 {
		return fmt.Sprintf("; +%d more", count-4)
	}
	return ""
}
