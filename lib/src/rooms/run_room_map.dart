import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';
import 'package:myrun/src/widgets/live_bits.dart';
import 'package:myrun/src/widgets/map_attribution.dart';
import 'package:myrun/src/widgets/map_tiles.dart';
import 'package:myrun/src/widgets/route_map.dart' show routeBounds;

/// Màu từng người trong phòng, theo thứ tự vào map. Chính mình luôn là
/// accent của app.
const runRoomRunnerColors = [
  RunNowDataColors.pace,
  RunNowDataColors.violet,
  RunNowDataColors.energy,
  RunNowSemanticColors.warning,
  RunNowDataColors.heart,
  RunNowDataColors.elevation,
];

Color runRoomRunnerColor(BuildContext context, int index, {required bool me}) =>
    me
    ? context.runNowPalette.accent
    : runRoomRunnerColors[index % runRoomRunnerColors.length];

/// Map của phòng: tuyến chủ phòng vẽ (nét đứt), đường đã chạy và vị trí mới
/// nhất của từng người. Tự canh khung cho thấy hết mọi người khi có người mới
/// xuất hiện; người xem kéo map thì thôi canh lại.
class RunRoomMap extends StatefulWidget {
  const RunRoomMap({
    required this.sessions,
    required this.myUid,
    this.plannedRoute = const [],
    super.key,
  });

  final List<LiveTrackingSession> sessions;
  final String? myUid;
  final List<LatLng> plannedRoute;

  @override
  State<RunRoomMap> createState() => _RunRoomMapState();
}

class _RunRoomMapState extends State<RunRoomMap> {
  final _map = MapController();
  bool _ready = false;
  bool _userMoved = false;
  Set<String> _fittedRunners = const {};

  @override
  void didUpdateWidget(covariant RunRoomMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final runners = {for (final s in widget.sessions) s.ownerUid};
    if (!_userMoved || !runners.containsAll(_fittedRunners)) _fit();
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  List<LatLng> _allPoints() => [
    ...widget.plannedRoute,
    for (final session in widget.sessions) ...liveRoutePoints(session),
  ];

  void _fit() {
    final points = _allPoints();
    if (!_ready || points.isEmpty) return;
    _fittedRunners = {for (final s in widget.sessions) s.ownerUid};
    if (points.length == 1) {
      _map.move(points.single, 16);
      return;
    }
    _map.fitCamera(
      CameraFit.bounds(
        bounds: routeBounds(points),
        padding: const EdgeInsets.all(36),
        maxZoom: 17,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final points = _allPoints();
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: points.isEmpty
            ? const LatLng(21.0285, 105.8542)
            : points.last,
        initialZoom: points.isEmpty ? 11 : 15,
        backgroundColor: palette.tint,
        onMapReady: () {
          _ready = true;
          _fit();
        },
        onPositionChanged: (_, hasGesture) {
          if (hasGesture) _userMoved = true;
        },
      ),
      children: [
        mapTileLayer(context, dark: dark),
        const MapAttribution(),
        PolylineLayer(
          polylines: [
            if (widget.plannedRoute.length >= 2)
              Polyline(
                points: widget.plannedRoute,
                color: palette.accentDeep.withValues(alpha: 0.8),
                strokeWidth: 3,
                pattern: StrokePattern.dashed(segments: const [8, 8]),
              ),
            for (final (i, session) in widget.sessions.indexed)
              Polyline(
                points: liveRoutePoints(session),
                color: runRoomRunnerColor(
                  context,
                  i,
                  me: session.ownerUid == widget.myUid,
                ),
                strokeWidth: 4,
                borderColor: dark ? palette.backgroundDeep : Colors.white,
                borderStrokeWidth: 1.5,
              ),
          ],
        ),
        MarkerLayer(
          markers: [
            for (final (i, session) in widget.sessions.indexed)
              if (session.lastLocation case final at?)
                Marker(
                  point: LatLng(at.latitude, at.longitude),
                  width: 40,
                  height: 40,
                  child: _RunnerDot(
                    session: session,
                    color: runRoomRunnerColor(
                      context,
                      i,
                      me: session.ownerUid == widget.myUid,
                    ),
                  ),
                ),
          ],
        ),
      ],
    );
  }
}

class _RunnerDot extends StatelessWidget {
  const _RunnerDot({required this.session, required this.color});

  final LiveTrackingSession session;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final url = session.ownerAvatarUrl;
    final initial = session.ownerName.trim().isEmpty
        ? '?'
        : session.ownerName.trim().characters.first.toUpperCase();
    return Tooltip(
      message: session.ownerName,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 3),
          color: Theme.of(context).colorScheme.surface,
        ),
        child: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.25),
          foregroundImage: url == null || url.isEmpty
              ? null
              : cachedAvatarImage(context, url, 34),
          child: Text(
            initial,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }
}
