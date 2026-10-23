import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/widgets/photo_viewer.dart';

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

/// Phòng bot nhìn từ tab MyBot: hai tin mới nhất không bị ẩn (cũ trước mới
/// sau) và tên các bot trong phòng, để tab vẽ chồng avatar và đếm.
typedef AgentRoomPreview = ({
  List<AgentRoomMessage> messages,
  List<String> bots,
});

/// Đọc một lần mỗi lần mở tab, không poll; muốn xem tiếp thì vào phòng.
final agentRoomPreviewProvider = FutureProvider.autoDispose<AgentRoomPreview>(
  retry: (_, _) => null,
  (ref) async {
    final page = await ref.watch(runNowApiClientProvider).getAgentRoom();
    return (
      messages: page.messages
          .where((m) => !m.hidden)
          .take(2)
          .toList()
          .reversed
          .toList(),
      bots: [for (final m in page.members) ?m.botName],
    );
  },
);

/// Người mình đã chặn trong phòng bot, cho màn bỏ chặn.
final agentBlocksProvider = FutureProvider.autoDispose<List<AgentBlocked>>(
  retry: (_, _) => null,
  (ref) => ref.watch(runNowApiClientProvider).getAgentBlocks(),
);

/// Số ảnh bot đã vẽ hiện trên tab MyBot.
const agentImagePreviewCount = 6;

/// Ảnh mới nhất bot đã vẽ cho tab MyBot; đọc một lần mỗi lần mở tab. Lỗi
/// (kể cả backend cũ chưa có API này) thì tab ẩn mục ảnh, không chặn gì.
final agentImagesPreviewProvider = FutureProvider.autoDispose<List<AgentImage>>(
  retry: (_, _) => null,
  (ref) async {
    try {
      final page = await ref
          .watch(runNowApiClientProvider)
          .getAgentImages(limit: agentImagePreviewCount);
      return page.images;
    } catch (error) {
      debugPrint('Bot: tải ảnh bot vẽ lỗi: $error');
      rethrow;
    }
  },
);

/// Dựng ảnh bot vẽ theo đường dẫn Storage: ô nhỏ thì giải mã thu nhỏ, [full]
/// là xem cả màn hình, phóng to được. Test thay để khỏi gọi Firebase.
final agentImageBuilderProvider =
    Provider<Widget Function(String path, {required bool full})>(
      (ref) =>
          (path, {required full}) => full
          ? StoragePhoto(path: path, fit: BoxFit.contain, interactive: true)
          : StoragePhoto(path: path, cacheWidth: 400),
    );
