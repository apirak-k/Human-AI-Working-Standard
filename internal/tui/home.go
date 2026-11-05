package tui

import (
	"errors"
	"fmt"
	"io"
	"strings"
)

type Action string

const (
	ActionSetup     Action = "setup"
	ActionSync      Action = "sync"
	ActionSettings  Action = "settings"
	ActionDoctor    Action = "doctor"
	ActionRepair    Action = "repair"
	ActionUninstall Action = "uninstall"
)

const homeMenu = "HAWS — Human-AI Working Standard\n\n" +
	"1) Sync\n" +
	"2) Settings\n" +
	"3) Doctor\n" +
	"4) Repair\n" +
	"5) Uninstall\n" +
	"6) Setup\n" +
	"q) Quit\n\n" +
	"Select an action: "

func Run(in io.Reader, out io.Writer, runAction func(Action, io.Reader) error) error {
	if in == nil || out == nil || runAction == nil {
		return errors.New("terminal input, output, and action runner are required")
	}
	for {
		if _, err := io.WriteString(out, homeMenu); err != nil {
			return err
		}
		line, readErr := readLine(in)
		if readErr != nil && !errors.Is(readErr, io.EOF) {
			return readErr
		}
		if errors.Is(readErr, io.EOF) && line == "" {
			return nil
		}

		choice := strings.ToLower(strings.TrimSpace(line))
		var action Action
		switch choice {
		case "1", "sync":
			action = ActionSync
		case "2", "settings":
			action = ActionSettings
		case "3", "doctor":
			action = ActionDoctor
		case "4", "repair":
			action = ActionRepair
		case "5", "uninstall":
			action = ActionUninstall
		case "6", "setup":
			action = ActionSetup
		case "q", "quit", "exit":
			return nil
		default:
			if _, err := fmt.Fprintln(out, "Choose 1, 2, 3, 4, 5, 6, or q."); err != nil {
				return err
			}
		}
		if action != "" {
			if err := runAction(action, in); err != nil {
				if _, writeErr := fmt.Fprintf(out, "Action failed: %v\n", err); writeErr != nil {
					return writeErr
				}
			}
		}
		if errors.Is(readErr, io.EOF) {
			return nil
		}
	}
}

func readLine(input io.Reader) (string, error) {
	var line strings.Builder
	buffer := []byte{0}
	for {
		n, err := io.ReadFull(input, buffer)
		if n > 0 {
			if buffer[0] == '\n' {
				return line.String(), nil
			}
			line.WriteByte(buffer[0])
		}
		if err != nil {
			if errors.Is(err, io.EOF) || errors.Is(err, io.ErrUnexpectedEOF) {
				return line.String(), io.EOF
			}
			return line.String(), err
		}
	}
}
