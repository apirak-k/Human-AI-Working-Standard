package migration

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

const (
	profileName     = "legacy-migration.json"
	profileSchema   = 1
	maxProfileBytes = 16 << 10
)

var ErrProfileExists = errors.New("legacy HAWS migration is already configured")

// Profile reuses the existing legacy directories by reference. Migration does
// not copy, move, or delete any content in those directories.
type Profile struct {
	SchemaVersion  int    `json:"schema_version"`
	LegacyRoot     string `json:"legacy_root"`
	StateDir       string `json:"state_dir"`
	SecondBrainDir string `json:"second_brain_dir,omitempty"`
}

// BuildProfile validates a legacy checkout and resolves its existing data
// directories without changing them. Empty stateDir uses .haws/state; an empty
// secondBrainDir reuses secondbrain/ when present, otherwise leaves the new
// package's own Second Brain directory active.
func BuildProfile(legacyRoot, stateDir, secondBrainDir string) (Profile, error) {
	root, err := resolveDirectory(legacyRoot, "legacy HAWS checkout")
	if err != nil {
		return Profile{}, err
	}
	if err := validateLegacyCheckout(root); err != nil {
		return Profile{}, err
	}
	if stateDir == "" {
		stateDir = filepath.Join(root, ".haws", "state")
	}
	stateDir, err = resolveDirectory(stateDir, "legacy HAWS state directory")
	if err != nil {
		return Profile{}, err
	}
	if secondBrainDir == "" {
		candidate := filepath.Join(root, "secondbrain")
		if _, statErr := os.Lstat(candidate); statErr == nil {
			secondBrainDir = candidate
		} else if !errors.Is(statErr, os.ErrNotExist) {
			return Profile{}, fmt.Errorf("inspect legacy Second Brain directory: %w", statErr)
		}
	}
	if secondBrainDir != "" {
		secondBrainDir, err = resolveDirectory(secondBrainDir, "legacy Second Brain directory")
		if err != nil {
			return Profile{}, err
		}
	}
	profile := Profile{
		SchemaVersion:  profileSchema,
		LegacyRoot:     root,
		StateDir:       stateDir,
		SecondBrainDir: secondBrainDir,
	}
	if err := validateProfile(profile); err != nil {
		return Profile{}, err
	}
	return profile, nil
}

// ProfilePath returns the package-local migration reference path.
func ProfilePath(packageRoot string) string {
	return filepath.Join(packageRoot, "data", "state", profileName)
}

// SavePackageProfile records a reference profile without replacing an existing
// file. It writes only inside an owned package data directory.
func SavePackageProfile(packageRoot string, profile Profile) error {
	root, err := resolvePackageRoot(packageRoot)
	if err != nil {
		return err
	}
	if err := validateProfile(profile); err != nil {
		return err
	}
	stateDir, err := packageStateDir(root, true)
	if err != nil {
		return err
	}
	destination := filepath.Join(stateDir, profileName)
	contents, err := json.Marshal(profile)
	if err != nil {
		return fmt.Errorf("encode HAWS migration profile: %w", err)
	}
	contents = append(contents, '\n')
	temporary, err := os.CreateTemp(stateDir, ".legacy-migration-*.tmp")
	if err != nil {
		return fmt.Errorf("stage HAWS migration profile: %w", err)
	}
	temporaryPath := temporary.Name()
	defer os.Remove(temporaryPath)
	if err := temporary.Chmod(0600); err != nil {
		_ = temporary.Close()
		return fmt.Errorf("protect HAWS migration profile: %w", err)
	}
	if _, err := temporary.Write(contents); err != nil {
		_ = temporary.Close()
		return fmt.Errorf("write HAWS migration profile: %w", err)
	}
	if err := temporary.Sync(); err != nil {
		_ = temporary.Close()
		return fmt.Errorf("sync HAWS migration profile: %w", err)
	}
	if err := temporary.Close(); err != nil {
		return fmt.Errorf("close HAWS migration profile: %w", err)
	}
	if err := os.Link(temporaryPath, destination); err != nil {
		if errors.Is(err, os.ErrExist) {
			return ErrProfileExists
		}
		return fmt.Errorf("save HAWS migration profile without replacing existing data: %w", err)
	}
	return nil
}

// LoadPackageProfile returns only a valid profile stored as a regular,
// bounded file beneath the package's non-symlinked data directory.
func LoadPackageProfile(packageRoot string) (Profile, bool, error) {
	profile, exists, err := readPackageProfile(packageRoot)
	if err != nil || !exists {
		return profile, exists, err
	}
	if err := validateProfile(profile); err != nil {
		return Profile{}, false, fmt.Errorf("validate HAWS migration profile: %w", err)
	}
	return profile, true, nil
}

// LoadPackageProfileForClear reads a structurally valid reference even if its
// legacy directories are gone, so the user can recover by removing the
// package-local pointer without touching any outside data.
func LoadPackageProfileForClear(packageRoot string) (Profile, bool, error) {
	profile, exists, err := readPackageProfile(packageRoot)
	if err != nil || !exists {
		return profile, exists, err
	}
	if err := validateStoredProfileShape(profile); err != nil {
		return Profile{}, false, fmt.Errorf("validate stored HAWS migration reference: %w", err)
	}
	return profile, true, nil
}

func readPackageProfile(packageRoot string) (Profile, bool, error) {
	root, err := resolvePackageRoot(packageRoot)
	if err != nil {
		return Profile{}, false, err
	}
	stateDir, err := packageStateDir(root, false)
	if errors.Is(err, os.ErrNotExist) {
		return Profile{}, false, nil
	}
	if err != nil {
		return Profile{}, false, err
	}
	filename := filepath.Join(stateDir, profileName)
	info, err := os.Lstat(filename)
	if errors.Is(err, os.ErrNotExist) {
		return Profile{}, false, nil
	}
	if err != nil {
		return Profile{}, false, fmt.Errorf("inspect HAWS migration profile: %w", err)
	}
	if info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() || info.Size() <= 0 || info.Size() > maxProfileBytes {
		return Profile{}, false, errors.New("HAWS migration profile is not a bounded regular file")
	}
	contents, err := os.ReadFile(filename)
	if err != nil {
		return Profile{}, false, fmt.Errorf("read HAWS migration profile: %w", err)
	}
	if int64(len(contents)) > maxProfileBytes {
		return Profile{}, false, errors.New("HAWS migration profile exceeds the size limit")
	}
	decoder := json.NewDecoder(bytes.NewReader(contents))
	decoder.DisallowUnknownFields()
	var profile Profile
	if err := decoder.Decode(&profile); err != nil {
		return Profile{}, false, fmt.Errorf("decode HAWS migration profile: %w", err)
	}
	if err := decoder.Decode(new(any)); !errors.Is(err, io.EOF) {
		return Profile{}, false, errors.New("HAWS migration profile has trailing data")
	}
	return profile, true, nil
}

func validateStoredProfileShape(profile Profile) error {
	if profile.SchemaVersion != profileSchema {
		return errors.New("HAWS migration profile schema is unsupported")
	}
	for _, value := range []struct{ name, path string }{
		{"legacy HAWS checkout", profile.LegacyRoot},
		{"legacy HAWS state directory", profile.StateDir},
		{"legacy Second Brain directory", profile.SecondBrainDir},
	} {
		if value.path == "" && value.name == "legacy Second Brain directory" {
			continue
		}
		if !filepath.IsAbs(value.path) || filepath.Clean(value.path) != value.path {
			return fmt.Errorf("%s path is not a clean absolute path", value.name)
		}
	}
	return nil
}

// ClearPackageProfile removes only a valid migration reference that still
// matches the profile shown to the user during confirmation.
func ClearPackageProfile(packageRoot string, expected Profile) error {
	root, err := resolvePackageRoot(packageRoot)
	if err != nil {
		return err
	}
	current, exists, err := LoadPackageProfileForClear(root)
	if err != nil {
		return err
	}
	if !exists {
		return nil
	}
	if current != expected {
		return errors.New("HAWS migration profile changed after preview")
	}
	stateDir, err := packageStateDir(root, false)
	if err != nil {
		return err
	}
	filename := filepath.Join(stateDir, profileName)
	if err := os.Remove(filename); err != nil {
		return fmt.Errorf("remove HAWS migration profile: %w", err)
	}
	return nil
}

// ApplyProfileEnvironmentForPackage activates the selected legacy data roots
// when environment values still point at the package defaults. Explicit paths
// supplied by the user remain authoritative.
func ApplyProfileEnvironmentForPackage(profile Profile, packageRoot string) error {
	if err := validateProfile(profile); err != nil {
		return err
	}
	packageRoot, err := resolvePackageRoot(packageRoot)
	if err != nil {
		return err
	}
	defaults := map[string]string{
		"HAWS_STATE_DIR":        filepath.Join(packageRoot, "data", "state"),
		"HAWS_SECOND_BRAIN_DIR": filepath.Join(packageRoot, "data", "secondbrain"),
	}
	for _, value := range []struct{ name, path string }{
		{"HAWS_REPO_DIR", profile.LegacyRoot},
		{"HAWS_STATE_DIR", profile.StateDir},
		{"HAWS_SECOND_BRAIN_DIR", profile.SecondBrainDir},
	} {
		if value.path == "" {
			continue
		}
		current := os.Getenv(value.name)
		if current != "" && !PathsEqual(current, defaults[value.name]) {
			continue
		}
		if err := os.Setenv(value.name, value.path); err != nil {
			return fmt.Errorf("set %s from HAWS migration profile: %w", value.name, err)
		}
	}
	return nil
}

// PathsEqual compares paths after resolving their nearest existing ancestor,
// including when the final package data directory has not been created yet.
func PathsEqual(left, right string) bool {
	if left == "" || right == "" {
		return false
	}
	left = canonicalForComparison(left)
	right = canonicalForComparison(right)
	if runtime.GOOS == "windows" {
		return strings.EqualFold(left, right)
	}
	return left == right
}

func canonicalForComparison(path string) string {
	abs, err := filepath.Abs(path)
	if err != nil {
		return filepath.Clean(path)
	}
	for current := filepath.Clean(abs); ; current = filepath.Dir(current) {
		resolved, resolveErr := filepath.EvalSymlinks(current)
		if resolveErr == nil {
			remainder, relErr := filepath.Rel(current, abs)
			if relErr == nil {
				return filepath.Clean(filepath.Join(resolved, remainder))
			}
			break
		}
		parent := filepath.Dir(current)
		if parent == current {
			break
		}
	}
	return filepath.Clean(abs)
}

func validateProfile(profile Profile) error {
	if profile.SchemaVersion != profileSchema {
		return errors.New("HAWS migration profile schema is unsupported")
	}
	root, err := canonicalExistingDirectory(profile.LegacyRoot, "legacy HAWS checkout")
	if err != nil {
		return err
	}
	if root != profile.LegacyRoot {
		return errors.New("legacy HAWS checkout path changed after migration preview")
	}
	if err := validateLegacyCheckout(root); err != nil {
		return err
	}
	stateDir, err := canonicalExistingDirectory(profile.StateDir, "legacy HAWS state directory")
	if err != nil {
		return err
	}
	if stateDir != profile.StateDir {
		return errors.New("legacy HAWS state path changed after migration preview")
	}
	if profile.SecondBrainDir != "" {
		brainDir, err := canonicalExistingDirectory(profile.SecondBrainDir, "legacy Second Brain directory")
		if err != nil {
			return err
		}
		if brainDir != profile.SecondBrainDir {
			return errors.New("legacy Second Brain path changed after migration preview")
		}
	}
	return nil
}

func validateLegacyCheckout(root string) error {
	for _, name := range []string{"haws.sh", ".git"} {
		info, err := os.Lstat(filepath.Join(root, name))
		if err != nil || info.Mode()&os.ModeSymlink != 0 || (name == "haws.sh" && !info.Mode().IsRegular()) || (name == ".git" && !info.IsDir() && !info.Mode().IsRegular()) {
			return fmt.Errorf("legacy HAWS checkout is missing a regular %s", name)
		}
	}
	return nil
}

func resolveDirectory(path, label string) (string, error) {
	if strings.TrimSpace(path) == "" {
		return "", fmt.Errorf("%s path is required", label)
	}
	abs, err := filepath.Abs(path)
	if err != nil {
		return "", fmt.Errorf("resolve %s path: %w", label, err)
	}
	return canonicalExistingDirectory(abs, label)
}

func canonicalExistingDirectory(path, label string) (string, error) {
	if !filepath.IsAbs(path) {
		return "", fmt.Errorf("%s path must be absolute", label)
	}
	resolved, err := filepath.EvalSymlinks(path)
	if err != nil {
		return "", fmt.Errorf("resolve %s path: %w", label, err)
	}
	info, err := os.Lstat(resolved)
	if err != nil || info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
		return "", fmt.Errorf("%s path must be an existing regular directory", label)
	}
	return filepath.Clean(resolved), nil
}

func resolvePackageRoot(root string) (string, error) {
	abs, err := filepath.Abs(root)
	if err != nil {
		return "", fmt.Errorf("resolve HAWS package root: %w", err)
	}
	resolved, err := filepath.EvalSymlinks(abs)
	if err != nil {
		return "", fmt.Errorf("resolve HAWS package root: %w", err)
	}
	manifest := filepath.Join(resolved, "package-manifest.json")
	info, err := os.Lstat(manifest)
	if err != nil || info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() {
		return "", errors.New("HAWS migration requires a verified package root")
	}
	return resolved, nil
}

func packageStateDir(root string, create bool) (string, error) {
	current := root
	for _, part := range []string{"data", "state"} {
		current = filepath.Join(current, part)
		info, err := os.Lstat(current)
		if errors.Is(err, os.ErrNotExist) && create {
			if err := os.Mkdir(current, 0700); err != nil && !errors.Is(err, os.ErrExist) {
				return "", fmt.Errorf("create HAWS package data directory: %w", err)
			}
			info, err = os.Lstat(current)
		}
		if err != nil {
			return "", err
		}
		if info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
			return "", errors.New("HAWS package data path contains a symlink or non-directory")
		}
	}
	return current, nil
}
