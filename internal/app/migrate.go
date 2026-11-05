package app

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"strings"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/migration"
)

// RunMigration previews and records a reference to an existing HAWS install.
// It never copies, moves, or deletes the legacy data.
func RunMigration(packageRoot string, args []string, stdin io.Reader, stdout, stderr io.Writer) error {
	flags := flag.NewFlagSet("migrate", flag.ContinueOnError)
	flags.SetOutput(stderr)
	from := flags.String("from", "", "existing HAWS checkout directory")
	stateDir := flags.String("state", "", "existing HAWS state directory (defaults to .haws/state)")
	brainDir := flags.String("second-brain", "", "existing Second Brain directory (defaults to secondbrain/ when present)")
	show := flags.Bool("show", false, "show the current migration reference")
	clear := flags.Bool("clear", false, "remove the migration reference while keeping all referenced data")
	yes := flags.Bool("yes", false, "confirm the displayed migration action")
	flags.Usage = func() {
		_, _ = fmt.Fprintln(stderr, "Usage: haws migrate --from CHECKOUT [--state DIR] [--second-brain DIR] [--yes]")
		_, _ = fmt.Fprintln(stderr, "       haws migrate --show | --clear [--yes]")
		flags.PrintDefaults()
	}
	if err := flags.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return nil
		}
		return err
	}
	if flags.NArg() != 0 {
		return errors.New("migrate does not accept positional arguments")
	}
	if *clear && (*from != "" || *stateDir != "" || *brainDir != "" || *show) {
		return errors.New("--clear cannot be combined with --from, --state, --second-brain, or --show")
	}
	if *show && (*from != "" || *stateDir != "" || *brainDir != "") {
		return errors.New("--show cannot be combined with migration paths")
	}

	var current migration.Profile
	var exists bool
	var err error
	if *clear {
		current, exists, err = migration.LoadPackageProfileForClear(packageRoot)
	} else {
		current, exists, err = migration.LoadPackageProfile(packageRoot)
	}
	if err != nil {
		return err
	}
	if *clear {
		if !exists {
			_, err := fmt.Fprintln(stdout, "No legacy migration reference is configured.")
			return err
		}
		if err := printMigrationPreview(stdout, "Remove migration reference", current); err != nil {
			return err
		}
		if _, err := fmt.Fprintln(stdout, "Only the package's reference file will be removed. The legacy checkout and all data remain in place."); err != nil {
			return err
		}
		confirmed, err := confirmMigration(stdin, stdout, *yes)
		if err != nil || !confirmed {
			if err == nil {
				_, err = fmt.Fprintln(stdout, "No changes were made.")
			}
			return err
		}
		if err := migration.ClearPackageProfile(packageRoot, current); err != nil {
			return err
		}
		_, err = fmt.Fprintln(stdout, "Legacy migration reference removed. Existing data was kept.")
		return err
	}
	if *show || *from == "" {
		if !exists {
			_, err := fmt.Fprintln(stdout, "No legacy migration reference is configured.")
			return err
		}
		return printMigrationPreview(stdout, "Current legacy migration reference", current)
	}
	if exists {
		return errors.New("a legacy migration reference already exists; use --show or clear it before setting a different one")
	}
	profile, err := migration.BuildProfile(*from, *stateDir, *brainDir)
	if err != nil {
		return err
	}
	if err := printMigrationPreview(stdout, "Legacy HAWS migration preview", profile); err != nil {
		return err
	}
	if _, err := fmt.Fprintln(stdout, "HAWS will save one reference inside this package. It will reuse your current settings, sources, skills, ownership records, integrations, and Second Brain in place."); err != nil {
		return err
	}
	if _, err := fmt.Fprintln(stdout, "No files will be copied, moved, or deleted from the legacy installation."); err != nil {
		return err
	}
	confirmed, err := confirmMigration(stdin, stdout, *yes)
	if err != nil || !confirmed {
		if err == nil {
			_, err = fmt.Fprintln(stdout, "No changes were made.")
		}
		return err
	}
	if err := migration.SavePackageProfile(packageRoot, profile); err != nil {
		return err
	}
	_, err = fmt.Fprintln(stdout, "Migration reference saved. Your existing data stays in its current location and will be used on the next HAWS launch.")
	return err
}

// RunMigrationWizard offers migration from the Home TUI using the common
// checkout layout. Advanced paths remain available through `haws migrate`.
func RunMigrationWizard(packageRoot string, stdin io.Reader, stdout, stderr io.Writer) error {
	if _, err := fmt.Fprint(stdout, "Path to your existing HAWS checkout (press Enter to cancel): "); err != nil {
		return err
	}
	path, err := readRepairConfirmation(stdin)
	if err != nil && !errors.Is(err, io.EOF) {
		return err
	}
	path = strings.TrimSpace(path)
	if path == "" {
		_, writeErr := fmt.Fprintln(stdout, "Migration cancelled. No changes were made.")
		return writeErr
	}
	return RunMigration(packageRoot, []string{"--from", path}, stdin, stdout, stderr)
}

func printMigrationPreview(out io.Writer, title string, profile migration.Profile) error {
	if _, err := fmt.Fprintf(out, "%s:\n", title); err != nil {
		return err
	}
	if _, err := fmt.Fprintf(out, "  HAWS checkout: %q\n  Settings and source state: %q\n", profile.LegacyRoot, profile.StateDir); err != nil {
		return err
	}
	brain := profile.SecondBrainDir
	if brain == "" {
		brain = "not selected; package Second Brain remains active"
	}
	if profile.SecondBrainDir != "" {
		brain = fmt.Sprintf("%q", brain)
	}
	_, err := fmt.Fprintf(out, "  Second Brain: %s\n", brain)
	return err
}

func confirmMigration(stdin io.Reader, stdout io.Writer, alreadyConfirmed bool) (bool, error) {
	if alreadyConfirmed {
		return true, nil
	}
	if _, err := fmt.Fprint(stdout, "Continue? [y/N]: "); err != nil {
		return false, err
	}
	answer, err := readRepairConfirmation(stdin)
	if err != nil && !errors.Is(err, io.EOF) {
		return false, err
	}
	return strings.EqualFold(strings.TrimSpace(answer), "y"), nil
}
