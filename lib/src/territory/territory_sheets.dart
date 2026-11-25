import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/territory/territory_models.dart';
import 'package:myrun/src/territory/territory_repository.dart';
import 'package:myrun/src/territory/territory_widgets.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';
import 'package:myrun/src/widgets/run_now_avatar.dart';
import 'package:myrun/src/widgets/run_now_loading.dart';

/// Luật lãnh địa trong bốn dòng, mở từ nút "Là gì?".
class TerritoryRulesSheet extends StatelessWidget {
  const TerritoryRulesSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.runNowPalette;
    Widget rule(IconData icon, String title, String detail) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 14,
      children: [
        Container(
          width: 44,
          height: 44,
          color: palette.accent.withValues(alpha: 0.14),
          child: Icon(icon, color: palette.accent),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              Text(detail, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ],
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            Text('Lãnh địa là gì?', style: theme.textTheme.headlineSmall),
            rule(
              Icons.grid_view_rounded,
              'Chạy qua ô là có ô',
              'Mỗi ô khoảng 150 m. Bỏ 200 m đầu và cuối buổi.',
            ),
            rule(
              Icons.bar_chart_rounded,
              'Nhiều km nhất giữ ô',
              'Tính km trong ô 30 ngày gần nhất.',
            ),
            rule(
              Icons.layers_rounded,
              'Ô càng đậm càng khó chiếm',
              'Muốn chiếm, chạy trong ô nhiều km hơn chủ ô.',
            ),
            rule(
              Icons.visibility_outlined,
              'Chỉ hồ sơ công khai',
              'Bản đồ ô cho thấy chỗ bạn hay chạy.',
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Đã hiểu'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chạm một ô: chủ ô, km giữ ô, người bám sau, cần bao nhiêu để chiếm. Chỉ
/// để xem, không có nút.
class TerritoryCellSheet extends ConsumerWidget {
  const TerritoryCellSheet({required this.cell, super.key});

  final TerritoryCell cell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = context.runNowPalette;
    final myUid = ref.watch(firebaseUserProvider).value?.uid;
    final mine = cell.ownerUid == myUid;
    final name =
        ref.watch(territoryNamesProvider)[cell.ownerUid]?.name ??
        territoryDefaultName;
    final mapColor = territoryMapColor(
      cell.ownerUid,
      myUid: myUid,
      mine: palette.accent,
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            Row(
              spacing: 12,
              children: [
                TerritoryAvatar(uid: cell.ownerUid, name: name),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mine ? '$name (bạn)' : name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      Text(
                        'Giữ ô này trong 30 ngày qua',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  territoryKm(cell.meters),
                  style: theme.textTheme.headlineSmall,
                ),
              ],
            ),
            if (cell.secondMeters > 0)
              Column(
                spacing: 6,
                children: [
                  _MetersBar(
                    label: 'Chủ ô',
                    meters: cell.meters,
                    max: cell.meters,
                    color: mapColor,
                  ),
                  _MetersBar(
                    label: 'Người bám sau',
                    meters: cell.secondMeters,
                    max: cell.meters,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                ],
              ),
            if (!mine)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Row(
                  spacing: 10,
                  children: [
                    Icon(Icons.bolt_rounded, color: palette.accent),
                    Expanded(
                      child: Text(
                        'Chạy hơn ${territoryKm(cell.meters)} trong ô này '
                        'để chiếm',
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Một thanh so km: nhãn, thanh dài theo [meters]/[max], số km.
class _MetersBar extends StatelessWidget {
  const _MetersBar({
    required this.label,
    required this.meters,
    required this.max,
    required this.color,
  });

  final String label;
  final int meters;
  final int max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      spacing: 10,
      children: [
        SizedBox(
          width: 104,
          child: Text(label, style: theme.textTheme.bodySmall),
        ),
        Expanded(
          child: LinearProgressIndicator(
            value: max == 0 ? 0 : (meters / max).clamp(0, 1).toDouble(),
            minHeight: 8,
            color: color,
            backgroundColor: theme.dividerColor,
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(
            territoryKm(meters),
            textAlign: TextAlign.right,
            style: theme.textTheme.labelLarge,
          ),
        ),
      ],
    );
  }
}

/// Avatar chữ cái đầu trên nền màu riêng của người đó.
class TerritoryAvatar extends ConsumerWidget {
  const TerritoryAvatar({
    required this.uid,
    required this.name,
    this.avatarUrl,
    this.size = 44,
    super.key,
  });

  final String uid;
  final String name;

  /// Ảnh đại diện; không truyền thì lấy từ BXH đã tải. Có ảnh thì phủ lên chữ
  /// cái đầu.
  final String? avatarUrl;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myUid = ref.watch(firebaseUserProvider).value?.uid;
    final palette = context.runNowPalette;
    final color = territoryOwnerColor(uid, myUid: myUid, mine: palette.accent);
    final initial = name.trim().isEmpty
        ? '?'
        : name.trim().characters.first.toUpperCase();
    final url = avatarUrl ?? ref.watch(territoryNamesProvider)[uid]?.avatarUrl;
    // Theo theme như mọi avatar của app: vuông ở kiểu Thép, Pixel.
    return RunNowAvatar(
      radius: size / 2,
      backgroundColor: color,
      foregroundImage: url == null || url.isEmpty
          ? null
          : cachedAvatarImage(context, url, size),
      child: Text(
        initial,
        style: TextStyle(
          // Màu chính có theme sáng (Mộc), chữ trắng trên đó không đọc được.
          color: uid == myUid ? palette.onAccent : Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.42,
        ),
      ),
    );
  }
}

/// Danh sách người giữ ô, nhiều ô trước: hạng, avatar, thanh so số ô, diện
/// tích. Chạm một người thì đóng sheet và trả người đó về.
class TerritoryHoldersSheet extends ConsumerWidget {
  const TerritoryHoldersSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final palette = context.runNowPalette;
    final myUid = ref.watch(firebaseUserProvider).value?.uid;
    final names = ref.watch(territoryNamesProvider);
    final body = ref
        .watch(territoryHoldersProvider)
        .when(
          data: (holders) {
            if (holders.isEmpty) {
              return const Center(child: Text('Chưa ai giữ ô'));
            }
            final most = holders.first.owner.cellCount;
            final total = holders.fold<double>(
              0,
              (sum, h) => sum + h.owner.areaM2,
            );
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Mọi người',
                          style: theme.textTheme.headlineSmall,
                        ),
                      ),
                      Text(
                        '${holders.length} người giữ ${territoryArea(total)}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: holders.length,
                    itemBuilder: (context, i) {
                      final holder = holders[i];
                      final me = holder.uid == myUid;
                      final name =
                          names[holder.uid]?.name ?? territoryDefaultName;
                      final color = territoryOwnerColor(
                        holder.uid,
                        myUid: myUid,
                        mine: palette.accent,
                      );
                      return Material(
                        color: me
                            ? palette.accent.withValues(alpha: 0.12)
                            : Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(holder),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 10,
                            ),
                            child: Row(
                              spacing: 12,
                              children: [
                                SizedBox(
                                  width: 22,
                                  child: Text(
                                    '${i + 1}',
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.titleSmall,
                                  ),
                                ),
                                TerritoryAvatar(
                                  uid: holder.uid,
                                  name: name,
                                  size: 40,
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    spacing: 6,
                                    children: [
                                      Text(
                                        me ? '$name (bạn)' : name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleSmall,
                                      ),
                                      LinearProgressIndicator(
                                        value: holder.owner.cellCount / most,
                                        minHeight: 6,
                                        color: color,
                                        backgroundColor: theme.dividerColor,
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  width: 76,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        territoryArea(holder.owner.areaM2),
                                        style: theme.textTheme.titleMedium,
                                      ),
                                      Text(
                                        '${holder.owner.cellCount} ô',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
          error: (error, _) {
            debugPrint('lãnh địa: tải người giữ ô lỗi: $error');
            return const Center(child: Text('Chưa tải được'));
          },
          loading: () => const RunNowLoading(label: 'Đang tải'),
        );
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
          minHeight: 160,
        ),
        child: body,
      ),
    );
  }
}
