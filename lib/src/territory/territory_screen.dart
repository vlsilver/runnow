import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/territory/territory_grid.dart';
import 'package:myrun/src/territory/territory_models.dart';
import 'package:myrun/src/territory/territory_repository.dart';
import 'package:myrun/src/territory/territory_share.dart';
import 'package:myrun/src/territory/territory_sheets.dart';
import 'package:myrun/src/territory/territory_stats_screen.dart';
import 'package:myrun/src/territory/territory_widgets.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/map_attribution.dart';
import 'package:myrun/src/widgets/map_vector.dart';
import 'package:myrun/src/widgets/run_now_loading.dart';

/// Chưa có ô nào và không có chunk để mở thì mở quanh trung tâm TP.HCM.
const territoryDefaultCenter = LatLng(10.7769, 106.7009);
const _defaultZoom = 14.0;
const _chunkZoom = 15.0;
const _cellZoom = 16.0;

/// Màn Lãnh địa: ô của mình (màu chính) và của mọi người (xanh) trên bản đồ,
/// lọc theo người, chạm ô xem chủ ô, danh sách Mọi người, số liệu từng người.
/// [cell] (id "x_y" z18, ô của một buổi) mở ngay ô đó; không có thì [chunk]
/// (id z13, từ push bị chiếm ô) mở đúng vùng đó; không có nữa thì mở ở chunk
/// mình giữ nhiều ô nhất.
class TerritoryScreen extends ConsumerWidget {
  const TerritoryScreen({this.chunk, this.cell, this.taken, super.key});

  final String? chunk;
  final String? cell;

  /// Người chiếm và buổi chiếm, từ push bị chiếm ô: màn vẽ ô vừa mất và hiện
  /// thẻ "X chiếm N ô của bạn".
  final TerritoryTaken? taken;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flag = ref.watch(territoryEnabledProvider);
    final enabled = flag.value ?? false;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lãnh địa'),
        actions: [if (enabled) const _ShareButton()],
      ),
      body: switch (flag) {
        AsyncValue(hasValue: true) when enabled => _body(ref),
        AsyncValue(hasValue: true) => const Center(
          child: Text('Lãnh địa chưa mở'),
        ),
        AsyncError(:final error) => _loadFailed(error),
        _ => const RunNowLoading(label: 'Đang tải lãnh địa'),
      },
    );
  }

  /// Lỗi gốc chỉ vào log; người dùng thấy một câu ngắn.
  Widget _loadFailed(Object error) {
    debugPrint('lãnh địa: tải lỗi: $error');
    return const Center(child: Text('Chưa tải được'));
  }

  Widget _body(WidgetRef ref) {
    // Link có thể tự gõ: ô ngoài lưới z18 thì bỏ qua.
    const side = 1 << territoryCellZoom;
    if (TileXY.parse(cell) case final at? when at.x < side && at.y < side) {
      return TerritoryMap(
        center: cellCenter(at),
        zoom: _cellZoom,
        taken: taken,
      );
    }
    final asked = TileXY.parse(chunk);
    if (asked != null) {
      return TerritoryMap(
        center: chunkCenter(asked),
        zoom: _chunkZoom,
        taken: taken,
      );
    }
    return ref
        .watch(myTerritoryProvider)
        .when(
          data: (owner) => switch (owner?.topChunk) {
            final top? => TerritoryMap(
              center: chunkCenter(top),
              zoom: _chunkZoom,
            ),
            null => const TerritoryMap(
              center: territoryDefaultCenter,
              zoom: _defaultZoom,
            ),
          },
          error: (error, _) => _loadFailed(error),
          loading: () => const RunNowLoading(label: 'Đang tải lãnh địa'),
        );
  }
}

/// Bản đồ ô, hàng lọc ở trên. Chỉ nghe các chunk trong khung nhìn, tối đa
/// [territoryMaxChunks]; zoom xa hơn thì không tải ô. Lọc được: tất cả, của
/// tôi, hay của một người chọn từ danh sách "Mọi người". Ô càng nhiều km càng
/// đậm ([territoryCellAlpha]).
class TerritoryMap extends ConsumerStatefulWidget {
  const TerritoryMap({
    required this.center,
    required this.zoom,
    this.taken,
    super.key,
  });

  final LatLng center;
  final double zoom;

  /// Buổi chiếm ô của mình (từ push): vẽ viền ô vừa mất và thẻ bị chiếm.
  final TerritoryTaken? taken;

  @override
  ConsumerState<TerritoryMap> createState() => _TerritoryMapState();
}

class _TerritoryMapState extends ConsumerState<TerritoryMap> {
  final _map = MapController();

  /// Null khi zoom quá xa.
  List<TileXY>? _chunks = const [];

  /// Chỉ hiện ô của uid này; null là hiện tất cả.
  String? _focus;

  /// Người dùng tự kéo bản đồ trong lúc chờ đọc ô thì không kéo bản đồ đi nữa.
  var _userMoved = false;

  /// Người dùng đã đóng thẻ bị chiếm.
  var _takenDismissed = false;

  /// Mở từ push bị chiếm: lúc bản đồ sẵn sàng thì đưa tới đúng các ô vừa mất.
  void _fitLost() {
    final lost = widget.taken?.cells ?? const <TileXY>[];
    if (lost.isEmpty) return;
    _map.fitCamera(
      CameraFit.coordinates(
        coordinates: [for (final cell in lost) ...cellCorners(cell)],
        padding: const EdgeInsets.fromLTRB(32, 160, 32, 96),
        maxZoom: 17,
      ),
    );
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _updateChunks(MapCamera camera) {
    final next = chunksInView(camera.visibleBounds);
    if (listEquals(next, _chunks)) return;
    setState(() => _chunks = next);
  }

  /// Lọc theo [uid]. Màn hình không có ô nào của người đó thì đưa bản đồ
  /// tới các ô họ giữ ở chunk nhiều ô nhất, để chọn xong là thấy ô; đang thấy
  /// ô của họ thì giữ nguyên chỗ đang xem. Xét theo khung nhìn chứ không theo
  /// chunk đã tải, vì một chunk rộng khoảng 5 km, lớn hơn màn hình nhiều.
  Future<void> _focusOn(String? uid, {TileXY? topChunk}) async {
    setState(() => _focus = uid);
    _userMoved = false;
    if (uid == null || topChunk == null) return;
    final view = _map.camera.visibleBounds;
    final onScreen = _visibleCells(
      read: true,
    ).any((cell) => view.contains(cellCenter(cell.tile)));
    if (onScreen) return;
    List<TerritoryCell> owned;
    try {
      owned = await ref.read(territoryRepositoryProvider).fetchOwnedCells(uid, [
        topChunk,
      ]);
    } catch (error) {
      // Không đọc được thì vẫn dời tới giữa chunk, lọc vẫn đúng.
      debugPrint('lãnh địa: đọc ô của $uid lỗi: $error');
      owned = const [];
    }
    // Người dùng đã đổi lọc hay tự kéo bản đồ trong lúc chờ thì thôi.
    if (!mounted || _focus != uid || _userMoved) return;
    if (owned.isEmpty) {
      _map.move(chunkCenter(topChunk), _chunkZoom);
    } else {
      _map.fitCamera(
        CameraFit.coordinates(
          coordinates: [for (final cell in owned) ...cellCorners(cell.tile)],
          padding: const EdgeInsets.fromLTRB(32, 48, 32, 96),
          maxZoom: 17,
        ),
      );
    }
    _updateChunks(_map.camera);
  }

  /// Mọi người → chọn một người → số liệu của họ → "Xem trên bản đồ" thì lọc.
  Future<void> _pickPerson() async {
    final picked = await showModalBottomSheet<TerritoryHolder>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const TerritoryHoldersSheet(),
    );
    if (picked == null || !mounted) return;
    await _openStats(picked.uid);
  }

  /// Mở số liệu của [uid]; trở về bằng "Xem trên bản đồ" thì lọc theo người
  /// đó.
  Future<void> _openStats(String uid) async {
    final owner = await Navigator.of(context).push<TerritoryOwner>(
      MaterialPageRoute(builder: (_) => TerritoryStatsScreen(uid: uid)),
    );
    if (owner == null || !mounted) return;
    await _focusOn(uid, topChunk: owner.topChunk);
  }

  /// Ô đang tải trong khung nhìn, đã lọc. [read] cho chỗ gọi ngoài build.
  List<TerritoryCell> _visibleCells({bool read = false}) => [
    for (final chunk in _chunks ?? const <TileXY>[])
      for (final cell
          in (read
                      ? ref.read(territoryChunkProvider(chunk))
                      : ref.watch(territoryChunkProvider(chunk)))
                  .value ??
              const <TerritoryCell>[])
        if (_focus == null || cell.ownerUid == _focus) cell,
  ];

  Future<void> _openCell(LatLng point) async {
    final tile = tileAt(point, territoryCellZoom);
    final chunk = chunkOfCell(tile);
    if (!(_chunks?.contains(chunk) ?? false)) return;
    final cells = ref.read(territoryChunkProvider(chunk)).value;
    final cell = cells
        ?.where((c) => c.tile == tile)
        .where((c) => _focus == null || c.ownerUid == _focus)
        .firstOrNull;
    if (cell == null) return;
    final owner = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => TerritoryCellSheet(cell: cell),
    );
    if (owner == null || !mounted) return;
    await _openStats(owner);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final myUid = ref.watch(firebaseUserProvider).value?.uid;
    final cells = _visibleCells();
    // Push gửi cho tài khoản khác (máy đổi tài khoản mà token cũ chưa gỡ)
    // thì không hiện: thẻ nói "của bạn".
    final taken = switch (widget.taken) {
      final t? when !_takenDismissed && (t.to == null || t.to == myUid) => t,
      _ => null,
    };
    // Ô đã giành lại (chủ hiện tại là mình) thì thôi viền.
    final mineNow = {
      for (final chunk in _chunks ?? const <TileXY>[])
        for (final cell
            in ref.watch(territoryChunkProvider(chunk)).value ??
                const <TerritoryCell>[])
          if (cell.ownerUid == myUid) cell.tile,
    };
    final lost = [
      for (final cell in taken?.cells ?? const <TileXY>[])
        if (!mineNow.contains(cell)) cell,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FilterBar(
          focus: _focus,
          myUid: myUid,
          onAll: () => _focusOn(null),
          onMine: (top) => _focusOn(myUid, topChunk: top),
          onPeople: _pickPerson,
        ),
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: widget.center,
                  initialZoom: widget.zoom,
                  minZoom: 4,
                  maxZoom: 19,
                  backgroundColor: palette.tint,
                  onMapReady: () {
                    _fitLost();
                    _updateChunks(_map.camera);
                  },
                  onPositionChanged: (camera, hasGesture) {
                    if (hasGesture) _userMoved = true;
                    _updateChunks(camera);
                  },
                  onTap: (_, point) => _openCell(point),
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                ),
                children: [
                  mapBaseLayer(context, dark: dark, around: [widget.center]),
                  PolygonLayer(
                    polygons: [
                      for (final cell in cells)
                        _polygon(cell, myUid, palette.accent),
                      // Ô vừa mất: viền nét đứt màu của mình trên ô người chiếm.
                      for (final cell in lost)
                        Polygon(
                          points: cellCorners(cell),
                          color: Colors.transparent,
                          borderColor: palette.accent,
                          borderStrokeWidth: 2.5,
                          pattern: StrokePattern.dashed(segments: [6, 4]),
                        ),
                    ],
                  ),
                  const MapAttribution(),
                ],
              ),
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Column(
                  spacing: 8,
                  children: [
                    if (taken != null && myUid != null)
                      _TakenBanner(
                        takerUid: taken.uid,
                        lost: taken.count,
                        onClose: () => setState(() => _takenDismissed = true),
                      ),
                    _Badge(tooFar: _chunks == null),
                  ],
                ),
              ),
              const Positioned(left: 12, bottom: 12, child: _Legend()),
              Positioned(
                right: 12,
                bottom: 44,
                child: _RulesButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    showDragHandle: true,
                    isScrollControlled: true,
                    builder: (_) => const TerritoryRulesSheet(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Polygon _polygon(TerritoryCell cell, String? myUid, Color mine) {
    final color = territoryMapColor(cell.ownerUid, myUid: myUid, mine: mine);
    return Polygon(
      points: cellCorners(cell.tile),
      color: color.withValues(alpha: territoryCellAlpha(cell.meters)),
      borderColor: color,
      borderStrokeWidth: cell.ownerUid == myUid ? 1.4 : 0.8,
    );
  }
}

/// Hàng lọc dưới tiêu đề, không đè lên bản đồ: Tất cả · Của tôi · người đang
/// chọn · Mọi người.
class _FilterBar extends ConsumerWidget {
  const _FilterBar({
    required this.focus,
    required this.myUid,
    required this.onAll,
    required this.onMine,
    required this.onPeople,
  });

  final String? focus;
  final String? myUid;
  final VoidCallback onAll;
  final void Function(TileXY? topChunk) onMine;
  final VoidCallback onPeople;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mine = ref.watch(myTerritoryProvider).value;
    final other = focus != null && focus != myUid ? focus : null;
    final otherName = other == null
        ? null
        : ref.watch(territoryNamesProvider)[other]?.name ??
              territoryDefaultName;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Row(
        spacing: 8,
        children: [
          ChoiceChip(
            label: const Text('Tất cả'),
            selected: focus == null,
            onSelected: (_) => onAll(),
          ),
          if (myUid != null)
            ChoiceChip(
              label: Text(
                mine == null ? 'Của tôi' : 'Của tôi · ${mine.cellCount} ô',
              ),
              selected: focus == myUid,
              onSelected: (_) => onMine(mine?.topChunk),
            ),
          if (otherName != null)
            InputChip(
              label: Text(otherName),
              selected: true,
              onPressed: () {},
              onDeleted: onAll,
            ),
          ActionChip(
            avatar: const Icon(Icons.groups_rounded, size: 18),
            label: const Text('Mọi người'),
            onPressed: onPeople,
          ),
        ],
      ),
    );
  }
}

/// Chú thích: màu của tôi và người khác, độ đậm ít km → nhiều.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    final ink = Theme.of(context).colorScheme.onSurface;
    Widget swatch(Color color, double alpha) => Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color.withValues(alpha: alpha),
        border: Border.all(color: color, width: 0.8),
      ),
    );
    return GlassPanel(
      borderRadius: 12,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              swatch(context.runNowPalette.accent, 0.8),
              Text('Tôi', style: style),
              const SizedBox(width: 6),
              swatch(territoryOthersColor(context.runNowPalette.accent), 0.8),
              Text('Người khác', style: style),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 4,
            children: [
              Text('ít km', style: style),
              for (final alpha in territoryShadeLevels)
                swatch(ink, alpha * 0.7),
              Text('nhiều', style: style),
            ],
          ),
        ],
      ),
    );
  }
}

class _RulesButton extends StatelessWidget {
  const _RulesButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GlassPanel(
      borderRadius: 12,
      padding: EdgeInsets.zero,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.help_outline_rounded, size: 18),
        label: const Text('Là gì?'),
      ),
    );
  }
}

/// Thẻ "X chiếm N ô của bạn" khi mở từ push bị chiếm, nút chạy giành lại.
class _TakenBanner extends ConsumerWidget {
  const _TakenBanner({
    required this.takerUid,
    required this.lost,
    required this.onClose,
  });

  final String takerUid;
  final int lost;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final name =
        ref.watch(territoryNamesProvider)[takerUid]?.name ??
        territoryDefaultName;
    return Material(
      color: theme.colorScheme.surface,
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        child: Column(
          spacing: 10,
          children: [
            Row(
              spacing: 12,
              children: [
                TerritoryAvatar(uid: takerUid, name: name),
                Expanded(
                  child: Text(
                    '$name chiếm $lost ô của bạn',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  onPressed: onClose,
                  tooltip: 'Đóng',
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => context.go('/tracking'),
                  child: const Text('Chạy giành lại'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nhắc phóng to khi zoom quá xa, hay nhắc hồ sơ private không có ô.
class _Badge extends ConsumerWidget {
  const _Badge({required this.tooFar});

  final bool tooFar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Backend chỉ tính ô cho hồ sơ công khai, vì bản đồ ô lộ tuyến chạy.
    final private =
        ref.watch(userProfileProvider).value?.visibility ==
        ProfileVisibility.private;
    if (!tooFar && !private) return const SizedBox.shrink();
    return GlassPanel(
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Text(
        tooFar ? 'Phóng to để xem ô' : 'Hồ sơ công khai mới có ô',
        style: Theme.of(context).textTheme.titleSmall,
      ),
    );
  }
}

/// Khoe lãnh địa của mình. Chưa có ô nào thì không có nút.
class _ShareButton extends ConsumerStatefulWidget {
  const _ShareButton();

  @override
  ConsumerState<_ShareButton> createState() => _ShareButtonState();
}

class _ShareButtonState extends ConsumerState<_ShareButton> {
  var _loading = false;

  Future<void> _share(String uid, TerritoryOwner owner) async {
    setState(() => _loading = true);
    await shareMyTerritory(context, ref, uid: uid, owner: owner);
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(firebaseUserProvider).value?.uid;
    final owner = ref.watch(myTerritoryProvider).value;
    if (uid == null || owner == null || owner.cellCount == 0) {
      return const SizedBox.shrink();
    }
    return IconButton(
      onPressed: _loading ? null : () => _share(uid, owner),
      tooltip: 'Khoe lãnh địa',
      icon: const Icon(Icons.ios_share),
    );
  }
}
