package tui

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/settings"
)

func settingsDraft(t *testing.T) *settings.Draft {
	t.Helper()
	root := t.TempDir()
	t.Setenv("HAWS_STATE_DIR", "state")
	t.Setenv("HAWS_REPO_DIR", root)
	t.Setenv("HAWS_SECOND_BRAIN_DIR", filepath.Join(root, "brain"))
	t.Setenv("HOME", filepath.Join(root, "home"))
	draft, err := settings.NewDraft(context.Background(), root)
	if err != nil {
		t.Fatal(err)
	}
	return draft
}

func TestSettingsDraftCancelAndInvalidInputNeverWrite(t *testing.T) {
	draft := settingsDraft(t)
	var out strings.Builder
	accepted, err := RunSettingsDraft(context.Background(), draft, strings.NewReader("invalid\n5\n1\nq\nq\n2\n"), &out, false)
	if err != nil || accepted {
		t.Fatalf("accepted %v error %v output %s", accepted, err, out.String())
	}
	if _, err := os.Stat(draft.Store.Dir); !os.IsNotExist(err) {
		t.Fatalf("cancel wrote files: %v", err)
	}
	if !strings.Contains(out.String(), "Discard Changes") || !strings.Contains(out.String(), "Choose") {
		t.Fatal(out.String())
	}
}

func TestSettingsDraftRequiresFinalConfirmation(t *testing.T) {
	for _, input := range []string{"5\n1\nq\n6\nq\n2\n", "5\n1\nq\n6\napply\n"} {
		t.Run(input, func(t *testing.T) {
			draft := settingsDraft(t)
			var out strings.Builder
			accepted, err := RunSettingsDraft(context.Background(), draft, strings.NewReader(input), &out, false)
			if err != nil || accepted != strings.Contains(input, "apply") {
				t.Fatalf("accepted %v, %v: %s", accepted, err, out.String())
			}
			if _, err := os.Stat(draft.Store.Dir); !os.IsNotExist(err) {
				t.Fatalf("preview wrote files: %v", err)
			}
			if draft.State.Config.AutoUpdateSkills {
				t.Fatal("toggle lost")
			}
		})
	}
}

func TestSetupCancelKeepsFollowingHomeInput(t *testing.T) {
	draft := settingsDraft(t)
	input := strings.NewReader("q\n3\n")
	var out strings.Builder
	accepted, err := RunSettingsDraft(context.Background(), draft, input, &out, true)
	if err != nil || accepted {
		t.Fatal(accepted, err)
	}
	line, err := readLine(input)
	if err != nil || line != "3" {
		t.Fatal("consumed Home input", line, err)
	}
}
