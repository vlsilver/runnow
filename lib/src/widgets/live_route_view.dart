import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';
import 'package:myrun/src/widgets/photo_pin_marker.dart';
import 'package:myrun/src/widgets/photo_viewer.dart';

const _liveRouteTileTemplate =
    'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
const _clusterThresholdMeters = 15.0;
const _distance = Distance();

/// 1 ảnh chụp trong lúc chạy live, kèm định danh người chụp. [RouteMap] dùng
/// chung chỉ giữ 1 list `ActivityPhoto` phẳng (không có chủ ảnh), nhưng màn
/// xem live theo dõi nhiều người cùng lúc nên caption ảnh cần biết đúng ai
/// chụp — type riêng này giữ thêm 3 field đó thay vì sửa `ActivityPhoto`
/// dùng chung khắp nơi.
class LiveRoutePhoto {
  const LiveRoutePhoto({
    required this.photo,
    required this.ownerUid,
    required this.ownerName,
    this.ownerAvatarUrl,
  });

  final ActivityPhoto photo;
  final String ownerUid;
  final String ownerName;
  final String? ownerAvatarUrl;
}

class _PhotoCluster {
  _PhotoCluster(this.anchor, this.photos);

  final LatLng anchor;
  final List<LiveRoutePhoto> photos; // sắp mới nhất trước.
}

/// Màn xem live full màn hình, khoá xoay ngang — bản đồ + overlay số liệu
/// người đang chạy (theo `features/design_handoff_live_route_view/README.md`).
/// Tách hẳn khỏi `_FullscreenRouteMap` (route_map.dart) vì các màn khác dùng
/// chung widget đó (chi tiết hoạt động, tracking, club, xác nhận tuyến)
/// không cần overlay/chip/cluster — chỉ riêng lối vào "Xem live" từ kèo theo
/// tuyến mới cần độ phức tạp này.
class LiveRouteView extends StatefulWidget {
  const LiveRouteView({
    required this.points,
    required this.liveRunners,
    required this.liveRunnersStream,
    required this.claimedPhotos,
    super.key,
  });

  final List<LatLng> points;
  final List<LiveTrackingSession> liveRunners;
  final Stream<List<LiveTrackingSession>> liveRunnersStream;
  final List<LiveRoutePhoto> claimedPhotos;

  @override
  State<LiveRouteView> createState() => _LiveRouteViewState();
}

class _LiveRouteViewState extends State<LiveRouteView> {
  final MapController _mapController = MapController();
  Timer? _tick;
  String? _focusedUid;
  bool _overlayExpanded = false;
  bool _autoFollow = true;
  LatLng? _lastFollowedLocation;
  List<LiveRoutePhoto>? _viewerSet;
  int _viewerIndex = 0;

  @override
  void initState() {
    super.initState();
    _focusedUid = widget.liveRunners.isNotEmpty
        ? widget.liveRunners.first.ownerUid
        : null;
    // "Cập nhật Xs trước" là chuỗi tương đối, cần tick lại định kỳ để không
    // bị đứng yên/cũ dù không có dữ liệu mới từ stream.
    _tick = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _focusRunner(String uid) {
    setState(() {
      _focusedUid = uid;
      _autoFollow = true;
      _lastFollowedLocation = null;
    });
  }

  void _openPhotoViewer(List<LiveRoutePhoto> set, int index) {
    setState(() {
      _viewerSet = set;
      _viewerIndex = index;
    });
  }

  void _closePhotoViewer() => setState(() => _viewerSet = null);

  List<_PhotoCluster> _clusterPhotos(List<LiveRoutePhoto> photos) {
    final sorted = [...photos]
      ..sort((a, b) => b.photo.capturedAt.compareTo(a.photo.capturedAt));
    final clusters = <_PhotoCluster>[];
    for (final item in sorted) {
      final point = LatLng(item.photo.latitude, item.photo.longitude);
      final existing = clusters
          .where(
            (cluster) =>
                _distance.distance(cluster.anchor, point) <=
                _clusterThresholdMeters,
          )
          .firstOrNull;
      if (existing != null) {
        existing.photos.add(item);
      } else {
        clusters.add(_PhotoCluster(point, [item]));
      }
    }
    return clusters;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: StreamBuilder<List<LiveTrackingSession>>(
        stream: widget.liveRunnersStream,
        initialData: widget.liveRunners,
        builder: (context, snapshot) {
          final sessions = snapshot.data ?? widget.liveRunners;
          final livePhotos = [
            for (final session in sessions)
              for (final photo in session.livePhotos)
                LiveRoutePhoto(
                  photo: photo,
                  ownerUid: session.ownerUid,
                  ownerName: session.ownerName,
                  ownerAvatarUrl: session.ownerAvatarUrl,
                ),
          ];
          final allPhotos = {
            for (final item in widget.claimedPhotos) item.photo.id: item,
            for (final item in livePhotos) item.photo.id: item,
          }.values.toList();
          final clusters = _clusterPhotos(allPhotos);

          LiveTrackingSession? focused;
          for (final session in sessions) {
            if (session.ownerUid == _focusedUid) {
              focused = session;
              break;
            }
          }
          focused ??= sessions.isNotEmpty ? sessions.first : null;

          if (_autoFollow && focused?.lastLocation != null) {
            final target = LatLng(
              focused!.lastLocation!.latitude,
              focused.lastLocation!.longitude,
            );
            if (_lastFollowedLocation == null ||
                _distance.distance(_lastFollowedLocation!, target) > 1) {
              _lastFollowedLocation = target;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                try {
                  _mapController.move(target, _mapController.camera.zoom);
                } catch (_) {
                  // Map chưa init xong ở frame đầu — bỏ qua, cập nhật kế
                  // tiếp sẽ tự thử lại.
                }
              });
            }
          }

          return Stack(
            children: [
              Positioned.fill(
                child: _LiveMap(
                  mapController: _mapController,
                  points: widget.points,
                  sessions: sessions,
                  focusedUid: focused?.ownerUid,
                  clusters: clusters,
                  onPhotoPinTap: (cluster) =>
                      _openPhotoViewer(cluster.photos, 0),
                  onUserGesture: () {
                    if (_autoFollow) setState(() => _autoFollow = false);
                  },
                  onRunnerTap: _focusRunner,
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                child: SafeArea(
                  child: _CircleIconButton(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              if (sessions.length > 1)
                Positioned(
                  top: 12,
                  right: 12,
                  child: SafeArea(
                    child: _RunnerChipRow(
                      sessions: sessions,
                      focusedUid: focused?.ownerUid,
                      onTap: _focusRunner,
                    ),
                  ),
                ),
              if (focused != null)
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: SafeArea(
                    child: _StatsOverlay(
                      session: focused,
                      expanded: _overlayExpanded,
                      onToggle: () =>
                          setState(() => _overlayExpanded = !_overlayExpanded),
                    ),
                  ),
                ),
              if (focused != null && !_autoFollow)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: SafeArea(
                    child: _CircleIconButton(
                      icon: Icons.my_location_rounded,
                      iconColor: RunNowSemanticColors.info,
                      onTap: () => setState(() => _autoFollow = true),
                    ),
                  ),
                ),
              if (_viewerSet != null)
                Positioned.fill(
                  child: _LivePhotoViewer(
                    photos: _viewerSet!,
                    initialIndex: _viewerIndex,
                    onClose: _closePhotoViewer,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    required this.onTap,
    this.iconColor = Colors.white,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
      ),
    );
  }
}

class _RunnerChipRow extends StatelessWidget {
  const _RunnerChipRow({
    required this.sessions,
    required this.focusedUid,
    required this.onTap,
  });

  final List<LiveTrackingSession> sessions;
  final String? focusedUid;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final session in sessions) ...[
          _RunnerChip(
            session: session,
            focused: session.ownerUid == focusedUid,
            onTap: () => onTap(session.ownerUid),
          ),
          if (session != sessions.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _RunnerChip extends StatelessWidget {
  const _RunnerChip({
    required this.session,
    required this.focused,
    required this.onTap,
  });

  final LiveTrackingSession session;
  final bool focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final avatarUrl = session.ownerAvatarUrl;
    return GestureDetector(
      onTap: onTap,
      child: Semantics(
        button: true,
        label: 'Xem live của ${session.ownerName}',
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: focused
                      ? RunNowSemanticColors.danger
                      : Colors.white.withValues(alpha: 0.25),
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: _avatarOrInitial(avatarUrl, session.ownerName, 34),
              ),
            ),
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 1.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _avatarOrInitial(String? avatarUrl, String name, double diameter) {
  if (avatarUrl == null || avatarUrl.isEmpty) {
    return ColoredBox(
      color: RunNowSemanticColors.info,
      child: SizedBox(
        width: diameter,
        height: diameter,
        child: Center(
          child: Text(
            name.isEmpty ? '?' : name[0].toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
  return Builder(
    builder: (context) => Image(
      image: cachedAvatarImage(context, avatarUrl, diameter),
      width: diameter,
      height: diameter,
      fit: BoxFit.cover,
    ),
  );
}

class _StatsOverlay extends StatelessWidget {
  const _StatsOverlay({
    required this.session,
    required this.expanded,
    required this.onToggle,
  });

  final LiveTrackingSession session;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: 300,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.9),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    ClipOval(
                      child: _avatarOrInitial(
                        session.ownerAvatarUrl,
                        session.ownerName,
                        34,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            session.ownerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: RunNowSemanticColors.danger,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _relativeUpdateLabel(session.updatedAt),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (!expanded) ...[
                      const SizedBox(width: 8),
                      Text(
                        _formatKm(session.distanceMeters),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: Colors.white.withValues(alpha: 0.4),
                      size: 20,
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: !expanded
                  ? const SizedBox(width: double.infinity)
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _StatCell(
                              value: _formatKm(session.distanceMeters),
                              label: 'Cự ly',
                            ),
                          ),
                          _StatDivider(),
                          Expanded(
                            child: _StatCell(
                              value: _formatPaceApostrophe(
                                session.averagePaceSecondsPerKm,
                              ),
                              label: 'Pace/km',
                            ),
                          ),
                          _StatDivider(),
                          Expanded(
                            child: _StatCell(
                              value: formatDuration(session.movingTimeSeconds),
                              label: 'Thời gian',
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 17,
              height: 1.1,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.34),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, color: Colors.white.withValues(alpha: 0.06));
  }
}

class _LiveMap extends StatelessWidget {
  const _LiveMap({
    required this.mapController,
    required this.points,
    required this.sessions,
    required this.focusedUid,
    required this.clusters,
    required this.onPhotoPinTap,
    required this.onUserGesture,
    required this.onRunnerTap,
  });

  final MapController mapController;
  final List<LatLng> points;
  final List<LiveTrackingSession> sessions;
  final String? focusedUid;
  final List<_PhotoCluster> clusters;
  final ValueChanged<_PhotoCluster> onPhotoPinTap;
  final VoidCallback onUserGesture;
  final ValueChanged<String> onRunnerTap;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: mapController,
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(28),
          maxZoom: 16,
        ),
        minZoom: 3,
        maxZoom: 18,
        backgroundColor: Colors.black,
        onPositionChanged: (position, hasGesture) {
          if (hasGesture) onUserGesture();
        },
      ),
      children: [
        TileLayer(
          urlTemplate: _liveRouteTileTemplate,
          userAgentPackageName: 'com.threei.run',
          retinaMode: RetinaMode.isHighDensity(context),
        ),
        PolylineLayer(
          polylines: [
            Polyline(
              points: points,
              color: Colors.white.withValues(alpha: 0.28),
              strokeWidth: 3,
              pattern: StrokePattern.dashed(segments: const [2, 10]),
            ),
          ],
        ),
        MarkerLayer(
          markers: [
            if (points.isNotEmpty)
              _waypointMarker(
                points.first,
                RunNowSemanticColors.success,
                Icons.play_arrow_rounded,
                'Điểm bắt đầu',
              ),
            if (points.length > 1)
              _waypointMarker(
                points.last,
                RunNowSemanticColors.danger,
                Icons.sports_score_rounded,
                'Điểm kết thúc',
              ),
            for (final session in sessions)
              if (session.lastLocation case final location?)
                Marker(
                  point: LatLng(location.latitude, location.longitude),
                  width: 44,
                  height: 44,
                  child: GestureDetector(
                    onTap: () => onRunnerTap(session.ownerUid),
                    child: _RunnerMapMarker(
                      session: session,
                      focused: session.ownerUid == focusedUid,
                    ),
                  ),
                ),
            for (final cluster in clusters)
              Marker(
                point: cluster.anchor,
                width: 40,
                height: photoPinVisibleHeight + photoPinAnchorGap,
                alignment: Alignment.topCenter,
                child: GestureDetector(
                  onTap: () => onPhotoPinTap(cluster),
                  child: PhotoPinMarker(
                    storagePath: cluster.photos.first.photo.storagePath,
                    extraCount: cluster.photos.length - 1,
                    animateIn: true,
                    withAnchorStem: true,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

Marker _waypointMarker(
  LatLng point,
  Color color,
  IconData icon,
  String semanticLabel,
) {
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
        child: Icon(icon, color: Colors.black87, size: 18),
      ),
    ),
  );
}

class _RunnerMapMarker extends StatefulWidget {
  const _RunnerMapMarker({required this.session, required this.focused});

  final LiveTrackingSession session;
  final bool focused;

  @override
  State<_RunnerMapMarker> createState() => _RunnerMapMarkerState();
}

class _RunnerMapMarkerState extends State<_RunnerMapMarker>
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
    final ringColor = widget.focused
        ? RunNowSemanticColors.danger
        : RunNowSemanticColors.info;
    return Opacity(
      opacity: widget.focused ? 1 : 0.55,
      child: Semantics(
        label: '${widget.session.ownerName} đang chạy live',
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: ringColor, width: 2.5),
                boxShadow: [
                  BoxShadow(
                    color: ringColor.withValues(alpha: 0.4),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: ClipOval(
                child: _avatarOrInitial(
                  widget.session.ownerAvatarUrl,
                  widget.session.ownerName,
                  38,
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
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 2),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LivePhotoViewer extends StatefulWidget {
  const _LivePhotoViewer({
    required this.photos,
    required this.initialIndex,
    required this.onClose,
  });

  final List<LiveRoutePhoto> photos;
  final int initialIndex;
  final VoidCallback onClose;

  @override
  State<_LivePhotoViewer> createState() => _LivePhotoViewerState();
}

class _LivePhotoViewerState extends State<_LivePhotoViewer> {
  late final PageController _pageController = PageController(
    initialPage: widget.initialIndex,
  );
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final multi = widget.photos.length > 1;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.photos.length,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (context, index) => Center(
              child: StoragePhoto(
                path: widget.photos[index].photo.storagePath,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 110,
            child: IgnorePointer(child: _ViewerScrim()),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 14,
            child: _PhotoViewerCaption(
              photo: widget.photos[_index],
              index: _index,
              count: widget.photos.length,
            ),
          ),
          if (multi) ...[
            Positioned(
              left: 14,
              top: 0,
              bottom: 0,
              child: Center(
                child: _CircleIconButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: () => _pageController.previousPage(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                  ),
                ),
              ),
            ),
            Positioned(
              right: 14,
              top: 0,
              bottom: 0,
              child: Center(
                child: _CircleIconButton(
                  icon: Icons.chevron_right_rounded,
                  onTap: () => _pageController.nextPage(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                  ),
                ),
              ),
            ),
          ],
          Positioned(
            top: 12,
            left: 12,
            child: SafeArea(
              child: _CircleIconButton(
                icon: Icons.close_rounded,
                onTap: widget.onClose,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewerScrim extends StatelessWidget {
  const _ViewerScrim();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.75)],
        ),
      ),
    );
  }
}

class _PhotoViewerCaption extends StatelessWidget {
  const _PhotoViewerCaption({
    required this.photo,
    required this.index,
    required this.count,
  });

  final LiveRoutePhoto photo;
  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    final capturedAt = photo.photo.capturedAt;
    final timeLabel =
        '${capturedAt.hour.toString().padLeft(2, '0')}:'
        '${capturedAt.minute.toString().padLeft(2, '0')}';
    final kmLabel = (photo.photo.distanceMeters / 1000).toStringAsFixed(1);
    return Row(
      children: [
        ClipOval(
          child: _avatarOrInitial(photo.ownerAvatarUrl, photo.ownerName, 30),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                photo.ownerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              Text(
                'Chụp lúc $timeLabel · km $kmLabel',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.55),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        if (count > 1)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < count; i++)
                Padding(
                  padding: const EdgeInsets.only(left: 5),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == index
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.35),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

String _formatKm(double meters) => '${(meters / 1000).toStringAsFixed(1)} km';

String _formatPaceApostrophe(double? secondsPerKm) {
  if (secondsPerKm == null || !secondsPerKm.isFinite || secondsPerKm <= 0) {
    return '--';
  }
  final rounded = secondsPerKm.round();
  final minutes = rounded ~/ 60;
  final seconds = (rounded % 60).toString().padLeft(2, '0');
  return '$minutes\'$seconds"';
}

String _relativeUpdateLabel(DateTime updatedAt) {
  final diff = DateTime.now().difference(updatedAt);
  if (diff.inSeconds < 5) return 'Cập nhật vừa xong';
  if (diff.inSeconds < 60) return 'Cập nhật ${diff.inSeconds}s trước';
  if (diff.inMinutes < 60) return 'Cập nhật ${diff.inMinutes} phút trước';
  return 'Cập nhật ${diff.inHours} giờ trước';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
