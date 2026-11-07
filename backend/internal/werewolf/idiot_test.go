package werewolf

import "testing"

func idiotGame(t *testing.T) *tg {
	roles := baseRoles()
	roles["v1"] = Idiot
	g := newGame(t, roles)
	g.st.Config.Extended = []Role{Idiot}
	g.next()
	return g
}

// Treo lần đầu: Kẻ ngốc lật bài, không chết, cả làng biết. Treo lần sau thì chết.
func TestIdiotFirstHangReveals(t *testing.T) {
	g := idiotGame(t)
	evs := g.hang("v1")
	sameDeaths(t, evs, map[string]Cause{})
	if e := find(evs, EventRevealed); e == nil || e.UID != "v1" || e.Role != Idiot {
		t.Fatalf("event lật bài = %+v", e)
	}
	if p := g.st.Players["v1"]; !p.Alive || !p.Revealed {
		t.Fatalf("v1 = %+v, mong đợi còn sống và đã lật bài", p)
	}
	sameDeaths(t, g.hang("v1"), map[string]Cause{"v1": CauseHang})
}

// Kẻ ngốc đã lật mất phiếu: không có nút, bấm thì bị từ chối, phiếu lọt vào thì
// bị huỷ, và không chiếm chỗ người bỏ phiếu khi chia phiếu theo km.
func TestRevealedIdiotLosesVote(t *testing.T) {
	g := idiotGame(t)
	g.hang("v1")
	for uid := range g.km {
		g.km[uid] = 1000
	}
	// Còn tính là người bỏ phiếu thì 12 người chỉ có 11 km, v1 ít km nhất bị cắt.
	g.km["v1"] = 0
	g.toPhase(PhaseDay)
	g.do(KindNominate, "v3", "v2")
	g.next()
	if got := g.st.Available("v1"); len(got) != 0 {
		t.Fatalf("Kẻ ngốc đã lật còn nút %v", got)
	}
	g.reject(ErrNoVote, Action{Kind: KindVote, Actor: "v1", Choice: ChoiceHang})
	// Phiếu ghi trước khi luật chặn (app cũ, bấm lúc đang chốt) vẫn phải bị huỷ.
	g.actions["v1/"+string(KindVote)] = Action{Kind: KindVote, Actor: "v1", Choice: ChoiceHang, ReceivedAt: g.now()}
	for _, v := range []string{"w1", "w2", "w3", "seer", "guard"} {
		g.vote(v, ChoiceHang)
	}
	for _, v := range []string{"witch", "hunter", "v3", "v4", "v5", "v6"} {
		g.vote(v, ChoiceSpare)
	}
	evs := g.next()
	if e := find(evs, EventVoteCut); e != nil {
		t.Fatalf("có người mất phiếu vì km: %+v", e)
	}
	if e := find(evs, EventVoid); e == nil || e.UID != "v1" || e.Reason != VoidNoVote {
		t.Fatalf("phiếu của v1 = %+v, mong đợi bị huỷ vì mất phiếu", e)
	}
	if e := find(evs, EventVoteResult); e.Hang != 5 || e.Spare != 6 {
		t.Fatalf("kết quả = %+v, mong đợi Treo 5, Tha 6", e)
	}
}
