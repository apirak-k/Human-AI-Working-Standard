package settings

import (
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"unicode"
)

type Source struct{ ID, Path, URL, Dir string }
type Skill struct {
	SourceID, ID, Name, Description, Entrypoint string
	Enabled                                     bool
}

// Sources reads configuration only; opening Settings never fetches repositories.
func (s Store) Sources(ctx context.Context) ([]Source, error) {
	root := s.Root
	if override := os.Getenv("HAWS_REPO_DIR"); override != "" {
		root = override
		if !filepath.IsAbs(root) {
			root = filepath.Join(s.Root, root)
		}
	}
	var sources []Source
	modules := filepath.Join(root, ".gitmodules")
	if _, err := os.Lstat(modules); err == nil {
		if _, err := catalogRead(modules); err != nil {
			return nil, err
		}
		cmd := exec.CommandContext(ctx, "git", "config", "--null", "--file", modules, "--get-regexp", `^submodule\..*\.(path|url)$`)
		output, err := cmd.Output()
		if err != nil {
			var exit *exec.ExitError
			if !errors.As(err, &exit) || exit.ExitCode() != 1 {
				return nil, fmt.Errorf("read repository sources: %w", err)
			}
		}
		paths := map[string]string{}
		urls := map[string]string{}
		var names []string
		for _, record := range strings.Split(string(output), "\x00") {
			key, value, ok := strings.Cut(record, "\n")
			if !ok {
				continue
			}
			key = strings.TrimPrefix(key, "submodule.")
			if name, ok := strings.CutSuffix(key, ".path"); ok {
				if _, exists := paths[name]; !exists {
					names = append(names, name)
				}
				paths[name] = strings.TrimPrefix(value, "./")
			}
			if name, ok := strings.CutSuffix(key, ".url"); ok {
				urls[name] = value
			}
		}
		for _, name := range names {
			path := paths[name]
			if !safeSourcePath(path) {
				continue
			}
			sources = append(sources, Source{ID: name + "::" + path, Path: path, URL: urls[name], Dir: filepath.Join(root, filepath.FromSlash(path))})
		}
	} else if !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}
	deviceRoot := filepath.Join(s.Dir, "skill-sources")
	registry, err := catalogRead(filepath.Join(deviceRoot, "registry.tsv"))
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return nil, err
	}
	gitlinks := map[string]bool{}
	if _, err := os.Lstat(filepath.Join(root, ".git")); err == nil {
		output, err := exec.CommandContext(ctx, "git", "-C", root, "ls-files", "--stage", "-z").Output()
		if err != nil {
			return nil, fmt.Errorf("read source ownership: %w", err)
		}
		for _, record := range strings.Split(string(output), "\x00") {
			fields, path, ok := strings.Cut(record, "\t")
			if ok && strings.HasPrefix(fields, "160000 ") {
				gitlinks[path] = true
			}
		}
	} else if errors.Is(err, os.ErrNotExist) {
		revisions, err := catalogRead(filepath.Join(root, "source-revisions.tsv"))
		if err != nil && !errors.Is(err, os.ErrNotExist) {
			return nil, err
		}
		for _, line := range strings.Split(string(revisions), "\n") {
			path, revision, ok := strings.Cut(line, "\t")
			if ok && regexp.MustCompile(`^[0-9a-f]{40}$`).MatchString(revision) {
				gitlinks[path] = true
			}
		}
	} else {
		return nil, err
	}
	devicePaths := map[string]bool{}
	for _, line := range strings.Split(string(registry), "\n") {
		fields := strings.Split(strings.TrimSuffix(line, "\r"), "\t")
		if len(fields) != 3 {
			continue
		}
		name, path, url := fields[0], fields[1], fields[2]
		if !validSourceName(name) || !safeSourcePath(path) || !(strings.HasPrefix(path, "skills/packs/") || strings.HasPrefix(path, "skills/standalone/")) || filepath.Base(path) != name || !validCatalogRemote(url) {
			continue
		}
		devicePaths[path] = true
		sources = append(sources, Source{ID: "device-" + name + "::" + path, Path: path, URL: url, Dir: filepath.Join(deviceRoot, filepath.FromSlash(path))})
	}
	for i := range sources {
		candidate := filepath.Join(deviceRoot, filepath.FromSlash(sources[i].Path))
		if devicePaths[sources[i].Path] {
			sources[i].Dir = candidate
			continue
		}
		if info, err := os.Lstat(filepath.Join(candidate, ".git")); gitlinks[sources[i].Path] && err == nil && info.Mode()&os.ModeSymlink == 0 {
			git := exec.CommandContext(ctx, "git", "-C", candidate, "rev-parse", "--verify", "HEAD")
			if err := git.Run(); err == nil {
				sources[i].Dir = candidate
			}
		}
	}
	custom := filepath.Join(root, "skills", "custom")
	if info, err := os.Lstat(custom); err == nil && info.IsDir() {
		sources = append(sources, Source{ID: "custom::skills/custom", Path: "skills/custom", URL: "local", Dir: custom})
	}
	return sources, nil
}

func safeSourcePath(path string) bool {
	if path == "" || path == "." || strings.Contains(path, "\\") || strings.Contains(path, ":") || strings.HasPrefix(path, "/") || strings.IndexFunc(path, unicode.IsControl) >= 0 {
		return false
	}
	for _, part := range strings.Split(path, "/") {
		if part == "." || part == ".." || part == "" {
			return false
		}
	}
	return true
}

func validSourceName(name string) bool {
	if name == "" {
		return false
	}
	for _, c := range name {
		if !(c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c >= '0' && c <= '9' || c == '_' || c == '.' || c == '-') {
			return false
		}
	}
	return true
}

func validCatalogRemote(url string) bool {
	if url == "" || strings.HasPrefix(url, "-") || strings.IndexFunc(url, unicode.IsControl) >= 0 {
		return false
	}
	if os.Getenv("HAWS_TEST_ALLOW_LOCAL_SOURCES") == "1" && (filepath.IsAbs(url) || strings.HasPrefix(url, "file://")) {
		return true
	}
	if strings.IndexFunc(url, unicode.IsSpace) >= 0 {
		return false
	}
	for _, prefix := range []string{"https://", "http://", "ssh://", "git://"} {
		if rest, ok := strings.CutPrefix(url, prefix); ok {
			host, path, ok := strings.Cut(rest, "/")
			return ok && host != "" && path != ""
		}
	}
	if rest, ok := strings.CutPrefix(url, "git@"); ok {
		host, path, ok := strings.Cut(rest, ":")
		return ok && host != "" && path != ""
	}
	return false
}

func (s Store) BaselineDisabledSkills() ([]string, error) {
	var disabled []string
	for _, name := range []string{"skills/skills.disabled", "skills.disabled", "config/skills.disabled"} {
		content, err := catalogRead(filepath.Join(s.Root, filepath.FromSlash(name)))
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		if err != nil {
			return nil, err
		}
		content, err = s.legacySkillBaseline(context.Background(), filepath.Join(s.Root, filepath.FromSlash(name)), content)
		if err != nil {
			return nil, err
		}
		for _, line := range strings.Split(string(content), "\n") {
			line, _, _ = strings.Cut(line, "#")
			if line = strings.TrimSpace(line); line != "" {
				disabled = append(disabled, line)
			}
		}
	}
	return disabled, nil
}

func catalogRead(path string) ([]byte, error) {
	info, err := os.Lstat(path)
	if err != nil {
		return nil, err
	}
	if !info.Mode().IsRegular() || info.Size() > 1<<20 {
		return nil, fmt.Errorf("catalog input is not a bounded regular file: %s", path)
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	contents, err := io.ReadAll(io.LimitReader(file, (1<<20)+1))
	if len(contents) > 1<<20 {
		return nil, fmt.Errorf("catalog input too large: %s", path)
	}
	return contents, err
}

// Skills preserves the legacy source-aware IDs and first-name-wins ordering.
func (s Store) Skills(ctx context.Context, sources []Source, disabled []string) ([]Skill, error) {
	off := map[string]bool{}
	for _, key := range disabled {
		off[key] = true
	}
	var skills []Skill
	for _, source := range sources {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		info, err := os.Lstat(source.Dir)
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		if err != nil {
			return nil, err
		}
		if !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
			return nil, fmt.Errorf("skill source is not a real directory: %s", source.Dir)
		}
		var files []string
		err = filepath.WalkDir(source.Dir, func(path string, entry fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if err := ctx.Err(); err != nil {
				return err
			}
			if entry.IsDir() && entry.Name() == ".git" {
				return filepath.SkipDir
			}
			if !entry.IsDir() && (entry.Name() == "SKILL.md" || entry.Name() == "skill.md") && entry.Type().IsRegular() && eligibleSkill(filepath.ToSlash(path)) {
				files = append(files, path)
			}
			return nil
		})
		if err != nil {
			return nil, err
		}
		sort.Strings(files)
		seen := map[string]bool{}
		for _, path := range files {
			contents, err := catalogRead(path)
			if err != nil {
				return nil, err
			}
			if len(contents) == 0 {
				continue
			}
			name, description := skillMetadata(contents, filepath.Base(filepath.Dir(path)))
			if name == "pi-planning-with-files" || strings.HasPrefix(name, "planning-with-files-v") || name == "design-taste-frontend-v1" || seen[name] {
				continue
			}
			seen[name] = true
			relative, err := filepath.Rel(source.Dir, path)
			if err != nil {
				return nil, err
			}
			relative = filepath.ToSlash(relative)
			id := source.ID + "::" + name
			skills = append(skills, Skill{SourceID: source.ID, ID: id, Name: name, Description: description, Entrypoint: relative, Enabled: !off[id] && !off[name] && !off[relative]})
		}
	}
	return skills, nil
}

func eligibleSkill(path string) bool {
	if strings.Contains(path, ".openclaw/") || strings.Contains(path, "caveman/plugins/") {
		return false
	}
	if strings.Contains(path, "archify") && strings.Contains(path, ".agents/skills") {
		return false
	}
	if strings.Contains(path, "planning-with-files") && !strings.Contains(path, ".agents/skills") && !strings.Contains(path, "skills/i18n") {
		return false
	}
	return !strings.Contains(path, "ui-ux-pro-max") || strings.Contains(path, ".claude/skills")
}

var metadataName = regexp.MustCompile(`^\s*name:\s*["']?([^"'#]+)["']?`)
var metadataDescription = regexp.MustCompile(`^\s*description:\s*(.*)`)

func skillMetadata(contents []byte, fallback string) (string, string) {
	lines := strings.Split(string(contents), "\n")
	name, description, before, body := "", "", "", ""
	frontmatter, blocks, capturing := false, 0, false
	for i, line := range lines {
		if i == len(lines)-1 && line == "" {
			break
		}
		terminated := i < len(lines)-1
		if terminated && name == "" {
			if match := metadataName.FindStringSubmatch(line); match != nil {
				name = strings.TrimRightFunc(match[1], unicode.IsSpace)
			}
		}
		trimmed := strings.TrimSpace(line)
		if trimmed == "---" {
			if blocks == 0 {
				blocks = 1
				frontmatter = true
			} else if frontmatter {
				blocks = 2
				frontmatter = false
			} else {
				blocks++
			}
			continue
		}
		if frontmatter && description == "" {
			if capturing {
				if len(line) > 0 && (line[0] == ' ' || line[0] == '\t') && trimmed != "" && !strings.HasPrefix(trimmed, "#") {
					description = strings.TrimLeft(line, " \t")
				} else {
					capturing = false
				}
			}
			if description == "" {
				if match := metadataDescription.FindStringSubmatch(line); match != nil {
					value := match[1]
					value = strings.TrimPrefix(value, "\"")
					value = strings.TrimSuffix(value, "\"")
					value = strings.TrimPrefix(value, "'")
					value = strings.TrimSuffix(value, "'")
					value = strings.TrimSuffix(value, "\r")
					value = strings.TrimSpace(value)
					if value == "" || value == ">" || value == "|" {
						capturing = true
					} else {
						description = value
					}
				}
			}
		} else if blocks == 0 && before == "" && trimmed != "" && !strings.HasPrefix(trimmed, "#") {
			before = trimmed
		} else if blocks >= 2 && body == "" && trimmed != "" && !strings.HasPrefix(trimmed, "#") {
			body = trimmed
		}
		if !terminated || name != "" && description != "" {
			break
		}
	}
	if name == "" {
		name = fallback
	}
	if description == "" {
		if before != "" {
			description = before
		} else if blocks >= 2 {
			description = body
		}
	}
	runes := []rune(description)
	if len(runes) > 60 {
		description = string(runes[:57]) + "..."
	}
	name = strings.NewReplacer("\t", " ", "\n", " ").Replace(name)
	description = strings.NewReplacer("\t", " ", "\n", " ").Replace(description)
	if description == "" {
		description = name
	}
	return name, description
}
