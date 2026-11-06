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
	"sort"
	"strings"
)

const maxSkillOwnershipBytes = 1 << 20

type CodexSkillSyncResult struct {
	Linked        int
	AlreadyLinked int
	PluginOwned   int
	Preserved     int
	Pruned        int
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
	if err := safeCodexSkillDirectory(home, filepath.Join(home, ".agents", "skills")); err != nil {
		return result, fmt.Errorf("Codex skills directory is unsafe: %w", err)
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
	activeDestinations := make(map[string]bool, len(targets))
	for _, target := range targets {
		activeDestinations[skillPathKey(target.destination)] = true
	}

	for _, target := range targets {
		if err := ctx.Err(); err != nil {
			return result, err
		}
		if err := safeCodexSkillParent(home, target.destination); err != nil {
			return result, fmt.Errorf("Codex skill destination is unsafe: %w", err)
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
					removed, err := removeSkillOwnershipFromLedgers(target.destination, store.Dir, globalLedger)
					if err != nil {
						return result, err
					}
					if removed {
						result.Pruned++
					}
				} else {
					result.Preserved++
				}
			} else if _, err := os.Lstat(target.destination); err == nil {
				result.Preserved++
			} else if !errors.Is(err, os.ErrNotExist) {
				return result, err
			} else {
				removed, err := removeSkillOwnershipFromLedgers(target.destination, store.Dir, globalLedger)
				if err != nil {
					return result, err
				}
				if removed {
					result.Pruned++
				}
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
	pruned, preserved, err := pruneStaleCodexSkillLinks(ctx, home, activeDestinations, stateOwnership, globalOwnership, store.Dir, globalLedger)
	if err != nil {
		return result, err
	}
	result.Pruned += pruned
	result.Preserved += preserved
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

func skillPathKey(path string) string {
	path = filepath.Clean(path)
	if runtime.GOOS == "windows" {
		return strings.ToLower(path)
	}
	return path
}

func safeCodexSkillParent(home, destination string) error {
	return safeCodexSkillDirectory(home, filepath.Dir(destination))
}

func safeCodexSkillDirectory(home, directory string) error {
	home, err := filepath.Abs(home)
	if err != nil {
		return err
	}
	homeInfo, err := os.Lstat(home)
	if err != nil {
		return err
	}
	if !homeInfo.IsDir() || homeInfo.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("home is not an unlinked directory: %s", home)
	}
	directory, err = filepath.Abs(directory)
	if err != nil {
		return err
	}
	relative, err := filepath.Rel(home, directory)
	if err != nil || filepath.IsAbs(relative) || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return fmt.Errorf("skill path escapes home: %s", directory)
	}
	current := home
	for _, part := range strings.Split(relative, string(filepath.Separator)) {
		if part == "" || part == "." {
			continue
		}
		current = filepath.Join(current, part)
		info, err := os.Lstat(current)
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		if err != nil {
			return err
		}
		if info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
			return fmt.Errorf("Codex skills parent is not an unlinked directory: %s", current)
		}
	}
	return nil
}

func codexSkillDestination(home, destination string) bool {
	if !filepath.IsAbs(destination) {
		return false
	}
	root := filepath.Join(home, ".agents", "skills")
	relative, err := filepath.Rel(root, filepath.Clean(destination))
	if err != nil || filepath.IsAbs(relative) || relative == "." || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return false
	}
	return safeSkillTargetName(filepath.ToSlash(relative))
}

func pruneStaleCodexSkillLinks(ctx context.Context, home string, active map[string]bool, stateRecords, globalRecords []skillOwnershipRecord, stateDir, globalLedger string) (int, int, error) {
	pruned, preserved := 0, 0
	seen := make(map[string]string)
	for _, records := range [][]skillOwnershipRecord{stateRecords, globalRecords} {
		for _, record := range records {
			if !codexSkillDestination(home, record.path) {
				continue
			}
			key := skillPathKey(record.path)
			if active[key] {
				continue
			}
			if _, ok := seen[key]; !ok {
				seen[key] = filepath.Clean(record.path)
			}
		}
	}
	destinations := make([]string, 0, len(seen))
	for _, destination := range seen {
		destinations = append(destinations, destination)
	}
	sort.Strings(destinations)
	for _, destination := range destinations {
		if err := ctx.Err(); err != nil {
			return pruned, preserved, err
		}
		if err := safeCodexSkillParent(home, destination); err != nil {
			preserved++
			continue
		}
		record, owned, err := findSkillOwnership(destination, stateRecords, globalRecords)
		if err != nil {
			return pruned, preserved, err
		}
		if !owned {
			continue
		}
		linkTarget, isLink, err := readDirectoryLink(destination)
		if err != nil {
			return pruned, preserved, err
		}
		if isLink {
			if !skillLinkMatchesRecord(destination, linkTarget, record) {
				preserved++
				continue
			}
			if err := os.Remove(destination); err != nil {
				return pruned, preserved, fmt.Errorf("remove stale HAWS-owned Codex skill link %s: %w", destination, err)
			}
		} else if _, err := os.Lstat(destination); err == nil {
			preserved++
			continue
		} else if !errors.Is(err, os.ErrNotExist) {
			return pruned, preserved, err
		}
		removed, err := removeSkillOwnershipFromLedgers(destination, stateDir, globalLedger)
		if err != nil {
			return pruned, preserved, err
		}
		if isLink || removed {
			pruned++
		}
	}
	return pruned, preserved, nil
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
	newRecord := strings.Join([]string{"skills", kind, destination, source, source, "schema=2"}, "\t")
	_, err := updateSkillOwnershipLedger(ledger, destination, &newRecord)
	return err
}

func removeSkillOwnershipFromLedgers(destination, stateDir, globalLedger string) (bool, error) {
	stateRemoved, err := updateSkillOwnershipLedger(filepath.Join(stateDir, "ownership.tsv"), destination, nil)
	if err != nil {
		return stateRemoved, err
	}
	globalRemoved, err := updateSkillOwnershipLedger(globalLedger, destination, nil)
	return stateRemoved || globalRemoved, err
}

func updateSkillOwnershipLedger(ledger, destination string, replacement *string) (bool, error) {
	info, err := os.Lstat(ledger)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return false, fmt.Errorf("inspect skill ownership ledger %s: %w", ledger, err)
	}
	if err == nil && (!info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || info.Size() > maxSkillOwnershipBytes) {
		return false, fmt.Errorf("skill ownership ledger is not a bounded regular file: %s", ledger)
	}
	if errors.Is(err, os.ErrNotExist) && replacement == nil {
		return false, nil
	}
	var lines []string
	if err == nil {
		contents, readErr := os.ReadFile(ledger)
		if readErr != nil {
			return false, fmt.Errorf("read skill ownership ledger %s: %w", ledger, readErr)
		}
		lines = strings.Split(strings.TrimSuffix(string(contents), "\n"), "\n")
		if len(lines) == 1 && lines[0] == "" {
			lines = nil
		}
	}
	updated := make([]string, 0, len(lines)+1)
	found := false
	matched := false
	for _, line := range lines {
		fields := strings.Split(line, "\t")
		if validSkillOwnershipLine(fields) && sameSkillPath(fields[2], destination) {
			matched = true
			if replacement != nil {
				if !found {
					updated = append(updated, *replacement)
					found = true
				}
			}
			continue
		}
		updated = append(updated, line)
	}
	if replacement != nil && !found {
		updated = append(updated, *replacement)
	}
	if replacement == nil && len(updated) == len(lines) {
		return false, nil
	}
	data := []byte(strings.Join(updated, "\n") + "\n")
	if len(data) > maxSkillOwnershipBytes {
		return false, errors.New("skill ownership ledger exceeds size limit")
	}
	mode := fs.FileMode(0600)
	if err == nil {
		mode = info.Mode().Perm()
	} else if replacement != nil {
		if err := os.MkdirAll(filepath.Dir(ledger), 0700); err != nil {
			return false, fmt.Errorf("create skill ownership directory: %w", err)
		}
	}
	temporary, err := os.CreateTemp(filepath.Dir(ledger), ".skills-ownership-*.tmp")
	if err != nil {
		return false, fmt.Errorf("stage skill ownership ledger: %w", err)
	}
	tempPath := temporary.Name()
	defer os.Remove(tempPath)
	if err := temporary.Chmod(mode); err != nil {
		_ = temporary.Close()
		return false, fmt.Errorf("set skill ownership ledger mode: %w", err)
	}
	if _, err := temporary.Write(data); err != nil {
		_ = temporary.Close()
		return false, fmt.Errorf("write skill ownership ledger: %w", err)
	}
	if err := temporary.Sync(); err != nil {
		_ = temporary.Close()
		return false, fmt.Errorf("sync skill ownership ledger: %w", err)
	}
	if err := temporary.Close(); err != nil {
		return false, fmt.Errorf("close skill ownership ledger: %w", err)
	}
	if err := os.Rename(tempPath, ledger); err != nil {
		return false, fmt.Errorf("replace skill ownership ledger: %w", err)
	}
	return replacement == nil && matched, nil
}

func validSkillOwnershipLine(fields []string) bool {
	if fields[0] != "skills" || (len(fields) != 5 && !(len(fields) == 6 && fields[5] == "schema=2")) {
		return false
	}
	if fields[1] != "symlink" && fields[1] != "junction" && fields[1] != "directory-link" {
		return false
	}
	return fields[2] != "" && fields[3] != "" && fields[4] != ""
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
