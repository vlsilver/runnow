import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';

/// Hồ sơ và bộ nhớ bot của người đang đăng nhập; null khi chưa đăng nhập.
/// Cài đặt chỉ đọc `.value` để biết có hiện mục bot không, nên lỗi thì ẩn mục
/// chứ không chặn màn. Không tự retry, giống danh sách ván Ma Sói.
final agentMeProvider = FutureProvider.autoDispose<AgentMe?>(
  retry: (_, _) => null,
  (ref) async {
    final uid = ref.watch(
      firebaseUserProvider.select((user) => user.value?.uid),
    );
    if (uid == null) return null;
    try {
      return await ref.watch(runNowApiClientProvider).getAgentMe();
    } catch (error) {
      debugPrint('Bot: tải hồ sơ bot lỗi: $error');
      rethrow;
    }
  },
);
