package backend

import (
	"errors"
	"fmt"
	"math"
	"net/http"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

// Chữ hiện cho người chơi. App chỉ render những gì API trả (3.8), nên sửa chữ ở
// đây là xong, không cần ra bản app mới.

var roleLabels = map[werewolf.Role]string{
	werewolf.Wolf: "Sói", werewolf.Seer: "Tiên tri", werewolf.Guard: "Bảo vệ", werewolf.Witch: "Phù thuỷ",
	werewolf.Hunter: "Thợ săn", werewolf.Cupid: "Cupid", werewolf.Villager: "Dân",
}

var roleRules = map[werewolf.Role]string{
	werewolf.Wolf:     "Đêm nào cả phe cũng chọn một người để cắn, từ 22h tới 0h. Lựa chọn bấm sau cùng của phe được tính. Tổng km của sói còn sống phải đủ X km cho mỗi sói.",
	werewolf.Seer:     "Mỗi đêm soi một người để biết người đó là Sói hay Dân. Chọn một lần, có kết quả ngay. Cần đủ X km.",
	werewolf.Guard:    "Mỗi đêm bảo vệ một người khỏi bị sói cắn, được tự bảo vệ. Không chọn lại người của đêm trước. Cần đủ X km.",
	werewolf.Witch:    "Cả ván có một bình cứu và một bình độc, dùng từ 0h tới 10h. Bình cứu chỉ cứu người bị cắn đêm đó; chỉ tự cứu được ở đêm 1. Cần đủ X km.",
	werewolf.Hunter:   "Khi chết thì được bắn một người, trong khung giờ ngay sau lúc chết. Chết vì độc hoặc rời PSC thì không được bắn.",
	werewolf.Cupid:    "Đêm 1 ghép hai người thành cặp đôi, ghép cả mình cũng được. Một người chết thì người kia chết theo. Quá 0h chưa ghép thì bot ghép thay.",
	werewolf.Villager: "Thảo luận, đề cử và biểu quyết để tìm ra sói.",
}

const gameRulesText = "Mỗi vòng dài một ngày. 22h tới 10h là đêm: các vai có kỹ năng chọn người. 10h bản tin đêm, đề cử tới 17h; người nhiều đề cử nhất lên giàn. 20h tới 22h biểu quyết Treo hay Tha. 22h chốt phiếu và km.\n" +
	"km trong khung 22h hôm qua tới 22h hôm nay quyết định có được dùng kỹ năng và có được bỏ phiếu không.\n" +
	"Dân thắng khi hết sói. Sói thắng khi số sói bằng số người còn lại. Cặp đôi Sói và Dân thắng khi chỉ còn hai người họ. Ván chạy tới khi có phe thắng, không giới hạn số vòng."

// botVoteRulesText nói kỹ phần đề cử và đếm phiếu (step.go: pickNominee,
// countVotes, voteCut) cho 3i, vì gameRulesText chỉ nói gọn cho màn hình app.
const botVoteRulesText = "Đề cử: 17h người nhiều đề cử nhất lên giàn, một đề cử là đủ; hoà thì bốc thăm; không ai đề cử thì hôm đó không treo. Đề cử của người đã chết và đề cử nhắm vào người đã chết không tính.\n" +
	"Biểu quyết: người lên giàn không bỏ phiếu. Treo khi phiếu Treo được tính nhiều hơn phiếu Tha, hoà thì tha. Người yêu bấm Treo người yêu mình thì phiếu đó không tính.\n" +
	"Phiếu theo km: 22h cộng km (22h hôm qua tới 22h hôm nay) của mọi người còn sống trừ người lên giàn. Số phiếu được tính bằng tổng km chia X km, làm tròn xuống, không quá số người. Thiếu thì người ít km nhất mất phiếu trước, kể cả người không bấm; bằng km thì bốc thăm."

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
	werewolf.KindWolfBite:    {"Cắn", "Chọn người phe Sói cắn đêm nay. Lựa chọn bấm sau cùng của phe được tính. Khoá lúc 0h.", "single_target", ""},
	werewolf.KindSeerPeek:    {"Soi", "Chọn một người để biết là Sói hay Dân.", "single_target", confirmOnce},
	werewolf.KindGuard:       {"Bảo vệ", "Chọn một người để đỡ cú cắn đêm nay. Không chọn lại người của đêm trước.", "single_target", ""},
	werewolf.KindWitchSave:   {"Bình cứu", "Cứu người bị cắn đêm nay. Cả ván chỉ có một bình.", "confirm", ""},
	werewolf.KindWitchPoison: {"Bình độc", "Chọn một người để giết. Cả ván chỉ có một bình.", "single_target", ""},
	werewolf.KindHunterShoot: {"Bắn", "Bạn đã chết. Chọn một người bắn theo.", "single_target", confirmOnce},
	werewolf.KindCupidPair:   {"Ghép đôi", "Chọn hai người thành cặp đôi. Một người chết thì người kia chết theo.", "two_targets", confirmOnce},
	werewolf.KindNominate:    {"Đề cử", "Chọn một người lên giàn. Đổi được tới 17h.", "single_target", ""},
	werewolf.KindVote:        {"Biểu quyết", "Treo hay tha người đang lên giàn. Đổi được tới 22h.", "choice", ""},
}

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
}

// rejectText riêng cho bình cứu: Precheck trả invalid_target khi không ai bị cắn.
func rejectText(kind werewolf.Kind, err error) string {
	if kind == werewolf.KindWitchSave && errors.Is(err, werewolf.ErrInvalidTarget) {
		return "Đêm nay không có ai để cứu."
	}
	if kind == werewolf.KindVote && errors.Is(err, werewolf.ErrNotYourRole) {
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

func phaseLabel(round int, phase werewolf.Phase) string {
	switch phase {
	case werewolf.PhaseSetup:
		return "Chuẩn bị, đêm 1 bắt đầu lúc 22h"
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
