import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/territory/territory_grid.dart';
import 'package:myrun/src/territory/territory_models.dart';
import 'package:myrun/src/territory/territory_repository.dart';
import 'package:myrun/src/territory/territory_share.dart';
import 'package:myrun/src/territory/territory_sheets.dart';
import 'package:myrun/src/territory/territory_widgets.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/map_vector.dart';
import 'package:myrun/src/widgets/run_now_loading.dart';

/// Số liệu lãnh địa của một người: bản đồ nhỏ các ô ở chỗ họ giữ nhiều ô
/// nhất, hạng, diện tích, số ô, km trong lãnh địa, ô chắc nhất, ô bị bám sát.
/// "Xem trên bản đồ" đóng màn và trả về số ô của người đó để bản đồ lọc.
class TerritoryStatsScreen extends ConsumerWidget {
  const TerritoryStatsScreen({required this.uid, super.key});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myUid = ref.watch(firebaseUserProvider).value?.uid;
    final mine = uid == myUid;
    final name =
        ref.watch(territoryNamesProvider)[uid]?.name ?? territoryDefaultName;
    final owner = ref.watch(territoryOwnerProvider(uid));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          mine ? 'Lãnh địa của bạn' : 'Lãnh địa của $name',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: owner.when(
        data: (owner) => _Body(uid: uid, name: name, owner: owner, mine: mine),
        error: (error, _) {
          debugPrint('lãnh địa: tải số liệu của $uid lỗi: $error');
          return const Center(child: Text('Chưa tải được'));
        },
        loading: () => const RunNowLoading(label: 'Đang tải'),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.uid,
    required this.name,
    required this.owner,
    required this.mine,
  });

  final String uid;
  final String name;
  final TerritoryOwner owner;
  final bool mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = context.runNowPalette;
    final holders = ref.watch(territoryHoldersProvider).value;
    final rank = holders?.indexWhere((h) => h.uid == uid);
    final cells = ref.watch(territoryOwnedCellsProvider(uid));
    final stats = cells.hasValue ? TerritoryStats(cells.value!) : null;
    if (cells.hasError) {
      debugPrint('lãnh địa: đọc ô của $uid lỗi: ${cells.error}');
    }
    // Đang đọc thì "…", đọc lỗi thì "–".
    final missing = cells.hasError ? '–' : '…';
    String number(int? n) => n?.toString() ?? missing;
    String km(int? meters) => meters == null ? missing : territoryKm(meters);
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 240,
            child: _CellsMap(
              owner: owner,
              cells: cells.value ?? const [],
              color: territoryMapColor(
                uid,
                myUid: mine ? uid : null,
                mine: palette.accent,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  spacing: 12,
                  children: [
                    TerritoryAvatar(uid: uid, name: name, size: 48),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                          if (rank != null && rank >= 0)
                            Text(
                              'Hạng ${rank + 1} / ${holders!.length} người '
                              'giữ ô',
                              style: theme.textTheme.bodySmall,
                            ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          territoryArea(owner.areaM2),
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: palette.accent,
                          ),
                        ),
                        Text('diện tích giữ', style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 2.2,
                  children: [
                    _Stat(value: '${owner.cellCount}', label: 'ô đang giữ'),
                    _Stat(value: km(stats?.meters), label: 'km trong lãnh địa'),
                    _Stat(
                      value: km(stats?.strongestMeters),
                      label: 'ô chắc nhất',
                    ),
                    _Stat(
                      value: number(stats?.contested),
                      label: 'ô bị bám sát',
                      color: (stats?.contested ?? 0) > 0
                          ? palette.accent
                          : null,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Row(
              spacing: 8,
              children: [
                if (mine && owner.cellCount > 0)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => shareMyTerritory(
                        context,
                        ref,
                        uid: uid,
                        owner: owner,
                      ),
                      icon: const Icon(Icons.ios_share),
                      label: const Text('Khoe lãnh địa'),
                    ),
                  ),
                Expanded(
                  child: OutlinedButton(
                    onPressed: owner.cellCount == 0
                        ? null
                        : () => Navigator.of(context).pop(owner),
                    child: const Text('Xem trên bản đồ'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.color});

  final String value;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(color: color),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Bản đồ nhỏ không kéo được: các ô ở chunk người đó giữ nhiều ô nhất, đậm
/// theo km.
class _CellsMap extends StatelessWidget {
  const _CellsMap({
    required this.owner,
    required this.cells,
    required this.color,
  });

  final TerritoryOwner owner;
  final List<TerritoryCell> cells;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final top = owner.topChunk;
    final palette = context.runNowPalette;
    if (top == null) return ColoredBox(color: palette.tint);
    final shown = [
      for (final cell in cells)
        if (chunkOfCell(cell.tile) == top) cell,
    ];
    final dark = Theme.of(context).brightness == Brightness.dark;
    final center = chunkCenter(top);
    return FlutterMap(
      // Đổi khoá khi ô về để camera fit lại vào các ô.
      key: ValueKey(shown.length),
      options: MapOptions(
        initialCenter: center,
        initialZoom: 15,
        initialCameraFit: shown.isEmpty
            ? null
            : CameraFit.coordinates(
                coordinates: [for (final c in shown) ...cellCorners(c.tile)],
                padding: const EdgeInsets.all(24),
                maxZoom: 17,
              ),
        backgroundColor: palette.tint,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.none,
        ),
      ),
      children: [
        mapBaseLayer(context, dark: dark, around: [center]),
        PolygonLayer(
          polygons: [
            for (final cell in shown)
              Polygon(
                points: cellCorners(cell.tile),
                color: color.withValues(alpha: territoryCellAlpha(cell.meters)),
                borderColor: color,
                borderStrokeWidth: 1,
              ),
          ],
        ),
      ],
    );
  }
}
