import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';

/// Các ván Ma Sói cho card ở màn Kèo. null khi chưa đăng nhập. Màn Kèo chỉ
/// đọc `.value`, nên API chậm hay lỗi thì không có card chứ list kèo vẫn hiện.
final gameListProvider = FutureProvider.autoDispose<GameList?>((ref) async {
  final uid = ref.watch(firebaseUserProvider.select((user) => user.value?.uid));
  if (uid == null) return null;
  try {
    return await ref.watch(runNowApiClientProvider).listGames();
  } catch (error) {
    debugPrint('Ma Sói: tải danh sách ván lỗi: $error');
    rethrow;
  }
});
