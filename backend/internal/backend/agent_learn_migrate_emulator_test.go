//go:build emulator

package backend

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"
)

func TestEmulatorLearnMigrationPlan(t *testing.T) {
	db := emulatorDB(t)
	for path, doc := range map[string]map[string]any{
		"botMemory/-100":       {"text": "**Thành viên:**\n- Cường đang tập full Đà Nẵng\n\n- Dũng đau gối\n- Nhóm chạy 6h thứ 7 hồ Tây\n- Linh thích trail\n- Hà mới vào nhóm\n- Bot gửi tin hai lần"},
		"botMemory/-old":       {"text": "- Nhóm chạy 6h thứ 7 hồ Tây\n- Cường App đi giày Pegasus"},
		"tgLinks/111":          {"uid": "cuong", "displayName": "Cường", "username": "cuong_run"},
		"publicProfiles/cuong": {"displayName": "Cường App"},
		// Người chưa liên kết: theo tg id. Hai người cùng tên Linh thì không đoán.
		"botConversations/-100/botMessages/m1": {"role": "user", "name": "Dũng", "tgUserId": "222"},
		"botConversations/-100/botMessages/m2": {"role": "user", "name": "Linh", "tgUserId": "333"},
		"botConversations/-100/botMessages/m3": {"role": "user", "name": "Linh", "tgUserId": "444"},
		"botConversations/-100/botMessages/m4": {"role": "user", "name": "Cường TG", "tgUserId": "111"},
		// Tin trước khi có tgUserId không biết là ai.
		"botConversations/-100/botMessages/m5": {"role": "user", "name": "Hà"},
	} {
		seed(t, db, path, doc)
	}
	long := strings.Repeat("x", agentMemoryMaxRunes+1)
	llm := &fakeLearn{reply: func(string, string) (string, error) {
		return fmt.Sprintf(`{"items":[
			{"text":"Cường đang tập full Đà Nẵng","person":"Cường","lines":["A2"]},
			{"text":"Cường App đi giày Pegasus","person":"cường  app","lines":["B2"]},
			{"text":"Dũng đau gối","person":"Dũng","lines":["A3"]},
			{"text":"Nhóm chạy 6h thứ 7 ở hồ Tây","person":"","lines":["A4"]},
			{"text":"Nhóm chạy 6h thứ 7 ở hồ Tây","person":"","lines":["B1"]},
			{"text":"Linh thích trail","person":"Linh","lines":["A5"]},
			{"text":"Hà mới vào nhóm","person":"Hà","lines":["A6"]},
			{"text":"%s","person":"","lines":["A1"]}
		],"dropped":[{"line":"A7","reason":"lỗi kỹ thuật"}]}`, long), nil
	}}
	svc := NewLearnService(NewAgentStore(db), llm, "-100")
	plan, err := svc.PlanMigration(context.Background(), []string{"-100", "-old"})
	if err != nil {
		t.Fatal(err)
	}
	if len(llm.calls) != 1 || llm.calls[0].system != learnMigratePrompt {
		t.Fatalf("muốn gọi model một lần với prompt migrate: %d", len(llm.calls))
	}
	in := llm.calls[0].input
	if !strings.Contains(in, "TÓM TẮT A:\n[A1] **Thành viên:**\n[A2] - Cường đang tập full Đà Nẵng\n[A3] - Dũng đau gối\n") || !strings.Contains(in, "TÓM TẮT B:\n[B1] - Nhóm chạy 6h thứ 7 hồ Tây\n[B2] - Cường App") {
		t.Fatalf("đầu vào model:\n%s", in)
	}
	var got []string
	for _, it := range plan.Items {
		got = append(got, strings.Join([]string{it.ID, it.Target, it.Text, it.Note}, " | "))
	}
	wantList(t, "items", got,
		"mig-1 | cuong | Cường đang tập full Đà Nẵng | ",
		"mig-2 | cuong | Cường App đi giày Pegasus | ",
		"mig-3 | tg-222 | Dũng đau gối | ",
		"mig-4 | _group | Nhóm chạy 6h thứ 7 ở hồ Tây | ",
		"mig-5 |  | Linh thích trail | trùng tên: tg-333, tg-444",
		"mig-6 |  | Hà mới vào nhóm | không thấy tên trong group Telegram",
	)
	// A1 chỉ nằm trong ký ức quá dài đã bị bỏ; B1 nằm trong ký ức trùng vẫn tính.
	wantList(t, "uncovered", plan.Uncovered, "A1")
	if len(plan.Lines) != 9 || plan.Lines[8].ID != "B2" || plan.Lines[8].Chat != "-old" {
		t.Fatalf("lines = %+v", plan.Lines)
	}
	if refs, err := learnedCol(db).DocumentRefs(context.Background()).GetAll(); err != nil || len(refs) != 0 {
		t.Fatalf("plan không được ghi ký ức: %v %d", err, len(refs))
	}
	if _, err := svc.PlanMigration(context.Background(), []string{"-khong-co"}); err == nil {
		t.Fatal("chat không có tóm tắt mà không báo lỗi")
	}
}

func TestEmulatorLearnMigrationApply(t *testing.T) {
	e := newLearnEnv(t)
	now := e.t0.Add(20 * time.Minute)
	var group []any
	for i := 1; i < agentLearnedLimit; i++ {
		group = append(group, map[string]any{"id": fmt.Sprintf("f%d", i), "text": fmt.Sprintf("ký ức %d", i), "createdAt": e.t0, "updatedAt": e.t0})
	}
	seed(t, e.db, "agentRooms/main/learned/_group", map[string]any{"facts": group, "nextId": agentLearnedLimit - 1, "batch": "lo-cu"})
	// Như lệnh migrate: plan đi qua file JSON rồi mới apply.
	raw, _ := json.Marshal(LearnMigration{Items: []LearnMigrationItem{
		{ID: "mig-1", Text: "Nhóm chạy 6h thứ 7", Target: agentGroupScope},
		{ID: "mig-2", Text: "Đội tiếp sức tên Sóc", Target: agentGroupScope},
		{ID: "mig-3", Text: "Cường tập full Đà Nẵng", Target: "cuong"},
		{ID: "mig-4", Text: "Hà mới vào nhóm"},
	}})
	var plan LearnMigration
	if err := json.Unmarshal(raw, &plan); err != nil {
		t.Fatal(err)
	}
	summary := func(r LearnMigrationResult) string {
		return fmt.Sprintf("added=%v existing=%v full=%v unmatched=%v", r.Added, r.Existing, r.Full, r.Unmatched)
	}
	for i, want := range []string{
		"added=[mig-1 mig-3] existing=[] full=[mig-2] unmatched=[mig-4]",
		// Chạy lại: không ghi trùng.
		"added=[] existing=[mig-1 mig-3] full=[mig-2] unmatched=[mig-4]",
	} {
		res, err := e.svc.ApplyMigration(context.Background(), &plan, now)
		if err != nil {
			t.Fatal(err)
		}
		if got := summary(res); got != want {
			t.Fatalf("lần %d: %s, muốn %s", i+1, got, want)
		}
	}
	doc := e.data("agentRooms/main/learned/_group")
	if doc["batch"] != "lo-cu" || number(doc["nextId"]) != agentLearnedLimit-1 {
		t.Fatalf("migrate xoá mất batch/nextId: %v %v", doc["batch"], doc["nextId"])
	}
	wantList(t, "ký ức Cường", e.factTexts("cuong"), "mig-3 Cường tập full Đà Nẵng")

	// Task học ghi đè cả doc sau đó: ký ức chuyển sang vẫn giữ nguồn.
	e.llm.reply = func(system, _ string) (string, error) {
		if system == learnGroupPrompt {
			return `[{"op":"UPDATE","id":"f1","text":"ký ức 1 đã sửa"}]`, nil
		}
		return "[]", nil
	}
	e.mustRun(now)
	sources := map[string]string{}
	for _, f := range liveFacts(e.data("agentRooms/main/learned/_group")["facts"], now) {
		sources[f.ID] = f.Text + "/" + f.Source
	}
	if sources["mig-1"] != "Nhóm chạy 6h thứ 7/migrated" || sources["f1"] != "ký ức 1 đã sửa/" {
		t.Fatalf("sau khi học: mig-1=%q f1=%q", sources["mig-1"], sources["f1"])
	}
}
