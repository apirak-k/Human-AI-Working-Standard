package tui

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/settings"
)

type settingsUI struct {
	ctx   context.Context
	draft *settings.Draft
	in    io.Reader
	out   io.Writer
}

// RunSettingsDraft edits only memory. The application owns final persistence.
func RunSettingsDraft(ctx context.Context, draft *settings.Draft, in io.Reader, out io.Writer, setup bool) (bool, error) {
	if draft == nil || in == nil || out == nil {
		return false, errors.New("settings draft and terminal streams are required")
	}
	ui := settingsUI{ctx, draft, in, out}
	if setup {
		for {
			previous := "Customize Settings"
			if _, err := os.Stat(draft.Store.Path("settings.tsv")); err == nil {
				previous = "Use Previous Settings"
			}
			choice, err := ui.ask("HAWS Setup\nNo changes have been made to this computer.\n\nDefault Setup\nRepositories        Default\nSkills              Default\nAI Environments     Default\nSecond Brain        Local-Only\nAuto Update         On\n\n1) Use Default Setup\n2) " + previous + "\nq) Cancel\nSelect: ")
			if err != nil {
				return false, normalEOF(err)
			}
			if cancelled(choice) {
				return false, nil
			}
			if choice == "1" {
				if err := draft.Reset(ctx); err != nil {
					return false, err
				}
				accepted, back, err := ui.preview()
				if err != nil || accepted {
					return accepted, err
				}
				if !back {
					continue
				}
			} else if choice != "2" {
				fmt.Fprintln(out, "Choose 1, 2, or q.")
				continue
			}
			return ui.edit()
		}
	}
	return ui.edit()
}

func normalEOF(err error) error {
	if errors.Is(err, io.EOF) {
		return nil
	}
	return err
}
func cancelled(choice string) bool {
	return choice == "q" || choice == "c" || choice == "cancel" || choice == "\x1b"
}
func toggleLabel(value bool) string {
	if value {
		return "On"
	}
	return "Off"
}

func (u settingsUI) ask(prompt string) (string, error) {
	if err := u.ctx.Err(); err != nil {
		return "", err
	}
	if _, err := io.WriteString(u.out, "\n"+prompt); err != nil {
		return "", err
	}
	line, err := readLine(u.in)
	if err != nil {
		return "", err
	}
	return strings.TrimSpace(line), nil
}

func (u settingsUI) edit() (bool, error) {
	for {
		choice, err := u.ask("HAWS Settings\nReview the draft; Apply is the only way to save changes.\n\n1) Repositories\n2) Skills\n3) AI Environments\n4) Second Brain\n5) Auto Update\n6) Apply — Preview\n7) Reset to Defaults\nq) Back\nSelect: ")
		if err != nil {
			return false, normalEOF(err)
		}
		if cancelled(choice) {
			if !u.draft.Dirty() {
				return false, nil
			}
			choice, err = u.ask("Discard Changes?\n1) Keep Editing\n2) Discard Changes\nSelect: ")
			if err != nil {
				return false, normalEOF(err)
			}
			if choice == "2" || cancelled(choice) {
				fmt.Fprintln(u.out, "Cancelled. No changes saved.")
				return false, nil
			}
			continue
		}
		switch strings.ToLower(choice) {
		case "1":
			err = u.repositories()
		case "2":
			err = u.skills()
		case "3":
			err = u.environments()
		case "4":
			err = u.brain()
		case "5":
			err = u.autoUpdate()
		case "6", "apply":
			accepted, back, previewErr := u.preview()
			if previewErr != nil {
				return false, normalEOF(previewErr)
			}
			if accepted {
				return true, nil
			}
			if !back {
				fmt.Fprintln(u.out, "Cancelled. No changes saved.")
				return false, nil
			}
		case "7":
			confirm, askErr := u.ask("Reset Settings to Defaults? This replaces the draft only.\nType reset to confirm, or q to cancel: ")
			if askErr != nil {
				return false, normalEOF(askErr)
			}
			if confirm == "reset" {
				err = u.draft.Reset(u.ctx)
			}
		default:
			fmt.Fprintln(u.out, "Choose 1–7 or q.")
		}
		if errors.Is(err, io.EOF) {
			return false, nil
		}
		if err != nil {
			return false, err
		}
	}
}

func (u settingsUI) preview() (accepted, back bool, err error) {
	if err = u.draft.RefreshCatalog(u.ctx); err != nil {
		return
	}
	fmt.Fprintln(u.out, "\nHAWS — Preview\nNo changes have been applied yet.\n\nRepositories")
	for _, source := range u.draft.Sources {
		fmt.Fprintf(u.out, "  %s (%s)\n", source.Path, source.URL)
	}
	for _, action := range u.draft.Repositories() {
		fmt.Fprintf(u.out, "  %s: %s (%s)\n", action.Kind, action.Path, action.URL)
	}
	fmt.Fprintln(u.out, "Skills")
	for _, source := range u.draft.Sources {
		active, total := 0, 0
		for _, skill := range u.draft.Skills {
			if skill.SourceID == source.ID {
				total++
				if skill.Enabled {
					active++
				}
			}
		}
		fmt.Fprintf(u.out, "  %s: %d/%d selected\n", source.Path, active, total)
	}
	fmt.Fprintln(u.out, "AI Environments")
	for _, client := range []string{"claude", "gemini", "codex"} {
		fmt.Fprintf(u.out, "  %s: %s\n", client, toggleLabel(!contains(u.draft.State.DisabledEnvironments, client)))
	}
	fmt.Fprintf(u.out, "Auto Update: Skills %s, Brain %s\n", toggleLabel(u.draft.State.Config.AutoUpdateSkills), toggleLabel(u.draft.State.Config.AutoUpdateBrain))
	fmt.Fprintln(u.out, "Second Brain:", settings.BrainDirectory(u.draft.Store.Root))
	if u.draft.BrainAfter == "" {
		fmt.Fprintln(u.out, "  Local-Only")
	} else {
		fmt.Fprintln(u.out, "  Remote:", u.draft.BrainAfter)
		fmt.Fprintln(u.out, "  Confirm this repository is private before connecting personal notes.")
	}
	fmt.Fprintln(u.out, "Integration changes use the existing component Sync (legacy Bash) until its native migration is complete.")
	choice, err := u.ask("Type apply to Install/Update, b to keep editing, or q to cancel: ")
	if err != nil {
		return false, false, err
	}
	switch choice {
	case "apply":
		return true, false, nil
	case "b", "\x1b":
		return false, true, nil
	default:
		return false, false, nil
	}
}

func contains(values []string, value string) bool {
	for _, item := range values {
		if item == value {
			return true
		}
	}
	return false
}
func toggleSelection(values []string, value string) []string {
	var result []string
	found := false
	for _, item := range values {
		if item == value {
			found = true
		} else {
			result = append(result, item)
		}
	}
	if !found {
		result = append(result, value)
	}
	return result
}

func (u settingsUI) autoUpdate() error {
	for {
		choice, err := u.ask(fmt.Sprintf("Auto Update Settings\n1) Skills & HAWS: %s\n2) Second Brain: %s\nq) Back\nSelect to toggle: ", toggleLabel(u.draft.State.Config.AutoUpdateSkills), toggleLabel(u.draft.State.Config.AutoUpdateBrain)))
		if err != nil {
			return err
		}
		if cancelled(choice) {
			return nil
		}
		switch choice {
		case "1":
			u.draft.State.Config.AutoUpdateSkills = !u.draft.State.Config.AutoUpdateSkills
		case "2":
			if u.draft.BrainAfter == "" {
				fmt.Fprintln(u.out, "Connect a Second Brain remote to enable cloud updates.")
				if err := u.brain(); err != nil {
					return err
				}
			} else {
				u.draft.State.Config.AutoUpdateBrain = !u.draft.State.Config.AutoUpdateBrain
			}
		default:
			fmt.Fprintln(u.out, "Choose 1, 2, or q.")
		}
	}
}

func (u settingsUI) environments() error {
	var clients []string
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	for _, client := range []string{"claude", "gemini", "codex"} {
		paths := []string{filepath.Join(home, "."+client)}
		if client == "codex" {
			paths = append(paths, filepath.Join(home, ".agents"))
		}
		for _, path := range paths {
			if info, err := os.Stat(path); err == nil && info.IsDir() {
				clients = append(clients, client)
				break
			}
		}
	}
	if len(clients) == 0 {
		fmt.Fprintln(u.out, "No AI environments detected on this machine.")
		return nil
	}
	for {
		var prompt strings.Builder
		prompt.WriteString("AI Environments\n")
		for i, client := range clients {
			fmt.Fprintf(&prompt, "%d) %s: %s\n", i+1, client, toggleLabel(!contains(u.draft.State.DisabledEnvironments, client)))
		}
		prompt.WriteString("q) Back\nSelect to toggle: ")
		choice, err := u.ask(prompt.String())
		if err != nil {
			return err
		}
		if cancelled(choice) {
			return nil
		}
		index, err := strconv.Atoi(choice)
		if err != nil || index < 1 || index > len(clients) {
			fmt.Fprintln(u.out, "Choose a listed environment or q.")
			continue
		}
		u.draft.State.DisabledEnvironments = toggleSelection(u.draft.State.DisabledEnvironments, clients[index-1])
	}
}

func (u settingsUI) brain() error {
	for {
		remote := u.draft.BrainAfter
		if remote == "" {
			remote = "Local-Only"
		}
		choice, err := u.ask("Second Brain\nPath: " + settings.BrainDirectory(u.draft.Store.Root) + "\nRemote: " + remote + "\n1) Connect Remote Repository\n2) Disconnect Remote\nq) Back\nSelect: ")
		if err != nil {
			return err
		}
		if cancelled(choice) {
			return nil
		}
		switch choice {
		case "1":
			if u.draft.BrainAfter != "" {
				fmt.Fprintln(u.out, "Disconnect the current remote in the draft first.")
				continue
			}
			value, err := u.ask("Confirm the repository is private. Enter Git repository URL (or q to cancel): ")
			if err != nil {
				return err
			}
			if cancelled(value) || value == "" {
				continue
			}
			if err := settings.ValidateBrainURL(value); err != nil {
				fmt.Fprintln(u.out, err)
				continue
			}
			u.draft.BrainAfter = value
		case "2":
			u.draft.BrainAfter = ""
		default:
			fmt.Fprintln(u.out, "Choose 1, 2, or q.")
		}
	}
}

func (u settingsUI) repositories() error {
	if err := u.draft.LoadCatalog(u.ctx); err != nil {
		return err
	}
	for {
		choice, err := u.ask("Repositories\n1) Add Git Repository\n2) Remove Git Repository\nq) Back\nSelect: ")
		if err != nil {
			return err
		}
		if cancelled(choice) {
			return nil
		}
		if choice == "1" {
			value, err := u.ask("Enter HTTPS GitHub repository URL (or q to cancel): ")
			if err != nil {
				return err
			}
			if cancelled(value) || value == "" {
				continue
			}
			if err := u.draft.AddSource(u.ctx, value); err != nil {
				fmt.Fprintln(u.out, err)
			}
			continue
		}
		if choice != "2" {
			fmt.Fprintln(u.out, "Choose 1, 2, or q.")
			continue
		}
		var ids []string
		var prompt strings.Builder
		prompt.WriteString("Remove Git Repository — draft only\n")
		for _, source := range u.draft.Sources {
			if source.URL == "local" {
				continue
			}
			ids = append(ids, source.ID)
			fmt.Fprintf(&prompt, "%d) %s\n", len(ids), source.Path)
		}
		for _, action := range u.draft.Repositories() {
			if action.Kind == "add-source" {
				ids = append(ids, "url:"+action.URL)
				fmt.Fprintf(&prompt, "%d) %s (new)\n", len(ids), action.Path)
			}
		}
		prompt.WriteString("q) Back\nSelect to toggle removal: ")
		value, err := u.ask(prompt.String())
		if err != nil {
			return err
		}
		if cancelled(value) {
			continue
		}
		index, err := strconv.Atoi(value)
		if err != nil || index < 1 || index > len(ids) {
			fmt.Fprintln(u.out, "Choose a listed repository.")
			continue
		}
		u.draft.RemoveSource(ids[index-1])
	}
}

func (u settingsUI) skills() error {
	if err := u.draft.LoadCatalog(u.ctx); err != nil {
		return err
	}
	for {
		type group struct {
			label   string
			indices []int
		}
		var groups []group
		groups = append(groups, group{label: "Custom"}, group{label: "SINGLE"})
		for _, source := range u.draft.Sources {
			var indices []int
			for i, skill := range u.draft.Skills {
				if skill.SourceID == source.ID {
					indices = append(indices, i)
				}
			}
			if source.Path == "skills/custom" {
				groups[0].indices = append(groups[0].indices, indices...)
			} else if len(indices) == 1 {
				groups[1].indices = append(groups[1].indices, indices...)
			} else if len(indices) > 1 {
				groups = append(groups, group{label: "PACK — " + source.Path, indices: indices})
			}
		}
		var prompt strings.Builder
		prompt.WriteString("Skills\n")
		for i, g := range groups {
			active := 0
			for _, index := range g.indices {
				if u.draft.Skills[index].Enabled {
					active++
				}
			}
			fmt.Fprintf(&prompt, "%d) %s (%d/%d selected)\n", i+1, g.label, active, len(g.indices))
		}
		prompt.WriteString("q) Back\nSelect: ")
		choice, err := u.ask(prompt.String())
		if err != nil {
			return err
		}
		if cancelled(choice) {
			return nil
		}
		index, err := strconv.Atoi(choice)
		if err != nil || index < 1 || index > len(groups) {
			fmt.Fprintln(u.out, "Choose a listed group.")
			continue
		}
		if err := u.skillSelector(groups[index-1].label, groups[index-1].indices); err != nil {
			return err
		}
	}
}

func (u settingsUI) skillSelector(label string, indices []int) error {
	page := 0
	for {
		var prompt strings.Builder
		fmt.Fprintf(&prompt, "%s\n", label)
		start := page * 12
		end := min(start+12, len(indices))
		for i := start; i < end; i++ {
			skill := u.draft.Skills[indices[i]]
			fmt.Fprintf(&prompt, "%d) [%s] %s [%s] — %s\n", i+1, toggleLabel(skill.Enabled), skill.Name, skill.SourceID, skill.Description)
		}
		prompt.WriteString("n) Next  p) Previous  a) Enable all  d) Disable all  q) Back\nSelect to toggle: ")
		choice, err := u.ask(prompt.String())
		if err != nil {
			return err
		}
		if cancelled(choice) {
			return nil
		}
		switch choice {
		case "n":
			if end < len(indices) {
				page++
			}
			continue
		case "p":
			if page > 0 {
				page--
			}
			continue
		case "a", "d":
			for _, index := range indices {
				u.draft.Skills[index].Enabled = choice == "a"
			}
			continue
		}
		index, err := strconv.Atoi(choice)
		if err != nil || index < 1 || index > len(indices) {
			fmt.Fprintln(u.out, "Choose a listed skill or navigation action.")
			continue
		}
		skill := &u.draft.Skills[indices[index-1]]
		skill.Enabled = !skill.Enabled
	}
}
