import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:myrun/src/runnow_api_client.dart';

/// Giữ state một chat phe (Phe Sói, Cặp đôi) và poll tin mới.
///
/// Màn chat đang mở thì poll trang mới nhất mỗi [pollEvery]. Một trang có
/// 30 tin, mà mỗi người gửi tối đa 1 tin/giây và phe chỉ vài người, nên giữa
/// hai lần poll không thể có quá một trang tin mới: gộp theo seq là đủ, không
/// sót tin.
class GameChatController extends ChangeNotifier {
  GameChatController({
    required this._api,
    required this.gameId,
    required this.chatKey,
  });

  static const pollEvery = Duration(seconds: 5);

  final RunNowApiClient _api;
  final String gameId;
  final String chatKey;

  final _messages = <int, GameChatMessage>{};
  String? _label;
  bool _canSend = false;
  bool _loaded = false;
  Object? _error;
  bool _hasOlder = false;
  bool _olderLoaded = false;
  bool _loadingOlder = false;

  bool _active = false;
  bool _disposed = false;
  Future<void>? _inFlight;
  bool _again = false;
  Timer? _pollTimer;

  /// Tên chat backend gửi; null khi chưa tải xong lần đầu.
  String? get label => _label;
  bool get canSend => _canSend;
  bool get loaded => _loaded;

  /// Lỗi của lần tải gần nhất; tin đã có vẫn giữ để hiện.
  Object? get error => _error;
  bool get hasOlder => _hasOlder;
  bool get loadingOlder => _loadingOlder;

  /// Tin mới trước.
  List<GameChatMessage> get messages =>
      _messages.values.toList()..sort((a, b) => b.seq.compareTo(a.seq));

  /// Bật khi màn đang hiện và app ở foreground: tải ngay rồi poll. Tắt thì
  /// dừng poll.
  void setActive(bool active) {
    if (_disposed) return;
    _active = active;
    if (active) {
      unawaited(refresh());
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  /// Đọc trang mới nhất. Gọi chồng thì chỉ chạy thêm một lượt sau lượt đang
  /// chạy, để tin vừa gửi chắc chắn có trong lượt đọc sau đó.
  Future<void> refresh() {
    if (_disposed) return Future.value();
    final running = _inFlight;
    if (running != null) {
      _again = true;
      return running;
    }
    return _inFlight = _refreshLoop();
  }

  Future<void> _refreshLoop() async {
    try {
      do {
        _again = false;
        await _fetch();
      } while (_again && !_disposed);
    } finally {
      _inFlight = null;
      _pollTimer?.cancel();
      if (!_disposed && _active) _pollTimer = Timer(pollEvery, refresh);
    }
  }

  Future<void> _fetch() async {
    try {
      final page = await _api.getGameChat(gameId, chatKey);
      if (_disposed) return;
      _apply(page);
      if (!_olderLoaded) _hasOlder = page.cursor != null;
      _loaded = true;
      _error = null;
    } catch (error, stack) {
      if (_disposed) return;
      debugPrint('Ma Sói: đọc chat $chatKey của $gameId lỗi: $error\n$stack');
      _error = error;
    }
    notifyListeners();
  }

  void _apply(GameChat page) {
    _label = page.label;
    _canSend = page.canSend;
    for (final m in page.messages) {
      _messages[m.seq] = m;
    }
  }

  /// Gửi tin rồi đọc lại. Lỗi (chỉ đọc, gửi dồn, mạng) ném ra cho màn hình
  /// báo; tin chưa gửi được thì màn hình giữ lại trong ô nhập.
  Future<void> send(String text) async {
    try {
      await _api.postGameChat(gameId, chatKey, text);
    } on RunNowApiException catch (error) {
      // Vừa chết hay ván vừa hết: đọc lại để ẩn ô nhập.
      if (error.code == 'chat_read_only') unawaited(refresh());
      rethrow;
    }
    await refresh();
  }

  /// Tải trang cũ hơn tin cũ nhất đang có. Lỗi ném ra cho màn hình báo.
  Future<void> loadOlder() async {
    if (!_hasOlder || _loadingOlder || _messages.isEmpty) return;
    final oldest = _messages.keys.reduce((a, b) => a < b ? a : b);
    _loadingOlder = true;
    notifyListeners();
    try {
      final page = await _api.getGameChat(gameId, chatKey, cursor: '$oldest');
      if (_disposed) return;
      _apply(page);
      _hasOlder = page.cursor != null;
      _olderLoaded = true;
    } finally {
      if (!_disposed) {
        _loadingOlder = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    super.dispose();
  }
}
