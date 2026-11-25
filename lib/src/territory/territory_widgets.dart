import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/territory/territory_grid.dart';
import 'package:myrun/src/territory/territory_models.dart';
import 'package:myrun/src/territory/territory_repository.dart';
import 'package:myrun/src/territory/territory_result_sheet.dart';
import 'package:myrun/src/territory/territory_sheets.dart';
import 'package:myrun/src/theme.dart';

/// Route màn Lãnh địa; [chunk] (id "x_y" z13) mở đúng vùng đó. [taken] (từ
/// push bị chiếm) là người chiếm, số ô và các ô mình vừa mất.
String territoryLocation({String? chunk, String? cell, TerritoryTaken? taken}) {
  final query = {
    'chunk': ?chunk,
    'cell': ?cell,
    if (taken != null) ...{
      'by': taken.uid,
      'n': '${taken.count}',
      'lost': [for (final c in taken.cells) c.id].join(','),
      'to': ?taken.to,
    },
  };
  return Uri(
    path: '/lanh-dia',
    queryParameters: query.isEmpty ? null : query,
  ).toString();
}

/// Số ô tối đa một push bị chiếm mang theo (`territoryPushCells` ở backend).
const territoryTakenMaxCells = 40;

/// Đọc lại [TerritoryTaken] từ query của route hay data của push. Thiếu người
/// chiếm hay số ô thì null (push cũ chỉ có chunk). Link có thể tự gõ nên chặn
/// số ô và danh sách ô ở mức push thật gửi được: một buổi tối đa 3000 ô.
TerritoryTaken? parseTerritoryTaken(
  String? by,
  String? n,
  String? lost, {
  String? to,
}) {
  final count = int.tryParse(n ?? '');
  if (by == null || by.isEmpty || count == null || count <= 0) return null;
  if (count > 3000) return null;
  return (
    uid: by,
    count: count,
    cells: [
      for (final id in (lost ?? '').split(',').take(territoryTakenMaxCells))
        ?TileXY.parse(id),
    ],
    to: to == null || to.isEmpty ? null : to,
  );
}

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

/// Một ô trên bản đồ: màu theo chủ (của mình là [mine]), đậm theo km, viền
/// ô của mình dày hơn. Màn Lãnh địa, lớp ô dưới tuyến và Trang chủ dùng chung.
Polygon territoryCellPolygon(
  TerritoryCell cell, {
  required String? myUid,
  required Color mine,
}) {
  final color = territoryMapColor(cell.ownerUid, myUid: myUid, mine: mine);
  return Polygon(
    points: cellCorners(cell.tile),
    color: color.withValues(alpha: territoryCellAlpha(cell.meters)),
    borderColor: color,
    borderStrokeWidth: cell.ownerUid == myUid ? 1.4 : 0.8,
  );
}

/// Người bị chiếm ô trong buổi, mất nhiều ô nhất trước; bằng nhau thì theo
/// uid cho thứ tự cố định.
List<String> territoryVictims(TerritoryResult result) =>
    (result.taken.entries.toList()..sort((a, b) {
          final byCount = b.value.compareTo(a.value);
          return byCount != 0 ? byCount : a.key.compareTo(b.key);
        }))
        .map((e) => e.key)
        .toList();

/// Số avatar người bị chiếm hiện trên chip; nhiều hơn thì ghi "+k".
const _chipVictims = 3;

/// Chip "+N ô" của một buổi chạy, chạm mở màn Lãnh địa ở vùng buổi đó chạy
/// qua, kể cả buổi của người khác. Backend ghi kết quả
/// vài giây sau khi lưu buổi; chưa có thì không hiện gì, không chờ.
///
/// Buổi không có số ô (chạy trước khi bật lãnh địa, hay +0 ô) mà có
/// [fallbackCell] thì hiện "Xem lãnh địa", mở bản đồ ngay ô đó.
class TerritoryResultChip extends ConsumerWidget {
  const TerritoryResultChip({
    required this.uid,
    required this.activityId,
    this.padding = EdgeInsets.zero,
    this.fallbackCell,
    super.key,
  });

  final String uid;
  final String activityId;

  /// Id ô z18 giữa tuyến buổi, cho link khi buổi không có số ô. Là hàm để
  /// chỉ giải mã tuyến khi lãnh địa mở và buổi thật sự cần link.
  final ValueGetter<String?>? fallbackCell;

  /// Chỉ áp khi chip hiện, để chỗ đặt chip không dôi khoảng trống.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(ref.watch(territoryEnabledProvider).value ?? false)) {
      return const SizedBox.shrink();
    }
    final async = ref.watch(
      activityTerritoryResultProvider((uid: uid, activityId: activityId)),
    );
    final result = async.value;
    final palette = context.runNowPalette;
    if (result == null || result.total == 0) {
      // Đợi đọc xong mới hiện link, để buổi có số ô không chớp link trước.
      if (!async.hasValue) return const SizedBox.shrink();
      final cell = fallbackCell?.call();
      if (cell == null) return const SizedBox.shrink();
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
            label: const Text('Xem lãnh địa'),
            onPressed: () => context.push(territoryLocation(cell: cell)),
          ),
        ),
      );
    }
    final names = ref.watch(territoryNamesProvider);
    final victims = territoryVictims(result);
    return Padding(
      padding: padding,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ActionChip(
              avatar: Icon(
                Icons.grid_view_rounded,
                size: 18,
                color: palette.accent,
              ),
              label: Text('+${result.total} ô'),
              // Backend đã lưu từng ô thì mở thẻ có bản đồ nhỏ; kết quả cũ
              // chỉ có số thì mở thẳng bản đồ như trước.
              onPressed: () => result.hasCells
                  ? showModalBottomSheet<void>(
                      context: context,
                      showDragHandle: true,
                      isScrollControlled: true,
                      builder: (_) => TerritoryResultSheet(result: result),
                    )
                  : context.push(territoryLocation(chunk: result.chunk?.id)),
            ),
            if (victims.isNotEmpty)
              // Wrap để chữ to hay màn hẹp thì xuống dòng thay vì tràn.
              Wrap(
                spacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'chiếm của',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  for (final victim in victims.take(_chipVictims))
                    _VictimAvatar(
                      uid: victim,
                      name: names[victim]?.name ?? territoryDefaultName,
                    ),
                  if (victims.length > _chipVictims)
                    Text(
                      '+${victims.length - _chipVictims}',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Avatar một người bị chiếm ô; chạm mở hồ sơ của họ.
class _VictimAvatar extends StatelessWidget {
  const _VictimAvatar({required this.uid, required this.name});

  final String uid;
  final String name;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: name,
    child: InkResponse(
      onTap: () => context.push('/club/$uid'),
      radius: 22,
      // Vùng chạm 48 px như nút chuẩn, avatar 30 px ở giữa.
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: TerritoryAvatar(uid: uid, name: name, size: 30),
      ),
    ),
  );
}
