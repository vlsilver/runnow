package backend

import "testing"

func TestSoloContractIsDeletedWhenOwnerLeaves(t *testing.T) {
	contract := map[string]any{"participantUids": []any{"u1"}}
	if got := remainingParticipants(contract, "u1"); got != 0 {
		t.Fatalf("remaining = %d, want 0", got)
	}
}

func TestGroupContractSurvivesWhenOthersRemain(t *testing.T) {
	// Kèo nhiều người là dữ liệu chung: xoá tài khoản của một người không
	// được kéo theo tiến độ của những người còn lại.
	contract := map[string]any{"participantUids": []any{"u1", "u2", "u3"}}
	if got := remainingParticipants(contract, "u1"); got != 2 {
		t.Fatalf("remaining = %d, want 2", got)
	}
}

func TestContractWithoutParticipantListIsDeletable(t *testing.T) {
	// Kèo cũ thiếu participantUids thì không ai truy vấn ra được nữa, nên
	// coi như rỗng thay vì để lại rác vĩnh viễn.
	if got := remainingParticipants(map[string]any{}, "u1"); got != 0 {
		t.Fatalf("remaining = %d, want 0", got)
	}
}
