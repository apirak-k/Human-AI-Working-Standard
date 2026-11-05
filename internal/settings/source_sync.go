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

// SyncSource updates one registered source only when an enabled skill in that
// source changed. The legacy Sync host remains responsible for source setup,
// orchestration, result presentation, and later skill/integration work.
func SyncSource(ctx context.Context, store Store, sourceID string, disabledSkills []string, timeout time.Duration) SyncResult {
	fail := func(detail string) SyncResult { return SyncResult{Status: "failed", Revision: "-", Detail: detail} }
	if ctx.Err() != nil {
		return fail("source synchronization was canceled")
	}
	if err := safeSettingsGitEnvironment(); err != nil {
		return fail("Git environment prevents safe synchronization")
	}
	if sourceID == "" || strings.IndexFunc(sourceID, func(r rune) bool { return r < 0x20 || r == 0x7f }) >= 0 {
		return fail("source is not registered")
	}

	sources, err := store.Sources(ctx)
	if err != nil {
		return fail("source is not registered")
	}
	var source Source
	found := false
	for _, candidate := range sources {
		if candidate.ID == sourceID && candidate.ID != "custom::skills/custom" {
			source = candidate
			found = true
			break
		}
	}
	if !found || !safeSourcePath(source.Path) {
		return fail("source is not registered")
	}

	sourceDir, err := sourceRepositoryRoot(ctx, source)
	if err != nil {
		return fail("source checkout is unavailable")
	}

	skills, err := store.Skills(ctx, []Source{source}, disabledSkills)
	if err != nil {
		return fail("source preflight failed")
	}
	active := make([]Skill, 0, len(skills))
	for _, skill := range skills {
		if skill.Enabled {
			active = append(active, skill)
		}
	}
	if len(active) == 0 {
		return SyncResult{Status: "skipped", Revision: "-", Detail: "source has no active skills"}
	}

	changes, err := sourceWorkingChanges(ctx, sourceDir)
	if err != nil {
		return fail("source checkout is unavailable")
	}
	if len(changes) > 0 {
		return SyncResult{Status: "blocked", Revision: "-", Detail: sourceLocalChangeDetail(source.Path, changes)}
	}

	ref := os.Getenv("HAWS_SYNC_CANDIDATE_REF")
	if ref == "" {
		ref = fmt.Sprintf("refs/haws-sync/native-source-%d-%d", os.Getpid(), time.Now().UnixNano())
	}
	if !strings.HasPrefix(ref, "refs/haws-sync/") {
		return fail("source preflight failed")
	}
	if _, err := settingsGit(ctx, sourceDir, "check-ref-format", ref); err != nil {
		return fail("source preflight failed")
	}
	defer func() { _, _ = settingsGit(context.Background(), sourceDir, "update-ref", "-d", ref) }()

	candidate, candidateErr := settingsGit(ctx, sourceDir, "rev-parse", "--verify", ref+"^{commit}")
	if candidateErr != nil {
		if errors.Is(ctx.Err(), context.Canceled) {
			return fail("source synchronization was canceled")
		}
		if os.Getenv("HAWS_SYNC_PREFETCH_DONE") == "1" {
			return SyncResult{Status: "skipped", Revision: "-", Detail: "Local fallback; network unavailable"}
		}
		fetchCtx := ctx
		if timeout > 0 {
			var cancel context.CancelFunc
			fetchCtx, cancel = context.WithTimeout(ctx, timeout)
			defer cancel()
		}
		_, fetchErr := settingsGit(fetchCtx, sourceDir, "-c", "http.connectTimeout=3", "-c", "http.lowSpeedLimit=1000", "-c", "http.lowSpeedTime=4", "fetch", "--quiet", "origin", "+HEAD:"+ref)
		if fetchErr != nil {
			if errors.Is(fetchCtx.Err(), context.Canceled) {
				return fail("source synchronization was canceled")
			}
			if errors.Is(fetchCtx.Err(), context.DeadlineExceeded) {
				seconds := int64(timeout / time.Second)
				if seconds <= 0 {
					seconds = 30
				}
				return SyncResult{Status: "skipped", Revision: "-", Detail: fmt.Sprintf("Local fallback; remote fetch exceeded %ds", seconds)}
			}
			return SyncResult{Status: "skipped", Revision: "-", Detail: "Local fallback; network unavailable"}
		}
		candidate, err = settingsGit(ctx, sourceDir, "rev-parse", "--verify", ref+"^{commit}")
		if err != nil {
			return fail("remote candidate could not be read")
		}
	}
	if candidate == "" {
		return fail("remote candidate could not be read")
	}
	if !sourceCandidateHasSkill(ctx, sourceDir, candidate, active) {
		return SyncResult{Status: "failed", Revision: candidate, Detail: "candidate validation failed"}
	}

	current, err := settingsGit(ctx, sourceDir, "rev-parse", "--verify", "HEAD")
	if err != nil {
		return fail("current revision could not be read")
	}
	if current != candidate {
		if _, err := settingsGit(ctx, sourceDir, "merge-base", "--is-ancestor", candidate, current); err == nil {
			return SyncResult{Status: "up-to-date", Revision: current, Detail: "local HEAD is ahead of remote candidate"}
		} else {
			var exit *exec.ExitError
			if !errors.As(err, &exit) || exit.ExitCode() != 1 {
				return fail("current revision could not be compared")
			}
		}
		changed, err := settingsGitOutput(ctx, sourceDir, "diff", "--no-renames", "--name-only", "-z", current, candidate)
		if err != nil {
			return SyncResult{Status: "failed", Revision: candidate, Detail: "changed paths could not be inspected"}
		}
		if !sourceChangesActiveSkill(changed, skills) {
			return SyncResult{Status: "up-to-date", Revision: current, Detail: "active skills unchanged"}
		}
		if _, err := settingsGit(ctx, sourceDir, "checkout", "--detach", candidate); err != nil {
			return SyncResult{Status: "failed", Revision: candidate, Detail: "candidate activation failed"}
		}
	}

	final, err := settingsGit(ctx, sourceDir, "rev-parse", "--verify", "HEAD")
	if err != nil {
		return fail("final revision could not be read")
	}
	if final != candidate {
		return SyncResult{Status: "failed", Revision: candidate, Detail: "final HEAD did not equal candidate"}
	}
	if current == candidate {
		return SyncResult{Status: "up-to-date", Revision: candidate, Detail: "final HEAD equals candidate"}
	}
	return SyncResult{Status: "updated", Revision: candidate, Detail: "final HEAD equals candidate"}
}

func sourceRepositoryRoot(ctx context.Context, source Source) (string, error) {
	if source.Dir == "" {
		return "", errors.New("source directory is missing")
	}
	dir, err := filepath.Abs(source.Dir)
	if err != nil {
		return "", err
	}
	info, err := os.Lstat(dir)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return "", errors.New("source directory is unavailable")
	}
	gitEntry, err := os.Lstat(filepath.Join(dir, ".git"))
	if err != nil || gitEntry.Mode()&os.ModeSymlink != 0 {
		return "", errors.New("source Git metadata is unavailable")
	}
	topOutput, err := settingsGitOutput(ctx, dir, "rev-parse", "--show-toplevel")
	if err != nil {
		return "", err
	}
	top := strings.TrimSuffix(string(topOutput), "\n")
	top = strings.TrimSuffix(top, "\r")
	want, err := filepath.EvalSymlinks(dir)
	if err != nil {
		return "", err
	}
	got, err := filepath.EvalSymlinks(top)
	if err != nil || filepath.Clean(got) != filepath.Clean(want) {
		return "", errors.New("source path is not the repository root")
	}
	if strings.HasPrefix(source.ID, "device-") {
		remote, err := settingsGit(ctx, dir, "remote", "get-url", "origin")
		if err != nil || remote != source.URL {
			return "", errors.New("device source remote does not match its registry")
		}
	}
	return dir, nil
}

func sourceWorkingChanges(ctx context.Context, dir string) ([]string, error) {
	status, err := settingsGitOutput(ctx, dir, "status", "--porcelain=v1", "--untracked-files=all", "-z")
	if err != nil {
		return nil, err
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
		changes = append(changes, code+" "+path)
		if code[0] == 'R' || code[0] == 'C' || code[1] == 'R' || code[1] == 'C' {
			i++
		}
	}
	return changes, nil
}

func sourceLocalChangeDetail(path string, changes []string) string {
	shown := min(len(changes), 4)
	detail := "source " + path + " local changes: " + strings.Join(changes[:shown], "; ")
	if len(changes) > shown {
		detail += fmt.Sprintf("; +%d more", len(changes)-shown)
	}
	return detail
}

func sourceCandidateHasSkill(ctx context.Context, dir, revision string, active []Skill) bool {
	tree, err := settingsGitOutput(ctx, dir, "ls-tree", "-r", "--full-tree", "-z", revision)
	if err != nil {
		return false
	}
	entrypoints := map[string]string{}
	for _, record := range strings.Split(string(tree), "\x00") {
		header, path, ok := strings.Cut(record, "\t")
		if !ok || path == "" {
			continue
		}
		fields := strings.Fields(header)
		if len(fields) != 3 || fields[1] != "blob" || (fields[0] != "100644" && fields[0] != "100755") {
			continue
		}
		base := path
		if slash := strings.LastIndexByte(base, '/'); slash >= 0 {
			base = base[slash+1:]
		}
		if (base == "SKILL.md" || base == "skill.md") && eligibleSkill(path) {
			entrypoints[path] = fields[2]
		}
	}

	foundCandidate := false
	for _, skill := range active {
		hash, ok := entrypoints[skill.Entrypoint]
		if !ok {
			continue
		}
		if !sourceCandidateBlobHasContent(ctx, dir, hash) {
			return false
		}
		foundCandidate = true
	}
	if !foundCandidate {
		for _, hash := range entrypoints {
			if sourceCandidateBlobHasContent(ctx, dir, hash) {
				foundCandidate = true
				break
			}
		}
	}
	return foundCandidate
}

func sourceCandidateBlobHasContent(ctx context.Context, dir, hash string) bool {
	size, err := settingsGit(ctx, dir, "cat-file", "-s", hash)
	if err != nil {
		return false
	}
	n, err := strconv.ParseInt(size, 10, 64)
	if err != nil || n <= 0 {
		return false
	}
	contents, err := settingsGitOutput(ctx, dir, "cat-file", "blob", hash)
	return err == nil && strings.TrimSpace(string(contents)) != ""
}

func sourceChangesActiveSkill(changed []byte, skills []Skill) bool {
	paths := strings.Split(string(changed), "\x00")
	for _, path := range paths {
		if path == "" {
			continue
		}
		base := path
		if slash := strings.LastIndexByte(base, '/'); slash >= 0 {
			base = base[slash+1:]
		}
		if (base == "SKILL.md" || base == "skill.md") && eligibleSkill(path) {
			return true
		}
		if sourcePathBelongsToActiveSkill(path, skills) {
			return true
		}
	}
	return false
}

func sourcePathBelongsToActiveSkill(path string, skills []Skill) bool {
	bestDepth, bestActive := -1, false
	for _, skill := range skills {
		entrypoint := skill.Entrypoint
		if entrypoint == "" {
			continue
		}
		skillDir := filepath.ToSlash(filepath.Dir(filepath.FromSlash(entrypoint)))
		if skillDir == "." {
			skillDir = ""
		}
		depth := 0
		if skillDir == "" {
			switch {
			case strings.HasPrefix(path, "README"), strings.HasPrefix(path, "CHANGELOG"), strings.HasPrefix(path, ".github/"):
				continue
			}
		} else {
			if !strings.HasPrefix(path, skillDir+"/") {
				continue
			}
			depth = strings.Count(skillDir, "/") + 1
		}
		if depth > bestDepth {
			bestDepth = depth
			bestActive = skill.Enabled
		} else if depth == bestDepth && skill.Enabled {
			bestActive = true
		}
	}
	return bestDepth >= 0 && bestActive
}

func settingsGitOutput(ctx context.Context, dir string, args ...string) ([]byte, error) {
	if err := safeSettingsGitEnvironment(); err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "git", append([]string{"-C", dir}, args...)...)
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
