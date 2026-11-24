package backend

import (
	"context"
	"crypto/rand"
	"fmt"
	"log/slog"
	"math/big"
	"net/http"
	"slices"
	"sort"
	"strings"
	"time"

	"cloud.google.com/go/firestore"
)

// Quà kèo: chủ một kèo công khai treo quà thật ở contractGifts/{contractId}.
// Doc kèo thì chủ kèo tự ghi được gần hết field (firestore.rules), nên quà nằm
// doc riêng chỉ backend ghi: sau khi có người tham gia, chủ kèo chỉ thêm được
// quà chứ không bớt hay đổi món đã treo.
//
// Người tham gia (trừ chủ kèo) đạt mục tiêu theo số backend tính thì có phần:
//   - draw: bốc thăm. Số người đạt không quá số suất thì khỏi bốc, ai đạt
//     trước nhận món trước.
//   - rank: xếp theo tiến độ trong số người đạt, bằng nhau thì ai đạt trước.
//
// Kết quả tính trong cùng transaction chốt kèo của job (FinalizeDueContracts),
// theo đúng số recalc vừa tính. Rules chặn app tự chốt kèo có quà, nên không có
// đường chốt nào bỏ qua bước này.
const (
	contractGiftDraw = "draw"
	contractGiftRank = "rank"

	contractGiftMaxItems = 5
	contractGiftMaxSlots = 20
	contractGiftPushPath = "/tasks/contract-gift-push"
	contractGiftPushKind = "contract_gift"
)

var (
	errContractNotFound    = &HTTPError{Status: http.StatusNotFound, Code: "contract_not_found", Message: "Không có kèo này."}
	errContractGiftOwner   = &HTTPError{Status: http.StatusForbidden, Code: "not_creator", Message: "Chỉ chủ kèo sửa được quà."}
	errContractGiftKind    = &HTTPError{Status: http.StatusUnprocessableEntity, Code: "gift_unsupported", Message: "Chỉ kèo công khai trong Club mới treo quà được."}
	errContractGiftLocked  = &HTTPError{Status: http.StatusConflict, Code: "gift_locked", Message: "Kèo đã hết hạn, không sửa quà được nữa."}
	errContractGiftShrink  = &HTTPError{Status: http.StatusConflict, Code: "gift_shrink", Message: "Kèo đã có người tham gia: chỉ thêm quà, không bớt hay đổi món đã treo."}
	errContractGiftInvalid = &HTTPError{Status: http.StatusUnprocessableEntity, Code: "invalid_gift", Message: "Quà không hợp lệ."}
	errContractGiftNone    = &HTTPError{Status: http.StatusNotFound, Code: "no_gift", Message: "Bạn không trúng quà ở kèo này."}
	errContractGiftWinner  = &HTTPError{Status: http.StatusNotFound, Code: "not_winner", Message: "Người này không trúng quà ở kèo này."}
	errContractGiftProfile = &HTTPError{Status: http.StatusConflict, Code: "profile_missing", Message: "Bạn chưa có hồ sơ công khai, mở app một lần rồi thử lại."}
	errContractGiftDone    = &HTTPError{Status: http.StatusConflict, Code: "gift_received", Message: "Quà đã tính là nhận rồi, không bỏ đánh dấu trao được."}
)

// ContractGiftItem là một món, có Slots suất. Thứ tự món là thứ tự bốc (draw)
// hay thứ tự hạng (rank).
type ContractGiftItem struct {
	ID     string   `json:"id"`
	Name   string   `json:"name"`
	Icon   string   `json:"icon"`
	Photos []string `json:"photos"`
	Slots  int      `json:"slots"`
}

type ContractGiftInput struct {
	Kind  string             `json:"kind"`
	Items []ContractGiftItem `json:"items"`
}

func contractGiftItemsFrom(raw any) []ContractGiftItem {
	var out []ContractGiftItem
	for _, v := range anyList(raw) {
		m, _ := v.(map[string]any)
		it := ContractGiftItem{ID: stringValue(m["id"]), Name: stringValue(m["name"]), Icon: stringValue(m["icon"]), Slots: int(number(m["slots"])), Photos: []string{}}
		for _, p := range anyList(m["photos"]) {
			it.Photos = append(it.Photos, stringValue(p))
		}
		out = append(out, it)
	}
	return out
}

func contractGiftItemsData(items []ContractGiftItem) []any {
	out := make([]any, 0, len(items))
	for _, it := range items {
		out = append(out, map[string]any{"id": it.ID, "name": it.Name, "icon": it.Icon, "photos": it.Photos, "slots": it.Slots})
	}
	return out
}

// normalizeContractGiftItems kiểm danh sách món gửi lên: tên bỏ khoảng trắng
// hai đầu, món mới được cấp id, ảnh nằm dưới thư mục của chủ kèo cho kèo này.
func normalizeContractGiftItems(creator, contractID string, items []ContractGiftItem) ([]ContractGiftItem, error) {
	if len(items) > contractGiftMaxItems {
		return nil, errContractGiftInvalid
	}
	prefix := "contractGifts/" + creator + "/" + contractID + "/"
	out := make([]ContractGiftItem, 0, len(items))
	ids := map[string]bool{}
	for _, it := range items {
		var ok bool
		if it.ID, it.Name, it.Photos, ok = normalizeRewardItem(it.ID, it.Name, it.Icon, it.Photos, prefix, ids); !ok {
			return nil, errContractGiftInvalid
		}
		if it.Slots < 1 || it.Slots > contractGiftMaxSlots {
			return nil, errContractGiftInvalid
		}
		out = append(out, it)
	}
	return out, nil
}

// giftKeepsOld: món cũ đứng nguyên chỗ đầu danh sách, cùng id, tên và số suất;
// chỉ đổi được icon, ảnh và thêm món mới vào cuối.
func giftKeepsOld(old, items []ContractGiftItem) bool {
	if len(items) < len(old) {
		return false
	}
	for i, o := range old {
		if items[i].ID != o.ID || items[i].Name != o.Name || items[i].Slots != o.Slots {
			return false
		}
	}
	return true
}

// giftKnownIDs: id gửi lên phải là id món cũ; món mới gửi id rỗng.
func giftKnownIDs(old, sent []ContractGiftItem) bool {
	for _, it := range sent {
		if it.ID != "" && !slices.ContainsFunc(old, func(o ContractGiftItem) bool { return o.ID == it.ID }) {
			return false
		}
	}
	return true
}

// othersJoined: kèo đã có người tham gia ngoài chủ kèo.
func othersJoined(contract map[string]any) bool {
	creator := stringValue(contract["creatorUid"])
	parts, _ := contract["participants"].(map[string]any)
	for uid := range parts {
		if uid != creator {
			return true
		}
	}
	return false
}

type ContractGiftService struct {
	db    *firestore.Client
	links *TelegramLinkService
}

func NewContractGiftService(db *firestore.Client, links *TelegramLinkService) *ContractGiftService {
	return &ContractGiftService{db: db, links: links}
}

// Set ghi quà của kèo. Chưa ai tham gia thì sửa tự do, gửi rỗng là bỏ quà;
// có người rồi thì chỉ thêm; kèo hết hạn hay đã chốt thì khoá.
func (s *ContractGiftService) Set(ctx context.Context, uid, contractID string, in ContractGiftInput, now time.Time) error {
	if in.Kind != contractGiftDraw && in.Kind != contractGiftRank {
		return errContractGiftInvalid
	}
	// Chỉ chép tên: username Telegram của chủ kèo không nằm trên doc ai cũng
	// đọc, người trúng lấy qua Contact.
	name, ok, err := profileGiver(ctx, s.db, uid)
	if err != nil {
		return err
	}
	if !ok {
		return errContractGiftProfile
	}
	contractRef := s.db.Collection("runContracts").Doc(contractID)
	ref := s.db.Collection("contractGifts").Doc(contractID)
	var items []ContractGiftItem
	err = s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := getOptional(tx, contractRef)
		if err != nil {
			return err
		}
		if !snap.Exists() {
			return errContractNotFound
		}
		c := snap.Data()
		if stringValue(c["creatorUid"]) != uid {
			return errContractGiftOwner
		}
		if stringValue(c["visibility"]) != "club" || stringValue(c["metric"]) == "route_completion" {
			return errContractGiftKind
		}
		if stringValue(c["status"]) != "active" || contractPeriodEnded(c, now) {
			return errContractGiftLocked
		}
		// Kiểm món sau khi biết là chủ kèo, để người lạ nhận not_creator chứ
		// không phải lỗi về ảnh nằm sai thư mục.
		if items, err = normalizeContractGiftItems(uid, contractID, in.Items); err != nil {
			return err
		}
		old, err := getOptional(tx, ref)
		if err != nil {
			return err
		}
		var oldItems []ContractGiftItem
		oldKind := ""
		if old.Exists() {
			oldItems = contractGiftItemsFrom(old.Data()["items"])
			oldKind = stringValue(old.Data()["kind"])
		}
		if !giftKnownIDs(oldItems, in.Items) {
			return errContractGiftInvalid
		}
		if othersJoined(c) && old.Exists() && (in.Kind != oldKind || !giftKeepsOld(oldItems, items)) {
			return errContractGiftShrink
		}
		if len(items) == 0 {
			if !old.Exists() {
				return nil
			}
			return tx.Delete(ref)
		}
		data := map[string]any{
			"contractId": contractID, "creatorUid": uid, "kind": in.Kind,
			"giverName": name,
			"items":     contractGiftItemsData(items), "updatedAt": now,
		}
		if !old.Exists() {
			data["createdAt"] = now
		}
		return tx.Set(ref, data, firestore.MergeAll)
	})
	if err != nil {
		return err
	}
	slog.InfoContext(ctx, "contract_gift.set", "uid", uid, "contract", contractID, "kind", in.Kind, "items", len(items))
	return nil
}

// giftEntrant là một người đạt mục tiêu, có phần trong quà kèo.
type giftEntrant struct {
	UID       string
	Progress  float64
	ReachedAt time.Time
	JoinedAt  time.Time
}

// giftWinner: người được món ItemID ở suất Slot (0 là suất đầu). Rank là hạng
// trong số người đạt, chỉ có ở kiểu rank.
type giftWinner struct {
	Slot   int
	ItemID string
	UID    string
	Rank   int
}

// resolveContractGifts chia suất cho người đạt. shuffle trộn danh sách khi phải
// bốc thăm; test truyền hàm cố định.
func resolveContractGifts(kind string, items []ContractGiftItem, entrants []giftEntrant, shuffle func([]giftEntrant)) []giftWinner {
	var slots []string
	for _, it := range items {
		for range it.Slots {
			slots = append(slots, it.ID)
		}
	}
	es := slices.Clone(entrants)
	earlier := func(a, b giftEntrant) bool {
		if !a.ReachedAt.Equal(b.ReachedAt) {
			return a.ReachedAt.Before(b.ReachedAt)
		}
		if !a.JoinedAt.Equal(b.JoinedAt) {
			return a.JoinedAt.Before(b.JoinedAt)
		}
		return a.UID < b.UID
	}
	if kind == contractGiftRank {
		sort.SliceStable(es, func(i, j int) bool {
			if es[i].Progress != es[j].Progress {
				return es[i].Progress > es[j].Progress
			}
			return earlier(es[i], es[j])
		})
	} else {
		sort.SliceStable(es, func(i, j int) bool { return earlier(es[i], es[j]) })
		if len(es) > len(slots) {
			shuffle(es)
		}
	}
	var out []giftWinner
	for i, itemID := range slots {
		if i >= len(es) {
			break
		}
		w := giftWinner{Slot: i, ItemID: itemID, UID: es[i].UID}
		if kind == contractGiftRank {
			w.Rank = i + 1
		}
		out = append(out, w)
	}
	return out
}

// cryptoShuffle trộn bằng crypto/rand để không ai đoán trước được thứ tự.
func cryptoShuffle(es []giftEntrant) {
	for i := len(es) - 1; i > 0; i-- {
		n, _ := rand.Int(rand.Reader, big.NewInt(int64(i+1))) // crypto/rand không trả lỗi từ Go 1.24
		j := int(n.Int64())
		es[i], es[j] = es[j], es[i]
	}
}

// giftEntrantsOf: người tham gia (trừ chủ kèo) đạt mục tiêu theo số recalc vừa
// tính cho kèo này.
func giftEntrantsOf(contractID string, contract map[string]any, recalced []ContractRecalcResult) []giftEntrant {
	creator := stringValue(contract["creatorUid"])
	parts, _ := contract["participants"].(map[string]any)
	var out []giftEntrant
	for _, r := range recalced {
		if r.ContractID != contractID || r.UID == creator || r.ReachedAt == nil {
			continue
		}
		p, _ := parts[r.UID].(map[string]any)
		joined, _ := p["joinedAt"].(time.Time)
		out = append(out, giftEntrant{UID: r.UID, Progress: r.NewProgress, ReachedAt: *r.ReachedAt, JoinedAt: joined})
	}
	return out
}

// giftResultUpdates là các field ghi vào contractGifts lúc chốt kèo.
func giftResultUpdates(kind string, items []ContractGiftItem, entrants []giftEntrant, now time.Time) []firestore.Update {
	winners := resolveContractGifts(kind, items, entrants, cryptoShuffle)
	ws := make([]any, 0, len(winners))
	for _, w := range winners {
		m := map[string]any{"slot": w.Slot, "itemId": w.ItemID, "uid": w.UID, "givenAt": nil, "receivedAt": nil}
		if kind == contractGiftRank {
			m["rank"] = w.Rank
		}
		ws = append(ws, m)
	}
	uids := make([]any, 0, len(entrants))
	for _, e := range entrants {
		uids = append(uids, e.UID)
	}
	out := []firestore.Update{
		{Path: "resolvedAt", Value: now},
		{Path: "entrants", Value: uids},
		{Path: "winners", Value: ws},
	}
	if len(uids) > 0 {
		// SendContractGiftResults hẹn push rồi gỡ cờ; hẹn lỗi thì lượt sau hẹn lại.
		out = append(out, firestore.Update{Path: "resultPushPending", Value: true})
	}
	return out
}

// SetGiven: chủ kèo đánh dấu đã trao hay bỏ đánh dấu cho một người trúng. Bỏ
// được khi quà chưa tính là nhận (rewardReceived).
// marked báo lần gọi này vừa ghi givenAt, để chỗ gọi báo người trúng một lần.
func (s *ContractGiftService) SetGiven(ctx context.Context, by, contractID, uid string, given bool, now time.Time) (marked bool, err error) {
	err = s.updateWinner(ctx, contractID, uid, func(gift map[string]any, w map[string]any) error {
		marked = false
		if stringValue(gift["creatorUid"]) != by {
			return errContractGiftOwner
		}
		if w == nil {
			return errContractGiftWinner
		}
		if !given {
			if rewardReceived(w, now) {
				return errContractGiftDone
			}
			w["givenAt"] = nil
			return nil
		}
		if w["givenAt"] == nil {
			w["givenAt"] = now
			marked = true
		}
		return nil
	})
	if err != nil {
		return false, err
	}
	slog.InfoContext(ctx, "contract_gift.given", "by", by, "contract", contractID, "uid", uid, "given", given)
	return marked, nil
}

// MarkReceived: người trúng báo đã nhận. Chưa ai bấm đã trao thì ghi luôn
// givenAt, vì quà đã tới tay thì chắc chắn đã trao.
func (s *ContractGiftService) MarkReceived(ctx context.Context, uid, contractID string, now time.Time) error {
	err := s.updateWinner(ctx, contractID, uid, func(_ map[string]any, w map[string]any) error {
		if w == nil {
			return errContractGiftNone
		}
		if w["receivedAt"] != nil {
			return nil
		}
		w["receivedAt"] = now
		if w["givenAt"] == nil {
			w["givenAt"] = now
		}
		return nil
	})
	if err != nil {
		return err
	}
	slog.InfoContext(ctx, "contract_gift.received", "contract", contractID, "uid", uid)
	return nil
}

// updateWinner đọc winners, cho change sửa dòng của uid rồi ghi lại cả mảng
// trong một transaction. uid không trúng thì change nhận winner nil và phải trả
// lỗi, để chỗ gọi chọn câu báo đúng người hỏi.
func (s *ContractGiftService) updateWinner(ctx context.Context, contractID, uid string, change func(gift, winner map[string]any) error) error {
	ref := s.db.Collection("contractGifts").Doc(contractID)
	return s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		snap, err := getOptional(tx, ref)
		if err != nil {
			return err
		}
		if !snap.Exists() {
			return errContractGiftNone
		}
		gift := snap.Data()
		winners := anyList(gift["winners"])
		i := slices.IndexFunc(winners, func(v any) bool {
			m, _ := v.(map[string]any)
			return stringValue(m["uid"]) == uid
		})
		if i < 0 {
			if err := change(gift, nil); err != nil {
				return err
			}
			return errContractGiftNone
		}
		w, _ := winners[i].(map[string]any)
		if err := change(gift, w); err != nil {
			return err
		}
		winners[i] = w
		return tx.Update(ref, []firestore.Update{{Path: "winners", Value: winners}})
	})
}

// Contact: username Telegram của người trao, chỉ cho người trúng quà. Đọc lúc
// hỏi chứ không chép vào doc quà, vì doc đó mọi thành viên đều đọc được. Rỗng
// khi người trao chưa liên kết Telegram.
func (s *ContractGiftService) Contact(ctx context.Context, uid, contractID string) (string, error) {
	gift, err := getData(ctx, s.db.Collection("contractGifts").Doc(contractID))
	if err != nil {
		return "", err
	}
	if gift == nil || !slices.ContainsFunc(anyList(gift["winners"]), func(v any) bool {
		m, _ := v.(map[string]any)
		return stringValue(m["uid"]) == uid
	}) {
		return "", errContractGiftNone
	}
	return giverTelegram(ctx, s.links, stringValue(gift["creatorUid"]))
}

// contractGiftAnnounceLine là dòng quà trong tin mở kèo lên nhóm, rỗng khi kèo
// không có quà. App gọi announce-new sau khi lưu quà nên tin có luôn dòng này.
func contractGiftAnnounceLine(gift map[string]any) string {
	items := contractGiftItemsFrom(gift["items"])
	if len(items) == 0 {
		return ""
	}
	names := make([]string, 0, len(items))
	for _, it := range items {
		n := it.Name
		if it.Slots > 1 {
			n += fmt.Sprintf(" ×%d", it.Slots)
		}
		names = append(names, n)
	}
	how := "bốc thăm trong số người đạt"
	if stringValue(gift["kind"]) == contractGiftRank {
		how = "theo hạng trong số người đạt"
	}
	return "🎁 Quà " + strings.Join(names, ", ") + ": " + how + ".\n"
}

type contractGiftPushTask struct {
	ContractID string   `json:"contractId"`
	Event      string   `json:"event"` // "ticket" | "result"
	UIDs       []string `json:"uids,omitempty"`
}

// NotifyContractTickets báo "có vé bốc thăm" cho người lần đầu đạt mục tiêu của
// kèo có quà bốc thăm, theo kết quả recalc vừa chạy. Mỗi người một lần: đánh
// dấu ticketNotified sau khi hẹn push. Hẹn trùng do chạy lại thì TaskID cố định
// chặn trong cửa sổ dedup của Cloud Tasks.
func NotifyContractTickets(ctx context.Context, db *firestore.Client, enqueue taskPublishFunc, recalced []ContractRecalcResult, dryRun bool) error {
	if dryRun || enqueue == nil {
		return nil
	}
	reached := map[string][]string{}
	for _, r := range recalced {
		if r.ReachedAt != nil {
			reached[r.ContractID] = append(reached[r.ContractID], r.UID)
		}
	}
	for contractID, uids := range reached {
		ref := db.Collection("contractGifts").Doc(contractID)
		gift, err := getData(ctx, ref)
		if err != nil {
			return err
		}
		if gift == nil || stringValue(gift["kind"]) != contractGiftDraw || gift["resolvedAt"] != nil {
			continue
		}
		notified, _ := gift["ticketNotified"].(map[string]any)
		var fresh []string
		for _, uid := range uids {
			if uid != stringValue(gift["creatorUid"]) && notified[uid] == nil {
				fresh = append(fresh, uid)
			}
		}
		if len(fresh) == 0 {
			continue
		}
		sort.Strings(fresh)
		task := PublishTask{Queue: QueueNotify, HandlerPath: contractGiftPushPath, Payload: contractGiftPushTask{ContractID: contractID, Event: "ticket", UIDs: fresh}, TaskID: StableTaskID("contract-ticket", contractID+":"+strings.Join(fresh, ","))}
		if _, err := enqueue(ctx, task); err != nil {
			return err
		}
		updates := make([]firestore.Update, 0, len(fresh))
		for _, uid := range fresh {
			updates = append(updates, firestore.Update{FieldPath: firestore.FieldPath{"ticketNotified", uid}, Value: firestore.ServerTimestamp})
		}
		if _, err := ref.Update(ctx, updates); err != nil {
			return err
		}
	}
	return nil
}

// SendContractGiftResults hẹn push "có kết quả quà" cho các kèo vừa chia quà
// (resultPushPending), rồi gỡ cờ. Lỗi thì trả ra: cờ còn nên lượt sau hẹn lại,
// TaskID cố định chặn hẹn trùng trong cửa sổ dedup của Cloud Tasks.
func SendContractGiftResults(ctx context.Context, db *firestore.Client, enqueue taskPublishFunc, dryRun bool) error {
	if dryRun || enqueue == nil {
		return nil
	}
	docs, err := db.Collection("contractGifts").Where("resultPushPending", "==", true).Documents(ctx).GetAll()
	if err != nil {
		return err
	}
	for _, doc := range docs {
		task := PublishTask{Queue: QueueNotify, HandlerPath: contractGiftPushPath, Payload: contractGiftPushTask{ContractID: doc.Ref.ID, Event: "result"}, TaskID: StableTaskID("contract-gift-result", doc.Ref.ID)}
		if _, err := enqueue(ctx, task); err != nil {
			return err
		}
		if _, err := doc.Ref.Update(ctx, []firestore.Update{{Path: "resultPushPending", Value: firestore.Delete}}); err != nil {
			return err
		}
	}
	return nil
}

// DeliverContractGiftPush gửi push quà kèo: "ticket" cho người vừa có vé,
// "result" cho mọi người đạt khi kèo đã chốt quà.
func DeliverContractGiftPush(ctx context.Context, db *firestore.Client, push *PushService, task contractGiftPushTask) error {
	off, err := pushKindOff(ctx, db, contractGiftPushKind)
	if err != nil || off {
		return err
	}
	contract, err := getData(ctx, db.Collection("runContracts").Doc(task.ContractID))
	if err != nil || contract == nil {
		return err
	}
	title := strings.TrimSpace(stringValue(contract["title"]))
	if title == "" {
		title = "Kèo"
	}
	data := map[string]string{"kind": contractGiftPushKind, "contractId": task.ContractID}
	if task.Event == "ticket" {
		return push.Send(ctx, task.UIDs, pushNote{Title: "Bạn có vé bốc thăm", Body: title + ": giữ vững tới lúc chốt kèo.", Data: data})
	}
	gift, err := getData(ctx, db.Collection("contractGifts").Doc(task.ContractID))
	if err != nil || gift == nil {
		return err
	}
	var uids []string
	for _, v := range anyList(gift["entrants"]) {
		uids = append(uids, stringValue(v))
	}
	if len(uids) == 0 {
		return nil
	}
	body := "Mở kèo để xem ai nhận quà."
	if stringValue(gift["kind"]) == contractGiftDraw {
		body = "Đã bốc thăm. Mở kèo để xem ai trúng."
	}
	return push.Send(ctx, uids, pushNote{Title: title + " có kết quả quà", Body: body, Data: data})
}

func (s *Server) contractGiftPush(w http.ResponseWriter, r *http.Request) error {
	var task contractGiftPushTask
	if decodeJSON(r, &task) != nil || task.ContractID == "" || s.deps.Push == nil {
		w.WriteHeader(204)
		return nil
	}
	if err := DeliverContractGiftPush(r.Context(), s.deps.Firestore, s.deps.Push, task); err != nil {
		return err
	}
	return writeJSON(w, 200, map[string]any{"ok": true})
}

func (s *Server) contractGiftRoutes() {
	s.route("PUT /v1/contracts/{contractId}/gifts", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		var body ContractGiftInput
		if decodeJSON(r, &body) != nil {
			return invalidRequest()
		}
		if err := s.deps.ContractGifts.Set(r.Context(), uid, r.PathValue("contractId"), body, s.now()); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	}))
	for method, given := range map[string]bool{"POST": true, "DELETE": false} {
		s.route(method+" /v1/contracts/{contractId}/gifts/winners/{uid}/given", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
			now := s.now()
			marked, err := s.deps.ContractGifts.SetGiven(r.Context(), uid, r.PathValue("contractId"), r.PathValue("uid"), given, now)
			if err != nil {
				return err
			}
			if marked {
				s.notifyGiftGiven(r.Context(), giftGivenTask(giftFromContract, r.PathValue("contractId"), r.PathValue("uid"), now))
			}
			return writeJSON(w, 200, map[string]any{"ok": true})
		}))
	}
	s.route("GET /v1/contracts/{contractId}/gifts/contact", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		tg, err := s.deps.ContractGifts.Contact(r.Context(), uid, r.PathValue("contractId"))
		if err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"giverTg": tg})
	}))
	s.route("POST /v1/contracts/{contractId}/gifts/received", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		if err := s.deps.ContractGifts.MarkReceived(r.Context(), uid, r.PathValue("contractId"), s.now()); err != nil {
			return err
		}
		return writeJSON(w, 200, map[string]any{"ok": true})
	}))
}
