import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:myrun/src/agents/agent_models.dart';

typedef AgentPageLoader<M extends AgentSeqMessage> =
    Future<AgentChatPage<M>> Function({String? cursor, int? after});

/// Giữ state một chat của bot (chat riêng hoặc phòng bot) và poll tin mới,
/// cùng nhịp với chat phe Ma Sói: lần đầu đọc trang mới nhất, sau đó mỗi
/// [pollEvery] đọc các tin sau seq lớn nhất đang có.
class AgentChatController<M extends AgentSeqMessage> extends ChangeNotifier {
  AgentChatController({
    required this.load,
    required this.post,
    required this.label,
  });

  /// Bot trả lời sau vài giây, phòng bot nói cách nhau 6 giây: 4 giây đủ để
  /// thấy tin gần như ngay mà không gọi dồn.
  static const pollEvery = Duration(seconds: 4);

  final AgentPageLoader<M> load;
  final Future<void> Function(String text) post;

  /// Dùng trong log.
  final String label;

  final _messages = <int, M>{};
  bool _loaded = false;
  Object? _error;
  bool _hasOlder = false;
  String? _olderCursor;
  bool _loadingOlder = false;
  bool _waiting = false;
  List<AgentRoomMember> _members = const [];

  bool _active = false;
  bool _disposed = false;
  Future<void>? _inFlight;
  bool _again = false;
  Timer? _pollTimer;

  bool get loaded => _loaded;
  Object? get error => _error;
  bool get hasOlder => _hasOlder;
  bool get loadingOlder => _loadingOlder;

  /// Chat riêng: bot chưa trả lời tin cuối của chủ.
  bool get waiting => _waiting;
  List<AgentRoomMember> get members => _members;

  /// Tin mới trước.
  List<M> get messages =>
      _messages.values.toList()..sort((a, b) => b.seq.compareTo(a.seq));

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
        final page = await load();
        if (_disposed) return;
        _apply(page);
        _olderCursor = page.cursor;
        _hasOlder = page.cursor != null;
        _loaded = true;
      } else {
        final newest = _messages.isEmpty
            ? 0
            : _messages.keys.reduce((a, b) => a > b ? a : b);
        final page = await load(after: newest);
        if (_disposed) return;
        _apply(page);
        if (page.hasNewer) _again = true;
      }
      _error = null;
    } catch (error, stack) {
      if (_disposed) return;
      debugPrint('Bot: đọc $label lỗi: $error\n$stack');
      _error = error;
    }
    notifyListeners();
  }

  void _apply(AgentChatPage<M> page) {
    _waiting = page.waiting;
    // Poll không có tin mới thì backend không gửi danh sách: giữ bản cũ.
    if (page.members.isNotEmpty) _members = page.members;
    for (final m in page.messages) {
      _messages[m.seq] = m;
    }
  }

  /// Gửi tin rồi đọc lại. Lỗi ném ra cho màn hình báo; chữ chưa gửi được thì
  /// màn hình giữ trong ô nhập.
  Future<void> send(String text) async {
    await post(text);
    await refresh();
  }

  Future<void> loadOlder() async {
    final cursor = _olderCursor;
    if (!_hasOlder || _loadingOlder || cursor == null) return;
    _loadingOlder = true;
    notifyListeners();
    try {
      final page = await load(cursor: cursor);
      if (_disposed) return;
      for (final m in page.messages) {
        _messages[m.seq] = m;
      }
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
