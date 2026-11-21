import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/config.dart';

/// Link mở trang ván trên web 3i (hosting rewrite về app web), nên ai có link
/// cũng vào được kể cả chưa cài app.
Uri gameInviteLink(String gameId) =>
    Uri.parse('${AppConfig.webBaseUrl}/games/${Uri.encodeComponent(gameId)}');

/// Màn cần mở cho link mời vào ván; null nếu không phải link đó.
String? gameLinkLocation(Uri link) {
  final web = Uri.parse(AppConfig.webBaseUrl);
  final path = link.pathSegments;
  if (link.scheme != web.scheme || link.host != web.host) return null;
  if (path.length != 2 || path.first != 'games') return null;
  final id = path.last;
  if (id.isEmpty || id == 'new') return null;
  return '/games/${Uri.encodeComponent(id)}';
}

/// Bấm link mời ở ngoài app thì mở màn ván.
class GameLinkOpener {
  GameLinkOpener(this._links);

  final AppLinks _links;
  bool _started = false;
  StreamSubscription<Uri>? _subscription;

  /// Gọi một lần sau khi đã đăng nhập. Strava và Garmin nghe stream từ lúc mở
  /// app nên link mở app có thể đã phát xong, phải đọc [AppLinks.getInitialLink].
  /// Stream mà vẫn phát lại đúng link đó thì bỏ qua, để không mở ván hai lần.
  Future<void> start(void Function(String location) open) async {
    if (_started) return;
    _started = true;
    void route(Uri link) {
      final location = gameLinkLocation(link);
      if (location != null) open(location);
    }

    Uri? initial;
    try {
      initial = await _links.getInitialLink();
    } catch (error) {
      debugPrint('game link: $error');
    }
    if (initial != null) route(initial);
    _subscription = _links.uriLinkStream.listen((link) {
      if (link == initial) {
        initial = null;
        return;
      }
      route(link);
    }, onError: (Object error) => debugPrint('game link: $error'));
  }

  void dispose() => unawaited(_subscription?.cancel());
}

/// Null trên web: web vào thẳng route theo URL.
final gameLinkOpenerProvider = Provider<GameLinkOpener?>((ref) {
  if (kIsWeb) return null;
  final opener = GameLinkOpener(AppLinks());
  ref.onDispose(opener.dispose);
  return opener;
});
