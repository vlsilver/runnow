import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Tin mới nhất người dùng đã đọc của từng chat, chỉ lưu trong máy: đổi máy
/// thì chấm tin mới hiện lại một lần, không mất gì.
class GameChatSeen {
  GameChatSeen({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static String _key(String uid, String gameId, String chatKey) =>
      'masoi_chat_seen_v1_${uid}_${gameId}_$chatKey';

  /// Seq đã đọc, 0 là chưa đọc tin nào. Đọc lỗi trả null để không báo tin mới
  /// sai.
  Future<int?> seen(String uid, String gameId, String chatKey) async {
    try {
      final value = await _storage.read(key: _key(uid, gameId, chatKey));
      return value == null ? 0 : int.tryParse(value) ?? 0;
    } catch (error) {
      debugPrint('Ma Sói: đọc tin đã xem lỗi: $error');
      return null;
    }
  }

  /// Ghi lỗi thì lần sau chấm tin mới vẫn hiện, chat không bị ảnh hưởng.
  Future<void> markSeen(
    String uid,
    String gameId,
    String chatKey,
    int seq,
  ) async {
    try {
      await _storage.write(key: _key(uid, gameId, chatKey), value: '$seq');
    } catch (error) {
      debugPrint('Ma Sói: ghi tin đã xem lỗi: $error');
    }
  }
}

final gameChatSeenProvider = Provider<GameChatSeen>((ref) => GameChatSeen());
