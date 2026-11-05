package tui

import (
	"errors"
	"io"
	"strings"
	"testing"
)

func TestRunHomeDispatchesEachActionAndQuits(t *testing.T) {
	var got []Action
	var out strings.Builder
	err := Run(strings.NewReader("1\n2\n3\n4\n5\n6\n7\nq\n"), &out, func(action Action, _ io.Reader) error {
		got = append(got, action)
		return nil
	})
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	want := []Action{ActionSync, ActionSettings, ActionDoctor, ActionRepair, ActionUninstall, ActionSetup, ActionMigration}
	if len(got) != len(want) {
		t.Fatalf("actions = %#v, want %#v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("actions = %#v, want %#v", got, want)
		}
	}
	for _, label := range []string{"Sync", "Settings", "Doctor", "Repair", "Uninstall", "Setup", "Migrate existing installation"} {
		if !strings.Contains(out.String(), label) {
			t.Errorf("menu output missing %q", label)
		}
	}
}

func TestRunHomeIgnoresInvalidChoice(t *testing.T) {
	called := false
	var out strings.Builder
	err := Run(strings.NewReader("x\nq\n"), &out, func(Action, io.Reader) error {
		called = true
		return nil
	})
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if called {
		t.Fatal("invalid choice dispatched an action")
	}
	if !strings.Contains(out.String(), "Choose 1, 2, 3, 4, 5, 6, 7, or q") {
		t.Fatalf("invalid choice was not explained: %q", out.String())
	}
}

func TestRunHomeEOFExitsWithoutDispatch(t *testing.T) {
	called := false
	if err := Run(strings.NewReader(""), io.Discard, func(Action, io.Reader) error {
		called = true
		return nil
	}); err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if called {
		t.Fatal("EOF dispatched an action")
	}
}

func TestRunHomeShowsActionFailureAndReturnsToMenu(t *testing.T) {
	calls := 0
	var out strings.Builder
	err := Run(strings.NewReader("1\nq\n"), &out, func(Action, io.Reader) error {
		calls++
		return errors.New("fixture failure")
	})
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if calls != 1 {
		t.Fatalf("action calls = %d, want 1", calls)
	}
	if !strings.Contains(out.String(), "Action failed: fixture failure") {
		t.Fatalf("action failure was not shown: %q", out.String())
	}
}

func TestHomeOffersSetup(t *testing.T) {
	var output strings.Builder
	var actions []Action
	if err := Run(strings.NewReader("6\nq\n"), &output, func(action Action, _ io.Reader) error { actions = append(actions, action); return nil }); err != nil {
		t.Fatal(err)
	}
	if len(actions) != 1 || actions[0] != ActionSetup {
		t.Fatalf("setup actions = %v", actions)
	}
}

func TestRunPassesOriginalInputToNestedActionWithoutReadAhead(t *testing.T) {
	var output strings.Builder
	var response string
	actions := 0
	input := strings.NewReader("1\nconfirm\nq\n")
	if err := Run(input, &output, func(_ Action, actionInput io.Reader) error {
		actions++
		if actionInput != input {
			t.Fatalf("action input = %T, want original input reader %T", actionInput, input)
		}
		line, err := readLine(actionInput)
		if err != nil {
			return err
		}
		response = strings.TrimSpace(line)
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	if response != "confirm" {
		t.Fatalf("nested response = %q", response)
	}
	if actions != 1 {
		t.Fatalf("actions = %d, want one action before the queued quit", actions)
	}
}
