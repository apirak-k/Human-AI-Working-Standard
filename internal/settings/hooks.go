package settings

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

type GitHooksSyncResult struct {
	Configured bool
	Updated    bool
	Adopted    bool
	Preserved  bool
	Skipped    bool
	Messages   []string
}

type gitHooksOwnership struct {
	kind, path, source, fingerprint string
}

// SyncGitHooks activates the tracked advisory hook without taking over a
// user-configured core.hooksPath or modified hook file.
func SyncGitHooks(ctx context.Context, root, stateDir string, adoptLegacy bool) (GitHooksSyncResult, error) {
	var result GitHooksSyncResult
	if err := ctx.Err(); err != nil {
		return result, err
	}
	if root == "" || stateDir == "" {
		return result, errors.New("Git hook setup needs source and state directories")
	}
	var err error
	root, err = filepath.Abs(root)
	if err != nil {
		return result, fmt.Errorf("resolve HAWS source directory: %w", err)
	}
	stateDir, err = filepath.Abs(stateDir)
	if err != nil {
		return result, fmt.Errorf("resolve HAWS state directory: %w", err)
	}
	if err := validateAgentStateDir(stateDir); err != nil {
		return result, err
	}

	hooksDir := filepath.Join(root, ".githooks")
	hooksInfo, err := os.Lstat(hooksDir)
	if err != nil {
		return result, fmt.Errorf("inspect HAWS Git hooks directory: %w", err)
	}
	if !hooksInfo.IsDir() || hooksInfo.Mode()&os.ModeSymlink != 0 {
		return result, fmt.Errorf("HAWS Git hooks path is not an unlinked directory: %s", hooksDir)
	}
	hookPath := filepath.Join(hooksDir, "commit-msg")
	hookInfo, err := os.Lstat(hookPath)
	if err != nil {
		return result, fmt.Errorf("inspect HAWS commit-msg hook: %w", err)
	}
	if !hookInfo.Mode().IsRegular() || hookInfo.Mode()&os.ModeSymlink != 0 {
		return result, fmt.Errorf("HAWS commit-msg hook is not a regular file: %s", hookPath)
	}
	repoRootBytes, err := gitHookCommand(ctx, root, "rev-parse", "--show-toplevel")
	if err != nil {
		return result, fmt.Errorf("HAWS Git hooks require a Git checkout: %w", err)
	}
	repoRoot := strings.TrimSuffix(strings.TrimSuffix(string(repoRootBytes), "\n"), "\r")
	repoRoot, err = filepath.Abs(repoRoot)
	if err != nil {
		return result, fmt.Errorf("resolve Git checkout root: %w", err)
	}
	rootInfo, rootErr := os.Stat(root)
	repoInfo, repoErr := os.Stat(repoRoot)
	if rootErr != nil || repoErr != nil || !os.SameFile(rootInfo, repoInfo) {
		return result, fmt.Errorf("HAWS Git hooks must be configured from the repository root: %s", root)
	}

	target := filepath.Join(root, ".githooks")
	ledgerPath := filepath.Join(stateDir, "ownership.tsv")
	ledger, ledgerExists, ledgerMode, err := readAgentOwnershipLedger(ledgerPath)
	if err != nil {
		return result, err
	}
	record, owned, err := findGitHooksOwnership(ledger, target)
	if err != nil {
		return result, err
	}
	currentHooks, _, err := gitHooksPath(ctx, root, true)
	if err != nil {
		return result, err
	}
	expected := gitHooksOwnership{kind: "git-config", path: target, source: "__HAWS_UNSET__", fingerprint: ".githooks"}

	if currentHooks == ".githooks" {
		if owned {
			if record != expected {
				result.Preserved = true
				result.Messages = append(result.Messages, "[PRESERVED] Existing HAWS hook ownership record is unsupported")
				return result, nil
			}
			result.Configured = true
			result.Skipped = true
			ensureGitHookExecutable(hookPath, hookInfo.Mode())
			return result, nil
		}
		if adoptLegacy {
			exact, err := exactTrackedGitHook(ctx, root, hookPath)
			if err != nil {
				return result, err
			}
			if exact {
				ledger, err = upsertGitHooksOwnership(ledger, expected)
				if err != nil {
					return result, err
				}
				if !ledgerExists {
					ledgerMode = 0o600
				}
				if err := writeAgentOwnershipLedger(ledgerPath, ledger, ledgerMode); err != nil {
					return result, err
				}
				result.Configured = true
				result.Adopted = true
				result.Messages = append(result.Messages, "[ADOPTED] Tracked HAWS Git hooks configuration")
				ensureGitHookExecutable(hookPath, hookInfo.Mode())
				return result, nil
			}
		}
		result.Preserved = true
		result.Messages = append(result.Messages, "[PRESERVED] Existing core.hooksPath is unowned outside the one-time legacy migration")
		return result, nil
	}

	if currentHooks != "" || owned {
		result.Preserved = true
		result.Messages = append(result.Messages, fmt.Sprintf("[PRESERVED] Existing core.hooksPath is not HAWS-owned: %s", currentHooks))
		return result, nil
	}

	if _, err := gitHookCommand(ctx, root, "config", "--local", "core.hooksPath", ".githooks"); err != nil {
		return result, fmt.Errorf("configure Git core.hooksPath: %w", err)
	}
	ledger, err = upsertGitHooksOwnership(ledger, expected)
	if err == nil {
		if !ledgerExists {
			ledgerMode = 0o600
		}
		err = writeAgentOwnershipLedger(ledgerPath, ledger, ledgerMode)
	}
	if err != nil {
		if configuredPath, set, readErr := gitHooksPath(ctx, root, true); readErr == nil && set && configuredPath == ".githooks" {
			_, _ = gitHookCommand(ctx, root, "config", "--local", "--unset-all", "core.hooksPath")
		}
		return result, fmt.Errorf("record Git hook ownership: %w", err)
	}
	ensureGitHookExecutable(hookPath, hookInfo.Mode())
	result.Configured = true
	result.Updated = true
	result.Messages = append(result.Messages, "[CONFIGURED] Git core.hooksPath set to .githooks")
	return result, nil
}

func ensureGitHookExecutable(path string, mode os.FileMode) {
	if mode.Perm()&0o111 == 0 {
		_ = os.Chmod(path, mode.Perm()|0o111)
	}
}

// GitHooksStatus reports whether the effective Git hook path points at HAWS.
func GitHooksStatus(ctx context.Context, root string) (string, error) {
	if err := ctx.Err(); err != nil {
		return "", err
	}
	if root == "" {
		return "", errors.New("Git hook status needs a source directory")
	}
	root, err := filepath.Abs(root)
	if err != nil {
		return "", fmt.Errorf("resolve HAWS source directory: %w", err)
	}
	current, set, err := gitHooksPath(ctx, root, false)
	if err != nil {
		return "", err
	}
	if !set || current == "" {
		current = "default (.git/hooks)"
	}
	status := "Status: [INACTIVE - Run './haws.sh hook install' to activate]"
	if current == ".githooks" {
		status = "Status: [ACTIVE & ADVISORY]"
	}
	return fmt.Sprintf("=== HAWS Git Hooks Status ===\nCurrent core.hooksPath: %s\n%s\n", current, status), nil
}

func gitHooksPath(ctx context.Context, root string, localOnly bool) (string, bool, error) {
	args := []string{"config"}
	if localOnly {
		args = append(args, "--local")
		args = append(args, "--get-all", "core.hooksPath")
	} else {
		args = append(args, "--get", "core.hooksPath")
	}
	output, err := gitHookCommand(ctx, root, args...)
	if err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) && exitErr.ExitCode() == 1 {
			return "", false, nil
		}
		return "", false, fmt.Errorf("read Git core.hooksPath: %w", err)
	}
	value := strings.TrimRight(string(output), "\r\n")
	return value, true, nil
}

func exactTrackedGitHook(ctx context.Context, root, hookPath string) (bool, error) {
	if _, err := gitHookCommand(ctx, root, "ls-files", "--error-unmatch", "--", ".githooks/commit-msg"); err != nil {
		if ctx.Err() != nil {
			return false, ctx.Err()
		}
		return false, nil
	}
	committed, err := gitHookCommand(ctx, root, "cat-file", "blob", "HEAD:.githooks/commit-msg")
	if err != nil {
		if ctx.Err() != nil {
			return false, ctx.Err()
		}
		return false, nil
	}
	working, err := os.ReadFile(hookPath)
	if err != nil {
		return false, fmt.Errorf("read HAWS commit-msg hook: %w", err)
	}
	return bytes.Equal(committed, working), nil
}

func findGitHooksOwnership(lines []string, target string) (gitHooksOwnership, bool, error) {
	var found gitHooksOwnership
	for _, line := range lines {
		fields := strings.Split(strings.TrimSuffix(line, "\r"), "\t")
		if len(fields) != 6 || fields[0] != "hooks" || fields[2] != target || fields[5] != "schema=2" {
			continue
		}
		record := gitHooksOwnership{kind: fields[1], path: fields[2], source: fields[3], fingerprint: fields[4]}
		if found.path != "" && found != record {
			return gitHooksOwnership{}, false, fmt.Errorf("conflicting HAWS hook ownership records for %s", target)
		}
		found = record
	}
	return found, found.path != "", nil
}

func upsertGitHooksOwnership(lines []string, record gitHooksOwnership) ([]string, error) {
	fields := []string{"hooks", record.kind, record.path, record.source, record.fingerprint, "schema=2"}
	for _, field := range fields {
		if strings.ContainsAny(field, "\t\r\n") {
			return nil, errors.New("Git hook ownership fields cannot contain tabs or newlines")
		}
	}
	updated := make([]string, 0, len(lines)+1)
	inserted := false
	for _, line := range lines {
		row := strings.Split(strings.TrimSuffix(line, "\r"), "\t")
		if len(row) == 6 && row[0] == "hooks" && row[2] == record.path && row[5] == "schema=2" {
			if !inserted {
				updated = append(updated, strings.Join(fields, "\t"))
				inserted = true
			}
			continue
		}
		updated = append(updated, line)
	}
	if !inserted {
		updated = append(updated, strings.Join(fields, "\t"))
	}
	return updated, nil
}

func gitHookCommand(ctx context.Context, root string, args ...string) ([]byte, error) {
	commandArgs := append([]string{"-C", root}, args...)
	command := exec.CommandContext(ctx, "git", commandArgs...)
	output, err := command.Output()
	if err != nil {
		return output, err
	}
	return output, nil
}
