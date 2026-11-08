package main

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net"
	"net/http"
	"os"
	"strconv"
)

// listenUnix serves a handler on a socket only this service's user can reach.
func listenUnix(ctx context.Context, path string, handler http.Handler) error {
	_ = os.Remove(path)
	listener, err := net.Listen("unix", path)
	if err != nil {
		return err
	}
	if err := os.Chmod(path, 0o600); err != nil {
		return err
	}
	server := &http.Server{Handler: handler}
	go func() {
		<-ctx.Done()
		_ = server.Close()
	}()
	go func() {
		if err := server.Serve(listener); err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("serve socket", "path", path, "err", err)
		}
	}()
	return nil
}

func chatHandler(buf *buffer, known *rooms) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /chats", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, buf.chats(known.portals(r.Context())))
	})
	mux.HandleFunc("GET /messages", func(w http.ResponseWriter, r *http.Request) {
		limit, err := strconv.Atoi(r.URL.Query().Get("limit"))
		if err != nil || limit < 1 || limit > 100 {
			limit = 30
		}
		writeJSON(w, http.StatusOK, buf.recent(r.URL.Query().Get("chat"), limit))
	})
	return mux
}

// rulesHandler sits on its own socket so the rule worker, which reads untrusted messages, cannot edit rules.
func rulesHandler(store *ruleStore) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /rules", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, store.list())
	})
	mux.HandleFunc("POST /rules", func(w http.ResponseWriter, r *http.Request) {
		var in rule
		if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
			writeError(w, err)
			return
		}
		out, err := store.add(in)
		if err != nil {
			writeError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, out)
	})
	mux.HandleFunc("PATCH /rules/{id}", func(w http.ResponseWriter, r *http.Request) {
		var patch rulePatch
		if err := json.NewDecoder(r.Body).Decode(&patch); err != nil {
			writeError(w, err)
			return
		}
		out, err := store.update(r.PathValue("id"), patch)
		if err != nil {
			writeError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, out)
	})
	mux.HandleFunc("DELETE /rules/{id}", func(w http.ResponseWriter, r *http.Request) {
		if err := store.remove(r.PathValue("id")); err != nil {
			writeError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, map[string]bool{"deleted": true})
	})
	return mux
}

func writeError(w http.ResponseWriter, err error) {
	writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(value); err != nil {
		slog.Error("encode response", "err", err)
	}
}
