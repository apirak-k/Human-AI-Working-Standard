package app

import (
	"context"
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/settings"
)

type settingsInputMutation struct {
	input   io.Reader
	mutate  func()
	changed bool
}

func (r *settingsInputMutation) Read(p []byte) (int, error) {
	if !r.changed {
		r.changed = true
		r.mutate()
	}
	return r.input.Read(p)
}

func TestSettingsEditorCannotOverwriteNewerPendingApply(t *testing.T) {
	root, calls, resultPath := settingsHostFixture(t, false, "0")
	plan := "add-source\tsources\thttps://github.com/example/demo\tskills/packs/demo\nintegration\tupdate\tcomponent integration\n"
	result := "settings\tcompleted\nadd-source\tpending\nintegration\tpending\n"
	input := &settingsInputMutation{input: strings.NewReader("5\n1\nq\n6\napply\n"), mutate: func() { recoveryProgress(t, root, plan, result) }}
	err := RunSettings(context.Background(), root, nil, input, io.Discard, io.Discard)
	if err == nil || !strings.Contains(err.Error(), "progress changed") {
		t.Fatal(err)
	}
	if got := recoveryRead(t, resultPath); got != result {
		t.Fatal(got)
	}
	state, err := settings.NewStore(root).Load()
	if err != nil || state.Config.AutoUpdateSkills {
		t.Fatal(state.Config, err)
	}
	assertNativeSettingsNoLegacyCalls(t, calls)
}

func TestSettingsRecoveryValidatesWholeJournalBeforeMutation(t *testing.T) {
	root, calls, resultPath, _, replacement := recoveryReplacementSource(t)
	plan := "remove-source\tsources\tdevice-demo::skills/packs/demo\tskills/packs/demo\t" + replacement + "\nintegration\tupdate\tcomponent integration\n"
	recoveryProgress(t, root, plan, "settings\tcompleted\nremove-source\tpending\nwrong-step\tpending\n")
	before := nativeSettingsSnapshot(t, root)
	if err := RunSettings(context.Background(), root, nil, strings.NewReader("r\n"), io.Discard, io.Discard); err == nil {
		t.Fatal("accepted malformed journal")
	}
	if _, err := os.Stat(filepath.Join(filepath.Dir(resultPath), "skill-sources", "skills", "packs", "demo")); err != nil {
		t.Fatal("removed source before validating journal", err)
	}
	if got := nativeSettingsSnapshot(t, root); len(got) != len(before) {
		t.Fatal("malformed recovery mutated the fixture")
	}
	assertNativeSettingsNoLegacyCalls(t, calls)
}
