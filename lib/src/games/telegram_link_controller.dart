import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:url_launcher/url_launcher.dart';

typedef UrlOpener = Future<bool> Function(Uri uri);

/// Liên kết tài khoản app với Telegram (L1). App lấy mã, mở
/// `t.me/<bot>?start=<mã>`; người dùng bấm Start trong DM, api ghi liên kết.
/// App không biết lúc nào việc đó xong, nên poll `GET /telegram/link` 3 giây
/// một lần trong 2 phút, và đọc lại khi app quay về foreground.
class TelegramLinkController extends ChangeNotifier {
  TelegramLinkController({required this._api, UrlOpener? openUrl})
    : _openUrl = openUrl ?? _launch;

  static const pollEvery = Duration(seconds: 3);
  static const pollFor = Duration(minutes: 2);

  final RunNowApiClient _api;
  final UrlOpener _openUrl;

  TelegramLinkStatus? _status;
  Object? _error;
  bool _busy = false;
  Timer? _poll;
  bool _disposed = false;

  /// null khi chưa đọc được lần nào.
  TelegramLinkStatus? get status => _status;
  Object? get error => _error;
  bool get busy => _busy;

  /// Đang chờ người dùng bấm Start bên Telegram.
  bool get waiting => _poll != null;

  /// Web mở trong tab hiện tại như kết nối Strava (`auth.dart`), vì mở tab mới
  /// sau một lần chờ API thì trình duyệt chặn popup. Quay lại thì trang tải
  /// lại và đọc trạng thái liên kết từ đầu.
  static Future<bool> _launch(Uri uri) => kIsWeb
      ? launchUrl(
          uri,
          mode: LaunchMode.platformDefault,
          webOnlyWindowName: '_self',
        )
      : launchUrl(uri, mode: LaunchMode.externalApplication);

  Future<void> load() async {
    try {
      final status = await _api.getTelegramLink();
      if (_disposed) return;
      _status = status;
      _error = null;
      if (status.linked) _stopPolling();
    } catch (error) {
      if (_disposed) return;
      debugPrint('Telegram: đọc trạng thái liên kết lỗi: $error');
      _error = error;
    }
    notifyListeners();
  }

  /// App quay về foreground: có thể người dùng vừa bấm Start bên Telegram.
  void onResume() {
    if (_status?.linked != true) unawaited(load());
  }

  /// Lấy mã rồi mở Telegram. Lỗi ném ra cho màn hình báo.
  Future<void> link() => _run(() async {
    final code = await _api.createTelegramLinkCode();
    if (!await _openUrl(Uri.parse(code.deepLink))) {
      throw StateError('Không mở được Telegram.');
    }
    _startPolling();
  });

  /// Huỷ liên kết. Backend từ chối (409 in_game) khi đang trong ván.
  Future<void> unlink() => _run(() async {
    await _api.unlinkTelegram();
    _stopPolling();
    _status = TelegramLinkStatus.fromJson(const {});
  });

  Future<void> _run(Future<void> Function() body) async {
    _busy = true;
    notifyListeners();
    try {
      await body();
    } finally {
      if (!_disposed) {
        _busy = false;
        notifyListeners();
      }
    }
  }

  void _startPolling() {
    _stopPolling();
    var left = pollFor.inSeconds ~/ pollEvery.inSeconds;
    _poll = Timer.periodic(pollEvery, (_) {
      if (--left <= 0) _stopPolling();
      unawaited(load());
    });
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPolling();
    super.dispose();
  }
}
