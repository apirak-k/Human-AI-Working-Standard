package settings

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

// MigrateLegacySkillState restores an owned legacy worktree selection only
// after Save has persisted the approved device selection from this draft.
func (s Store) MigrateLegacySkillState(ctx context.Context, state State) error {
	deviceBefore, loaded := state.loaded[s.Path("skills.disabled")]
	legacyPath := filepath.Join(s.Root, "skills", "skills.disabled")
	legacyBefore := state.loaded[legacyPath]
	if !loaded || deviceBefore.exists || !legacyBefore.exists || !ownedLegacySkillState(legacyBefore.data) {
		return nil
	}
	desired, err := listData(state.DisabledSkills, false)
	if err != nil {
		return err
	}
	verifyPersisted := func() error {
		persisted, err := readStateFile(s.Path("skills.disabled"))
		if err != nil {
			return err
		}
		if !persisted.exists || strings.Join(parseList(persisted.data, false), "\n") != strings.Join(parseList(desired, false), "\n") {
			return errors.New("legacy skill selection is not safely persisted in device state")
		}
		return nil
	}
	if err := verifyPersisted(); err != nil {
		return err
	}
	if err := safeSettingsGitEnvironment(); err != nil {
		return err
	}
	if err := ctx.Err(); err != nil {
		return err
	}
	return s.withProgressLock(func(_ *os.Root) error {
		if err := verifyPersisted(); err != nil {
			return err
		}
		current, err := readStateFile(legacyPath)
		if err != nil {
			return err
		}
		if !current.exists || current.data != legacyBefore.data {
			return errors.New("legacy skill selection changed after draft load; preserve it and reload")
		}
		repo := s.repositoryRoot()
		toplevel, err := settingsGit(ctx, repo, "rev-parse", "--show-toplevel")
		if err != nil {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			return nil
		}
		resolved, err := filepath.EvalSymlinks(toplevel)
		if err != nil {
			return err
		}
		if filepath.Clean(resolved) != filepath.Clean(s.Root) {
			return nil
		}
		if _, err := settingsGit(ctx, repo, "ls-files", "--error-unmatch", "--", "skills/skills.disabled"); err != nil {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			return nil
		}
		status, err := legacySkillGitOutput(ctx, repo, "status", "--porcelain=v1", "-z", "--untracked-files=all", "--", "skills/skills.disabled")
		if err != nil {
			return err
		}
		if string(status) != " M skills/skills.disabled\x00" {
			return nil
		}
		baseline, err := legacySkillGitOutput(ctx, repo, "show", ":skills/skills.disabled")
		if err != nil {
			return err
		}
		parent, err := openStateDir(filepath.Dir(legacyPath), false)
		if err != nil {
			return err
		}
		defer parent.Close()
		stage, err := stageStateFile(parent, string(baseline), legacyBefore.mode.Perm())
		if err != nil {
			return err
		}
		defer parent.Remove(stage)
		latestStatus, err := legacySkillGitOutput(ctx, repo, "status", "--porcelain=v1", "-z", "--untracked-files=all", "--", "skills/skills.disabled")
		if err != nil {
			return err
		}
		if string(latestStatus) != string(status) {
			return errors.New("legacy skill Git state changed during migration")
		}
		latestBaseline, err := legacySkillGitOutput(ctx, repo, "show", ":skills/skills.disabled")
		if err != nil {
			return err
		}
		if string(latestBaseline) != string(baseline) {
			return errors.New("legacy skill index baseline changed during migration")
		}
		if err := verifyPersisted(); err != nil {
			return err
		}
		return commitStateFiles([]replacement{{path: legacyPath, parent: parent, name: filepath.Base(legacyPath), stage: stage, before: legacyBefore}})
	})
}

func ownedLegacySkillState(data string) bool {
	header := regexp.MustCompile(`^[[:space:]]*#[[:space:]]*HAWS Disabled Skills([[:space:]]+\(source-aware\))?[[:space:]]*$`)
	for _, line := range strings.Split(data, "\n") {
		if header.MatchString(line) {
			return true
		}
	}
	return false
}

// Reset reads the tracked baseline that Bash's eager migration would restore,
// while native Settings leaves the legacy worktree untouched until Apply.
func (s Store) legacySkillBaseline(ctx context.Context, path string, contents []byte) ([]byte, error) {
	if filepath.Clean(path) != filepath.Join(s.Root, "skills", "skills.disabled") || !ownedLegacySkillState(string(contents)) {
		return contents, nil
	}
	device, err := readStateFile(s.Path("skills.disabled"))
	if err != nil {
		return nil, err
	}
	if device.exists {
		return contents, nil
	}
	current, err := readStateFile(path)
	if err != nil {
		return nil, err
	}
	if !current.exists || current.data != string(contents) {
		return nil, errors.New("legacy skill selection changed while reading baseline")
	}
	if err := safeSettingsGitEnvironment(); err != nil {
		return nil, err
	}
	repo := s.repositoryRoot()
	toplevel, err := settingsGit(ctx, repo, "rev-parse", "--show-toplevel")
	if err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return contents, nil
	}
	resolved, err := filepath.EvalSymlinks(toplevel)
	if err != nil {
		return nil, err
	}
	if filepath.Clean(resolved) != filepath.Clean(s.Root) {
		return contents, nil
	}
	status, err := legacySkillGitOutput(ctx, repo, "status", "--porcelain=v1", "-z", "--untracked-files=all", "--", "skills/skills.disabled")
	if err != nil {
		return nil, err
	}
	if string(status) != " M skills/skills.disabled\x00" {
		return contents, nil
	}
	return legacySkillGitOutput(ctx, repo, "show", ":skills/skills.disabled")
}

// Keep Git's leading status column and baseline bytes, which settingsGit trims.
func legacySkillGitOutput(ctx context.Context, root string, args ...string) ([]byte, error) {
	if err := safeSettingsGitEnvironment(); err != nil {
		return nil, err
	}
	ctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, "git", append([]string{"-C", root}, args...)...)
	cmd.Env = append(os.Environ(), "GIT_TERMINAL_PROMPT=0", "GIT_OPTIONAL_LOCKS=0")
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	output, readErr := io.ReadAll(io.LimitReader(stdout, maxStateBytes+1))
	if readErr != nil || len(output) > maxStateBytes {
		_ = cmd.Process.Kill()
		_ = cmd.Wait()
		if readErr != nil {
			return nil, readErr
		}
		return nil, errors.New("legacy skill Git output exceeds the size limit")
	}
	if err := cmd.Wait(); err != nil {
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("read legacy skill Git %s: %w", args[0], err)
	}
	return output, nil
}
