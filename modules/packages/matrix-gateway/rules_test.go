package main

import (
	"path/filepath"
	"testing"
)

func ptr[T any](v T) *T { return &v }

func TestRuleLifecycle(t *testing.T) {
	path := filepath.Join(t.TempDir(), "rules.json")
	store, err := loadRules(path)
	if err != nil {
		t.Fatal(err)
	}

	if _, err := store.add(rule{Name: "x", Instruction: "y"}); err == nil {
		t.Fatal("rule without filters was accepted")
	}
	if _, err := store.add(rule{Name: "x", Instruction: "y", Match: "("}); err == nil {
		t.Fatal("invalid regex was accepted")
	}

	added, err := store.add(rule{Name: "rent", Instruction: "Summarise.", Chat: "house", Match: "(?i)rent"})
	if err != nil {
		t.Fatal(err)
	}
	if !added.Enabled || added.Revision != 1 {
		t.Fatalf("unexpected new rule: %+v", added)
	}

	msg := record{Chat: "House share", Sender: "Sam", Body: "RENT is due"}
	if got := store.candidates(msg); len(got) != 1 {
		t.Fatalf("expected one match, got %d", len(got))
	}
	if got := store.candidates(record{Chat: "Work", Body: "rent"}); len(got) != 0 {
		t.Fatal("chat filter did not exclude other chats")
	}

	updated, err := store.update(added.ID, rulePatch{Match: ptr(""), About: ptr("money owed"), Note: ptr("too narrow")})
	if err != nil {
		t.Fatal(err)
	}
	if updated.Revision != 2 || updated.Match != "" || len(updated.Feedback) != 1 {
		t.Fatalf("unexpected update: %+v", updated)
	}
	if got := store.candidates(record{Chat: "House share", Body: "anything"}); len(got) != 1 {
		t.Fatal("cleared regex still filtered messages")
	}

	if err := store.addFeedback(added.ID, "good"); err != nil {
		t.Fatal(err)
	}
	if _, err := store.update(added.ID, rulePatch{Enabled: ptr(false)}); err != nil {
		t.Fatal(err)
	}
	if got := store.candidates(msg); len(got) != 0 {
		t.Fatal("disabled rule still matched")
	}

	reloaded, err := loadRules(path)
	if err != nil {
		t.Fatal(err)
	}
	rules := reloaded.list()
	if len(rules) != 1 || rules[0].Revision != 3 || len(rules[0].Feedback) != 2 {
		t.Fatalf("rules did not persist: %+v", rules)
	}

	if err := reloaded.remove(added.ID); err != nil {
		t.Fatal(err)
	}
	if len(reloaded.list()) != 0 {
		t.Fatal("rule was not removed")
	}
}
