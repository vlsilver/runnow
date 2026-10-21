package backend

import (
	"context"
	"fmt"
	"slices"
	"strings"
	"time"
	"unicode/utf8"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// Phòng bot: một phòng chung cho mọi thành viên thử nghiệm và bot của họ.
// Người gửi tin qua api; bot nói theo lượt do task agent-turn chạy trên bot
// service (agent_core.go). Doc phòng giữ seq và state lượt nói:
//
//	seq         seq của tin mới nhất
//	chain       số tin bot liên tiếp kể từ tin người gần nhất
//	lastSpeaker chủ của bot vừa nói, rỗng nếu tin cuối là của người
//	lastSpoke   uid chủ bot → seq lần cuối bot đó nói
//	turnOf      seq mà lượt bot gần nhất trả lời, để task chạy lại biết đã ghi
//	day, dayCount  ngân sách tin bot trong ngày (giờ VN)

type AgentRoomMessage struct {
	Seq  int64  `json:"seq"`
	Kind string `json:"kind"` // human | agent
	// UID là người gửi; tin của bot thì là uid chủ bot.
	UID  string `json:"uid"`
	Name string `json:"name"`
	// Owner: tên chủ bot, chỉ có ở tin của bot.
	Owner string    `json:"owner,omitempty"`
	Text  string    `json:"text"`
	At    time.Time `json:"at"`
	// Hidden: người xem đã chặn người gửi (tin của bot thì là chủ bot); Text rỗng,
	// app không vẽ tin này. Vẫn trả tin chứ không bỏ, để seq của app đi tiếp:
	// app poll bằng after = seq lớn nhất đang có, bỏ tin thì poll mãi một chỗ.
	Hidden bool `json:"hidden,omitempty"`
}

type AgentRoomMember struct {
	UID     string `json:"uid"`
	Name    string `json:"name"`
	BotName string `json:"botName,omitempty"` // rỗng khi người này chưa tạo bot
}

type AgentRoomPage struct {
	Messages []AgentRoomMessage `json:"messages"`
	Members  []AgentRoomMember  `json:"members"`
	Cursor   string             `json:"cursor,omitempty"`
	HasNewer bool               `json:"hasNewer"`
}

// roomAgent là một bot trong phòng: chủ, tên, persona.
type roomAgent struct {
	uid, name, persona string
}

// agentRoomMax là số bot tối đa được đọc vào một lượt nói khi đã mở cho mọi
// người, để số lần đọc hồ sơ bot mỗi lượt không tăng theo số người dùng.
const agentRoomMax = 20

// roomAgents là bot được nói trong phòng, theo thứ tự uid: bot đã tạo, đang
// inRoom, và chủ có quyền dùng bot.
//   - Cờ open tắt: chỉ đọc bot của allowlist như trước giờ. Nhờ vậy tắt cờ thì
//     bot của người ngoài allowlist im ngay, dù vẫn còn inRoom. Bot chưa có
//     field inRoom (tạo trước khi có field) vẫn tính là ở phòng, để deploy bản
//     này không phụ thuộc việc đã chạy backfill hay chưa.
//   - Cờ open bật: query theo inRoom, tối đa agentRoomMax bot. Bot của prefer
//     (người vừa nhắn) luôn có mặt nếu đang ở phòng, để người đó không bị cắt
//     chỉ vì uid đứng sau 20 bot đầu.
func (s *AgentStore) roomAgents(ctx context.Context, acc agentAccess, prefer string) ([]roomAgent, error) {
	var docs []*firestore.DocumentSnapshot
	if !acc.open {
		if len(acc.members) == 0 {
			return nil, nil
		}
		refs := make([]*firestore.DocumentRef, len(acc.members))
		for i, uid := range acc.members {
			refs[i] = s.agentRef(uid)
		}
		all, err := s.db.GetAll(ctx, refs)
		if err != nil {
			return nil, err
		}
		for _, d := range all {
			if d.Exists() {
				docs = append(docs, d)
			}
		}
	} else {
		var err error
		docs, err = s.db.Collection("agents").Where("inRoom", "==", true).Limit(agentRoomMax).Documents(ctx).GetAll()
		if err != nil {
			return nil, err
		}
		if prefer != "" && len(docs) == agentRoomMax && !slices.ContainsFunc(docs, func(d *firestore.DocumentSnapshot) bool { return d.Ref.ID == prefer }) {
			d, err := s.agentRef(prefer).Get(ctx)
			switch {
			case status.Code(err) == codes.NotFound:
			case err != nil:
				return nil, err
			case d.Data()["inRoom"] == true:
				docs = append(docs[:agentRoomMax-1], d)
			}
		}
	}
	var out []roomAgent
	for _, d := range docs {
		if inRoom, ok := d.Data()["inRoom"]; !ok || inRoom == true {
			out = append(out, roomAgent{uid: d.Ref.ID, name: stringValue(d.Data()["name"]), persona: stringValue(d.Data()["persona"])})
		}
	}
	slices.SortFunc(out, func(a, b roomAgent) int { return strings.Compare(a.uid, b.uid) })
	return out, nil
}

// BackfillInRoom cho bot đã tạo của allowlist hiện tại vào phòng (inRoom =
// true). Phải chạy trước khi bật cờ open: lúc đó phòng query theo inRoom ==
// true, bot chưa có field sẽ im. Cờ còn tắt thì chưa cần. Chạy lại an toàn: bot
// đã có inRoom, kể cả false do chủ tự tắt, thì để nguyên. Trả uid vừa được ghi.
func (s *AgentStore) BackfillInRoom(ctx context.Context) ([]string, error) {
	acc, err := s.access(ctx)
	if err != nil {
		return nil, err
	}
	var set []string
	for _, uid := range acc.members {
		ref := s.agentRef(uid)
		wrote := false
		err := s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
			wrote = false
			doc, err := tx.Get(ref)
			if status.Code(err) == codes.NotFound {
				return nil // chưa tạo bot
			}
			if err != nil {
				return err
			}
			if _, ok := doc.Data()["inRoom"]; ok {
				return nil
			}
			wrote = true
			return tx.Update(ref, []firestore.Update{{Path: "inRoom", Value: true}})
		})
		if err != nil {
			return set, fmt.Errorf("agents/%s: %w", uid, err)
		}
		if wrote {
			set = append(set, uid)
		}
	}
	return set, nil
}

// roster là người trong phòng, theo thứ tự uid. Cờ open tắt thì là allowlist
// như trước giờ, kể cả người chưa tạo bot. Cờ bật thì là chủ của các bot đang
// ở phòng, để danh sách không dài theo số người dùng.
func (a agentAccess) roster(agents []roomAgent) []string {
	if !a.open {
		return a.members
	}
	out := make([]string, len(agents))
	for i, ag := range agents {
		out[i] = ag.uid
	}
	return out
}

func (s *AgentStore) Room(ctx context.Context, uid, cursor, after string) (AgentRoomPage, error) {
	acc, err := s.access(ctx)
	if err != nil {
		return AgentRoomPage{}, err
	}
	if !acc.allows(uid) {
		return AgentRoomPage{}, errAgentDisabled
	}
	docs, next, hasNewer, err := pageBySeq(ctx, s.roomRef(agentMainRoom).Collection("messages"), cursor, after)
	if err != nil {
		return AgentRoomPage{}, err
	}
	out := AgentRoomPage{Messages: make([]AgentRoomMessage, 0, len(docs)), Members: []AgentRoomMember{}, Cursor: next, HasNewer: hasNewer}
	// Poll không có tin mới thì khỏi đọc tên và danh sách bot.
	if after != "" && len(docs) == 0 {
		return out, nil
	}
	agents, err := s.roomAgents(ctx, acc, uid)
	if err != nil {
		return AgentRoomPage{}, err
	}
	members := acc.roster(agents)
	uids := slices.Clone(members)
	for _, d := range docs {
		if u := stringValue(d.Data()["uid"]); !slices.Contains(uids, u) {
			uids = append(uids, u) // người đã rời danh sách vẫn hiện tên
		}
	}
	names, err := s.displayNames(ctx, uids)
	if err != nil {
		return AgentRoomPage{}, err
	}
	blocked, err := s.blockedUIDs(ctx, uid)
	if err != nil {
		return AgentRoomPage{}, err
	}
	bots := map[string]string{}
	for _, a := range agents {
		bots[a.uid] = a.name
	}
	for _, m := range members {
		out.Members = append(out.Members, AgentRoomMember{UID: m, Name: names[m], BotName: bots[m]})
	}
	for _, d := range docs {
		m := d.Data()
		msg := AgentRoomMessage{Seq: int64(number(m["seq"])), Kind: stringValue(m["kind"]), UID: stringValue(m["uid"]), Text: stringValue(m["text"]), At: timeValue(m["at"])}
		msg.Name = names[msg.UID]
		if msg.Kind == agentKindAgent {
			// Tên bot chụp lúc nói, đúng với tên mà các bot khác đã đọc.
			msg.Owner, msg.Name = msg.Name, stringValue(m["name"])
		}
		if slices.Contains(blocked, msg.UID) {
			msg.Hidden, msg.Text = true, ""
		}
		out.Messages = append(out.Messages, msg)
	}
	return out, nil
}

// PostRoom ghi tin của người vào phòng và trả seq. Tin người reset chuỗi bot,
// nên sau mỗi tin người các bot lại được nói tối đa agentChainMax tin.
func (s *AgentStore) PostRoom(ctx context.Context, uid, text string, wall time.Time) (int64, error) {
	text = strings.TrimSpace(text)
	if text == "" || utf8.RuneCountInString(text) > agentTextMaxRunes {
		return 0, errAgentText
	}
	text = maskProfanity(text)
	if err := s.requireConsent(ctx, uid); err != nil {
		return 0, err
	}
	ref := s.roomRef(agentMainRoom)
	var seq int64
	err := s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		room, err := readRoom(tx, ref)
		if err != nil {
			return err
		}
		if last := timeValue(nested(room, "lastSentAt", uid)); !last.IsZero() && wall.Sub(last) < agentMinGap {
			return errAgentTooFast
		}
		seq = int64(number(room["seq"])) + 1
		if err := tx.Create(ref.Collection("messages").Doc(seqDocID(seq)), map[string]any{"seq": seq, "kind": agentKindHuman, "uid": uid, "text": text, "channel": agentChannelApp, "at": wall}); err != nil {
			return err
		}
		return tx.Set(ref, map[string]any{"seq": seq, "chain": 0, "lastSpeaker": "", "lastSentAt": map[string]any{uid: wall}, "updatedAt": wall}, firestore.MergeAll)
	})
	return seq, err
}

func readRoom(tx *firestore.Transaction, ref *firestore.DocumentRef) (map[string]any, error) {
	doc, err := tx.Get(ref)
	if status.Code(err) == codes.NotFound {
		return map[string]any{}, nil
	}
	if err != nil {
		return nil, err
	}
	return doc.Data(), nil
}

// roomTranscript là tối đa limit tin gần nhất tới seq upTo, cũ trước.
func (s *AgentStore) roomTranscript(ctx context.Context, upTo int64, limit int) ([]map[string]any, error) {
	docs, err := s.roomRef(agentMainRoom).Collection("messages").Where("seq", "<=", upTo).OrderBy("seq", firestore.Desc).Limit(limit).Documents(ctx).GetAll()
	if err != nil {
		return nil, err
	}
	out := make([]map[string]any, len(docs))
	for i, d := range docs {
		out[len(docs)-1-i] = d.Data()
	}
	return out, nil
}
