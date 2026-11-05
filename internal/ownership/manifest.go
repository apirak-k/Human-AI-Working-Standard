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
	fingerprint   string
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
	digest := sha256.Sum256(contents)
	manifest.fingerprint = hex.EncodeToString(digest[:])
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
			wasRemoved, currentState, removeErr := removeOwnedPackageFile(root, status.Path, status.SHA256)
			if removeErr != nil {
				preserved = append(preserved, status.Path)
				failures = append(failures, fmt.Errorf("remove owned HAWS package file %s: %w", status.Path, removeErr))
			} else if wasRemoved {
				removed = append(removed, status.Path)
			} else if currentState != "missing" {
				preserved = append(preserved, status.Path)
			}
		default:
			preserved = append(preserved, status.Path)
		}
	}
	for _, directory := range packageDirectories(current) {
		removed, reason, removeErr := removeEmptyPackageDirectory(root, directory)
		if removeErr != nil {
			if reason == "" {
				reason = "could not remove"
			}
			preserved = append(preserved, directory+" ("+reason+")")
			failures = append(failures, fmt.Errorf("remove empty HAWS package directory %s: %w", directory, removeErr))
		} else if !removed && reason != "" {
			preserved = append(preserved, directory+" ("+reason+")")
		}
	}
	if len(preserved) == 0 {
		manifestRemoved, state, removeErr := removeOwnedPackageFile(root, ManifestName, current.fingerprint)
		if removeErr != nil {
			preserved = append(preserved, ManifestName)
			failures = append(failures, fmt.Errorf("remove HAWS package manifest: %w", removeErr))
		} else if manifestRemoved {
			removed = append(removed, ManifestName)
		} else if state != "missing" {
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

func removeEmptyPackageDirectory(root, relative string) (bool, string, error) {
	return removeEmptyPackageDirectoryWithHook(root, relative, nil)
}

// removeEmptyPackageDirectoryWithHook removes an empty package directory by
// retaining and revalidating directory handles for every path component. The
// hook exists only so tests can exercise a parent replacement between checks.
func removeEmptyPackageDirectoryWithHook(root, relative string, beforeRemove func()) (bool, string, error) {
	parts, err := safePackagePathParts(relative)
	if err != nil || len(parts) == 0 {
		return false, "", errors.New("package directory path is invalid")
	}
	rootHandle, exists, safe, err := openVerifiedPackageRoot(root)
	if err != nil {
		return false, "could not inspect", err
	}
	if !exists {
		return false, "", nil
	}
	if !safe {
		return false, "symlinked or unowned parent", nil
	}
	defer rootHandle.Close()

	parentParts := parts[:len(parts)-1]
	name := parts[len(parts)-1]
	parent, parents, parentInfos, reason, err := openPackageDirectoryParent(rootHandle, parentParts, nil)
	if err != nil || reason != "" || parent == nil {
		closeRoots(parents)
		return false, reason, err
	}
	finalInfo, err := parent.Lstat(name)
	if errors.Is(err, os.ErrNotExist) {
		closeRoots(parents)
		return false, "", nil
	}
	if err != nil {
		closeRoots(parents)
		return false, "could not inspect", err
	}
	if finalInfo.Mode()&os.ModeSymlink != 0 || !finalInfo.IsDir() {
		closeRoots(parents)
		return false, "symlinked or unowned parent", nil
	}
	finalHandle, err := parent.OpenRoot(name)
	if err != nil {
		closeRoots(parents)
		return false, "could not inspect", err
	}
	finalHandleInfo, err := finalHandle.Stat(".")
	if err != nil || !os.SameFile(finalInfo, finalHandleInfo) {
		_ = finalHandle.Close()
		closeRoots(parents)
		if err != nil {
			return false, "could not inspect", err
		}
		return false, "symlinked or unowned parent", nil
	}
	finalAfterOpen, err := parent.Lstat(name)
	if err != nil || finalAfterOpen.Mode()&os.ModeSymlink != 0 || !os.SameFile(finalInfo, finalAfterOpen) {
		_ = finalHandle.Close()
		closeRoots(parents)
		if err != nil && !errors.Is(err, os.ErrNotExist) {
			return false, "could not inspect", err
		}
		return false, "symlinked or unowned parent", nil
	}
	directory, err := finalHandle.Open(".")
	if err != nil {
		_ = finalHandle.Close()
		closeRoots(parents)
		return false, "could not inspect", err
	}
	entries, readErr := directory.ReadDir(-1)
	closeErr := directory.Close()
	_ = finalHandle.Close()
	closeRoots(parents)
	if readErr != nil {
		return false, "could not inspect", readErr
	}
	if closeErr != nil {
		return false, "could not inspect", closeErr
	}
	if len(entries) > 0 {
		return false, "contains unowned files", nil
	}
	if beforeRemove != nil {
		beforeRemove()
	}

	// Reopen the same parents from the package root and compare each identity
	// before removing the final component through the retained parent handle.
	currentParent, currentParents, _, reason, err := openPackageDirectoryParent(rootHandle, parentParts, parentInfos)
	if err != nil || reason != "" || currentParent == nil {
		closeRoots(currentParents)
		return false, reason, err
	}
	defer closeRoots(currentParents)
	currentFinal, err := currentParent.Lstat(name)
	if errors.Is(err, os.ErrNotExist) {
		return false, "", nil
	}
	if err != nil {
		return false, "could not inspect", err
	}
	if currentFinal.Mode()&os.ModeSymlink != 0 || !currentFinal.IsDir() || !os.SameFile(finalInfo, currentFinal) {
		return false, "symlinked or unowned parent", nil
	}
	if err := currentParent.Remove(name); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return false, "", nil
		}
		return false, "could not remove", err
	}
	return true, "", nil
}

func removeOwnedPackageFile(root, relative, expectedHash string) (bool, string, error) {
	return removeOwnedPackageFileWithHook(root, relative, expectedHash, nil)
}

func removeOwnedPackageFileWithHook(root, relative, expectedHash string, beforeRemove func()) (bool, string, error) {
	parts, err := safePackagePathParts(relative)
	if err != nil || len(parts) == 0 {
		return false, "unowned", errors.New("package file path is invalid")
	}
	rootHandle, exists, safe, err := openVerifiedPackageRoot(root)
	if err != nil {
		return false, "unowned", err
	}
	if !exists {
		return false, "missing", nil
	}
	if !safe {
		return false, "unowned", nil
	}
	defer rootHandle.Close()

	parentParts := parts[:len(parts)-1]
	name := parts[len(parts)-1]
	parent, parents, parentInfos, reason, err := openPackageDirectoryParent(rootHandle, parentParts, nil)
	if err != nil || reason != "" || parent == nil {
		closeRoots(parents)
		if err == nil && reason == "" && parent == nil {
			return false, "missing", nil
		}
		return false, "unowned", err
	}
	defer closeRoots(parents)
	initialInfo, state, err := inspectOwnedFileAt(parent, name, expectedHash)
	if err != nil || state != "owned" {
		return false, state, err
	}
	if beforeRemove != nil {
		beforeRemove()
	}

	currentParent, currentParents, _, reason, err := openPackageDirectoryParent(rootHandle, parentParts, parentInfos)
	if err != nil || reason != "" || currentParent == nil {
		closeRoots(currentParents)
		return false, "unowned", err
	}
	defer closeRoots(currentParents)
	currentInfo, state, err := inspectOwnedFileAt(currentParent, name, expectedHash)
	if err != nil || state != "owned" || !os.SameFile(initialInfo, currentInfo) {
		if err == nil && state == "owned" {
			state = "unowned"
		}
		return false, state, err
	}
	latestInfo, err := currentParent.Lstat(name)
	if errors.Is(err, os.ErrNotExist) {
		return false, "missing", nil
	}
	if err != nil {
		return false, "unowned", err
	}
	if latestInfo.Mode()&os.ModeSymlink != 0 || !latestInfo.Mode().IsRegular() || !os.SameFile(currentInfo, latestInfo) {
		return false, "unowned", nil
	}
	if err := currentParent.Remove(name); err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return false, "missing", nil
		}
		return false, "unowned", err
	}
	return true, "missing", nil
}

func inspectOwnedFileAt(parent *os.Root, name, expectedHash string) (os.FileInfo, string, error) {
	info, err := parent.Lstat(name)
	if errors.Is(err, os.ErrNotExist) {
		return nil, "missing", nil
	}
	if err != nil {
		return nil, "unowned", err
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() || info.Size() > maxPackageFile {
		return nil, "unowned", nil
	}
	file, err := parent.Open(name)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil, "missing", nil
		}
		return nil, "unowned", err
	}
	openedInfo, statErr := file.Stat()
	if statErr != nil || !os.SameFile(info, openedInfo) {
		_ = file.Close()
		if statErr != nil {
			return nil, "unowned", statErr
		}
		return nil, "unowned", nil
	}
	hash := sha256.New()
	_, copyErr := io.Copy(hash, io.LimitReader(file, maxPackageFile+1))
	closeErr := file.Close()
	if copyErr != nil {
		return nil, "unowned", copyErr
	}
	if closeErr != nil {
		return nil, "unowned", closeErr
	}
	if hex.EncodeToString(hash.Sum(nil)) != strings.ToLower(expectedHash) {
		return nil, "changed", nil
	}
	return info, "owned", nil
}

func safePackagePathParts(relative string) ([]string, error) {
	clean := path.Clean(relative)
	if clean == "." || clean == ".." || strings.HasPrefix(clean, "../") || clean != relative || path.IsAbs(relative) || strings.Contains(relative, "\\") {
		return nil, errors.New("package path is invalid")
	}
	return strings.Split(clean, "/"), nil
}

func openVerifiedPackageRoot(root string) (*os.Root, bool, bool, error) {
	rootInfo, err := os.Lstat(root)
	if errors.Is(err, os.ErrNotExist) {
		return nil, false, false, nil
	}
	if err != nil {
		return nil, true, false, err
	}
	if rootInfo.Mode()&os.ModeSymlink != 0 || !rootInfo.IsDir() {
		return nil, true, false, nil
	}
	rootHandle, err := os.OpenRoot(root)
	if err != nil {
		return nil, true, false, err
	}
	openedRootInfo, err := rootHandle.Stat(".")
	if err != nil {
		_ = rootHandle.Close()
		return nil, true, false, err
	}
	rootAfterOpen, err := os.Lstat(root)
	if err != nil {
		_ = rootHandle.Close()
		if errors.Is(err, os.ErrNotExist) {
			return nil, false, false, nil
		}
		return nil, true, false, err
	}
	if rootAfterOpen.Mode()&os.ModeSymlink != 0 || !os.SameFile(rootInfo, openedRootInfo) || !os.SameFile(rootInfo, rootAfterOpen) {
		_ = rootHandle.Close()
		return nil, true, false, nil
	}
	return rootHandle, true, true, nil
}

func openPackageDirectoryParent(root *os.Root, components []string, expected []os.FileInfo) (*os.Root, []*os.Root, []os.FileInfo, string, error) {
	parent := root
	opened := make([]*os.Root, 0, len(components))
	infos := make([]os.FileInfo, 0, len(components))
	for index, component := range components {
		info, err := parent.Lstat(component)
		if errors.Is(err, os.ErrNotExist) {
			return nil, opened, infos, "", nil
		}
		if err != nil {
			return nil, opened, infos, "could not inspect", err
		}
		if info.Mode()&os.ModeSymlink != 0 || !info.IsDir() || expected != nil && !os.SameFile(info, expected[index]) {
			return nil, opened, infos, "symlinked or unowned parent", nil
		}
		child, err := parent.OpenRoot(component)
		if err != nil {
			return nil, opened, infos, "could not inspect", err
		}
		openedInfo, err := child.Stat(".")
		if err != nil || !os.SameFile(info, openedInfo) {
			_ = child.Close()
			if err != nil {
				return nil, opened, infos, "could not inspect", err
			}
			return nil, opened, infos, "symlinked or unowned parent", nil
		}
		afterOpen, err := parent.Lstat(component)
		if err != nil || afterOpen.Mode()&os.ModeSymlink != 0 || !os.SameFile(info, afterOpen) {
			_ = child.Close()
			if err != nil && !errors.Is(err, os.ErrNotExist) {
				return nil, opened, infos, "could not inspect", err
			}
			return nil, opened, infos, "symlinked or unowned parent", nil
		}
		opened = append(opened, child)
		infos = append(infos, info)
		parent = child
	}
	return parent, opened, infos, "", nil
}

func closeRoots(roots []*os.Root) {
	for index := len(roots) - 1; index >= 0; index-- {
		_ = roots[index].Close()
	}
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
	if left.SchemaVersion != right.SchemaVersion || left.Version != right.Version || left.Platform != right.Platform || left.fingerprint != right.fingerprint || len(left.Files) != len(right.Files) {
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
