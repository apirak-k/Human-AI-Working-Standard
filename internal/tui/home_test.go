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
	err := Run(strings.NewReader("1\n2\n3\n4\nq\n"), &out, func(action Action) error {
		got = append(got, action)
		return nil
	})
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	want := []Action{ActionSync, ActionSettings, ActionDoctor, ActionUninstall}
	if len(got) != len(want) {
		t.Fatalf("actions = %#v, want %#v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("actions = %#v, want %#v", got, want)
		}
	}
	for _, label := range []string{"Sync", "Settings", "Doctor", "Uninstall"} {
		if !strings.Contains(out.String(), label) {
			t.Errorf("menu output missing %q", label)
		}
	}
}

func TestRunHomeIgnoresInvalidChoice(t *testing.T) {
	called := false
	var out strings.Builder
	err := Run(strings.NewReader("x\nq\n"), &out, func(Action) error {
		called = true
		return nil
	})
	if err != nil {
		t.Fatalf("Run() error = %v", err)
	}
	if called {
		t.Fatal("invalid choice dispatched an action")
	}
	if !strings.Contains(out.String(), "Choose 1, 2, 3, 4, or q") {
		t.Fatalf("invalid choice was not explained: %q", out.String())
	}
}

func TestRunHomeEOFExitsWithoutDispatch(t *testing.T) {
	called := false
	if err := Run(strings.NewReader(""), io.Discard, func(Action) error {
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
	err := Run(strings.NewReader("1\nq\n"), &out, func(Action) error {
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
