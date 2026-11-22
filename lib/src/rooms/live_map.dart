import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/live_bits.dart';
import 'package:myrun/src/widgets/map_tiles.dart';
import 'package:myrun/src/widgets/map_vector.dart';
import 'package:myrun/src/widgets/route_map.dart'
    show LiveRunnerMarker, routeBounds;

/// Khung cả Việt Nam, lúc chưa ai chạy hay bấm "Tất cả".
final vietnamBounds = LatLngBounds(
  const LatLng(8.2, 102.1),
  const LatLng(23.5, 109.6),
);

LatLng _at(LiveTrackingSession s) =>
    LatLng(s.lastLocation!.latitude, s.lastLocation!.longitude);

/// Gộp người đứng gần nhau trên màn: ai cách người mở cụm dưới [radius] px
/// thì vào cụm đó, giữ thứ tự đầu vào. [project] đổi toạ độ ra pixel ở mức
/// zoom đang xem, nên zoom vào thì cụm tự tách.
List<List<LiveTrackingSession>> groupNearby(
  List<LiveTrackingSession> sessions,
  Offset Function(LatLng) project, {
  double radius = 44,
}) {
  final groups = <List<LiveTrackingSession>>[];
  final anchors = <Offset>[];
  for (final s in sessions) {
    final p = project(_at(s));
    final i = anchors.indexWhere((a) => (a - p).distance < radius);
    if (i < 0) {
      anchors.add(p);
      groups.add([s]);
    } else {
      groups[i].add(s);
    }
  }
  return groups;
}

/// Bản đồ mọi người đang chạy live: mỗi người một avatar ở vị trí mới nhất.
/// Chạm avatar thì bay tới người đó và vẽ đường đã chạy, thẻ dưới đáy mở màn
/// xem live. Chạm chỗ trống thì về khung ôm mọi người.
class LiveRunnersMap extends StatefulWidget {
  const LiveRunnersMap({
    required this.sessions,
    required this.onOpen,
    super.key,
  });

  /// Buổi không có vị trí thì không lên bản đồ.
  final List<LiveTrackingSession> sessions;
  final ValueChanged<LiveTrackingSession> onOpen;

  @override
  State<LiveRunnersMap> createState() => _LiveRunnersMapState();
}

class _LiveRunnersMapState extends State<LiveRunnersMap> {
  final _map = MapController();
  bool _ready = false;
  String? _selectedId;

  List<LiveTrackingSession> get _placed => [
    for (final s in widget.sessions)
      if (s.lastLocation != null) s,
  ];

  LiveTrackingSession? get _selected {
    for (final s in _placed) {
      if (s.id == _selectedId) return s;
    }
    return null;
  }

  @override
  void didUpdateWidget(covariant LiveRunnersMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Người đang xem đã về đích thì về khung cả nước.
    if (_selectedId != null && _selected == null) {
      _selectedId = null;
      _showCountry();
    }
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  /// Khung chung luôn là cả Việt Nam, để thấy club đang chạy ở những đâu;
  /// muốn xem gần thì chạm vào một người.
  void _showCountry() {
    if (!_ready) return;
    _map.fitCamera(
      CameraFit.bounds(
        bounds: vietnamBounds,
        padding: const EdgeInsets.all(12),
      ),
    );
  }

  void _select(LiveTrackingSession session) {
    setState(() => _selectedId = session.id);
    final route = liveRoutePoints(session);
    if (route.length < 2) {
      _map.move(_at(session), 16);
      return;
    }
    _map.fitCamera(
      CameraFit.bounds(
        bounds: routeBounds(route),
        padding: const EdgeInsets.fromLTRB(40, 40, 40, 90),
        maxZoom: _maxZoom,
      ),
    );
  }

  static const _maxZoom = 16.0;

  /// Chạm cụm thì zoom cho vừa những người trong cụm, để họ tách ra. Chạy sát
  /// nhau tới mức zoom hết cỡ vẫn chung cụm (cả nhóm chạy cùng) thì cho chọn
  /// người từ danh sách.
  void _openGroup(List<LiveTrackingSession> group) {
    final splits =
        groupNearby(
          group,
          (p) => _map.camera.projectAtZoom(p, _maxZoom),
        ).length >
        1;
    if (!splits) {
      _pick(group);
      return;
    }
    _map.fitCamera(
      CameraFit.coordinates(
        coordinates: [for (final s in group) _at(s)],
        padding: const EdgeInsets.all(60),
        maxZoom: _maxZoom,
      ),
    );
  }

  Future<void> _pick(List<LiveTrackingSession> group) async {
    final picked = await showModalBottomSheet<LiveTrackingSession>(
      context: context,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final s in group)
              ListTile(
                title: Text(
                  s.ownerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                trailing: Text(formatDistance(s.distanceMeters)),
                onTap: () => Navigator.of(sheet).pop(s),
              ),
          ],
        ),
      ),
    );
    // Người được chọn có thể đã về đích trong lúc sheet mở.
    if (picked == null || !mounted) return;
    if (_placed.any((s) => s.id == picked.id)) _select(picked);
  }

  void _clear() {
    if (_selectedId == null) return;
    setState(() => _selectedId = null);
    _showCountry();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final placed = _placed;
    final selected = _selected;
    final route = selected == null
        ? const <LatLng>[]
        : liveRoutePoints(selected);
    // Chọn lớp nền theo khung đang xem: chưa chọn ai thì là cả nước, để một
    // người chạy ở nước ngoài không kéo cả bản đồ về lớp raster.
    final around = selected == null
        ? [vietnamBounds.southWest, vietnamBounds.northEast]
        : route.length > 1
        ? route
        : [_at(selected)];
    final credit = mapTileCredits(
      currentMapTileTemplate(),
    ).map((c) => c.label).join(' · ');
    return ClipRRect(
      borderRadius: palette.radius(18),
      child: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCameraFit: CameraFit.bounds(
                  bounds: vietnamBounds,
                  padding: const EdgeInsets.all(12),
                ),
                backgroundColor: palette.tint,
                onMapReady: () => _ready = true,
                onTap: (_, _) => _clear(),
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                mapBaseLayer(context, dark: dark, around: around),
                if (route.length > 1)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: route,
                        color: palette.danger,
                        strokeWidth: 4,
                        borderColor: dark
                            ? palette.backgroundDeep
                            : Colors.white,
                        borderStrokeWidth: 1.5,
                      ),
                    ],
                  ),
                _RunnerMarkers(
                  others: [
                    for (final s in placed)
                      if (s.id != _selectedId) s,
                  ],
                  selected: selected,
                  onSelect: _select,
                  onCluster: _openGroup,
                ),
              ],
            ),
          ),
          if (selected != null)
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: _SelectedRunner(
                session: selected,
                onOpen: () => widget.onOpen(selected),
              ),
            )
          else if (placed.isEmpty)
            Positioned(
              left: 12,
              bottom: 12,
              child: _Chip(text: 'Chưa ai đang chạy live'),
            ),
          if (selected != null || placed.length > 1)
            Positioned(
              top: 10,
              right: 10,
              child: _Chip(
                text: 'Tất cả · ${placed.length}',
                onTap: selected == null ? _showCountry : _clear,
              ),
            ),
          // Ghi nguồn bản đồ là bắt buộc (ODbL).
          Positioned(
            left: 10,
            top: 8,
            child: Text(
              '© $credit',
              style: TextStyle(
                fontSize: 8,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lớp avatar: người gần nhau ở mức zoom hiện tại gộp thành một avatar kèm
/// số người; người đang chọn luôn đứng riêng và nằm trên cùng.
class _RunnerMarkers extends StatelessWidget {
  const _RunnerMarkers({
    required this.others,
    required this.selected,
    required this.onSelect,
    required this.onCluster,
  });

  final List<LiveTrackingSession> others;
  final LiveTrackingSession? selected;
  final ValueChanged<LiveTrackingSession> onSelect;
  final ValueChanged<List<LiveTrackingSession>> onCluster;

  @override
  Widget build(BuildContext context) {
    final camera = MapCamera.of(context);
    // Luồng live đổi thứ tự mỗi lần có người gửi vị trí; xếp theo id để cụm
    // và avatar đứng đầu cụm không nhảy.
    final sorted = [...others]..sort((a, b) => a.id.compareTo(b.id));
    final groups = groupNearby(sorted, camera.projectAtZoom);
    Marker marker(LiveTrackingSession s, Widget child, VoidCallback onTap) =>
        Marker(
          point: _at(s),
          width: 46,
          height: 46,
          child: GestureDetector(onTap: onTap, child: child),
        );
    return MarkerLayer(
      markers: [
        for (final g in groups)
          g.length == 1
              ? marker(g.first, LiveRunnerMarker(session: g.first), () {
                  onSelect(g.first);
                })
              : marker(
                  g.first,
                  _ClusterMarker(lead: g.first, count: g.length),
                  () => onCluster(g),
                ),
        if (selected case final s?)
          marker(s, LiveRunnerMarker(session: s, selected: true), () {
            onSelect(s);
          }),
      ],
    );
  }
}

class _ClusterMarker extends StatelessWidget {
  const _ClusterMarker({required this.lead, required this.count});

  final LiveTrackingSession lead;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Semantics(
      label: '$count người đang chạy ở đây',
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: LiveRunnerMarker(session: lead)),
          Positioned(
            top: -6,
            right: -8,
            child: Container(
              constraints: const BoxConstraints(minWidth: 20),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: palette.danger,
                borderRadius: palette.radius(10),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                '$count',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Material(
      color: palette.glassStart,
      shape: StadiumBorder(side: BorderSide(color: palette.border)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}

class _SelectedRunner extends StatelessWidget {
  const _SelectedRunner({required this.session, required this.onOpen});

  final LiveTrackingSession session;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Material(
      color: palette.glassStart,
      shape: RoundedRectangleBorder(
        borderRadius: palette.radius(14),
        side: BorderSide(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                session.ownerName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatDistance(session.distanceMeters),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: onOpen,
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              child: const Text('Xem live'),
            ),
          ],
        ),
      ),
    );
  }
}
