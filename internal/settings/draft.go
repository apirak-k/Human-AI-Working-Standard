package settings

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
)

// Draft holds unapplied edits; loading and previewing never writes state.
type Draft struct {
	Store                   Store
	State                   State
	Sources                 []Source
	Skills                  []Skill
	BrainBefore, BrainAfter string
	initial                 State
	catalogLoaded           bool
	originalSkills          []Skill
	removed                 map[string]bool
	added                   []RepositoryAction
}

func NewDraft(ctx context.Context, root string) (*Draft, error) {
	store := NewStore(root)
	state, err := store.Load()
	if err != nil {
		return nil, err
	}
	if _, err := os.Lstat(store.Path("skills.disabled")); errors.Is(err, os.ErrNotExist) {
		state.DisabledSkills, err = store.BaselineDisabledSkills()
		if err != nil {
			return nil, err
		}
	}
	brain, err := BrainRemote(ctx, BrainDirectory(root))
	if err != nil {
		return nil, err
	}
	d := &Draft{Store: store, State: state, initial: state, BrainBefore: brain, BrainAfter: brain, removed: map[string]bool{}}
	d.State.DisabledEnvironments = append([]string(nil), state.DisabledEnvironments...)
	d.State.DisabledSkills = append([]string(nil), state.DisabledSkills...)
	return d, nil
}

func (d *Draft) LoadCatalog(ctx context.Context) error {
	if d.catalogLoaded {
		return nil
	}
	sources, err := d.Store.Sources(ctx)
	if err != nil {
		return err
	}
	skills, err := d.Store.Skills(ctx, sources, d.initial.DisabledSkills)
	if err != nil {
		return err
	}
	d.Sources = sources
	d.Skills = skills
	d.originalSkills = append([]Skill(nil), skills...)
	d.catalogLoaded = true
	return nil
}

// RefreshCatalog rebases explicit selections onto additions/removals made while
// Settings was open. Newly discovered skills retain their persisted defaults.
func (d *Draft) RefreshCatalog(ctx context.Context) error {
	changes := map[string]bool{}
	for i, skill := range d.Skills {
		if skill.Enabled != d.originalSkills[i].Enabled {
			changes[skill.ID] = skill.Enabled
		}
	}
	d.catalogLoaded = false
	if err := d.LoadCatalog(ctx); err != nil {
		return err
	}
	for i := range d.Skills {
		if enabled, changed := changes[d.Skills[i].ID]; changed {
			d.Skills[i].Enabled = enabled
		}
	}
	return nil
}

func (d *Draft) ValidateCatalog(ctx context.Context) error {
	sources, err := d.Store.Sources(ctx)
	if err != nil {
		return err
	}
	skills, err := d.Store.Skills(ctx, sources, d.initial.DisabledSkills)
	if err != nil {
		return err
	}
	if !reflect.DeepEqual(sources, d.Sources) || !reflect.DeepEqual(skills, d.originalSkills) {
		return errors.New("repository or skill catalog changed after Preview; reopen Settings before applying")
	}
	return nil
}

func sameSelection(a, b []string) bool {
	normalize := func(values []string) []string {
		result := append([]string{}, values...)
		sort.Strings(result)
		return result
	}
	return reflect.DeepEqual(normalize(a), normalize(b))
}

func (d *Draft) Dirty() bool {
	if d.State.Config != d.initial.Config || !sameSelection(d.State.DisabledEnvironments, d.initial.DisabledEnvironments) || !sameSelection(d.State.DisabledSkills, d.initial.DisabledSkills) || d.BrainBefore != d.BrainAfter || len(d.added) > 0 {
		return true
	}
	for _, removed := range d.removed {
		if removed {
			return true
		}
	}
	for i, skill := range d.Skills {
		if skill.Enabled != d.originalSkills[i].Enabled {
			return true
		}
	}
	return false
}

func (d *Draft) Reset(ctx context.Context) error {
	if err := d.RefreshCatalog(ctx); err != nil {
		return err
	}
	baseline, err := d.Store.BaselineDisabledSkills()
	if err != nil {
		return err
	}
	skills, err := d.Store.Skills(ctx, d.Sources, baseline)
	if err != nil {
		return err
	}
	d.State.DisabledSkills = append([]string(nil), baseline...)
	d.State.Config = DefaultConfig()
	d.State.DisabledEnvironments = nil
	d.BrainAfter = ""
	d.Skills = skills
	d.added = nil
	d.removed = map[string]bool{}
	return nil
}

func (d *Draft) AddSource(ctx context.Context, raw string) error {
	if err := d.LoadCatalog(ctx); err != nil {
		return err
	}
	parsed, err := url.Parse(raw)
	if err != nil || parsed.Scheme != "https" || parsed.Host != "github.com" || parsed.User != nil || parsed.RawQuery != "" || parsed.Fragment != "" || parsed.RawPath != "" {
		return errors.New("enter an HTTPS GitHub repository URL")
	}
	parts := strings.Split(strings.Trim(parsed.Path, "/"), "/")
	if len(parts) != 2 || !validSourceName(parts[0]) || !validSourceName(parts[1]) || parts[0] == "." || parts[0] == ".." {
		return errors.New("enter https://github.com/owner/repository")
	}
	name := strings.TrimSuffix(parts[1], ".git")
	if name == "" || name == "." || name == ".." {
		return errors.New("invalid repository name")
	}
	identity := func(s string) string { return strings.TrimSuffix(strings.TrimSuffix(s, "/"), ".git") }
	path := "skills/packs/" + name
	for _, source := range d.Sources {
		if identity(source.URL) == identity(raw) || source.Path == path {
			return errors.New("repository already registered or destination occupied")
		}
	}
	for _, source := range d.added {
		if identity(source.URL) == identity(raw) || source.Path == path {
			return errors.New("repository already exists in draft")
		}
	}
	for _, candidate := range []string{filepath.Join(d.Store.Root, filepath.FromSlash(path)), filepath.Join(d.Store.Dir, "skill-sources", filepath.FromSlash(path))} {
		if _, err := os.Lstat(candidate); err == nil {
			return fmt.Errorf("repository destination occupied: %s", candidate)
		} else if !errors.Is(err, os.ErrNotExist) {
			return err
		}
	}
	d.added = append(d.added, RepositoryAction{Kind: "add-source", Path: path, URL: strings.TrimSuffix(raw, "/")})
	return nil
}

func (d *Draft) RemoveSource(id string) {
	for i, source := range d.added {
		if id == "url:"+source.URL {
			d.added = append(d.added[:i], d.added[i+1:]...)
			return
		}
	}
	for _, source := range d.Sources {
		if source.ID == id && source.URL != "local" {
			d.removed[id] = !d.removed[id]
			return
		}
	}
}

func (d *Draft) Repositories() []RepositoryAction {
	var actions []RepositoryAction
	for _, source := range d.Sources {
		if d.removed[source.ID] {
			actions = append(actions, RepositoryAction{Kind: "remove-source", ID: source.ID, Path: source.Path, URL: source.URL})
		}
	}
	return append(actions, d.added...)
}

func (d *Draft) SavedState() State {
	state := d.State
	if d.catalogLoaded {
		changed := false
		for i, skill := range d.Skills {
			if skill.Enabled != d.originalSkills[i].Enabled {
				changed = true
				break
			}
		}
		if changed || !sameSelection(state.DisabledSkills, d.initial.DisabledSkills) {
			known := map[string]bool{}
			for _, skill := range d.Skills {
				known[skill.ID] = true
				known[skill.Name] = true
				known[skill.Entrypoint] = true
			}
			var retained []string
			for _, id := range state.DisabledSkills {
				if !known[id] {
					retained = append(retained, id)
				}
			}
			state.DisabledSkills = retained
			for _, skill := range d.Skills {
				if !skill.Enabled {
					state.DisabledSkills = append(state.DisabledSkills, skill.ID)
				}
			}
		}
	}
	return state
}

func (d *Draft) NeedsIntegration(installed bool) bool {
	if !installed || len(d.Repositories()) > 0 || !sameSelection(d.State.DisabledEnvironments, d.initial.DisabledEnvironments) {
		return true
	}
	for i, skill := range d.Skills {
		if skill.Enabled != d.originalSkills[i].Enabled {
			return true
		}
	}
	return false
}
