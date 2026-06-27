/// Backend mặc định cho nền tảng không có dart:io (web). Tracking trực tiếp
/// không dùng trên web nên draft không được lưu — các thao tác là no-op.
class DraftStorage {
  const DraftStorage();

  Future<String?> read() async => null;

  Future<void> write(String data) async {}

  Future<void> clear() async {}
}

DraftStorage createDraftStorage() => const DraftStorage();
