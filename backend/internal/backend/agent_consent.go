package backend

import (
	"context"
	"fmt"
	"net/http"
	"slices"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// Đồng ý gửi dữ liệu cho AI: bot cá nhân gửi tin, persona và bộ nhớ của chủ cho
// Google Vertex AI, nên người dùng phải đồng ý bản điều khoản hiện hành trước.
//
//	agents/{uid}/consent/ai   version, at, source (app | backfill)
//
// Nằm ở doc con chứ không phải field trên agents/{uid}: doc cha có mặt nghĩa là
// "đã tạo bot" (Me, requireAgent, DM, ReplyDM, roomAgents đều dựa vào đó), ghi
// field lên đó cho người chưa tạo bot là đẻ ra một bot rỗng. Doc con không làm
// doc cha tồn tại, và vẫn nằm trong cây agents/{uid} nên xoá tài khoản xoá luôn.
//
// Chỉ người vào bằng cờ open mới phải đồng ý. Người trong allowlist thì không,
// vì app 1.5.0 của tester không biết mã consent_required; đòi họ thì chat báo
// lỗi.

// agentAIConsentVersion là bản điều khoản AI đang bắt buộc. Tăng số này khi đổi
// nội dung gửi cho AI (cùng lúc sửa web/terms.html và màn xin phép), người đã
// đồng ý bản cũ sẽ phải đồng ý lại. Để trong code chứ không trong config: bản
// mới luôn đi cùng thay đổi điều khoản phải review, và không ai lỡ tay sửa
// config mà bắt mọi người đồng ý lại.
const agentAIConsentVersion = 1

const (
	agentConsentSourceApp      = "app"
	agentConsentSourceBackfill = "backfill"
)

var (
	// Kèm consentVersion để app hiện màn xin phép rồi gửi đúng bản, khỏi đọc
	// lại GET /v1/agents/me.
	errAgentConsentRequired = &HTTPError{Status: http.StatusForbidden, Code: "consent_required", Message: "Bạn cần đồng ý cho bot gửi dữ liệu tới AI trước khi dùng.", Extra: map[string]any{"consentVersion": agentAIConsentVersion}}
	errAgentConsentVersion  = &HTTPError{Status: http.StatusConflict, Code: "consent_version_mismatch", Message: "Điều khoản đã đổi, mở lại để đọc bản mới.", Extra: map[string]any{"consentVersion": agentAIConsentVersion}}
)

// AgentConsent là phần đồng ý AI trong GET /v1/agents/me và kết quả POST
// /v1/agents/me/consent.
type AgentConsent struct {
	ConsentRequired bool `json:"consentRequired"`
	// ConsentVersion là bản điều khoản đang bắt buộc, app gửi lại số này khi
	// người dùng bấm đồng ý.
	ConsentVersion int `json:"consentVersion"`
}

func (s *AgentStore) consentRef(uid string) *firestore.DocumentRef {
	return s.agentRef(uid).Collection("consent").Doc("ai")
}

// consentRequired: uid phải đồng ý trước khi dùng bot, vì vào bằng cờ open và
// chưa đồng ý bản hiện hành. Người trong allowlist không bao giờ phải, nên không
// tốn thêm lượt đọc nào.
func (s *AgentStore) consentRequired(ctx context.Context, acc agentAccess, uid string) (bool, error) {
	if slices.Contains(acc.members, uid) {
		return false, nil
	}
	doc, err := s.consentRef(uid).Get(ctx)
	if status.Code(err) == codes.NotFound {
		return true, nil
	}
	if err != nil {
		return false, err
	}
	return int(number(doc.Data()["version"])) < agentAIConsentVersion, nil
}

// requireConsent như requireMember, thêm điều kiện đã đồng ý AI. Dùng ở mọi API
// làm dữ liệu của người gọi tới được model.
func (s *AgentStore) requireConsent(ctx context.Context, uid string) error {
	acc, err := s.access(ctx)
	if err != nil {
		return err
	}
	if !acc.allows(uid) {
		return errAgentDisabled
	}
	need, err := s.consentRequired(ctx, acc, uid)
	if err != nil {
		return err
	}
	if need {
		return errAgentConsentRequired
	}
	return nil
}

// RecordConsent ghi uid đồng ý bản version. Chỉ nhận bản hiện hành: app gửi
// bản cũ (màn mở từ trước khi đổi điều khoản) thì báo để app đọc lại. Gửi lại
// lần hai thì giữ nguyên lần đồng ý đầu, nên bấm hai lần không đổi gì.
func (s *AgentStore) RecordConsent(ctx context.Context, uid string, version int, wall time.Time) (AgentConsent, error) {
	if version != agentAIConsentVersion {
		return AgentConsent{}, errAgentConsentVersion
	}
	if err := s.requireMember(ctx, uid); err != nil {
		return AgentConsent{}, err
	}
	ref := s.consentRef(uid)
	err := s.db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		doc, err := tx.Get(ref)
		switch {
		case status.Code(err) == codes.NotFound:
		case err != nil:
			return err
		case int(number(doc.Data()["version"])) >= agentAIConsentVersion:
			return nil
		}
		return tx.Set(ref, map[string]any{"version": agentAIConsentVersion, "at": wall, "source": agentConsentSourceApp})
	})
	if err != nil {
		return AgentConsent{}, err
	}
	return AgentConsent{ConsentVersion: agentAIConsentVersion}, nil
}

// BackfillAIConsent ghi đồng ý bản hiện hành cho allowlist hiện tại, đánh dấu
// source backfill để phân biệt với người tự bấm. Chỉ ghi cho người chưa có bản
// ghi nào, nên chạy lại không đổi gì, và không dùng được để lặng lẽ nâng người
// đã đồng ý bản cũ lên bản mới. Trả uid vừa được ghi.
func (s *AgentStore) BackfillAIConsent(ctx context.Context, wall time.Time) ([]string, error) {
	acc, err := s.access(ctx)
	if err != nil {
		return nil, err
	}
	var set []string
	for _, uid := range acc.members {
		_, err := s.consentRef(uid).Create(ctx, map[string]any{"version": agentAIConsentVersion, "at": wall, "source": agentConsentSourceBackfill})
		if status.Code(err) == codes.AlreadyExists {
			continue
		}
		if err != nil {
			return set, fmt.Errorf("agents/%s/consent/ai: %w", uid, err)
		}
		set = append(set, uid)
	}
	return set, nil
}
