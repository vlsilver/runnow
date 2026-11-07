//go:build emulator

package backend

import (
	"context"
	"testing"
	"time"
)

func TestEmulatorAccountDeleteRemovesHearts(t *testing.T) {
	db := emulatorDB(t)
	at := time.Now()
	for _, path := range []string{
		"hearts/run_uB_a1/by/uA",
		"hearts/live_s1/by/uA",
		"hearts/run_uB_a1/by/uB",
	} {
		seed(t, db, path, map[string]any{"uid": path[len(path)-2:], "at": at})
	}
	accounts := &AccountService{db: db}
	if err := accounts.deleteOwnedDocuments(context.Background(), "uA", ""); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{"hearts/run_uB_a1/by/uA", "hearts/live_s1/by/uA"} {
		if snap, _ := db.Doc(path).Get(context.Background()); snap != nil && snap.Exists() {
			t.Errorf("xoá tài khoản mà còn tim %s", path)
		}
	}
	if snap, err := db.Doc("hearts/run_uB_a1/by/uB").Get(context.Background()); err != nil || !snap.Exists() {
		t.Fatalf("tim của người khác bị xoá (%v)", err)
	}
}
