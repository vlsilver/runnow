import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Người dùng đã đồng ý quy tắc chat Ma Sói trên máy này chưa. App Store 1.2
/// đòi người dùng đồng ý điều khoản trước khi vào nội dung do người khác gõ.
class GameChatTerms {
  GameChatTerms({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  /// Đổi quy tắc thì đổi khoá để hỏi lại mọi người.
  static const _key = 'masoi_chat_terms_v1';

  final FlutterSecureStorage _storage;

  /// Đọc lỗi thì coi như chưa đồng ý: hỏi lại thì không hại gì.
  Future<bool> accepted() async {
    try {
      return await _storage.read(key: _key) == '1';
    } catch (error) {
      debugPrint('Ma Sói: đọc đồng ý quy tắc chat lỗi: $error');
      return false;
    }
  }

  Future<void> accept() => _storage.write(key: _key, value: '1');
}

final gameChatTermsProvider = Provider<GameChatTerms>((ref) => GameChatTerms());
