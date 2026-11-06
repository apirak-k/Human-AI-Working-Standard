package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/app"
	"github.com/apirak-k/Human-AI-Working-Standard/internal/legacy"
	"github.com/apirak-k/Human-AI-Working-Standard/internal/settings"
	"github.com/apirak-k/Human-AI-Working-Standard/internal/tui"
	"github.com/apirak-k/Human-AI-Working-Standard/internal/update"
)

var version = "dev"

func main() {
	if len(os.Args) == 2 && os.Args[1] == "--haws-resolve-active-binary" {
		os.Exit(resolveActiveBinary(os.Stdout, os.Stderr))
	}
	os.Exit(run(os.Args[1:], os.Stdin, os.Stdout, os.Stderr))
}

func resolveActiveBinary(stdout, stderr io.Writer) int {
	current, err := os.Executable()
	if err != nil {
		fmt.Fprintln(stderr, "resolve HAWS executable path:", err)
		return 1
	}
	root, err := update.FindInstallRoot(current, runtime.GOOS)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	active, err := update.ActiveBinary(root, runtime.GOOS, runtime.GOARCH)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	if active == "" {
		active, err = filepath.Abs(current)
		if err != nil {
			fmt.Fprintln(stderr, "resolve base HAWS executable path:", err)
			return 1
		}
	}
	if _, err := fmt.Fprintln(stdout, active); err != nil {
		fmt.Fprintln(stderr, "write resolved HAWS executable path:", err)
		return 1
	}
	return 0
}

func run(args []string, stdin io.Reader, stdout, stderr io.Writer) int {
	if len(args) == 1 && args[0] == "--version" {
		fmt.Fprintf(stdout, "HAWS %s\n", version)
		return 0
	}
	if len(args) == 2 && args[0] == "--haws-prepare-source" {
		root := nativeSyncRoot()
		if root == "" {
			fmt.Fprintln(stderr, "native source preparation needs its HAWS root")
			return 1
		}
		prepareCtx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
		defer stop()
		if os.Getenv("HAWS_SYNC_PREFETCH_MODE") == "1" {
			var cancel context.CancelFunc
			prepareCtx, cancel = context.WithTimeout(prepareCtx, nativeSyncPreparationTimeout())
			defer cancel()
		}
		handled, err := settings.PrepareRegisteredSource(prepareCtx, settings.NewStore(root), args[1])
		if err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		if !handled {
			return 2
		}
		return 0
	}
	if len(args) == 2 && args[0] == "--haws-sync-target" {
		root := nativeSyncRoot()
		if root == "" {
			fmt.Fprintln(stderr, "native Sync target needs its HAWS root")
			return 1
		}
		targetCtx, stop := signal.NotifyContext(context.Background(), os.Interrupt)
		defer stop()
		result, err := app.NativeSyncTarget(targetCtx, root, args[1])
		if err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		if _, err := fmt.Fprintf(stdout, "%s\t%s\t%s\n", syncTargetField(result.Status), syncTargetField(result.Revision), syncTargetField(result.Detail)); err != nil {
			fmt.Fprintln(stderr, "write native Sync target result:", err)
			return 1
		}
		return 0
	}
	if len(args) > 0 && args[0] == "--haws-codex-agents" {
		root := nativeSyncRoot()
		if root == "" {
			fmt.Fprintln(stderr, "native Codex agent profiles need their HAWS root")
			return 1
		}
		return runNativeCodexAgents(root, args[1:], stdout, stderr)
	}
	if len(args) > 0 && args[0] == "--haws-sync-agent-files" {
		return runNativeAgentFiles(args[1:], stdout, stderr)
	}
	if len(args) == 1 && args[0] == "--haws-sync-codex-skills" {
		return runNativeSkillLinker("codex", stdout, stderr)
	}
	if len(args) == 1 && args[0] == "--haws-sync-claude-skills" {
		return runNativeSkillLinker("claude", stdout, stderr)
	}
	if len(args) > 0 && args[0] == "--haws-gemini-skills-json" {
		return runNativeGeminiSkillsJSON(args[1:], stdout, stderr)
	}
	if len(args) > 0 && args[0] == "migrate" {
		packageRoot, err := findPackageRootForRun()
		if err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		return actionExitCode(app.RunMigration(packageRoot, args[1:], stdin, stdout, stderr), stderr)
	}
	if len(args) == 1 && (args[0] == "menu" || args[0] == "interactive") {
		args = nil
	}
	root, err := findRootForRun()
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	ctx := context.Background()
	if len(args) > 0 {
		if args[0] == "codex-agents" {
			return runNativeCodexAgents(root, args[1:], stdout, stderr)
		}
		action := commandAction(args[0])
		if action == "" {
			return actionExitCode(legacy.RunCommand(ctx, root, args, stdin, stdout, stderr), stderr)
		}
		return actionExitCode(runAction(ctx, root, action, args, stdin, stdout, stderr), stderr)
	}
	if !setupAlreadyExists(root) {
		if _, err := fmt.Fprintln(stdout, "[INFO] First launch detected; starting HAWS Setup."); err != nil {
			fmt.Fprintln(stderr, "write first-run message:", err)
			return 1
		}
		if err := runAction(ctx, root, tui.ActionSetup, nil, stdin, stdout, stderr); err != nil {
			return actionExitCode(err, stderr)
		}
	}
	err = tui.Run(stdin, stdout, func(action tui.Action, actionInput io.Reader) error {
		root, err = findRootForRun()
		if err != nil {
			return err
		}
		return runAction(ctx, root, action, nil, actionInput, stdout, stderr)
	})
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	return 0
}

func runNativeCodexAgents(sourceRoot string, args []string, stdout, stderr io.Writer) int {
	command := "check"
	codexHome := ""
	dryRun := false
	emitOwnership := false
	positionals := 0

	for index := 0; index < len(args); index++ {
		argument := args[index]
		name, value, hasValue := strings.Cut(argument, "=")
		switch name {
		case "--source", "--codex-home":
			if !hasValue {
				index++
				if index >= len(args) || strings.HasPrefix(args[index], "--") {
					fmt.Fprintf(stderr, "HAWS Codex agents: %s requires a path\n", name)
					return 1
				}
				value = args[index]
			}
			if value == "" {
				fmt.Fprintf(stderr, "HAWS Codex agents: %s requires a path\n", name)
				return 1
			}
			if name == "--source" {
				sourceRoot = value
			} else {
				codexHome = value
			}
		case "--dry-run":
			if hasValue {
				fmt.Fprintln(stderr, "HAWS Codex agents: --dry-run does not take a value")
				return 1
			}
			dryRun = true
		case "--emit-ownership":
			if hasValue {
				fmt.Fprintln(stderr, "HAWS Codex agents: --emit-ownership does not take a value")
				return 1
			}
			emitOwnership = true
		default:
			if strings.HasPrefix(argument, "-") || positionals > 0 {
				fmt.Fprintln(stderr, "usage: codex-agents [install|check|uninstall] [--dry-run] [--source PATH] [--codex-home PATH]")
				return 1
			}
			command = argument
			positionals++
		}
	}

	result, err := settings.RunCodexAgents(command, sourceRoot, codexHome, dryRun)
	if err != nil {
		fmt.Fprintf(stderr, "HAWS Codex agents: %v\n", err)
		return 1
	}
	if emitOwnership {
		for _, profile := range result.Profiles {
			if !profile.Managed {
				continue
			}
			if _, err := fmt.Fprintf(stdout, "profile\t%s\t%s\t%s\t%s\n", profile.Name, profile.Path, profile.Source, profile.Hash); err != nil {
				fmt.Fprintf(stderr, "write Codex agent ownership result: %v\n", err)
				return 1
			}
		}
		if result.ManifestHash != "" {
			manifestSource := filepath.Join(sourceRoot, "ai-configs", "codex", "agents.mjs")
			if _, err := fmt.Fprintf(stdout, "manifest\t-\t%s\t%s\t%s\n", result.ManifestPath, manifestSource, result.ManifestHash); err != nil {
				fmt.Fprintf(stderr, "write Codex agent ownership result: %v\n", err)
				return 1
			}
		}
		return 0
	}
	if _, err := fmt.Fprintln(stdout, result.Message); err != nil {
		fmt.Fprintf(stderr, "write Codex agent result: %v\n", err)
		return 1
	}
	return 0
}

func nativeSyncRoot() string {
	if root := os.Getenv("HAWS_SYNC_ROOT"); root != "" {
		return root
	}
	return os.Getenv("HAWS_ROOT")
}

func runNativeSkillLinker(environment string, stdout, stderr io.Writer) int {
	root := nativeSyncRoot()
	if root == "" {
		fmt.Fprintf(stderr, "native %s skill linking needs its HAWS root\n", environment)
		return 1
	}
	home := os.Getenv("HOME")
	if home == "" {
		var err error
		home, err = os.UserHomeDir()
		if err != nil {
			fmt.Fprintln(stderr, "resolve user home directory:", err)
			return 1
		}
	}
	var result settings.SkillLinkSyncResult
	var err error
	switch environment {
	case "claude":
		result, err = settings.SyncClaudeSkillLinks(context.Background(), settings.NewStore(root), home)
	case "codex":
		result, err = settings.SyncCodexSkillLinks(context.Background(), settings.NewStore(root), home)
	default:
		fmt.Fprintf(stderr, "unsupported native skill-link environment %q\n", environment)
		return 1
	}
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	if _, err := fmt.Fprintf(stdout, "%d\t%d\t%d\t%d\t%d\n", result.Linked, result.AlreadyLinked, result.PluginOwned, result.Preserved, result.Pruned); err != nil {
		fmt.Fprintf(stderr, "write native %s skill result: %v\n", environment, err)
		return 1
	}
	return 0
}

func runNativeAgentFiles(args []string, stdout, stderr io.Writer) int {
	root := nativeSyncRoot()
	if root == "" {
		fmt.Fprintln(stderr, "native agent file linking needs its HAWS root")
		return 1
	}
	sourceRoot := root
	home := os.Getenv("HOME")
	stateDir := os.Getenv("HAWS_STATE_DIR")
	if stateDir == "" {
		stateDir = filepath.Join(root, ".haws", "state")
	}
	var environments []string
	legacyManifest := ""
	adoptLegacy := false
	for index := 0; index < len(args); index++ {
		argument := args[index]
		name, value, hasValue := strings.Cut(argument, "=")
		switch name {
		case "--source", "--home", "--state-dir", "--legacy-manifest":
			if !hasValue {
				index++
				if index >= len(args) || strings.HasPrefix(args[index], "--") {
					fmt.Fprintf(stderr, "HAWS agent files: %s requires a path\n", name)
					return 1
				}
				value = args[index]
			}
			if value == "" {
				fmt.Fprintf(stderr, "HAWS agent files: %s requires a path\n", name)
				return 1
			}
			switch name {
			case "--source":
				sourceRoot = value
			case "--home":
				home = value
			case "--state-dir":
				stateDir = value
			case "--legacy-manifest":
				legacyManifest = value
			}
		case "--claude":
			if hasValue {
				fmt.Fprintln(stderr, "HAWS agent files: --claude does not take a value")
				return 1
			}
			environments = append(environments, "claude")
		case "--gemini":
			if hasValue {
				fmt.Fprintln(stderr, "HAWS agent files: --gemini does not take a value")
				return 1
			}
			environments = append(environments, "gemini")
		case "--adopt-legacy":
			if hasValue {
				fmt.Fprintln(stderr, "HAWS agent files: --adopt-legacy does not take a value")
				return 1
			}
			adoptLegacy = true
		default:
			fmt.Fprintln(stderr, "usage: --haws-sync-agent-files --source PATH --home PATH --state-dir PATH (--claude|--gemini)... [--adopt-legacy --legacy-manifest PATH]")
			return 1
		}
	}
	if home == "" {
		var err error
		home, err = os.UserHomeDir()
		if err != nil {
			fmt.Fprintln(stderr, "resolve user home directory:", err)
			return 1
		}
	}
	if adoptLegacy && legacyManifest == "" {
		fmt.Fprintln(stderr, "HAWS agent files: --adopt-legacy requires --legacy-manifest")
		return 1
	}
	result, err := settings.SyncAgentFiles(context.Background(), sourceRoot, home, stateDir, environments, legacyManifest, adoptLegacy)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	for _, message := range result.Messages {
		if _, err := fmt.Fprintln(stderr, "  "+message); err != nil {
			fmt.Fprintln(stderr, "write native agent file message:", err)
			return 1
		}
	}
	if _, err := fmt.Fprintf(stdout, "%d\t%d\t%d\t%d\t%d\t%d\t%d\n", result.Targets, result.Linked, result.Hardlinked, result.Copied, result.Already, result.Preserved, result.Adopted); err != nil {
		fmt.Fprintln(stderr, "write native agent file result:", err)
		return 1
	}
	return 0
}

func runNativeGeminiSkillsJSON(args []string, stdout, stderr io.Writer) int {
	usage := "usage: --haws-gemini-skills-json apply <file> <manifest> <candidate> [--replace-owned] | adopt <file> <manifest> <candidate> <legacy-manifest> <legacy-skill-map> | verify <file> <manifest> | uninstall <file> <manifest>"
	if len(args) == 0 {
		fmt.Fprintln(stderr, usage)
		return 1
	}
	command := args[0]
	var result settings.GeminiSkillConfigResult
	var message string
	var err error
	switch command {
	case "apply":
		if len(args) != 4 && len(args) != 5 || len(args) == 5 && args[4] != "--replace-owned" {
			fmt.Fprintln(stderr, usage)
			return 1
		}
		result, err = settings.ApplyGeminiSkillConfig(args[1], args[2], args[3], len(args) == 5)
		if err == nil {
			if result.Pruned > 0 {
				message = fmt.Sprintf("OK: pruned %d missing HAWS skill source entries.\n", result.Pruned)
			}
			message += fmt.Sprintf("OK: merged %d new HAWS Antigravity skill entries; preserved %d existing entries.\n", result.Added, result.Preserved)
		}
	case "adopt":
		if len(args) != 6 {
			fmt.Fprintln(stderr, usage)
			return 1
		}
		var adoption settings.GeminiSkillAdoptionResult
		adoption, err = settings.AdoptGeminiSkillOwnership(args[1], args[2], args[3], args[4], args[5])
		if err == nil {
			if adoption.Adopted > 0 {
				message = fmt.Sprintf("OK: adopted %d exact legacy HAWS skill entries; left skills config unchanged.\n", adoption.Adopted)
			} else if adoption.LegacyRecords == 0 {
				message = "OK: no legacy skill records to adopt.\n"
			} else {
				message = "OK: no exact legacy HAWS skill entries to adopt.\n"
			}
		}
	case "verify":
		if len(args) != 3 {
			fmt.Fprintln(stderr, usage)
			return 1
		}
		err = settings.VerifyGeminiSkillConfig(args[1], args[2])
		if err == nil {
			message = "OK: Antigravity skills config and ownership record are readable.\n"
		}
	case "uninstall":
		if len(args) != 3 {
			fmt.Fprintln(stderr, usage)
			return 1
		}
		result, err = settings.UninstallGeminiSkillConfig(args[1], args[2])
		if err == nil {
			message = fmt.Sprintf("OK: removed %d HAWS Antigravity skill entries; preserved %d other entries.\n", result.Removed, result.Preserved)
		}
	default:
		fmt.Fprintln(stderr, usage)
		return 1
	}
	if err != nil {
		fmt.Fprintf(stderr, "HAWS Antigravity skills: %v\n", err)
		return 1
	}
	if _, err := io.WriteString(stdout, message); err != nil {
		fmt.Fprintf(stderr, "write native Antigravity skill result: %v\n", err)
		return 1
	}
	return 0
}

func nativeSyncPreparationTimeout() time.Duration {
	seconds, err := strconv.Atoi(os.Getenv("HAWS_SYNC_TIMEOUT_SECONDS"))
	if err != nil || seconds <= 0 || seconds > 86400 {
		seconds = 30
	}
	timeout := time.Duration(seconds)*time.Second - 250*time.Millisecond
	if timeout <= 0 {
		return 250 * time.Millisecond
	}
	return timeout
}

func syncTargetField(value string) string {
	value = strings.NewReplacer("\t", " ", "\r", " ", "\n", " ").Replace(value)
	if value == "" {
		return "-"
	}
	return value
}

func setupAlreadyExists(root string) bool {
	store := settings.NewStore(root)
	stateDir := store.Dir
	if info, err := os.Lstat(filepath.Join(stateDir, "uninstalled")); err == nil && info.Mode().IsRegular() && info.Size() > 0 {
		return false
	}
	if _, result, err := store.ReadProgress(); err == nil && strings.Contains(result, "\tpending") {
		info, err := os.Lstat(filepath.Join(stateDir, "install.complete"))
		return err == nil && info.Mode().IsRegular() && info.Size() > 0
	}
	for _, name := range []string{"install.complete", "settings.tsv"} {
		info, err := os.Lstat(filepath.Join(stateDir, name))
		if err == nil && info.Mode().IsRegular() && info.Mode()&os.ModeSymlink == 0 && (name != "install.complete" || info.Size() > 0) {
			return true
		}
	}
	return false
}

func findRootForRun() (string, error) {
	explicitRoot := os.Getenv("HAWS_ROOT")
	appRoot := ""
	if explicitRoot != "" {
		appRoot = packageRootForPath(explicitRoot)
		if appRoot == "" {
			packageDir := os.Getenv("HAWS_PACKAGE_DIR")
			if packageDir != "" {
				appRoot = packageDir
			}
		}
		if appRoot == "" {
			return legacy.FindRoot()
		}
	} else if configured := os.Getenv("HAWS_APP_DIR"); configured != "" {
		appRoot = configured
	} else {
		executable, err := os.Executable()
		if err != nil {
			return "", fmt.Errorf("resolve HAWS executable path: %w", err)
		}
		if installedRoot, err := update.FindInstallRoot(executable, runtime.GOOS); err == nil {
			appRoot = installedRoot
		}
	}
	if appRoot == "" {
		return legacy.FindRoot()
	}
	runtimeRoot, err := update.ActiveRuntime(appRoot, runtime.GOOS)
	if err != nil {
		return "", err
	}
	return legacy.ConfigurePackageRuntime(appRoot, runtimeRoot)
}

func findPackageRootForRun() (string, error) {
	for _, candidate := range []string{os.Getenv("HAWS_APP_DIR"), os.Getenv("HAWS_PACKAGE_DIR"), os.Getenv("HAWS_ROOT")} {
		if packageRoot := packageRootForPath(candidate); packageRoot != "" {
			resolved, err := filepath.EvalSymlinks(packageRoot)
			if err != nil {
				return "", fmt.Errorf("resolve HAWS package directory: %w", err)
			}
			return resolved, nil
		}
	}
	executable, err := os.Executable()
	if err != nil {
		return "", fmt.Errorf("resolve HAWS executable path: %w", err)
	}
	packageRoot, err := update.FindInstallRoot(executable, runtime.GOOS)
	if err != nil || packageRoot == "" || !hasPackageManifest(packageRoot) {
		return "", errors.New("migration is available from an installed HAWS package; start the package launcher first")
	}
	resolved, err := filepath.EvalSymlinks(packageRoot)
	if err != nil {
		return "", fmt.Errorf("resolve HAWS package directory: %w", err)
	}
	return resolved, nil
}

func packageRootForPath(root string) string {
	absolute, err := filepath.Abs(root)
	if err != nil {
		return ""
	}
	if hasPackageManifest(absolute) {
		return absolute
	}
	if filepath.Base(absolute) == "runtime" && hasPackageManifest(filepath.Dir(absolute)) {
		return filepath.Dir(absolute)
	}
	return ""
}

func hasPackageManifest(root string) bool {
	info, err := os.Lstat(filepath.Join(root, "package-manifest.json"))
	return err == nil && info.Mode().IsRegular() && info.Mode()&os.ModeSymlink == 0
}

func commandAction(command string) tui.Action {
	switch command {
	case "setup", "bootstrap":
		return tui.ActionSetup
	case "sync", "update", "install":
		return tui.ActionSync
	case "settings", "configure":
		return tui.ActionSettings
	case "doctor", "test":
		return tui.ActionDoctor
	case "repair":
		return tui.ActionRepair
	case "uninstall", "remove":
		return tui.ActionUninstall
	default:
		return ""
	}
}

func runAction(ctx context.Context, root string, action tui.Action, args []string, stdin io.Reader, stdout, stderr io.Writer) error {
	if len(args) == 0 {
		args = []string{string(action)}
	}
	if action == tui.ActionSync {
		return app.RunSync(ctx, args, stdin, stdout, stderr)
	}
	if action == tui.ActionRepair {
		return app.RunRepair(ctx, stdin, stdout, stderr)
	}
	if action == tui.ActionSetup || action == tui.ActionSettings {
		return app.RunSettings(ctx, root, args, stdin, stdout, stderr)
	}
	if action == tui.ActionUninstall {
		return app.RunUninstall(ctx, args, stdin, stdout, stderr)
	}
	if action == tui.ActionMigration {
		packageRoot, err := findPackageRootForRun()
		if err != nil {
			return err
		}
		return app.RunMigrationWizard(packageRoot, stdin, stdout, stderr)
	}
	return legacy.RunCommand(ctx, root, args, stdin, stdout, stderr)
}

func actionExitCode(err error, stderr io.Writer) int {
	if err == nil {
		return 0
	}
	if errors.Is(err, context.Canceled) {
		fmt.Fprintln(stderr, err)
		return 130
	}
	var exitErr interface{ ExitCode() int }
	if errors.As(err, &exitErr) {
		var applyErr *app.SettingsApplyError
		if errors.As(err, &applyErr) {
			fmt.Fprintln(stderr, err)
		}
		return exitErr.ExitCode()
	}
	fmt.Fprintln(stderr, err)
	return 1
}
