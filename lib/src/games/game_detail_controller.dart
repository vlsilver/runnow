import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:myrun/src/runnow_api_client.dart';

/// Giữ state màn chi tiết một ván Ma Sói và lo việc làm mới.
///
/// Làm mới khi: mở màn, app quay lại foreground ([setActive]), có push
/// ([refresh]), vừa gửi hành động, và theo lịch: mỗi `refreshAfterSeconds`
/// backend gửi, hoặc sớm hơn nếu deadline + 1 phút tới trước. App ở nền thì
/// không poll.
class GameDetailController extends ChangeNotifier {
  GameDetailController({
    required this._api,
    required this.gameId,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const fallbackPoll = Duration(seconds: 30);

  /// Bước chốt chạy ngay sau deadline; chờ thêm 1 phút rồi mới đọc kết quả.
  static const afterDeadline = Duration(minutes: 1);

  final RunNowApiClient _api;
  final String gameId;
  final DateTime Function() _clock;

  GameDetail? _detail;
  GameMe? _me;
  Object? _error;
  Duration _clockOffset = Duration.zero;

  /// Mọi tin feed đã thấy, theo seq. Feed chỉ ghi thêm, nên giữ cả tin đã
  /// rơi khỏi trang đầu: có tin mới thì trang đầu dời xuống, tin bị đẩy ra
  /// vẫn phải còn nếu trang cũ đã tải trước đó.
  final _feed = <int, GameFeedItem>{};
  bool _olderLoaded = false;
  String? _olderCursor;
  bool _loadingOlder = false;

  bool _active = false;
  bool _disposed = false;
  Future<void>? _inFlight;
  bool _again = false;

  /// Tăng mỗi lần nhận `/me` từ hành động, để refresh đã bắt đầu trước đó
  /// không ghi đè `/me` mới hơn.
  int _meGeneration = 0;
  Timer? _pollTimer;
  Timer? _deadlineTimer;

  GameDetail? get detail => _detail;

  /// null khi người xem chưa đăng ký ván.
  GameMe? get me => _me;

  /// Lỗi của lần làm mới gần nhất; vẫn giữ [detail] cũ để hiện.
  Object? get error => _error;
  bool get loadingOlder => _loadingOlder;

  /// Giờ server ước lượng theo `serverNow` của lần đọc gần nhất, để đếm
  /// ngược không lệch theo đồng hồ máy.
  DateTime serverNow() => _clock().add(_clockOffset);

  /// Đã qua hạn phase: backend báo closing, hoặc dữ liệu đang có đã quá
  /// deadline mà chưa đọc được kết quả.
  bool get phaseClosing {
    final phase = _detail?.phase;
    if (phase == null) return false;
    if (phase.isClosing) return true;
    final deadline = phase.deadline;
    return deadline != null && !serverNow().isBefore(deadline);
  }

  /// Feed mới nhất trước.
  List<GameFeedItem> get feedItems =>
      _feed.values.toList()..sort((a, b) => b.seq.compareTo(a.seq));

  bool get hasOlderFeed =>
      _olderLoaded ? _olderCursor != null : _detail?.feed.cursor != null;

  /// Bật khi màn đang hiện và app ở foreground: làm mới ngay rồi poll. Tắt
  /// thì dừng mọi lịch.
  void setActive(bool active) {
    if (_disposed) return;
    _active = active;
    if (active) {
      unawaited(refresh());
    } else {
      _cancelTimers();
    }
  }

  /// Đọc lại detail (và `/me` nếu đã đăng ký). Gọi chồng thì chỉ chạy thêm
  /// một lượt sau lượt đang chạy.
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
      _schedule();
    }
  }

  Future<void> _fetch() async {
    final meGeneration = _meGeneration;
    try {
      final detail = await _api.getGame(gameId);
      final receivedAt = _clock();
      final me = detail.isRegistered ? await _api.getGameMe(gameId) : null;
      if (_disposed) return;
      _detail = detail;
      _addFeed(detail.feed.items);
      if (meGeneration == _meGeneration) _me = me;
      final serverNow = detail.serverNow;
      _clockOffset = serverNow == null
          ? Duration.zero
          : serverNow.difference(receivedAt);
      _error = null;
    } catch (error, stack) {
      if (_disposed) return;
      debugPrint('Ma Sói: đọc ván $gameId lỗi: $error\n$stack');
      _error = error;
    }
    notifyListeners();
  }

  void _schedule() {
    _cancelTimers();
    if (_disposed || !_active) return;
    final seconds = _detail?.refreshAfterSeconds ?? 0;
    var delay = seconds > 0 ? Duration(seconds: seconds) : fallbackPoll;
    final deadline = _detail?.phase?.deadline;
    if (deadline != null) {
      final untilDeadline = deadline.difference(serverNow());
      if (untilDeadline > Duration.zero) {
        // Vẽ lại đúng lúc hết hạn để hiện "Đang chốt…" thay phase cũ.
        _deadlineTimer = Timer(untilDeadline, notifyListeners);
      }
      final untilResult = untilDeadline + afterDeadline;
      if (untilResult > Duration.zero && untilResult < delay) {
        delay = untilResult;
      }
    }
    _pollTimer = Timer(delay, refresh);
  }

  void _cancelTimers() {
    _pollTimer?.cancel();
    _deadlineTimer?.cancel();
    _pollTimer = null;
    _deadlineTimer = null;
  }

  /// Gửi một hành động. Lỗi (luật từ chối, mạng) ném ra cho màn hình báo.
  Future<void> submitAction({
    required String kind,
    List<String> targets = const [],
    String? choice,
    bool clear = false,
  }) async {
    final me = await _api.submitGameAction(
      gameId,
      kind: kind,
      targets: targets,
      choice: choice,
      clear: clear,
    );
    if (_disposed) return;
    _meGeneration++;
    _me = me;
    notifyListeners();
    unawaited(refresh());
  }

  Future<void> register() async {
    await _api.registerForGame(gameId);
    await refresh();
  }

  Future<void> unregister() async {
    await _api.unregisterFromGame(gameId);
    await refresh();
  }

  /// Tải trang feed cũ hơn. Lỗi ném ra cho màn hình báo; bấm lại là thử lại.
  Future<void> loadOlderFeed() async {
    final cursor = _olderLoaded ? _olderCursor : _detail?.feed.cursor;
    if (cursor == null || _loadingOlder) return;
    _loadingOlder = true;
    notifyListeners();
    try {
      final page = await _api.getGameFeed(gameId, cursor: cursor);
      if (_disposed) return;
      _addFeed(page.items);
      _olderCursor = page.cursor;
      _olderLoaded = true;
    } finally {
      if (!_disposed) {
        _loadingOlder = false;
        notifyListeners();
      }
    }
  }

  void _addFeed(List<GameFeedItem> items) {
    for (final item in items) {
      _feed[item.seq] = item;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelTimers();
    super.dispose();
  }
}
