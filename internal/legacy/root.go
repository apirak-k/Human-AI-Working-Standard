package legacy

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

func FindRoot() (string, error) {
	if root := os.Getenv("HAWS_ROOT"); root != "" {
		absolute, err := filepath.Abs(root)
		if err != nil {
			return "", err
		}
		if isPackageLauncher(absolute) {
			runtimeRoot, err := validateRoot(filepath.Join(absolute, "runtime"))
			if err != nil {
				return "", err
			}
			return ConfigurePackageRuntime(absolute, runtimeRoot)
		}
		if filepath.Base(absolute) == "runtime" && isPackageLauncher(filepath.Dir(absolute)) {
			runtimeRoot, err := validateRoot(absolute)
			if err != nil {
				return "", err
			}
			return ConfigurePackageRuntime(filepath.Dir(absolute), runtimeRoot)
		}
		if packageDir := os.Getenv("HAWS_PACKAGE_DIR"); packageDir != "" {
			return preparePackageRootAt(absolute, packageDir)
		}
		return validateRoot(root)
	}
	cwd, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("find HAWS checkout from current directory: %w", err)
	}
	executable, _ := os.Executable()
	// Prefer the runtime shipped with the executable over an unrelated cwd.
	if executable != "" {
		for dir := filepath.Dir(executable); ; dir = filepath.Dir(dir) {
			candidate := filepath.Join(dir, "runtime")
			if root, err := validateRoot(candidate); err == nil && isPackageLauncher(dir) {
				return ConfigurePackageRuntime(dir, root)
			}
			if filepath.Dir(dir) == dir {
				break
			}
		}
	}
	starts := []string{cwd}
	if executable != "" {
		starts = append(starts, filepath.Dir(executable))
	}
	seen := make(map[string]bool)
	for _, start := range starts {
		for dir := start; ; dir = filepath.Dir(dir) {
			if seen[dir] {
				break
			}
			seen[dir] = true
			if fileInfo, err := os.Stat(filepath.Join(dir, "haws.sh")); err == nil && !fileInfo.IsDir() && !isPackageLauncher(dir) {
				return dir, nil
			}
			parent := filepath.Dir(dir)
			if parent == dir {
				break
			}
		}
	}
	return "", fmt.Errorf("could not find a HAWS checkout containing haws.sh; set HAWS_ROOT")
}

func validateRoot(root string) (string, error) {
	absolute, err := filepath.Abs(root)
	if err != nil {
		return "", fmt.Errorf("resolve HAWS root %q: %w", root, err)
	}
	info, err := os.Stat(filepath.Join(absolute, "haws.sh"))
	if err != nil || info.IsDir() {
		return "", fmt.Errorf("HAWS root %q does not contain haws.sh", absolute)
	}
	return absolute, nil
}

// A package launcher named haws.sh is not the legacy shell runtime.
func isPackageLauncher(dir string) bool {
	info, err := os.Stat(filepath.Join(dir, "package-manifest.json"))
	return err == nil && info.Mode().IsRegular()
}

// ConfigurePackageRuntime selects a validated packaged runtime while keeping
// package data and Git discovery boundaries at the stable package directory.
func ConfigurePackageRuntime(packageDir, runtimeRoot string) (string, error) {
	packageAbs, err := filepath.Abs(packageDir)
	if err != nil {
		return "", fmt.Errorf("resolve HAWS package directory: %w", err)
	}
	packageAbs, err = filepath.EvalSymlinks(packageAbs)
	if err != nil {
		return "", fmt.Errorf("resolve HAWS package directory: %w", err)
	}
	manifestInfo, err := os.Lstat(filepath.Join(packageAbs, "package-manifest.json"))
	if err != nil || manifestInfo.Mode()&os.ModeSymlink != 0 || !manifestInfo.Mode().IsRegular() {
		return "", errors.New("HAWS package directory has no package manifest")
	}
	runtimeAbs, err := validateRoot(runtimeRoot)
	if err != nil {
		return "", err
	}
	runtimeInfo, err := os.Lstat(runtimeAbs)
	if err != nil || runtimeInfo.Mode()&os.ModeSymlink != 0 || !runtimeInfo.IsDir() {
		return "", errors.New("HAWS runtime path is not a regular directory")
	}
	launcherInfo, err := os.Lstat(filepath.Join(runtimeAbs, "haws.sh"))
	if err != nil || launcherInfo.Mode()&os.ModeSymlink != 0 || !launcherInfo.Mode().IsRegular() {
		return "", errors.New("HAWS runtime entrypoint is not a regular file")
	}
	resolvedRuntime, err := filepath.EvalSymlinks(runtimeAbs)
	if err != nil {
		return "", fmt.Errorf("resolve HAWS runtime path: %w", err)
	}
	runtimeAbs = resolvedRuntime
	relative, err := filepath.Rel(packageAbs, runtimeAbs)
	if err != nil || !validPackageRuntimeRelative(relative) {
		return "", errors.New("HAWS runtime is outside the package's owned runtime locations")
	}
	current := packageAbs
	for _, part := range strings.Split(filepath.Clean(relative), string(filepath.Separator)) {
		current = filepath.Join(current, part)
		info, err := os.Lstat(current)
		if err != nil || info.Mode()&os.ModeSymlink != 0 {
			return "", errors.New("HAWS runtime path contains a symbolic link or missing directory")
		}
	}
	if err := os.Setenv("HAWS_APP_DIR", packageAbs); err != nil {
		return "", err
	}
	if err := os.Setenv("HAWS_PACKAGE_DIR", packageAbs); err != nil {
		return "", err
	}
	if err := os.Setenv("HAWS_ROOT", runtimeAbs); err != nil {
		return "", err
	}
	return preparePackageRootAt(runtimeAbs, packageAbs)
}

func validPackageRuntimeRelative(relative string) bool {
	if relative == "runtime" {
		return true
	}
	parts := strings.Split(filepath.Clean(relative), string(filepath.Separator))
	return len(parts) == 3 && parts[0] == "versions" && parts[1] != "" && parts[1] != "." && parts[1] != ".." && parts[2] == "runtime"
}

// preparePackageRoot keeps mutable state outside the shipped runtime.
func preparePackageRoot(root string) (string, error) {
	return preparePackageRootAt(root, filepath.Dir(root))
}

func preparePackageRootAt(root, packageDir string) (string, error) {
	var err error
	packageDir, err = filepath.Abs(packageDir)
	if err != nil {
		return "", fmt.Errorf("resolve HAWS package directory: %w", err)
	}
	ceilingPaths := []string{packageDir}
	seenCeilingPaths := map[string]bool{filepath.Clean(packageDir): true}
	for _, prior := range strings.Split(os.Getenv("GIT_CEILING_DIRECTORIES"), string(os.PathListSeparator)) {
		if prior == "" {
			continue
		}
		clean := filepath.Clean(prior)
		if seenCeilingPaths[clean] {
			continue
		}
		seenCeilingPaths[clean] = true
		ceilingPaths = append(ceilingPaths, prior)
	}
	if err := os.Setenv("GIT_CEILING_DIRECTORIES", strings.Join(ceilingPaths, string(os.PathListSeparator))); err != nil {
		return "", err
	}
	data := filepath.Join(packageDir, "data")
	if os.Getenv("HAWS_STATE_DIR") == "" {
		if err := os.Setenv("HAWS_STATE_DIR", filepath.Join(data, "state")); err != nil {
			return "", err
		}
	} else if !filepath.IsAbs(os.Getenv("HAWS_STATE_DIR")) {
		stateDir := filepath.Join(packageDir, os.Getenv("HAWS_STATE_DIR"))
		if err := os.Setenv("HAWS_STATE_DIR", stateDir); err != nil {
			return "", err
		}
	}
	stateDir := os.Getenv("HAWS_STATE_DIR")
	if os.Getenv("HAWS_DISABLED_ENVIRONMENTS_FILE") == "" {
		disabledFile := filepath.Join(stateDir, "environments.disabled")
		if err := migratePackageCompatibilitySettings(root, packageDir, disabledFile); err != nil {
			return "", err
		}
		if err := os.Setenv("HAWS_DISABLED_ENVIRONMENTS_FILE", disabledFile); err != nil {
			return "", err
		}
	}
	if os.Getenv("HAWS_SECOND_BRAIN_DIR") != "" {
		return root, nil
	}
	brain := filepath.Join(data, "secondbrain")
	if err := ensurePackageDirectory(packageDir, filepath.Join("data", "secondbrain")); err != nil {
		return "", fmt.Errorf("create Second Brain data directory: %w", err)
	}
	for _, name := range []string{"ANTI_PATTERNS.md", "USER_PREFERENCES.md", "WORKFLOW.md"} {
		seed := filepath.Join(root, "secondbrain", name)
		info, err := os.Lstat(seed)
		if err != nil || info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() || info.Size() <= 0 || info.Size() > maxPackageSettingsBytes {
			return "", fmt.Errorf("Second Brain seed %q is not a bounded regular file", name)
		}
		contents, err := os.ReadFile(seed)
		if err != nil {
			return "", fmt.Errorf("read Second Brain seed: %w", err)
		}
		if err := writeSeed(filepath.Join(brain, name), contents); err != nil {
			return "", err
		}
	}
	if err := os.Setenv("HAWS_SECOND_BRAIN_DIR", brain); err != nil {
		return "", err
	}
	return root, nil
}

func ensurePackageDirectory(packageDir, relative string) error {
	if filepath.IsAbs(relative) || filepath.Clean(relative) == "." || filepath.Clean(relative) == ".." || strings.HasPrefix(filepath.Clean(relative), ".."+string(filepath.Separator)) {
		return errors.New("package data directory path is unsafe")
	}
	current := packageDir
	for _, part := range strings.Split(filepath.Clean(relative), string(filepath.Separator)) {
		current = filepath.Join(current, part)
		info, err := os.Lstat(current)
		if os.IsNotExist(err) {
			if err := os.Mkdir(current, 0700); err != nil && !os.IsExist(err) {
				return err
			}
			info, err = os.Lstat(current)
		}
		if err != nil {
			return err
		}
		if info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
			return errors.New("package data path contains a symlink or non-directory")
		}
	}
	return nil
}

func migratePackageCompatibilitySettings(runtimeRoot, packageDir, destination string) error {
	if info, err := os.Lstat(destination); err == nil {
		if info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() || info.Size() > maxPackageSettingsBytes {
			return errors.New("packaged AI environment settings are not a bounded regular file")
		}
		return nil
	} else if !os.IsNotExist(err) {
		return fmt.Errorf("inspect packaged AI environment settings: %w", err)
	}
	candidates := []string{
		filepath.Join(runtimeRoot, "ai-configs", "environments.disabled"),
		filepath.Join(runtimeRoot, "config", "environments.disabled"),
		filepath.Join(runtimeRoot, "environments.disabled"),
		filepath.Join(packageDir, "runtime", "ai-configs", "environments.disabled"),
		filepath.Join(packageDir, "runtime", "config", "environments.disabled"),
		filepath.Join(packageDir, "runtime", "environments.disabled"),
	}
	seen := make(map[string]bool, len(candidates))
	for _, candidate := range candidates {
		clean := filepath.Clean(candidate)
		if seen[clean] {
			continue
		}
		seen[clean] = true
		info, err := os.Lstat(candidate)
		if os.IsNotExist(err) {
			continue
		}
		if err != nil {
			return fmt.Errorf("inspect prior AI environment settings: %w", err)
		}
		if info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular() || info.Size() > maxPackageSettingsBytes {
			return errors.New("prior AI environment settings are not a bounded regular file")
		}
		contents, err := os.ReadFile(candidate)
		if err != nil {
			return fmt.Errorf("read prior AI environment settings: %w", err)
		}
		if int64(len(contents)) > maxPackageSettingsBytes {
			return errors.New("prior AI environment settings exceed the size limit")
		}
		if err := os.MkdirAll(filepath.Dir(destination), 0700); err != nil {
			return fmt.Errorf("create HAWS state directory: %w", err)
		}
		if err := writeSeed(destination, contents); err != nil {
			return fmt.Errorf("preserve prior AI environment settings: %w", err)
		}
		return nil
	}
	return nil
}

const maxPackageSettingsBytes = 1 << 20

// Publish a complete seed only if the user has not already created it.
func writeSeed(destination string, contents []byte) error {
	file, err := os.CreateTemp(filepath.Dir(destination), ".haws-seed-*")
	if err != nil {
		return err
	}
	defer os.Remove(file.Name())
	if _, err := file.Write(contents); err != nil {
		_ = file.Close()
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	if err := os.Link(file.Name(), destination); err != nil && !os.IsExist(err) {
		return err
	}
	return nil
}
