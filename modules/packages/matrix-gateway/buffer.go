package main

import (
	"slices"
	"strings"
	"sync"
	"time"
)

type record struct {
	ID     string
	Time   time.Time
	Chat   string
	Sender string
	Body   string
}

type chatSummary struct {
	Chat     string `json:"chat"`
	Messages int    `json:"messages"`
	Last     string `json:"last"`
}

type messageView struct {
	Time   string `json:"time"`
	Chat   string `json:"chat"`
	Sender string `json:"sender"`
	Body   string `json:"body"`
}

// buffer keeps recent bridged messages in memory only, so bodies never reach disk.
type buffer struct {
	mu    sync.Mutex
	items []record
	seen  map[string]struct{}
	max   int
}

func newBuffer(max int) *buffer {
	return &buffer{max: max, seen: map[string]struct{}{}}
}

func (b *buffer) add(r record) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if _, ok := b.seen[r.ID]; ok {
		return
	}
	b.seen[r.ID] = struct{}{}
	// Backfill can deliver older messages after live ones, so insert in time order.
	i := len(b.items)
	for i > 0 && b.items[i-1].Time.After(r.Time) {
		i--
	}
	b.items = slices.Insert(b.items, i, r)
	for len(b.items) > b.max {
		delete(b.seen, b.items[0].ID)
		b.items = b.items[1:]
	}
}

func (b *buffer) recent(chat string, limit int) []messageView {
	b.mu.Lock()
	defer b.mu.Unlock()
	chat = strings.ToLower(chat)
	out := []messageView{}
	for i := len(b.items) - 1; i >= 0 && len(out) < limit; i-- {
		r := b.items[i]
		if chat != "" && !strings.Contains(strings.ToLower(r.Chat), chat) {
			continue
		}
		out = append(out, messageView{
			Time:   r.Time.Local().Format("2006-01-02 15:04"),
			Chat:   r.Chat,
			Sender: r.Sender,
			Body:   r.Body,
		})
	}
	for i, j := 0, len(out)-1; i < j; i, j = i+1, j-1 {
		out[i], out[j] = out[j], out[i]
	}
	return out
}

// chats lists every joined portal, including silent ones, so coverage is visible before anyone speaks.
func (b *buffer) chats(portals []string) []chatSummary {
	b.mu.Lock()
	defer b.mu.Unlock()
	index := map[string]int{}
	out := []chatSummary{}
	for _, r := range b.items {
		i, ok := index[r.Chat]
		if !ok {
			i = len(out)
			index[r.Chat] = i
			out = append(out, chatSummary{Chat: r.Chat})
		}
		out[i].Messages++
		out[i].Last = r.Time.Local().Format("2006-01-02 15:04")
	}
	for _, name := range portals {
		if _, ok := index[name]; !ok {
			index[name] = len(out)
			out = append(out, chatSummary{Chat: name})
		}
	}
	return out
}
