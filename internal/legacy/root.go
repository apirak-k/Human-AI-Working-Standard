package legacy

import (
	"fmt"
	"os"
	"path/filepath"
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
			return preparePackageRoot(runtimeRoot)
		}
		if filepath.Base(absolute) == "runtime" && isPackageLauncher(filepath.Dir(absolute)) {
			runtimeRoot, err := validateRoot(absolute)
			if err != nil {
				return "", err
			}
			return preparePackageRoot(runtimeRoot)
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
				return preparePackageRoot(root)
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

// preparePackageRoot keeps mutable state outside the shipped runtime.
func preparePackageRoot(root string) (string, error) {
	packageDir := filepath.Dir(root)
	ceiling := packageDir
	if prior := os.Getenv("GIT_CEILING_DIRECTORIES"); prior != "" {
		ceiling += string(os.PathListSeparator) + prior
	}
	if err := os.Setenv("GIT_CEILING_DIRECTORIES", ceiling); err != nil {
		return "", err
	}
	data := filepath.Join(packageDir, "data")
	if os.Getenv("HAWS_STATE_DIR") == "" {
		if err := os.Setenv("HAWS_STATE_DIR", filepath.Join(data, "state")); err != nil {
			return "", err
		}
	}
	if os.Getenv("HAWS_SECOND_BRAIN_DIR") != "" {
		return root, nil
	}
	brain := filepath.Join(data, "secondbrain")
	if err := os.MkdirAll(brain, 0700); err != nil {
		return "", fmt.Errorf("create Second Brain data directory: %w", err)
	}
	for _, name := range []string{"ANTI_PATTERNS.md", "USER_PREFERENCES.md", "WORKFLOW.md"} {
		contents, err := os.ReadFile(filepath.Join(root, "secondbrain", name))
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
