package app

import (
	"context"
	"errors"
	"fmt"
	"io"
	"os/exec"
	"strings"

	"github.com/apirak-k/Human-AI-Working-Standard/internal/legacy"
)

// RunRepair shows read-only diagnostics and a Sync-based repair plan before
// applying the existing verified update and enabled-component path.
func RunRepair(ctx context.Context, stdin io.Reader, stdout, stderr io.Writer) error {
	root, err := legacy.FindRoot()
	if err != nil {
		return err
	}
	doctorErr := legacy.RunCommand(ctx, root, []string{"doctor", "--deep"}, strings.NewReader(""), stdout, stderr)
	if doctorErr != nil {
		var exitErr *exec.ExitError
		if !errors.As(doctorErr, &exitErr) || exitErr.ExitCode() != 1 {
			return fmt.Errorf("run read-only HAWS diagnostics: %w", doctorErr)
		}
	}
	if _, err := fmt.Fprintln(stdout, "\nHAWS Repair plan (no changes made yet):\n  • Apply a verified HAWS app update when Auto Update is enabled and an update is available.\n  • Run one Sync for enabled sources and integrations.\n  • Preserve modified or unowned destinations reported by ownership checks."); err != nil {
		return err
	}
	if _, err := fmt.Fprint(stdout, "Apply this repair plan? [y/N]: "); err != nil {
		return err
	}
	answer, readErr := readRepairConfirmation(stdin)
	if readErr != nil && !errors.Is(readErr, io.EOF) {
		return fmt.Errorf("read repair confirmation: %w", readErr)
	}
	if !strings.EqualFold(strings.TrimSpace(answer), "y") {
		_, err := fmt.Fprintln(stdout, "No changes were made.")
		return err
	}
	return RunSync(ctx, nil, strings.NewReader(""), stdout, stderr)
}

func readRepairConfirmation(input io.Reader) (string, error) {
	var answer strings.Builder
	buffer := []byte{0}
	for {
		n, err := io.ReadFull(input, buffer)
		if n > 0 {
			if buffer[0] == '\n' {
				return answer.String(), nil
			}
			answer.WriteByte(buffer[0])
		}
		if err != nil {
			if errors.Is(err, io.EOF) || errors.Is(err, io.ErrUnexpectedEOF) {
				return answer.String(), io.EOF
			}
			return answer.String(), err
		}
	}
}
