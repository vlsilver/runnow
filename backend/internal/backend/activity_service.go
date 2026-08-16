package backend

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"math"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

type TrackedActivityResult struct {
	Status           string `json:"status"`
	StravaActivityID string `json:"stravaActivityId,omitempty"`
}

// stravaDuplicateSearchWindow bounds how far from the anchor activity's start
// time we look for a Strava/3i duplicate pair, in either direction.
const stravaDuplicateSearchWindow = 4 * time.Hour

// telegramActivityNotifyWindow keeps initial/recovery backfills from spamming
// old runs while still allowing a just-finished activity to notify even if it
// was written by backfill before the webhook update is processed.
const telegramActivityNotifyWindow = 36 * time.Hour

type ActivityService struct {
	db            *firestore.Client
	gateway       *StravaGateway
	tokens        *TokenStore
	tasks         *TaskPublisher
	telegram      *TelegramService
	broadcast     broadcastRecorder
	publicBaseURL string
	webBaseURL    string
}

// broadcastRecorder ghi lại một tin do chính bot phát ra group (như thông báo
// buổi chạy) vào trí nhớ. Tuỳ chọn — nil khi bot chưa bật; NotifyTelegram vẫn
// gửi thông báo bình thường, chỉ không lưu vào trí nhớ.
type broadcastRecorder interface {
	RecordBroadcast(ctx context.Context, chatID, text string) error
	ActivityAnnouncement(ctx context.Context, displayName, activityName string, fact ActivityFact) string
	LiveAnnouncement(ctx context.Context, displayName, event string, distanceMeters, movingTimeSeconds float64, milestoneKm int) string
	LivePhotoAnnouncement(ctx context.Context, displayName, photoPath string, distanceMeters float64) error
	ContractRoast(ctx context.Context, title, targetLabel string, failers []roastFailer) string
	Enabled() bool
}

func NewActivityService(db *firestore.Client, g *StravaGateway, tokens *TokenStore, tasks *TaskPublisher, telegram *TelegramService, publicBaseURL, webBaseURL string) *ActivityService {
	return &ActivityService{db: db, gateway: g, tokens: tokens, tasks: tasks, telegram: telegram, publicBaseURL: publicBaseURL, webBaseURL: webBaseURL}
}

// SetBroadcastRecorder nối recorder sau khi bot được khởi tạo. Tách khỏi
// constructor vì BotService dựng SAU ActivityService trong dependencies.
func (s *ActivityService) SetBroadcastRecorder(r broadcastRecorder) { s.broadcast = r }

func (s *ActivityService) SaveTracked(ctx context.Context, uid string, raw map[string]any) (TrackedActivityResult, error) {
	next, err := normalizeTrackedActivity(raw)
	if err != nil {
		return TrackedActivityResult{}, err
	}
	// Buổi chạy DÀI có thể nhồi route+streams tới mức doc vượt trần 1MB của
	// Firestore → ghi hỏng, mất cả buổi. Giảm mật độ route/streams cho vừa
	// TRƯỚC khi ghi (bản đồ/biểu đồ vẫn đủ mượt). Không đụng client.
	shrinkTrackedActivity(ctx, uid, next)
	activityID := stringValue(next["id"])
	distance := number(next["distanceMeters"])
	duplicateID := ""
	if distance >= 500 {
		duplicateID, err = s.preferredStravaDuplicate(ctx, uid, next)
		if err != nil {
			return TrackedActivityResult{}, err
		}
	}
	// Ghi thẳng ID của activity Strava trùng (nếu có) lên chính doc này — kèo
	// chỉ cần đọc field này để biết activity nào trùng activity nào, không
	// phải tự tính lại overlap ratio mỗi lần kiểm tra xung đột claim.
	if duplicateID != "" {
		next["duplicateOfActivityId"] = duplicateID
	}
	ref := s.db.Collection("users").Doc(uid).Collection("activities").Doc(activityID)
	next["trackingSavedAt"] = firestore.ServerTimestamp
	next["updatedAt"] = firestore.ServerTimestamp
	if _, err = ref.Set(ctx, next, firestore.MergeAll); err != nil {
		return TrackedActivityResult{}, err
	}
	if err = s.enqueueDerived(ctx, uid, trackedDerivedCause(next)); err != nil {
		return TrackedActivityResult{}, err
	}
	if startedAt, parseErr := time.Parse(time.RFC3339, stringValue(next["startedAt"])); parseErr == nil {
		if err = s.enqueuePeriodStats(ctx, uid, startedAt); err != nil {
			return TrackedActivityResult{}, err
		}
	}
	if distance < 500 {
		return TrackedActivityResult{Status: "below_minimum_distance"}, nil
	}
	if duplicateID != "" {
		return TrackedActivityResult{Status: "duplicate_of_strava", StravaActivityID: duplicateID}, nil
	}
	return TrackedActivityResult{Status: "counted"}, nil
}

// healthWorkout là 1 buổi chạy nhập từ Apple Health (client đọc HealthKit).
type healthWorkout struct {
	SourceID          string  `json:"sourceId"`
	StartedAt         string  `json:"startedAt"`
	DistanceMeters    float64 `json:"distanceMeters"`
	MovingTimeSeconds int64   `json:"movingTimeSeconds"`
}

// ImportHealthWorkouts upsert các buổi chạy từ Apple Health thành activity
// source=apple_health (id = "health-<uuid>" nên nhập lại chỉ ghi đè, không nhân
// bản), rồi dedup với Strava (đồng hồ thường vừa lên Strava vừa vào Health) để
// KHÔNG đếm đôi km. Trả về số buổi đã ghi.
func (s *ActivityService) ImportHealthWorkouts(ctx context.Context, uid string, workouts []healthWorkout) (int, error) {
	imported := 0
	now := time.Now()
	months := map[string]time.Time{} // tháng khác nhau bị đụng → rebuild period 1 lần/tháng
	for _, w := range workouts {
		if w.SourceID == "" || len(w.SourceID) > 100 || strings.ContainsAny(w.SourceID, "/ ") {
			continue
		}
		if w.DistanceMeters <= 0 || w.DistanceMeters > 1e7 || w.MovingTimeSeconds <= 0 || w.MovingTimeSeconds > 7*24*60*60 {
			continue
		}
		started, err := time.Parse(time.RFC3339, w.StartedAt)
		if err != nil || started.After(now.Add(10*time.Minute)) {
			continue
		}
		activityID := "health-" + w.SourceID
		next := map[string]any{
			"id":                 activityID,
			"source":             "apple_health",
			"sourceActivityId":   w.SourceID,
			"sportType":          "Run",
			"name":               "Chạy (Apple Health)",
			"manual":             false,
			"recordingDevice":    "apple_health",
			"startedAt":          started.UTC().Format(time.RFC3339Nano),
			"distanceMeters":     w.DistanceMeters,
			"movingTimeSeconds":  w.MovingTimeSeconds,
			"elapsedTimeSeconds": w.MovingTimeSeconds,
			"updatedAt":          firestore.ServerTimestamp,
		}
		// Trùng với 1 buổi Strava đang có → đánh dấu để leaderboard không đếm đôi.
		if w.DistanceMeters >= 500 {
			if dupID, derr := s.preferredStravaDuplicate(ctx, uid, next); derr == nil && dupID != "" {
				next["duplicateOfActivityId"] = dupID
			}
		}
		ref := s.db.Collection("users").Doc(uid).Collection("activities").Doc(activityID)
		if _, err := ref.Set(ctx, next, firestore.MergeAll); err != nil {
			return imported, err
		}
		months[started.Format("2006-01")] = started
		imported++
	}
	if imported == 0 {
		return 0, nil
	}
	// Gom việc rebuild: leaderboard hiện tại rebuild MỘT lần cho cả batch; stats
	// theo tháng rebuild một lần cho MỖI tháng khác nhau bị đụng — thay vì bắn
	// một task cho từng buổi (sync 90 ngày = ~90 task trùng).
	if err := s.enqueueDerived(ctx, uid, "health-import"); err != nil {
		return imported, err
	}
	for _, m := range months {
		if err := s.enqueuePeriodStats(ctx, uid, m); err != nil {
			return imported, err
		}
	}
	return imported, nil
}

func trackedDerivedCause(activity map[string]any) string {
	identity := map[string]any{}
	for _, key := range []string{
		"id", "sportType", "startedAt", "distanceMeters",
		"movingTimeSeconds", "elapsedTimeSeconds", "officialState",
	} {
		identity[key] = activity[key]
	}
	return StableTaskID("tracked", identity)
}

// trackedActivityMaxJSONBytes là ngưỡng an toàn (dưới trần 1,048,576 của
// Firestore, chừa margin cho tên field + overhead), đo bằng độ dài JSON như một
// xấp xỉ kích thước document.
const trackedActivityMaxJSONBytes = 800_000

// shrinkTrackedActivity giảm mật độ routePoints + streams (+ laps nếu cần) tới
// khi doc ước lượng nằm dưới ngưỡng, để buổi chạy dài không vượt trần 1MB của
// Firestore. Không đụng client — sửa ngay tại backend, hiệu lực cho mọi app.
func shrinkTrackedActivity(ctx context.Context, uid string, next map[string]any) {
	before := estimateDocJSONSize(next)
	if before <= trackedActivityMaxJSONBytes {
		return
	}
	for maxLen := 4000; maxLen >= 200; maxLen /= 2 {
		if rp, ok := next["routePoints"].([]any); ok {
			next["routePoints"] = downsampleList(rp, maxLen)
		}
		if st, ok := next["streams"].(map[string]any); ok {
			for k, v := range st {
				if arr, ok := v.([]any); ok {
					st[k] = downsampleList(arr, maxLen)
				}
			}
		}
		if lp, ok := next["laps"].([]any); ok && maxLen < 1000 {
			next["laps"] = downsampleList(lp, maxLen)
		}
		if after := estimateDocJSONSize(next); after <= trackedActivityMaxJSONBytes {
			slog.InfoContext(ctx, "activity.tracked_downsampled", "uid", uid,
				"id", stringValue(next["id"]), "beforeBytes", before, "afterBytes", after, "maxLen", maxLen)
			return
		}
	}
	// Cực hiếm: vẫn to sau khi giảm mạnh → bỏ streams thô (giữ route đã thưa +
	// splits + số liệu tổng) để CHẮC CHẮN ghi được — thà thiếu biểu đồ còn hơn
	// mất cả buổi chạy.
	delete(next, "streams")
	next["streamsHydrated"] = false
	slog.WarnContext(ctx, "activity.tracked_streams_dropped", "uid", uid,
		"id", stringValue(next["id"]), "beforeBytes", before, "afterBytes", estimateDocJSONSize(next))
}

// downsampleList giữ tối đa maxLen phần tử phân bố đều, LUÔN gồm phần tử đầu và
// cuối để bản đồ/biểu đồ không bị cụt hai đầu.
func downsampleList(list []any, maxLen int) []any {
	n := len(list)
	if n <= maxLen || maxLen < 2 {
		return list
	}
	out := make([]any, 0, maxLen)
	step := float64(n-1) / float64(maxLen-1)
	last := -1
	for i := 0; i < maxLen; i++ {
		idx := int(math.Round(float64(i) * step))
		if idx >= n {
			idx = n - 1
		}
		if idx != last {
			out = append(out, list[idx])
			last = idx
		}
	}
	return out
}

func estimateDocJSONSize(m map[string]any) int {
	b, err := json.Marshal(m)
	if err != nil {
		return 1 << 30 // không marshal được → coi như rất to để buộc giảm/bỏ streams
	}
	return len(b)
}

func normalizeTrackedActivity(raw map[string]any) (map[string]any, error) {
	id := strings.TrimSpace(stringValue(raw["id"]))
	name := strings.TrimSpace(stringValue(raw["name"]))
	startedAt := stringValue(raw["startedAt"])
	started, parseErr := time.Parse(time.RFC3339, startedAt)
	distance := number(raw["distanceMeters"])
	moving := int64(number(raw["movingTimeSeconds"]))
	elapsed := int64(number(raw["elapsedTimeSeconds"]))
	if id == "" || len(id) > 128 || !strings.HasPrefix(id, "runnow-") ||
		name == "" || len([]rune(name)) > 80 || raw["source"] != "runnow" ||
		raw["sportType"] != "Run" || parseErr != nil ||
		started.After(time.Now().Add(10*time.Minute)) ||
		math.IsNaN(distance) || math.IsInf(distance, 0) || distance < 0 || distance > 1e7 ||
		moving < 0 || elapsed < 0 || elapsed > 7*24*60*60 || moving > elapsed+60 {
		return nil, invalidRequest()
	}
	allowed := map[string]bool{
		"schemaVersion": true, "id": true, "name": true, "source": true,
		"sourceActivityId": true, "manual": true, "recordingDevice": true,
		"sportType": true, "startedAt": true, "distanceMeters": true,
		"movingTimeSeconds": true, "elapsedTimeSeconds": true,
		"averageHeartRate": true, "averageCadence": true,
		"elevationGainMeters": true, "polyline": true, "routePoints": true,
		"hydrated": true, "calories": true, "gearName": true, "splits": true,
		"laps": true, "streams": true, "photos": true, "streamsHydrated": true,
		"streamsVersion": true,
		// trackingDebug CỐ Ý bị loại: nó là log debug chiếm tới ~70% doc (695KB
		// cho buổi 6km) và không ai đọc — bỏ khỏi bản lưu để doc gọn, tránh vượt
		// trần 1MB. App vẫn gửi cũng không sao, ở đây không lưu nữa.
	}
	next := make(map[string]any, len(raw)+4)
	for key, value := range raw {
		if allowed[key] {
			next[key] = value
		}
	}
	next["id"] = id
	next["name"] = name
	next["source"] = "runnow"
	next["sourceActivityId"] = id
	next["sportType"] = "Run"
	next["startedAt"] = started.UTC().Format(time.RFC3339Nano)
	next["distanceMeters"] = distance
	next["movingTimeSeconds"] = moving
	next["elapsedTimeSeconds"] = elapsed
	next["hydrated"] = true
	next["streamsHydrated"] = true
	next["streamsVersion"] = 4
	next["officialState"] = "candidate"
	next["updatedBy"] = "backend"
	return next, nil
}

func (s *ActivityService) preferredStravaDuplicate(ctx context.Context, uid string, tracked map[string]any) (string, error) {
	started, _ := time.Parse(time.RFC3339, stringValue(tracked["startedAt"]))
	end := started.Add(time.Duration(max64(int64(number(tracked["elapsedTimeSeconds"])), 1)) * time.Second)
	iter := s.db.Collection("users").Doc(uid).Collection("activities").
		Where("startedAt", ">=", started.Add(-stravaDuplicateSearchWindow).UTC().Format(time.RFC3339Nano)).
		Where("startedAt", "<", end.UTC().Format(time.RFC3339Nano)).Documents(ctx)
	defer iter.Stop()
	candidate := activityFact(stringValue(tracked["id"]), tracked)
	for {
		doc, nextErr := iter.Next()
		if nextErr != nil {
			if nextErr == iterator.Done {
				return "", nil
			}
			return "", nextErr
		}
		fact := activityFact(doc.Ref.ID, doc.Data())
		if fact.Source == "strava" && (fact.SportType == "Run" || fact.SportType == "TrailRun" || fact.SportType == "VirtualRun") && overlapRatio(candidate, fact) > 0.3 {
			return fact.ID, nil
		}
	}
}

// markRunNowDuplicates handles the reverse of preferredStravaDuplicate: a 3i
// tracked activity may already exist (and be claimed by a kèo) by the time
// this Strava activity syncs in later. Stamps `duplicateOfActivityId` on any
// matching 3i doc so callers can check a plain field instead of recomputing
// overlap ratios against every claimed activity on every check.
func (s *ActivityService) markRunNowDuplicates(ctx context.Context, uid, stravaActivityID string, stravaData map[string]any) error {
	stravaFact := activityFact(stravaActivityID, stravaData)
	if stravaFact.SportType != "Run" && stravaFact.SportType != "TrailRun" && stravaFact.SportType != "VirtualRun" {
		return nil
	}
	iter := s.db.Collection("users").Doc(uid).Collection("activities").
		Where("source", "==", "runnow").
		Where("startedAt", ">=", stravaFact.StartedAt.Add(-stravaDuplicateSearchWindow).UTC().Format(time.RFC3339Nano)).
		Where("startedAt", "<", stravaFact.StartedAt.Add(stravaDuplicateSearchWindow).UTC().Format(time.RFC3339Nano)).
		Documents(ctx)
	defer iter.Stop()
	for {
		doc, err := iter.Next()
		if err == iterator.Done {
			return nil
		}
		if err != nil {
			return err
		}
		data := doc.Data()
		if stringValue(data["duplicateOfActivityId"]) == stravaActivityID {
			continue
		}
		fact := activityFact(doc.Ref.ID, data)
		if overlapRatio(fact, stravaFact) > 0.3 {
			if _, err := doc.Ref.Set(ctx, map[string]any{"duplicateOfActivityId": stravaActivityID, "updatedAt": firestore.ServerTimestamp}, firestore.MergeAll); err != nil {
				return err
			}
		}
	}
}

func (s *ActivityService) ProcessWebhook(ctx context.Context, eventKey string, event StravaWebhookEvent) error {
	ref := s.db.Collection("integrationEvents").Doc(eventKey)
	snap, err := ref.Get(ctx)
	if err != nil {
		return err
	}
	if snap.Data()["status"] == "processed" {
		return nil
	}
	_, err = ref.Set(ctx, map[string]any{"status": "processing", "attempts": firestore.Increment(1), "processingAt": firestore.ServerTimestamp, "updatedAt": firestore.ServerTimestamp}, firestore.MergeAll)
	if err != nil {
		return err
	}
	uid, err := s.uidForAthlete(ctx, itoa64(event.OwnerID))
	if err != nil {
		return s.failEvent(ctx, ref, err)
	}
	if uid == "" {
		_, err = ref.Set(ctx, map[string]any{"status": "ignored", "ignoreReason": "unknown_athlete", "updatedAt": firestore.ServerTimestamp}, firestore.MergeAll)
		return err
	}
	if event.ObjectType == "athlete" && falseLike(event.Updates["authorized"]) {
		err = s.tokens.markRevoked(ctx, uid, "deauthorized")
	} else if event.ObjectType == "activity" {
		if event.AspectType == "delete" {
			err = s.deleteActivity(ctx, uid, itoa64(event.ObjectID), event.EventTime)
		} else {
			err = s.fetchAndUpsert(ctx, uid, itoa64(event.ObjectID), event.EventTime, false)
		}
	}
	if err != nil {
		return s.failEvent(ctx, ref, err)
	}
	if event.ObjectType == "activity" {
		if _, err = s.db.Collection("users").Doc(uid).Set(ctx, map[string]any{
			"lastSyncedAt": firestore.ServerTimestamp,
			"updatedAt":    firestore.ServerTimestamp,
		}, firestore.MergeAll); err != nil {
			return s.failEvent(ctx, ref, err)
		}
	}
	_, err = ref.Set(ctx, map[string]any{"status": "processed", "processedAt": firestore.ServerTimestamp, "updatedAt": firestore.ServerTimestamp}, firestore.MergeAll)
	return err
}

func (s *ActivityService) BackfillPage(ctx context.Context, uid string, page int, runID string, after *int64) error {
	var activities []StravaActivity
	err := s.tokens.WithAccessToken(ctx, uid, func(token string) error {
		var fetchErr error
		activities, fetchErr = s.gateway.ListActivities(ctx, token, page, 100, after)
		return fetchErr
	})
	if err != nil {
		return err
	}
	supported := make([]StravaActivity, 0, len(activities))
	for _, a := range activities {
		if IsSupportedActivity(a) {
			supported = append(supported, a)
		}
	}
	refs := make([]*firestore.DocumentRef, 0, len(supported)*2)
	for _, a := range supported {
		refs = append(refs, s.db.Collection("users").Doc(uid).Collection("activities").Doc(itoa64(a.ID)))
	}
	for _, a := range supported {
		refs = append(refs, s.db.Collection("activityTombstones").Doc(uid+"_"+itoa64(a.ID)))
	}
	var snaps []*firestore.DocumentSnapshot
	if len(refs) > 0 {
		snaps, err = s.db.GetAll(ctx, refs)
		if err != nil {
			return err
		}
	}
	batch := s.db.Batch()
	changed := int64(0)
	notifyActivityIDs := make([]string, 0, len(supported))
	now := time.Now()
	for i, a := range supported {
		existing := map[string]any(nil)
		if snaps[i].Exists() {
			existing = snaps[i].Data()
		}
		if snaps[len(supported)+i].Exists() {
			continue
		}
		next := NormalizeActivity(a, false, nil)
		if !SummaryChanged(existing, next) {
			continue
		}
		if shouldEnqueueTelegramActivity(existing, next, now) {
			notifyActivityIDs = append(notifyActivityIDs, itoa64(a.ID))
		}
		next["importedAt"] = firestore.ServerTimestamp
		next["updatedAt"] = firestore.ServerTimestamp
		batch.Set(refs[i], next, firestore.MergeAll)
		changed++
	}
	if changed > 0 {
		if _, err = batch.Commit(ctx); err != nil {
			return err
		}
		for _, activityID := range notifyActivityIDs {
			if err = s.enqueueNotify(ctx, uid, activityID); err != nil {
				return err
			}
		}
	}
	statusValue := "backfilling"
	if len(activities) < 100 {
		statusValue = "active"
	}
	_, err = s.db.Collection("stravaConnections").Doc(uid).Set(ctx, map[string]any{"status": statusValue, "backfillPage": page, "backfillImportedCount": firestore.Increment(changed), "lastBackfillAt": firestore.ServerTimestamp, "updatedAt": firestore.ServerTimestamp}, firestore.MergeAll)
	if err != nil {
		return err
	}
	if len(activities) == 100 {
		payload := map[string]any{"uid": uid, "page": page + 1, "runId": runID}
		if after != nil {
			payload["after"] = *after
		}
		_, err = s.tasks.Publish(ctx, PublishTask{Queue: QueueBackfill, HandlerPath: "/tasks/backfill-page", Payload: payload, TaskID: fmt.Sprintf("backfill-%s-%s-%d", uid, runID, page+1)})
		return err
	}
	if _, err = s.db.Collection("users").Doc(uid).Set(ctx, map[string]any{
		"lastSyncedAt": firestore.ServerTimestamp,
		"updatedAt":    firestore.ServerTimestamp,
	}, firestore.MergeAll); err != nil {
		return err
	}
	return s.enqueueDerived(ctx, uid, fmt.Sprintf("backfill-complete-%d", page))
}

func (s *ActivityService) Hydrate(ctx context.Context, uid, activityID string) error {
	ref := s.db.Collection("users").Doc(uid).Collection("activities").Doc(activityID)
	snap, err := ref.Get(ctx)
	if err == nil {
		data := snap.Data()
		if data["hydrated"] == true && data["streamsHydrated"] == true && int(number(data["streamsVersion"])) == 4 {
			return nil
		}
	} else if status.Code(err) != codes.NotFound {
		return err
	}
	return s.fetchAndUpsert(ctx, uid, activityID, time.Now().Unix(), true)
}

func (s *ActivityService) fetchAndUpsert(ctx context.Context, uid, activityID string, eventTime int64, includeStreams bool) error {
	tombRef := s.db.Collection("activityTombstones").Doc(uid + "_" + activityID)
	tomb, err := tombRef.Get(ctx)
	tombExists := err == nil
	if err != nil && status.Code(err) != codes.NotFound {
		return err
	}
	if tombExists && int64(number(tomb.Data()["sourceEventTime"])) >= eventTime {
		return nil
	}
	var activity StravaActivity
	err = s.tokens.WithAccessToken(ctx, uid, func(token string) error {
		var fetchErr error
		activity, fetchErr = s.gateway.GetActivity(ctx, token, activityID)
		return fetchErr
	})
	if err != nil {
		var api *StravaAPIError
		if errors.As(err, &api) && api.Status == 404 {
			return s.deleteActivity(ctx, uid, activityID, eventTime)
		}
		return err
	}
	if !IsSupportedActivity(activity) {
		return s.deleteActivity(ctx, uid, activityID, eventTime)
	}
	ref := s.db.Collection("users").Doc(uid).Collection("activities").Doc(activityID)
	previous, previousErr := ref.Get(ctx)
	var previousData map[string]any
	if previousErr == nil {
		previousData = previous.Data()
	} else if status.Code(previousErr) != codes.NotFound {
		return previousErr
	}
	next := NormalizeActivity(activity, true, &eventTime)
	next["streamsHydrated"] = false
	affectsDerived := SummaryChanged(previousData, next)
	if includeStreams {
		var streams map[string]any
		err = s.tokens.WithAccessToken(ctx, uid, func(token string) error {
			var fetchErr error
			streams, fetchErr = s.gateway.GetStreams(ctx, token, activityID)
			return fetchErr
		})
		if err != nil {
			return err
		}
		for key, value := range normalizeStreams(streams, activity.StartDate) {
			next[key] = value
		}
	}
	next["detailHydratedAt"] = firestore.ServerTimestamp
	next["updatedAt"] = firestore.ServerTimestamp
	if _, err = ref.Set(ctx, next, firestore.MergeAll); err != nil {
		return err
	}
	if tombExists {
		if _, err = tombRef.Delete(ctx); err != nil {
			return err
		}
	}
	if err := s.markRunNowDuplicates(ctx, uid, activityID, next); err != nil {
		return err
	}
	if newStarted, parseErr := time.Parse(time.RFC3339, stringValue(next["startedAt"])); parseErr == nil {
		if err := s.enqueuePeriodStats(ctx, uid, newStarted); err != nil {
			return err
		}
		// Rare, but a corrected startedAt moves the activity to a different
		// day/week/month — the period it used to belong to must also be
		// rebuilt or it would keep double-counting a session that moved away.
		if previousData != nil {
			if oldStarted, oldErr := time.Parse(time.RFC3339, stringValue(previousData["startedAt"])); oldErr == nil && !oldStarted.Equal(newStarted) {
				if err := s.enqueuePeriodStats(ctx, uid, oldStarted); err != nil {
					return err
				}
			}
		}
	}
	// Telegram notify is field-idempotent, not "doc did not exist" based.
	// Backfill can create a recent activity before the webhook update arrives;
	// the later webhook would otherwise skip notification because previousData
	// is already present.
	if shouldEnqueueTelegramActivity(previousData, next, time.Now()) {
		if err := s.enqueueNotify(ctx, uid, activityID); err != nil {
			return err
		}
	}
	if affectsDerived {
		return s.enqueueDerived(ctx, uid, "activity-"+activityID+"-"+itoa64(eventTime))
	}
	return nil
}

func (s *ActivityService) deleteActivity(ctx context.Context, uid, activityID string, eventTime int64) error {
	activityRef := s.db.Collection("users").Doc(uid).Collection("activities").Doc(activityID)
	tombRef := s.db.Collection("activityTombstones").Doc(uid + "_" + activityID)
	// Read the doc's own startedAt before it's deleted — otherwise there is no
	// way to know which periodStats day/week/month to rebuild afterward, and
	// it would keep counting a session that no longer exists.
	var deletedStartedAt time.Time
	if snap, err := activityRef.Get(ctx); err == nil {
		deletedStartedAt, _ = time.Parse(time.RFC3339, stringValue(snap.Data()["startedAt"]))
	} else if status.Code(err) != codes.NotFound {
		return err
	}
	err := s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, getErr := tx.Get(tombRef)
		if getErr == nil && int64(number(snap.Data()["sourceEventTime"])) > eventTime {
			return nil
		}
		if getErr != nil && status.Code(getErr) != codes.NotFound {
			return getErr
		}
		if err := tx.Set(tombRef, map[string]any{"uid": uid, "activityId": activityID, "sourceEventTime": eventTime, "deletedAt": firestore.ServerTimestamp, "updatedAt": firestore.ServerTimestamp, "expiresAt": time.Now().Add(30 * 24 * time.Hour)}, firestore.MergeAll); err != nil {
			return err
		}
		return tx.Delete(activityRef)
	})
	if err != nil {
		return err
	}
	if !deletedStartedAt.IsZero() {
		if err := s.enqueuePeriodStats(ctx, uid, deletedStartedAt); err != nil {
			return err
		}
	}
	return s.enqueueDerived(ctx, uid, "delete-"+activityID+"-"+itoa64(eventTime))
}

// NotifyTelegram loads the activity + owner's display name and posts a
// Telegram activity alert (see enqueueNotify for when this task is
// scheduled). A no-op, not an error, if Telegram isn't configured or the
// activity is gone by the time the task runs — neither is worth retrying.
func (s *ActivityService) NotifyTelegram(ctx context.Context, uid, activityID string) error {
	if !s.telegram.Enabled() {
		return nil
	}
	ref := s.db.Collection("users").Doc(uid).Collection("activities").Doc(activityID)
	data, err := getData(ctx, ref)
	if err != nil {
		return err
	}
	if data == nil {
		return nil
	}
	if data["telegramNotifiedAt"] != nil {
		return nil
	}
	profile, err := resolveProfile(ctx, s.db, uid)
	if err != nil {
		return err
	}
	// Chống double-notify: nếu buổi này đã được tường thuật LIVE (app 3i) và
	// giờ bản Strava trùng sync về, nuốt tin lặp. Đánh dấu đã-notify rồi thôi.
	if stringValue(data["source"]) == "strava" && liveFinishAlreadyCovered(profile, data, time.Now()) {
		_, _ = ref.Set(ctx, map[string]any{"telegramNotifiedAt": firestore.ServerTimestamp}, firestore.MergeAll)
		return nil
	}
	detailURL := activityDetailURL(s.webBaseURL, uid, activityID)
	displayName := preferredName(profile)
	fact := activityFact(activityID, data)
	activityName := stringValue(data["name"])
	hasBot := s.broadcast != nil && s.broadcast.Enabled()

	// Để BOT tự viết trọn lời thông báo bằng giọng người thay cho thẻ số liệu
	// máy móc. Lỗi hay chưa bật bot thì rơi về thẻ tĩnh — không bao giờ mất
	// thông báo.
	announcement := ""
	if hasBot {
		announcement = s.broadcast.ActivityAnnouncement(ctx, displayName, activityName, fact)
	}

	// Claim cờ TRƯỚC khi gửi để retry (hoặc giao song song) không bắn lặp: nếu
	// ghi cờ SAU khi gửi mà ghi hỏng, retry sẽ gửi lần 2. Gửi lỗi sau claim thì
	// mất tin còn hơn gửi đôi.
	claimed, err := claimOnce(ctx, s.db, ref, "telegramNotifiedAt", map[string]any{
		"telegramNotifiedAt": firestore.ServerTimestamp,
		"updatedAt":          firestore.ServerTimestamp,
	})
	if err != nil {
		return err
	}
	if !claimed {
		return nil
	}
	if announcement != "" {
		if err := s.telegram.SendActivityAnnouncement(ctx, announcement, detailURL); err != nil {
			slog.WarnContext(ctx, "activity.telegram_send_failed_after_claim", "error", err, "activityId", activityID)
			return nil
		}
	} else if err := s.telegram.SendActivityAlert(ctx, displayName, activityName, fact, detailURL, ""); err != nil {
		slog.WarnContext(ctx, "activity.telegram_send_failed_after_claim", "error", err, "activityId", activityID)
		return nil
	}

	// Telegram không đẩy lại tin của chính bot, nên tự ghi vào trí nhớ ở đây —
	// nếu không, mọi phản ứng của nhóm quanh thông báo sẽ mất ngữ cảnh. Ghi
	// đúng thứ đã gửi (lời bot viết, hoặc bản plain của thẻ). Không chặn luồng
	// nếu ghi hỏng.
	if hasBot {
		recorded := announcement
		if recorded == "" {
			recorded = telegramActivityPlain(displayName, activityName, fact)
		}
		if err := s.broadcast.RecordBroadcast(ctx, s.telegram.ChatID(), recorded); err != nil {
			slog.WarnContext(ctx, "activity.broadcast_record_failed", "error", err)
		}
	}
	return nil
}

func shouldEnqueueTelegramActivity(previousData map[string]any, next map[string]any, now time.Time) bool {
	if stringValue(next["source"]) != "strava" || !notifySportTypes[stringValue(next["sportType"])] {
		return false
	}
	if previousData != nil && previousData["telegramNotifiedAt"] != nil {
		return false
	}
	startedAt, err := time.Parse(time.RFC3339, stringValue(next["startedAt"]))
	if err != nil {
		return false
	}
	return !startedAt.Before(now.Add(-telegramActivityNotifyWindow)) && !startedAt.After(now.Add(2*time.Hour))
}

// PublicActivitySummary is the read-only, no-login-required projection of an
// activity shown at GET /v1/public/activities/{uid}/{activityId} — the page
// the Telegram alert's "Xem chi tiết" button links to.
type PublicActivitySummary struct {
	DisplayName  string
	ActivityName string
	Fact         ActivityFact
}

func (s *ActivityService) PublicSummary(ctx context.Context, uid, activityID string) (*PublicActivitySummary, error) {
	data, err := getData(ctx, s.db.Collection("users").Doc(uid).Collection("activities").Doc(activityID))
	if err != nil {
		return nil, err
	}
	if data == nil {
		return nil, &HTTPError{Status: 404, Code: "not_found", Message: "Không tìm thấy hoạt động."}
	}
	profile, err := resolveProfile(ctx, s.db, uid)
	if err != nil {
		return nil, err
	}
	return &PublicActivitySummary{DisplayName: preferredName(profile), ActivityName: stringValue(data["name"]), Fact: activityFact(activityID, data)}, nil
}

func (s *ActivityService) uidForAthlete(ctx context.Context, athleteID string) (string, error) {
	snap, err := s.db.Collection("stravaAthleteLinks").Doc(athleteID).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	return stringValue(snap.Data()["uid"]), nil
}
func (s *ActivityService) enqueueDerived(ctx context.Context, uid, cause string) error {
	_, err := s.tasks.Publish(ctx, PublishTask{Queue: QueueDerived, HandlerPath: "/tasks/rebuild-derived-data", Payload: map[string]any{"uid": uid, "cause": cause}, TaskID: StableTaskID("derived", map[string]any{"uid": uid, "cause": cause})})
	return err
}

// enqueueNotify schedules the Telegram activity-alert task. Stable task ID
// keyed on uid+activityId — a genuinely new activity only ever triggers this
// once, so no dedupe suffix (like eventTime) is needed.
func (s *ActivityService) enqueueNotify(ctx context.Context, uid, activityID string) error {
	payload := map[string]any{"uid": uid, "activityId": activityID}
	_, err := s.tasks.Publish(ctx, PublishTask{Queue: QueueNotify, HandlerPath: "/tasks/notify-telegram", Payload: payload, TaskID: StableTaskID("notify", payload)})
	return err
}

// enqueuePeriodStats schedules a rebuild of the day/week/month periodStats
// docs that startedAt falls into. Reused for both the activity's current
// startedAt and (when it moved) its previous one, so a stable task ID keyed
// on uid+startedAt is enough to dedupe redundant triggers for the same spot.
func (s *ActivityService) enqueuePeriodStats(ctx context.Context, uid string, startedAt time.Time) error {
	payload := map[string]any{"uid": uid, "startedAt": startedAt.UTC().Format(time.RFC3339Nano)}
	_, err := s.tasks.Publish(ctx, PublishTask{Queue: QueueDerived, HandlerPath: "/tasks/rebuild-period-stats", Payload: payload, TaskID: StableTaskID("period-stats", payload)})
	return err
}
func (s *ActivityService) failEvent(ctx context.Context, ref *firestore.DocumentRef, cause error) error {
	code := "unknown_error"
	var api *StravaAPIError
	if errors.As(cause, &api) {
		code = fmt.Sprintf("strava_%d", api.Status)
	}
	_, _ = ref.Set(ctx, map[string]any{"status": "failed", "lastErrorCode": code, "updatedAt": firestore.ServerTimestamp}, firestore.MergeAll)
	return cause
}

func normalizeStreams(raw map[string]any, startedAt string) map[string]any {
	streams := map[string][]float64{}
	for key, value := range raw {
		if key == "latlng" {
			continue
		}
		data := streamData(value)
		values := make([]float64, 0, len(data))
		for _, item := range data {
			n := number(item)
			if n != 0 || item == float64(0) {
				values = append(values, n)
			}
		}
		if len(values) > 0 {
			streams[key] = downsample(values, 300)
		}
	}
	latlng := streamData(raw["latlng"])
	times := streamData(raw["time"])
	start, _ := time.Parse(time.RFC3339, startedAt)
	points := make([]map[string]any, 0, min(len(latlng), 500))
	for _, index := range sampleIndexes(len(latlng), 500) {
		pair, ok := latlng[index].([]any)
		if !ok || len(pair) < 2 {
			continue
		}
		lat, lon := number(pair[0]), number(pair[1])
		seconds := int64(index)
		if index < len(times) {
			seconds = int64(math.Round(number(times[index])))
		}
		points = append(points, map[string]any{"latitude": lat, "longitude": lon, "timestamp": start.Add(time.Duration(seconds) * time.Second).UTC().Format(time.RFC3339Nano)})
	}
	return map[string]any{"streams": streams, "routePoints": points, "streamsHydrated": true, "streamsVersion": 4}
}
func streamData(value any) []any {
	record, ok := value.(map[string]any)
	if !ok {
		return nil
	}
	values, _ := record["data"].([]any)
	return values
}
func downsample(values []float64, maxSamples int) []float64 {
	if len(values) <= maxSamples {
		return values
	}
	out := make([]float64, maxSamples)
	last := len(values) - 1
	for i := range out {
		out[i] = values[int(math.Round(float64(i*last)/float64(maxSamples-1)))]
	}
	return out
}
func sampleIndexes(length, maxSamples int) []int {
	if length <= 0 {
		return nil
	}
	size := min(length, maxSamples)
	out := make([]int, size)
	if size == 1 {
		return out
	}
	last := length - 1
	for i := range out {
		out[i] = int(math.Round(float64(i*last) / float64(size-1)))
	}
	return out
}
