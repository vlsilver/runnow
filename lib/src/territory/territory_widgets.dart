import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/territory/territory_repository.dart';
import 'package:myrun/src/theme.dart';

/// Route màn Lãnh địa; [chunk] (id "x_y" z13) mở đúng vùng đó.
String territoryLocation({String? chunk}) => Uri(
  path: '/lanh-dia',
  queryParameters: chunk == null ? null : {'chunk': chunk},
).toString();

/// "1,2 km" từ số mét của chủ ô.
String territoryKm(int meters) =>
    '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';

/// Màu ô: của mình là màu chính của theme; người khác là một tông trung tính
/// cố định theo uid, để mở lại màn vẫn ra cùng màu.
Color territoryOwnerColor(
  String ownerUid, {
  required String? myUid,
  required Color mine,
}) {
  if (ownerUid == myUid) return mine;
  const others = RunNowTerritoryTokens.otherOwners;
  return others[_stableHash(ownerUid) % others.length];
}

/// FNV-1a 32 bit trên mã UTF-16: `String.hashCode` không hứa giữ nguyên giữa
/// các lần chạy hay giữa web và máy.
int _stableHash(String text) {
  var hash = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
  }
  return hash;
}

/// Dòng "Lãnh địa · N ô" ở Trang chủ, chạm mở màn Lãnh địa. Không hiện gì khi
/// cờ tắt hay chưa đăng nhập.
class TerritoryHomeRow extends ConsumerWidget {
  const TerritoryHomeRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(ref.watch(territoryEnabledProvider).value ?? false)) {
      return const SizedBox.shrink();
    }
    final owner = ref.watch(myTerritoryProvider);
    if (owner.hasValue && owner.value == null) return const SizedBox.shrink();
    final palette = context.runNowPalette;
    final count = owner.value?.cellCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: palette.tint,
        shape: palette.roundBorder,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push(territoryLocation()),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
            child: Row(
              children: [
                Icon(Icons.grid_view_rounded, size: 20, color: palette.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    count == null ? 'Lãnh địa' : 'Lãnh địa · $count ô',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.45),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
