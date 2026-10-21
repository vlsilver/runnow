import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:myrun/src/runnow_api_client.dart';

/// Giữ state một chat phe (Phe Sói, Cặp đôi) và poll tin mới.
///
/// Lần đầu đọc trang mới nhất. Sau đó màn chat đang mở thì mỗi [pollEvery]
/// đọc các tin sau seq lớn nhất đang có (`after`), còn tin mới hơn thì đọc
/// tiếp ngay. App vào nền hay mất mạng lâu, lúc quay lại vẫn lấp đủ đoạn giữa.
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
  String? _olderCursor;
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

  /// Tin mới trước, bỏ tin của người đã chặn.
  List<GameChatMessage> get messages =>
      _messages.values.where((m) => !m.hidden).toList()
        ..sort((a, b) => b.seq.compareTo(a.seq));

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
      if (!_loaded) {
        final page = await _api.getGameChat(gameId, chatKey);
        if (_disposed) return;
        _apply(page);
        _olderCursor = page.cursor;
        _hasOlder = page.cursor != null;
        _loaded = true;
      } else {
        final newest = _messages.isEmpty
            ? 0
            : _messages.keys.reduce((a, b) => a > b ? a : b);
        final page = await _api.getGameChat(gameId, chatKey, after: newest);
        if (_disposed) return;
        _apply(page);
        if (page.hasNewer) _again = true;
      }
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

  /// Báo cáo tin cho admin; [block] thì ẩn luôn mọi tin của người gửi ngay
  /// trên máy, không chờ lần đọc sau. Lỗi ném ra cho màn hình báo.
  Future<void> report(GameChatMessage message, {required bool block}) async {
    await _api.reportGameChat(gameId, chatKey, message.seq, block: block);
    if (!block || _disposed) return;
    for (final m in _messages.values.toList()) {
      if (m.uid == message.uid && !m.system) _messages[m.seq] = m.asHidden();
    }
    notifyListeners();
  }

  /// Tải trang cũ hơn theo cursor backend trả. Lỗi ném ra cho màn hình báo.
  Future<void> loadOlder() async {
    final cursor = _olderCursor;
    if (!_hasOlder || _loadingOlder || cursor == null) return;
    _loadingOlder = true;
    notifyListeners();
    try {
      final page = await _api.getGameChat(gameId, chatKey, cursor: cursor);
      if (_disposed) return;
      _apply(page);
      _olderCursor = page.cursor;
      _hasOlder = page.cursor != null;
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
