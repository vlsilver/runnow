import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
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

/// Màn Lãnh địa: ô của mình và của người khác trên bản đồ, chạm ô xem chủ ô.
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
/// [territoryMaxChunks]; zoom xa hơn thì không tải ô.
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

  void _openCell(LatLng point) {
    final tile = tileAt(point, territoryCellZoom);
    final chunk = chunkOfCell(tile);
    if (!(_chunks?.contains(chunk) ?? false)) return;
    final cells = ref.read(territoryChunkProvider(chunk)).value;
    final cell = cells?.where((c) => c.tile == tile).firstOrNull;
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
    final cells = [
      for (final chunk in _chunks ?? const <TileXY>[])
        ...?ref.watch(territoryChunkProvider(chunk)).value,
    ];
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
            onPositionChanged: (camera, _) => _updateChunks(camera),
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
          top: 12,
          left: 0,
          right: 0,
          child: Center(child: _Badge(tooFar: _chunks == null)),
        ),
      ],
    );
  }

  Polygon _polygon(TerritoryCell cell, String? myUid, Color mine) {
    final color = territoryOwnerColor(cell.ownerUid, myUid: myUid, mine: mine);
    final isMine = cell.ownerUid == myUid;
    return Polygon(
      points: cellCorners(cell.tile),
      color: color.withValues(alpha: isMine ? 0.55 : 0.4),
      borderColor: color,
      borderStrokeWidth: 0.8,
    );
  }
}

/// Nhãn trên cùng: số ô của mình, hay nhắc phóng to khi zoom quá xa.
class _Badge extends ConsumerWidget {
  const _Badge({required this.tooFar});

  final bool tooFar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(myTerritoryProvider).value?.cellCount;
    if (!tooFar && count == null) return const SizedBox.shrink();
    return GlassPanel(
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Text(
        tooFar ? 'Phóng to để xem ô' : '$count ô',
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
