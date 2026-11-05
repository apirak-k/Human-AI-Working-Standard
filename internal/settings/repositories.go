package settings

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"unicode"
)

type RepositoryAction struct{ Kind, ID, Path, URL string }

func repositoryURLIdentity(url string) string {
	url = strings.TrimSuffix(url, "/")
	if strings.HasPrefix(url, "https://github.com/") {
		url = strings.TrimSuffix(url, ".git")
	}
	return url
}

func validRepositoryURL(url string) bool {
	if strings.IndexFunc(url, unicode.IsControl) >= 0 {
		return false
	}
	url = strings.TrimSuffix(url, "/")
	if os.Getenv("HAWS_TEST_ALLOW_LOCAL_SOURCES") == "1" && (filepath.IsAbs(url) || strings.HasPrefix(url, "file://")) {
		return true
	}
	path, ok := strings.CutPrefix(url, "https://github.com/")
	if !ok {
		return false
	}
	parts := strings.Split(path, "/")
	if len(parts) != 2 {
		return false
	}
	parts[1] = strings.TrimSuffix(parts[1], ".git")
	for _, part := range parts {
		if !validSourceName(part) || part == "." || part == ".." {
			return false
		}
	}
	return true
}

func safeRepositoryPath(path string) bool {
	return safeSourcePath(path) && (strings.HasPrefix(path, "skills/packs/") || strings.HasPrefix(path, "skills/standalone/")) && validSourceName(filepath.Base(path))
}

func repositoryPathUnlinked(root, relative string) error {
	absolute, err := filepath.Abs(filepath.Join(root, filepath.FromSlash(relative)))
	if err != nil {
		return err
	}
	volume := filepath.VolumeName(absolute)
	current := volume + string(filepath.Separator)
	parts := strings.Split(strings.TrimPrefix(strings.TrimPrefix(absolute, volume), string(filepath.Separator)), string(filepath.Separator))
	for _, part := range parts {
		current = filepath.Join(current, part)
		info, err := os.Lstat(current)
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		if err != nil {
			return err
		}
		if info.Mode()&os.ModeSymlink != 0 {
			return fmt.Errorf("repository path is a symbolic link: %s", current)
		}
	}
	return nil
}

func (s Store) deviceRepository(source Source) (bool, error) {
	registry, err := catalogRead(filepath.Join(s.Dir, "skill-sources", "registry.tsv"))
	if errors.Is(err, os.ErrNotExist) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	for _, line := range strings.Split(string(registry), "\n") {
		fields := strings.Split(strings.TrimSuffix(line, "\r"), "\t")
		if len(fields) == 3 && "device-"+fields[0]+"::"+fields[1] == source.ID && fields[1] == source.Path && fields[2] == source.URL {
			return true, nil
		}
	}
	return false, nil
}

func (s Store) repositoryRoot() string {
	root := os.Getenv("HAWS_REPO_DIR")
	if root == "" {
		return s.Root
	}
	if !filepath.IsAbs(root) {
		return filepath.Join(s.Root, root)
	}
	return root
}

func (s Store) PreflightRepositories(ctx context.Context, actions []RepositoryAction) error {
	if err := safeSettingsGitEnvironment(); err != nil {
		return err
	}
	sources, err := s.Sources(ctx)
	if err != nil {
		return err
	}
	urls, paths, removals := map[string]bool{}, map[string]bool{}, map[string]bool{}
	for _, source := range sources {
		urls[repositoryURLIdentity(source.URL)] = true
		paths[source.Path] = true
	}
	for _, action := range actions {
		if err := ctx.Err(); err != nil {
			return err
		}
		if !safeRepositoryPath(action.Path) {
			return fmt.Errorf("unsafe repository destination: %s", action.Path)
		}
		if err := repositoryPathUnlinked(s.repositoryRoot(), action.Path); err != nil {
			return err
		}
		if err := repositoryPathUnlinked(s.Dir, "skill-sources/"+action.Path); err != nil {
			return err
		}
		switch action.Kind {
		case "add-source":
			if !validRepositoryURL(action.URL) {
				return errors.New("invalid GitHub repository URL")
			}
			identity := repositoryURLIdentity(action.URL)
			if urls[identity] || paths[action.Path] {
				return errors.New("repository URL or destination is already registered")
			}
			for _, candidate := range []string{filepath.Join(s.repositoryRoot(), filepath.FromSlash(action.Path)), filepath.Join(s.Dir, "skill-sources", filepath.FromSlash(action.Path))} {
				if _, err := os.Lstat(candidate); !errors.Is(err, os.ErrNotExist) {
					return fmt.Errorf("repository destination is occupied: %s", candidate)
				}
			}
			urls[identity], paths[action.Path] = true, true
		case "remove-source":
			if removals[action.ID] {
				return errors.New("duplicate repository removal")
			}
			removals[action.ID] = true
			source, err := repositorySource(sources, action)
			if err != nil {
				return err
			}
			if err := s.checkRepositoryRemoval(ctx, source); err != nil {
				return err
			}
		default:
			return fmt.Errorf("unsupported repository action: %s", action.Kind)
		}
	}
	return nil
}

func repositorySource(sources []Source, action RepositoryAction) (Source, error) {
	for _, source := range sources {
		if source.ID == action.ID {
			if source.Path != action.Path {
				return Source{}, errors.New("repository path changed after preview")
			}
			if action.URL != "" && source.URL != action.URL {
				return Source{}, errors.New("repository URL changed after preview")
			}
			return source, nil
		}
	}
	return Source{}, errors.New("repository source is no longer registered")
}

func (s Store) checkRepositoryRemoval(ctx context.Context, source Source) error {
	device, err := s.deviceRepository(source)
	if err != nil {
		return err
	}
	checkout := filepath.Join(s.repositoryRoot(), filepath.FromSlash(source.Path))
	if device {
		checkout = filepath.Join(s.Dir, "skill-sources", filepath.FromSlash(source.Path))
	}
	if !device {
		index, err := settingsGit(ctx, s.repositoryRoot(), "ls-files", "--stage", "--", source.Path)
		if err != nil {
			return err
		}
		if !strings.HasPrefix(index, "160000 ") || !strings.HasSuffix(index, "\t"+source.Path) || strings.Contains(index, "\n") {
			return errors.New("repository is not a registered submodule")
		}
	}
	info, err := os.Lstat(checkout)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return errors.New("repository checkout is not a real directory")
	}
	status, err := settingsGit(ctx, checkout, "status", "--porcelain", "--untracked-files=all", "--ignored=traditional")
	if err != nil {
		return err
	}
	if status != "" {
		return errors.New("repository has local changes (including ignored files)")
	}
	if device {
		if !independentBrain(ctx, checkout) {
			return errors.New("device source is not an independently owned Git checkout")
		}
		remote, err := settingsGit(ctx, checkout, "config", "--local", "--get", "remote.origin.url")
		if err != nil {
			return err
		}
		if remote != source.URL {
			return errors.New("repository origin does not match its registered source")
		}
	} else {
		expected, err := settingsGit(ctx, s.repositoryRoot(), "rev-parse", "--path-format=absolute", "--git-path", "modules/"+source.Path)
		if err != nil {
			return err
		}
		modules, err := settingsGit(ctx, s.repositoryRoot(), "rev-parse", "--path-format=absolute", "--git-path", "modules")
		if err != nil {
			return err
		}
		relative, err := filepath.Rel(modules, expected)
		if err != nil || !filepath.IsLocal(relative) {
			return errors.New("submodule cache is outside the owned modules directory")
		}
		if err := repositoryPathUnlinked(modules, filepath.ToSlash(relative)); err != nil {
			return err
		}
		actual, err := settingsGit(ctx, checkout, "rev-parse", "--path-format=absolute", "--absolute-git-dir")
		if err != nil {
			return err
		}
		if filepath.Clean(actual) != filepath.Clean(expected) {
			return errors.New("repository is not the submodule checkout owned by HAWS")
		}
	}
	return nil
}

func (s Store) ApplyRepository(ctx context.Context, action RepositoryAction) error {
	if err := s.PreflightRepositories(ctx, []RepositoryAction{action}); err != nil {
		return err
	}
	if err := repositoryPathUnlinked(s.Dir, "skill-sources"); err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Join(s.Dir, "skill-sources"), 0700); err != nil {
		return err
	}
	lock := filepath.Join(s.Dir, "skill-sources", ".registry-lock")
	if err := os.Mkdir(lock, 0700); err != nil {
		return fmt.Errorf("another repository operation may be active (lock %s): %w", lock, err)
	}
	defer os.Remove(lock)
	if err := s.PreflightRepositories(ctx, []RepositoryAction{action}); err != nil {
		return err
	}
	if action.Kind == "add-source" {
		return s.addDeviceRepository(ctx, action)
	}
	sources, err := s.Sources(ctx)
	if err != nil {
		return err
	}
	source, err := repositorySource(sources, action)
	if err != nil {
		return err
	}
	device, err := s.deviceRepository(source)
	if err != nil {
		return err
	}
	if !device {
		if _, err := settingsGit(ctx, s.repositoryRoot(), "submodule", "deinit", "-f", "--", action.Path); err != nil {
			return fmt.Errorf("submodule deinitialization failed; inspect checkout before retrying: %w", err)
		}
		if _, err := settingsGit(ctx, s.repositoryRoot(), "rm", "-f", "--", action.Path); err != nil {
			return fmt.Errorf("submodule was deinitialized but Git removal failed; cache preserved: %w", err)
		}
		return nil
	}
	registry := filepath.Join(s.Dir, "skill-sources", "registry.tsv")
	body, err := catalogRead(registry)
	if err != nil {
		return err
	}
	var lines []string
	found := false
	for _, line := range strings.Split(string(body), "\n") {
		fields := strings.Split(strings.TrimSuffix(line, "\r"), "\t")
		if len(fields) == 3 && fields[1] == action.Path {
			found = true
			continue
		}
		if line != "" {
			lines = append(lines, line)
		}
	}
	if !found {
		return errors.New("repository registry changed")
	}
	checkout := filepath.Join(s.Dir, "skill-sources", filepath.FromSlash(action.Path))
	tombstone := ""
	if _, err := os.Lstat(checkout); err == nil {
		tombstone, err = os.MkdirTemp(filepath.Dir(checkout), ".haws-prune-")
		if err != nil {
			return err
		}
		if err := os.Remove(tombstone); err != nil {
			return err
		}
		if err := os.Rename(checkout, tombstone); err != nil {
			return err
		}
	}
	output := strings.Join(lines, "\n")
	if output != "" {
		output += "\n"
	}
	if err := repositoryRegistryWrite(registry, []byte(output)); err != nil {
		if tombstone != "" {
			if rollback := os.Rename(tombstone, checkout); rollback != nil {
				return fmt.Errorf("registry failed: %v; original checkout preserved at %s: %w", err, tombstone, rollback)
			}
		}
		return err
	}
	if tombstone != "" {
		if err := os.RemoveAll(tombstone); err != nil {
			return fmt.Errorf("source unregistered; clean cache remains at %s: %w", tombstone, err)
		}
	}
	return nil
}

func (s Store) addDeviceRepository(ctx context.Context, action RepositoryAction) error {
	checkout := filepath.Join(s.Dir, "skill-sources", filepath.FromSlash(action.Path))
	if err := os.MkdirAll(filepath.Dir(checkout), 0700); err != nil {
		return err
	}
	stage, err := os.MkdirTemp(filepath.Dir(checkout), ".haws-clone-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(stage)
	candidate := filepath.Join(stage, "checkout")
	if _, err := settingsGit(ctx, s.repositoryRoot(), "clone", "--quiet", "--", strings.TrimSuffix(action.URL, "/"), candidate); err != nil {
		return err
	}
	skills, err := s.Skills(ctx, []Source{{ID: "candidate", Dir: candidate}}, nil)
	if err != nil {
		return err
	}
	if len(skills) == 0 {
		return errors.New("repository has no discoverable HAWS skills")
	}
	if err := s.PreflightRepositories(ctx, []RepositoryAction{action}); err != nil {
		return err
	}
	registry := filepath.Join(s.Dir, "skill-sources", "registry.tsv")
	body, err := catalogRead(registry)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	if len(body) > 0 && body[len(body)-1] != '\n' {
		body = append(body, '\n')
	}
	body = append(body, []byte(filepath.Base(action.Path)+"\t"+action.Path+"\t"+strings.TrimSuffix(action.URL, "/")+"\n")...)
	if err := os.Rename(candidate, checkout); err != nil {
		return err
	}
	if err := repositoryRegistryWrite(registry, body); err != nil {
		_ = os.RemoveAll(checkout)
		return err
	}
	return nil
}

func repositoryRegistryWrite(path string, contents []byte) error {
	if err := repositoryPathUnlinked(filepath.Dir(path), filepath.Base(path)); err != nil {
		return err
	}
	file, err := os.CreateTemp(filepath.Dir(path), ".registry-")
	if err != nil {
		return err
	}
	defer os.Remove(file.Name())
	if _, err := file.Write(contents); err != nil {
		_ = file.Close()
		return err
	}
	if err := file.Sync(); err != nil {
		_ = file.Close()
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	return os.Rename(file.Name(), path)
}
