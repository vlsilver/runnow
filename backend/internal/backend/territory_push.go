package backend

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"sort"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// PushTaken gửi push "bị chiếm ô" cho buổi activityID của uid. Chạy hẹn sau
// pushDelay để buổi của người chạy cùng kịp lưu, rồi tính lại ai bị chiếm trên
// các buổi có lúc này, không đọc territory.result. Claim một lần bằng Create lên
// territoryPushes, doc riêng nên không bao giờ dựng lại doc buổi đã xoá.
func (s *TerritoryService) PushTaken(ctx context.Context, uid, activityID string, now time.Time) error {
	cfg, err := loadTerritoryConfig(ctx, s.db)
	if err != nil {
		return err
	}
	if !cfg.Enabled || s.push == nil {
		return nil
	}
	claim := s.db.Collection("territoryPushes").Doc(uid + "_" + activityID)
	if done, err := getData(ctx, claim); err != nil || done != nil {
		return err
	}
	ref := s.db.Collection("users").Doc(uid).Collection("activities").Doc(activityID)
	snap, err := ref.Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil
	}
	if err != nil {
		return err
	}
	d := territoryDoc{ref: ref, data: snap.Data(), fact: activityFact(activityID, snap.Data())}
	if d.territory()["counted"] != true || !cfg.resultsOn(d.endedAt()) {
		return nil
	}
	dupPushed, err := s.duplicatePushed(ctx, uid, d)
	if err != nil || dupPushed {
		return err
	}
	res, others, err := s.outcome(ctx, uid, d, cfg)
	if err != nil {
		return err
	}
	ended := d.endedAt()
	// Mỗi người bị chiếm mở push ở chunk của một ô chính họ mất (ô nhỏ nhất
	// theo id, để chạy lại ra cùng chunk), không phải ô của người khác.
	victims := map[string]int{}
	victimChunk := map[string]string{}
	cells := make([]string, 0, len(res.TakenCells))
	for cell := range res.TakenCells {
		cells = append(cells, cell)
	}
	sort.Strings(cells)
	for _, cell := range cells {
		victim := res.TakenCells[cell]
		if ranTogether(others[cell], victim, ended, cfg.QuietCoRun) {
			continue
		}
		victims[victim]++
		if _, ok := victimChunk[victim]; !ok {
			if c, err := parseTileID(cell); err == nil {
				victimChunk[victim] = chunkOf(c).id()
			}
		}
	}
	// Đọc tên trước khi claim: lỗi DB ở đây thì task chạy lại, không mất push.
	profile, err := resolveProfile(ctx, s.db, uid)
	if err != nil {
		return err
	}
	if _, err := claim.Create(ctx, map[string]any{"uid": uid, "activityId": activityID, "victims": len(victims), "createdAt": firestore.ServerTimestamp, "expireAt": now.Add(30 * 24 * time.Hour)}); err != nil {
		if status.Code(err) == codes.AlreadyExists {
			return nil
		}
		return err
	}
	if len(victims) == 0 {
		return nil
	}
	name := preferredName(profile)
	uids := make([]string, 0, len(victims))
	for v := range victims {
		uids = append(uids, v)
	}
	sort.Strings(uids)
	for _, v := range uids {
		note := pushNote{
			Title: "Lãnh địa",
			Body:  fmt.Sprintf("%s vừa chiếm %d ô của bạn", name, victims[v]),
			Data:  map[string]string{"kind": territoryPushKind, "chunk": victimChunk[v], "uid": uid, "activityId": activityID},
		}
		if err := s.push.Send(ctx, []string{v}, note); err != nil {
			slog.WarnContext(ctx, "territory.push_failed", "uid", uid, "activityId", activityID, "victim", v, "error", err)
		}
	}
	slog.InfoContext(ctx, "territory.push_sent", "uid", uid, "activityId", activityID, "victims", len(uids))
	return nil
}

// ranTogether: người bị chiếm có lượt qua ô này cách buổi chiếm không quá
// quiet, theo cả hai chiều, tức hai người chạy cùng nhau.
func ranTogether(passes []territoryPass, victim string, ended time.Time, quiet time.Duration) bool {
	for _, p := range passes {
		if p.UID != victim {
			continue
		}
		gap := p.EndedAt.Sub(ended)
		if gap < 0 {
			gap = -gap
		}
		if gap <= quiet {
			return true
		}
	}
	return false
}

// duplicatePushed: một bản khác của cùng lần chạy (3i và Strava) đã push rồi.
// Xét sameRun cả hai chiều, vì sameRun chia phần trùng cho thời lượng của buổi
// đứng trước, và xét cả duplicateOfActivityId.
func (s *TerritoryService) duplicatePushed(ctx context.Context, uid string, d territoryDoc) (bool, error) {
	from := d.fact.StartedAt.Add(-48 * time.Hour).UTC().Format(time.RFC3339Nano)
	iter := s.db.Collection("users").Doc(uid).Collection("activities").
		Where("startedAt", ">=", from).Select(territoryActivityFields...).Documents(ctx)
	defer iter.Stop()
	for {
		snap, err := iter.Next()
		if errors.Is(err, iterator.Done) {
			return false, nil
		}
		if err != nil {
			return false, err
		}
		if snap.Ref.ID == d.ref.ID {
			continue
		}
		other := activityFact(snap.Ref.ID, snap.Data())
		linked := stringValue(snap.Data()["duplicateOfActivityId"]) == d.ref.ID || stringValue(d.data["duplicateOfActivityId"]) == snap.Ref.ID
		if !linked && !sameRun(d.fact, other) && !sameRun(other, d.fact) {
			continue
		}
		claimed, err := getData(ctx, s.db.Collection("territoryPushes").Doc(uid+"_"+snap.Ref.ID))
		if err != nil {
			return false, err
		}
		if claimed != nil {
			return true, nil
		}
	}
}

// Daily là việc hằng ngày: hẹn tính lại từng chunk (ô hết lượt bị bỏ, chủ đổi
// khi km trôi khỏi cửa sổ), mỗi chunk một task để một request không phải làm
// hết, và xoá doc owners không còn mục nào. Sync của từng người đã chạy hằng
// ngày qua refresh-leaderboard → rebuild-derived-data.
func (s *TerritoryService) Daily(ctx context.Context, now time.Time) error {
	refs, err := s.db.Collection("territoryChunks").DocumentRefs(ctx).GetAll()
	if err != nil {
		return err
	}
	day := dateKey(now)
	for _, ref := range refs {
		if _, err := s.tasks.Publish(ctx, PublishTask{Queue: QueueTerritory, HandlerPath: territoryRebuildPath,
			Payload: map[string]any{"chunks": []string{ref.ID}}, TaskID: "territory-rebuild-" + day + "-" + ref.ID}); err != nil {
			return err
		}
	}
	owners, err := s.db.Collection("territoryOwners").Documents(ctx).GetAll()
	if err != nil {
		return err
	}
	for _, o := range owners {
		by, _ := o.Data()["byChunk"].(map[string]any)
		if len(by) > 0 {
			continue
		}
		if _, err := o.Ref.Delete(ctx, firestore.LastUpdateTime(o.UpdateTime)); err != nil && status.Code(err) != codes.FailedPrecondition {
			return err
		}
	}
	slog.InfoContext(ctx, "territory.daily", "chunks", len(refs), "owners", len(owners))
	return nil
}

// RebuildChunks tính lại các chunk cho trước; dùng sau khi xoá tài khoản.
func (s *TerritoryService) RebuildChunks(ctx context.Context, chunks []string, now time.Time) error {
	cfg, err := loadTerritoryConfig(ctx, s.db)
	if err != nil {
		return err
	}
	for _, c := range chunks {
		if err := s.RebuildChunk(ctx, c, now, cfg); err != nil {
			return err
		}
	}
	return nil
}

func (s *Server) territoryRoutes() {
	s.route("POST "+territorySyncPath, func(w http.ResponseWriter, r *http.Request) error {
		var task struct{ UID, Cause string }
		if decodeJSON(r, &task) != nil || task.UID == "" {
			w.WriteHeader(204)
			return nil
		}
		if err := s.deps.Territory.Sync(r.Context(), task.UID, s.now()); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	})
	s.route("POST "+territoryRebuildPath, func(w http.ResponseWriter, r *http.Request) error {
		var task struct{ Chunks []string }
		if decodeJSON(r, &task) != nil || len(task.Chunks) == 0 {
			w.WriteHeader(204)
			return nil
		}
		if err := s.deps.Territory.RebuildChunks(r.Context(), task.Chunks, s.now()); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	})
	s.route("POST "+territoryPushPath, func(w http.ResponseWriter, r *http.Request) error {
		var task struct{ UID, ActivityID string }
		if decodeJSON(r, &task) != nil || task.UID == "" || task.ActivityID == "" {
			w.WriteHeader(204)
			return nil
		}
		if err := s.deps.Territory.PushTaken(r.Context(), task.UID, task.ActivityID, s.now()); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	})
	s.route("POST "+territoryDailyPath, func(w http.ResponseWriter, r *http.Request) error {
		if err := s.deps.Territory.Daily(r.Context(), s.now()); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	})
}

// ownedTerritoryChunks là các chunk uid đang có ô, đọc từ territoryOwners.
func ownedTerritoryChunks(ctx context.Context, db *firestore.Client, uid string) ([]string, error) {
	data, err := getData(ctx, db.Collection("territoryOwners").Doc(uid))
	if err != nil {
		return nil, err
	}
	by, _ := data["byChunk"].(map[string]any)
	out := make([]string, 0, len(by))
	for c := range by {
		out = append(out, c)
	}
	sort.Strings(out)
	return out, nil
}

// SyncAllTerritory chạy Sync lần lượt cho mọi user, dùng cho backfill lúc ra
// mắt. Không hẹn push (không có queue). Chạy lại không đổi gì. Trả số user đã
// sync.
func SyncAllTerritory(ctx context.Context, db *firestore.Client, now time.Time) (int, error) {
	cfg, err := loadTerritoryConfig(ctx, db)
	if err != nil {
		return 0, err
	}
	// Backfill ghi thẳng, song song với queue: chỉ an toàn trước khi bật, lúc
	// mọi kết quả còn rỗng và không có push.
	if cfg.Enabled || !cfg.EnabledAt.IsZero() {
		return 0, errors.New("config/territory đã bật: backfill chỉ chạy trước khi bật")
	}
	svc := NewTerritoryService(db, nil, nil)
	users, err := db.Collection("users").DocumentRefs(ctx).GetAll()
	if err != nil {
		return 0, err
	}
	for i, u := range users {
		if err := svc.Sync(ctx, u.ID, now); err != nil {
			return i, err
		}
	}
	return len(users), nil
}
