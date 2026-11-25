import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/territory/territory_models.dart';
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

/// Màu ô trên bản đồ: của mình là màu chính của theme, mọi người khác một màu
/// chung ([territoryOthersColor]); muốn biết từng người thì lọc hay mở danh
/// sách Mọi người.
Color territoryMapColor(
  String ownerUid, {
  required String? myUid,
  required Color mine,
}) => ownerUid == myUid ? mine : territoryOthersColor(mine);

/// Màu ô người khác: xanh, trừ khi màu chính của theme có sắc gần xanh (lệch
/// dưới 45°, như theme Nước) thì dùng tím để hai màu vẫn tách nhau.
Color territoryOthersColor(Color mine) {
  final mineHue = HSVColor.fromColor(mine).hue;
  final blueHue = HSVColor.fromColor(RunNowTerritoryTokens.others).hue;
  final gap = (mineHue - blueHue).abs();
  final diff = gap > 180 ? 360 - gap : gap;
  return diff < 45
      ? RunNowTerritoryTokens.othersAlt
      : RunNowTerritoryTokens.others;
}

/// Màu riêng của một người cho avatar và thanh trong danh sách: của mình là màu
/// chính, người khác một màu cố định theo uid để mở lại vẫn ra cùng màu.
Color territoryOwnerColor(
  String ownerUid, {
  required String? myUid,
  required Color mine,
}) {
  if (ownerUid == myUid) return mine;
  const people = RunNowTerritoryTokens.people;
  return people[_stableHash(ownerUid) % people.length];
}

/// "2,6 km²", "61 ha", "6,8 ha": từ 1 km² ghi km², dưới 10 ha giữ một số lẻ.
String territoryArea(double m2) {
  String one(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
  final ha = m2 / 10000;
  if (ha >= 99.5) return '${one(ha / 100)} km²';
  // Làm tròn trước rồi mới chọn cách viết, để 9,96 ha ra "10 ha" chứ không
  // ra "10,0 ha".
  if (ha >= 9.95) return '${ha.round()} ha';
  return '${one(ha)} ha';
}

/// Ngưỡng mét cho bốn mức đậm của ô. Một lượt chạy xuyên ô dài khoảng
/// 150 m (cạnh ô z18 ở TP.HCM), nên 300/750/1500 m tương đương khoảng
/// 2/5/10 lượt. Số mét là số backend dùng để giữ ô (`m`, 30 ngày), nên ô càng
/// đậm càng khó bị chiếm.
const territoryShadeMeters = <int>[300, 750, 1500];
const _shadeAlpha = <double>[0.2, 0.38, 0.56, 0.74];

/// Độ đậm (alpha) của ô theo số mét chủ ô đã chạy trong ô.
double territoryCellAlpha(int meters) {
  var level = 0;
  while (level < territoryShadeMeters.length &&
      meters >= territoryShadeMeters[level]) {
    level++;
  }
  return _shadeAlpha[level];
}

/// Bốn mức đậm, để vẽ chú thích "ít → nhiều".
List<double> get territoryShadeLevels => _shadeAlpha;

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

/// Chữ trên chip kết quả buổi: "+N ô", và "chiếm của Bình" khi có ô chiếm
/// được. Nhiều người bị chiếm thì ghi người mất nhiều ô nhất, kèm "+k".
({String gain, String? takenFrom}) territoryResultText(
  TerritoryResult result,
  Map<String, ({String name, String? avatarUrl})> names,
) {
  final victims = result.taken.entries.toList()
    ..sort((a, b) {
      final byCount = b.value.compareTo(a.value);
      return byCount != 0 ? byCount : a.key.compareTo(b.key);
    });
  String? takenFrom;
  if (victims.isNotEmpty) {
    final first = names[victims.first.key]?.name ?? territoryDefaultName;
    final more = victims.length - 1;
    takenFrom = more == 0 ? 'chiếm của $first' : 'chiếm của $first +$more';
  }
  return (gain: '+${result.total} ô', takenFrom: takenFrom);
}

/// Chip "+N ô" của một buổi chạy, chạm mở màn Lãnh địa ở vùng buổi đó chạy
/// qua, kể cả buổi của người khác. Backend ghi kết quả
/// vài giây sau khi lưu buổi; chưa có thì không hiện gì, không chờ.
class TerritoryResultChip extends ConsumerWidget {
  const TerritoryResultChip({
    required this.uid,
    required this.activityId,
    this.padding = EdgeInsets.zero,
    super.key,
  });

  final String uid;
  final String activityId;

  /// Chỉ áp khi chip hiện, để chỗ đặt chip không dôi khoảng trống.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(ref.watch(territoryEnabledProvider).value ?? false)) {
      return const SizedBox.shrink();
    }
    final result = ref
        .watch(
          activityTerritoryResultProvider((uid: uid, activityId: activityId)),
        )
        .value;
    if (result == null || result.total == 0) return const SizedBox.shrink();
    final text = territoryResultText(result, ref.watch(territoryNamesProvider));
    final palette = context.runNowPalette;
    return Padding(
      padding: padding,
      child: Align(
        alignment: Alignment.centerLeft,
        child: ActionChip(
          avatar: Icon(
            Icons.grid_view_rounded,
            size: 18,
            color: palette.accent,
          ),
          label: Text(
            [text.gain, ?text.takenFrom].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onPressed: () =>
              context.push(territoryLocation(chunk: result.chunk?.id)),
        ),
      ),
    );
  }
}
