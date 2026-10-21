import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';

/// Hồ sơ và bộ nhớ bot của người đang đăng nhập; null khi chưa đăng nhập.
/// Thanh tab chỉ đọc `.value` để biết có hiện tab MyBot không, nên lỗi thì giữ
/// bộ tab cũ chứ không chặn màn. Không tự retry, giống danh sách ván Ma Sói.
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

/// Có hiện tab MyBot không. Chỉ người được mời (`enabled`) mới thấy; chưa tải
/// xong hay tải lỗi thì giữ bộ tab cũ, nên lỗi API không làm mất tab nào.
bool myBotTabVisible(WidgetRef ref) =>
    ref.watch(agentMeProvider).value?.enabled ?? false;

/// Hai tin mới nhất của phòng bot, cũ trước mới sau, cho tab MyBot. Chỉ đọc một
/// lần mỗi lần mở tab, không poll; muốn xem tiếp thì vào phòng.
final agentRoomPreviewProvider =
    FutureProvider.autoDispose<List<AgentRoomMessage>>(retry: (_, _) => null, (
      ref,
    ) async {
      final page = await ref.watch(runNowApiClientProvider).getAgentRoom();
      return page.messages.take(2).toList().reversed.toList();
    });
