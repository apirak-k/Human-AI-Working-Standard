// Command haws-dev runs the current HAWS source in a persistent, isolated
// development sandbox. It is a developer entry point, not part of releases.
package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
)

const sandboxMarker = ".haws-dev-sandbox.json"

type sandboxMetadata struct {
	SchemaVersion int    `json:"schema_version"`
	SourceRoot    string `json:"source_root"`
}

func main() {
	if err := run(os.Args[1:], os.Stdin, os.Stdout, os.Stderr); err != nil {
		fmt.Fprintln(os.Stderr, "HAWS development launcher:", err)
		var exitError exitCodeError
		if errors.As(err, &exitError) {
			os.Exit(exitError.code)
		}
		os.Exit(1)
	}
}

func run(args []string, stdin io.Reader, stdout, stderr io.Writer) error {
	flags := flag.NewFlagSet("haws-dev", flag.ContinueOnError)
	flags.SetOutput(stderr)
	sourceFlag := flags.String("source-root", "", "HAWS development checkout")
	sandboxFlag := flags.String("sandbox-root", "", "isolated development data directory")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if stdin == nil || stdout == nil || stderr == nil {
		return errors.New("terminal input, output, and error streams are required")
	}
	sourceRoot, err := resolveSourceRoot(*sourceFlag)
	if err != nil {
		return err
	}
	sandboxRoot, err := resolveSandboxRoot(*sandboxFlag)
	if err != nil {
		return err
	}
	if pathsOverlap(sourceRoot, sandboxRoot) {
		return fmt.Errorf("sandbox %q must be separate from checkout %q", sandboxRoot, sourceRoot)
	}
	if err := prepareSandbox(sourceRoot, sandboxRoot); err != nil {
		return err
	}
	if runtime.GOOS != "windows" {
		path, err := supportedBash(os.Getenv("HOME"), os.Getenv("PATH"))
		if err == nil {
			os.Setenv("PATH", filepath.Dir(path)+string(os.PathListSeparator)+os.Getenv("PATH"))
		}
	}

	dataRoot := filepath.Join(sandboxRoot, "data")
	directories := []string{
		filepath.Join(sandboxRoot, "home"),
		filepath.Join(sandboxRoot, "bin"),
		filepath.Join(sandboxRoot, "cache", "go-build"),
		filepath.Join(dataRoot, "state"),
		filepath.Join(dataRoot, "secondbrain"),
		filepath.Join(dataRoot, "tmp"),
	}
	if runtime.GOOS == "windows" {
		directories = append(directories, filepath.Join(sandboxRoot, "home", "AppData", "Roaming"), filepath.Join(sandboxRoot, "home", "AppData", "Local"))
	}
	for _, directory := range directories {
		if err := os.MkdirAll(directory, 0o700); err != nil {
			return fmt.Errorf("create isolated development directory %q: %w", directory, err)
		}
	}
	app := filepath.Join(sandboxRoot, "bin", executableName("haws-dev"))
	build := exec.Command("go", "build", "-trimpath", "-buildvcs=false", "-o", app, "./cmd/haws")
	build.Dir = sourceRoot
	build.Env = isolatedEnvironment(sandboxRoot, true)
	build.Stdout = stdout
	build.Stderr = stderr
	if err := build.Run(); err != nil {
		return fmt.Errorf("build current HAWS source: %w", err)
	}
	appArgs := flags.Args()
	if _, err := fmt.Fprintf(stdout,
		"HAWS Development Sandbox\nData stays under: %s\nHAWS uses sandbox-only settings, AI configuration, and Second Brain paths.\n\n",
		sandboxRoot,
	); err != nil {
		return err
	}
	command := exec.Command(app, appArgs...)
	command.Dir = sourceRoot
	command.Env = isolatedEnvironment(sandboxRoot, false)
	command.Stdin = stdin
	command.Stdout = stdout
	command.Stderr = stderr
	if err := command.Run(); err != nil {
		var exitError *exec.ExitError
		if errors.As(err, &exitError) {
			return exitCodeError{code: exitError.ExitCode()}
		}
		return fmt.Errorf("run HAWS: %w", err)
	}
	return nil
}

type exitCodeError struct{ code int }

func (e exitCodeError) Error() string { return fmt.Sprintf("HAWS exited with status %d", e.code) }

func resolveSourceRoot(value string) (string, error) {
	if value == "" {
		value, _ = os.Getwd()
	}
	root, err := filepath.Abs(value)
	if err != nil {
		return "", fmt.Errorf("resolve HAWS checkout: %w", err)
	}
	root, err = filepath.EvalSymlinks(root)
	if err != nil {
		return "", fmt.Errorf("resolve HAWS checkout: %w", err)
	}
	if !fileExists(filepath.Join(root, "haws.sh")) {
		return "", fmt.Errorf("%q is not a HAWS checkout (haws.sh is missing)", root)
	}
	if _, err := gitOutput(root, "rev-parse", "--show-toplevel"); err != nil {
		return "", fmt.Errorf("HAWS development checkout must be a Git repository: %w", err)
	}
	return root, nil
}

func resolveSandboxRoot(value string) (string, error) {
	if value == "" {
		base, err := os.UserCacheDir()
		if err != nil {
			return "", fmt.Errorf("locate user cache for HAWS sandbox: %w", err)
		}
		value = filepath.Join(base, "HAWS", "development-sandbox-live")
	}
	root, err := filepath.Abs(value)
	if err != nil {
		return "", fmt.Errorf("resolve HAWS sandbox: %w", err)
	}
	if info, err := os.Lstat(root); err == nil && info.Mode()&os.ModeSymlink != 0 {
		return "", fmt.Errorf("refusing to use a symlink as the HAWS sandbox root: %q", root)
	} else if err != nil && !errors.Is(err, os.ErrNotExist) {
		return "", fmt.Errorf("inspect HAWS sandbox: %w", err)
	}
	var missing []string
	ancestor := root
	for {
		_, err := os.Lstat(ancestor)
		if err == nil {
			resolved, err := filepath.EvalSymlinks(ancestor)
			if err != nil {
				return "", fmt.Errorf("resolve HAWS sandbox parent %q: %w", ancestor, err)
			}
			info, err := os.Stat(resolved)
			if err != nil || !info.IsDir() {
				return "", fmt.Errorf("HAWS sandbox parent %q is not a directory", ancestor)
			}
			for index := len(missing) - 1; index >= 0; index-- {
				resolved = filepath.Join(resolved, missing[index])
			}
			return filepath.Clean(resolved), nil
		}
		if !errors.Is(err, os.ErrNotExist) {
			return "", fmt.Errorf("inspect HAWS sandbox parent %q: %w", ancestor, err)
		}
		parent := filepath.Dir(ancestor)
		if parent == ancestor {
			return "", fmt.Errorf("could not locate an existing parent for HAWS sandbox %q", root)
		}
		missing = append(missing, filepath.Base(ancestor))
		ancestor = parent
	}
}

func prepareSandbox(sourceRoot, sandboxRoot string) error {
	if err := os.MkdirAll(sandboxRoot, 0o700); err != nil {
		return fmt.Errorf("create HAWS sandbox: %w", err)
	}
	marker := filepath.Join(sandboxRoot, sandboxMarker)
	metadata := sandboxMetadata{SchemaVersion: 1, SourceRoot: sourceRoot}
	if info, err := os.Lstat(marker); err == nil && (info.Mode()&os.ModeSymlink != 0 || !info.Mode().IsRegular()) {
		return fmt.Errorf("sandbox marker %q is not a regular file", marker)
	}
	if contents, err := os.ReadFile(marker); err == nil {
		var existing sandboxMetadata
		if err := json.Unmarshal(contents, &existing); err != nil || existing.SchemaVersion != 1 || existing.SourceRoot != sourceRoot {
			return fmt.Errorf("sandbox marker %q does not match this HAWS checkout; refusing to reuse it", marker)
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("read HAWS sandbox marker: %w", err)
	} else {
		entries, readErr := os.ReadDir(sandboxRoot)
		if readErr != nil {
			return fmt.Errorf("inspect HAWS sandbox: %w", readErr)
		}
		if len(entries) != 0 {
			return fmt.Errorf("sandbox directory %q is not empty and has no HAWS ownership marker", sandboxRoot)
		}
		contents, _ := json.Marshal(metadata)
		if err := os.WriteFile(marker, append(contents, '\n'), 0o600); err != nil {
			return fmt.Errorf("mark HAWS development sandbox: %w", err)
		}
	}
	return syncRuntime(sourceRoot, filepath.Join(sandboxRoot, "runtime"))
}

func syncRuntime(sourceRoot, runtimeRoot string) error {
	head, err := gitOutput(sourceRoot, "rev-parse", "HEAD")
	if err != nil {
		return err
	}
	if _, err := os.Lstat(runtimeRoot); errors.Is(err, os.ErrNotExist) {
		if err := runGit(sourceRoot, "clone", "--shared", "--no-checkout", sourceRoot, runtimeRoot); err != nil {
			return fmt.Errorf("create isolated HAWS runtime checkout: %w", err)
		}
		if remote, remoteErr := gitOutput(sourceRoot, "remote", "get-url", "origin"); remoteErr == nil && strings.TrimSpace(remote) != "" {
			if err := runGit(runtimeRoot, "remote", "set-url", "origin", strings.TrimSpace(remote)); err != nil {
				return fmt.Errorf("configure isolated HAWS runtime remote: %w", err)
			}
		}
	} else if err != nil {
		return fmt.Errorf("inspect isolated HAWS runtime: %w", err)
	} else {
		info, statErr := os.Lstat(runtimeRoot)
		if statErr != nil || info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
			return fmt.Errorf("isolated HAWS runtime %q is not a regular directory", runtimeRoot)
		}
		if !fileExists(filepath.Join(runtimeRoot, ".git")) {
			return fmt.Errorf("isolated HAWS runtime %q is not a Git checkout", runtimeRoot)
		}
		if err := runGit(runtimeRoot, "fetch", sourceRoot, head); err != nil {
			return fmt.Errorf("refresh isolated HAWS source: %w", err)
		}
	}
	if err := runGit(runtimeRoot, "config", "core.autocrlf", "false"); err != nil {
		return fmt.Errorf("configure isolated HAWS runtime line endings: %w", err)
	}
	if err := runGit(runtimeRoot, "reset", "--hard", head); err != nil {
		return fmt.Errorf("refresh isolated HAWS runtime files: %w", err)
	}
	if err := applyWorkingChanges(sourceRoot, runtimeRoot); err != nil {
		return err
	}
	return nil
}

func applyWorkingChanges(sourceRoot, runtimeRoot string) error {
	paths := []string{".", ":(exclude)AGENTS.md", ":(exclude)PROJECT_SPECIFIC.md", ":(exclude)HANDOFF.md", ":(exclude)docs/superpowers/**", ":(exclude).haws/**", ":(exclude)secondbrain/notes/**", ":(exclude)dev/secondbrain/**", ":(exclude)skills/custom/**", ":(exclude)scratch/**"}
	patch, err := exec.Command("git", append([]string{"-C", sourceRoot, "diff", "--binary", "HEAD", "--"}, paths...)...).Output()
	if err != nil {
		return fmt.Errorf("read current HAWS development changes: %w", err)
	}
	if len(patch) > 0 {
		command := exec.Command("git", "-C", runtimeRoot, "apply", "--binary", "-")
		command.Stdin = bytes.NewReader(patch)
		if output, err := command.CombinedOutput(); err != nil {
			return fmt.Errorf("apply current HAWS development changes to sandbox: %w\n%s", err, strings.TrimSpace(string(output)))
		}
	}
	untracked, err := exec.Command("git", "-C", sourceRoot, "ls-files", "--others", "--exclude-standard", "-z").Output()
	if err != nil {
		return fmt.Errorf("list current HAWS development files: %w", err)
	}
	for _, name := range bytes.Split(untracked, []byte{0}) {
		if len(name) == 0 {
			continue
		}
		path := filepath.Clean(filepath.FromSlash(string(name)))
		if !safeSourcePath(path) || excludedSourcePath(filepath.ToSlash(path)) {
			continue
		}
		if err := copyUntrackedFile(sourceRoot, runtimeRoot, path); err != nil {
			return err
		}
	}
	return nil
}

func safeSourcePath(path string) bool {
	return path != "." && !filepath.IsAbs(path) && filepath.IsLocal(path)
}

func excludedSourcePath(path string) bool {
	for _, excluded := range []string{".haws", "secondbrain/notes", "dev/secondbrain", "skills/custom", "scratch", ".codex", "worktrees"} {
		if path == excluded || strings.HasPrefix(path, excluded+"/") {
			return true
		}
	}
	switch path {
	case "AGENTS.md", "PROJECT_SPECIFIC.md", "HANDOFF.md":
		return true
	}
	return strings.HasPrefix(path, "docs/superpowers/")
}

func copyUntrackedFile(sourceRoot, runtimeRoot, path string) error {
	source := filepath.Join(sourceRoot, path)
	destination := filepath.Join(runtimeRoot, path)
	info, err := os.Lstat(source)
	if err != nil {
		return fmt.Errorf("inspect current HAWS source %q: %w", path, err)
	}
	if info.Mode()&os.ModeSymlink != 0 {
		return nil
	}
	if !info.Mode().IsRegular() {
		return nil
	}
	if err := ensureSandboxParents(runtimeRoot, filepath.Dir(path)); err != nil {
		return err
	}
	if existing, err := os.Lstat(destination); err == nil && (existing.Mode()&os.ModeSymlink != 0 || !existing.Mode().IsRegular()) {
		return fmt.Errorf("refusing to overwrite non-regular sandbox source %q", path)
	} else if err != nil && !errors.Is(err, os.ErrNotExist) {
		return fmt.Errorf("inspect sandbox source %q: %w", path, err)
	}
	contents, err := os.ReadFile(source)
	if err != nil {
		return fmt.Errorf("read current HAWS source %q: %w", path, err)
	}
	if err := os.WriteFile(destination, contents, info.Mode().Perm()); err != nil {
		return fmt.Errorf("copy current HAWS source %q into sandbox: %w", path, err)
	}
	return nil
}

func ensureSandboxParents(root, relative string) error {
	current := root
	for _, component := range strings.Split(relative, string(filepath.Separator)) {
		if component == "." || component == "" {
			continue
		}
		current = filepath.Join(current, component)
		info, err := os.Lstat(current)
		if errors.Is(err, os.ErrNotExist) {
			if err := os.Mkdir(current, 0o755); err != nil {
				return fmt.Errorf("create sandbox source directory %q: %w", current, err)
			}
			continue
		}
		if err != nil || info.Mode()&os.ModeSymlink != 0 || !info.IsDir() {
			return fmt.Errorf("refusing to write current HAWS source through non-directory %q", current)
		}
	}
	return nil
}

func isolatedEnvironment(sandboxRoot string, forBuild bool) []string {
	values := map[string]string{
		"HOME": filepath.Join(sandboxRoot, "home"), "USERPROFILE": filepath.Join(sandboxRoot, "home"),
		"XDG_CONFIG_HOME": filepath.Join(sandboxRoot, "home", ".config"), "XDG_DATA_HOME": filepath.Join(sandboxRoot, "home", ".local", "share"),
		"XDG_CACHE_HOME": filepath.Join(sandboxRoot, "cache"), "CODEX_HOME": filepath.Join(sandboxRoot, "home", ".codex"),
		"HAWS_ROOT": filepath.Join(sandboxRoot, "runtime"), "HAWS_REPO_DIR": filepath.Join(sandboxRoot, "runtime"),
		"HAWS_STATE_DIR": filepath.Join(sandboxRoot, "data", "state"), "HAWS_SECOND_BRAIN_DIR": filepath.Join(sandboxRoot, "data", "secondbrain"),
		"HAWS_DEV_SANDBOX": sandboxRoot, "TMPDIR": filepath.Join(sandboxRoot, "data", "tmp"),
		"TMP": filepath.Join(sandboxRoot, "data", "tmp"), "TEMP": filepath.Join(sandboxRoot, "data", "tmp"),
		"GIT_CONFIG_NOSYSTEM": "1", "GIT_TERMINAL_PROMPT": "0", "GOCACHE": filepath.Join(sandboxRoot, "cache", "go-build"),
	}
	if forBuild {
		delete(values, "HAWS_ROOT")
		delete(values, "HAWS_REPO_DIR")
		delete(values, "HAWS_STATE_DIR")
		delete(values, "HAWS_SECOND_BRAIN_DIR")
	}
	if runtime.GOOS == "windows" {
		home := values["USERPROFILE"]
		values["APPDATA"] = filepath.Join(sandboxRoot, "home", "AppData", "Roaming")
		values["LOCALAPPDATA"] = filepath.Join(sandboxRoot, "home", "AppData", "Local")
		values["HOMEDRIVE"] = filepath.VolumeName(home)
		values["HOMEPATH"] = strings.TrimPrefix(home, filepath.VolumeName(home))
	}
	return replaceEnvironment(os.Environ(), values, []string{
		"GPG_TTY", "GOFLAGS", "GOENV", "GOTOOLCHAIN",
	})
}

func replaceEnvironment(current []string, values map[string]string, unset []string) []string {
	replacements := make(map[string]string, len(values))
	for key, value := range values {
		replacements[strings.ToUpper(key)] = value
	}
	remove := make(map[string]bool, len(unset))
	for _, key := range unset {
		remove[strings.ToUpper(key)] = true
	}
	result := make([]string, 0, len(current)+len(values))
	for _, entry := range current {
		key, _, ok := strings.Cut(entry, "=")
		if !ok {
			continue
		}
		upper := strings.ToUpper(key)
		if _, replace := replacements[upper]; replace || remove[upper] || isolatedCredentialVariable(upper) {
			continue
		}
		result = append(result, entry)
	}
	for key, value := range values {
		result = append(result, key+"="+value)
	}
	return result
}

func isolatedCredentialVariable(name string) bool {
	for _, prefix := range []string{"HAWS_", "GIT_", "SSH_", "GH_", "GITHUB_", "GITLAB_", "CLAUDE_", "ANTHROPIC_", "CODEX_", "OPENAI_", "GEMINI_", "GOOGLE_", "AWS_", "AZURE_", "NPM_"} {
		if strings.HasPrefix(name, prefix) {
			return true
		}
	}
	return false
}

func supportedBash(home, pathValue string) (string, error) {
	candidates := []string{}
	if home != "" {
		candidates = append(candidates, filepath.Join(home, ".local", "bin", "bash"))
	}
	candidates = append(candidates, "/opt/homebrew/bin/bash", "/usr/local/bin/bash")
	for _, directory := range filepath.SplitList(pathValue) {
		if directory != "" {
			candidates = append(candidates, filepath.Join(directory, "bash"))
		}
	}
	seen := make(map[string]bool)
	for _, candidate := range candidates {
		if seen[candidate] {
			continue
		}
		seen[candidate] = true
		info, err := os.Stat(candidate)
		if err != nil || info.IsDir() || info.Mode()&0o111 == 0 {
			continue
		}
		check := exec.Command(candidate, "-c", "(( BASH_VERSINFO[0] > 4 || ( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 2) ))")
		if err := check.Run(); err == nil {
			return candidate, nil
		}
	}
	return "", errors.New("this HAWS build still uses legacy shell actions; install Bash 4.2 or newer before using the development sandbox")
}

func gitOutput(directory string, args ...string) (string, error) {
	command := exec.Command("git", append([]string{"-C", directory}, args...)...)
	output, err := command.Output()
	if err != nil {
		return "", fmt.Errorf("git %s: %w", strings.Join(args, " "), err)
	}
	return strings.TrimSpace(string(output)), nil
}

func runGit(directory string, args ...string) error {
	command := exec.Command("git", append([]string{"-C", directory}, args...)...)
	if output, err := command.CombinedOutput(); err != nil {
		return fmt.Errorf("git %s: %w\n%s", strings.Join(args, " "), err, strings.TrimSpace(string(output)))
	}
	return nil
}

func fileExists(path string) bool {
	info, err := os.Lstat(path)
	return err == nil && (info.Mode().IsRegular() || info.IsDir())
}

func pathsOverlap(left, right string) bool {
	left, _ = filepath.Abs(left)
	right, _ = filepath.Abs(right)
	if left == right {
		return true
	}
	leftRelative, leftErr := filepath.Rel(left, right)
	rightRelative, rightErr := filepath.Rel(right, left)
	return (leftErr == nil && leftRelative != ".." && !strings.HasPrefix(leftRelative, ".."+string(filepath.Separator))) ||
		(rightErr == nil && rightRelative != ".." && !strings.HasPrefix(rightRelative, ".."+string(filepath.Separator)))
}

func executableName(name string) string {
	if runtime.GOOS == "windows" {
		return name + ".exe"
	}
	return name
}
