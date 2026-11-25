import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/territory/territory_grid.dart';
import 'package:myrun/src/territory/territory_models.dart';
import 'package:myrun/src/territory/territory_repository.dart';
import 'package:myrun/src/territory/territory_share.dart';
import 'package:myrun/src/territory/territory_widgets.dart';
import 'package:myrun/src/theme.dart';

/// Màu viền ô chiếm được trên thẻ nền tối: xanh nhạt, khác màu ô mới.
const _takenEdge = RunNowTerritoryTokens.posterTakenEdge;

/// Thẻ "+N ô" của một buổi: hình các ô mới (đặc) và ô chiếm được (viền xanh),
/// số ô, chiếm của ai, nút mở bản đồ đúng vùng của buổi. Chỉ mở khi backend đã
/// lưu từng ô ([TerritoryResult.hasCells]).
class TerritoryResultSheet extends ConsumerWidget {
  const TerritoryResultSheet({required this.result, super.key});

  final TerritoryResult result;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.runNowPalette;
    final names = ref.watch(territoryNamesProvider);
    final victims = result.taken.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    const ink = RunNowTerritoryTokens.posterInk;
    Widget legend(Widget swatch, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        swatch,
        Text(text, style: const TextStyle(color: ink, fontSize: 15)),
      ],
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 12,
          children: [
            DecoratedBox(
              decoration: const BoxDecoration(
                color: RunNowTerritoryTokens.posterBackground,
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: 8,
                  children: [
                    SizedBox(
                      height: 200,
                      width: double.infinity,
                      child: CustomPaint(
                        painter: _ResultPainter(
                          fresh: result.newCells,
                          taken: result.takenCells.keys.toList(),
                          color: palette.accent,
                        ),
                      ),
                    ),
                    Text(
                      '+${result.total} ô',
                      style: palette.heading(
                        TextStyle(
                          color: palette.accent,
                          fontSize: 52,
                          height: 1,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: 14,
                      runSpacing: 6,
                      children: [
                        if (result.gained > 0)
                          legend(
                            Container(
                              width: 12,
                              height: 12,
                              color: palette.accent,
                            ),
                            '${result.gained} ô mới',
                          ),
                        for (final MapEntry(:key, :value) in victims)
                          legend(
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: palette.accent,
                                border: Border.all(color: _takenEdge, width: 2),
                              ),
                            ),
                            'chiếm $value ô của '
                            '${names[key]?.name ?? territoryDefaultName}',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop();
                // Ô giữa danh sách, để buổi dài cũng mở vào giữa các ô.
                final cells = [...result.newCells, ...result.takenCells.keys];
                context.push(
                  territoryLocation(
                    chunk: result.chunk?.id,
                    cell: cells.isEmpty ? null : cells[cells.length ~/ 2].id,
                  ),
                );
              },
              child: const Text('Xem trên bản đồ'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultPainter extends CustomPainter {
  _ResultPainter({
    required this.fresh,
    required this.taken,
    required this.color,
  });

  final List<TileXY> fresh;
  final List<TileXY> taken;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final all = [...fresh, ...taken];
    final rects = territoryArtRects(all, size, padding: 4);
    final fill = Paint()..color = color;
    final edge = Paint()
      ..color = RunNowTerritoryTokens.posterBackground
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6;
    final takenEdge = Paint()
      ..color = _takenEdge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var i = 0; i < rects.length; i++) {
      final rect = rects[i];
      canvas.drawRect(rect, fill);
      if (i < fresh.length) {
        canvas.drawRect(rect, edge);
      } else {
        canvas.drawRect(rect.deflate(1), takenEdge);
      }
    }
  }

  @override
  bool shouldRepaint(_ResultPainter old) =>
      old.color != color ||
      !identical(old.fresh, fresh) ||
      !identical(old.taken, taken);
}
