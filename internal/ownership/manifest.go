package ownership

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
)

const (
	ManifestName    = "package-manifest.json"
	manifestSchema  = 1
	maxManifestSize = 16 << 10
	maxPackageFile  = 64 << 20
)

// ErrRunningPackage reports that package files cannot be removed while the
// base executable is the process currently running uninstall.
var ErrRunningPackage = errors.New("HAWS base package executable is currently running")

// RuntimeFiles is the bounded set of immutable resources shipped with a package.
// Mutable data is kept in the separate data directory.
var RuntimeFiles = []string{
	"haws.sh", "haws.bat", ".gitmodules", "source-revisions.tsv",
	"secondbrain/ANTI_PATTERNS.md", "secondbrain/USER_PREFERENCES.md", "secondbrain/WORKFLOW.md",
	"core/HAWS.md", "core/WORK_INSTRUCTIONS.md",
	"agents/backend-engineer.md", "agents/frontend-engineer.md", "agents/organizer.md", "agents/researcher.md", "agents/tester.md",
	"templates/AGENTS.md", "templates/ARCHITECTURE.md", "templates/CONSTRAINTS.md", "templates/DESIGN.md", "templates/HANDOFF.md", "templates/PROJECT.md",
	"ai-configs/claude/CLAUDE.md.template", "ai-configs/codex/AGENTS.override.md.template", "ai-configs/codex/agents.mjs", "ai-configs/gemini/GEMINI.md.template", "ai-configs/gemini/skills-json.mjs",
	"skills/skills.disabled", "skills/custom/README.md", "skills/custom/keyboard-layout-fixer/SKILL.md", "skills/custom/keyboard-layout-fixer/scripts/layout_fixer.mjs",
}

type Manifest struct {
	SchemaVersion int               `json:"schema_version"`
	Version       string            `json:"version"`
	Platform      string            `json:"platform"`
	Files         map[string]string `json:"files"`
}

type FileStatus struct {
	Path   string
	SHA256 string
	State  string
}

// InspectPackage verifies the app-owned manifest and fingerprints without
// following symlinks or accepting paths outside the OS package layout.
func InspectPackage(root, goos string) (Manifest, []FileStatus, error) {
	root, err := resolveRoot(root)
	if err != nil {
		return Manifest{}, nil, err
	}
	manifest, err := ReadManifest(root, goos)
	if err != nil {
		return Manifest{}, nil, err
	}
	paths := make([]string, 0, len(manifest.Files))
	for path := range manifest.Files {
		paths = append(paths, path)
	}
	sort.Strings(paths)
	statuses := make([]FileStatus, 0, len(paths))
	for _, path := range paths {
		state, err := inspectFile(root, path, manifest.Files[path])
		if err != nil {
			return Manifest{}, nil, err
		}
		statuses = append(statuses, FileStatus{Path: path, SHA256: manifest.Files[path], State: state})
	}
	return manifest, statuses, nil
}

func ReadManifest(root, goos string) (Manifest, error) {
	root, err := resolveRoot(root)
	if err != nil {
		return Manifest{}, err
	}
	manifestPath := filepath.Join(root, ManifestName)
	info, err := os.Lstat(manifestPath)
	if err != nil {
		return Manifest{}, fmt.Errorf("inspect HAWS package manifest: %w", err)
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() || info.Size() <= 0 || info.Size() > maxManifestSize {
		return Manifest{}, errors.New("HAWS package manifest is not a bounded regular file")
	}
	contents, err := os.ReadFile(manifestPath)
	if err != nil {
		return Manifest{}, fmt.Errorf("read HAWS package manifest: %w", err)
	}
	decoder := json.NewDecoder(bytes.NewReader(contents))
	decoder.DisallowUnknownFields()
	var manifest Manifest
	if err := decoder.Decode(&manifest); err != nil {
		return Manifest{}, fmt.Errorf("decode HAWS package manifest: %w", err)
	}
	if err := decoder.Decode(new(any)); !errors.Is(err, io.EOF) {
		return Manifest{}, errors.New("HAWS package manifest has trailing data")
	}
	if err := validateManifest(manifest, goos); err != nil {
		return Manifest{}, err
	}
	return manifest, nil
}

// RemovePackageFiles rechecks the manifest and every file after preview.
// Changed files and files inside symlinked directories are retained.
func RemovePackageFiles(root, goos string, expected Manifest, currentExecutable string) ([]string, []string, error) {
	root, err := resolveRoot(root)
	if err != nil {
		return nil, nil, err
	}
	current, statuses, err := InspectPackage(root, goos)
	if err != nil {
		return nil, nil, err
	}
	if !sameManifest(current, expected) {
		return nil, nil, errors.New("HAWS package ownership manifest changed after uninstall preview")
	}
	platform, _, extension, _ := packagePlatform(goos)
	for _, arch := range []string{"amd64", "arm64"} {
		binaryPath := "bin/" + platform + "-" + arch + "/haws" + extension
		if samePath(filepath.Join(root, filepath.FromSlash(binaryPath)), currentExecutable) {
			preserved := make([]string, 0, len(current.Files)+1)
			for path := range current.Files {
				preserved = append(preserved, path)
			}
			preserved = append(preserved, ManifestName+" (kept while the base application is running)")
			sort.Strings(preserved)
			return nil, preserved, ErrRunningPackage
		}
	}
	removed := make([]string, 0, len(statuses)+1)
	preserved := make([]string, 0)
	var failures []error
	for _, status := range statuses {
		switch status.State {
		case "missing":
			continue
		case "owned":
			path := filepath.Join(root, filepath.FromSlash(status.Path))
			if err := os.Remove(path); err != nil {
				if !errors.Is(err, os.ErrNotExist) {
					preserved = append(preserved, status.Path)
					failures = append(failures, fmt.Errorf("remove owned HAWS package file %s: %w", status.Path, err))
				}
			} else {
				removed = append(removed, status.Path)
			}
		default:
			preserved = append(preserved, status.Path)
		}
	}
	for _, directory := range packageDirectories(current) {
		path := filepath.Join(root, filepath.FromSlash(directory))
		exists, safe, statErr := inspectOwnedDirectoryPath(root, directory)
		if errors.Is(statErr, os.ErrNotExist) {
			continue
		}
		if statErr != nil {
			preserved = append(preserved, directory+" (could not inspect)")
			failures = append(failures, fmt.Errorf("inspect owned HAWS package directory %s: %w", directory, statErr))
			continue
		}
		if !exists {
			continue
		}
		if !safe {
			preserved = append(preserved, directory+" (symlinked or unowned parent)")
			continue
		}
		entries, readErr := os.ReadDir(path)
		if readErr != nil {
			preserved = append(preserved, directory+" (could not inspect)")
			failures = append(failures, fmt.Errorf("inspect owned HAWS package directory %s: %w", directory, readErr))
			continue
		}
		if len(entries) > 0 {
			preserved = append(preserved, directory+" (contains unowned files)")
			continue
		}
		// Recheck all components immediately before removal so a swapped
		// symlinked parent cannot redirect this operation outside the package.
		exists, safe, statErr = inspectOwnedDirectoryPath(root, directory)
		if errors.Is(statErr, os.ErrNotExist) {
			continue
		}
		if statErr != nil {
			preserved = append(preserved, directory+" (could not inspect)")
			failures = append(failures, fmt.Errorf("recheck owned HAWS package directory %s: %w", directory, statErr))
			continue
		}
		if !exists {
			continue
		}
		if !safe {
			preserved = append(preserved, directory+" (symlinked or unowned parent)")
			continue
		}
		if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
			preserved = append(preserved, directory+" (could not remove)")
			failures = append(failures, fmt.Errorf("remove empty HAWS package directory %s: %w", directory, err))
		}
	}
	if len(preserved) == 0 {
		manifestPath := filepath.Join(root, ManifestName)
		info, statErr := os.Lstat(manifestPath)
		if statErr == nil && info.Mode().IsRegular() && info.Mode()&os.ModeSymlink == 0 {
			if removeErr := os.Remove(manifestPath); removeErr == nil {
				removed = append(removed, ManifestName)
			} else if !errors.Is(removeErr, os.ErrNotExist) {
				preserved = append(preserved, ManifestName)
				failures = append(failures, fmt.Errorf("remove HAWS package manifest: %w", removeErr))
			}
		} else if statErr != nil && !errors.Is(statErr, os.ErrNotExist) {
			preserved = append(preserved, ManifestName)
		} else if statErr == nil {
			preserved = append(preserved, ManifestName)
		}
	} else {
		preserved = append(preserved, ManifestName+" (kept for remaining package files)")
	}
	sort.Strings(removed)
	sort.Strings(preserved)
	return removed, preserved, errors.Join(failures...)
}

func validateManifest(manifest Manifest, goos string) error {
	platform, launcher, extension, err := packagePlatform(goos)
	if err != nil {
		return err
	}
	if manifest.SchemaVersion != manifestSchema || manifest.Platform != platform || !validVersion(manifest.Version) {
		return errors.New("HAWS package manifest identity is invalid")
	}
	expected := map[string]bool{
		"README.txt": true,
		launcher:     true,
		"bin/" + platform + "-amd64/haws" + extension: true,
		"bin/" + platform + "-arm64/haws" + extension: true,
	}
	for _, file := range RuntimeFiles {
		expected["runtime/"+file] = true
	}
	if len(manifest.Files) < 4 {
		return errors.New("HAWS package manifest has an invalid file list")
	}
	for _, required := range []string{"README.txt", launcher, "bin/" + platform + "-amd64/haws" + extension, "bin/" + platform + "-arm64/haws" + extension} {
		if _, ok := manifest.Files[required]; !ok {
			return errors.New("HAWS package manifest is missing a required file")
		}
	}
	for path, fingerprint := range manifest.Files {
		if !expected[path] || !isSHA256Hex(fingerprint) {
			return fmt.Errorf("HAWS package manifest contains an invalid file record %q", path)
		}
	}
	return nil
}

func inspectFile(root, relative, expectedHash string) (string, error) {
	if strings.Contains(relative, "\\") || filepath.IsAbs(relative) || strings.Contains(relative, "..") {
		return "unowned", nil
	}
	path := filepath.Join(root, filepath.FromSlash(relative))
	parts := strings.Split(filepath.FromSlash(relative), string(filepath.Separator))
	current := root
	for index, part := range parts {
		current = filepath.Join(current, part)
		info, err := os.Lstat(current)
		if errors.Is(err, os.ErrNotExist) {
			return "missing", nil
		}
		if err != nil {
			return "unowned", nil
		}
		if info.Mode()&os.ModeSymlink != 0 {
			return "unowned", nil
		}
		if index < len(parts)-1 && !info.IsDir() {
			return "unowned", nil
		}
		if index == len(parts)-1 && (!info.Mode().IsRegular() || info.Size() > maxPackageFile) {
			return "unowned", nil
		}
	}
	file, err := os.Open(path)
	if err != nil {
		return "unowned", nil
	}
	hash := sha256.New()
	_, copyErr := io.Copy(hash, io.LimitReader(file, maxPackageFile+1))
	closeErr := file.Close()
	if copyErr != nil || closeErr != nil {
		return "unowned", nil
	}
	if hex.EncodeToString(hash.Sum(nil)) != strings.ToLower(expectedHash) {
		return "changed", nil
	}
	return "owned", nil
}

// inspectOwnedDirectoryPath refuses to follow symlinks or non-directory
// ancestors while checking a package directory that may be removed.
func inspectOwnedDirectoryPath(root, relative string) (exists, safe bool, err error) {
	clean := path.Clean(relative)
	if clean == "." || clean == ".." || strings.HasPrefix(clean, "../") || path.IsAbs(relative) || strings.Contains(relative, "\\") {
		return false, false, errors.New("package directory path is invalid")
	}
	rootInfo, err := os.Lstat(root)
	if errors.Is(err, os.ErrNotExist) {
		return false, false, nil
	}
	if err != nil {
		return false, false, err
	}
	if rootInfo.Mode()&os.ModeSymlink != 0 || !rootInfo.IsDir() {
		return true, false, nil
	}
	current := root
	for _, part := range strings.Split(clean, "/") {
		current = filepath.Join(current, part)
		info, statErr := os.Lstat(current)
		if errors.Is(statErr, os.ErrNotExist) {
			return false, false, nil
		}
		if statErr != nil {
			return false, false, statErr
		}
		if info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
			return true, false, nil
		}
	}
	return true, true, nil
}

func packageDirectories(manifest Manifest) []string {
	seen := make(map[string]struct{})
	for filename := range manifest.Files {
		directory := path.Dir(filename)
		for directory != "." && directory != "/" && directory != "" {
			seen[directory] = struct{}{}
			parent := path.Dir(directory)
			if parent == directory {
				break
			}
			directory = parent
		}
	}
	directories := make([]string, 0, len(seen))
	for directory := range seen {
		directories = append(directories, directory)
	}
	sort.Slice(directories, func(i, j int) bool {
		leftDepth := strings.Count(directories[i], "/")
		rightDepth := strings.Count(directories[j], "/")
		if leftDepth != rightDepth {
			return leftDepth > rightDepth
		}
		return directories[i] < directories[j]
	})
	return directories
}

func packagePlatform(goos string) (string, string, string, error) {
	switch goos {
	case "windows":
		return "windows", "haws.bat", ".exe", nil
	case "darwin", "macos":
		return "macos", "haws.command", "", nil
	case "linux":
		return "linux", "haws.sh", "", nil
	default:
		return "", "", "", fmt.Errorf("unsupported HAWS package platform %q", goos)
	}
}

func resolveRoot(root string) (string, error) {
	if strings.TrimSpace(root) == "" {
		return "", errors.New("HAWS package directory is required")
	}
	absolute, err := filepath.Abs(root)
	if err != nil {
		return "", fmt.Errorf("resolve HAWS package directory: %w", err)
	}
	resolved, err := filepath.EvalSymlinks(absolute)
	if err != nil {
		return "", fmt.Errorf("resolve HAWS package directory: %w", err)
	}
	info, err := os.Stat(resolved)
	if err != nil || !info.IsDir() {
		return "", errors.New("HAWS package path is not a directory")
	}
	return resolved, nil
}

func validVersion(value string) bool {
	if value == "" {
		return false
	}
	for index, char := range value {
		if char > 127 || index == 0 && !isASCIIAlphaNumeric(byte(char)) {
			return false
		}
		if !isASCIIAlphaNumeric(byte(char)) && char != '.' && char != '_' && char != '+' && char != '-' {
			return false
		}
	}
	return true
}

func isASCIIAlphaNumeric(value byte) bool {
	return value >= 'a' && value <= 'z' || value >= 'A' && value <= 'Z' || value >= '0' && value <= '9'
}

func isSHA256Hex(value string) bool {
	if len(value) != sha256.Size*2 {
		return false
	}
	_, err := hex.DecodeString(value)
	return err == nil
}

func sameManifest(left, right Manifest) bool {
	if left.SchemaVersion != right.SchemaVersion || left.Version != right.Version || left.Platform != right.Platform || len(left.Files) != len(right.Files) {
		return false
	}
	for path, hash := range left.Files {
		if right.Files[path] != hash {
			return false
		}
	}
	return true
}

func samePath(left, right string) bool {
	if right == "" {
		return false
	}
	leftAbs, leftErr := filepath.Abs(left)
	rightAbs, rightErr := filepath.Abs(right)
	if leftErr != nil || rightErr != nil {
		return false
	}
	leftResolved, err := filepath.EvalSymlinks(leftAbs)
	if err == nil {
		leftAbs = leftResolved
	}
	rightResolved, err := filepath.EvalSymlinks(rightAbs)
	if err == nil {
		rightAbs = rightResolved
	}
	if runtime.GOOS == "windows" {
		return strings.EqualFold(filepath.Clean(leftAbs), filepath.Clean(rightAbs))
	}
	return filepath.Clean(leftAbs) == filepath.Clean(rightAbs)
}
