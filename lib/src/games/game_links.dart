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
