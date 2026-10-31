package backend

import (
	"context"
	"fmt"
	"log/slog"
	"math"
	"net/http"
	"slices"
	"time"

	"cloud.google.com/go/firestore"
)

// Config bot cá nhân mà admin sửa trên trang Admin, cùng doc agentState/config
// với cờ open và allowlist. Đọc ở mỗi task nên sửa xong có hiệu lực từ task kế,
// không cần deploy.
//
// Nhãn, giải thích, đơn vị và khoảng hợp lệ của từng field nằm ở đây chứ không
// ở app: thêm field hay sửa câu giải thích chỉ cần deploy backend, app vẽ theo
// danh sách server trả.

type agentConfigField struct {
	Key   string `json:"key"`
	Label string `json:"label"`
	Help  string `json:"help"`
	// Kind là "int" hoặc "number".
	Kind    string  `json:"kind"`
	Unit    string  `json:"unit"`
	Min     float64 `json:"min"`
	Max     float64 `json:"max"`
	Default float64 `json:"default"`
}

var agentConfigFields = []agentConfigField{
	{
		Key: "dailyBudgetUsd", Label: "Trần tiền AI mỗi ngày", Kind: "number", Unit: "USD/ngày", Min: 0, Max: 1000, Default: 0,
		Help: "Tổng tiền gọi AI (Gemini) trong một ngày giờ VN của mọi bot cá nhân cộng lại: trả lời chat riêng, nói trong phòng bot, tra web và tự học. " +
			"Chạm trần thì mọi bot trả một câu nghỉ tới 0h, admin đã liên kết Telegram nhận một tin báo. " +
			"Tổng có thể vượt trần một chút, vì lượt đang chạy dở lúc chạm trần vẫn chạy xong. " +
			"0 là không giới hạn. Không tính 3i trong group Telegram, coach và vẽ thẻ buổi chạy (có trần riêng). Tiền tính theo bảng giá model bên dưới.",
	},
	{
		Key: "runCardArtDailyBudgetUsd", Label: "Trần tiền vẽ thẻ buổi chạy mỗi ngày", Kind: "number", Unit: "USD/ngày", Min: 0, Max: 1000, Default: runCardArtPool.capDefault,
		Help: "Tổng tiền gọi AI vẽ tranh cho thẻ buổi chạy trong một ngày giờ VN, mọi người cộng lại. Mỗi thẻ vẽ một lần. " +
			"Chạm trần thì lượt vẽ mới báo hết lượt tới 0h, người dùng vẽ lại được hôm sau; admin đã liên kết Telegram nhận một tin báo. " +
			"Tổng có thể vượt trần một chút, vì lượt đang vẽ dở vẫn chạy xong. 0 là không giới hạn. " +
			"Tiền tính theo bảng giá model bên dưới: nhớ khai giá model ảnh, thiếu giá thì tính theo giá dự phòng, thấp hơn giá ảnh thật.",
	},
	{
		Key: "dmDailyMax", Label: "Trần tin bot của mỗi người mỗi ngày", Kind: "int", Unit: "tin/người/ngày", Min: 0, Max: 1000, Default: agentDMDailyMax,
		Help: "Câu sẵn cộng câu thưởng theo km (hai dòng dưới) không vượt quá số này, chạy bao xa cũng vậy. Câu trả lời chat riêng (app, Telegram) và tin bot nói trong phòng bot (app, topic Telegram) trừ chung một lượt. " +
			"Hết lượt thì chat riêng nhận câu nghỉ, trong phòng thì bot im để bot khác nói; 0h giờ VN đếm lại. " +
			"Một câu trả lời gọi AI tối đa 3 lần (khi bot cần nhớ, quên hay tra web), nên đây là chỗ chặn một người tiêu quá nhiều. 0 thì bot chỉ trả câu nghỉ, không gọi AI.",
	},
	{
		Key: "dmBaseDaily", Label: "Tin bot có sẵn mỗi ngày", Kind: "int", Unit: "tin/người/ngày", Min: 0, Max: 1000, Default: agentDMBaseDaily,
		Help: "Bot của mỗi người có sẵn chừng này tin mỗi ngày (giờ VN), chưa cần chạy. Chat riêng và phòng bot, app và Telegram đều đếm chung.",
	},
	{
		Key: "dmPerKm", Label: "Tin bot thêm cho mỗi km chạy", Kind: "int", Unit: "tin/km", Min: 0, Max: 1000, Default: agentDMPerKm,
		Help: "Mỗi km trọn chạy hay đi bộ trong ngày (giờ VN) mở thêm chừng này câu: 4,1 km tính 4 km. Km gồm buổi chạy đã đồng bộ và quãng đường Apple Health tự đồng bộ (lấy số lớn hơn), cùng số km với lượt vẽ ảnh. " +
			"Hết lượt mà còn mốc km thì câu nghỉ của bot chỉ chủ chạy thêm bao nhiêu. 0 là không thưởng theo km.",
	},
	{
		Key: "roomDailyMax", Label: "Tin bot trong phòng mỗi ngày", Kind: "int", Unit: "tin/ngày, cả phòng", Min: 0, Max: 5000, Default: agentRoomDailyMax,
		Help: "Tổng số tin mọi bot được nói trong phòng bot mỗi ngày (giờ VN), dùng chung cho cả phòng. Mỗi tin còn trừ một lượt trong trần tin bot của chủ bot ở trên. " +
			"Hết thì các bot im tới 0h, người vẫn nhắn được. Mỗi tin bot là một lượt gọi AI, có thể kèm một lần tra web. 0 là bot không nói trong phòng.",
	},
	{
		Key: "chainMax", Label: "Số tin bot nói nối nhau", Kind: "int", Unit: "tin sau mỗi tin người", Min: 1, Max: 20, Default: agentChainMax,
		Help: "Sau mỗi tin của người trong phòng bot, các bot được nói tiếp nhau tối đa chừng này tin rồi dừng, chờ người nhắn tiếp. " +
			"Đặt 1 thì mỗi tin người chỉ có một bot đáp. Tăng lên thì phòng rôm rả hơn, nhưng tiền phòng bot tăng gần như theo đúng số này.",
	},
}

// agentPriceFields giải thích từng cột của một dòng llmPrices (xem agentBudgetConfig).
var agentPriceFields = []agentConfigField{
	{Key: "inputPer1M", Label: "Giá input", Unit: "USD / 1M token", Help: "Bắt buộc. Giá mỗi 1 triệu token gửi vào model: lời dặn, lịch sử chat, tính cách, ký ức và kết quả tra web. Lấy ở trang giá Vertex AI, bậc Standard, đúng model."},
	{Key: "outputPer1M", Label: "Giá output", Unit: "USD / 1M token", Help: "Bắt buộc. Giá mỗi 1 triệu token model viết ra."},
	{Key: "thinkingPer1M", Label: "Giá thinking", Unit: "USD / 1M token", Help: "Giá mỗi 1 triệu token model nghĩ trước khi trả lời. Để trống thì tính bằng giá output, đúng cách Vertex đang tính."},
	{Key: "cachedPer1M", Label: "Giá input cache", Unit: "USD / 1M token", Help: "Giá mỗi 1 triệu token input Vertex đọc lại từ cache, thường bằng 1/10 giá input. Để trống thì tính bằng giá input, tức tính dư chứ không tính thiếu."},
	{Key: "searchPerCall", Label: "Phí mỗi lượt tra web", Unit: "USD / lượt", Help: "Phí mỗi lần bot tra Google (grounding). Vertex tính theo lượt tra, không theo token. Để trống là 0."},
}

const (
	agentPriceRowsMax = 10
	agentPriceMax     = 1000
	agentModelNameMax = 100
)

var errAgentConfigChanged = &HTTPError{Status: http.StatusConflict, Code: "config_changed", Message: "Admin khác vừa sửa config, tải lại rồi sửa tiếp."}

func agentConfigInvalid(format string, args ...any) error {
	return &HTTPError{Status: http.StatusBadRequest, Code: "invalid_request", Message: fmt.Sprintf(format, args...)}
}

// agentLimits là các giới hạn đếm theo tin, đọc một lần cho cả task.
type agentLimits struct {
	dmDailyMax, roomDailyMax, chainMax int64
	// dmBase và dmPerKm cùng dmDailyMax tính hạn mức chat riêng theo km (xem
	// agentDMQuota).
	dmBase, dmPerKm int64
}

func defaultAgentLimits() agentLimits {
	return agentLimits{dmDailyMax: agentDMDailyMax, roomDailyMax: agentRoomDailyMax, chainMax: agentChainMax, dmBase: agentDMBaseDaily, dmPerKm: agentDMPerKm}
}

// agentConfigNumber là giá trị đang hiệu lực của field: giá trị đã lưu nếu hợp
// lệ, không thì mặc định. Doc bị sửa tay ra ngoài khoảng thì log và dùng mặc
// định, để một con số gõ sai không tắt hẳn bot hay bỏ hẳn giới hạn.
func agentConfigNumber(ctx context.Context, cfg map[string]any, f agentConfigField) float64 {
	v, ok := cfg[f.Key]
	if !ok {
		return f.Default
	}
	n, isNum := v.(float64)
	if i, isInt := v.(int64); isInt {
		n, isNum = float64(i), true
	}
	if !isNum || validConfigNumber(f, n) != nil {
		slog.WarnContext(ctx, "agent.config_invalid", "key", f.Key, "value", v)
		return f.Default
	}
	return n
}

func validConfigNumber(f agentConfigField, n float64) error {
	if math.IsNaN(n) || math.IsInf(n, 0) || n < f.Min || n > f.Max {
		return agentConfigInvalid("%s phải từ %g tới %g.", f.Label, f.Min, f.Max)
	}
	if f.Kind == "int" && n != math.Trunc(n) {
		return agentConfigInvalid("%s phải là số nguyên.", f.Label)
	}
	return nil
}

func agentConfigFieldByKey(key string) (agentConfigField, bool) {
	i := slices.IndexFunc(agentConfigFields, func(f agentConfigField) bool { return f.Key == key })
	if i < 0 {
		return agentConfigField{}, false
	}
	return agentConfigFields[i], true
}

func parseAgentLimits(ctx context.Context, cfg map[string]any) agentLimits {
	get := func(key string) int64 {
		f, _ := agentConfigFieldByKey(key)
		return int64(agentConfigNumber(ctx, cfg, f))
	}
	return agentLimits{dmDailyMax: get("dmDailyMax"), roomDailyMax: get("roomDailyMax"), chainMax: get("chainMax"), dmBase: get("dmBaseDaily"), dmPerKm: get("dmPerKm")}
}

func (s *AgentStore) configRef() *firestore.DocumentRef {
	return s.db.Collection("agentState").Doc("config")
}

func (s *AgentStore) limits(ctx context.Context) (agentLimits, error) {
	cfg, err := getData(ctx, s.configRef())
	if err != nil {
		return agentLimits{}, err
	}
	return parseAgentLimits(ctx, cfg), nil
}

// agentModelUse là một model bot cá nhân đang chạy và việc nó làm, để admin
// biết phải khai giá cho tên nào.
type agentModelUse struct {
	Model  string `json:"model"`
	Use    string `json:"use"`
	Priced bool   `json:"priced"`
}

type agentConfigValue struct {
	agentConfigField
	// Value nil là chưa đặt, server dùng Default.
	Value *float64 `json:"value"`
}

type agentPriceRow struct {
	Model         string   `json:"model"`
	InputPer1M    *float64 `json:"inputPer1M"`
	OutputPer1M   *float64 `json:"outputPer1M"`
	ThinkingPer1M *float64 `json:"thinkingPer1M"`
	CachedPer1M   *float64 `json:"cachedPer1M"`
	SearchPerCall *float64 `json:"searchPerCall"`
}

func (p agentPriceRow) numbers() map[string]*float64 {
	return map[string]*float64{"inputPer1M": p.InputPer1M, "outputPer1M": p.OutputPer1M, "thinkingPer1M": p.ThinkingPer1M, "cachedPer1M": p.CachedPer1M, "searchPerCall": p.SearchPerCall}
}

type agentUsageToday struct {
	Day         string  `json:"day"`
	CostUsd     float64 `json:"costUsd"`
	Calls       int64   `json:"calls"`
	SearchCalls int64   `json:"searchCalls"`
	BudgetHit   bool    `json:"budgetHit"`
}

type AgentAdminConfig struct {
	Fields      []agentConfigValue `json:"fields"`
	PriceFields []agentConfigField `json:"priceFields"`
	Prices      []agentPriceRow    `json:"prices"`
	Models      []agentModelUse    `json:"models"`
	Usage       agentUsageToday    `json:"usage"`
	// Version là lần admin lưu gần nhất; PATCH gửi lại để không ghi đè bản
	// admin khác vừa lưu. Rỗng là chưa ai lưu.
	Version string `json:"version"`
}

type AgentConfigPatch struct {
	Version string              `json:"version"`
	Values  map[string]*float64 `json:"values"`
	Prices  *[]agentPriceRow    `json:"prices"`
}

func configVersion(cfg map[string]any) string {
	if t, ok := cfg["adminUpdatedAt"].(time.Time); ok {
		return t.UTC().Format(time.RFC3339Nano)
	}
	return ""
}

func optionalNumber(m map[string]any, key string) *float64 {
	if _, ok := m[key]; !ok {
		return nil
	}
	n := number(m[key])
	return &n
}

// AdminConfig trả config cho trang Admin. models là các model bot cá nhân đang
// chạy (lấy từ env của service, api và bot cùng mặc định AGENT_MODEL).
func (s *AgentStore) AdminConfig(ctx context.Context, models []agentModelUse, wall time.Time) (AgentAdminConfig, error) {
	cfg, err := getData(ctx, s.configRef())
	if err != nil {
		return AgentAdminConfig{}, err
	}
	day := agentUsageDay(wall)
	usage, err := getData(ctx, s.db.Collection("agentState").Doc("usage").Collection("days").Doc(day))
	if err != nil {
		return AgentAdminConfig{}, err
	}
	out := AgentAdminConfig{
		Fields: []agentConfigValue{}, PriceFields: agentPriceFields, Prices: []agentPriceRow{}, Models: []agentModelUse{},
		Usage: agentUsageToday{
			Day: day, CostUsd: number(usage["costUsd"]), Calls: int64(number(usage["calls"])),
			SearchCalls: int64(number(usage["searchCalls"])), BudgetHit: usage["budgetHitAt"] != nil,
		},
		Version: configVersion(cfg),
	}
	for _, f := range agentConfigFields {
		out.Fields = append(out.Fields, agentConfigValue{agentConfigField: f, Value: optionalNumber(cfg, f.Key)})
	}
	priced := map[string]bool{}
	for _, v := range anyList(cfg["llmPrices"]) {
		m, _ := v.(map[string]any)
		row := agentPriceRow{Model: stringValue(m["model"])}
		row.InputPer1M, row.OutputPer1M = optionalNumber(m, "inputPer1M"), optionalNumber(m, "outputPer1M")
		row.ThinkingPer1M, row.CachedPer1M = optionalNumber(m, "thinkingPer1M"), optionalNumber(m, "cachedPer1M")
		row.SearchPerCall = optionalNumber(m, "searchPerCall")
		out.Prices = append(out.Prices, row)
		priced[row.Model] = true
	}
	for _, m := range models {
		m.Priced = priced[m.Model]
		out.Models = append(out.Models, m)
	}
	return out, nil
}

// SetAdminConfig lưu các field admin sửa. Giá trị nil đưa field về mặc định;
// prices có mặt thì thay cả bảng giá. Version khác bản đang lưu thì từ chối, để
// trang mở từ trước không ghi đè bản admin khác vừa lưu.
func (s *AgentStore) SetAdminConfig(ctx context.Context, by string, patch AgentConfigPatch, wall time.Time) error {
	update := map[string]any{}
	for key, v := range patch.Values {
		f, ok := agentConfigFieldByKey(key)
		if !ok {
			return agentConfigInvalid("Không có field %s.", key)
		}
		if v == nil {
			update[key] = firestore.Delete
			continue
		}
		if err := validConfigNumber(f, *v); err != nil {
			return err
		}
		update[key] = *v
	}
	if patch.Prices != nil {
		rows, err := priceRowsForStore(*patch.Prices)
		if err != nil {
			return err
		}
		update["llmPrices"] = rows
	}
	if len(update) == 0 {
		return agentConfigInvalid("Không có gì để lưu.")
	}
	update["adminUpdatedAt"], update["adminUpdatedBy"] = wall, by
	err := s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		doc, err := getOptional(tx, s.configRef())
		if err != nil {
			return err
		}
		var cfg map[string]any
		if doc.Exists() {
			cfg = doc.Data()
		}
		if configVersion(cfg) != patch.Version {
			return errAgentConfigChanged
		}
		return tx.Set(s.configRef(), update, firestore.MergeAll)
	})
	if err != nil {
		return err
	}
	values := map[string]any{}
	for key, v := range patch.Values {
		values[key] = nil
		if v != nil {
			values[key] = *v
		}
	}
	slog.InfoContext(ctx, "admin.agent_config_changed", "by", by, "values", values, "prices", patch.Prices != nil)
	return nil
}

// priceRowsForStore kiểm bảng giá rồi đổi sang dạng lưu: cột để trống thì
// không ghi, để parseAgentBudgetConfig lấy giá thay (output cho thinking, input
// cho cache).
func priceRowsForStore(rows []agentPriceRow) ([]any, error) {
	if len(rows) > agentPriceRowsMax {
		return nil, agentConfigInvalid("Tối đa %d dòng giá.", agentPriceRowsMax)
	}
	seen := map[string]bool{}
	out := make([]any, 0, len(rows))
	for _, row := range rows {
		if row.Model == "" || len(row.Model) > agentModelNameMax {
			return nil, agentConfigInvalid("Tên model không được trống và tối đa %d ký tự.", agentModelNameMax)
		}
		if seen[row.Model] {
			return nil, agentConfigInvalid("Model %s có hai dòng giá.", row.Model)
		}
		seen[row.Model] = true
		if row.InputPer1M == nil || row.OutputPer1M == nil {
			return nil, agentConfigInvalid("Model %s phải có giá input và giá output.", row.Model)
		}
		m := map[string]any{"model": row.Model}
		for _, f := range agentPriceFields {
			v := row.numbers()[f.Key]
			if v == nil {
				continue
			}
			if math.IsNaN(*v) || math.IsInf(*v, 0) || *v < 0 || *v > agentPriceMax {
				return nil, agentConfigInvalid("%s của %s phải từ 0 tới %d.", f.Label, row.Model, agentPriceMax)
			}
			m[f.Key] = *v
		}
		out = append(out, m)
	}
	return out, nil
}

// agentModelUses là các model tính tiền theo bảng llmPrices, để admin thấy model
// nào chưa khai giá. Model vẽ thẻ có trần riêng nhưng dùng chung bảng giá, nên
// cũng phải có mặt; thiếu giá thì trần tính theo giá dự phòng, thấp hơn giá ảnh.
func (s *Server) agentModelUses() []agentModelUse {
	out := []agentModelUse{{Model: s.config.AgentModel, Use: "Trả lời chat riêng, nói trong phòng bot và tra web"}}
	if s.config.AgentLearnModel == s.config.AgentModel {
		out[0].Use += ", tự học về người dùng"
	} else {
		out = append(out, agentModelUse{Model: s.config.AgentLearnModel, Use: "Tự học về người dùng"})
	}
	art := s.config.RunCardArtModel
	if art != "" && !slices.ContainsFunc(out, func(u agentModelUse) bool { return u.Model == art }) {
		out = append(out, agentModelUse{Model: art, Use: "Vẽ tranh thẻ buổi chạy"})
	}
	return out
}

func (s *Server) agentConfigRoutes() {
	read := func(w http.ResponseWriter, r *http.Request) error {
		out, err := s.deps.Agents.AdminConfig(r.Context(), s.agentModelUses(), s.now())
		if err != nil {
			return err
		}
		return writeJSON(w, 200, out)
	}
	s.route("GET /v1/admin/agent-config", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		if err := s.deps.Games.RequireAdmin(r.Context(), uid); err != nil {
			return err
		}
		return read(w, r)
	}))
	s.route("PATCH /v1/admin/agent-config", s.authenticated(func(w http.ResponseWriter, r *http.Request, uid string) error {
		if err := s.deps.Games.RequireAdmin(r.Context(), uid); err != nil {
			return err
		}
		var body AgentConfigPatch
		if decodeJSON(r, &body) != nil {
			return invalidRequest()
		}
		if err := s.deps.Agents.SetAdminConfig(r.Context(), uid, body, s.now()); err != nil {
			return err
		}
		return read(w, r)
	}))
}
