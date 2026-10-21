package backend

import (
	"context"
	"log/slog"
	"time"

	"cloud.google.com/go/firestore"
	"google.golang.org/api/iterator"
)

// Chốt kèo tới hạn ở backend: trước đây chỉ chủ kèo bấm "Chốt kết quả" trên app
// mới đóng được, chủ kèo quên là kèo treo active mãi. Chạy NGAY SAU
// RecalcActiveContracts trong cùng job scheduler để chốt theo số BE vừa tính
// (gồm đi bộ + luật 2500 bước). Nút chốt trên app vẫn là đường dự phòng: hai bên
// cùng kiểm status == active trong transaction nên ai tới trước thì thắng.

// ContractFinalizeResult: 1 kèo đã (hoặc sẽ, khi dry-run) được chốt.
type ContractFinalizeResult struct {
	ContractID string  `json:"contractId"`
	Status     string  `json:"status"`
	Progress   float64 `json:"progress"`
	Target     float64 `json:"target"`
	Roast      bool    `json:"roast"`
}

// FinalizeDueContracts chốt mọi kèo active đã qua finalizeAt. [recalced] là kết
// quả của RecalcActiveContracts vừa chạy: kèo nào có participant thiếu kết quả
// (recalc user đó lỗi) thì để lần chạy sau, vì chốt rồi không mở lại được.
// Lỗi Firestore/Cloud Tasks thì trả ra và dừng; chạy lại an toàn vì kèo đã chốt
// không còn active.
func FinalizeDueContracts(ctx context.Context, db *firestore.Client, tasks *TaskPublisher, recalced []ContractRecalcResult, now time.Time, dryRun bool) ([]ContractFinalizeResult, error) {
	it := db.Collection("runContracts").Where("status", "==", "active").Documents(ctx)
	defer it.Stop()
	var results []ContractFinalizeResult
	for {
		doc, err := it.Next()
		if err == iterator.Done {
			break
		}
		if err != nil {
			return results, err
		}
		d := doc.Data()
		if !contractDueForFinalize(d, now) {
			continue
		}
		if !recalcCoversParticipants(doc.Ref.ID, d, recalced) {
			slog.WarnContext(ctx, "contract.finalize_skipped_incomplete_recalc", "contract", doc.Ref.ID)
			continue
		}
		if dryRun {
			// Dry-run recalc không ghi nên doc còn số cũ: chốt thử theo số vừa tính.
			res := finalizeResultFor(doc.Ref.ID, d)
			for _, r := range recalced {
				if r.ContractID == doc.Ref.ID && r.UID == stringValue(d["creatorUid"]) {
					res.Progress = r.NewProgress
					res.Status = contractFinalStatus(stringValue(d["metric"]), res.Progress, res.Target)
				}
			}
			results = append(results, res)
			continue
		}
		res, closed, err := finalizeContract(ctx, db, doc.Ref, now)
		if err != nil {
			return results, err
		}
		if !closed {
			continue // chủ kèo vừa chốt trên app
		}
		if res.Roast && tasks != nil {
			// Cùng TaskID với /v1/contracts/announce-result nên không bêu đôi;
			// bot còn chặn thêm bằng roastedAt. uid = chủ kèo vì bot chỉ nhận
			// lời gọi từ chủ kèo.
			payload := map[string]any{"uid": stringValue(d["creatorUid"]), "contractId": doc.Ref.ID}
			if _, err := tasks.Publish(ctx, PublishTask{Queue: QueueBotInbound, HandlerPath: "/tasks/contract-roast", Payload: payload, TaskID: StableTaskID("roast", doc.Ref.ID)}); err != nil {
				return results, err
			}
		}
		slog.InfoContext(ctx, "contract.finalized", "contract", doc.Ref.ID, "status", res.Status, "progress", res.Progress, "target", res.Target)
		results = append(results, res)
	}
	return results, nil
}

// finalizeContract đóng 1 kèo trong transaction. closed=false nếu lúc đọc lại kèo
// đã không còn active (app chốt trước) — không ghi gì.
func finalizeContract(ctx context.Context, db *firestore.Client, ref *firestore.DocumentRef, now time.Time) (ContractFinalizeResult, bool, error) {
	var res ContractFinalizeResult
	closed := false
	err := db.RunTransaction(ctx, func(ctx context.Context, tx *firestore.Transaction) error {
		closed = false
		snap, err := tx.Get(ref)
		if err != nil {
			return err
		}
		d := snap.Data()
		if !contractDueForFinalize(d, now) {
			return nil
		}
		res = finalizeResultFor(ref.ID, d)
		closed = true
		updates := []firestore.Update{
			{Path: "status", Value: res.Status},
			{Path: "finalizedBy", Value: "scheduler"},
			{Path: "updatedAt", Value: firestore.ServerTimestamp},
		}
		if res.Status == "completed" {
			updates = append(updates, firestore.Update{Path: "completedAt", Value: firestore.ServerTimestamp})
		} else {
			updates = append(updates, firestore.Update{Path: "failedAt", Value: firestore.ServerTimestamp})
		}
		return tx.Update(ref, updates)
	})
	return res, closed, err
}

// finalizeResultFor: kết quả kèo theo tiến độ CHỦ KÈO (progressValue), giống
// app lúc chốt tay. Bêu chỉ áp cho kèo public.
func finalizeResultFor(id string, d map[string]any) ContractFinalizeResult {
	metric := stringValue(d["metric"])
	progress := number(d["progressValue"])
	target := number(d["targetValue"])
	return ContractFinalizeResult{
		ContractID: id,
		Status:     contractFinalStatus(metric, progress, target),
		Progress:   progress,
		Target:     target,
		Roast:      stringValue(d["visibility"]) == "club",
	}
}

// contractDueForFinalize: kèo còn active và đã qua finalizeAt (hết grace đồng bộ).
// Thiếu finalizeAt thì không chốt — không tự suy mốc.
func contractDueForFinalize(d map[string]any, now time.Time) bool {
	if stringValue(d["status"]) != "active" {
		return false
	}
	finalizeAt, ok := d["finalizeAt"].(time.Time)
	if !ok || finalizeAt.IsZero() {
		return false
	}
	return !now.Before(finalizeAt)
}

// contractPeriodEnded: kèo đã qua endAtExclusive (có thể vẫn active vì đang chờ
// chốt). Dùng ở chỗ hiển thị "đang chạy" để không kể kèo đã hết kỳ.
func contractPeriodEnded(d map[string]any, now time.Time) bool {
	end, ok := d["endAtExclusive"].(time.Time)
	return ok && !end.IsZero() && !now.Before(end)
}

func contractFinalStatus(metric string, progress, target float64) string {
	if contractMetTarget(metric, progress, target) {
		return "completed"
	}
	return "failed"
}

// recalcCoversParticipants: mọi participant của kèo đều có kết quả recalc lần này.
// route_completion BE không tính (client khớp tuyến) nên chốt theo số client ghi.
func recalcCoversParticipants(contractID string, d map[string]any, recalced []ContractRecalcResult) bool {
	if stringValue(d["metric"]) == "route_completion" {
		return true
	}
	done := map[string]bool{}
	for _, r := range recalced {
		if r.ContractID == contractID {
			done[r.UID] = true
		}
	}
	parts, _ := d["participants"].(map[string]any)
	for uid := range parts {
		if !done[uid] {
			return false
		}
	}
	return true
}
