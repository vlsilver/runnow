import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../providers.dart';
import '../achievements/run_faces/face_map.dart' show mapCreditLine;
import '../share.dart';
import '../theme.dart';
import '../widgets/map_vector.dart';
import 'territory_grid.dart';
import 'territory_models.dart';
import 'territory_repository.dart';
import 'territory_widgets.dart';

/// Câu gửi kèm ảnh lãnh địa.
String territoryShareCaption(String name, String area) =>
    '$name giữ $area lãnh địa trên 3i';

/// Đang mở thẻ khoe: bấm lần nữa (nút ở thanh trên hay ở màn Thông số) không
/// đọc lại và không chồng thêm sheet.
var _sharing = false;

/// Khoe lãnh địa của mình: đọc các ô quanh chỗ giữ nhiều ô nhất rồi mở sheet
/// thẻ. Lỗi thì báo một câu ngắn, lỗi gốc vào log.
Future<void> shareMyTerritory(
  BuildContext context,
  WidgetRef ref, {
  required String uid,
  required TerritoryOwner owner,
}) async {
  if (_sharing) return;
  _sharing = true;
  try {
    await _shareMyTerritory(context, ref, uid: uid, owner: owner);
  } finally {
    _sharing = false;
  }
}

Future<void> _shareMyTerritory(
  BuildContext context,
  WidgetRef ref, {
  required String uid,
  required TerritoryOwner owner,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final name =
      ref.read(userProfileProvider).value?.displayName ?? territoryDefaultName;
  try {
    final cells = await ref
        .read(territoryRepositoryProvider)
        .fetchOwnedCells(uid, territoryShareChunks(owner));
    if (!context.mounted) return;
    await showTerritoryShare(
      context,
      name: name,
      owner: owner,
      cells: [for (final c in cells) c.tile],
    );
  } catch (error) {
    debugPrint('khoe lãnh địa lỗi: $error');
    messenger.showSnackBar(
      const SnackBar(content: Text('Chưa khoe được lãnh địa')),
    );
  }
}

/// Mở sheet xem trước thẻ lãnh địa rồi khoe; khổ ảnh theo Cài đặt như mọi
/// thẻ khác. Web không gửi được
/// file nên chỉ gửi chữ, như các thẻ khác.
Future<void> showTerritoryShare(
  BuildContext context, {
  required String name,
  required TerritoryOwner owner,
  required List<TileXY> cells,
  DateTime? date,
}) async {
  final area = territoryArea(owner.areaM2);
  final caption = territoryShareCaption(name, area);
  if (kIsWeb) {
    await SharePlus.instance.share(ShareParams(text: caption));
    return;
  }
  await showShareCardSheet(
    context,
    caption: caption,
    fileName: '3i-lanh-dia.png',
    label: 'Chia sẻ',
    card: TerritoryPoster(
      name: name,
      area: area,
      cellCount: owner.cellCount,
      cells: cells,
      date: date ?? DateTime.now(),
    ),
  );
}

/// Các chunk có ô vẽ lên thẻ: chunk giữ nhiều ô nhất và 8 chunk quanh nó,
/// chỉ những chunk có ô của mình. Vẽ cả ô ở hai thành phố thì khung bao phủ
/// hàng trăm km và mỗi ô nhỏ dưới 1 px. Số ô trên thẻ vẫn là tổng mọi nơi.
List<TileXY> territoryShareChunks(TerritoryOwner owner) {
  final top = owner.topChunk;
  if (top == null) return const [];
  return [
    for (final chunk in owner.byChunk.keys)
      if ((chunk.x - top.x).abs() <= 1 && (chunk.y - top.y).abs() <= 1) chunk,
  ];
}

/// Ô vẽ to nhất trên thẻ, để người mới có một hai ô không ra một khối vuông
/// chiếm cả thẻ.
const _maxCellSide = 28.0;

/// Hình chữ nhật của từng ô khi vẽ [cells] vừa khung [size], chừa [padding]
/// mỗi bên. Ô z18 là ô vuông đều trên lưới Mercator nên vẽ thẳng theo toạ độ
/// tile, không cần đổi ra lat/lng. Hình được canh giữa khung.
List<Rect> territoryArtRects(
  List<TileXY> cells,
  Size size, {
  double padding = 0,
  double maxSide = _maxCellSide,
}) {
  if (cells.isEmpty) return const [];
  var minX = cells.first.x, maxX = cells.first.x;
  var minY = cells.first.y, maxY = cells.first.y;
  for (final c in cells) {
    minX = math.min(minX, c.x);
    maxX = math.max(maxX, c.x);
    minY = math.min(minY, c.y);
    maxY = math.max(maxY, c.y);
  }
  final columns = maxX - minX + 1;
  final rows = maxY - minY + 1;
  final width = size.width - 2 * padding;
  final height = size.height - 2 * padding;
  final side = math.min(maxSide, math.min(width / columns, height / rows));
  final left = padding + (width - side * columns) / 2;
  final top = padding + (height - side * rows) / 2;
  return [
    for (final c in cells)
      Rect.fromLTWH(
        left + (c.x - minX) * side,
        top + (c.y - minY) * side,
        side,
        side,
      ),
  ];
}

/// Thẻ dọc 3:4 khoe lãnh địa: các ô của mình trên nền bản đồ tối, diện tích,
/// tên, số ô và ngày. Nền bản đồ cho người xem thấy chỗ mình hay chạy; người
/// khoe là người chọn gửi.
class TerritoryPoster extends StatelessWidget {
  const TerritoryPoster({
    required this.name,
    required this.area,
    required this.cellCount,
    required this.cells,
    required this.date,
    super.key,
  });

  final String name;

  /// "2,6 km²", từ [territoryArea].
  final String area;
  final int cellCount;
  final List<TileXY> cells;
  final DateTime date;

  static const size = Size(360, 480);
  static const _background = RunNowTerritoryTokens.posterBackground;
  static const _ink = RunNowTerritoryTokens.posterInk;
  static const _muted = RunNowTerritoryTokens.posterMuted;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return SizedBox.fromSize(
      size: size,
      child: ClipRRect(
        borderRadius: palette.radius(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: _background),
            if (cells.isNotEmpty)
              _PosterMap(cells: cells, color: palette.accent),
            // Tối dần ở đầu và đáy để chữ đọc được trên nền bản đồ.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.18, 0.5, 1],
                  colors: [
                    _background.withValues(alpha: 0.85),
                    _background.withValues(alpha: 0),
                    _background.withValues(alpha: 0),
                    _background.withValues(alpha: 0.95),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '3I RUN',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.4,
                            color: _ink,
                          ),
                        ),
                      ),
                      Text(
                        _date(date),
                        style: const TextStyle(
                          fontSize: 12,
                          letterSpacing: 1.2,
                          color: _ink,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    area,
                    style: palette.heading(
                      TextStyle(
                        color: palette.accent,
                        fontSize: 56,
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$cellCount ô',
                    style: const TextStyle(color: _ink, fontSize: 15),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Ảnh khoe không bấm được nên ghi công bản đồ in thẳng lên.
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      mapCreditLine(),
                      style: const TextStyle(fontSize: 8, color: _muted),
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

/// Bản đồ tối đứng yên dưới thẻ khoe: khung vừa các ô, chừa chỗ cho chữ ở
/// đầu và đáy thẻ.
class _PosterMap extends StatelessWidget {
  const _PosterMap({required this.cells, required this.color});

  final List<TileXY> cells;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final corners = [for (final c in cells) ...cellCorners(c)];
    return IgnorePointer(
      child: FlutterMap(
        options: MapOptions(
          initialCenter: cellCenter(cells.first),
          initialCameraFit: CameraFit.coordinates(
            coordinates: corners,
            padding: const EdgeInsets.fromLTRB(28, 56, 28, 130),
            maxZoom: 16,
          ),
          backgroundColor: RunNowTerritoryTokens.posterBackground,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.none,
          ),
        ),
        children: [
          mapBaseLayer(context, dark: true, around: [cellCenter(cells.first)]),
          PolygonLayer(
            polygons: [
              for (final c in cells)
                Polygon(
                  points: cellCorners(c),
                  color: color.withValues(alpha: 0.6),
                  borderColor: color,
                  borderStrokeWidth: 1,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "25.11.2026".
String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
