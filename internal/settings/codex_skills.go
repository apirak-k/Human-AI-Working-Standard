package settings

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

const maxSkillOwnershipBytes = 1 << 20

type CodexSkillSyncResult struct {
	Linked        int
	AlreadyLinked int
	PluginOwned   int
	Preserved     int
}

type codexSkillTarget struct {
	name, pluginName, source, destination string
	pluginOwned                           bool
}

type skillOwnershipRecord struct {
	kind, path, source, fingerprint string
}

// SyncCodexSkillLinks reconciles active catalog skills with Codex's shared
// ~/.agents/skills directory. It uses the same ownership ledger as Sync.
func SyncCodexSkillLinks(ctx context.Context, store Store, home string) (CodexSkillSyncResult, error) {
	var result CodexSkillSyncResult
	if err := ctx.Err(); err != nil {
		return result, err
	}
	if !filepath.IsAbs(home) || home == "." {
		return result, errors.New("Codex skill linking needs an absolute home directory")
	}
	state, err := store.Load()
	if err != nil {
		return result, fmt.Errorf("load skill selections: %w", err)
	}
	if contains(state.DisabledEnvironments, "codex") {
		return result, nil
	}
	sources, err := store.Sources(ctx)
	if err != nil {
		return result, fmt.Errorf("read skill sources: %w", err)
	}
	skills, err := store.Skills(ctx, sources, state.DisabledSkills)
	if err != nil {
		return result, fmt.Errorf("read active skills: %w", err)
	}
	sourceByID := make(map[string]Source, len(sources))
	for _, source := range sources {
		sourceByID[source.ID] = source
	}
	counts := make(map[string]int)
	seen := make(map[string]bool)
	active := make([]Skill, 0, len(skills))
	for _, skill := range skills {
		if !skill.Enabled || seen[skill.ID] {
			continue
		}
		seen[skill.ID] = true
		active = append(active, skill)
		counts[skill.Name]++
	}
	targets := make([]codexSkillTarget, 0, len(active))
	for _, skill := range active {
		if err := ctx.Err(); err != nil {
			return result, err
		}
		source, ok := sourceByID[skill.SourceID]
		if !ok {
			continue
		}
		name := skill.Name
		if counts[skill.Name] > 1 {
			name += " [" + filepath.Base(filepath.FromSlash(source.Path)) + "]"
		}
		if !safeSkillTargetName(name) {
			return result, fmt.Errorf("unsafe Codex skill target name %q", name)
		}
		entrypoint := filepath.Clean(filepath.FromSlash(skill.Entrypoint))
		if filepath.IsAbs(entrypoint) || entrypoint == "." || entrypoint == ".." || strings.HasPrefix(entrypoint, ".."+string(filepath.Separator)) {
			return result, fmt.Errorf("unsafe skill entrypoint %q", skill.Entrypoint)
		}
		skillDir := filepath.Dir(filepath.Join(source.Dir, entrypoint))
		relative, err := filepath.Rel(source.Dir, skillDir)
		if err != nil || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) || filepath.IsAbs(relative) {
			return result, fmt.Errorf("skill entrypoint escapes its source: %q", skill.Entrypoint)
		}
		if info, err := os.Stat(skillDir); err != nil || !info.IsDir() {
			if err == nil {
				err = errors.New("not a directory")
			}
			return result, fmt.Errorf("skill directory is unavailable: %w", err)
		}
		targets = append(targets, codexSkillTarget{
			name:        name,
			pluginName:  skill.Name,
			source:      skillDir,
			destination: filepath.Join(home, ".agents", "skills", filepath.FromSlash(name)),
			pluginOwned: strings.HasPrefix(skill.Name, "ponytail"),
		})
	}

	stateOwnership, err := readSkillOwnership(filepath.Join(store.Dir, "ownership.tsv"))
	if err != nil {
		return result, err
	}
	globalLedger := filepath.Join(home, ".haws", "skills-ownership.tsv")
	globalOwnership, err := readSkillOwnership(globalLedger)
	if err != nil {
		return result, err
	}
	for i := range targets {
		if !targets[i].pluginOwned {
			continue
		}
		targets[i].pluginOwned, err = codexPluginOwnsSkill(ctx, home, targets[i].pluginName)
		if err != nil {
			return result, err
		}
	}

	for _, target := range targets {
		if err := ctx.Err(); err != nil {
			return result, err
		}
		record, owned, err := findSkillOwnership(target.destination, stateOwnership, globalOwnership)
		if err != nil {
			return result, err
		}
		linkTarget, isLink, err := readDirectoryLink(target.destination)
		if err != nil {
			return result, err
		}
		verifiedOwned := owned && isLink && skillLinkMatchesRecord(target.destination, linkTarget, record)
		if target.pluginOwned {
			result.PluginOwned++
			if isLink {
				if verifiedOwned {
					if err := os.Remove(target.destination); err != nil {
						return result, fmt.Errorf("remove HAWS-owned Codex skill link %s: %w", target.destination, err)
					}
				} else {
					result.Preserved++
				}
			} else if _, err := os.Lstat(target.destination); err == nil {
				result.Preserved++
			} else if !errors.Is(err, os.ErrNotExist) {
				return result, err
			}
			continue
		}

		if isLink {
			if codexLinkPointsTo(target.source, target.destination, linkTarget) {
				result.Linked++
				result.AlreadyLinked++
				continue
			}
			if !verifiedOwned {
				result.Preserved++
				continue
			}
			if err := os.Remove(target.destination); err != nil {
				return result, fmt.Errorf("remove HAWS-owned Codex skill link %s: %w", target.destination, err)
			}
		} else if _, err := os.Lstat(target.destination); err == nil {
			result.Preserved++
			continue
		} else if !errors.Is(err, os.ErrNotExist) {
			return result, err
		}

		if err := os.MkdirAll(filepath.Dir(target.destination), 0700); err != nil {
			return result, fmt.Errorf("create Codex skills directory: %w", err)
		}
		linkKind, err := createDirectoryLink(ctx, target.destination, target.source)
		if err != nil {
			return result, fmt.Errorf("create Codex skill link %s: %w", target.destination, err)
		}
		if err := recordSkillOwnership(globalLedger, linkKind, target.destination, target.source); err != nil {
			_ = os.Remove(target.destination)
			return result, err
		}
		result.Linked++
	}
	return result, nil
}

func contains(values []string, wanted string) bool {
	for _, value := range values {
		if value == wanted {
			return true
		}
	}
	return false
}

func safeSkillTargetName(name string) bool {
	if name == "" || strings.Contains(name, `\`) || strings.IndexFunc(name, func(r rune) bool { return r < 0x20 || r == 0x7f }) >= 0 {
		return false
	}
	for _, part := range strings.Split(name, "/") {
		if part == "" || part == "." || part == ".." || strings.ContainsAny(part, `<>:"|?*`) {
			return false
		}
	}
	return !filepath.IsAbs(filepath.FromSlash(name))
}

func readSkillOwnership(path string) ([]skillOwnershipRecord, error) {
	info, err := os.Lstat(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("inspect skill ownership ledger %s: %w", path, err)
	}
	if !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || info.Size() > maxSkillOwnershipBytes {
		return nil, fmt.Errorf("skill ownership ledger is not a bounded regular file: %s", path)
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, fmt.Errorf("read skill ownership ledger %s: %w", path, err)
	}
	defer file.Close()
	var records []skillOwnershipRecord
	reader := bufio.NewReader(file)
	var total int64
	for {
		line, readErr := reader.ReadString('\n')
		total += int64(len(line))
		if total > maxSkillOwnershipBytes {
			return nil, fmt.Errorf("skill ownership ledger exceeds size limit: %s", path)
		}
		trimmed := strings.TrimSuffix(strings.TrimSuffix(line, "\n"), "\r")
		fields := strings.Split(trimmed, "\t")
		if len(fields) >= 3 && fields[0] == "skills" {
			if len(fields) != 5 && !(len(fields) == 6 && fields[5] == "schema=2") {
				continue
			}
			if fields[1] != "symlink" && fields[1] != "junction" && fields[1] != "directory-link" {
				continue
			}
			records = append(records, skillOwnershipRecord{
				kind:        fields[1],
				path:        fields[2],
				source:      fields[3],
				fingerprint: fields[4],
			})
		}
		if readErr != nil {
			if !errors.Is(readErr, io.EOF) {
				return nil, fmt.Errorf("read skill ownership ledger %s: %w", path, readErr)
			}
			break
		}
	}
	return records, nil
}

func findSkillOwnership(destination string, sources ...[]skillOwnershipRecord) (skillOwnershipRecord, bool, error) {
	var found skillOwnershipRecord
	foundSource := -1
	for sourceIndex, records := range sources {
		for _, record := range records {
			if !sameSkillPath(record.path, destination) {
				continue
			}
			if sourceIndex > foundSource {
				found = record
				foundSource = sourceIndex
				continue
			}
			if sourceIndex == foundSource && (found.kind != record.kind || found.source != record.source || found.fingerprint != record.fingerprint) {
				return skillOwnershipRecord{}, false, fmt.Errorf("conflicting skill ownership records for %s", destination)
			}
		}
	}
	return found, foundSource >= 0, nil
}

func sameSkillPath(left, right string) bool {
	left = filepath.Clean(left)
	right = filepath.Clean(right)
	if runtime.GOOS == "windows" {
		return strings.EqualFold(left, right)
	}
	return left == right
}

func readDirectoryLink(path string) (string, bool, error) {
	target, err := os.Readlink(path)
	if err == nil {
		return target, true, nil
	}
	if errors.Is(err, fs.ErrNotExist) {
		return "", false, nil
	}
	if _, statErr := os.Lstat(path); errors.Is(statErr, os.ErrNotExist) {
		return "", false, nil
	} else if statErr != nil {
		return "", false, statErr
	}
	return "", false, nil
}

func skillLinkMatchesRecord(destination, linkTarget string, record skillOwnershipRecord) bool {
	if record.fingerprint == "" {
		return false
	}
	current := resolveLinkTarget(destination, linkTarget)
	source := resolveLinkTarget(destination, record.source)
	if current == "" || source == "" {
		return false
	}
	if !sameSkillPath(current, source) {
		currentResolved, currentErr := filepath.EvalSymlinks(current)
		sourceResolved, sourceErr := filepath.EvalSymlinks(source)
		if currentErr != nil || sourceErr != nil || !sameSkillPath(currentResolved, sourceResolved) {
			return false
		}
	}
	if record.fingerprint == linkTarget {
		return true
	}
	fingerprint := resolveLinkTarget(destination, record.fingerprint)
	if fingerprint == "" {
		return false
	}
	if sameSkillPath(fingerprint, current) || sameSkillPath(fingerprint, source) {
		return true
	}
	fingerprintResolved, fingerprintErr := filepath.EvalSymlinks(fingerprint)
	currentResolved, currentErr := filepath.EvalSymlinks(current)
	return fingerprintErr == nil && currentErr == nil && sameSkillPath(fingerprintResolved, currentResolved)
}

func resolveLinkTarget(destination, target string) string {
	if target == "" {
		return ""
	}
	if !filepath.IsAbs(target) {
		target = filepath.Join(filepath.Dir(destination), target)
	}
	resolved, err := filepath.Abs(target)
	if err != nil {
		return ""
	}
	return filepath.Clean(resolved)
}

func codexLinkPointsTo(source, destination, linkTarget string) bool {
	current := resolveLinkTarget(destination, linkTarget)
	expected, err := filepath.Abs(source)
	if err != nil || current == "" {
		return false
	}
	if sameSkillPath(current, filepath.Clean(expected)) {
		return true
	}
	currentResolved, currentErr := filepath.EvalSymlinks(current)
	expectedResolved, expectedErr := filepath.EvalSymlinks(expected)
	return currentErr == nil && expectedErr == nil && sameSkillPath(currentResolved, expectedResolved)
}

func recordSkillOwnership(ledger, kind, destination, source string) error {
	if err := os.MkdirAll(filepath.Dir(ledger), 0700); err != nil {
		return fmt.Errorf("create skill ownership directory: %w", err)
	}
	info, err := os.Lstat(ledger)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("inspect skill ownership ledger %s: %w", ledger, err)
	}
	if err == nil && (!info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || info.Size() > maxSkillOwnershipBytes) {
		return fmt.Errorf("skill ownership ledger is not a bounded regular file: %s", ledger)
	}
	var lines []string
	if err == nil {
		contents, readErr := os.ReadFile(ledger)
		if readErr != nil {
			return fmt.Errorf("read skill ownership ledger %s: %w", ledger, readErr)
		}
		lines = strings.Split(strings.TrimSuffix(string(contents), "\n"), "\n")
		if len(lines) == 1 && lines[0] == "" {
			lines = nil
		}
	}
	newRecord := strings.Join([]string{"skills", kind, destination, source, source, "schema=2"}, "\t")
	updated := make([]string, 0, len(lines)+1)
	found := false
	for _, line := range lines {
		fields := strings.Split(line, "\t")
		if len(fields) >= 3 && fields[0] == "skills" && sameSkillPath(fields[2], destination) {
			if !found {
				updated = append(updated, newRecord)
				found = true
			}
			continue
		}
		updated = append(updated, line)
	}
	if !found {
		updated = append(updated, newRecord)
	}
	data := []byte(strings.Join(updated, "\n") + "\n")
	if len(data) > maxSkillOwnershipBytes {
		return errors.New("skill ownership ledger exceeds size limit")
	}
	mode := fs.FileMode(0600)
	if err == nil {
		mode = info.Mode().Perm()
	}
	temporary, err := os.CreateTemp(filepath.Dir(ledger), ".skills-ownership-*.tmp")
	if err != nil {
		return fmt.Errorf("stage skill ownership ledger: %w", err)
	}
	tempPath := temporary.Name()
	defer os.Remove(tempPath)
	if err := temporary.Chmod(mode); err != nil {
		_ = temporary.Close()
		return fmt.Errorf("set skill ownership ledger mode: %w", err)
	}
	if _, err := temporary.Write(data); err != nil {
		_ = temporary.Close()
		return fmt.Errorf("write skill ownership ledger: %w", err)
	}
	if err := temporary.Sync(); err != nil {
		_ = temporary.Close()
		return fmt.Errorf("sync skill ownership ledger: %w", err)
	}
	if err := temporary.Close(); err != nil {
		return fmt.Errorf("close skill ownership ledger: %w", err)
	}
	if err := os.Rename(tempPath, ledger); err != nil {
		return fmt.Errorf("replace skill ownership ledger: %w", err)
	}
	return nil
}

func codexPluginOwnsSkill(ctx context.Context, home, skillName string) (bool, error) {
	if !strings.HasPrefix(skillName, "ponytail") {
		return false, nil
	}
	defaultCodexHome := os.Getenv("CODEX_HOME")
	if defaultCodexHome == "" {
		defaultCodexHome = filepath.Join(home, ".codex")
	}
	roots := []string{
		filepath.Join(defaultCodexHome, "plugins", "cache"),
		filepath.Join(home, ".codex", "plugins", "cache"),
		filepath.Join(home, ".agents", "plugins", "cache"),
	}
	seen := make(map[string]bool)
	for _, root := range roots {
		root = filepath.Clean(root)
		if seen[root] {
			continue
		}
		seen[root] = true
		info, err := os.Lstat(root)
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		if err != nil {
			return false, fmt.Errorf("inspect Codex plugin cache %s: %w", root, err)
		}
		if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
			continue
		}
		found := false
		err = filepath.WalkDir(root, func(path string, entry fs.DirEntry, walkErr error) error {
			if walkErr != nil {
				return walkErr
			}
			if err := ctx.Err(); err != nil {
				return err
			}
			if entry.IsDir() {
				return nil
			}
			if entry.Name() != "SKILL.md" && entry.Name() != "skill.md" {
				return nil
			}
			if filepath.Base(filepath.Dir(path)) != skillName || filepath.Base(filepath.Dir(filepath.Dir(path))) != "skills" {
				return nil
			}
			info, err := entry.Info()
			if err == nil && info.Mode().IsRegular() {
				found = true
				return fs.SkipAll
			}
			return nil
		})
		if err != nil && !errors.Is(err, fs.SkipAll) {
			return false, fmt.Errorf("scan Codex plugin cache %s: %w", root, err)
		}
		if found {
			return true, nil
		}
	}
	return false, nil
}

func createDirectoryLink(ctx context.Context, destination, source string) (string, error) {
	if err := ctx.Err(); err != nil {
		return "", err
	}
	if runtime.GOOS == "windows" {
		command := exec.CommandContext(ctx, "cmd.exe", "/d", "/c", "mklink", "/J", destination, source)
		if output, err := command.CombinedOutput(); err != nil {
			return "", fmt.Errorf("create directory junction: %w: %s", err, strings.TrimSpace(string(output)))
		}
		return "junction", nil
	}
	if err := os.Symlink(source, destination); err != nil {
		return "", err
	}
	return "symlink", nil
}
