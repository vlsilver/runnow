import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/territory/territory_grid.dart';
import 'package:myrun/src/territory/territory_mini_map.dart';
import 'package:myrun/src/territory/territory_models.dart';
import 'package:myrun/src/territory/territory_repository.dart';
import 'package:myrun/src/territory/territory_sheets.dart';
import 'package:myrun/src/territory/territory_stats_screen.dart';
import 'package:myrun/src/territory/territory_widgets.dart';
import 'package:myrun/src/theme.dart';

/// Số người đầu BXH lãnh địa hiện ở Trang chủ.
const _homeTop = 3;

/// Mục "Lãnh địa" ở Trang chủ: bản đồ nhỏ các ô quanh chỗ mình giữ nhiều ô
/// nhất (chưa có ô thì chỗ người đứng đầu), rồi BXH lãnh địa: top 3 và dòng
/// của mình. Chỉ ẩn khi lãnh địa tắt. [header] do Trang chủ dựng (cùng kiểu
/// với các mục khác), nhận hàm mở màn Lãnh địa.
class TerritoryHomeSection extends ConsumerWidget {
  const TerritoryHomeSection({required this.header, super.key});

  final Widget Function(VoidCallback onMore) header;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(ref.watch(territoryEnabledProvider).value ?? false)) {
      return const SizedBox.shrink();
    }
    // Trang chủ không bao giờ đóng nên BXH không tự hết hạn: số ô của mình
    // đổi (backend ghi ô vài giây sau khi lưu buổi) thì đọc lại. null là doc
    // của mình chưa đọc xong; chưa có ô là 0.
    ref.listen(
      myTerritoryProvider.select(
        (owner) => owner.hasValue ? (owner.value?.cellCount ?? 0) : null,
      ),
      (previous, next) {
        if (previous != null && next != null && previous != next) {
          ref.invalidate(territoryHoldersProvider);
        }
      },
    );
    final holders = ref.watch(territoryHoldersProvider);
    final myUid = ref.watch(firebaseUserProvider).value?.uid;
    final palette = context.runNowPalette;
    final list = holders.value;
    final myRank = list?.indexWhere((h) => h.uid == myUid) ?? -1;
    // Chỗ mình giữ nhiều ô nhất; chưa có ô thì chỗ người đứng đầu.
    final center =
        (myRank >= 0 ? list![myRank] : list?.firstOrNull)?.owner.topChunk;
    void open() => context.push(territoryLocation(chunk: center?.id));
    final body = holders.when(
      data: (holders) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 170,
              child: InkWell(
                onTap: open,
                child: IgnorePointer(
                  child: center == null
                      ? ColoredBox(color: palette.tint)
                      : _HomeMiniMap(chunk: center, myUid: myUid),
                ),
              ),
            ),
            if (holders.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Chưa ai giữ ô, chạy qua ô để có ô.'),
              )
            else ...[
              for (var i = 0; i < holders.length && i < _homeTop; i++)
                _HolderRow(rank: i + 1, holder: holders[i], me: i == myRank),
              if (myRank >= _homeTop)
                _HolderRow(rank: myRank + 1, holder: holders[myRank], me: true),
              if (myRank < 0)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text('Bạn chưa giữ ô nào, chạy qua ô để có ô.'),
                ),
            ],
          ],
        );
      },
      error: (error, _) {
        debugPrint('lãnh địa: Trang chủ tải người giữ ô lỗi: $error');
        return ListTile(
          title: const Text('Chưa tải được lãnh địa'),
          trailing: const Icon(Icons.refresh_rounded),
          onTap: () => ref.invalidate(territoryHoldersProvider),
        );
      },
      // Giữ chỗ cỡ bản đồ cộng ba dòng BXH để mục về không đẩy các mục dưới.
      loading: () => SizedBox(
        height: 170 + _homeTop * 38,
        child: ColoredBox(color: palette.tint),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header(open),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Material(
            color: palette.tint,
            borderRadius: palette.radius(26),
            clipBehavior: Clip.antiAlias,
            child: body,
          ),
        ),
      ],
    );
  }
}

/// Một dòng BXH lãnh địa: hạng, avatar, tên, diện tích và số ô. Chạm mở
/// số liệu người đó; "Xem trên bản đồ" ở đó mở màn Lãnh địa.
class _HolderRow extends ConsumerWidget {
  const _HolderRow({
    required this.rank,
    required this.holder,
    required this.me,
  });

  final int rank;
  final TerritoryHolder holder;
  final bool me;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = context.runNowPalette;
    final name =
        ref.watch(territoryNamesProvider)[holder.uid]?.name ??
        territoryDefaultName;
    return Material(
      color: me ? palette.accent.withValues(alpha: 0.12) : Colors.transparent,
      child: InkWell(
        onTap: () async {
          // Navigator gốc như từ màn Lãnh địa, để thanh tab không đè.
          final picked = await Navigator.of(context, rootNavigator: true)
              .push<TerritoryOwner>(
                MaterialPageRoute(
                  builder: (_) => TerritoryStatsScreen(uid: holder.uid),
                ),
              );
          // "Xem trên bản đồ": mở đúng chỗ người đó giữ nhiều ô nhất.
          if (picked != null && context.mounted) {
            await context.push(territoryLocation(chunk: picked.topChunk?.id));
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            spacing: 12,
            children: [
              SizedBox(
                width: 22,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              TerritoryAvatar(uid: holder.uid, name: name, size: 26),
              Expanded(
                child: Text(
                  me ? '$name (bạn)' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              // Một dòng một người: chỉ diện tích; số ô xem ở màn số liệu.
              Text(
                territoryArea(holder.owner.areaM2),
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bản đồ nhỏ đứng yên: mọi ô của [chunk], tô theo chủ như màn Lãnh địa,
/// khung vừa ô của mình (không có thì mọi ô trong chunk).
class _HomeMiniMap extends ConsumerWidget {
  const _HomeMiniMap({required this.chunk, required this.myUid});

  final TileXY chunk;
  final String? myUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.runNowPalette;
    final cells =
        ref.watch(territoryChunkProvider(chunk)).value ??
        const <TerritoryCell>[];
    final mine = [
      for (final cell in cells)
        if (cell.ownerUid == myUid) cell,
    ];
    final fit = mine.isNotEmpty ? mine : cells;
    return TerritoryMiniMap(
      center: chunkCenter(chunk),
      fit: [for (final c in fit) c.tile],
      polygons: [
        for (final cell in cells)
          territoryCellPolygon(cell, myUid: myUid, mine: palette.accent),
      ],
    );
  }
}
