package app

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/signal"
	"strings"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/settings"
)

// recoverSettings prevents a new draft from silently abandoning an approved,
// partially applied repository or Second Brain operation.
func recoverSettings(ctx context.Context, root string, in io.Reader, out, stderr io.Writer) (handled bool, err error) {
	store := settings.NewStore(root)
	plan, result, err := store.ReadProgress()
	if err != nil {
		return false, err
	}
	unfinished := false
	rows := strings.Split(strings.TrimSuffix(result, "\n"), "\n")
	for _, row := range rows {
		fields := strings.Split(row, "\t")
		if len(fields) == 2 && fields[1] == "pending" && fields[0] != "integration" {
			unfinished = true
		}
	}
	if !unfinished {
		return false, nil
	}
	if _, err := fmt.Fprintf(out, "Previous Settings apply is incomplete.\nApproved plan:\n%s\nProgress:\n%s\nr) Retry approved actions\nd) Discard unfinished actions and edit Settings\nq) Cancel\nSelect: ", plan, result); err != nil {
		return true, err
	}
	choice, err := readSettingsChoice(in)
	if err != nil {
		if errors.Is(err, io.EOF) {
			return true, nil
		}
		return true, err
	}
	if choice != "d" && choice != "r" {
		return true, nil
	}
	err = store.WithApplyLock(func() error {
		if err := sameSettingsProgress(store, plan, result); err != nil {
			return err
		}
		if choice == "r" {
			applyContext, stop := signal.NotifyContext(ctx, os.Interrupt)
			defer stop()
			return retrySettings(applyContext, store, plan, rows, out, stderr)
		}
		for i, row := range rows {
			kind, status, ok := strings.Cut(row, "\t")
			if ok && status == "pending" {
				rows[i] = kind + "\tdiscarded"
			}
		}
		return store.WriteProgress(plan, strings.Join(rows, "\n")+"\n")
	})
	return choice != "d", err
}

func sameSettingsProgress(store settings.Store, plan, result string) error {
	currentPlan, currentResult, err := store.ReadProgress()
	if err != nil {
		return err
	}
	if currentPlan != plan || currentResult != result {
		return errors.New("Settings progress changed while the editor was open; reopen Settings before applying")
	}
	return nil
}

func readSettingsChoice(input io.Reader) (string, error) {
	var line strings.Builder
	byteBuffer := []byte{0}
	for line.Len() < 1024 {
		_, err := io.ReadFull(input, byteBuffer)
		if err != nil {
			return "", err
		}
		if byteBuffer[0] == '\n' {
			return strings.TrimSpace(line.String()), nil
		}
		line.WriteByte(byteBuffer[0])
	}
	return "", errors.New("Settings recovery choice is too long")
}

type settingsRecoveryStep struct {
	kind       string
	repository settings.RepositoryAction
	url        string
}

func retrySettings(ctx context.Context, store settings.Store, plan string, rows []string, out, stderr io.Writer) error {
	if len(rows) == 0 || rows[0] != "settings\tcompleted" {
		return errors.New("settings were not saved; choose Discard unfinished actions and review a new draft")
	}
	var steps []settingsRecoveryStep
	for _, line := range strings.Split(plan, "\n") {
		if line == "" {
			continue
		}
		fields := strings.Split(line, "\t")
		if len(fields) < 3 {
			return errors.New("invalid saved Settings plan; review a new draft")
		}
		switch fields[0] {
		case "setting", "environment":
			continue
		case "integration":
			steps = append(steps, settingsRecoveryStep{kind: "integration"})
		case "add-source", "remove-source":
			if len(fields) != 4 && !(fields[0] == "remove-source" && len(fields) == 5) {
				return errors.New("invalid saved repository action")
			}
			action := settings.RepositoryAction{Kind: fields[0], Path: fields[3]}
			if action.Kind == "add-source" {
				action.URL = fields[2]
			} else {
				if len(fields) != 5 || fields[4] == "" {
					return errors.New("saved removal has no approved repository URL; discard unfinished actions and review a new draft")
				}
				action.ID = fields[2]
				action.URL = fields[4]
			}
			steps = append(steps, settingsRecoveryStep{kind: action.Kind, repository: action})
		case "brain-connect", "brain-disconnect":
			if len(fields) != 3 {
				return errors.New("invalid saved Second Brain action")
			}
			steps = append(steps, settingsRecoveryStep{kind: "brain", url: fields[2], repository: settings.RepositoryAction{Kind: fields[0]}})
		default:
			return errors.New("unknown saved Settings action; review a new draft")
		}
	}
	if len(rows) != len(steps)+1 {
		return errors.New("saved Settings progress does not match the plan; review a new draft")
	}
	for i, step := range steps {
		kind, status, ok := strings.Cut(rows[i+1], "\t")
		if !ok || kind != step.kind || (status != "completed" && status != "pending") {
			return errors.New("saved Settings progress does not match its actions")
		}
		if step.kind == "brain" {
			if err := settings.ValidateBrainURL(step.url); err != nil {
				return err
			}
		}
	}
	if err := preflightPendingRepositoryActions(ctx, store, steps, rows); err != nil {
		return err
	}
	persist := func() error { return store.WriteProgress(plan, strings.Join(rows, "\n")+"\n") }
	for i, step := range steps {
		kind, status, ok := strings.Cut(rows[i+1], "\t")
		if !ok || kind != step.kind {
			return errors.New("saved Settings progress does not match its actions")
		}
		if status == "completed" {
			continue
		}
		if status != "pending" {
			return errors.New("saved action was discarded; review a new draft")
		}
		if err := ctx.Err(); err != nil {
			return err
		}
		var err error
		switch step.kind {
		case "add-source", "remove-source":
			var sources []settings.Source
			sources, err = store.Sources(ctx)
			if err != nil {
				return err
			}
			done := step.kind == "remove-source"
			for _, source := range sources {
				if step.kind == "add-source" && source.Path == step.repository.Path && source.URL == step.repository.URL {
					done = true
				}
				if step.kind == "remove-source" && source.ID == step.repository.ID {
					done = false
				}
			}
			if !done {
				err = store.ApplyRepository(ctx, step.repository)
			}
		case "brain":
			path := settings.BrainDirectory(store.Root)
			var remote string
			remote, err = settings.BrainRemote(ctx, path)
			if err == nil {
				if step.repository.Kind == "brain-connect" {
					if remote != step.url {
						if remote != "" {
							return errors.New("Second Brain remote changed after the interrupted apply; review a new draft")
						}
						err = settings.ConnectBrain(ctx, path, step.url)
					}
				} else if remote != "" {
					err = settings.DisconnectBrain(ctx, path, step.url)
				}
			}
		case "integration":
			err = RunSync(ctx, nil, strings.NewReader(""), out, stderr)
		}
		if err != nil {
			return &SettingsApplyError{Step: step.kind, Err: err}
		}
		rows[i+1] = step.kind + "\tcompleted"
		if err := persist(); err != nil {
			return err
		}
	}
	return store.CompleteInstall()
}

// Validate every approved repository retry before the first one can mutate the
// registry or checkout. A later stale action must not leave earlier actions
// partially replayed.
func preflightPendingRepositoryActions(ctx context.Context, store settings.Store, steps []settingsRecoveryStep, rows []string) error {
	var pending []settings.RepositoryAction
	var sources []settings.Source
	loadedSources := false
	for i, step := range steps {
		_, status, ok := strings.Cut(rows[i+1], "\t")
		if !ok || status != "pending" || step.kind != "add-source" && step.kind != "remove-source" {
			continue
		}
		if !loadedSources {
			var err error
			sources, err = store.Sources(ctx)
			if err != nil {
				return err
			}
			loadedSources = true
		}
		alreadyApplied := step.kind == "remove-source"
		for _, source := range sources {
			if step.kind == "add-source" && source.Path == step.repository.Path && source.URL == step.repository.URL {
				alreadyApplied = true
			}
			if step.kind == "remove-source" && source.ID == step.repository.ID {
				alreadyApplied = false
			}
		}
		if !alreadyApplied {
			pending = append(pending, step.repository)
		}
	}
	if len(pending) == 0 {
		return nil
	}
	return store.PreflightRepositories(ctx, pending)
}
