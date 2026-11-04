package tui

import (
	"bufio"
	"errors"
	"fmt"
	"io"
	"strings"
)

type Action string

const (
	ActionSync      Action = "sync"
	ActionSettings  Action = "settings"
	ActionDoctor    Action = "doctor"
	ActionUninstall Action = "uninstall"
)

const homeMenu = "HAWS — Human-AI Working Standard\n\n" +
	"1) Sync\n" +
	"2) Settings\n" +
	"3) Doctor\n" +
	"4) Uninstall\n" +
	"q) Quit\n\n" +
	"Select an action: "

func Run(in io.Reader, out io.Writer, runAction func(Action) error) error {
	if in == nil || out == nil || runAction == nil {
		return errors.New("terminal input, output, and action runner are required")
	}
	reader := bufio.NewReader(in)
	for {
		if _, err := io.WriteString(out, homeMenu); err != nil {
			return err
		}
		line, readErr := reader.ReadString('\n')
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
		case "4", "uninstall":
			action = ActionUninstall
		case "q", "quit", "exit":
			return nil
		default:
			if _, err := fmt.Fprintln(out, "Choose 1, 2, 3, 4, or q."); err != nil {
				return err
			}
		}
		if action != "" {
			if err := runAction(action); err != nil {
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
