package backend

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// GameStore là lớp Firestore của Ma Sói (3.7). Mỗi lần chốt là một transaction:
// đọc state, action, km, người rời nhóm; chạy engine; ghi state, phần công khai,
// event, outbox và feed cùng lúc. Hai lần chốt chạy song song thì Firestore cho
// một bên chạy lại và bên đó thấy đã chốt rồi, nên không có event hay tin đôi.
type GameStore struct {
	db *firestore.Client
	// pscChatID là TELEGRAM_CHAT_ID; ván thử không được tạo trong chat này (X1).
	pscChatID string
	// frameKm tính km khung của một người; mặc định LoadFrameKm.
	frameKm func(ctx context.Context, uid string, frameEnd time.Time) (FrameKm, error)
	// beforeSubmit chỉ test đặt: chen một bước chốt vào giữa lúc PressButton đọc
	// state và lúc transaction ghi action.
	beforeSubmit func()
}

func NewGameStore(db *firestore.Client, pscChatID string) *GameStore {
	return &GameStore{db: db, pscChatID: pscChatID, frameKm: func(ctx context.Context, uid string, frameEnd time.Time) (FrameKm, error) {
		return LoadFrameKm(ctx, db, uid, frameEnd)
	}}
}

const (
	gameRegistering = "registering"
	gameStarting    = "starting" // api đã nhận Start, chờ bot kiểm người và chia vai
	gameRunning     = "running"
	gameEnded       = "ended"
	gameCancelled   = "cancelled"
)

var errGameRunning = &HTTPError{Status: http.StatusConflict, Code: "game_running", Message: "Đang có ván Ma Sói chưa kết thúc."}

// errKmNotReady: state đã sang mốc cần km mà snapshot chưa ghi (bước khác chốt
// xen vào giữa lúc ghi km và lúc mở transaction). Chạy lại vòng snapshot.
var errKmNotReady = errors.New("snapshot km chưa có")

// maxAdvanceSteps chặn vòng chạy bù: một lần gọi chạy tối đa ngần này bước,
// phần còn lại để task hoặc tick kế tiếp chạy tiếp.
const maxAdvanceSteps = 20

func (s *GameStore) gameRef(id string) *firestore.DocumentRef {
	return s.db.Collection("games").Doc(id)
}

func (s *GameStore) currentRef() *firestore.DocumentRef {
	return s.db.Collection("gameState").Doc("current")
}

func secretRef(game *firestore.DocumentRef) *firestore.DocumentRef {
	return game.Collection("secret").Doc("state")
}

func roundRef(game *firestore.DocumentRef, n int) *firestore.DocumentRef {
	return game.Collection("rounds").Doc(strconv.Itoa(n))
}

// kmRound là vòng chứa snapshot km của mốc 22h kế tiếp: mở đêm 1 ghi vào
// rounds/0, chốt ngày n ghi vào rounds/n.
func kmRound(st *werewolf.State) int {
	if st.Phase == werewolf.PhaseSetup {
		return 0
	}
	return st.Round
}

type NewGameInput struct {
	CreatedBy string
	ChatID    string
	ThreadID  int64
	Config    werewolf.Config
	// RegistrationDeadline: quá hạn thì không đăng ký được nữa; zero là không hạn.
	RegistrationDeadline time.Time
}

// CreateGame mở ván mới ở trạng thái đăng ký. Chỉ một ván được mở một lúc:
// gameState/current còn trỏ tới ván chưa kết thúc thì trả 409 game_running.
func (s *GameStore) CreateGame(ctx context.Context, in NewGameInput, now time.Time) (string, error) {
	if in.Config.TestMode {
		// Ván thử có người giả và lệnh admin đẩy giờ; chạy trong PSC là tin của nó
		// tới cả 16 người thật. Thiếu cấu hình thì không kiểm được, nên từ chối.
		if s.pscChatID == "" {
			return "", errors.New("thiếu TELEGRAM_CHAT_ID, không kiểm được ván thử có nằm ngoài PSC không")
		}
		if strings.TrimSpace(in.ChatID) == s.pscChatID {
			return "", errTestModeInPsc
		}
	}
	ref := s.db.Collection("games").NewDoc()
	cfg, err := json.Marshal(in.Config)
	if err != nil {
		return "", err
	}
	var deadline any
	if !in.RegistrationDeadline.IsZero() {
		deadline = in.RegistrationDeadline
	}
	err = s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		cur, err := tx.Get(s.currentRef())
		if err != nil && status.Code(err) != codes.NotFound {
			return err
		}
		if cur.Exists() {
			if id := stringValue(cur.Data()["gameId"]); id != "" {
				g, err := tx.Get(s.gameRef(id))
				if err != nil && status.Code(err) != codes.NotFound {
					return err
				}
				if g.Exists() && !gameClosed(stringValue(g.Data()["status"])) {
					return errGameRunning
				}
			}
		}
		if err := tx.Create(ref, map[string]any{
			"status": gameRegistering, "createdBy": in.CreatedBy, "createdAt": now,
			"chatId": in.ChatID, "threadId": in.ThreadID, "testMode": in.Config.TestMode,
			"config": string(cfg), "version": 0, "eventSeq": 0, "feedSeq": 0, "updatedAt": now,
			"registrationDeadline": deadline, "playerCount": 0,
		}); err != nil {
			return err
		}
		return tx.Set(s.currentRef(), map[string]any{"gameId": ref.ID, "updatedAt": now})
	})
	if err != nil {
		return "", err
	}
	return ref.ID, nil
}

func gameClosed(status string) bool { return status == gameEnded || status == gameCancelled }

// StartGame ghi state ban đầu (đã chia vai) và các tin mở ván. Chỉ chạy được
// một lần: ván đã chạy thì trả 409.
func (s *GameStore) StartGame(ctx context.Context, gameID string, st *werewolf.State, now time.Time) error {
	return s.startGame(ctx, gameID, st, nil, now)
}

// startRoster là phần game-start sửa danh sách người chơi lúc Start: xoá người
// bị loại và ghi tg hiện tại của người còn lại, vì lúc đăng ký người đó có thể đã
// đổi liên kết (L1 (b)).
type startRoster struct {
	exclude  []string
	tgUserID map[string]int64
}

// startGame là StartGame; roster khác nil thì là đường của game-start: ván phải
// còn ở starting, vì admin có thể đã huỷ trong lúc bot hỏi Telegram.
func (s *GameStore) startGame(ctx context.Context, gameID string, st *werewolf.State, roster *startRoster, now time.Time) error {
	game := s.gameRef(gameID)
	return s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		g, err := tx.Get(game)
		if err != nil {
			return err
		}
		status := stringValue(g.Data()["status"])
		open := status == gameStarting || roster == nil && status == gameRegistering
		if !open {
			return &HTTPError{Status: http.StatusConflict, Code: "game_running", Message: "Ván đã bắt đầu hoặc đã kết thúc."}
		}
		// players/{uid} do bước đăng ký ghi, có tgUserId; thiếu thì dữ liệu đã hỏng,
		// không tự tạo, vì tới 22h người đó sẽ bị tính là đã rời PSC.
		uids := sortedPlayers(st)
		var refs []*firestore.DocumentRef
		for _, uid := range uids {
			refs = append(refs, game.Collection("players").Doc(uid))
		}
		players, err := tx.GetAll(refs)
		if err != nil {
			return err
		}
		for i, p := range players {
			if !p.Exists() {
				return fmt.Errorf("thiếu players/%s", uids[i])
			}
		}
		msgs := withoutFakeDMs(startMessages(st), g.Data())
		chats, err := readChats(tx, game, msgs)
		if err != nil {
			return err
		}
		for _, ref := range refs {
			fields := map[string]any{"alive": true}
			if roster != nil {
				if tg, ok := roster.tgUserID[ref.ID]; ok {
					fields["tgUserId"] = tg
				}
			}
			if err := tx.Set(ref, fields, firestore.MergeAll); err != nil {
				return err
			}
		}
		if roster != nil {
			for _, uid := range roster.exclude {
				if err := tx.Delete(game.Collection("players").Doc(uid)); err != nil {
					return err
				}
			}
		}
		w := stepWrite{tx: tx, game: game, gameData: g.Data(), after: st, msgs: msgs, chats: chats, now: now, wall: now,
			extra: map[string]any{"playerCount": len(st.Players), "startError": nil}}
		return w.commit(map[string]any{"kind": "start"})
	})
}

// AdvanceResult là việc AdvanceGame đã làm và lần hẹn kế tiếp. Caller hẹn task
// game-advance vào NextAt + 30s với TaskID StableTaskID("gameadv", gameId+TaskKey).
// NextAt là giờ thật, đã trừ độ lệch đồng hồ của ván thử; rỗng khi ván không
// chạy hoặc đang tạm dừng.
type AdvanceResult struct {
	Steps   int
	Status  string
	NextAt  time.Time
	TaskKey string
}

// AdvanceGame chạy hết các bước đã tới hạn lúc wall (giờ thật), mỗi bước một
// transaction, đúng thứ tự (E5). Gọi lại bao nhiêu lần cũng được: bước đã chốt
// thì thôi.
func (s *GameStore) AdvanceGame(ctx context.Context, gameID string, wall time.Time) (AdvanceResult, error) {
	var res AdvanceResult
	for i := 0; i < maxAdvanceSteps; i++ {
		if err := s.snapshotKmIfDue(ctx, gameID, wall); err != nil {
			return res, err
		}
		stepped, err := s.advanceOnce(ctx, gameID, wall, "", &res)
		if errors.Is(err, errKmNotReady) {
			continue
		}
		if err != nil || !stepped {
			return res, err
		}
		res.Steps++
	}
	return res, nil
}

// gameAdvanceTask là payload của /tasks/game-advance. Bot decode chặt, nên thêm
// field thì deploy bot trước. TaskKey chỉ để đọc log: handler luôn đọc lại state.
type gameAdvanceTask struct {
	GameID  string `json:"gameId"`
	TaskKey string `json:"taskKey,omitempty"`
}

// advanceDelay: task hẹn sau mốc một chút, để đồng hồ lệch vài giây không làm
// task tới sớm, thấy chưa tới hạn rồi hẹn lại đúng mốc cũ (trùng TaskID, bị bỏ).
const advanceDelay = 30 * time.Second

// gameAdvanceTaskFor: res rỗng là chạy ngay, không TaskID (sau Start, resume,
// extend: handler đọc state rồi tự hẹn). Có NextAt thì hẹn vào NextAt + 30s,
// TaskID theo TaskKey nên tick, task và admin cùng hẹn một mốc chỉ ra một task.
func gameAdvanceTaskFor(gameID string, res AdvanceResult) PublishTask {
	t := PublishTask{Queue: QueueGameInbound, HandlerPath: "/tasks/game-advance", Payload: gameAdvanceTask{GameID: gameID, TaskKey: res.TaskKey}}
	if !res.NextAt.IsZero() {
		at := res.NextAt.Add(advanceDelay)
		t.ScheduleTime = &at
		t.TaskID = StableTaskID("gameadv", gameID+res.TaskKey)
	}
	return t
}

// CurrentGame là ván gameState/current trỏ tới và status của nó; chưa có ván
// nào thì id rỗng.
func (s *GameStore) CurrentGame(ctx context.Context) (id, gameStatus string, err error) {
	cur, err := s.currentRef().Get(ctx)
	if status.Code(err) == codes.NotFound {
		return "", "", nil
	}
	if err != nil {
		return "", "", err
	}
	id = stringValue(cur.Data()["gameId"])
	if id == "" {
		return "", "", nil
	}
	g, err := s.gameRef(id).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return "", "", nil
	}
	if err != nil {
		return "", "", err
	}
	return id, stringValue(g.Data()["status"]), nil
}

// HasPendingOutbox: ván còn chat có tin chờ gửi.
func (s *GameStore) HasPendingOutbox(ctx context.Context, gameID string) (bool, error) {
	docs, err := s.gameRef(gameID).Collection("outboxChats").Where("pending", "==", true).Limit(1).Documents(ctx).GetAll()
	return len(docs) > 0, err
}

// snapshotKmIfDue: tới mốc 22h thì tính km của mọi người chơi và ghi bằng
// Create, bản ghi đầu tiên thắng (R29: không chốt lại). Chạy ngoài transaction vì
// mỗi người tốn vài query; transaction của bước chỉ đọc các doc này. Ván thử
// không đọc buổi chạy: giờ ván đã bị đẩy nên khung không khớp buổi chạy thật,
// km do admin/km ghi, ai không được ghi thì là 0.
func (s *GameStore) snapshotKmIfDue(ctx context.Context, gameID string, wall time.Time) error {
	game := s.gameRef(gameID)
	g, err := game.Get(ctx)
	if err != nil {
		return err
	}
	now, testMode := gameNow(g.Data(), wall), g.Data()["testMode"] == true
	snap, err := secretRef(game).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return nil // chưa Start
	}
	if err != nil {
		return err
	}
	st, err := decodeState(snap.Data())
	if err != nil {
		return err
	}
	end, ok := st.KmFrameEnd()
	if !ok || st.Paused || now.Before(end) {
		return nil
	}
	refs := kmRefs(game, st)
	existing, err := s.db.GetAll(ctx, refs)
	if err != nil {
		return err
	}
	for i, doc := range existing {
		if doc.Exists() {
			continue
		}
		uid := refs[i].ID
		doc := map[string]any{"frameEnd": end, "meters": 0.0, "source": "test", "createdAt": wall}
		if !testMode {
			fk, err := s.frameKm(ctx, uid, end)
			if err != nil {
				return fmt.Errorf("km của %s: %w", uid, err)
			}
			doc = kmDoc(fk, wall)
		}
		if _, err := refs[i].Create(ctx, doc); err != nil && status.Code(err) != codes.AlreadyExists {
			return err
		}
	}
	return nil
}

func kmRefs(game *firestore.DocumentRef, st *werewolf.State) []*firestore.DocumentRef {
	col := roundRef(game, kmRound(st)).Collection("km")
	var refs []*firestore.DocumentRef
	for _, uid := range sortedPlayers(st) {
		refs = append(refs, col.Doc(uid))
	}
	return refs
}

func kmDoc(fk FrameKm, now time.Time) map[string]any {
	return map[string]any{
		"frameStart": fk.FrameStart, "frameEnd": fk.FrameEnd,
		"officialMeters": fk.OfficialMeters, "healthMeters": fk.HealthMeters, "meters": fk.Meters,
		"kmSource": fk.Source, "hourlyYesterday": fk.HourlyYesterday, "hourlyToday": fk.HourlyToday,
		"scaleYesterday": fk.ScaleYesterday, "scaleToday": fk.ScaleToday,
		"source": "auto", "createdAt": now,
	}
}

// advanceOnce chạy một việc đã tới hạn trong một transaction. stepped=false khi
// không còn gì tới hạn hoặc ván không chạy. expectKey khác rỗng là CAS của
// admin/advance: TaskKey đã khác thì trả errPhaseMoved, không chạy gì.
func (s *GameStore) advanceOnce(ctx context.Context, gameID string, wall time.Time, expectKey string, res *AdvanceResult) (bool, error) {
	game := s.gameRef(gameID)
	var stepped bool
	err := s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		stepped, res.NextAt, res.TaskKey = false, time.Time{}, ""
		g, err := tx.Get(game)
		if err != nil {
			return err
		}
		res.Status = stringValue(g.Data()["status"])
		if res.Status != gameRunning {
			return nil
		}
		sec, err := tx.Get(secretRef(game))
		if err != nil {
			return err
		}
		st, err := decodeState(sec.Data())
		if err != nil {
			return err
		}
		if expectKey != "" && st.TaskKey() != expectKey {
			return errPhaseMoved
		}
		offset := clockOffset(g.Data())
		now := wall.Add(offset)
		// Ván tạm dừng thì không hẹn gì; resume sẽ kick game-advance.
		if !st.Paused {
			res.NextAt, res.TaskKey = st.NextAt().Add(-offset), st.TaskKey()
		}
		in, err := s.readInputs(tx, game, st, now)
		if err != nil {
			return err
		}
		next, evs, err := werewolf.Advance(st, in, now)
		if errors.Is(err, werewolf.ErrNotDue) || errors.Is(err, werewolf.ErrNotRunning) {
			return nil
		}
		if err != nil {
			return err
		}
		msgs := withoutFakeDMs(stepMessages(st, next, evs), g.Data())
		chats, err := readChats(tx, game, msgs)
		if err != nil {
			return err
		}
		inputs, err := json.Marshal(in)
		if err != nil {
			return err
		}
		w := stepWrite{tx: tx, game: game, gameData: g.Data(), before: st, after: next, events: evs, msgs: msgs, chats: chats, now: now, wall: wall,
			users: s.db.Collection("users")}
		if err := w.commit(map[string]any{"kind": "step", "phaseKey": st.PhaseKey(), "inputs": string(inputs)}); err != nil {
			return err
		}
		stepped = true
		res.Status, res.NextAt, res.TaskKey = w.status(), time.Time{}, ""
		if res.Status == gameRunning {
			res.NextAt, res.TaskKey = next.NextAt().Add(-offset), next.TaskKey()
		}
		return nil
	})
	return stepped, err
}

// readInputs đọc trong transaction mọi thứ engine cần cho bước kế: action của
// vòng hiện tại, snapshot km nếu bước này là mốc 22h, và người đã rời PSC.
func (s *GameStore) readInputs(tx *firestore.Transaction, game *firestore.DocumentRef, st *werewolf.State, now time.Time) (werewolf.Inputs, error) {
	var in werewolf.Inputs
	docs, err := tx.Documents(roundRef(game, st.Round).Collection("actions")).GetAll()
	if err != nil {
		return in, err
	}
	for _, d := range docs {
		if a, ok := decodeAction(d.Data()); ok {
			in.Actions = append(in.Actions, a)
		}
	}
	sort.Slice(in.Actions, func(i, j int) bool {
		a, b := in.Actions[i], in.Actions[j]
		if !a.ReceivedAt.Equal(b.ReceivedAt) {
			return a.ReceivedAt.Before(b.ReceivedAt)
		}
		return a.Actor+string(a.Kind) < b.Actor+string(b.Kind)
	})

	if end, ok := st.KmFrameEnd(); ok && !now.Before(end) {
		kms, err := tx.GetAll(kmRefs(game, st))
		if err != nil {
			return in, err
		}
		in.Km = map[string]float64{}
		for _, d := range kms {
			if !d.Exists() {
				return in, errKmNotReady
			}
			in.Km[d.Ref.ID] = number(d.Data()["meters"])
		}
	}

	in.Left, err = s.readLeft(tx, game, st)
	return in, err
}

// readLeft: người chơi còn sống mà tgLinks báo không còn ở PSC, hoặc không còn
// liên kết (xoá tài khoản, R33). Người chơi giả của testMode không rời được.
func (s *GameStore) readLeft(tx *firestore.Transaction, game *firestore.DocumentRef, st *werewolf.State) ([]string, error) {
	uids := sortedPlayers(st)
	var refs []*firestore.DocumentRef
	for _, uid := range uids {
		refs = append(refs, game.Collection("players").Doc(uid))
	}
	players, err := tx.GetAll(refs)
	if err != nil {
		return nil, err
	}
	var linkRefs []*firestore.DocumentRef
	var linkUIDs, left []string
	for i, p := range players {
		uid := uids[i]
		if !st.Players[uid].Alive {
			continue
		}
		if !p.Exists() {
			return nil, fmt.Errorf("thiếu players/%s của người chơi trong state", uid)
		}
		if p.Data()["fake"] == true {
			continue
		}
		tg := tgIDString(p.Data()["tgUserId"])
		if tg == "" {
			left = append(left, uid)
			continue
		}
		linkRefs = append(linkRefs, s.db.Collection("tgLinks").Doc(tg))
		linkUIDs = append(linkUIDs, uid)
	}
	if len(linkRefs) > 0 {
		links, err := tx.GetAll(linkRefs)
		if err != nil {
			return nil, err
		}
		for i, l := range links {
			if !l.Exists() || l.Data()["inPsc"] != true || stringValue(l.Data()["uid"]) != linkUIDs[i] {
				left = append(left, linkUIDs[i])
			}
		}
	}
	sort.Strings(left)
	return left, nil
}

func tgIDString(v any) string {
	switch x := v.(type) {
	case string:
		return x
	case int64:
		return strconv.FormatInt(x, 10)
	case float64:
		return strconv.FormatInt(int64(x), 10)
	}
	return ""
}

func decodeAction(d map[string]any) (werewolf.Action, bool) {
	if d["cleared"] == true {
		return werewolf.Action{}, false
	}
	a := werewolf.Action{Kind: werewolf.Kind(stringValue(d["kind"])), Actor: stringValue(d["uid"]), Choice: stringValue(d["choice"])}
	if t, ok := d["receivedAt"].(time.Time); ok {
		a.ReceivedAt = t
	}
	if raw, ok := d["targets"].([]any); ok {
		for _, t := range raw {
			a.Targets = append(a.Targets, stringValue(t))
		}
	}
	return a, a.Kind != "" && a.Actor != ""
}

func decodeState(d map[string]any) (*werewolf.State, error) {
	raw, ok := d["state"].(string)
	if !ok {
		return nil, errors.New("secret/state thiếu field state")
	}
	var st werewolf.State
	if err := json.Unmarshal([]byte(raw), &st); err != nil {
		return nil, fmt.Errorf("đọc secret/state: %w", err)
	}
	return &st, nil
}

// readChats đọc nextSeq của các chat sắp nhận tin. Phải đọc trước mọi lần ghi
// của transaction.
func readChats(tx *firestore.Transaction, game *firestore.DocumentRef, msgs []gameMsg) (map[string]int64, error) {
	chats := map[string]int64{}
	var refs []*firestore.DocumentRef
	for _, m := range msgs {
		if _, ok := chats[m.ChatKey]; !ok {
			chats[m.ChatKey] = 1
			refs = append(refs, game.Collection("outboxChats").Doc(m.ChatKey))
		}
	}
	if len(refs) == 0 {
		return chats, nil
	}
	docs, err := tx.GetAll(refs)
	if err != nil {
		return nil, err
	}
	for _, d := range docs {
		if d.Exists() {
			if n := int64(number(d.Data()["nextSeq"])); n > 0 {
				chats[d.Ref.ID] = n
			}
		}
	}
	return chats, nil
}

// stepWrite gom mọi lần ghi của một lần chốt (hoặc Start) trong transaction.
type stepWrite struct {
	tx            *firestore.Transaction
	game          *firestore.DocumentRef
	gameData      map[string]any
	before, after *werewolf.State // before nil khi không phải bước engine (Start, pause, resume)
	events        []werewolf.Event
	msgs          []gameMsg
	chats         map[string]int64
	// now là giờ ván (engine, event, feed, diedAt); wall là giờ thật (updatedAt,
	// outbox). Hai giờ chỉ khác nhau ở ván thử đã bị admin/advance đẩy giờ.
	now, wall time.Time
	// extra gộp thêm vào games/{id} (Start ghi playerCount sau khi loại người).
	extra map[string]any
	// users là collection users, để bước kết thúc ván ghi thẻ cho phe thắng.
	users *firestore.CollectionRef
}

func (w *stepWrite) status() string {
	if w.after.Phase == werewolf.PhaseEnded {
		return gameEnded
	}
	return gameRunning
}

func (w *stepWrite) commit(event map[string]any) error {
	tx, game, now, wall := w.tx, w.game, w.now, w.wall
	state, err := json.Marshal(w.after)
	if err != nil {
		return err
	}
	sum := sha256.Sum256(state)
	if err := tx.Set(secretRef(game), map[string]any{"state": string(state), "phaseKey": w.after.PhaseKey(), "updatedAt": wall}); err != nil {
		return err
	}

	eventSeq := int64(number(w.gameData["eventSeq"])) + 1
	evs, err := json.Marshal(w.events)
	if err != nil {
		return err
	}
	// at là giờ engine đã chạy bước, để replay; wallAt là giờ thật.
	event["seq"], event["at"], event["wallAt"], event["events"], event["stateHash"] = eventSeq, now, wall, string(evs), hex.EncodeToString(sum[:])
	if event["kind"] == "start" {
		event["state"] = string(state) // điểm đầu để replay
	}
	if err := tx.Create(game.Collection("events").Doc(strconv.FormatInt(eventSeq, 10)), event); err != nil {
		return err
	}

	public := w.publicGame()
	for k, v := range w.extra {
		public[k] = v
	}
	public["eventSeq"] = eventSeq
	public["version"] = int64(number(w.gameData["version"])) + 1
	reminderOnly := len(w.events) == 1 && w.events[0].Kind == werewolf.EventReminder
	if w.before != nil && !reminderOnly {
		feedSeq := int64(number(w.gameData["feedSeq"])) + 1
		public["feedSeq"] = feedSeq
		feed, err := json.Marshal(publicEvents(w.events))
		if err != nil {
			return err
		}
		if err := tx.Create(game.Collection("feed").Doc(strconv.FormatInt(feedSeq, 10)), map[string]any{
			"seq": feedSeq, "at": now, "wallAt": wall, "phaseKey": w.before.PhaseKey(), "round": w.after.Round,
			"phase": string(w.after.Phase), "events": string(feed),
		}); err != nil {
			return err
		}
	}
	if err := tx.Set(game, public, firestore.MergeAll); err != nil {
		return err
	}

	for _, e := range w.events {
		switch e.Kind {
		case werewolf.EventDeath:
			p := w.after.Players[e.UID]
			if err := tx.Set(game.Collection("players").Doc(e.UID), map[string]any{"alive": false, "deathRound": p.DeathRound, "diedAt": now}, firestore.MergeAll); err != nil {
				return err
			}
		case werewolf.EventVoid:
			ref := roundRef(game, w.before.Round).Collection("actions").Doc(e.UID + "_" + string(e.Action))
			if err := tx.Set(ref, map[string]any{"voidReason": e.Reason}, firestore.MergeAll); err != nil {
				return err
			}
		}
	}
	if err := w.writeGameCards(); err != nil {
		return err
	}
	return w.writeOutbox(eventSeq)
}

// writeGameCards trao thẻ cho người phe thắng, kể cả người đã chết, ở đúng bước
// ván chuyển sang kết thúc. Người chơi giả của ván thử không có tài khoản nên
// không nhận. Ván huỷ không đi qua đây nên không ai có thẻ.
func (w *stepWrite) writeGameCards() error {
	if w.before == nil || w.before.Phase == werewolf.PhaseEnded || w.after.Phase != werewolf.PhaseEnded {
		return nil
	}
	if w.users == nil {
		return errors.New("stepWrite: ván kết thúc mà thiếu users để ghi thẻ")
	}
	fake := fakeUIDs(w.gameData)
	for _, uid := range w.after.Winners() {
		if fake[uid] {
			continue
		}
		ref := w.users.Doc(uid).Collection("gameCards").Doc(w.game.ID)
		if err := w.tx.Set(ref, gameCardDoc(w.game.ID, uid, w.after, w.wall)); err != nil {
			return err
		}
	}
	return nil
}

// publicGame là phần của games/{id} mà API được đọc: không có vai của người còn
// sống, không có seed, km chi tiết hay lựa chọn.
// gameNominees là người lên giàn trên doc ván; doc ghi trước khi có nhiều
// phiên chỉ có "nominee".
func gameNominees(data map[string]any) []string {
	var out []string
	for _, v := range anyList(data["nominees"]) {
		if uid := stringValue(v); uid != "" {
			out = append(out, uid)
		}
	}
	if len(out) == 0 {
		if uid := stringValue(data["nominee"]); uid != "" {
			out = []string{uid}
		}
	}
	return out
}

func (w *stepWrite) publicGame() map[string]any {
	st := w.after
	revealed := map[string]any{}
	for uid, p := range st.Players {
		if !p.Alive || st.Phase == werewolf.PhaseEnded {
			revealed[uid] = string(p.Role)
		}
	}
	out := map[string]any{
		"status": w.status(), "round": st.Round, "phase": string(st.Phase), "phaseKey": st.PhaseKey(),
		"paused": st.Paused, "nextAt": nil, "taskKey": st.TaskKey(), "updatedAt": w.wall,
		"deadline": nil, "winner": string(st.Winner), "nominee": nil,
	}
	if nominees := st.TrialNominees(); st.Phase == werewolf.PhaseTrial && len(nominees) > 0 {
		out["nominee"], out["nominees"] = nominees[0], nominees
	} else {
		out["nominees"] = nil
	}
	if len(revealed) > 0 {
		out["revealed"] = revealed
	}
	if st.Phase != werewolf.PhaseEnded {
		out["deadline"], out["nextAt"] = st.Deadline(), st.NextAt()
	}
	return out
}

func (w *stepWrite) writeOutbox(eventSeq int64) error {
	for _, m := range w.msgs {
		seq := w.chats[m.ChatKey]
		w.chats[m.ChatKey] = seq + 1
		data, err := json.Marshal(m.Data)
		if err != nil {
			return err
		}
		ref := w.game.Collection("outbox").Doc(m.ChatKey + "_" + strconv.FormatInt(seq, 10))
		if err := w.tx.Create(ref, map[string]any{
			"chatKey": m.ChatKey, "seq": seq, "template": m.Template, "data": string(data),
			"status": "pending", "eventSeq": eventSeq, "createdAt": w.wall,
		}); err != nil {
			return err
		}
	}
	return markChatsPending(w.tx, w.game, w.chats, w.wall)
}

// markChatsPending ghi nextSeq mới của các chat vừa nhận tin và bật pending
// cho bộ gửi.
func markChatsPending(tx *firestore.Transaction, game *firestore.DocumentRef, chats map[string]int64, wall time.Time) error {
	for key, next := range chats {
		if err := tx.Set(game.Collection("outboxChats").Doc(key), map[string]any{
			"chatKey": key, "nextSeq": next, "pending": true, "updatedAt": wall,
		}, firestore.MergeAll); err != nil {
			return err
		}
	}
	return nil
}
