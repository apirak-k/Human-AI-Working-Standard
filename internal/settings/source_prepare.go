package settings

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// PrepareRegisteredSource creates an absent registered device source checkout.
// The bool is false when the target is a repository source that still needs the
// legacy Gitlink preparation path.
func PrepareRegisteredSource(ctx context.Context, store Store, sourceID string) (bool, error) {
	source, registered, err := registeredDeviceSource(ctx, store, sourceID)
	if err != nil || !registered {
		return registered, err
	}
	if err := safeSettingsGitEnvironment(); err != nil {
		return true, errors.New("Git environment prevents safe source preparation")
	}
	if err := repositoryPathUnlinked(store.Dir, "skill-sources/registry.tsv"); err != nil {
		return true, errors.New("device source registry path is unsafe")
	}
	if err := repositoryPathUnlinked(store.Dir, filepath.ToSlash(filepath.Join("skill-sources", filepath.FromSlash(source.Path)))); err != nil {
		return true, errors.New("device source checkout path is unsafe")
	}

	if _, err := os.Lstat(source.Dir); err == nil {
		if _, err := sourceRepositoryRoot(ctx, source); err != nil {
			return true, errors.New("device source checkout does not match its registration")
		}
		return true, nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return true, errors.New("device source checkout is unavailable")
	}

	unlock, err := lockDeviceSources(ctx, store)
	if err != nil {
		return true, err
	}
	defer unlock()

	current, stillRegistered, err := registeredDeviceSource(ctx, store, sourceID)
	if err != nil || !stillRegistered || current.Path != source.Path || current.URL != source.URL {
		return true, errors.New("device source registration changed during preparation")
	}
	if _, err := os.Lstat(source.Dir); err == nil {
		if _, err := sourceRepositoryRoot(ctx, source); err != nil {
			return true, errors.New("device source checkout does not match its registration")
		}
		return true, nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return true, errors.New("device source checkout is unavailable")
	}

	parent := filepath.Dir(source.Dir)
	if err := os.MkdirAll(parent, 0700); err != nil {
		return true, fmt.Errorf("create device source directory: %w", err)
	}
	stage, err := os.MkdirTemp(parent, ".haws-source-")
	if err != nil {
		return true, fmt.Errorf("stage device source checkout: %w", err)
	}
	defer os.RemoveAll(stage)
	candidate := filepath.Join(stage, "checkout")
	if _, err := settingsGit(ctx, store.Root, "clone", "--quiet", "--", source.URL, candidate); err != nil {
		return true, errors.New("device source clone failed")
	}
	candidateSource := source
	candidateSource.Dir = candidate
	if _, err := sourceRepositoryRoot(ctx, candidateSource); err != nil {
		return true, errors.New("device source clone is not an independent checkout of its registered remote")
	}
	hasSkill, err := sourceHasEntrypoint(candidate)
	if err != nil || !hasSkill {
		return true, errors.New("device source clone has no skill entrypoint")
	}

	if err := repositoryPathUnlinked(store.Dir, filepath.ToSlash(filepath.Join("skill-sources", filepath.FromSlash(source.Path)))); err != nil {
		return true, errors.New("device source checkout path became unsafe")
	}
	if _, err := os.Lstat(source.Dir); err == nil {
		if _, err := sourceRepositoryRoot(ctx, source); err == nil {
			return true, nil
		}
		return true, errors.New("device source checkout appeared with a different registration")
	} else if !errors.Is(err, os.ErrNotExist) {
		return true, errors.New("device source checkout is unavailable")
	}
	if err := os.Rename(candidate, source.Dir); err != nil {
		return true, fmt.Errorf("activate device source checkout: %w", err)
	}
	if _, err := sourceRepositoryRoot(ctx, source); err != nil {
		return true, errors.New("activated device source checkout failed validation")
	}
	return true, nil
}

func registeredDeviceSource(ctx context.Context, store Store, sourceID string) (Source, bool, error) {
	if sourceID == "" {
		return Source{}, false, nil
	}
	registryPath := filepath.Join(store.Dir, "skill-sources", "registry.tsv")
	contents, err := catalogRead(registryPath)
	if errors.Is(err, os.ErrNotExist) {
		return Source{}, false, nil
	}
	if err != nil {
		return Source{}, strings.HasPrefix(sourceID, "device-"), fmt.Errorf("read device source registry: %w", err)
	}
	var found Source
	for _, raw := range strings.Split(string(contents), "\n") {
		fields := strings.Split(strings.TrimSuffix(raw, "\r"), "\t")
		if len(fields) != 3 || !validSourceName(fields[0]) || !safeRepositoryPath(fields[1]) || !validCatalogRemote(fields[2]) {
			continue
		}
		id := "device-" + fields[0] + "::" + fields[1]
		if id != sourceID {
			continue
		}
		if found.ID != "" {
			return Source{}, true, errors.New("device source registration is ambiguous")
		}
		found = Source{ID: id, Path: fields[1], URL: fields[2], Dir: filepath.Join(store.Dir, "skill-sources", filepath.FromSlash(fields[1]))}
	}
	if found.ID == "" {
		return Source{}, false, nil
	}
	if err := ctx.Err(); err != nil {
		return Source{}, true, err
	}
	sources, err := store.Sources(ctx)
	if err != nil {
		return Source{}, true, fmt.Errorf("verify device source identity: %w", err)
	}
	identities, exact := 0, 0
	for _, candidate := range sources {
		if candidate.ID != sourceID {
			continue
		}
		identities++
		if candidate.Path == found.Path && candidate.URL == found.URL && filepath.Clean(candidate.Dir) == filepath.Clean(found.Dir) {
			exact++
		}
	}
	if identities != 1 || exact != 1 {
		return Source{}, true, errors.New("device source identity is ambiguous")
	}
	return found, true, nil
}

func lockDeviceSources(ctx context.Context, store Store) (func(), error) {
	root := filepath.Join(store.Dir, "skill-sources")
	if err := repositoryPathUnlinked(store.Dir, "skill-sources"); err != nil {
		return nil, errors.New("device source directory is unsafe")
	}
	if err := os.MkdirAll(root, 0700); err != nil {
		return nil, fmt.Errorf("create device source directory: %w", err)
	}
	lock := filepath.Join(root, ".registry-lock")
	deadline := time.NewTimer(30 * time.Second)
	defer deadline.Stop()
	ticker := time.NewTicker(25 * time.Millisecond)
	defer ticker.Stop()
	for {
		err := os.Mkdir(lock, 0700)
		if err == nil {
			return func() {
				info, err := os.Lstat(lock)
				if err == nil && info.IsDir() && info.Mode()&os.ModeSymlink == 0 {
					_ = os.Remove(lock)
				}
			}, nil
		}
		if !errors.Is(err, os.ErrExist) {
			return nil, fmt.Errorf("acquire device source lock: %w", err)
		}
		if info, statErr := os.Lstat(lock); statErr == nil && (!info.IsDir() || info.Mode()&os.ModeSymlink != 0) {
			return nil, errors.New("device source lock path is unsafe")
		} else if statErr != nil && !errors.Is(statErr, os.ErrNotExist) {
			return nil, fmt.Errorf("inspect device source lock: %w", statErr)
		}
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-deadline.C:
			return nil, errors.New("another device source operation is still active")
		case <-ticker.C:
		}
	}
}

func sourceHasEntrypoint(root string) (bool, error) {
	found := false
	err := filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.IsDir() && entry.Name() == ".git" {
			return filepath.SkipDir
		}
		if !entry.IsDir() && entry.Type().IsRegular() && (entry.Name() == "SKILL.md" || entry.Name() == "skill.md") {
			found = true
			return filepath.SkipAll
		}
		return nil
	})
	return found, err
}
