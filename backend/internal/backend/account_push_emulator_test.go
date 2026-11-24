//go:build emulator

package backend

import (
	"context"
	"testing"
	"time"
)

// Xoá tài khoản thì mất cả cài đặt thông báo và mốc push live của người đó;
// của người khác giữ nguyên.
func TestEmulatorAccountDeleteRemovesPushState(t *testing.T) {
	db := emulatorDB(t)
	ctx := context.Background()
	seed(t, db, "pushPrefs/uA", map[string]any{"off": []any{"live"}})
	seed(t, db, "livePushRunners/uA", map[string]any{"activityId": "a1", "at": time.Now()})
	seed(t, db, "pushPrefs/uB", map[string]any{"off": []any{"rank"}})
	accounts := &AccountService{db: db}
	if err := accounts.deleteOwnedDocuments(ctx, "uA", ""); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{"pushPrefs/uA", "livePushRunners/uA"} {
		if snap, _ := db.Doc(path).Get(ctx); snap != nil && snap.Exists() {
			t.Errorf("xoá tài khoản mà còn %s", path)
		}
	}
	if snap, err := db.Doc("pushPrefs/uB").Get(ctx); err != nil || !snap.Exists() {
		t.Fatalf("cài đặt của người khác bị xoá (%v)", err)
	}
}
