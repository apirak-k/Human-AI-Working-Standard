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

// PrepareRegisteredSource prepares registered device sources and tracked or
// packaged Gitlink sources. The bool is false when this helper does not own the
// source type and the legacy path should handle it.
func PrepareRegisteredSource(ctx context.Context, store Store, sourceID string) (bool, error) {
	if err := safeSettingsGitEnvironment(); err != nil {
		return false, errors.New("Git environment prevents safe source preparation")
	}
	source, registered, err := registeredDeviceSource(ctx, store, sourceID)
	if err != nil {
		return registered, err
	}
	if !registered {
		return prepareGitlinkSource(ctx, store, sourceID)
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

func prepareGitlinkSource(ctx context.Context, store Store, sourceID string) (bool, error) {
	source, found, err := catalogSourceByID(ctx, store, sourceID)
	if err != nil || !found {
		return found, err
	}
	if !safeRepositoryPath(source.Path) {
		return true, errors.New("Gitlink source path is unsafe")
	}
	if err := safeSettingsGitEnvironment(); err != nil {
		return true, errors.New("Git environment prevents safe source preparation")
	}
	root := store.repositoryRoot()
	pinned, isGitlink, packaged, err := gitlinkRevision(ctx, root, source.Path)
	if err != nil || !isGitlink {
		return isGitlink, err
	}
	if err := repositoryPathUnlinked(root, source.Path); err != nil {
		return true, errors.New("Gitlink source path is unsafe")
	}
	relative := filepath.ToSlash(filepath.Join("skill-sources", filepath.FromSlash(source.Path)))
	if err := repositoryPathUnlinked(store.Dir, relative); err != nil {
		return true, errors.New("device source checkout path is unsafe")
	}
	if packaged {
		if err := repositoryPathUnlinked(store.Dir, relative+".haws-owned"); err != nil {
			return true, errors.New("device source ownership path is unsafe")
		}
		if !validCatalogRemote(source.URL) {
			return true, errors.New("packaged Gitlink source has an invalid remote")
		}
	} else if source.URL == "" || strings.IndexFunc(source.URL, func(r rune) bool { return r < 0x20 || r == 0x7f }) >= 0 {
		return true, errors.New("Gitlink source has an invalid remote")
	}

	unlock, err := lockDeviceSources(ctx, store)
	if err != nil {
		return true, err
	}
	defer unlock()

	current, stillRegistered, err := catalogSourceByID(ctx, store, sourceID)
	if err != nil || !stillRegistered || current.Path != source.Path || current.URL != source.URL {
		return true, errors.New("Gitlink source registration changed during preparation")
	}
	currentPin, currentGitlink, currentPackaged, err := gitlinkRevision(ctx, root, source.Path)
	if err != nil || !currentGitlink || currentPackaged != packaged || currentPin != pinned {
		return true, errors.New("Gitlink source changed during preparation")
	}
	if err := repositoryPathUnlinked(root, source.Path); err != nil {
		return true, errors.New("Gitlink source path became unsafe")
	}
	if err := repositoryPathUnlinked(store.Dir, relative); err != nil {
		return true, errors.New("device source checkout path became unsafe")
	}
	if packaged {
		if err := repositoryPathUnlinked(store.Dir, relative+".haws-owned"); err != nil {
			return true, errors.New("device source ownership path became unsafe")
		}
	}

	deviceDir := filepath.Join(store.Dir, "skill-sources", filepath.FromSlash(source.Path))
	if packaged {
		return true, preparePackagedGitlink(ctx, store.Dir, root, source, deviceDir, pinned)
	}
	return true, prepareTrackedGitlink(ctx, store.Dir, root, source, deviceDir, pinned)
}

func catalogSourceByID(ctx context.Context, store Store, sourceID string) (Source, bool, error) {
	sources, err := store.Sources(ctx)
	if err != nil {
		return Source{}, false, err
	}
	var found Source
	for _, source := range sources {
		if source.ID != sourceID {
			continue
		}
		if found.ID != "" {
			return Source{}, true, errors.New("source identity is ambiguous")
		}
		found = source
	}
	if found.ID == "" {
		return Source{}, false, nil
	}
	if err := ctx.Err(); err != nil {
		return Source{}, true, err
	}
	return found, true, nil
}

func gitlinkRevision(ctx context.Context, root, sourcePath string) (string, bool, bool, error) {
	gitEntry, err := os.Lstat(filepath.Join(root, ".git"))
	if err == nil {
		if gitEntry.Mode()&os.ModeSymlink != 0 {
			return "", true, false, errors.New("HAWS Git metadata path is unsafe")
		}
		output, err := settingsGit(ctx, root, "ls-files", "--stage", "--", sourcePath)
		if err != nil {
			return "", false, false, err
		}
		if output == "" {
			return "", false, false, nil
		}
		if strings.Contains(output, "\n") {
			return "", true, false, errors.New("Gitlink source has ambiguous index entries")
		}
		header, path, ok := strings.Cut(output, "\t")
		fields := strings.Fields(header)
		if !ok || path != sourcePath || len(fields) != 3 || fields[0] != "160000" {
			return "", false, false, nil
		}
		if fields[2] != "0" || !validGitObjectID(fields[1]) {
			return "", true, false, errors.New("Gitlink source has an invalid index revision")
		}
		return fields[1], true, false, nil
	}
	if !errors.Is(err, os.ErrNotExist) {
		return "", false, false, err
	}

	contents, err := catalogRead(filepath.Join(root, "source-revisions.tsv"))
	if errors.Is(err, os.ErrNotExist) {
		return "", false, false, nil
	}
	if err != nil {
		return "", true, true, err
	}
	var revision string
	found := false
	for _, raw := range strings.Split(string(contents), "\n") {
		fields := strings.Split(strings.TrimSuffix(raw, "\r"), "\t")
		if len(fields) == 0 || fields[0] != sourcePath {
			continue
		}
		if found || len(fields) != 2 || len(fields[1]) != 40 || !validGitObjectID(fields[1]) {
			return "", true, true, errors.New("packaged Gitlink revision is invalid or ambiguous")
		}
		revision, found = fields[1], true
	}
	return revision, found, found, nil
}

func validGitObjectID(revision string) bool {
	if len(revision) != 40 && len(revision) != 64 {
		return false
	}
	for _, b := range []byte(revision) {
		if !(b >= '0' && b <= '9' || b >= 'a' && b <= 'f') {
			return false
		}
	}
	return true
}

func prepareTrackedGitlink(ctx context.Context, stateDir, root string, source Source, deviceDir, pinned string) error {
	if err := repositoryPathUnlinked(stateDir, filepath.ToSlash(filepath.Join("skill-sources", filepath.FromSlash(source.Path)))); err != nil {
		return errors.New("device Gitlink checkout path is unsafe")
	}
	deviceSource := source
	deviceSource.Dir = deviceDir
	if _, err := os.Lstat(deviceDir); err == nil {
		if _, err := sourceRepositoryRoot(ctx, deviceSource); err != nil {
			return errors.New("device Gitlink checkout conflicts with its registration")
		}
		return nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return errors.New("device Gitlink checkout is unavailable")
	}

	sourceDir := filepath.Join(root, filepath.FromSlash(source.Path))
	if err := ensureTrackedGitlinkCheckout(ctx, root, source, sourceDir, pinned); err != nil {
		return err
	}
	seedRemote, _ := settingsGit(ctx, sourceDir, "remote", "get-url", "origin")
	parent := filepath.Dir(deviceDir)
	if err := os.MkdirAll(parent, 0700); err != nil {
		return fmt.Errorf("create device source directory: %w", err)
	}
	stage, err := os.MkdirTemp(parent, ".haws-source-")
	if err != nil {
		return fmt.Errorf("stage device source checkout: %w", err)
	}
	defer os.RemoveAll(stage)
	candidate := filepath.Join(stage, "checkout")
	if _, err := settingsGit(ctx, root, "clone", "--quiet", "--no-hardlinks", "--", sourceDir, candidate); err != nil {
		return errors.New("Gitlink source clone failed")
	}
	if seedRemote != "" && source.URL != "" && source.URL != "-" && source.URL != "local" && validCatalogRemote(source.URL) {
		if _, err := settingsGit(ctx, candidate, "remote", "set-url", "origin", source.URL); err != nil {
			return errors.New("Gitlink source remote could not be updated")
		}
	} else if seedRemote == "" {
		_, _ = settingsGit(ctx, candidate, "remote", "remove", "origin")
	}
	candidateSource := source
	candidateSource.Dir = candidate
	if _, err := sourceRepositoryRoot(ctx, candidateSource); err != nil {
		return errors.New("Gitlink source clone is not an independent checkout")
	}
	hasSkill, err := sourceHasEntrypoint(candidate)
	if err != nil || !hasSkill {
		return errors.New("Gitlink source clone has no skill entrypoint")
	}
	if err := repositoryPathUnlinked(root, source.Path); err != nil {
		return errors.New("Gitlink source path became unsafe")
	}
	if err := repositoryPathUnlinked(stateDir, filepath.ToSlash(filepath.Join("skill-sources", filepath.FromSlash(source.Path)))); err != nil {
		return errors.New("device Gitlink checkout path became unsafe")
	}
	if _, err := os.Lstat(deviceDir); err == nil {
		return errors.New("device Gitlink checkout appeared during preparation")
	} else if !errors.Is(err, os.ErrNotExist) {
		return errors.New("device Gitlink checkout is unavailable")
	}
	if err := os.Rename(candidate, deviceDir); err != nil {
		return fmt.Errorf("activate device Gitlink checkout: %w", err)
	}
	deviceSource.Dir = deviceDir
	if _, err := sourceRepositoryRoot(ctx, deviceSource); err != nil {
		return errors.New("activated device Gitlink checkout failed validation")
	}
	return nil
}

func ensureTrackedGitlinkCheckout(ctx context.Context, root string, source Source, sourceDir, pinned string) error {
	if err := repositoryPathUnlinked(root, source.Path); err != nil {
		return errors.New("Gitlink source path is unsafe")
	}
	needsUpdate := false
	info, err := os.Lstat(sourceDir)
	if errors.Is(err, os.ErrNotExist) {
		needsUpdate = true
	} else if err != nil {
		return errors.New("Gitlink source checkout is unavailable")
	} else {
		if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
			return errors.New("Gitlink source checkout is not a real directory")
		}
		sourceCheckout := source
		sourceCheckout.Dir = sourceDir
		if _, err := sourceRepositoryRoot(ctx, sourceCheckout); err == nil {
			return nil
		}
		entries, readErr := os.ReadDir(sourceDir)
		if readErr != nil || len(entries) != 0 {
			return errors.New("Gitlink source path contains unowned files")
		}
		needsUpdate = true
	}
	if needsUpdate {
		if _, err := settingsGit(ctx, root, "submodule", "update", "--init", "--quiet", "--", source.Path); err != nil {
			return errors.New("Gitlink submodule preparation failed")
		}
	}
	sourceCheckout := source
	sourceCheckout.Dir = sourceDir
	if _, err := sourceRepositoryRoot(ctx, sourceCheckout); err != nil {
		return errors.New("prepared Gitlink checkout failed validation")
	}
	current, err := settingsGit(ctx, sourceDir, "rev-parse", "--verify", "HEAD")
	if err != nil || current != pinned {
		return errors.New("prepared Gitlink checkout does not match its indexed revision")
	}
	return nil
}

func preparePackagedGitlink(ctx context.Context, stateDir, root string, source Source, deviceDir, pinned string) error {
	marker := deviceDir + ".haws-owned"
	devicePath := filepath.ToSlash(filepath.Join("skill-sources", filepath.FromSlash(source.Path)))
	if _, err := os.Lstat(deviceDir); err == nil {
		info, statErr := os.Lstat(marker)
		if statErr != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
			return errors.New("packaged Gitlink checkout is not HAWS-owned")
		}
		contents, readErr := catalogRead(marker)
		if readErr != nil || strings.TrimRight(string(contents), "\r\n") != source.URL {
			return errors.New("packaged Gitlink ownership marker does not match its source")
		}
		deviceSource := source
		deviceSource.Dir = deviceDir
		if _, err := sourceRepositoryRoot(ctx, deviceSource); err != nil {
			return errors.New("packaged Gitlink checkout is invalid")
		}
		remote, err := settingsGit(ctx, deviceDir, "remote", "get-url", "origin")
		if err != nil || remote != source.URL {
			return errors.New("packaged Gitlink checkout remote does not match its source")
		}
		return nil
	} else if !errors.Is(err, os.ErrNotExist) {
		return errors.New("packaged Gitlink checkout is unavailable")
	}
	if _, err := os.Lstat(marker); err == nil {
		return errors.New("orphaned packaged Gitlink ownership marker requires inspection")
	} else if !errors.Is(err, os.ErrNotExist) {
		return errors.New("packaged Gitlink ownership marker is unavailable")
	}

	parent := filepath.Dir(deviceDir)
	if err := os.MkdirAll(parent, 0700); err != nil {
		return fmt.Errorf("create device source directory: %w", err)
	}
	stage, err := os.MkdirTemp(parent, ".haws-source-")
	if err != nil {
		return fmt.Errorf("stage device source checkout: %w", err)
	}
	defer os.RemoveAll(stage)
	candidate := filepath.Join(stage, "checkout")
	if _, err := settingsGit(ctx, root, "clone", "--quiet", "--no-hardlinks", "--", source.URL, candidate); err != nil {
		return errors.New("packaged Gitlink source clone failed")
	}
	if _, err := settingsGit(ctx, candidate, "checkout", "--quiet", "--detach", pinned); err != nil {
		return errors.New("packaged Gitlink revision is unavailable from its source")
	}
	revision, err := settingsGit(ctx, candidate, "rev-parse", "--verify", "HEAD")
	if err != nil || revision != pinned {
		return errors.New("packaged Gitlink clone did not reach its pinned revision")
	}
	candidateSource := source
	candidateSource.Dir = candidate
	if _, err := sourceRepositoryRoot(ctx, candidateSource); err != nil {
		return errors.New("packaged Gitlink clone is not an independent checkout")
	}
	if remote, err := settingsGit(ctx, candidate, "remote", "get-url", "origin"); err != nil || remote != source.URL {
		return errors.New("packaged Gitlink clone remote does not match its source")
	}
	hasSkill, err := sourceHasEntrypoint(candidate)
	if err != nil || !hasSkill {
		return errors.New("packaged Gitlink source has no skill entrypoint")
	}
	if err := repositoryPathUnlinked(stateDir, devicePath); err != nil {
		return errors.New("packaged Gitlink checkout path became unsafe")
	}
	if err := repositoryPathUnlinked(stateDir, devicePath+".haws-owned"); err != nil {
		return errors.New("packaged Gitlink source path became unsafe")
	}
	if _, err := os.Lstat(deviceDir); err == nil {
		return errors.New("packaged Gitlink checkout appeared during preparation")
	} else if !errors.Is(err, os.ErrNotExist) {
		return errors.New("packaged Gitlink checkout is unavailable")
	}
	if err := os.Rename(candidate, deviceDir); err != nil {
		return fmt.Errorf("activate packaged Gitlink checkout: %w", err)
	}
	if err := writeOwnedGitlinkMarker(marker, source.URL); err != nil {
		return fmt.Errorf("record packaged Gitlink ownership: %w", err)
	}
	return nil
}

func writeOwnedGitlinkMarker(path, remote string) error {
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return err
	}
	if _, err := file.WriteString(remote + "\n"); err != nil {
		_ = file.Close()
		_ = os.Remove(path)
		return err
	}
	if err := file.Sync(); err != nil {
		_ = file.Close()
		_ = os.Remove(path)
		return err
	}
	if err := file.Close(); err != nil {
		_ = os.Remove(path)
		return err
	}
	return nil
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
