//go:build emulator

package backend

import (
	"context"
	"net/http"
	"os"
	"testing"

	"cloud.google.com/go/firestore"
)

// Test có tag emulator chạy bằng backend/scripts/test_emulator.sh. Project là
// demo-*, nên dù env trỏ nhầm cũng không có project thật nào để ghi vào.
const emulatorProject = "demo-runnow"

// emulatorDB trả client nối Firestore emulator, đã xoá sạch dữ liệu của test
// trước. Test trong package này không được chạy t.Parallel vì dùng chung DB.
// Thiếu emulator thì fail chứ không skip: "ok" mà không chạy gì là xanh giả.
func emulatorDB(t *testing.T) *firestore.Client {
	t.Helper()
	host := os.Getenv("FIRESTORE_EMULATOR_HOST")
	if host == "" {
		t.Fatal("thiếu FIRESTORE_EMULATOR_HOST: chạy bằng backend/scripts/test_emulator.sh")
	}
	req, err := http.NewRequest(http.MethodDelete, "http://"+host+"/emulator/v1/projects/"+emulatorProject+"/databases/(default)/documents", nil)
	if err != nil {
		t.Fatal(err)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("xoá dữ liệu emulator: %v", err)
	}
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("xoá dữ liệu emulator: status %d", resp.StatusCode)
	}
	db, err := firestore.NewClient(context.Background(), emulatorProject)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	return db
}

// seed ghi thẳng doc theo đường dẫn "col/doc/col/doc…".
func seed(t *testing.T, db *firestore.Client, path string, data map[string]any) {
	t.Helper()
	if _, err := db.Doc(path).Set(context.Background(), data); err != nil {
		t.Fatalf("ghi %s: %v", path, err)
	}
}
