package backend

import (
	"reflect"
	"testing"

	ww "github.com/vlsilver/runnow/backend/internal/werewolf"
)

// tallyPlayers: người chơi đặt tên theo uid để kỳ vọng đọc thẳng được.
func tallyPlayers(uids ...string) []gamePlayerInfo {
	out := make([]gamePlayerInfo, len(uids))
	for i, uid := range uids {
		out[i] = gamePlayerInfo{uid: uid, name: uid}
	}
	return out
}

// Phiên Treo Chi, Theo nhóm 2 km một phiếu (ví dụ trên board, tính tay): 9 người
// chạy 17,2 km nên 8 phiếu được tính, Vy ít km nhất mất phiếu. Treo 4 phiếu
// 9,5 km, Tha 4 phiếu 7,4 km: bằng phiếu, Treo hơn km nên thắng.
func TestActionTallyVoteCutByGroupKm(t *testing.T) {
	uids := []string{"Chi", "An", "Dung", "Ha", "Tu", "Vy", "Binh", "Lan", "Khoa", "Minh"}
	roles := map[string]ww.Role{}
	for _, uid := range uids {
		roles[uid] = ww.Villager
	}
	roles["Dung"] = ww.Wolf
	st := ww.NewState(ww.Seed{1}, ww.Config{Ruleset: ww.RulesetKm, KmPerUnit: 2}, roles, msgStart)
	st.Phase, st.Nominee = ww.PhaseTrial, "Chi"
	km := map[string]float64{"An": 3200, "Dung": 3000, "Ha": 2100, "Tu": 1200, "Vy": 300, "Binh": 2400, "Lan": 2600, "Khoa": 1500, "Minh": 900}
	var acts []ww.Action
	for _, uid := range []string{"An", "Dung", "Ha", "Tu", "Vy"} {
		acts = append(acts, ww.Action{Kind: ww.KindVote, Actor: uid, Choice: ww.ChoiceHang})
	}
	for _, uid := range []string{"Binh", "Lan", "Khoa", "Minh"} {
		acts = append(acts, ww.Action{Kind: ww.KindVote, Actor: uid, Choice: ww.ChoiceSpare})
	}
	got := actionTally(st, ww.KindVote, acts, km, tallyPlayers(uids...))
	want := &GameTally{
		Seats:  1,
		Reason: "Bằng phiếu · hơn km",
		Note:   "Nhóm chạy 17.2 km, 2 km một phiếu: đủ 8 phiếu cho 9 người. Mất phiếu vì ít km nhất: Vy.",
		Rows: []GameTallyRow{
			{ID: ww.ChoiceHang, Label: "Treo", Votes: 4, Km: 9.5, Lead: true, Voters: []GameTallyVoter{
				{Name: "An", Km: 3.2}, {Name: "Dung", Km: 3}, {Name: "Ha", Km: 2.1}, {Name: "Tu", Km: 1.2}, {Name: "Vy", Km: 0.3, Cut: true}}},
			{ID: ww.ChoiceSpare, Label: "Tha", Votes: 4, Km: 7.4, Voters: []GameTallyVoter{
				{Name: "Binh", Km: 2.4}, {Name: "Lan", Km: 2.6}, {Name: "Khoa", Km: 1.5}, {Name: "Minh", Km: 0.9}}},
		},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("tally =\n %+v\nmong đợi\n %+v", got, want)
	}
}

// Riêng 1 km một phiếu, Top 2 được 2 phiếu (tính tay): Dao 0,5 km chưa đủ nên
// mất phiếu; trong người còn phiếu, An 5 km và Binh 4 km vào top. Treo 2 phiếu
// (An), Tha 3 phiếu (Binh 2 + Cuc 1): Tha nhiều phiếu hơn.
func TestActionTallyVoteSoloWithTop(t *testing.T) {
	uids := []string{"Nam", "An", "Binh", "Cuc", "Dao"}
	roles := map[string]ww.Role{"Nam": ww.Villager, "An": ww.Villager, "Binh": ww.Wolf, "Cuc": ww.Villager, "Dao": ww.Villager}
	cfg := ww.Config{Ruleset: ww.RulesetKm, Vote: ww.VoteSolo, KmPerUnit: 1, TopVoters: 2, TopWeight: 2}
	st := ww.NewState(ww.Seed{1}, cfg, roles, msgStart)
	st.Phase, st.Nominee = ww.PhaseTrial, "Nam"
	km := map[string]float64{"An": 5000, "Binh": 4000, "Cuc": 3000, "Dao": 500}
	acts := []ww.Action{
		{Kind: ww.KindVote, Actor: "An", Choice: ww.ChoiceHang},
		{Kind: ww.KindVote, Actor: "Binh", Choice: ww.ChoiceSpare},
		{Kind: ww.KindVote, Actor: "Cuc", Choice: ww.ChoiceSpare},
		{Kind: ww.KindVote, Actor: "Dao", Choice: ww.ChoiceHang},
	}
	got := actionTally(st, ww.KindVote, acts, km, tallyPlayers(uids...))
	want := &GameTally{
		Seats:  1,
		Reason: "Nhiều phiếu hơn",
		Note:   "Chưa đủ 1 km nên mất phiếu: Dao. Top 2 được 2 phiếu: An, Binh.",
		Rows: []GameTallyRow{
			{ID: ww.ChoiceHang, Label: "Treo", Votes: 2, Km: 5, Voters: []GameTallyVoter{
				{Name: "An", Km: 5, Weight: 2}, {Name: "Dao", Km: 0.5, Cut: true}}},
			{ID: ww.ChoiceSpare, Label: "Tha", Votes: 3, Km: 7, Lead: true, Voters: []GameTallyVoter{
				{Name: "Binh", Km: 4, Weight: 2}, {Name: "Cuc", Km: 3}}},
		},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("tally =\n %+v\nmong đợi\n %+v", got, want)
	}
}

// Đề cử, treo tối đa 2 (tính tay): Xuan 2 đề cử dẫn chắc; Yen và Vu cùng 1 đề cử,
// người đề cử Yen chạy 3 km, người đề cử Vu 2 km, nên Yen lấy suất thứ hai vì
// hơn km, dù Vu được đề cử trước. Đề cử nhắm người đã chết không tính.
func TestActionTallyNominateSeatsByKm(t *testing.T) {
	uids := []string{"An", "Binh", "Cuc", "Dao", "Xuan", "Yen", "Vu", "Ma"}
	roles := map[string]ww.Role{}
	for _, uid := range uids {
		roles[uid] = ww.Villager
	}
	roles["Dao"] = ww.Wolf
	st := ww.NewState(ww.Seed{1}, ww.Config{Ruleset: ww.RulesetKm, MaxHang: 2}, roles, msgStart)
	st.Phase = ww.PhaseDay
	st.Players["Ma"].Alive = false
	st.Km = map[string]float64{"An": 1000, "Binh": 1500, "Cuc": 2000, "Dao": 3000, "Xuan": 4000}
	acts := []ww.Action{
		{Kind: ww.KindNominate, Actor: "An", Targets: []string{"Xuan"}},
		{Kind: ww.KindNominate, Actor: "Binh", Targets: []string{"Xuan"}},
		{Kind: ww.KindNominate, Actor: "Cuc", Targets: []string{"Vu"}},
		{Kind: ww.KindNominate, Actor: "Dao", Targets: []string{"Yen"}},
		{Kind: ww.KindNominate, Actor: "Xuan", Targets: []string{"Ma"}},
	}
	got := actionTally(st, ww.KindNominate, acts, st.Km, tallyPlayers(uids...))
	want := &GameTally{
		Seats:  2,
		Reason: "Bằng phiếu · hơn km",
		Rows: []GameTallyRow{
			{ID: "Xuan", Label: "Xuan", Votes: 2, Km: 2.5, Lead: true, Voters: []GameTallyVoter{{Name: "An", Km: 1}, {Name: "Binh", Km: 1.5}}},
			{ID: "Yen", Label: "Yen", Votes: 1, Km: 3, Lead: true, Voters: []GameTallyVoter{{Name: "Dao", Km: 3}}},
			{ID: "Vu", Label: "Vu", Votes: 1, Km: 2, Voters: []GameTallyVoter{{Name: "Cuc", Km: 2}}},
		},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("tally =\n %+v\nmong đợi\n %+v", got, want)
	}
}

// Sói cắn Theo nhóm, 2 km một phiếu (tính tay): 3 sói chạy 1,5 + 2,5 + 0,8 = 4,8 km
// nên 2 phiếu được tính, Soi3 ít km nhất mất phiếu. An 1 phiếu (Soi1), Binh 1
// phiếu (Soi2 2,5 km): bằng phiếu, Binh hơn km. Phiếu của người không phải sói
// không tính.
func TestActionTallyWolfBiteCut(t *testing.T) {
	uids := []string{"Soi1", "Soi2", "Soi3", "An", "Binh"}
	roles := map[string]ww.Role{"Soi1": ww.Wolf, "Soi2": ww.Wolf, "Soi3": ww.Wolf, "An": ww.Villager, "Binh": ww.Seer}
	cfg := ww.Config{Ruleset: ww.RulesetKm, SkillKm: map[ww.Role]float64{ww.Wolf: 2}}
	st := ww.NewState(ww.Seed{1}, cfg, roles, msgStart)
	st.Phase = ww.PhaseNight
	st.Km = map[string]float64{"Soi1": 1500, "Soi2": 2500, "Soi3": 800, "An": 9000}
	acts := []ww.Action{
		{Kind: ww.KindWolfBite, Actor: "Soi1", Targets: []string{"An"}},
		{Kind: ww.KindWolfBite, Actor: "Soi2", Targets: []string{"Binh"}},
		{Kind: ww.KindWolfBite, Actor: "Soi3", Targets: []string{"An"}},
		{Kind: ww.KindWolfBite, Actor: "An", Targets: []string{"Binh"}},
	}
	got := actionTally(st, ww.KindWolfBite, acts, st.Km, tallyPlayers(uids...))
	want := &GameTally{
		Seats:  1,
		Reason: "Bằng phiếu · hơn km",
		Note:   "Mất phiếu vì ít km nhất: Soi3.",
		Rows: []GameTallyRow{
			{ID: "Binh", Label: "Binh", Votes: 1, Km: 2.5, Lead: true, Voters: []GameTallyVoter{{Name: "Soi2", Km: 2.5}}},
			{ID: "An", Label: "An", Votes: 1, Km: 1.5, Voters: []GameTallyVoter{{Name: "Soi1", Km: 1.5}, {Name: "Soi3", Km: 0.8, Cut: true}}},
		},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("tally =\n %+v\nmong đợi\n %+v", got, want)
	}
}

// Ván luật cũ không có bảng kiểm phiếu; ván luật km chưa ai chọn thì không hàng
// nào dẫn và không có lý do.
func TestActionTallyOldRulesetAndEmpty(t *testing.T) {
	roles := map[string]ww.Role{"An": ww.Villager, "Binh": ww.Wolf, "Cuc": ww.Villager}
	old := ww.NewState(ww.Seed{1}, ww.Config{}, roles, msgStart)
	if got := actionTally(old, ww.KindNominate, nil, nil, tallyPlayers("An", "Binh", "Cuc")); got != nil {
		t.Fatalf("ván cũ: tally = %+v, mong đợi nil", got)
	}
	st := ww.NewState(ww.Seed{1}, ww.Config{Ruleset: ww.RulesetKm}, roles, msgStart)
	st.Phase, st.Nominee = ww.PhaseTrial, "An"
	got := actionTally(st, ww.KindVote, nil, map[string]float64{"Binh": 5000, "Cuc": 5000}, tallyPlayers("An", "Binh", "Cuc"))
	want := &GameTally{Seats: 1, Rows: []GameTallyRow{
		{ID: ww.ChoiceHang, Label: "Treo", Voters: []GameTallyVoter{}},
		{ID: ww.ChoiceSpare, Label: "Tha", Voters: []GameTallyVoter{}},
	}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("tally =\n %+v\nmong đợi\n %+v", got, want)
	}
}
