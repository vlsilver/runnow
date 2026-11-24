import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../share.dart';
import '../theme.dart';
import 'territory_grid.dart';
import 'territory_models.dart';

/// Câu gửi kèm ảnh lãnh địa.
String territoryShareCaption(String name, int cellCount) =>
    '$name giữ $cellCount ô lãnh địa trên 3i';

/// Mở sheet xem trước thẻ lãnh địa rồi mới khoe. Web không gửi được file nên
/// chỉ gửi chữ, như các thẻ khác.
Future<void> showTerritoryShare(
  BuildContext context, {
  required String name,
  required int cellCount,
  required List<TileXY> cells,
}) async {
  final caption = territoryShareCaption(name, cellCount);
  if (kIsWeb) {
    await SharePlus.instance.share(ShareParams(text: caption));
    return;
  }
  await showShareCardSheet(
    context,
    caption: caption,
    fileName: '3i-lanh-dia.png',
    label: 'Khoe lãnh địa',
    card: TerritoryPoster(name: name, cellCount: cellCount, cells: cells),
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

/// Thẻ dọc 3:4 khoe lãnh địa: các ô của mình trên nền tối, số ô và tên. Không
/// vẽ tile bản đồ, chỉ hình các ô.
class TerritoryPoster extends StatelessWidget {
  const TerritoryPoster({
    required this.name,
    required this.cellCount,
    required this.cells,
    super.key,
  });

  final String name;
  final int cellCount;
  final List<TileXY> cells;

  static const size = Size(360, 480);
  static const _background = RunNowTerritoryTokens.posterBackground;
  static const _ink = RunNowTerritoryTokens.posterInk;
  static const _muted = RunNowTerritoryTokens.posterMuted;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return SizedBox.fromSize(
      size: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _background,
          borderRadius: palette.radius(20),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'LÃNH ĐỊA',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: _muted,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: CustomPaint(
                  painter: _CellsPainter(cells, palette.accent),
                  child: const SizedBox.expand(),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '$cellCount ô',
                style: palette.heading(
                  TextStyle(
                    color: palette.accent,
                    fontSize: 56,
                    height: 1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CellsPainter extends CustomPainter {
  _CellsPainter(this.cells, this.color);

  final List<TileXY> cells;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = color.withValues(alpha: 0.8);
    final edge = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    for (final rect in territoryArtRects(cells, size, padding: 8)) {
      canvas.drawRect(rect, fill);
      canvas.drawRect(rect, edge);
    }
  }

  @override
  bool shouldRepaint(_CellsPainter old) =>
      old.color != color || !identical(old.cells, cells);
}
