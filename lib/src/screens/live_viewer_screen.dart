import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/hearts.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';
import 'package:myrun/src/widgets/heart_button.dart';
import 'package:myrun/src/widgets/live_bits.dart';
import 'package:myrun/src/widgets/map_attribution.dart';
import 'package:myrun/src/widgets/map_tiles.dart';
import 'package:myrun/src/widgets/photo_pin_marker.dart';
import 'package:myrun/src/widgets/route_map.dart' show routeBounds;

/// Xem một người trong club đang chạy: bản đồ full màn, đường đã chạy phát
/// sáng, chấm vị trí nhấp nháy, và một tấm số liệu ở dưới. Chỉ xem, không
/// điều khiển gì phiên của người khác.
class LiveViewerScreen extends ConsumerWidget {
  const LiveViewerScreen({required this.sessionId, super.key});

  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(liveSessionProvider(sessionId));
    return Scaffold(
      backgroundColor: context.runNowPalette.backgroundDeep,
      body: live.when(
        data: (session) => session == null
            ? const _Gone(message: 'Buổi chạy này không còn.')
            : _LiveView(session: session),
        // Rules trả permission-denied cả khi document không tồn tại, nên
        // không tách được "không có quyền" với "không còn".
        error: (error, _) {
          debugPrint('live session $sessionId: $error');
          return _Gone(
            message: 'Không xem được buổi chạy này.',
            onRetry: () => ref.invalidate(liveSessionProvider(sessionId)),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}

/// Mốc từng km trên đường chạy: điểm đầu tiên mà quãng cộng dồn chạm k km.
/// Điểm live cách nhau ~100 m nên mốc lệch tối đa chừng đó.
List<({int km, LatLng point})> routeKmMarks(List<LatLng> points) {
  const distance = Distance();
  final marks = <({int km, LatLng point})>[];
  var total = 0.0;
  for (var i = 1; i < points.length; i++) {
    total += distance.as(LengthUnit.Meter, points[i - 1], points[i]);
    while (total >= (marks.length + 1) * 1000) {
      marks.add((km: marks.length + 1, point: points[i]));
    }
  }
  return marks;
}

class _LiveView extends StatefulWidget {
  const _LiveView({required this.session});

  final LiveTrackingSession session;

  @override
  State<_LiveView> createState() => _LiveViewState();
}

class _LiveViewState extends State<_LiveView> {
  final _map = MapController();
  bool _ready = false;
  // Người xem tự kéo bản đồ thì thôi bám theo, tới khi bấm nút định vị.
  bool _manual = false;

  List<LatLng> get _points => liveRoutePoints(widget.session);

  @override
  void didUpdateWidget(covariant _LiveView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_manual && oldWidget.session.updatedAt != widget.session.updatedAt) {
      _fit();
    }
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _fit() {
    final points = _points;
    if (!_ready || points.isEmpty) return;
    if (points.length == 1) {
      _map.move(points.single, 16);
      return;
    }
    final insets = MediaQuery.paddingOf(context);
    _map.fitCamera(
      CameraFit.bounds(
        bounds: routeBounds(points),
        padding: EdgeInsets.fromLTRB(48, insets.top + 90, 48, 330),
        maxZoom: 17,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final points = _points;
    return Stack(
      children: [
        Positioned.fill(
          child: points.isEmpty
              ? const _WaitingGps()
              : _buildMap(context, points),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              // Chừa góc phải cho nút ghi nguồn bản đồ (MapAttribution top).
              padding: const EdgeInsets.fromLTRB(14, 6, 60, 0),
              child: Row(
                children: [
                  _CircleButton(
                    icon: Icons.arrow_back_rounded,
                    tooltip: 'Quay lại',
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _WhoPill(session: session),
                    ),
                  ),
                  if (_manual && points.isNotEmpty)
                    _CircleButton(
                      icon: Icons.my_location_rounded,
                      tooltip: 'Theo người chạy',
                      onTap: () {
                        setState(() => _manual = false);
                        _fit();
                      },
                    ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 10,
          right: 10,
          bottom: 0,
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 10),
            child: _LiveSheet(session: session),
          ),
        ),
      ],
    );
  }

  Widget _buildMap(BuildContext context, List<LatLng> points) {
    final palette = context.runNowPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final running =
        widget.session.status == LiveTrackingStatus.running &&
        !widget.session.isExpired(DateTime.now());
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: points.last,
        initialZoom: 15,
        minZoom: 3,
        maxZoom: 18,
        backgroundColor: palette.backgroundDeep,
        onMapReady: () {
          _ready = true;
          _fit();
        },
        onPositionChanged: (_, hasGesture) {
          if (hasGesture && !_manual) setState(() => _manual = true);
        },
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        mapTileLayer(context, dark: dark),
        // Tấm số liệu che góc dưới, nên ghi nguồn bản đồ để ở trên.
        const MapAttribution(top: true),
        PolylineLayer(
          polylines: [
            Polyline(
              points: points,
              color: palette.accent.withValues(alpha: 0.28),
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
            for (final mark in routeKmMarks(points))
              Marker(
                point: mark.point,
                width: 26,
                height: 26,
                child: _KmMark(km: mark.km),
              ),
            for (final photo in widget.session.livePhotos)
              Marker(
                point: LatLng(photo.latitude, photo.longitude),
                width: 40,
                height: photoPinVisibleHeight,
                alignment: Alignment.topCenter,
                child: PhotoPinMarker(storagePath: photo.storagePath),
              ),
            Marker(
              point: points.last,
              width: 64,
              height: 64,
              child: running
                  ? PulsingDot(color: palette.accent)
                  : Center(child: _StillDot(color: palette.textMuted)),
            ),
          ],
        ),
      ],
    );
  }
}

class _LiveSheet extends ConsumerWidget {
  const _LiveSheet({required this.session});

  final LiveTrackingSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.runNowPalette;
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.55);
    final contractId = session.contractId;
    final note = _statusNote(session, DateTime.now());
    final heart = liveHeartTarget(session.id);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: palette.border.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (note != null) ...[
              Text(
                note,
                style: TextStyle(color: muted, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: (session.distanceMeters / 1000).toStringAsFixed(
                            2,
                          ),
                        ),
                        TextSpan(
                          text: ' km',
                          style: TextStyle(fontSize: 24, color: muted),
                        ),
                      ],
                    ),
                    style: const TextStyle(
                      fontFamily: 'Barlow Condensed',
                      fontSize: 68,
                      height: 0.95,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                HeartButton(target: heart, canUnlike: false, size: 30),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: EverySecond(
                    builder: (context, now) => _Stat(
                      value: formatDuration(liveElapsedSeconds(session, now)),
                      label: 'thời gian',
                    ),
                  ),
                ),
                Expanded(
                  child: _Stat(
                    value: formatPace(
                      session.averagePaceSecondsPerKm,
                    ).replaceAll(' /km', ''),
                    label: '/km',
                  ),
                ),
                Expanded(
                  child: _Stat(
                    value: DateFormat(
                      'HH:mm',
                    ).format(session.startedAt.toLocal()),
                    label: 'bắt đầu',
                  ),
                ),
              ],
            ),
            if (contractId != null)
              _ContractChip(contractId: contractId, session: session),
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: HeartCheerers(target: heart),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dòng trạng thái khi phiên không còn chạy bình thường. Null khi đang chạy.
String? _statusNote(LiveTrackingSession session, DateTime now) {
  final at = DateFormat('HH:mm').format(session.updatedAt.toLocal());
  return switch (session.status) {
    LiveTrackingStatus.finished => 'Đã chạy xong lúc $at',
    LiveTrackingStatus.expired => 'Mất tín hiệu từ $at',
    LiveTrackingStatus.paused => 'Đang tạm dừng',
    LiveTrackingStatus.running when session.isExpired(now) =>
      'Mất tín hiệu từ $at',
    LiveTrackingStatus.running => null,
  };
}

/// Kèo người này đang chạy cho. Kèo quãng đường thì có thanh: phần đã có
/// trước buổi này và phần buổi live đang cộng thêm.
class _ContractChip extends ConsumerWidget {
  const _ContractChip({required this.contractId, required this.session});

  final String contractId;
  final LiveTrackingSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contract = ref.watch(runContractProvider(contractId));
    // Kèo riêng tư người xem không đọc được: không có chip, không chặn màn.
    if (contract.hasError) {
      debugPrint('live contract $contractId: ${contract.error}');
    }
    final value = contract.value;
    if (value == null) return const SizedBox.shrink();
    final palette = context.runNowPalette;
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.55);
    final target = value.targetValue;
    final before = value.participantFor(session.ownerUid)?.progressValue;
    final showBar =
        value.metric == RunContractMetric.distance &&
        before != null &&
        target > 0;
    final withLive = (before ?? 0) + session.distanceMeters / 1000;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.tint,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              if (showBar) ...[
                const SizedBox(width: 10),
                SizedBox(
                  width: 72,
                  child: _TwoPartBar(
                    before: before / target,
                    after: withLive / target,
                    color: palette.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${withLive.toStringAsFixed(1)}/${target.toStringAsFixed(0)}',
                  style: TextStyle(
                    color: muted,
                    fontFamily: 'Barlow Condensed',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TwoPartBar extends StatelessWidget {
  const _TwoPartBar({
    required this.before,
    required this.after,
    required this.color,
  });

  final double before;
  final double after;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.08);
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: 8,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: track),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: after.clamp(0.0, 1.0),
              child: ColoredBox(color: color.withValues(alpha: 0.45)),
            ),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: before.clamp(0.0, 1.0),
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontFamily: 'Barlow Condensed',
            fontSize: 26,
            height: 1,
            fontWeight: FontWeight.w800,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.5),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _WhoPill extends StatelessWidget {
  const _WhoPill({required this.session});

  final LiveTrackingSession session;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final url = session.ownerAvatarUrl;
    final hasUrl = url != null && url.isNotEmpty;
    final name = session.ownerName;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.border.withValues(alpha: 0.6)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(5, 5, 14, 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 15,
              backgroundColor: palette.accent,
              backgroundImage: hasUrl
                  ? cachedAvatarImage(context, url, 30)
                  : null,
              child: hasUrl
                  ? null
                  : Text(
                      name.isEmpty ? '?' : name[0].toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            if (session.status == LiveTrackingStatus.running) ...[
              const SizedBox(width: 8),
              const LiveDot(color: RunNowSemanticColors.danger),
            ],
          ],
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Material(
      color: palette.background.withValues(alpha: 0.88),
      shape: CircleBorder(
        side: BorderSide(color: palette.border.withValues(alpha: 0.6)),
      ),
      child: IconButton(tooltip: tooltip, onPressed: onTap, icon: Icon(icon)),
    );
  }
}

class _KmMark extends StatelessWidget {
  const _KmMark({required this.km});

  final int km;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background,
        shape: BoxShape.circle,
        border: Border.all(color: palette.accent, width: 2),
      ),
      child: Center(
        child: Text(
          '$km',
          style: const TextStyle(
            fontFamily: 'Barlow Condensed',
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _StillDot extends StatelessWidget {
  const _StillDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
      ),
    );
  }
}

class _WaitingGps extends StatelessWidget {
  const _WaitingGps();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 200),
        child: Text(
          'Đang chờ GPS của người chạy…',
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.55),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _Gone extends StatelessWidget {
  const _Gone({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton(
            tooltip: 'Quay lại',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  if (onRetry != null)
                    TextButton(
                      onPressed: onRetry,
                      child: const Text('Thử lại'),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
