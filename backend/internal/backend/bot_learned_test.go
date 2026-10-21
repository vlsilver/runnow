package backend

import "testing"

func TestBotRecentPeople(t *testing.T) {
	rows := []map[string]any{
		{"role": "user", "tgUserId": "2", "name": "B"},
		{"role": "model", "tgUserId": "9", "name": "bot"},
		{"role": "user", "tgUserId": "1", "name": "A cũ"},
		{"role": "user", "name": "không id"},
	}
	for i := 3; i < 20; i++ {
		rows = append(rows, map[string]any{"role": "user", "tgUserId": string(rune('a' + i)), "name": "x"})
	}
	got := botRecentPeople("1", "A", rows)
	if len(got) != botLearnedPeople || got[0] != (learnedSubject{tg: "1", name: "A"}) || got[1].tg != "2" || got[2].tg != "d" {
		t.Fatalf("botRecentPeople = %+v", got)
	}
}
