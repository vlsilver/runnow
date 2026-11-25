import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/territory/territory_grid.dart';
import 'package:myrun/src/territory/territory_models.dart';
import 'package:myrun/src/territory/territory_repository.dart';
import 'package:myrun/src/territory/territory_share.dart';
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

/// Màn Lãnh địa: ô của mình và của mọi người trên bản đồ, lọc theo người,
/// chạm ô xem chủ ô.
/// [chunk] (id "x_y" z13, từ push bị chiếm ô) mở đúng vùng đó; không có thì
/// mở ở chunk mình giữ nhiều ô nhất.
class TerritoryScreen extends ConsumerWidget {
  const TerritoryScreen({this.chunk, super.key});

  final String? chunk;

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
    final asked = TileXY.parse(chunk);
    if (asked != null) {
      return TerritoryMap(center: chunkCenter(asked), zoom: _chunkZoom);
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

/// Bản đồ ô. Chỉ nghe các chunk trong khung nhìn, tối đa
/// [territoryMaxChunks]; zoom xa hơn thì không tải ô. Lọc được: tất cả, của
/// tôi, hay của một người chọn từ danh sách "Mọi người". Ô càng nhiều km càng
/// đậm ([territoryCellAlpha]).
class TerritoryMap extends ConsumerStatefulWidget {
  const TerritoryMap({required this.center, required this.zoom, super.key});

  final LatLng center;
  final double zoom;

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
    ).any((cell) => view.contains(_cellCenter(cell.tile)));
    if (onScreen) return;
    List<TileXY> owned;
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
          coordinates: [for (final tile in owned) ...cellCorners(tile)],
          padding: const EdgeInsets.fromLTRB(32, 96, 32, 64),
          maxZoom: 17,
        ),
      );
    }
    _updateChunks(_map.camera);
  }

  static LatLng _cellCenter(TileXY tile) =>
      tileCorner(tile.x + 0.5, tile.y + 0.5, territoryCellZoom);

  Future<void> _pickPerson() async {
    final picked = await showModalBottomSheet<TerritoryHolder>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _HoldersSheet(),
    );
    if (picked == null || !mounted) return;
    _focusOn(picked.uid, topChunk: picked.owner.topChunk);
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

  void _openCell(LatLng point) {
    final tile = tileAt(point, territoryCellZoom);
    final chunk = chunkOfCell(tile);
    if (!(_chunks?.contains(chunk) ?? false)) return;
    final cells = ref.read(territoryChunkProvider(chunk)).value;
    final cell = cells
        ?.where((c) => c.tile == tile)
        .where((c) => _focus == null || c.ownerUid == _focus)
        .firstOrNull;
    if (cell == null) return;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => _CellSheet(cell: cell),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final myUid = ref.watch(firebaseUserProvider).value?.uid;
    final cells = _visibleCells();
    return Stack(
      children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: widget.center,
            initialZoom: widget.zoom,
            minZoom: 4,
            maxZoom: 19,
            backgroundColor: palette.tint,
            onMapReady: () => _updateChunks(_map.camera),
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
                for (final cell in cells) _polygon(cell, myUid, palette.accent),
              ],
            ),
            const MapAttribution(),
          ],
        ),
        Positioned(
          top: 8,
          left: 0,
          right: 0,
          child: Column(
            children: [
              _FilterBar(
                focus: _focus,
                myUid: myUid,
                onAll: () => _focusOn(null),
                onMine: (top) => _focusOn(myUid, topChunk: top),
                onPeople: _pickPerson,
              ),
              const SizedBox(height: 8),
              _Badge(tooFar: _chunks == null),
            ],
          ),
        ),
        Positioned(
          left: 12,
          bottom: 12,
          child: SafeArea(
            child: _ShadeLegend(
              // Đang lọc một người thì chú thích theo màu ô của người đó;
              // xem tất cả thì màu trung tính, vì mỗi người một màu.
              color: _focus == null
                  ? Theme.of(context).colorScheme.onSurface
                  : territoryOwnerColor(
                      _focus!,
                      myUid: myUid,
                      mine: palette.accent,
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Polygon _polygon(TerritoryCell cell, String? myUid, Color mine) {
    final color = territoryOwnerColor(cell.ownerUid, myUid: myUid, mine: mine);
    return Polygon(
      points: cellCorners(cell.tile),
      color: color.withValues(alpha: territoryCellAlpha(cell.meters)),
      borderColor: color,
      borderStrokeWidth: cell.ownerUid == myUid ? 1.4 : 0.8,
    );
  }
}

/// Hàng lọc trên bản đồ: Tất cả · Của tôi · người đang chọn · Mọi người.
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
      padding: const EdgeInsets.symmetric(horizontal: 12),
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

/// Danh sách người giữ ô, nhiều ô trước. Chạm một người thì đóng sheet và
/// trả người đó về cho bản đồ lọc.
class _HoldersSheet extends ConsumerWidget {
  const _HoldersSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myUid = ref.watch(firebaseUserProvider).value?.uid;
    final names = ref.watch(territoryNamesProvider);
    final theme = Theme.of(context);
    final body = ref
        .watch(territoryHoldersProvider)
        .when(
          data: (holders) => holders.isEmpty
              ? const Center(child: Text('Chưa ai giữ ô'))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: holders.length,
                  itemBuilder: (context, i) {
                    final holder = holders[i];
                    final name =
                        names[holder.uid]?.name ?? territoryDefaultName;
                    return ListTile(
                      leading: SizedBox(
                        width: 28,
                        child: Text(
                          '${i + 1}',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      title: Text(
                        holder.uid == myUid ? '$name (bạn)' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Text(
                        '${holder.owner.cellCount} ô',
                        style: theme.textTheme.titleSmall,
                      ),
                      onTap: () => Navigator.of(context).pop(holder),
                    );
                  },
                ),
          error: (error, _) {
            debugPrint('lãnh địa: tải người giữ ô lỗi: $error');
            return const Center(child: Text('Chưa tải được'));
          },
          loading: () => const RunNowLoading(label: 'Đang tải'),
        );
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
          minHeight: 160,
        ),
        child: body,
      ),
    );
  }
}

/// Chú thích độ đậm: ít km → nhiều km.
class _ShadeLegend extends StatelessWidget {
  const _ShadeLegend({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelSmall;
    return GlassPanel(
      borderRadius: 12,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 4,
        children: [
          Text('ít km', style: style),
          for (final alpha in territoryShadeLevels)
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: color.withValues(alpha: alpha),
                border: Border.all(color: color, width: 0.8),
              ),
            ),
          Text('nhiều', style: style),
        ],
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

class _CellSheet extends ConsumerWidget {
  const _CellSheet({required this.cell});

  final TerritoryCell cell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name =
        ref.watch(territoryNamesProvider)[cell.ownerUid]?.name ??
        territoryDefaultName;
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Row(
          children: [
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium,
              ),
            ),
            Text(territoryKm(cell.meters), style: theme.textTheme.titleMedium),
          ],
        ),
      ),
    );
  }
}

/// Khoe lãnh địa: đọc các ô của mình quanh chỗ giữ nhiều ô nhất rồi mở sheet
/// thẻ.
/// Chưa có ô nào thì không có nút.
class _ShareButton extends ConsumerStatefulWidget {
  const _ShareButton();

  @override
  ConsumerState<_ShareButton> createState() => _ShareButtonState();
}

class _ShareButtonState extends ConsumerState<_ShareButton> {
  var _loading = false;

  Future<void> _share(String uid, TerritoryOwner owner, String name) async {
    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final cells = await ref
          .read(territoryRepositoryProvider)
          .fetchOwnedCells(uid, territoryShareChunks(owner));
      if (!mounted) return;
      await showTerritoryShare(
        context,
        name: name,
        cellCount: owner.cellCount,
        cells: cells,
      );
    } catch (error) {
      debugPrint('khoe lãnh địa lỗi: $error');
      messenger.showSnackBar(
        const SnackBar(content: Text('Chưa khoe được lãnh địa')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = ref.watch(firebaseUserProvider).value?.uid;
    final owner = ref.watch(myTerritoryProvider).value;
    final name =
        ref.watch(userProfileProvider).value?.displayName ??
        territoryDefaultName;
    if (uid == null || owner == null || owner.cellCount == 0) {
      return const SizedBox.shrink();
    }
    return IconButton(
      onPressed: _loading ? null : () => _share(uid, owner, name),
      tooltip: 'Khoe lãnh địa',
      icon: const Icon(Icons.ios_share),
    );
  }
}
