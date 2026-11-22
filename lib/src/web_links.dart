import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/games/game_links.dart';

/// Đổi một link web 3i ra màn trong app; null nếu link đó không mở trong app.
typedef WebLinkLocator = String? Function(Uri link);

/// Bấm link web 3i ở ngoài app (universal link, app link) thì mở đúng màn.
class WebLinkOpener {
  WebLinkOpener(this._links, this._locate);

  final AppLinks _links;
  final WebLinkLocator _locate;
  bool _started = false;
  StreamSubscription<Uri>? _subscription;

  /// Gọi một lần sau khi đã đăng nhập. Strava và Garmin nghe stream từ lúc mở
  /// app nên link mở app có thể đã phát xong, phải đọc [AppLinks.getInitialLink].
  /// Stream mà vẫn phát lại đúng link đó thì bỏ qua, để không mở màn hai lần.
  Future<void> start(void Function(String location) open) async {
    if (_started) return;
    _started = true;
    void route(Uri link) {
      final location = _locate(link);
      if (location != null) open(location);
    }

    Uri? initial;
    try {
      initial = await _links.getInitialLink();
    } catch (error) {
      debugPrint('web link: $error');
    }
    if (initial != null) route(initial);
    _subscription = _links.uriLinkStream.listen((link) {
      if (link == initial) {
        initial = null;
        return;
      }
      route(link);
    }, onError: (Object error) => debugPrint('web link: $error'));
  }

  void dispose() => unawaited(_subscription?.cancel());
}

/// Null trên web: web vào thẳng route theo URL.
final webLinkOpenerProvider = Provider<WebLinkOpener?>((ref) {
  if (kIsWeb) return null;
  final opener = WebLinkOpener(AppLinks(), gameLinkLocation);
  ref.onDispose(opener.dispose);
  return opener;
});
