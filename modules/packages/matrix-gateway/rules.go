package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
	"sync"
	"time"
)

const maxFeedback = 20

type feedback struct {
	Time time.Time `json:"time"`
	Text string    `json:"text"`
}

type rule struct {
	ID          string     `json:"id"`
	Name        string     `json:"name"`
	Chat        string     `json:"chat,omitempty"`
	Sender      string     `json:"sender,omitempty"`
	Match       string     `json:"match,omitempty"`
	About       string     `json:"about,omitempty"`
	Instruction string     `json:"instruction"`
	Enabled     bool       `json:"enabled"`
	Revision    int        `json:"revision"`
	Feedback    []feedback `json:"feedback,omitempty"`
	Updated     time.Time  `json:"updated"`
}

// rulePatch uses pointers so nil leaves a field alone and "" clears it.
type rulePatch struct {
	Name        *string `json:"name"`
	Chat        *string `json:"chat"`
	Sender      *string `json:"sender"`
	Match       *string `json:"match"`
	About       *string `json:"about"`
	Instruction *string `json:"instruction"`
	Enabled     *bool   `json:"enabled"`
	Note        *string `json:"note"`
}

type ruleStore struct {
	mu       sync.Mutex
	path     string
	rules    []rule
	compiled map[string]*regexp.Regexp
}

func loadRules(path string) (*ruleStore, error) {
	s := &ruleStore{path: path, compiled: map[string]*regexp.Regexp{}}
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return s, nil
	}
	if err != nil {
		return nil, err
	}
	if err := json.Unmarshal(data, &s.rules); err != nil {
		return nil, err
	}
	for _, r := range s.rules {
		re, err := validateRule(r)
		if err != nil {
			slog.Warn("invalid stored rule", "id", r.ID, "err", err)
			continue
		}
		s.compiled[r.ID] = re
	}
	return s, nil
}

func validateRule(r rule) (*regexp.Regexp, error) {
	switch {
	case strings.TrimSpace(r.Name) == "":
		return nil, errors.New("name is required")
	case strings.TrimSpace(r.Instruction) == "":
		return nil, errors.New("instruction is required")
	case len(r.Instruction) > 1000 || len(r.About) > 500:
		return nil, errors.New("instruction or about is too long")
	case r.Chat == "" && r.Sender == "" && r.Match == "" && r.About == "":
		return nil, errors.New("set at least one of chat, sender, match or about")
	}
	if r.Match == "" {
		return nil, nil
	}
	re, err := regexp.Compile(r.Match)
	if err != nil {
		return nil, fmt.Errorf("invalid match regex: %w", err)
	}
	return re, nil
}

// save writes through a temp file so a crash never leaves half a rules file.
func (s *ruleStore) save() error {
	data, err := json.MarshalIndent(s.rules, "", "  ")
	if err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(s.path), ".rules-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), s.path)
}

func (s *ruleStore) list() []rule {
	s.mu.Lock()
	defer s.mu.Unlock()
	return slices.Clone(s.rules)
}

func (s *ruleStore) add(r rule) (rule, error) {
	re, err := validateRule(r)
	if err != nil {
		return rule{}, err
	}
	raw := make([]byte, 4)
	if _, err := rand.Read(raw); err != nil {
		return rule{}, err
	}
	r.ID = "r" + hex.EncodeToString(raw)
	r.Enabled = true
	r.Revision = 1
	r.Feedback = nil
	r.Updated = time.Now()

	s.mu.Lock()
	defer s.mu.Unlock()
	s.rules = append(s.rules, r)
	s.compiled[r.ID] = re
	return r, s.save()
}

func (s *ruleStore) update(ruleID string, p rulePatch) (rule, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	i := slices.IndexFunc(s.rules, func(r rule) bool { return r.ID == ruleID })
	if i < 0 {
		return rule{}, fmt.Errorf("no rule %s", ruleID)
	}
	r := s.rules[i]
	for _, f := range []struct {
		dst *string
		src *string
	}{{&r.Name, p.Name}, {&r.Chat, p.Chat}, {&r.Sender, p.Sender}, {&r.Match, p.Match}, {&r.About, p.About}, {&r.Instruction, p.Instruction}} {
		if f.src != nil {
			*f.dst = *f.src
		}
	}
	if p.Enabled != nil {
		r.Enabled = *p.Enabled
	}
	re, err := validateRule(r)
	if err != nil {
		return rule{}, err
	}
	if p.Note != nil && *p.Note != "" {
		r.Feedback = appendFeedback(r.Feedback, "change: "+*p.Note)
	}
	r.Revision++
	r.Updated = time.Now()
	s.rules[i] = r
	s.compiled[r.ID] = re
	return r, s.save()
}

func (s *ruleStore) remove(ruleID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	i := slices.IndexFunc(s.rules, func(r rule) bool { return r.ID == ruleID })
	if i < 0 {
		return fmt.Errorf("no rule %s", ruleID)
	}
	s.rules = slices.Delete(s.rules, i, i+1)
	delete(s.compiled, ruleID)
	return s.save()
}

func (s *ruleStore) addFeedback(ruleID, text string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	i := slices.IndexFunc(s.rules, func(r rule) bool { return r.ID == ruleID })
	if i < 0 {
		return fmt.Errorf("no rule %s", ruleID)
	}
	s.rules[i].Feedback = appendFeedback(s.rules[i].Feedback, "user: "+text)
	return s.save()
}

func appendFeedback(log []feedback, text string) []feedback {
	log = append(log, feedback{Time: time.Now(), Text: text})
	if len(log) > maxFeedback {
		log = log[len(log)-maxFeedback:]
	}
	return log
}

// candidates returns enabled rules whose cheap filters match; "about" is judged later by the model.
func (s *ruleStore) candidates(r record) []rule {
	s.mu.Lock()
	defer s.mu.Unlock()
	chat, sender := strings.ToLower(r.Chat), strings.ToLower(r.Sender)
	var out []rule
	for _, rl := range s.rules {
		if !rl.Enabled {
			continue
		}
		if rl.Chat != "" && !strings.Contains(chat, strings.ToLower(rl.Chat)) {
			continue
		}
		if rl.Sender != "" && !strings.Contains(sender, strings.ToLower(rl.Sender)) {
			continue
		}
		if re := s.compiled[rl.ID]; re != nil && !re.MatchString(r.Body) {
			continue
		}
		if rl.Match != "" && s.compiled[rl.ID] == nil {
			continue
		}
		out = append(out, rl)
	}
	return out
}
