import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/live_route_view.dart';
import 'package:myrun/src/widgets/photo_pin_marker.dart';

const _lightTileTemplate =
    'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';
const _darkTileTemplate =
    'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
const _photoClusterThresholdMeters = 15.0;
const _photoClusterDistance = Distance();

class _PhotoCluster {
  _PhotoCluster(this.anchor, this.photos);

  final LatLng anchor;
  final List<ActivityPhoto> photos; // sắp mới nhất trước.
}

/// Gộp các ảnh chụp gần nhau (cùng ngưỡng với `LiveRouteView`) thành 1 marker
/// kèm badge "+N", để bản đồ nhỏ ở màn chi tiết kèo nhất quán với màn live
/// thay vì chồng nhiều marker rời rạc lên nhau.
List<_PhotoCluster> _clusterPhotos(List<ActivityPhoto> photos) {
  final sorted = [...photos]
    ..sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
  final clusters = <_PhotoCluster>[];
  for (final photo in sorted) {
    final point = LatLng(photo.latitude, photo.longitude);
    final existing = clusters
        .where(
          (cluster) =>
              _photoClusterDistance.distance(cluster.anchor, point) <=
              _photoClusterThresholdMeters,
        )
        .firstOrNull;
    if (existing != null) {
      existing.photos.add(photo);
    } else {
      clusters.add(_PhotoCluster(point, [photo]));
    }
  }
  return clusters;
}

class RouteMap extends StatelessWidget {
  const RouteMap({
    required this.encodedPolyline,
    this.routePoints,
    this.photos = const [],
    this.onPhotoTap,
    this.highlightedDistanceMeters,
    this.totalDistanceMeters,
    this.liveRunners = const [],
    this.liveRunnersStream,
    this.liveRoutePhotos = const [],
    this.height = 330,
    super.key,
  });

  const RouteMap.fromRoutePoints({
    required List<RoutePoint> points,
    this.height = 330,
    this.photos = const [],
    this.onPhotoTap,
    this.highlightedDistanceMeters,
    this.totalDistanceMeters,
    this.liveRunners = const [],
    this.liveRunnersStream,
    this.liveRoutePhotos = const [],
    super.key,
  }) : encodedPolyline = null,
       routePoints = points;

  final String? encodedPolyline;
  final List<RoutePoint>? routePoints;
  final double height;
  final List<ActivityPhoto> photos;
  final ValueChanged<ActivityPhoto>? onPhotoTap;
  final double? highlightedDistanceMeters;
  final double? totalDistanceMeters;
  final List<LiveTrackingSession> liveRunners;

  /// Nguồn live tiếp tục cập nhật vị trí/ảnh trong lúc màn full màn hình
  /// đang mở — [liveRunners] chỉ là snapshot tại thời điểm bấm mở, còn
  /// stream này (nếu có) mới giữ cho màn full màn hình sống động thay vì
  /// đứng yên suốt lúc xem. Không bắt buộc — null thì full màn hình chỉ
  /// hiện đúng snapshot lúc mở, như trước. Khác null còn quyết định mở
  /// [LiveRouteView] (bản đồ live có overlay số liệu) thay vì
  /// `_FullscreenRouteMap` thường (xem [_openFullscreen]).
  final Stream<List<LiveTrackingSession>>? liveRunnersStream;

  /// Ảnh kèm định danh người chụp, chỉ dùng khi mở [LiveRouteView] (cần
  /// hiện avatar/tên đúng người trong caption ảnh) — [photos] (phẳng, không
  /// chủ ảnh) vẫn dùng cho bản đồ preview nhỏ + `_FullscreenRouteMap` như
  /// cũ, không đổi.
  final List<LiveRoutePhoto> liveRoutePhotos;

  @override
  Widget build(BuildContext context) {
    final points = _mapPoints();
    if (points.isEmpty) {
      return const GlassPanel(
        borderRadius: 0,
        child: SizedBox(
          height: 180,
          child: Center(child: Text('Không có dữ liệu route.')),
        ),
      );
    }
    return ClipRect(
      child: SizedBox(
        height: height,
        child: Stack(
          children: [
            Positioned.fill(
              child: _FlutterRouteMap(
                points: points,
                photos: photos,
                onPhotoTap: onPhotoTap,
                highlightedDistanceMeters: highlightedDistanceMeters,
                totalDistanceMeters: totalDistanceMeters,
                liveRunners: liveRunners,
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: liveRunnersStream != null
                  ? _ViewLiveButton(
                      onTap: () => _openFullscreen(context, points),
                    )
                  : _MapExpandButton(
                      onTap: () => _openFullscreen(context, points),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _openFullscreen(BuildContext context, List<LatLng> points) {
    final liveStream = liveRunnersStream;
    if (liveStream != null) {
      Navigator.of(context).push(
        PageRouteBuilder<void>(
          fullscreenDialog: true,
          opaque: true,
          pageBuilder: (context, _, _) => LiveRouteView(
            points: points,
            liveRunners: liveRunners,
            liveRunnersStream: liveStream,
            claimedPhotos: liveRoutePhotos,
          ),
        ),
      );
      return;
    }
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        fullscreenDialog: true,
        opaque: true,
        pageBuilder: (context, _, _) => _FullscreenRouteMap(
          points: points,
          photos: photos,
          onPhotoTap: onPhotoTap,
          highlightedDistanceMeters: highlightedDistanceMeters,
          totalDistanceMeters: totalDistanceMeters,
          liveRunners: liveRunners,
          liveRunnersStream: liveRunnersStream,
        ),
      ),
    );
  }

  List<LatLng> _mapPoints() {
    final directPoints = routePoints;
    if (directPoints != null && directPoints.isNotEmpty) {
      return directPoints
          .map((point) => LatLng(point.latitude, point.longitude))
          .toList();
    }
    final encoded = encodedPolyline;
    if (encoded == null || encoded.isEmpty) return const <LatLng>[];
    return decodePolyline(encoded);
  }
}

class _MapExpandButton extends StatelessWidget {
  const _MapExpandButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Phóng to bản đồ toàn màn hình',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: const Icon(
              Icons.open_in_full_rounded,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}

/// Thay [_MapExpandButton] ở bất kỳ đâu caller có truyền [liveRunnersStream]
/// (hiện chỉ kèo theo tuyến) — hiện luôn, bất kể tại thời điểm đó có ai
/// đang chạy live hay chưa, vì bấm vào vẫn luôn mở đúng full màn hình có
/// khả năng hiện live (vị trí + ảnh cập nhật liên tục ngay khi có người bắt
/// đầu chạy), cùng kiểu chấm đỏ nhấp nháy đã dùng cho nút "LIVE NOW".
class _ViewLiveButton extends StatefulWidget {
  const _ViewLiveButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_ViewLiveButton> createState() => _ViewLiveButtonState();
}

class _ViewLiveButtonState extends State<_ViewLiveButton>
    with SingleTickerProviderStateMixin {
  late final _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Xem live vị trí và ảnh đang chạy',
      child: RepaintBoundary(
        child: Material(
          color: Colors.transparent,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: RunNowSemanticColors.danger,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FadeTransition(
                      opacity: Tween<double>(
                        begin: 0.4,
                        end: 1,
                      ).animate(_pulseController),
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Xem live',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Bản đồ route phóng to toàn màn hình, khóa xoay ngang trong lúc mở — dùng
/// chung cho mọi nơi hiển thị [RouteMap] (chi tiết hoạt động, chi tiết kèo,
/// tracking, club, xác nhận tuyến) vì đều đi qua đúng 1 điểm mở duy nhất
/// này thay vì tự cài đặt riêng lẻ ở từng màn.
class _FullscreenRouteMap extends StatefulWidget {
  const _FullscreenRouteMap({
    required this.points,
    required this.photos,
    required this.onPhotoTap,
    required this.highlightedDistanceMeters,
    required this.totalDistanceMeters,
    required this.liveRunners,
    required this.liveRunnersStream,
  });

  final List<LatLng> points;
  final List<ActivityPhoto> photos;
  final ValueChanged<ActivityPhoto>? onPhotoTap;
  final double? highlightedDistanceMeters;
  final double? totalDistanceMeters;
  final List<LiveTrackingSession> liveRunners;
  final Stream<List<LiveTrackingSession>>? liveRunnersStream;

  @override
  State<_FullscreenRouteMap> createState() => _FullscreenRouteMapState();
}

class _FullscreenRouteMapState extends State<_FullscreenRouteMap> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: widget.liveRunnersStream == null
                ? _FlutterRouteMap(
                    points: widget.points,
                    photos: widget.photos,
                    onPhotoTap: widget.onPhotoTap,
                    highlightedDistanceMeters: widget.highlightedDistanceMeters,
                    totalDistanceMeters: widget.totalDistanceMeters,
                    liveRunners: widget.liveRunners,
                  )
                : StreamBuilder<List<LiveTrackingSession>>(
                    stream: widget.liveRunnersStream,
                    initialData: widget.liveRunners,
                    builder: (context, snapshot) {
                      final sessions = snapshot.data ?? widget.liveRunners;
                      final displayPhotos = {
                        for (final photo in widget.photos) photo.id: photo,
                        for (final session in sessions)
                          for (final photo in session.livePhotos)
                            photo.id: photo,
                      }.values.toList();
                      return _FlutterRouteMap(
                        points: widget.points,
                        photos: displayPhotos,
                        onPhotoTap: widget.onPhotoTap,
                        highlightedDistanceMeters:
                            widget.highlightedDistanceMeters,
                        totalDistanceMeters: widget.totalDistanceMeters,
                        liveRunners: sessions,
                      );
                    },
                  ),
          ),
          Positioned(
            top: 12,
            left: 12,
            child: SafeArea(
              child: IconButton.filledTonal(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FlutterRouteMap extends StatefulWidget {
  const _FlutterRouteMap({
    required this.points,
    required this.photos,
    required this.onPhotoTap,
    required this.highlightedDistanceMeters,
    required this.totalDistanceMeters,
    required this.liveRunners,
  });

  final List<LatLng> points;
  final List<ActivityPhoto> photos;
  final ValueChanged<ActivityPhoto>? onPhotoTap;
  final double? highlightedDistanceMeters;
  final double? totalDistanceMeters;
  final List<LiveTrackingSession> liveRunners;

  @override
  State<_FlutterRouteMap> createState() => _FlutterRouteMapState();
}

class _FlutterRouteMapState extends State<_FlutterRouteMap> {
  final _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _scheduleFitBounds();
  }

  @override
  void didUpdateWidget(covariant _FlutterRouteMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // `MapOptions.initialCameraFit` chỉ được flutter_map áp dụng đúng 1 lần
    // lúc tạo controller — nếu widget này build lần đầu trước khi `points`
    // load xong (dễ xảy ra hơn trên web do thứ tự tải dữ liệu khác app gốc),
    // camera bị kẹt ở lần fit đầu tiên dù `points` sau đó đã đủ, khiến bản
    // đồ hiện đúng tile nhưng không zoom vào tuyến đường. Chủ động fit lại
    // mỗi khi `points` thực sự đổi để không phụ thuộc thời điểm build đầu.
    if (!listEquals(oldWidget.points, widget.points)) {
      _scheduleFitBounds();
    }
  }

  void _scheduleFitBounds() {
    if (widget.points.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: routeBounds(widget.points),
          padding: const EdgeInsets.all(28),
          maxZoom: 16,
        ),
      );
    });
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.points;
    final photos = widget.photos;
    final onPhotoTap = widget.onPhotoTap;
    final highlightedDistanceMeters = widget.highlightedDistanceMeters;
    final totalDistanceMeters = widget.totalDistanceMeters;
    final liveRunners = widget.liveRunners;
    final palette = context.runNowPalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileTemplate = isDark ? _darkTileTemplate : _lightTileTemplate;
    final routeOutline = isDark
        ? Colors.black.withValues(alpha: 0.5)
        : Colors.white.withValues(alpha: 0.88);
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: routeBounds(points),
          padding: const EdgeInsets.all(28),
          maxZoom: 16,
        ),
        minZoom: 3,
        maxZoom: 18,
        backgroundColor: palette.backgroundDeep,
        interactionOptions: const InteractionOptions(
          flags:
              InteractiveFlag.drag |
              InteractiveFlag.flingAnimation |
              InteractiveFlag.pinchMove |
              InteractiveFlag.pinchZoom |
              InteractiveFlag.doubleTapZoom,
        ),
      ),
      children: [
        TileLayer(
          key: ValueKey(tileTemplate),
          urlTemplate: tileTemplate,
          userAgentPackageName: 'com.threeaeidiot.runnow',
          retinaMode: RetinaMode.isHighDensity(context),
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: points,
              color: routeOutline,
              strokeWidth: 6.5,
              borderStrokeWidth: 0,
            ),
            Polyline(
              points: points,
              color: palette.secondary,
              strokeWidth: 3.5,
              borderColor: isDark ? palette.backgroundDeep : Colors.white,
              borderStrokeWidth: 1.5,
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            _routeMarker(
              point: points.first,
              // Xanh lá/đỏ tương phản mạnh, không phụ thuộc ramp màu theme —
              // trước đó dùng secondary/accent (2 bậc liền kề trong ramp)
              // nhìn gần như cùng màu, khó phân biệt bắt đầu/kết thúc.
              color: RunNowSemanticColors.success,
              icon: Icons.play_arrow_rounded,
              semanticLabel: 'Điểm bắt đầu',
            ),
            _routeMarker(
              point: points.last,
              color: RunNowSemanticColors.danger,
              icon: Icons.sports_score_rounded,
              semanticLabel: 'Điểm kết thúc',
            ),
            for (final cluster in _clusterPhotos(photos))
              Marker(
                point: cluster.anchor,
                width: 40,
                height: photoPinVisibleHeight,
                alignment: Alignment.topCenter,
                child: GestureDetector(
                  onTap: onPhotoTap == null
                      ? null
                      : () => onPhotoTap(cluster.photos.first),
                  child: PhotoPinMarker(
                    storagePath: cluster.photos.first.storagePath,
                    extraCount: cluster.photos.length - 1,
                  ),
                ),
              ),
            if (highlightedDistanceMeters case final distance?)
              Marker(
                point: routePointAtActivityDistance(
                  points,
                  selectedDistanceMeters: distance,
                  activityDistanceMeters: totalDistanceMeters,
                ),
                width: 38,
                height: 38,
                child: _TelemetryMapMarker(color: palette.accent),
              ),
            for (final runner in liveRunners)
              if (runner.lastLocation case final location?)
                Marker(
                  point: LatLng(location.latitude, location.longitude),
                  width: 42,
                  height: 42,
                  child: _LiveRunnerMarker(session: runner),
                ),
          ],
        ),
      ],
    );
  }
}

class _TelemetryMapMarker extends StatelessWidget {
  const _TelemetryMapMarker({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Vị trí đang chọn trên biểu đồ',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 12),
          ],
        ),
        child: Center(
          child: Container(
            width: 13,
            height: 13,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

class _LiveRunnerMarker extends StatefulWidget {
  const _LiveRunnerMarker({required this.session});

  final LiveTrackingSession session;

  @override
  State<_LiveRunnerMarker> createState() => _LiveRunnerMarkerState();
}

class _LiveRunnerMarkerState extends State<_LiveRunnerMarker>
    with SingleTickerProviderStateMixin {
  late final _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = widget.session.ownerAvatarUrl;
    final ownerName = widget.session.ownerName;
    return Semantics(
      label: '$ownerName đang chạy live',
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: RunNowSemanticColors.info, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: RunNowSemanticColors.info.withValues(alpha: 0.45),
                  blurRadius: 10,
                ),
              ],
            ),
            child: ClipOval(
              child: avatarUrl == null || avatarUrl.isEmpty
                  ? ColoredBox(
                      color: RunNowSemanticColors.info,
                      child: SizedBox(
                        width: 38,
                        height: 38,
                        child: Center(
                          child: Text(
                            ownerName.isEmpty
                                ? '?'
                                : ownerName[0].toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    )
                  : Image(
                      image: cachedAvatarImage(context, avatarUrl, 38),
                      width: 38,
                      height: 38,
                      fit: BoxFit.cover,
                    ),
            ),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: RepaintBoundary(
              child: FadeTransition(
                opacity: Tween<double>(
                  begin: 0.35,
                  end: 1,
                ).animate(_pulseController),
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: RunNowSemanticColors.info,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Marker _routeMarker({
  required LatLng point,
  required Color color,
  required IconData icon,
  required String semanticLabel,
}) {
  final foreground = color.computeLuminance() > 0.55
      ? Colors.black87
      : Colors.white;
  return Marker(
    point: point,
    width: 32,
    height: 32,
    child: Semantics(
      label: semanticLabel,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.42), blurRadius: 10),
          ],
        ),
        child: Icon(icon, color: foreground, size: 18),
      ),
    ),
  );
}

RouteCamera routeCameraPosition(List<LatLng> points) {
  final bounds = routeBounds(points);
  final latitudeSpan = bounds.north - bounds.south;
  final longitudeSpan = bounds.east - bounds.west;
  final span = math.max(latitudeSpan, longitudeSpan);
  final zoom = span <= 0
      ? 15.0
      : (math.log(360 / span) / math.ln2 - 1.4).clamp(8.0, 16.0);
  return RouteCamera(center: bounds.simpleCenter, zoom: zoom);
}

LatLng routePointAtDistance(List<LatLng> points, double distanceMeters) {
  if (points.isEmpty) throw ArgumentError.value(points, 'points');
  if (points.length == 1 || distanceMeters <= 0) return points.first;
  var traversed = 0.0;
  for (var index = 1; index < points.length; index++) {
    final start = points[index - 1];
    final end = points[index];
    final segment = _distanceMeters(start, end);
    if (traversed + segment >= distanceMeters) {
      if (segment <= 0) return end;
      final progress = ((distanceMeters - traversed) / segment).clamp(0.0, 1.0);
      return LatLng(
        start.latitude + (end.latitude - start.latitude) * progress,
        start.longitude + (end.longitude - start.longitude) * progress,
      );
    }
    traversed += segment;
  }
  return points.last;
}

LatLng routePointAtActivityDistance(
  List<LatLng> points, {
  required double selectedDistanceMeters,
  required double? activityDistanceMeters,
}) {
  if (activityDistanceMeters == null || activityDistanceMeters <= 0) {
    return routePointAtDistance(points, selectedDistanceMeters);
  }
  final routeDistance = routeLengthMeters(points);
  final progress = (selectedDistanceMeters / activityDistanceMeters).clamp(
    0.0,
    1.0,
  );
  return routePointAtDistance(points, routeDistance * progress);
}

double routeLengthMeters(List<LatLng> points) {
  var total = 0.0;
  for (var index = 1; index < points.length; index++) {
    total += _distanceMeters(points[index - 1], points[index]);
  }
  return total;
}

double _distanceMeters(LatLng start, LatLng end) {
  const earthRadiusMeters = 6371000.0;
  final latitudeDelta = (end.latitude - start.latitude) * math.pi / 180;
  final longitudeDelta = (end.longitude - start.longitude) * math.pi / 180;
  final startLatitude = start.latitude * math.pi / 180;
  final endLatitude = end.latitude * math.pi / 180;
  final a =
      math.sin(latitudeDelta / 2) * math.sin(latitudeDelta / 2) +
      math.cos(startLatitude) *
          math.cos(endLatitude) *
          math.sin(longitudeDelta / 2) *
          math.sin(longitudeDelta / 2);
  return earthRadiusMeters * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

class RouteCamera {
  const RouteCamera({required this.center, required this.zoom});

  final LatLng center;
  final double zoom;
}

LatLngBounds routeBounds(List<LatLng> points) {
  return LatLngBounds.fromPoints(points);
}

List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  var index = 0;
  var latitude = 0;
  var longitude = 0;
  while (index < encoded.length) {
    final lat = _decodeValue(encoded, index);
    index = lat.$2;
    final lng = _decodeValue(encoded, index);
    index = lng.$2;
    latitude += lat.$1;
    longitude += lng.$1;
    points.add(LatLng(latitude / 1e5, longitude / 1e5));
  }
  return points;
}

(int, int) _decodeValue(String encoded, int start) {
  var index = start;
  var result = 0;
  var shift = 0;
  int byte;
  do {
    byte = encoded.codeUnitAt(index++) - 63;
    result |= (byte & 0x1f) << shift;
    shift += 5;
  } while (byte >= 0x20);
  return ((result & 1) == 1 ? ~(result >> 1) : result >> 1, index);
}
