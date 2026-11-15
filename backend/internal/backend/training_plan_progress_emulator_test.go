//go:build emulator

package backend

import (
	"context"
	"reflect"
	"testing"
	"time"

	"cloud.google.com/go/firestore"
)

func seedPlanRun(t *testing.T, db *firestore.Client, uid, id, day string, meters float64) {
	t.Helper()
	seed(t, db, "users/"+uid+"/activities/"+id, map[string]any{
		"source": "strava", "sportType": "Run",
		"startedAt":         planTestTime(day, 6).UTC().Format(time.RFC3339),
		"distanceMeters":    meters,
		"movingTimeSeconds": 1800, "elapsedTimeSeconds": 1800,
	})
}

func planParticipant(t *testing.T, db *firestore.Client, uid string) map[string]any {
	t.Helper()
	snap, err := db.Doc("coachPlans/an").Get(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	part, _ := snap.Data()["participants"].(map[string]any)[uid].(map[string]any)
	return part
}

// "an" chạy đủ buổi tempo 04/11, "binh" theo cùng giáo án nhưng chỉ chạy 2 km.
func TestEmulatorMarkPlanSessions(t *testing.T) {
	db := emulatorDB(t)
	ctx := context.Background()
	plan := planTestDoc(map[string]any{"doneIndices": []int{}})
	plan["status"] = "active"
	plan["participants"].(map[string]any)["binh"] = map[string]any{"doneIndices": []int{}}
	plan["participantUids"] = []string{"an", "binh"}
	seed(t, db, "coachPlans/an", plan)
	seedPlanRun(t, db, "an", "a-tempo", "2026-11-04", 6100)
	seedPlanRun(t, db, "binh", "b-short", "2026-11-04", 2000)
	now := planTestTime("2026-11-04", 20)

	// Chạy thử thì chỉ báo, không ghi.
	marks, err := MarkPlanSessions(ctx, db, now, true)
	if err != nil {
		t.Fatal(err)
	}
	want := []PlanSessionMark{{PlanID: "an", UID: "an", DayIndex: 2, ActivityID: "a-tempo"}}
	if !reflect.DeepEqual(marks, want) {
		t.Fatalf("chạy thử = %+v, muốn %+v", marks, want)
	}
	if got := toAnySlice(planParticipant(t, db, "an")["doneIndices"]); len(got) != 0 {
		t.Fatalf("chạy thử mà đã ghi: %v", got)
	}

	if marks, err = MarkPlanSessions(ctx, db, now, false); err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(marks, want) {
		t.Fatalf("đánh dấu = %+v, muốn %+v", marks, want)
	}
	an := planParticipant(t, db, "an")
	if got := toAnySlice(an["doneIndices"]); !reflect.DeepEqual(got, []any{int64(2)}) {
		t.Fatalf("doneIndices của an = %v", got)
	}
	if got := an["matched"].(map[string]any)["2"]; got != "a-tempo" {
		t.Fatalf("activity khớp = %v", got)
	}
	if got := toAnySlice(planParticipant(t, db, "binh")["doneIndices"]); len(got) != 0 {
		t.Fatalf("binh chạy 2 km mà được tick: %v", got)
	}

	// an bỏ tick buổi đó: lượt sau không tick lại.
	if _, err := db.Doc("coachPlans/an").Update(ctx, []firestore.Update{
		{FieldPath: firestore.FieldPath{"participants", "an", "doneIndices"}, Value: firestore.ArrayRemove(2)},
	}); err != nil {
		t.Fatal(err)
	}
	if marks, err = MarkPlanSessions(ctx, db, now, false); err != nil || len(marks) != 0 {
		t.Fatalf("lượt sau = %+v, %v", marks, err)
	}
	if got := toAnySlice(planParticipant(t, db, "an")["doneIndices"]); len(got) != 0 {
		t.Fatalf("buổi đã bỏ tick bị tick lại: %v", got)
	}

	// binh chạy thêm 3 km cùng ngày: đủ 5/6 km, tick riêng cho binh.
	seedPlanRun(t, db, "binh", "b-more", "2026-11-04", 3000)
	marks, err = MarkPlanSessionsForUser(ctx, db, "binh", now)
	if err != nil {
		t.Fatal(err)
	}
	want = []PlanSessionMark{{PlanID: "an", UID: "binh", DayIndex: 2, ActivityID: "b-more"}}
	if !reflect.DeepEqual(marks, want) {
		t.Fatalf("đánh dấu cho binh = %+v, muốn %+v", marks, want)
	}
	if got := toAnySlice(planParticipant(t, db, "binh")["doneIndices"]); !reflect.DeepEqual(got, []any{int64(2)}) {
		t.Fatalf("doneIndices của binh = %v", got)
	}
}
