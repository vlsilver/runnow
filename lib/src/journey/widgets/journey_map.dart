import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:myrun/src/journey/journey_models.dart';
import 'package:myrun/src/journey/widgets/completion_stamp.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/route_map.dart'
    show routeBounds, routePointAtDistance;

const _lightTileTemplate =
    'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';
const _darkTileTemplate =
    'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
const _distanceCalculator = Distance();

/// Zoom dùng khi người dùng bấm quay về vị trí hiện tại.
const _regionalZoom = 7.4;

/// Từ ngưỡng zoom này trở lên mới hiện tên mốc đã mở khoá — zoom cả nước
/// (~4-6) mà hiện hết tên sẽ chồng chéo vì nhiều mốc miền Trung rất gần nhau.
const _labelZoomThreshold = 7.2;

/// Bản đồ "Hành Trình" — route thật (road-snapped qua OSRM, xem
/// `journey_models.dart`), không phải hình vẽ tượng trưng: cùng nền tảng
/// flutter_map/OpenStreetMap đang dùng cho bản đồ hoạt động
/// (`widgets/route_map.dart`), chỉ khác polyline nguồn dữ liệu và cách vẽ
/// mốc/vị trí. Lấp đầy toàn bộ khoảng trống được cấp (dùng trong
/// `Positioned.fill`/`Expanded`) — bản đồ là nhân vật chính của màn, không
/// phải 1 card nhỏ giữa danh sách.
class JourneyMap extends StatefulWidget {
  const JourneyMap({
    required this.progress,
    required this.onMilestoneTap,
    required this.onShowInfo,
    super.key,
  });

  final JourneyProgress progress;
  final ValueChanged<JourneyMilestone> onMilestoneTap;

  /// Bấm vào marker vị trí hiện tại HOẶC nút vòng tròn góc bản đồ — mở
  /// thêm thông tin chi tiết hành trình (route, %, mốc kế tiếp...) thay vì
  /// nhồi hết vào 1 popup nổi trên bản đồ (từng đè lên nhãn mốc khác).
  final VoidCallback onShowInfo;

  @override
  State<JourneyMap> createState() => _JourneyMapState();
}

class _JourneyMapState extends State<JourneyMap> {
  final _mapController = MapController();
  double _zoom = _regionalZoom;
  double _rotationDeg = 0;

  LatLng get _currentPosition => routePointAtDistance(
    widget.progress.route.points,
    widget.progress.distanceIntoRouteMeters,
  );

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _recenterOnMe() {
    _mapController.moveAndRotate(_currentPosition, _regionalZoom, 0);
  }

  void _resetRotation() {
    _mapController.rotate(0);
  }

  void _fitWholeRoute() {
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: routeBounds(widget.progress.route.points),
        padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
        maxZoom: 12,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tileTemplate = isDark ? _darkTileTemplate : _lightTileTemplate;
    final route = widget.progress.route;
    final points = route.points;
    final coveredPoints = _coveredPolyline(
      points,
      widget.progress.distanceIntoRouteMeters,
    );
    final remainingOutline = isDark
        ? Colors.white.withValues(alpha: 0.2)
        : Colors.black.withValues(alpha: 0.16);
    final showLabels = _zoom >= _labelZoomThreshold;

    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition,
              initialZoom: _regionalZoom,
              initialCameraFit: points.length > 1
                  ? CameraFit.bounds(
                      bounds: routeBounds(points),
                      padding: const EdgeInsets.fromLTRB(28, 88, 28, 32),
                      maxZoom: 12,
                    )
                  : null,
              minZoom: 4,
              maxZoom: 17,
              backgroundColor: palette.backgroundDeep,
              onMapEvent: (event) {
                final zoomChanged = (event.camera.zoom - _zoom).abs() >= 0.05;
                final rotationChanged =
                    (event.camera.rotation - _rotationDeg).abs() >= 0.5;
                if (!zoomChanged && !rotationChanged) return;
                setState(() {
                  if (zoomChanged) _zoom = event.camera.zoom;
                  if (rotationChanged) _rotationDeg = event.camera.rotation;
                });
              },
              interactionOptions: const InteractionOptions(
                flags:
                    InteractiveFlag.drag |
                    InteractiveFlag.flingAnimation |
                    InteractiveFlag.pinchMove |
                    InteractiveFlag.pinchZoom |
                    InteractiveFlag.doubleTapZoom |
                    InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                key: ValueKey(tileTemplate),
                urlTemplate: tileTemplate,
                userAgentPackageName: 'com.threei.run',
                retinaMode: RetinaMode.isHighDensity(context),
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: points,
                    color: remainingOutline,
                    strokeWidth: 2,
                  ),
                  if (coveredPoints.length > 1)
                    Polyline(
                      points: coveredPoints,
                      color: palette.secondary,
                      strokeWidth: 2.6,
                      borderColor: isDark
                          ? palette.backgroundDeep
                          : Colors.white,
                      borderStrokeWidth: 0.8,
                    ),
                ],
              ),
              // Vị trí hiện tại vẽ TRƯỚC (nằm dưới) mốc — marker mốc + nhãn
              // luôn hiện rõ trên cùng, không bị vòng tròn vị trí đè lên khi
              // 2 điểm trùng nhau (đứng đúng tại 1 mốc).
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentPosition,
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    child: _CurrentPositionMarker(
                      color: palette.secondary,
                      accent: palette.accent,
                      progress: widget.progress,
                      onTap: widget.onShowInfo,
                    ),
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  for (var index = 0; index < route.milestones.length; index++)
                    _milestoneMarker(
                      route.milestones[index],
                      isStart: index == 0,
                      isEnd: index == route.milestones.length - 1,
                      showLabel: showLabels,
                      palette: palette,
                    ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                if (_rotationDeg.abs() > 0.5) ...[
                  _MapControlButton(
                    tooltip: 'Đưa về hướng Bắc',
                    icon: Icons.explore_rounded,
                    iconTurns: -_rotationDeg / 360,
                    onTap: _resetRotation,
                  ),
                  const SizedBox(height: 8),
                ],
                _MapControlButton(
                  tooltip: 'Xem cả hành trình',
                  icon: Icons.zoom_out_map_rounded,
                  onTap: _fitWholeRoute,
                ),
                const SizedBox(height: 8),
                _MapControlButton(
                  tooltip: 'Về vị trí của bạn',
                  icon: Icons.my_location_rounded,
                  onTap: _recenterOnMe,
                ),
                const SizedBox(height: 8),
                _ProgressRingButton(
                  progress: widget.progress,
                  accent: palette.accent,
                  onTap: widget.onShowInfo,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Marker _milestoneMarker(
    JourneyMilestone milestone, {
    required bool isStart,
    required bool isEnd,
    required bool showLabel,
    required RunNowPalette palette,
  }) {
    final isEndpoint = isStart || isEnd;
    final reached = widget.progress.isMilestoneReached(milestone);
    final label = reached && (showLabel || isEndpoint);
    return Marker(
      point: milestone.location,
      width: 130,
      height: label ? 54 : 26,
      alignment: Alignment.topCenter,
      child: GestureDetector(
        onTap: () => widget.onMilestoneTap(milestone),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MilestoneMarker(
              reached: reached,
              isEndpoint: isEndpoint,
              color: isStart
                  ? RunNowSemanticColors.success
                  : isEnd
                  ? RunNowSemanticColors.danger
                  : palette.accent,
            ),
            if (label) ...[
              const SizedBox(height: 3),
              _MilestoneLabel(text: _shortMapLabel(milestone.name)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Danh sách điểm của [points] tính từ đầu tới đúng [meters] mét dọc theo
/// route (nội suy điểm cuối) — dùng để tô đậm đoạn "đã đi" khác màu với
/// phần còn lại, cùng logic đi bộ từng đoạn với `routePointAtDistance`
/// trong `route_map.dart` nhưng trả về cả danh sách thay vì 1 điểm.
List<LatLng> _coveredPolyline(List<LatLng> points, double meters) {
  if (points.isEmpty || meters <= 0) return const [];
  final covered = <LatLng>[points.first];
  var traversed = 0.0;
  for (var index = 1; index < points.length; index++) {
    final start = points[index - 1];
    final end = points[index];
    final segment = _distanceCalculator.distance(start, end);
    if (traversed + segment >= meters) {
      final progress = segment <= 0
          ? 0.0
          : ((meters - traversed) / segment).clamp(0.0, 1.0);
      covered.add(
        LatLng(
          start.latitude + (end.latitude - start.latitude) * progress,
          start.longitude + (end.longitude - start.longitude) * progress,
        ),
      );
      return covered;
    }
    traversed += segment;
    covered.add(end);
  }
  return covered;
}

class _MilestoneMarker extends StatelessWidget {
  const _MilestoneMarker({
    required this.reached,
    required this.isEndpoint,
    required this.color,
  });

  final bool reached;
  final bool isEndpoint;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (!reached) {
      return Semantics(
        label: 'Mốc chưa mở khoá',
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
        ),
      );
    }
    if (isEndpoint) {
      return Semantics(
        label: 'Điểm mốc cực',
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white, width: 1.5),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 6),
            ],
          ),
          child: const Icon(Icons.flag_rounded, color: Colors.white, size: 10),
        ),
      );
    }
    return Semantics(
      label: 'Mốc đã mở khoá',
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
          boxShadow: [
            BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: 5),
          ],
        ),
      ),
    );
  }
}

/// Tên đầy đủ (vd "Tân Kỳ (Km0 đường Hồ Chí Minh)") quá dài để làm nhãn trên
/// bản đồ — chỉ giữ phần trước dấu ngoặc, tên đầy đủ vẫn hiện khi bấm vào
/// mốc (`journey_screen.dart`).
String _shortMapLabel(String name) => name.split(' (').first;

class _MilestoneLabel extends StatelessWidget {
  const _MilestoneLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.tooltip,
    required this.icon,
    required this.onTap,
    this.iconTurns = 0,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  /// Số vòng quay của icon (1.0 = 360°) — dùng để kim la bàn chỉ đúng hướng
  /// Bắc thật khi bản đồ đang xoay.
  final double iconTurns;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: AnimatedRotation(
              turns: iconTurns,
              duration: const Duration(milliseconds: 120),
              child: Icon(icon, color: Colors.white, size: 19),
            ),
          ),
        ),
      ),
    );
  }
}

/// Marker vị trí hiện tại — vòng tiến độ quanh avatar thay vì popup chữ nổi
/// bên trên (từng đè lên nhãn mốc khi bạn đứng đúng tại 1 mốc). Bấm vào để
/// xem thêm thông tin hành trình (`onTap`) thay vì hiện chữ "Bạn" cố định.
class _CurrentPositionMarker extends StatefulWidget {
  const _CurrentPositionMarker({
    required this.color,
    required this.accent,
    required this.progress,
    required this.onTap,
  });

  final Color color;
  final Color accent;
  final JourneyProgress progress;
  final VoidCallback onTap;

  @override
  State<_CurrentPositionMarker> createState() => _CurrentPositionMarkerState();
}

class _CurrentPositionMarkerState extends State<_CurrentPositionMarker>
    with SingleTickerProviderStateMixin {
  late final _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.progress.route.totalLengthMeters;
    final ratio = total <= 0
        ? 0.0
        : (widget.progress.distanceIntoRouteMeters / total).clamp(0.0, 1.0);
    return Semantics(
      button: true,
      label: 'Vị trí hiện tại của bạn — bấm để xem thêm thông tin hành trình',
      child: GestureDetector(
        onTap: widget.onTap,
        child: RepaintBoundary(
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              FadeTransition(
                opacity: Tween<double>(
                  begin: 0.15,
                  end: 0.4,
                ).animate(_pulseController),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: widget.color,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  value: ratio,
                  strokeWidth: 2.4,
                  backgroundColor: Colors.white.withValues(alpha: 0.35),
                  valueColor: AlwaysStoppedAnimation(widget.accent),
                ),
              ),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.6),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.directions_run_rounded,
                  color: Colors.white,
                  size: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nút góc bản đồ hiện % + km/km bằng vòng tròn tiến độ — bấm để xem thêm
/// thông tin hành trình, cùng hành động với bấm vào marker vị trí hiện tại
/// nhưng luôn đứng yên ở góc (không bị mốc khác che hay đè lên).
class _ProgressRingButton extends StatelessWidget {
  const _ProgressRingButton({
    required this.progress,
    required this.accent,
    required this.onTap,
  });

  final JourneyProgress progress;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final total = progress.route.totalLengthMeters;
    final ratio = total <= 0
        ? 0.0
        : (progress.distanceIntoRouteMeters / total).clamp(0.0, 1.0);
    final complete = progress.isComplete;
    return Semantics(
      button: true,
      label: complete
          ? 'Đã hoàn thành hành trình — xem thêm thông tin'
          : 'Xem thêm thông tin hành trình',
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: 56,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: complete
                ? CompletionStamp(accent: accent, size: 40)
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: ratio,
                              strokeWidth: 2.6,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.2,
                              ),
                              valueColor: AlwaysStoppedAnimation(accent),
                            ),
                            Text(
                              '${(ratio * 100).round()}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatCompactKm(progress.distanceIntoRouteMeters),
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '/${formatCompactKm(total)}',
                        maxLines: 1,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
