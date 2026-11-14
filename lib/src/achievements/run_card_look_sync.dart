import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/providers.dart';

/// Gửi một lượt kiểu thẻ, bộ màu lên backend; khớp
/// `RunNowApiClient.setRunCardLooks`.
typedef SendRunCardLooks =
    Future<void> Function(List<Map<String, String>> looks, {bool fill});

/// Phần kiểu thẻ, bộ màu mà doc thẻ của mình chưa có trong khi máy này đã
/// chọn: thẻ đặt kiểu trước khi app biết gửi lên, và thẻ lật sau đó mặc kiểu
/// mặc định. [localStyleId] trả kiểu máy này giữ cho thẻ, null là không có gì
/// đáng gửi.
List<Map<String, String>> missingRunCardLooks(
  List<RunCard> cards, {
  required String? Function(RunCard card) localStyleId,
  required String? skinId,
}) => [
  for (final card in cards)
    if (card.secret == null)
      if ({
            if (card.lookStyle == null) 'style': ?localStyleId(card),
            if (card.lookSkin == null) 'skin': ?skinId,
          }
          case final look when look.isNotEmpty)
        {'activityId': card.id, ...look},
];

/// Đưa kiểu thẻ và bộ màu chủ thẻ chọn lên backend để người khác thấy thẻ
/// đúng như vậy. Gửi nền, không chặn giao diện: lỗi thì ghi log, lựa chọn vẫn
/// nằm trong máy và người khác thấy bản cũ cho tới lần đặt sau.
class RunCardLookSync {
  RunCardLookSync(this._send);

  /// Giới hạn số thẻ một lượt của backend.
  static const _batch = 100;

  final SendRunCardLooks _send;

  /// Lượt điền bù đã gửi trong phiên, để lượt hỏng không bị gửi lại mãi mỗi
  /// lần danh sách thẻ đổi.
  final _filled = <String>{};

  /// Chủ thẻ vừa đặt [styleId] cho thẻ [cardId].
  Future<void> cardStyle(String cardId, String styleId) => _put([
    {'activityId': cardId, 'style': styleId},
  ]);

  /// Chủ thẻ vừa đổi bộ màu: áp cho mọi thẻ [cardIds] của mình. [skinId] rỗng
  /// là về theo theme của người xem.
  Future<void> skin(Iterable<String> cardIds, String skinId) => _put([
    for (final id in cardIds) {'activityId': id, 'skin': skinId},
  ]);

  /// Điền [looks] (từ [missingRunCardLooks]) vào chỗ doc thẻ còn thiếu.
  Future<void> fill(List<Map<String, String>> looks) => _put([
    for (final look in looks)
      if (_filled.add(look.toString())) look,
  ], fill: true);

  Future<void> _put(
    List<Map<String, String>> looks, {
    bool fill = false,
  }) async {
    try {
      for (var i = 0; i < looks.length; i += _batch) {
        final end = i + _batch < looks.length ? i + _batch : looks.length;
        await _send(looks.sublist(i, end), fill: fill);
      }
    } on Exception catch (error, stack) {
      debugPrint('Không lưu được kiểu thẻ lên backend: $error\n$stack');
    }
  }
}

final runCardLookSyncProvider = Provider<RunCardLookSync>(
  (ref) => RunCardLookSync(
    (looks, {fill = false}) =>
        ref.read(runNowApiClientProvider).setRunCardLooks(looks, fill: fill),
  ),
);
