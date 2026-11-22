import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:myrun/src/achievements/run_faces/face_map.dart'
    show mapCreditLine;
import 'package:myrun/src/config.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/rooms/live_map.dart';
import 'package:myrun/src/share.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';
import 'package:myrun/src/widgets/live_bits.dart';
import 'package:myrun/src/widgets/map_vector.dart';
import 'package:myrun/src/widgets/route_map.dart'
    show LiveRunnerMarker, routeBounds;
import 'package:myrun/src/widgets/run_now_avatar.dart';
import 'package:share_plus/share_plus.dart';

/// Link màn Live chung trên web 3i.
Uri liveBoardLink() => Uri.parse('${AppConfig.webBaseUrl}/live');

/// Link xem live một người trên web 3i.
Uri liveSessionLink(String sessionId) =>
    Uri.parse('${AppConfig.webBaseUrl}/live/${Uri.encodeComponent(sessionId)}');

/// Màn cần mở cho link live web 3i: màn Live chung hoặc màn xem một người;
/// null nếu không phải link live.
String? liveLinkLocation(Uri link) {
  final web = Uri.parse(AppConfig.webBaseUrl);
  if (link.scheme != web.scheme || link.host != web.host) return null;
  final path = [...link.pathSegments];
  if (path.isNotEmpty && path.last.isEmpty) path.removeLast();
  if (path.isEmpty || path.first != 'live') return null;
  return switch (path.length) {
    1 => '/live',
    2 => '/live/${Uri.encodeComponent(path.last)}',
    _ => null,
  };
}

/// Được khoe buổi live này không. Buổi riêng tư chỉ chủ buổi được khoe, vì
/// người chạy chọn không cho người ngoài thấy vị trí. Buổi phải còn live và có
/// vị trí để ảnh có bản đồ.
bool canShareLive(LiveTrackingSession session, String? uid, DateTime now) =>
    session.isLiveAt(now) &&
    session.lastLocation != null &&
    (session.visibility == LiveTrackingVisibility.club ||
        session.ownerUid == uid);

/// Câu gửi kèm ảnh live một người. Buổi riêng tư (chỉ chủ buổi khoe được) thì
/// không kèm link, vì người nhận ngoài kèo mở ra cũng không xem được.
String liveSessionCaption(LiveTrackingSession session) {
  final line =
      '${session.ownerName} đang chạy live trên 3i: '
      '${formatDistance(session.distanceMeters)}';
  return session.visibility == LiveTrackingVisibility.private
      ? line
      : '$line\n${liveSessionLink(session.id)}';
}

String liveBoardCaption(int runners) =>
    '$runners người đang chạy live trên 3i\n${liveBoardLink()}';

/// Mở sheet xem trước ảnh live một người rồi mới khoe. Sheet cho bản đồ và
/// avatar thời gian tải xong trước khi chụp. Web không gửi được file nên chỉ
/// gửi chữ.
Future<void> showLiveSessionShare(
  BuildContext context,
  LiveTrackingSession session,
) async {
  final caption = liveSessionCaption(session);
  if (kIsWeb) {
    await SharePlus.instance.share(ShareParams(text: caption));
    return;
  }
  await showShareCardSheet(
    context,
    caption: caption,
    fileName: '3i-live.png',
    label: 'Khoe live',
    card: LiveSessionPoster(session: session, at: DateTime.now()),
  );
}

/// Như [showLiveSessionShare] cho cả màn Live: mọi người đang chạy có vị trí.
Future<void> showLiveBoardShare(
  BuildContext context,
  List<LiveTrackingSession> sessions,
) async {
  final placed = [
    for (final s in sessions)
      if (s.lastLocation != null) s,
  ];
  final caption = liveBoardCaption(placed.length);
  if (kIsWeb) {
    await SharePlus.instance.share(ShareParams(text: caption));
    return;
  }
  await showShareCardSheet(
    context,
    caption: caption,
    fileName: '3i-live.png',
    label: 'Khoe live',
    card: LiveBoardPoster(sessions: placed, at: DateTime.now()),
  );
}

/// Ảnh khoe một người đang chạy: bản đồ với đường đã chạy và chấm vị trí,
/// nhãn LIVE kèm giờ chụp, số liệu ở dưới.
class LiveSessionPoster extends StatelessWidget {
  const LiveSessionPoster({required this.session, required this.at, super.key});

  static const size = Size(360, 480);

  final LiveTrackingSession session;

  /// Giờ chụp ảnh, in lên ảnh để người xem biết lúc đó còn đang chạy.
  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final points = liveRoutePoints(session);
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.55);
    return _PosterFrame(
      map: FlutterMap(
        options: MapOptions(
          initialCenter: points.last,
          initialZoom: 15,
          initialCameraFit: points.length < 2
              ? null
              : CameraFit.bounds(
                  bounds: routeBounds(points),
                  padding: const EdgeInsets.fromLTRB(40, 80, 40, 190),
                  maxZoom: 16,
                ),
          backgroundColor: palette.backgroundDeep,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.none,
          ),
        ),
        children: [
          mapBaseLayer(context, dark: dark, around: points),
          PolylineLayer(
            polylines: [
              Polyline(
                points: points,
                color: palette.wash(palette.accent, 0.28),
                strokeWidth: 14,
              ),
              Polyline(
                points: points,
                color: palette.accent,
                strokeWidth: 5,
                borderColor: dark ? palette.backgroundDeep : Colors.white,
                borderStrokeWidth: 1.5,
              ),
            ],
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: points.last,
                width: 64,
                height: 64,
                child: PulsingDot(color: palette.accent),
              ),
            ],
          ),
        ],
      ),
      top: _LiveBadge(at: at),
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(
                name: session.ownerName,
                url: session.ownerAvatarUrl,
                radius: 14,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  session.ownerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: (session.distanceMeters / 1000).toStringAsFixed(2),
                ),
                TextSpan(
                  text: ' km',
                  style: TextStyle(fontSize: 20, color: muted),
                ),
              ],
            ),
            style: TextStyle(
              fontFamily: palette.narrowFont,
              fontSize: 56,
              height: 0.95,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            [
              formatDuration(liveElapsedSeconds(session, at)),
              // Mới chạy chưa có pace thì bỏ hẳn, đừng in "--" lên ảnh.
              if (session.averagePaceSecondsPerKm != null)
                formatPace(session.averagePaceSecondsPerKm),
            ].join(' · '),
            style: TextStyle(
              color: muted,
              fontFamily: palette.narrowFont,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ảnh khoe cả màn Live: avatar mọi người đang chạy trên bản đồ, gộp cụm như
/// màn Live, nhãn LIVE kèm số người và giờ chụp.
class LiveBoardPoster extends StatelessWidget {
  const LiveBoardPoster({required this.sessions, required this.at, super.key});

  static const size = LiveSessionPoster.size;

  /// Chỉ những buổi có vị trí.
  final List<LiveTrackingSession> sessions;
  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final points = [for (final s in sessions) liveAt(s)];
    final around = points.isEmpty
        ? [vietnamBounds.southWest, vietnamBounds.northEast]
        : points;
    return _PosterFrame(
      map: FlutterMap(
        options: MapOptions(
          initialCameraFit: points.length == 1
              ? null
              : CameraFit.coordinates(
                  coordinates: around,
                  padding: const EdgeInsets.fromLTRB(44, 90, 44, 110),
                  maxZoom: 14,
                ),
          initialCenter: points.length == 1
              ? points.single
              : const LatLng(0, 0),
          initialZoom: 14,
          backgroundColor: palette.backgroundDeep,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.none,
          ),
        ),
        children: [
          mapBaseLayer(context, dark: dark, around: around),
          _PosterRunners(sessions: sessions),
        ],
      ),
      top: _LiveBadge(at: at),
      bottom: Text(
        '${sessions.length} người đang chạy',
        style: const TextStyle(
          fontSize: 26,
          height: 1.05,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.4,
        ),
      ),
    );
  }
}

/// Avatar trên ảnh, gộp cụm theo khung đang chụp.
class _PosterRunners extends StatelessWidget {
  const _PosterRunners({required this.sessions});

  final List<LiveTrackingSession> sessions;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    final sorted = [...sessions]..sort((a, b) => a.id.compareTo(b.id));
    return MarkerLayer(
      markers: [
        for (final g in groupNearby(sorted, camera.projectAtZoom))
          Marker(
            point: liveAt(g.first),
            width: 46,
            height: 46,
            child: g.length == 1
                ? LiveRunnerMarker(session: g.first)
                : LiveClusterMarker(lead: g.first, count: g.length),
          ),
      ],
    );
  }
}

/// Khung chung của hai ảnh: bản đồ phủ kín, nhãn trên cùng, tấm chữ dưới đáy
/// và dòng ghi nguồn bản đồ mà giấy phép OpenStreetMap buộc phải có.
class _PosterFrame extends StatelessWidget {
  const _PosterFrame({
    required this.map,
    required this.top,
    required this.bottom,
  });

  final Widget map;
  final Widget top;
  final Widget bottom;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return SizedBox.fromSize(
      size: LiveSessionPoster.size,
      child: ClipRRect(
        borderRadius: palette.radius(24),
        child: Stack(
          children: [
            Positioned.fill(child: map),
            Positioned(left: 16, top: 16, child: top),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.background.withValues(alpha: 0.92),
                  borderRadius: palette.radius(20),
                  border: Border.all(
                    color: palette.border.withValues(alpha: 0.6),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: bottom,
                ),
              ),
            ),
            Positioned(
              right: 14,
              top: 18,
              child: Text(
                mapCreditLine(),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nhãn đỏ "LIVE" kèm giờ chụp.
class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.at});

  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: palette.danger,
            borderRadius: palette.radius(999),
          ),
          child: const Padding(
            padding: EdgeInsets.fromLTRB(10, 5, 12, 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                LiveDot(color: Colors.white),
                SizedBox(width: 6),
                Text(
                  'LIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            color: palette.background.withValues(alpha: 0.88),
            borderRadius: palette.radius(999),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text(
              DateFormat('HH:mm · dd/MM').format(at),
              style: TextStyle(
                fontFamily: palette.narrowFont,
                fontSize: 13,
                fontWeight: FontWeight.w800,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, required this.url, required this.radius});

  final String name;
  final String? url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final hasUrl = url != null && url!.isNotEmpty;
    return RunNowAvatar(
      radius: radius,
      backgroundColor: palette.accent,
      backgroundImage: hasUrl
          ? cachedAvatarImage(context, url!, radius * 2)
          : null,
      child: hasUrl
          ? null
          : Text(
              name.isEmpty ? '?' : name[0].toUpperCase(),
              style: TextStyle(
                color: Colors.white,
                fontSize: radius * 0.8,
                fontWeight: FontWeight.w900,
              ),
            ),
    );
  }
}
