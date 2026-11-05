package app

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"strings"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/settings"
	"github.com/apirak-k/Human-AI-Working-Standard/internal/tui"
)

// RunSettings owns the configuration workflow natively. Component integration
// remains the separately reported Sync migration boundary.
func RunSettings(ctx context.Context, root string, args []string, stdin io.Reader, stdout, stderr io.Writer) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	if len(args) > 1 {
		return errors.New("Setup and Settings do not accept additional arguments")
	}
	handled, err := recoverSettings(ctx, root, stdin, stdout, stderr)
	if err != nil || handled {
		return err
	}
	draft, err := settings.NewDraft(ctx, root)
	if err != nil {
		return err
	}
	planBefore, resultBefore, err := draft.Store.ReadProgress()
	if err != nil {
		return err
	}
	setup := len(args) > 0 && (args[0] == "setup" || args[0] == "bootstrap")
	accepted, err := tui.RunSettingsDraft(ctx, draft, stdin, stdout, setup)
	if err != nil || !accepted {
		return err
	}
	return draft.Store.WithApplyLock(func() error {
		if err := sameSettingsProgress(draft.Store, planBefore, resultBefore); err != nil {
			return err
		}
		if err := draft.Store.ValidateLoaded(draft.SavedState()); err != nil {
			return err
		}
		applyContext, stop := signal.NotifyContext(ctx, os.Interrupt)
		defer stop()
		return applySettings(applyContext, root, draft, stdout, stderr)
	})
}

func applySettings(ctx context.Context, root string, draft *settings.Draft, stdout, stderr io.Writer) error {
	installed, err := draft.Store.InstallComplete()
	if err != nil {
		return err
	}
	pending, err := settingsIntegrationPending(root)
	if err != nil {
		return err
	}
	integration := draft.NeedsIntegration(installed) || pending
	if installed && !draft.Dirty() && !pending {
		_, err = fmt.Fprintln(stdout, "No settings have changed.")
		return err
	}
	if err := draft.ValidateCatalog(ctx); err != nil {
		return err
	}
	actions := draft.Repositories()
	if len(actions) > 0 {
		if err := draft.Store.PreflightRepositories(ctx, actions); err != nil {
			return fmt.Errorf("Settings preflight failed; no settings changes applied: %w", err)
		}
	}
	brainChanged := draft.BrainBefore != draft.BrainAfter
	if brainChanged {
		remote, err := settings.BrainRemote(ctx, settings.BrainDirectory(root))
		if err != nil {
			return err
		}
		if remote != draft.BrainBefore {
			return errors.New("Second Brain remote changed; reload Settings before applying")
		}
		if draft.BrainAfter != "" {
			if err := settings.ValidateBrainURL(draft.BrainAfter); err != nil {
				return err
			}
		}
	}
	if integration {
		if _, err := exec.LookPath("git"); err != nil {
			return fmt.Errorf("Git is required before applying integrations: %w", err)
		}
	}
	plan := settingsPlan(draft, integration)
	completed := []string{"settings\tpending"}
	for _, action := range actions {
		completed = append(completed, action.Kind+"\tpending")
	}
	if brainChanged {
		completed = append(completed, "brain\tpending")
	}
	if integration {
		completed = append(completed, "integration\tpending")
	}
	persist := func() error { return draft.Store.WriteProgress(plan, strings.Join(completed, "\n")+"\n") }
	if err := persist(); err != nil {
		return err
	}
	saved := draft.SavedState()
	if err := draft.Store.Save(saved); err != nil {
		return err
	}
	if err := draft.Store.MigrateLegacySkillState(ctx, saved); err != nil {
		return &SettingsApplyError{Step: "legacy skill-state migration", Err: err}
	}
	completed[0] = "settings\tcompleted"
	if err := persist(); err != nil {
		return err
	}
	fmt.Fprintln(stdout, "Completed: native Go settings")
	for i, action := range actions {
		if err := draft.Store.ApplyRepository(ctx, action); err != nil {
			return &SettingsApplyError{Step: action.Kind, Err: err}
		}
		completed[i+1] = action.Kind + "\tcompleted"
		if err := persist(); err != nil {
			return err
		}
		fmt.Fprintln(stdout, "Completed:", action.Kind, action.Path)
	}
	if brainChanged {
		path := settings.BrainDirectory(root)
		if draft.BrainAfter == "" {
			err = settings.DisconnectBrain(ctx, path, draft.BrainBefore)
		} else {
			err = settings.ConnectBrain(ctx, path, draft.BrainAfter)
		}
		if err != nil {
			return &SettingsApplyError{Step: "Second Brain connection", Err: err}
		}
		completed[len(actions)+1] = "brain\tcompleted"
		if err := persist(); err != nil {
			return err
		}
		fmt.Fprintln(stdout, "Completed: native Go Second Brain configuration")
	}
	if integration {
		if _, err := fmt.Fprintln(stdout, "[INFO] Settings saved; applying integration changes through one Go-hosted authoritative Sync (legacy component runtime)."); err != nil {
			return err
		}
		if err := RunSync(ctx, nil, strings.NewReader(""), stdout, stderr); err != nil {
			return &SettingsApplyError{Step: "integration (pending; retry Sync)", Err: err}
		}
	}
	if err := draft.Store.CompleteInstall(); err != nil {
		return err
	}
	_, err = fmt.Fprintln(stdout, "[PASS] Native Go Settings apply verified.")
	return err
}

type SettingsApplyError struct {
	Step string
	Err  error
}

func (e *SettingsApplyError) Error() string {
	return fmt.Sprintf("Partial failure; settings were saved. Remaining: %s: %v", e.Step, e.Err)
}
func (e *SettingsApplyError) Unwrap() error { return e.Err }
func (e *SettingsApplyError) ExitCode() int {
	var child interface{ ExitCode() int }
	if errors.As(e.Err, &child) && child.ExitCode() > 1 {
		return child.ExitCode()
	}
	return 3
}

func settingsPlan(d *settings.Draft, integration bool) string {
	toggle := func(on bool) string {
		if on {
			return "on"
		}
		return "off"
	}
	var plan strings.Builder
	fmt.Fprintf(&plan, "setting\tauto_update\t%s\nsetting\tauto_update_brain\t%s\n", toggle(d.State.Config.AutoUpdateSkills), toggle(d.State.Config.AutoUpdateBrain))
	for _, client := range []string{"claude", "gemini", "codex"} {
		enabled := true
		for _, off := range d.State.DisabledEnvironments {
			if off == client {
				enabled = false
			}
		}
		status := "disabled"
		if enabled {
			status = "enabled"
		}
		fmt.Fprintf(&plan, "environment\t%s\t%s\n", client, status)
	}
	for _, action := range d.Repositories() {
		value := action.URL
		if action.Kind == "remove-source" {
			value = action.ID
		}
		if action.Kind == "remove-source" {
			fmt.Fprintf(&plan, "%s\tsources\t%s\t%s\t%s\n", action.Kind, value, action.Path, action.URL)
		} else {
			fmt.Fprintf(&plan, "%s\tsources\t%s\t%s\n", action.Kind, value, action.Path)
		}
	}
	if d.BrainBefore != d.BrainAfter {
		if d.BrainAfter == "" {
			fmt.Fprintf(&plan, "brain-disconnect\tremote\t%s\n", d.BrainBefore)
		} else {
			fmt.Fprintf(&plan, "brain-connect\tremote\t%s\n", d.BrainAfter)
		}
	}
	if integration {
		fmt.Fprintln(&plan, "integration\tupdate\tcomponent integration")
	}
	return plan.String()
}

func settingsIntegrationPending(root string) (bool, error) {
	_, contents, err := settings.NewStore(root).ReadProgress()
	if err != nil {
		return false, err
	}
	for _, line := range strings.Split(contents, "\n") {
		if strings.TrimSuffix(line, "\r") == "integration\tpending" {
			return true, nil
		}
	}
	return false, nil
}

func completePendingSettingsIntegration(root string) error {
	store := settings.NewStore(root)
	changed, err := store.CompleteIntegration()
	if err != nil || !changed {
		return err
	}
	_, contents, err := store.ReadProgress()
	if err != nil {
		return err
	}
	for _, line := range strings.Split(contents, "\n") {
		if strings.HasSuffix(strings.TrimSuffix(line, "\r"), "\tpending") {
			return errors.New("component Sync completed, but Settings still has unfinished actions; reopen Settings to recover")
		}
	}
	return store.CompleteInstall()
}
