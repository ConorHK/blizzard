package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"slices"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
)

type rpcResponse struct {
	ID      string          `json:"id"`
	Type    string          `json:"type"`
	Success bool            `json:"success"`
	Error   string          `json:"error"`
	Data    json.RawMessage `json:"data"`
}

// agent drives one long-lived `pi --mode rpc` child over JSONL.
type agent struct {
	stdin   io.WriteCloser
	turn    sync.Mutex
	write   sync.Mutex
	pending sync.Map
	settled chan struct{}
	done    chan struct{}
	nextID  atomic.Int64
}

// startAgent never passes the Matrix secrets, plus any variables named in hide, to the child.
func startAgent(ctx context.Context, command string, hide ...string) (*agent, error) {
	cmd := exec.CommandContext(ctx, command)
	cmd.Stderr = os.Stderr
	hide = append(hide, "MATRIX_PASSWORD", "MATRIX_PICKLE_KEY")
	for _, kv := range os.Environ() {
		name, _, _ := strings.Cut(kv, "=")
		if !slices.Contains(hide, name) {
			cmd.Env = append(cmd.Env, kv)
		}
	}
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return nil, err
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	a := &agent{
		stdin:   stdin,
		settled: make(chan struct{}, 1),
		done:    make(chan struct{}),
	}
	go a.read(stdout)
	go func() {
		_ = cmd.Wait()
		close(a.done)
	}()
	return a, nil
}

func (a *agent) read(stdout io.Reader) {
	// pi frames records on LF only, so a bufio.Scanner token limit would break long replies.
	reader := bufio.NewReader(stdout)
	for {
		line, err := reader.ReadBytes('\n')
		if len(line) > 0 {
			var rec rpcResponse
			if json.Unmarshal(line, &rec) == nil {
				switch rec.Type {
				case "response":
					if ch, ok := a.pending.LoadAndDelete(rec.ID); ok {
						ch.(chan rpcResponse) <- rec
					}
				case "agent_settled":
					select {
					case a.settled <- struct{}{}:
					default:
					}
				}
			}
		}
		if err != nil {
			return
		}
	}
}

func (a *agent) call(ctx context.Context, command map[string]any) (rpcResponse, error) {
	id := strconv.FormatInt(a.nextID.Add(1), 10)
	command["id"] = id
	line, err := json.Marshal(command)
	if err != nil {
		return rpcResponse{}, err
	}
	ch := make(chan rpcResponse, 1)
	a.pending.Store(id, ch)
	defer a.pending.Delete(id)

	a.write.Lock()
	_, err = a.stdin.Write(append(line, '\n'))
	a.write.Unlock()
	if err != nil {
		return rpcResponse{}, err
	}

	select {
	case resp := <-ch:
		if !resp.Success {
			return resp, fmt.Errorf("%s: %s", command["type"], resp.Error)
		}
		return resp, nil
	case <-a.done:
		return rpcResponse{}, errors.New("agent exited")
	case <-ctx.Done():
		return rpcResponse{}, ctx.Err()
	}
}

func (a *agent) ask(ctx context.Context, message string) (string, error) {
	a.turn.Lock()
	defer a.turn.Unlock()

	select {
	case <-a.settled:
	default:
	}

	resp, err := a.call(ctx, map[string]any{"type": "prompt", "message": message})
	if err != nil {
		return "", err
	}
	var started struct {
		Disposition string `json:"disposition"`
	}
	_ = json.Unmarshal(resp.Data, &started)
	if started.Disposition != "handled" {
		select {
		case <-a.settled:
		case <-a.done:
			return "", errors.New("agent exited")
		case <-ctx.Done():
			_, _ = a.call(context.Background(), map[string]any{"type": "abort"})
			return "", ctx.Err()
		}
	}

	resp, err = a.call(ctx, map[string]any{"type": "get_last_assistant_text"})
	if err != nil {
		return "", err
	}
	var last struct {
		Text *string `json:"text"`
	}
	if err := json.Unmarshal(resp.Data, &last); err != nil {
		return "", err
	}
	if last.Text == nil {
		return "", errors.New("no reply")
	}
	return *last.Text, nil
}

func (a *agent) reset(ctx context.Context) error {
	a.turn.Lock()
	defer a.turn.Unlock()
	_, err := a.call(ctx, map[string]any{"type": "new_session"})
	return err
}
