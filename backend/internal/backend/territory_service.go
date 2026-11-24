package backend

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"maps"
	"slices"
	"strconv"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// Lãnh địa: backend tính ô của từng buổi và chủ của từng ô; app chỉ đọc
// territoryChunks, territoryOwners và territory.result trên buổi. Mọi task chạy
// trên queue territory một luồng, nên hai lần sync không ghi đè nhau. Thiết kế:
// docs/territory_design.md.
const (
	territorySyncPath    = "/tasks/territory-sync"
	territoryRebuildPath = "/tasks/territory-rebuild"
	territoryPushPath    = "/tasks/territory-push"
	territoryDailyPath   = "/tasks/territory-daily"
	territoryPushKind    = "territory_taken"
)

// territoryTasks là phần TaskPublisher lãnh địa dùng; test thay bằng bản ghi.
type territoryTasks interface {
	Publish(ctx context.Context, input PublishTask) (string, error)
}

// territoryConfig đọc từ config/territory. Thiếu doc hay thiếu field thì dùng
// mặc định, và enabled = false: backend tính ô âm thầm, không ghi kết quả,
// không push, tới khi bật cùng lúc ra bản app có màn Lãnh địa.
type territoryConfig struct {
	Enabled    bool
	EnabledAt  time.Time
	Version    int
	DecayDays  int
	QuietCoRun time.Duration
	PushDelay  time.Duration
	Rules      territoryRules
}

func (c territoryConfig) window() time.Duration { return time.Duration(c.DecayDays) * 24 * time.Hour }

// resultsOn: buổi kết thúc từ mốc bật thì có kết quả "+N ô". Tắt enabled chỉ
// dừng push; kết quả vẫn tính, để bật lại không còn buổi "+0 ô".
func (c territoryConfig) resultsOn(endedAt time.Time) bool {
	return !c.EnabledAt.IsZero() && !endedAt.Before(c.EnabledAt)
}

func loadTerritoryConfig(ctx context.Context, db *firestore.Client) (territoryConfig, error) {
	c := territoryConfig{Version: 1, DecayDays: 30, QuietCoRun: 3 * time.Hour, PushDelay: time.Hour, Rules: defaultTerritoryRules()}
	data, err := getData(ctx, db.Collection("config").Doc("territory"))
	if err != nil {
		return c, err
	}
	if data == nil {
		return c, nil
	}
	c.Enabled = data["enabled"] == true
	if at := timePtr(data["enabledAt"]); at != nil {
		c.EnabledAt = *at
	}
	pos := func(key string, set func(float64)) {
		if v := number(data[key]); v > 0 {
			set(v)
		}
	}
	pos("version", func(v float64) { c.Version = int(v) })
	pos("decayDays", func(v float64) { c.DecayDays = int(v) })
	pos("quietCoRunHours", func(v float64) { c.QuietCoRun = time.Duration(v * float64(time.Hour)) })
	pos("pushDelayMinutes", func(v float64) { c.PushDelay = time.Duration(v * float64(time.Minute)) })
	pos("trimMeters", func(v float64) { c.Rules.TrimMeters = v })
	pos("fastestPaceSecPerKm", func(v float64) { c.Rules.FastestPaceSecPerKm = v })
	pos("slowestPaceSecPerKm", func(v float64) { c.Rules.SlowestPaceSecPerKm = v })
	pos("maxAccuracyMeters", func(v float64) { c.Rules.MaxAccuracyMeters = v })
	return c, nil
}

type TerritoryService struct {
	db    *firestore.Client
	tasks territoryTasks
	push  *PushService
}

func NewTerritoryService(db *firestore.Client, tasks territoryTasks, push *PushService) *TerritoryService {
	return &TerritoryService{db: db, tasks: tasks, push: push}
}

// enqueueTerritorySync xếp một lần sync cho uid. Không đặt TaskID: sync chạy
// lại bao nhiêu lần cũng ra cùng trạng thái, còn TaskID cố định thì Cloud
// Tasks gộp mất lần đổi thứ hai trong cùng giờ. publish nil (test không gài
// task) thì bỏ qua.
func enqueueTerritorySync(ctx context.Context, publish taskPublishFunc, uid, cause string) error {
	if publish == nil {
		return nil
	}
	_, err := publish(ctx, PublishTask{Queue: QueueTerritory, HandlerPath: territorySyncPath, Payload: map[string]any{"uid": uid, "cause": cause}})
	return err
}

// territoryMaxCells và territoryMaxMeterRatio chặn tuyến hỏng hay giả: tuyến
// thật không có hàng nghìn ô, và tổng mét trong ô không thể vượt xa quãng
// đường của buổi. Vượt thì coi buổi không có tuyến.
const (
	territoryMaxCells      = 3000
	territoryMaxMeterRatio = 1.3
)

// territoryActivityFields là mọi field sync cần, để không đọc routePoints
// (doc buổi tới 800 KB) khi chỉ xét buổi nào được tính.
var territoryActivityFields = []string{
	"source", "sportType", "startedAt", "distanceMeters", "elevationGainMeters",
	"movingTimeSeconds", "elapsedTimeSeconds", "manual", "duplicateOfActivityId",
	"routeSketch", "routeSavedAt", "trackingSavedAt", "territory",
}

type territoryDoc struct {
	ref  *firestore.DocumentRef
	data map[string]any
	fact ActivityFact
}

func (d territoryDoc) endedAt() time.Time {
	el := d.fact.ElapsedTimeSeconds
	if el <= 0 {
		el = d.fact.MovingTimeSeconds
	}
	return d.fact.StartedAt.Add(time.Duration(el) * time.Second)
}

func (d territoryDoc) territory() map[string]any {
	t, _ := d.data["territory"].(map[string]any)
	return t
}

// Sync đối chiếu buổi trong cửa sổ của uid: tính ô cho buổi mới hay đổi đầu
// vào, ghi counted, tính lại mọi chunk người đó có ô hay có buổi chạm tới, ghi
// kết quả cho buổi chưa có, và hẹn push. Không dựa vào dấu nào của lần chạy
// trước, nên chạy lại từ đầu luôn đúng.
func (s *TerritoryService) Sync(ctx context.Context, uid string, now time.Time) error {
	started := time.Now()
	cfg, err := loadTerritoryConfig(ctx, s.db)
	if err != nil {
		return err
	}
	public, err := profileIsPublic(ctx, s.db, uid)
	if err != nil {
		return err
	}
	ownerChunks, err := s.ownerChunks(ctx, uid)
	if err != nil {
		return err
	}
	docs, err := s.windowDocs(ctx, uid, now, cfg)
	if err != nil {
		return err
	}
	facts := make([]ActivityFact, len(docs))
	for i, d := range docs {
		facts[i] = d.fact
	}
	official := map[string]bool{}
	for _, f := range SelectOfficialActivities(facts) {
		official[f.ID] = true
	}
	byID := map[string]territoryDoc{}
	for _, d := range docs {
		byID[d.ref.ID] = d
	}

	rebuild := map[string]bool{}
	for c := range ownerChunks {
		rebuild[c] = true
	}
	for _, d := range docs {
		changed, err := s.syncActivity(ctx, d, byID, official[d.ref.ID] && public, cfg)
		if err != nil {
			return err
		}
		for _, c := range changed {
			rebuild[c] = true
		}
	}
	// Đọc lại sau khi ghi để bước sau thấy chunks và counted mới.
	docs, err = s.windowDocs(ctx, uid, now, cfg)
	if err != nil {
		return err
	}
	for _, d := range docs {
		t := d.territory()
		if t["counted"] == true {
			for _, c := range stringList(t["chunks"]) {
				rebuild[c] = true
			}
		}
	}
	chunks := slices.Sorted(maps.Keys(rebuild))
	for _, c := range chunks {
		if err := s.RebuildChunk(ctx, c, now, cfg); err != nil {
			return err
		}
	}
	for _, d := range docs {
		if err := s.writeResult(ctx, uid, d, cfg); err != nil {
			return err
		}
	}
	slog.InfoContext(ctx, "territory.synced", "uid", uid, "activities", len(docs), "chunks", len(chunks), "ms", time.Since(started).Milliseconds())
	return s.schedulePushes(ctx, uid, now, cfg)
}

// windowDocs đọc buổi có startedAt trong cửa sổ cộng hai ngày (buổi dài), rồi
// lọc theo endedAt. Buổi dài hơn hai ngày bị bỏ.
func (s *TerritoryService) windowDocs(ctx context.Context, uid string, now time.Time, cfg territoryConfig) ([]territoryDoc, error) {
	from := now.Add(-cfg.window() - 48*time.Hour)
	iter := s.db.Collection("users").Doc(uid).Collection("activities").
		Where("startedAt", ">=", from.UTC().Format(time.RFC3339Nano)).
		Select(territoryActivityFields...).Documents(ctx)
	defer iter.Stop()
	var out []territoryDoc
	cut := now.Add(-cfg.window())
	for {
		snap, err := iter.Next()
		if errors.Is(err, iterator.Done) {
			break
		}
		if err != nil {
			return nil, err
		}
		d := territoryDoc{ref: snap.Ref, data: snap.Data(), fact: activityFact(snap.Ref.ID, snap.Data())}
		if d.endedAt().After(cut) {
			out = append(out, d)
		}
	}
	return out, nil
}

func (s *TerritoryService) ownerChunks(ctx context.Context, uid string) (map[string]bool, error) {
	data, err := getData(ctx, s.db.Collection("territoryOwners").Doc(uid))
	if err != nil {
		return nil, err
	}
	out := map[string]bool{}
	if by, ok := data["byChunk"].(map[string]any); ok {
		for c := range by {
			out[c] = true
		}
	}
	return out, nil
}

func profileIsPublic(ctx context.Context, db *firestore.Client, uid string) (bool, error) {
	data, err := getData(ctx, db.Collection("publicProfiles").Doc(uid))
	if err != nil {
		return false, err
	}
	return stringValue(data["profileVisibility"]) == "public", nil
}

// routeSource chọn doc cho tuyến: routePoints của chính buổi, rồi của bản trùng
// (doc có duplicateOfActivityId trỏ về buổi này), rồi polyline của chính buổi.
// Biết doc nào có tuyến qua routeSketch, để không phải đọc routePoints.
func routeSource(d territoryDoc, byID map[string]territoryDoc) territoryDoc {
	if d.fact.Source != "strava" || d.data["routeSavedAt"] != nil {
		return d
	}
	ids := slices.Sorted(maps.Keys(byID))
	for _, id := range ids {
		o := byID[id]
		if stringValue(o.data["duplicateOfActivityId"]) == d.ref.ID && o.data["routeSketch"] != nil {
			return o
		}
	}
	return d
}

func routeSavedKey(d territoryDoc) string {
	for _, k := range []string{"routeSavedAt", "trackingSavedAt"} {
		if at := timePtr(d.data[k]); at != nil {
			return at.UTC().Format(time.RFC3339Nano)
		}
	}
	return ""
}

func territoryInputHash(d, src territoryDoc, cfg territoryConfig) string {
	return strings.Join([]string{
		strconv.Itoa(cfg.Version), d.fact.StartedAt.UTC().Format(time.RFC3339),
		strconv.FormatInt(d.fact.ElapsedTimeSeconds, 10), src.ref.ID, routeSavedKey(src),
	}, "|")
}

// syncActivity ghi ô và counted của một buổi, trả các chunk cần tính lại do
// buổi này đổi (chunk cũ và chunk mới). Buổi không được tính thì không tính ô.
func (s *TerritoryService) syncActivity(ctx context.Context, d territoryDoc, byID map[string]territoryDoc, counted bool, cfg territoryConfig) ([]string, error) {
	t := d.territory()
	wasCounted := t["counted"] == true
	oldChunks := stringList(t["chunks"])
	updates := []firestore.Update{}
	var changed []string
	if counted {
		src := routeSource(d, byID)
		hash := territoryInputHash(d, src, cfg)
		if stringValue(t["inputHash"]) != hash {
			cells, err := s.cellsOf(ctx, src, cfg)
			if err != nil {
				return nil, err
			}
			chunks := chunksOf(cells)
			updates = append(updates,
				firestore.Update{Path: "territory.cells", Value: cells},
				firestore.Update{Path: "territory.chunks", Value: chunks},
				firestore.Update{Path: "territory.routeFrom", Value: src.ref.ID},
				firestore.Update{Path: "territory.inputHash", Value: hash},
			)
			changed = append(changed, oldChunks...)
			changed = append(changed, chunks...)
		}
		ended := d.endedAt()
		if at := timePtr(t["endedAt"]); at == nil || !at.Equal(ended) {
			updates = append(updates, firestore.Update{Path: "territory.endedAt", Value: ended})
			changed = append(changed, oldChunks...)
		}
	}
	if counted != wasCounted {
		updates = append(updates, firestore.Update{Path: "territory.counted", Value: counted})
		changed = append(changed, oldChunks...)
		if counted {
			// Kết quả ghi lúc buổi chưa được tính là rỗng; tính lại.
			updates = append(updates, firestore.Update{Path: "territory.result", Value: firestore.Delete})
		}
	}
	if len(updates) == 0 {
		return nil, nil
	}
	if _, err := d.ref.Update(ctx, updates); err != nil {
		if status.Code(err) == codes.NotFound {
			return nil, nil // buổi vừa bị xoá: lần tính lại chunk tự bỏ nó
		}
		return nil, err
	}
	return changed, nil
}

func (s *TerritoryService) cellsOf(ctx context.Context, src territoryDoc, cfg territoryConfig) (map[string]int, error) {
	snap, err := src.ref.Get(ctx)
	if err != nil {
		if status.Code(err) == codes.NotFound {
			return map[string]int{}, nil
		}
		return nil, err
	}
	if snap.Data()["manual"] == true {
		return map[string]int{}, nil
	}
	cells := territoryCells(routeSamplesFromDoc(snap.Data()), cfg.Rules)
	total := 0
	for _, m := range cells {
		total += m
	}
	limit := number(snap.Data()["distanceMeters"])*territoryMaxMeterRatio + cfg.Rules.TrimMeters
	if len(cells) > territoryMaxCells || float64(total) > limit {
		slog.WarnContext(ctx, "territory.route_rejected", "activityId", src.ref.ID, "cells", len(cells), "meters", total, "distanceMeters", number(snap.Data()["distanceMeters"]))
		return map[string]int{}, nil
	}
	return cells, nil
}

func chunksOf(cells map[string]int) []string {
	set := map[string]bool{}
	for id := range cells {
		if cell, err := parseTileID(id); err == nil {
			set[chunkOf(cell).id()] = true
		}
	}
	return slices.Sorted(maps.Keys(set))
}

// passesQuery là các buổi được tính chạm chunk, endedAt trong (from, to].
func (s *TerritoryService) passesQuery(chunk string, from, to time.Time) firestore.Query {
	return s.db.CollectionGroup("activities").
		Where("territory.counted", "==", true).
		Where("territory.chunks", "array-contains", chunk).
		Where("territory.endedAt", ">", from).
		Where("territory.endedAt", "<=", to).
		Select("territory.cells", "territory.endedAt")
}

// passesFrom gom lượt qua theo ô, chỉ ô thuộc chunk.
func passesFrom(snaps []*firestore.DocumentSnapshot, chunk string) map[string][]territoryPass {
	out := map[string][]territoryPass{}
	for _, snap := range snaps {
		t, _ := snap.Data()["territory"].(map[string]any)
		ended := timePtr(t["endedAt"])
		cells, _ := t["cells"].(map[string]any)
		user := snap.Ref.Parent.Parent
		if ended == nil || user == nil {
			continue
		}
		for id, m := range cells {
			cell, err := parseTileID(id)
			if err != nil || chunkOf(cell).id() != chunk {
				continue
			}
			out[id] = append(out[id], territoryPass{UID: user.ID, ActivityID: snap.Ref.ID, EndedAt: *ended, Meters: int(number(m))})
		}
	}
	return out
}

// RebuildChunk tính lại cả chunk bằng ownerOf ở mốc now, trong một transaction:
// đọc chunk, query lượt qua, rồi ghi đè chunk và byChunk của từng người liên
// quan. Ghi byChunk bằng merge, không đọc doc owners.
func (s *TerritoryService) RebuildChunk(ctx context.Context, chunk string, now time.Time, cfg territoryConfig) error {
	chunkRef := s.db.Collection("territoryChunks").Doc(chunk)
	err := s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		oldCounts := map[string]int{}
		snap, err := tx.Get(chunkRef)
		if err != nil && status.Code(err) != codes.NotFound {
			return err
		}
		if err == nil {
			if cells, ok := snap.Data()["cells"].(map[string]any); ok {
				for _, v := range cells {
					if m, ok := v.(map[string]any); ok {
						oldCounts[stringValue(m["u"])]++
					}
				}
			}
		}
		snaps, err := tx.Documents(s.passesQuery(chunk, now.Add(-cfg.window()), now)).GetAll()
		if err != nil {
			return err
		}
		cells := map[string]any{}
		newCounts := map[string]int{}
		for id, passes := range passesFrom(snaps, chunk) {
			o, ok := ownerOf(passes, now, cfg.window())
			if !ok {
				continue
			}
			cells[id] = map[string]any{"u": o.UID, "m": o.Meters, "m2": o.Second}
			newCounts[o.UID]++
		}
		if len(cells) == 0 {
			if err := tx.Delete(chunkRef); err != nil {
				return err
			}
		} else if err := tx.Set(chunkRef, map[string]any{"cells": cells, "updatedAt": firestore.ServerTimestamp}); err != nil {
			return err
		}
		for uid := range mergeKeys(oldCounts, newCounts) {
			var v any = firestore.Delete
			if n := newCounts[uid]; n > 0 {
				v = n
			}
			ref := s.db.Collection("territoryOwners").Doc(uid)
			if err := tx.Set(ref, map[string]any{"byChunk": map[string]any{chunk: v}, "updatedAt": firestore.ServerTimestamp}, firestore.MergeAll); err != nil {
				return err
			}
		}
		return nil
	})
	if err != nil {
		return fmt.Errorf("territory rebuild %s: %w", chunk, err)
	}
	return nil
}

func mergeKeys(a, b map[string]int) map[string]bool {
	out := map[string]bool{}
	for k := range a {
		out[k] = true
	}
	for k := range b {
		out[k] = true
	}
	delete(out, "")
	return out
}

// outcome tính kết quả của buổi d trên các buổi đã về lúc này (mục "Kết quả
// của một buổi" trong thiết kế). Trả cả lượt qua đọc được để push lọc người
// chạy cùng.
func (s *TerritoryService) outcome(ctx context.Context, uid string, d territoryDoc, cfg territoryConfig) (territoryResult, map[string][]territoryPass, error) {
	t := d.territory()
	ended := timePtr(t["endedAt"])
	cellsAny, _ := t["cells"].(map[string]any)
	if ended == nil || len(cellsAny) == 0 {
		return territoryResult{Taken: map[string]int{}, TakenCells: map[string]string{}}, nil, nil
	}
	cells := map[string]int{}
	for id, m := range cellsAny {
		cells[id] = int(number(m))
	}
	others := map[string][]territoryPass{}
	for _, chunk := range stringList(t["chunks"]) {
		// Lấy cả lượt sau buổi tới quietCoRun: push cần biết người chạy cùng
		// lưu buổi sau; resultFor tự bỏ lượt không nhỏ hơn buổi.
		snaps, err := s.passesQuery(chunk, ended.Add(-cfg.window()), ended.Add(cfg.QuietCoRun)).Documents(ctx).GetAll()
		if err != nil {
			return territoryResult{}, nil, err
		}
		for id, ps := range passesFrom(snaps, chunk) {
			others[id] = append(others[id], ps...)
		}
	}
	x := territoryPass{UID: uid, ActivityID: d.ref.ID, EndedAt: *ended}
	return resultFor(x, cells, others, cfg.window()), others, nil
}

// writeResult ghi territory.result một lần cho buổi chưa có. Buổi không được
// tính, hay kết thúc trước mốc bật, có kết quả rỗng.
func (s *TerritoryService) writeResult(ctx context.Context, uid string, d territoryDoc, cfg territoryConfig) error {
	t := d.territory()
	if t != nil && t["result"] != nil {
		return nil
	}
	result := map[string]any{"gained": 0, "taken": map[string]any{}}
	if t["counted"] == true && cfg.resultsOn(d.endedAt()) {
		r, _, err := s.outcome(ctx, uid, d, cfg)
		if err != nil {
			return err
		}
		taken := map[string]any{}
		for u, n := range r.Taken {
			taken[u] = n
		}
		result = map[string]any{"gained": r.Gained, "taken": taken}
	}
	// Bản sao nhỏ cho app: doc buổi tới 800 KB vì routePoints, app nghe doc này
	// thay vì nghe cả buổi chỉ để lấy "+N ô". Ghi trước dấu territory.result,
	// để chạy lại sau lỗi ghi lại cả hai.
	small := map[string]any{"uid": uid, "activityId": d.ref.ID, "gained": result["gained"], "taken": result["taken"], "updatedAt": firestore.ServerTimestamp}
	if chunks := stringList(t["chunks"]); len(chunks) > 0 {
		small["chunk"] = chunks[0]
	}
	if _, err := s.db.Collection("territoryResults").Doc(uid+"_"+d.ref.ID).Set(ctx, small); err != nil {
		return err
	}
	if _, err := d.ref.Update(ctx, []firestore.Update{{Path: "territory.result", Value: result}}); err != nil && status.Code(err) != codes.NotFound {
		return err
	}
	return nil
}

func (s *TerritoryService) schedulePushes(ctx context.Context, uid string, now time.Time, cfg territoryConfig) error {
	if !cfg.Enabled || s.tasks == nil {
		return nil
	}
	docs, err := s.windowDocs(ctx, uid, now, cfg)
	if err != nil {
		return err
	}
	for _, d := range docs {
		t := d.territory()
		ended := d.endedAt()
		res, _ := t["result"].(map[string]any)
		if t["counted"] != true || !cfg.resultsOn(ended) || now.Sub(ended) > 24*time.Hour || res == nil {
			continue
		}
		taken, _ := res["taken"].(map[string]any)
		if number(res["gained"]) == 0 && len(taken) == 0 {
			continue
		}
		at := ended.Add(cfg.PushDelay)
		if at.Before(now) {
			at = now
		}
		if _, err := s.tasks.Publish(ctx, PublishTask{
			Queue: QueueTerritory, HandlerPath: territoryPushPath,
			Payload:      map[string]any{"uid": uid, "activityId": d.ref.ID},
			TaskID:       "territory-push-" + uid + "-" + d.ref.ID,
			ScheduleTime: &at,
		}); err != nil {
			return err
		}
	}
	return nil
}
