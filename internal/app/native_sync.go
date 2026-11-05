package app

import (
	"context"
	"os"
	"strconv"
	"time"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/settings"
)

// NativeSyncTarget runs one migrated Sync target while the legacy Sync host
// retains its existing lock, ordering, and result presentation.
// shortcut: only HAWS root, registered sources, and Second Brain are native; migrate skill and integration targets before removing the shell Sync host.
func NativeSyncTarget(ctx context.Context, root, target string) (settings.SyncResult, error) {
	if target == "haws" && os.Getenv("HAWS_PACKAGE_DIR") != "" {
		return settings.SyncResult{Status: "skipped", Revision: "-", Detail: "HAWS app update is managed by Go"}, nil
	}
	store := settings.NewStore(root)
	state, err := store.Load()
	if err != nil {
		return settings.SyncResult{Status: "failed", Revision: "-", Detail: "HAWS settings could not be read"}, nil
	}
	if target == "haws" {
		if !state.Config.AutoUpdateSkills {
			return settings.SyncResult{Status: "skipped", Revision: "-", Detail: "Auto Update is disabled"}, nil
		}
		return settings.SyncHawsRoot(ctx, store.Root, syncTargetTimeout()), nil
	}
	if target == "secondbrain" {
		if !state.Config.AutoUpdateBrain {
			return settings.SyncResult{Status: "skipped", Revision: "-", Detail: "Auto Update is disabled"}, nil
		}
		return settings.SyncBrain(ctx, settings.BrainDirectory(store.Root), syncTargetTimeout()), nil
	}
	if !state.Config.AutoUpdateSkills {
		return settings.SyncResult{Status: "skipped", Revision: "-", Detail: "Auto Update is disabled"}, nil
	}
	return settings.SyncSource(ctx, store, target, state.DisabledSkills, syncTargetTimeout()), nil
}

func syncTargetTimeout() time.Duration {
	seconds, err := strconv.ParseInt(os.Getenv("HAWS_SYNC_TIMEOUT_SECONDS"), 10, 64)
	if err != nil || seconds <= 0 || seconds > int64((1<<63-1)/int64(time.Second)) {
		seconds = 30
	}
	return time.Duration(seconds) * time.Second
}
