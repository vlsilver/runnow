package backend

import (
	"reflect"
	"strings"
	"testing"
	"time"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// summaryPlay chạy ván qua engine thật và ghi lại từng bước như events/{seq}:
// phaseKey trước bước, mọi event (kể cả riêng), inputs. Km chỉ có ở hai mốc
// chốt km (setup, trial), như readInputs.
type summaryPlay struct {
	t     *testing.T
	st    *ww.State
	km    map[string]float64
	steps []summaryStep
}

func newSummaryPlay(t *testing.T, cfg ww.Config, roles map[string]ww.Role, km map[string]float64) *summaryPlay {
	return &summaryPlay{t: t, st: ww.NewState(ww.Seed{1}, cfg, roles, msgStart), km: km}
}

func (p *summaryPlay) step(acts ...ww.Action) {
	p.t.Helper()
	in := ww.Inputs{Actions: acts}
	if p.st.Phase == ww.PhaseSetup || p.st.Phase == ww.PhaseTrial {
		in.Km = p.km
	}
	next, evs, err := ww.Step(p.st, in)
	if err != nil {
		p.t.Fatal(err)
	}
	p.steps = append(p.steps, summaryStep{PhaseKey: p.st.PhaseKey(), Events: evs, Inputs: in})
	p.st = next
}

func (p *summaryPlay) vote(actor, choice string) ww.Action {
	return ww.Action{Kind: ww.KindVote, Actor: actor, Choice: choice, ReceivedAt: p.st.NightAt.Add(23 * time.Hour)}
}

func (p *summaryPlay) summary() GameSummary {
	p.t.Helper()
	if p.st.Phase != ww.PhaseEnded {
		p.t.Fatalf("ván chưa kết thúc: %s", p.st.PhaseKey())
	}
	return buildSummary(p.st, p.steps, strings.ToUpper, map[string]string{"wolf": "https://img/wolf.png"})
}

// Ván 4 người: đêm 1 sói cắn V1, ngày 1 làng treo nhầm V3, còn 1 sói 1 dân nên
// sói thắng. Lật bài: phe thắng đứng trước, mỗi người kèm lúc chết.
func TestSummaryTeamsShowRoleAndFate(t *testing.T) {
	roles := map[string]ww.Role{"w1": ww.Wolf, "v1": ww.Villager, "v2": ww.Villager, "v3": ww.Villager}
	p := newSummaryPlay(t, ww.Config{}, roles, map[string]float64{"w1": 5000, "v1": 5000, "v2": 5000, "v3": 5000})
	p.step()
	p.step(act1(ww.KindWolfBite, "w1", "v1"))
	p.step()
	p.step(act1(ww.KindNominate, "v2", "v3"), act1(ww.KindNominate, "w1", "v3"))
	p.step(p.vote("v2", ww.ChoiceHang), p.vote("w1", ww.ChoiceHang))

	s := p.summary()
	if s.Winner != "wolves" || s.WinnerLabel != "Phe Sói thắng" {
		t.Fatalf("winner = %q %q", s.Winner, s.WinnerLabel)
	}
	want := []GameSummaryTeam{
		{Team: "wolves", Label: "Phe Sói", Won: true, Players: []GameSummaryPlayer{
			{UID: "w1", Name: "W1", Role: "wolf", RoleLabel: "Sói", CardURL: "https://img/wolf.png", Alive: true, Fate: "Sống"},
		}},
		{Team: "village", Label: "Phe Dân", Players: []GameSummaryPlayer{
			{UID: "v1", Name: "V1", Role: "villager", RoleLabel: "Dân", Fate: "Đêm 1", CauseLabel: "Bị sói cắn"},
			{UID: "v2", Name: "V2", Role: "villager", RoleLabel: "Dân", Alive: true, Fate: "Sống"},
			{UID: "v3", Name: "V3", Role: "villager", RoleLabel: "Dân", Fate: "Ngày 1", CauseLabel: "Bị treo"},
		}},
	}
	for i := range s.Teams {
		for j := range s.Teams[i].Players {
			s.Teams[i].Players[j].Km = "" // km xét ở test riêng
		}
	}
	if !reflect.DeepEqual(s.Teams, want) {
		t.Fatalf("teams = %+v\nmong đợi %+v", s.Teams, want)
	}
}

// Diễn lại có cả lựa chọn ban đêm, chia theo đêm/ngày. Ván tắt km: phiếu nào cũng
// tính. Đêm 1 sói cắn V1, bảo vệ đỡ đúng V1, tiên tri soi ra W1; ngày 1 làng
// treo W1 với 5 Treo (phiếu Tha của chính W1 không tính, người lên giàn không
// bỏ phiếu phiên mình), dân thắng.
func TestSummaryReplayShowsNightActions(t *testing.T) {
	roles := map[string]ww.Role{"w1": ww.Wolf, "seer": ww.Seer, "guard": ww.Guard, "witch": ww.Witch, "v1": ww.Villager, "v2": ww.Villager}
	p := newSummaryPlay(t, ww.Config{KmOff: true}, roles, nil)
	p.step()
	p.step(act1(ww.KindWolfBite, "w1", "v1"))
	p.step(act1(ww.KindGuard, "guard", "v1"), act1(ww.KindSeerPeek, "seer", "w1"))
	p.step(act1(ww.KindNominate, "v1", "w1"), act1(ww.KindNominate, "v2", "w1"))
	p.step(p.vote("v1", ww.ChoiceHang), p.vote("v2", ww.ChoiceHang), p.vote("seer", ww.ChoiceHang),
		p.vote("guard", ww.ChoiceHang), p.vote("witch", ww.ChoiceHang), p.vote("w1", ww.ChoiceSpare))

	want := []GameSummarySection{
		{Title: "Đêm 1", Round: 1, Night: true, Lines: []GameSummaryLine{
			{Icon: "bite", Text: "Sói cắn V1."},
			{Icon: "guard", Text: "Bảo vệ GUARD canh V1.", Tag: "CỨU"},
			{Icon: "seer", Text: "Tiên tri SEER soi W1: Sói.", Tag: "SÓI"},
		}},
		{Title: "Ngày 1", Round: 1, Lines: []GameSummaryLine{
			{Icon: "nominee", Text: "W1 lên giàn với 2 đề cử.", Tag: "GIÀN"},
			{Icon: "vote", Text: "Treo 5, Tha 0: W1 bị treo.", Tag: "TREO", Hang: 5, Spare: 0},
			{Icon: "death", Text: "W1 chết: bị treo. Lá bài: Sói."},
			{Icon: "winner", Text: "Phe Dân thắng."},
		}},
	}
	s := p.summary()
	if !reflect.DeepEqual(s.Replay, want) {
		t.Fatalf("replay = %+v\nmong đợi %+v", s.Replay, want)
	}
	// Ván tắt km: không có số km nào, kể cả danh hiệu chạy nhiều nhất.
	wantStats := []GameSummaryStat{{Label: "Số vòng", Value: "1"}, {Label: "Người chết", Value: "1/6"}, {Label: "Treo trúng sói", Value: "1/1"}}
	if !reflect.DeepEqual(s.Stats, wantStats) {
		t.Fatalf("stats = %+v", s.Stats)
	}
	if len(s.Titles) != 2 || s.Titles[0].Key != "seer" || s.Titles[1].Key != "guard" {
		t.Fatalf("titles = %+v", s.Titles)
	}
	for _, team := range s.Teams {
		for _, pl := range team.Players {
			if pl.Km != "" {
				t.Fatalf("%s có km %q", pl.UID, pl.Km)
			}
		}
	}
}

// Thợ săn bị treo ngày 1 rồi bắn sói: lượt bắn mang phaseKey r2/night/hunter
// nhưng xảy ra tối ngày 1, nên nằm trong Ngày 1 và W1 chết "Ngày 1". Đêm 1 phù
// thuỷ cứu người bị cắn; bảo vệ 0 km nên lượt canh bị huỷ, chỉ còn câu huỷ.
func TestSummaryHunterShotAfterHangBelongsToThatDay(t *testing.T) {
	roles := map[string]ww.Role{"w1": ww.Wolf, "hunter": ww.Hunter, "witch": ww.Witch, "guard": ww.Guard, "v1": ww.Villager, "v2": ww.Villager}
	km := map[string]float64{"w1": 10000, "hunter": 10000, "witch": 10000, "guard": 0, "v1": 10000, "v2": 10000}
	p := newSummaryPlay(t, ww.Config{Vote: ww.VoteFlat}, roles, km)
	p.step()
	p.step(act1(ww.KindWolfBite, "w1", "v1"))
	p.step(act1(ww.KindGuard, "guard", "v2"), act1(ww.KindWitchSave, "witch"))
	p.step(act1(ww.KindNominate, "v1", "hunter"), act1(ww.KindNominate, "v2", "hunter"), act1(ww.KindNominate, "w1", "hunter"))
	p.step(p.vote("w1", ww.ChoiceHang), p.vote("v1", ww.ChoiceHang), p.vote("v2", ww.ChoiceHang),
		p.vote("witch", ww.ChoiceSpare), p.vote("guard", ww.ChoiceSpare))
	p.step(act1(ww.KindHunterShoot, "hunter", "w1"))

	s := p.summary()
	want := []GameSummarySection{
		{Title: "Đêm 1", Round: 1, Night: true, Lines: []GameSummaryLine{
			{Icon: "bite", Text: "Sói cắn V1."},
			{Icon: "witch", Text: "Phù thuỷ WITCH cứu V1.", Tag: "CỨU"},
			{Icon: "void", Text: "Lượt bảo vệ của GUARD bị huỷ: chưa đủ km."},
		}},
		{Title: "Ngày 1", Round: 1, Lines: []GameSummaryLine{
			{Icon: "nominee", Text: "HUNTER lên giàn với 3 đề cử.", Tag: "GIÀN"},
			{Icon: "vote", Text: "Treo 3, Tha 2: HUNTER bị treo.", Tag: "TREO", Hang: 3, Spare: 2},
			{Icon: "death", Text: "HUNTER chết: bị treo. Lá bài: Thợ săn."},
			{Icon: "hunter", Text: "HUNTER là Thợ săn, được bắn một người."},
			{Icon: "death", Text: "W1 chết: trúng đạn thợ săn. Lá bài: Sói."},
			{Icon: "winner", Text: "Phe Dân thắng."},
		}},
	}
	if !reflect.DeepEqual(s.Replay, want) {
		t.Fatalf("replay = %+v\nmong đợi %+v", s.Replay, want)
	}
	if w1 := s.Teams[1].Players[0]; w1.UID != "w1" || w1.Fate != "Ngày 1" || w1.CauseLabel != "Trúng đạn thợ săn" {
		t.Fatalf("w1 = %+v", w1)
	}
}

// Số liệu và danh hiệu. Hai khung km (mở đêm 1, chốt ngày 1) cùng số nên mỗi
// người gấp đôi: W1 6, SEER 8, GUARD 10, V1 24, V2 4, cả làng 52 km. Ván hết ở
// chốt ngày 1 (engine đã tăng Round lên 2) nhưng chỉ chơi 1 vòng.
func TestSummaryStatsAndTitles(t *testing.T) {
	roles := map[string]ww.Role{"w1": ww.Wolf, "seer": ww.Seer, "guard": ww.Guard, "v1": ww.Villager, "v2": ww.Villager}
	km := map[string]float64{"w1": 3000, "seer": 4000, "guard": 5000, "v1": 12000, "v2": 2000}
	p := newSummaryPlay(t, ww.Config{Vote: ww.VoteFlat}, roles, km)
	p.step()
	p.step(act1(ww.KindWolfBite, "w1", "v2"))
	p.step(act1(ww.KindGuard, "guard", "v2"), act1(ww.KindSeerPeek, "seer", "w1"))
	p.step(act1(ww.KindNominate, "v1", "w1"), act1(ww.KindNominate, "seer", "w1"))
	p.step(p.vote("v1", ww.ChoiceHang), p.vote("seer", ww.ChoiceHang), p.vote("guard", ww.ChoiceHang), p.vote("v2", ww.ChoiceHang))

	s := p.summary()
	wantStats := []GameSummaryStat{
		{Label: "Số vòng", Value: "1"}, {Label: "Người chết", Value: "1/5"},
		{Label: "Km cả làng", Value: "52 km"}, {Label: "Treo trúng sói", Value: "1/1"},
	}
	if !reflect.DeepEqual(s.Stats, wantStats) {
		t.Fatalf("stats = %+v", s.Stats)
	}
	if want := "Treo đủ 1 sói · còn 4 người sống"; s.Subtitle != want {
		t.Fatalf("subtitle = %q, muốn %q", s.Subtitle, want)
	}
	wantTitles := []GameSummaryTitle{
		{Key: "runner", Label: "Chạy nhiều nhất", UIDs: []string{"v1"}, Name: "V1", Value: "24 km"},
		{Key: "seer", Label: "Tiên tri tìm ra sói", UIDs: []string{"seer"}, Name: "SEER", Value: "1 sói"},
		{Key: "guard", Label: "Bảo vệ cứu người", UIDs: []string{"guard"}, Name: "GUARD", Value: "1 lần"},
	}
	if !reflect.DeepEqual(s.Titles, wantTitles) {
		t.Fatalf("titles = %+v", s.Titles)
	}
	if v1 := s.Teams[0].Players[2]; v1.UID != "v1" || v1.Km != "24 km" {
		t.Fatalf("v1 = %+v", v1)
	}
}

// Câu phụ không nói "treo" khi sói chết vì cách khác, và nói đúng phe thắng.
func TestSummarySubtitleFollowsHowTheGameEnded(t *testing.T) {
	t.Run("sói chết vì bình độc", func(t *testing.T) {
		roles := map[string]ww.Role{"w1": ww.Wolf, "witch": ww.Witch, "v1": ww.Villager, "v2": ww.Villager, "v3": ww.Villager}
		p := newSummaryPlay(t, ww.Config{Vote: ww.VoteFlat}, roles, map[string]float64{"witch": 5000})
		p.step()
		p.step()
		p.step(act1(ww.KindWitchPoison, "witch", "w1"))
		if want := "Hạ đủ 1 sói · còn 4 người sống"; p.summary().Subtitle != want {
			t.Fatalf("subtitle = %q, muốn %q", p.summary().Subtitle, want)
		}
	})
	t.Run("sói thắng", func(t *testing.T) {
		roles := map[string]ww.Role{"w1": ww.Wolf, "v1": ww.Villager, "v2": ww.Villager}
		p := newSummaryPlay(t, ww.Config{Vote: ww.VoteFlat}, roles, map[string]float64{"w1": 5000})
		p.step()
		p.step(act1(ww.KindWolfBite, "w1", "v1"))
		p.step()
		if want := "Sói áp đảo làng · còn 2 người sống"; p.summary().Subtitle != want {
			t.Fatalf("subtitle = %q, muốn %q", p.summary().Subtitle, want)
		}
	})
}

// Diễn lại nhóm được theo vòng và vẽ được thanh Treo/Tha: mỗi mục biết vòng và
// ngày của nó, câu kết quả phiếu mang đúng số phiếu engine đếm.
func TestSummaryReplayKeepsRoundDateAndVoteCount(t *testing.T) {
	roles := map[string]ww.Role{"w1": ww.Wolf, "v1": ww.Villager, "v2": ww.Villager, "v3": ww.Villager}
	p := newSummaryPlay(t, ww.Config{}, roles, map[string]float64{"w1": 5000, "v1": 5000, "v2": 5000, "v3": 5000})
	p.step()
	p.step(act1(ww.KindWolfBite, "w1", "v1"))
	p.step()
	p.step(act1(ww.KindNominate, "v2", "v3"), act1(ww.KindNominate, "w1", "v3"))
	p.step(p.vote("v2", ww.ChoiceHang), p.vote("w1", ww.ChoiceHang))
	// 23h giờ Việt Nam ngày 16 là 16h UTC: ngày phải theo giờ Việt Nam.
	for i := range p.steps {
		p.steps[i].At = time.Date(2026, 10, 16+i, 23, 0, 0, 0, vietnam).UTC()
	}

	var votes []GameSummaryLine
	got := map[string]GameSummarySection{}
	for _, section := range p.summary().Replay {
		got[section.Title] = section
		for _, line := range section.Lines {
			if line.Tag == "TREO" {
				votes = append(votes, line)
			}
		}
	}
	if n := got["Đêm 1"]; n.Round != 1 || n.Date != "17/10" {
		t.Fatalf("Đêm 1 = round %d date %q", n.Round, n.Date)
	}
	if d := got["Ngày 1"]; d.Round != 1 || d.Date != "19/10" {
		t.Fatalf("Ngày 1 = round %d date %q", d.Round, d.Date)
	}
	if len(votes) != 1 || votes[0].Hang != 2 || votes[0].Spare != 0 {
		t.Fatalf("câu phiếu = %+v", votes)
	}
}
