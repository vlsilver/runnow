import 'package:flutter/foundation.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';

/// Chốt kèo. Kèo hẹn thì mở phòng chạy live đúng giờ hẹn trước, rồi ghi phòng
/// vào kèo ngay lúc tạo. Chốt kèo lỗi thì đóng phòng vừa mở, để danh sách phòng
/// công khai không còn phòng hẹn mà không có kèo.
Future<String> createContractWithMeetupRoom(
  RunContractDraft draft, {
  required Future<String> Function(RunContractDraft draft) create,
  required Future<String> Function(DateTime startsAt) openRoom,
  required Future<void> Function(String roomId) closeRoom,
}) async {
  final meetAt = draft.meetAt;
  if (meetAt == null) return create(draft);
  final roomId = await openRoom(meetAt);
  try {
    return await create(draft.copyWith(roomId: roomId));
  } catch (_) {
    try {
      await closeRoom(roomId);
    } catch (error) {
      // Phòng mồ côi tự đóng sau giờ hẹn 6 tiếng; lỗi người dùng cần thấy vẫn
      // là lỗi chốt kèo.
      debugPrint('meetup room $roomId: không đóng được: $error');
    }
    rethrow;
  }
}
