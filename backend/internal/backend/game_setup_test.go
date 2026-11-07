package backend

import (
	"fmt"
	"reflect"
	"strings"
	"testing"

	"github.com/vlsilver/runnow/backend/internal/werewolf"
)

func setupLines(sections []GameSetupSection) string {
	var b strings.Builder
	for _, s := range sections {
		fmt.Fprintf(&b, "# %s\n", s.Title)
		for _, it := range s.Items {
			sub := ""
			if it.Sub {
				sub = "  "
			}
			fmt.Fprintf(&b, "%s%s = %s [%s]\n", sub, it.Label, it.Value, it.Icon)
		}
	}
	return b.String()
}

// Ván km mới: chỉ hiện cái đang áp; đặc quyền tắt không hiện, dòng con nằm
// dưới thẻ cha, giờ viết "h".
func TestGameSetupKmGame(t *testing.T) {
	var c werewolf.Config
	err := applyGameSettings(&c, map[string]any{
		"extraWolves": 1.0, "elder": true, "darkVote": true, "darkKm": 1.5,
		"vote": "solo", "kmPerUnit": 2.0, "maxHang": 2.0, "seerKm": 1.5,
		"topOn": true, "topWeight": 3.0, "dayMin": 570.0, "trialMin": 150.0,
	})
	if err != nil {
		t.Fatal(err)
	}
	want := `# Vai
Thêm sói = 1 sói []
Già làng = Bật []
# Phe Sói · Đặc quyền hắc ám
Phiếu Đôi = Bật [vote]
Km để mở = 1.5 km []
# Vòng chơi
Số vòng mỗi ngày = 1 vòng []
Độ dài pha Đêm = 2h []
Độ dài pha Rạng sáng = 10h []
Độ dài pha Ngày = 9h30 []
Độ dài pha Biểu quyết = 2h30 []
# Chế độ dùng kỹ năng
Chế độ dùng kỹ năng = Riêng []
# Km mỗi lượt
Biểu quyết = 2 km [vote]
  Treo tối đa mỗi vòng = 2 người []
Bầu cắn = 0 km [wolf]
Soi = 1.5 km [seer]
Che = 1 km [guard]
Dùng thuốc = 1 km [witch]
Bắn khi ngã = 1 km [hunter]
# Đặc quyền phe Dân
Top N được x phiếu = Bật [bolt]
  Số người = Số sói + 1 []
  Phiếu mỗi người = 3 phiếu []
`
	if got := setupLines(gameSetupFor(c)); got != want {
		t.Fatalf("setup:\n%s\nmong đợi:\n%s", got, want)
	}
}

// Ván không dùng km: hết khối km (treo tối đa vẫn áp), không thêm sói thì
// không hiện, lịch tự đặt hiện giờ mở và độ dài vòng.
func TestGameSetupKmOff(t *testing.T) {
	var c werewolf.Config
	err := applyGameSettings(&c, map[string]any{
		"kmOff": true, "startHour": 6.0, "roundHours": 6.0, "roundsPerDay": 3.0,
	})
	if err != nil {
		t.Fatal(err)
	}
	want := `# Kỹ năng
Không dùng km = Bật []
# Lịch
Giờ mở vòng đầu = 6h []
# Vòng chơi
Độ dài một vòng = 6h []
Số vòng mỗi ngày = 3 vòng []
Độ dài pha Đêm = 30 phút []
Độ dài pha Rạng sáng = 2h30 []
Độ dài pha Ngày = 2h30 []
Độ dài pha Biểu quyết = 30 phút []
# Km mỗi lượt
Treo tối đa mỗi vòng = 3 người []
`
	if got := setupLines(gameSetupFor(c)); got != want {
		t.Fatalf("setup:\n%s\nmong đợi:\n%s", got, want)
	}
}

// Tắt Telegram: ván ghi NoTelegram và phần xem lại thiết lập nói rõ là tắt;
// để mặc định (bật) thì không hiện dòng nào.
func TestGameSetupTelegramOff(t *testing.T) {
	var c werewolf.Config
	if err := applyGameSettings(&c, map[string]any{"telegram": false}); err != nil {
		t.Fatal(err)
	}
	if !c.NoTelegram {
		t.Fatal("tắt Telegram mà config vẫn có Telegram")
	}
	if got := setupLines(gameSetupFor(c)); !strings.Contains(got, "# Giao tiếp\nTelegram group = Tắt []\n") {
		t.Fatalf("setup:\n%s", got)
	}
	if got := setupLines(gameSetupFor(werewolf.Config{})); strings.Contains(got, "Telegram") {
		t.Fatalf("Telegram mặc định vẫn hiện:\n%s", got)
	}
}

// Mọi tuỳ chọn đọc lại đúng giá trị đã áp: tuỳ chọn mới thiếu read hay read
// lệch apply thì phần xem lại thiết lập nói sai về ván.
func TestGameSettingsReadBack(t *testing.T) {
	for _, d := range gameSettingDefs {
		if d.read == nil {
			t.Errorf("%s: thiếu read", d.Key)
			continue
		}
		in := map[string]any{"darkCloak": true, "topOn": true}
		var v any
		switch d.Type {
		case settingToggle:
			v = true
		case settingChoice:
			v = d.Choices[len(d.Choices)-1].Value
		case settingRoundPhases:
			v = []any{[]any{60.0, 300.0, 300.0, 60.0}, []any{120.0, 240.0, 240.0, 120.0}}
			in["roundsPerDay"] = 2.0
		default:
			v = *d.Max
		}
		in[d.Key] = v
		for _, cond := range d.EnabledIf {
			if cond.Key == "kmOff" {
				in["kmOff"] = cond.Equals
			}
		}
		var c werewolf.Config
		if err := applyGameSettings(&c, in); err != nil {
			t.Fatalf("%s: %v", d.Key, err)
		}
		if got := d.read(c); !reflect.DeepEqual(got, v) {
			t.Errorf("%s: áp %v, đọc lại %v", d.Key, v, got)
		}
	}
}

// Ván cũ trước luật km giữ tên luật phiếu cũ.
func TestGameSetupLegacyVote(t *testing.T) {
	got := setupLines(gameSetupFor(werewolf.Config{KmPerUnit: 2, Vote: werewolf.VoteTop}))
	if !strings.Contains(got, "Chế độ dùng kỹ năng = Top km được 2 phiếu []\n") || !strings.Contains(got, "Biểu quyết = 2 km [vote]\n") {
		t.Fatalf("setup ván cũ:\n%s", got)
	}
}
