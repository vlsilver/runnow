package backend

import (
	"errors"
	"fmt"
	"math"
	"net/http"
	"slices"
	"strings"
	"time"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Chữ hiện cho người chơi. App chỉ render những gì API trả (3.8), nên sửa chữ ở
// đây là xong, không cần ra bản app mới.

var roleLabels = map[werewolf.Role]string{
	werewolf.Wolf: "Sói", werewolf.Seer: "Tiên tri", werewolf.Guard: "Bảo vệ", werewolf.Witch: "Phù thuỷ",
	werewolf.Hunter: "Thợ săn", werewolf.Cupid: "Cupid", werewolf.Villager: "Dân",
	werewolf.Elder: "Già làng", werewolf.Idiot: "Kẻ ngốc",
}

var roleRules = map[werewolf.Role]string{
	werewolf.Wolf:     "Đêm nào cả phe cũng chọn một người để cắn, từ {night} tới {lock}. Lựa chọn bấm sau cùng của phe được tính.",
	werewolf.Seer:     "Mỗi đêm soi một người để biết người đó là Sói hay Dân. Chọn một lần, có kết quả ngay.",
	werewolf.Guard:    "Mỗi đêm bảo vệ một người khỏi bị sói cắn, được tự bảo vệ. Không chọn lại người của đêm trước.",
	werewolf.Witch:    "Cả ván có một bình cứu và một bình độc, dùng từ {lock} tới {dawn}. Bình cứu chỉ cứu người bị cắn đêm đó; chỉ tự cứu được ở đêm 1.",
	werewolf.Hunter:   "Khi chết thì được bắn một người, trong khung giờ ngay sau lúc chết. Chết vì độc hoặc rời PSC thì không được bắn.",
	werewolf.Cupid:    "Đêm 1 ghép hai người thành cặp đôi, ghép cả mình cũng được. Một người chết thì người kia chết theo. Quá {lock} chưa ghép thì bot ghép thay.",
	werewolf.Villager: "Thảo luận, đề cử và biểu quyết để tìm ra sói.",
	werewolf.Elder:    "Phe Dân. Chịu được một lần bị sói cắn: cú cắn đầu tiên không ai bảo vệ hay cứu thì bạn vẫn sống, chỉ mình bạn được báo. Cú cắn sau thì chết. Bị độc, bị treo hay bị bắn thì chết ngay.",
	werewolf.Idiot:    "Phe Dân. Bị làng treo lần đầu thì bạn lật bài Kẻ ngốc và vẫn sống, nhưng từ đó mất quyền bỏ phiếu tới hết ván, vẫn đề cử được. Bị treo lần nữa thì chết. Bị cắn, bị độc hay bị bắn thì chết như thường.",
}

// Chữ giờ trong luật viết bằng {night}, {lock}…, clockText đổi theo lịch ván.
const gameRulesText = scheduleDefaultText + " {night} tới {dawn} là đêm: các vai có kỹ năng chọn người. {dawn} bản tin đêm, đề cử tới {nominate}; tối đa 3 người nhiều đề cử nhất lên giàn. {nominate} tới {close} biểu quyết Treo hay Tha từng người. {close} chốt phiếu và km.\n" +
	"Người bị treo chỉ lộ là phe Dân hay phe Sói, không lật lá bài, trừ khi còn được bắn một người thì lật. Chết cách khác thì lật lá bài. Hết ván lật bài tất cả.\n" +
	gameKmLineCut +
	"Dân thắng khi hết sói. Sói thắng khi số sói bằng số người còn lại. Cặp đôi Sói và Dân thắng khi chỉ còn hai người họ. Ván chạy tới khi có phe thắng, không giới hạn số vòng."

// botVoteRulesText nói kỹ phần đề cử và đếm phiếu (step.go: pickNominee,
// countVotes, voteCut) cho 3i, vì gameRulesText chỉ nói gọn cho màn hình app.
const botVoteRulesText = "Đề cử: {nominate} tối đa 3 người nhiều đề cử nhất lên giàn, một đề cử là đủ; bằng đề cử ở suất cuối thì bốc thăm; không ai đề cử thì hôm đó không treo. Đề cử của người đã chết và đề cử nhắm vào người đã chết không tính.\n" +
	"Biểu quyết: mỗi người lên giàn có một phiên Treo/Tha riêng, mọi phiên chốt cùng lúc {close} nên một ngày treo được tới 3 người. Người lên giàn không bỏ phiếu ở phiên của mình nhưng vẫn bỏ phiếu ở phiên người khác, kể cả khi chính họ bị treo. Treo khi phiếu Treo được tính nhiều hơn phiếu Tha, hoà thì tha. Người yêu bấm Treo người yêu mình thì phiếu đó không tính.\n" +
	botVoteKmCut

// Các câu về km trong luật đổi theo cấu hình của ván (werewolf.Config): km từng
// vai, tắt km, luật phiếu. x là km một phiếu đã định dạng, "X" khi chưa có ván.
const (
	gameKmLineCut  = "km trong khung 22h hôm qua tới 22h hôm nay quyết định có được dùng kỹ năng và có được bỏ phiếu không.\n"
	gameKmLineTop  = "km trong khung 22h hôm qua tới 22h hôm nay quyết định có được dùng kỹ năng không. Không ai mất phiếu; %s chạy nhiều nhất, mỗi người đủ %s km, được tính 2 phiếu.\n"
	gameKmLineFlat = "km trong khung 22h hôm qua tới 22h hôm nay chỉ quyết định có được dùng kỹ năng không; phiếu nào cũng tính.\n"
	botVoteKmCut   = "Phiếu theo km, tính riêng từng phiên: 22h cộng km (22h hôm qua tới 22h hôm nay) của mọi người còn sống trừ người lên giàn của phiên đó. Số phiếu được tính bằng tổng km chia X km, làm tròn xuống, không quá số người. Thiếu thì người ít km nhất mất phiếu trước, kể cả người không bấm; bằng km thì bốc thăm."
	botVoteKmTop   = "Phiếu theo km, tính riêng từng phiên: không ai mất phiếu. 22h lấy km (22h hôm qua tới 22h hôm nay) của mọi người còn sống trừ người lên giàn của phiên đó; %s nhiều km nhất, mỗi người đủ X km, được tính 2 phiếu; bằng km ở suất cuối thì bốc thăm."
	botVoteKmFlat  = "Mỗi người một phiếu, km không tác động lên phiếu."
)

// gameRulesFor là gameRulesText theo cấu hình của ván.
func gameRulesFor(cfg werewolf.Config) string {
	text := gameRulesText
	switch cfg.VoteMode() {
	case werewolf.VoteTop:
		text = strings.Replace(text, gameKmLineCut, fmt.Sprintf(gameKmLineTop, topVotersText(cfg), formatKm(kmPerUnit(cfg))), 1)
	case werewolf.VoteFlat:
		if cfg.KmOff {
			text = strings.Replace(strings.Replace(text, gameKmLineCut, "", 1), "{close} chốt phiếu và km.", "{close} chốt phiếu.", 1)
		} else {
			text = strings.Replace(text, gameKmLineCut, gameKmLineFlat, 1)
		}
	}
	text = strings.Replace(text, scheduleDefaultText, scheduleText(cfg), 1)
	return clockText(text, ruleClock(cfg))
}

const scheduleDefaultText = "Mỗi vòng dài một ngày."

// scheduleText là câu đầu luật: vòng dài bao lâu, mở lúc mấy giờ.
func scheduleText(cfg werewolf.Config) string {
	s := cfg.Schedule
	// Lịch gốc chỉ chia lại pha (ván km) vẫn là một vòng một ngày mở 22h; giờ
	// từng pha in ở các dòng sau.
	if s == nil || (s.StartHour == 22 && s.RoundHours == 24 && s.Rounds == 1) {
		return scheduleDefaultText
	}
	starts := cfg.RoundStarts()
	hours := make([]string, len(starts))
	for i, h := range starts {
		hours[i] = itoa(h) + "h"
	}
	if !cfg.KmOff {
		return fmt.Sprintf("Mỗi ngày %d vòng, mỗi vòng dài %d tiếng, mở lúc %s. Km chốt lúc 22h nên các vòng trong ngày dùng chung km của ngày chạy trước. Giờ bên dưới là của vòng mở lúc %s, vòng khác lệch giờ tương ứng.",
			s.Rounds, s.RoundHours, strings.Join(hours, ", "), hours[0])
	}
	if s.Rounds == 1 {
		return fmt.Sprintf("Mỗi ngày một vòng dài %d tiếng, mở lúc %s; ngoài khung đó không nhận lựa chọn nào.", s.RoundHours, hours[0])
	}
	return fmt.Sprintf("Mỗi ngày %d vòng, mỗi vòng dài %d tiếng, mở lúc %s; ngoài khung đó không nhận lựa chọn nào. Giờ bên dưới là của vòng mở lúc %s, vòng khác lệch giờ tương ứng.",
		s.Rounds, s.RoundHours, strings.Join(hours, ", "), hours[0])
}

// hm là giờ VN viết kiểu "22h", "6h30".
func hm(t time.Time) string {
	t = t.In(vietnam)
	if t.Minute() == 0 {
		return itoa(t.Hour()) + "h"
	}
	return fmt.Sprintf("%dh%02d", t.Hour(), t.Minute())
}

// clockText thay chữ giờ trong s bằng các mốc của vòng k. "{dawn sáng}" thêm
// chữ "sáng" khi mốc đó rơi vào buổi sáng, như "10h sáng" của lịch gốc.
func clockText(s string, k werewolf.RoundClock) string {
	dawn, dawnPart := hm(k.Dawn), hm(k.Dawn)
	if h := k.Dawn.In(vietnam).Hour(); h >= 4 && h <= 10 {
		dawnPart += " sáng"
	}
	return strings.NewReplacer("{night}", hm(k.Night), "{lock}", hm(k.WolfLock), "{dawn sáng}", dawnPart, "{dawn}", dawn,
		"{nominate}", hm(k.NominateClose), "{close}", hm(k.Close)).Replace(s)
}

// ruleClock là các mốc của vòng mở đầu tiên trong ngày, cho luật in sẵn.
func ruleClock(cfg werewolf.Config) werewolf.RoundClock {
	return cfg.Clock(time.Date(2026, 1, 1, cfg.RoundStarts()[0], 0, 0, 0, vietnam))
}

// botVoteRulesFor là botVoteRulesText theo cấu hình của ván.
func botVoteRulesFor(cfg werewolf.Config, x string) string {
	km := botVoteKmCut
	switch cfg.VoteMode() {
	case werewolf.VoteTop:
		km = fmt.Sprintf(botVoteKmTop, topVotersText(cfg))
	case werewolf.VoteFlat:
		km = botVoteKmFlat
	}
	return clockText(strings.ReplaceAll(strings.Replace(botVoteRulesText, botVoteKmCut, km, 1), "X km", x+" km"), ruleClock(cfg))
}

func topVotersText(cfg werewolf.Config) string {
	if cfg.TopVoters > 0 {
		return fmt.Sprintf("%d người", cfg.TopVoters)
	}
	return "số người bằng số sói còn sống cộng 1"
}

// roleRulesFor là luật của vai role kèm câu km và giờ theo cấu hình của ván.
func roleRulesFor(role werewolf.Role, cfg werewolf.Config, x string) string {
	text := clockText(roleRules[role], ruleClock(cfg))
	if line := roleKmLine(role, cfg, x); line != "" {
		return text + " " + line
	}
	return text
}

// roleKmLine là câu km của vai role; rỗng khi vai không có kỹ năng cần km hoặc
// ván tắt km.
func roleKmLine(role werewolf.Role, cfg werewolf.Config, x string) string {
	if cfg.KmOff {
		return ""
	}
	need := skillKmText(role, cfg, x)
	switch role {
	case werewolf.Wolf:
		if cfg.SkillMeters(werewolf.Wolf) == 0 {
			return "Phe Sói cắn không cần km."
		}
		return "Tổng km của sói còn sống phải đủ " + need + " km cho mỗi sói."
	case werewolf.Seer, werewolf.Guard, werewolf.Witch, werewolf.Hunter:
		switch {
		case cfg.SkillMeters(role) == 0:
			return "Không cần km."
		case cfg.VillageGate:
			return "Tính chung cả phe Dân: tổng km người không phải sói còn sống phải đủ " + need + " km cho mỗi người."
		}
		return "Cần đủ " + need + " km."
	}
	return ""
}

// skillKmText là km vai role cần, đã định dạng; vai theo KmPerUnit thì là x.
func skillKmText(role werewolf.Role, cfg werewolf.Config, x string) string {
	if km, ok := cfg.SkillKm[role]; ok {
		return formatKm(km)
	}
	return x
}

// kmNeedsText là câu đầu bảng km trong group: km từng kỹ năng cần, không nhắc
// vai của ai.
func kmNeedsText(cfg werewolf.Config) string {
	x := formatKm(kmPerUnit(cfg))
	var parts []string
	for _, role := range []werewolf.Role{werewolf.Seer, werewolf.Guard, werewolf.Witch, werewolf.Hunter} {
		if slices.Contains(cfg.Disabled, role) {
			continue
		}
		if cfg.SkillMeters(role) == 0 {
			parts = append(parts, roleLabels[role]+" không cần km")
		} else {
			parts = append(parts, roleLabels[role]+" "+skillKmText(role, cfg, x)+" km")
		}
	}
	text := "Km cần cho kỹ năng: " + strings.Join(parts, ", ") + "."
	if cfg.VillageGate {
		text += " Phe Dân tính chung: tổng km người không phải sói còn sống phải đủ mức đó cho mỗi người."
	}
	if cfg.SkillMeters(werewolf.Wolf) == 0 {
		text += " Sói cắn không cần km."
	} else {
		text += " Sói tính chung cả phe: tổng km sói còn sống phải đủ " + skillKmText(werewolf.Wolf, cfg, x) + " km cho mỗi sói."
	}
	return text + " Cupid không cần km."
}

// botHowToPlayText là cách bấm, để 3i chỉ đúng chỗ khi người chơi hỏi.
const botHowToPlayText = "Mọi lựa chọn đều bằng nút, gõ chữ cho 3i không được tính. Kỹ năng ban đêm: bấm trong app 3i Run (mục Ma Sói) hoặc nút trong tin 3i nhắn riêng: chọn tên rồi bấm Chốt. Đề cử và biểu quyết: bấm nút trong topic Ma Sói của group hoặc trong app, đổi được tới hạn. Phe Sói bàn nhau trong chat phe Sói của app."

var teamLabels = map[werewolf.Team]string{
	werewolf.TeamVillage: "Phe Dân", werewolf.TeamWolves: "Phe Sói", werewolf.TeamLovers: "Cặp đôi",
}

var statusLabels = map[string]string{
	gameRegistering: "Đang đăng ký", gameStarting: "Đang chia bài", gameRunning: "Đang chơi",
	gameEnded: "Đã kết thúc", gameCancelled: "Đã huỷ",
}

type actionText struct {
	label, help, input, confirm string
}

const confirmOnce = "Chọn rồi không đổi được. Chắc chưa?"

var actionTexts = map[werewolf.Kind]actionText{
	werewolf.KindWolfBite:    {"Cắn", "Chọn người phe Sói cắn đêm nay. Lựa chọn bấm sau cùng của phe được tính. Khoá lúc {lock}.", "single_target", ""},
	werewolf.KindSeerPeek:    {"Soi", "Chọn một người để biết là Sói hay Dân.", "single_target", confirmOnce},
	werewolf.KindGuard:       {"Bảo vệ", "Chọn một người để đỡ cú cắn đêm nay. Không chọn lại người của đêm trước.", "single_target", ""},
	werewolf.KindWitchSave:   {"Bình cứu", "Cứu người bị cắn đêm nay. Cả ván chỉ có một bình.", "confirm", ""},
	werewolf.KindWitchPoison: {"Bình độc", "Chọn một người để giết. Cả ván chỉ có một bình.", "single_target", ""},
	werewolf.KindHunterShoot: {"Bắn", "Bạn đã chết. Chọn một người bắn theo.", "single_target", confirmOnce},
	werewolf.KindCupidPair:   {"Ghép đôi", "Chọn hai người thành cặp đôi. Một người chết thì người kia chết theo.", "two_targets", confirmOnce},
	werewolf.KindNominate:    {"Đề cử", "Chọn một người lên giàn. Đổi được tới {nominate}.", "single_target", ""},
	werewolf.KindVote:        voteText,
	werewolf.KindVote2:       voteText,
	werewolf.KindVote3:       voteText,
}

// actionHelp là dòng hướng dẫn của kind, giờ theo vòng đang chạy của ván.
func actionHelp(st *werewolf.State, kind werewolf.Kind) string {
	return clockText(actionTexts[kind].help, st.Config.Clock(st.NightAt))
}

var voteText = actionText{"Biểu quyết", "Treo hay tha người đang lên giàn. Đổi được tới {close}.", "choice", ""}

// rejectTexts là lý do luật từ chối, dùng cho cả disabledReason lẫn body lỗi.
var rejectTexts = map[werewolf.Reject]string{
	werewolf.ErrPhaseClosed:    "Chưa tới giờ hoặc đã hết giờ.",
	werewolf.ErrNotAlive:       "Bạn đã chết.",
	werewolf.ErrNotYourRole:    "Vai của bạn không làm được việc này.",
	werewolf.ErrKmInsufficient: "Chưa đủ km.",
	werewolf.ErrInvalidTarget:  "Không chọn được người này.",
	werewolf.ErrLoverTarget:    "Không chọn được người yêu của mình.",
	werewolf.ErrGuardRepeat:    "Không bảo vệ lại người của đêm trước.",
	werewolf.ErrAlreadyUsed:    "Bạn đã dùng lượt này rồi.",
	werewolf.ErrPaused:         "Ván đang tạm dừng.",
	werewolf.ErrNoVote:         "Kẻ ngốc đã lật bài nên không được bỏ phiếu nữa.",
}

// rejectText riêng cho bình cứu: Precheck trả invalid_target khi không ai bị cắn.
func rejectText(kind werewolf.Kind, err error) string {
	if kind == werewolf.KindWitchSave && errors.Is(err, werewolf.ErrInvalidTarget) {
		return "Đêm nay không có ai để cứu."
	}
	if werewolf.IsVote(kind) && errors.Is(err, werewolf.ErrNotYourRole) {
		return "Người lên giàn không bỏ phiếu."
	}
	// Cắn xét km chung của phe (wolvesHaveKm), còn app hiện km riêng từng người:
	// chỉ ghi "Chưa đủ km" thì sói có km riêng đủ ngưỡng tưởng app lỗi.
	if kind == werewolf.KindWolfBite && errors.Is(err, werewolf.ErrKmInsufficient) {
		return "Phe Sói chưa đủ km. Sói tính chung cả phe: tổng km của sói còn sống phải đủ ngưỡng km cho mỗi sói, km riêng của bạn đủ thì vẫn chưa cắn được."
	}
	var r werewolf.Reject
	if errors.As(err, &r) {
		if t, ok := rejectTexts[r]; ok {
			return t
		}
	}
	return "Chưa làm được lúc này."
}

// wolfKmShort là phe Sói thiếu km bao nhiêu: have, need theo mét (WolfKm), unit
// theo km. Chỉ dùng trong thẻ và tin riêng của sói. Km phe cắt xuống 0,1 km như
// bảng km, để thiếu vài chục mét không hiện thành đủ.
func wolfKmShort(have, need, unit float64) string {
	return fmt.Sprintf("cả phe có %s km, cần %s km (%s km cho mỗi sói còn sống)",
		formatKm(math.Floor(have/100)/10), formatKm(need/1000), formatKm(unit))
}

// disabledReason là lý do khoá nút trên thẻ hành động. Có state nên nút Cắn
// thiếu km ghi được số của phe; rejectText thì không có state.
func disabledReason(st *werewolf.State, kind werewolf.Kind, err error) string {
	if kind != werewolf.KindWolfBite || !errors.Is(err, werewolf.ErrKmInsufficient) {
		return rejectText(kind, err)
	}
	have, need := werewolf.WolfKm(st)
	return "Phe Sói chưa đủ km: " + wolfKmShort(have, need, kmPerUnit(st.Config)) + ". " +
		"Sói tính chung cả phe nên km riêng của bạn đủ thì vẫn chưa cắn được. Km đã chốt lúc 22h, muốn cắn đêm sau thì cả phe chạy thêm trước 22h."
}

// rejectHTTP: lỗi luật trả 409/422, không bao giờ 5xx, để app không retry (3.8).
func rejectHTTP(kind werewolf.Kind, err error) *HTTPError {
	status := http.StatusUnprocessableEntity
	if errors.Is(err, werewolf.ErrPhaseClosed) || errors.Is(err, werewolf.ErrPaused) {
		status = http.StatusConflict
	}
	return &HTTPError{Status: status, Code: err.Error(), Message: rejectText(kind, err)}
}

var choiceLabels = map[string]string{werewolf.ChoiceHang: "Treo", werewolf.ChoiceSpare: "Tha"}

// phaseLabel là tên lượt đang chạy. deadline là hạn của lượt đó; lúc chuẩn bị
// thì nó là giờ mở đêm 1.
func phaseLabel(round int, phase werewolf.Phase, deadline time.Time) string {
	switch phase {
	case werewolf.PhaseSetup:
		if deadline.IsZero() {
			return "Chuẩn bị"
		}
		return "Chuẩn bị, đêm 1 bắt đầu lúc " + hm(deadline)
	case werewolf.PhaseNight:
		return "Đêm " + itoa(round) + ", sói đang chọn"
	case werewolf.PhaseDawn:
		return "Rạng sáng ngày " + itoa(round)
	case werewolf.PhaseDay:
		return "Ngày " + itoa(round) + ", đề cử"
	case werewolf.PhaseTrial:
		return "Ngày " + itoa(round) + ", lên giàn"
	case werewolf.PhaseEnded:
		return "Đã kết thúc"
	}
	return ""
}
