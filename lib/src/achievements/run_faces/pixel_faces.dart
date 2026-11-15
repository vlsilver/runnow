import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:myrun/src/achievements/run_card_paths.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/achievements/run_faces/face_map.dart';
import 'package:myrun/src/achievements/run_faces/run_face_kit.dart';

/// Chữ điểm ảnh của bộ Pixel, cùng font với kiểu Pixel của app.
const _font = 'VT323';

TextStyle _px(double size, Color color, {double? h, double ls = 0}) =>
    TextStyle(
      fontFamily: _font,
      fontSize: size,
      color: color,
      height: h,
      letterSpacing: ls,
      leadingDistribution: TextLeadingDistribution.even,
      decoration: TextDecoration.none,
    );

Widget _line(String s, double size, Color color, {double ls = 0}) => Text(
  s,
  maxLines: 1,
  softWrap: false,
  overflow: TextOverflow.ellipsis,
  style: _px(size, color, ls: ls),
);

/// Một nửa hàng: chữ dài quá thì co lại chứ không tràn.
Widget _fitted(Widget child, {bool end = false}) => Flexible(
  child: fit(child, a: end ? Alignment.centerRight : Alignment.centerLeft),
);

/// Pixel không có bảng màu riêng: cảnh và chữ lấy màu của bộ màu thẻ.
class PixelFront extends StatelessWidget {
  const PixelFront(this.f, {super.key});

  final RunFace f;

  @override
  Widget build(BuildContext context) {
    final skin = RunCardSkin.of(context);
    final accent = skin.accent(f.tier);
    return faceBox(
      bg: skin.field,
      ink: skin.hero,
      children: [
        CustomPaint(painter: _ScenePainter(skin, accent, _seed(f))),
        badgeAt(f, l: 16, t: 44),
        pin(
          l: 16,
          r: 16,
          t: 12,
          h: 26,
          c: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _fitted(_line('PACE ${f.pace}', 24, skin.hero, ls: 1)),
              const SizedBox(width: 8),
              _fitted(_line('TIME ${f.time}', 24, skin.hero, ls: 1), end: true),
            ],
          ),
        ),
        pin(
          l: 16,
          r: 16,
          t: _groundBottom + 6,
          h: 74,
          c: fit(
            baseline([
              Text(
                f.km,
                maxLines: 1,
                softWrap: false,
                style: _px(100, skin.hero, h: 0.74).copyWith(
                  shadows: [Shadow(color: skin.routeLine, offset: _hard)],
                ),
              ),
              Text('KM', style: _px(34, skin.routeLine)),
            ], gap: 8),
          ),
        ),
        pin(
          l: 16,
          r: 16,
          b: 10,
          h: 20,
          c: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _fitted(_line(f.date, 18, skin.ink, ls: 1)),
              const SizedBox(width: 8),
              _fitted(_line('3I RUN', 18, accent, ls: 2), end: true),
            ],
          ),
        ),
      ],
    );
  }
}

const _hard = Offset(4, 4);

/// Ô của cảnh mặt trước; mặt thẻ 300×420 là 50×70 ô.
const _cell = 6.0;
const _horizonRow = 46;
const _groundRows = 4;
const _groundBottom = (_horizonRow + _groundRows) * _cell;

/// Mỗi buổi chạy ra một dãy nhà riêng nhưng vẽ lại vẫn y như cũ.
int _seed(RunFace f) => '${f.date}${f.km}${f.time}'.codeUnits.fold(
  7,
  (a, b) => (a * 31 + b) & 0x7fffffff,
);

const _moon = [
  '..XXXX..',
  '.XXXXXX.',
  'XXXXXXXX',
  'XXXXXoXX',
  'XXXXXXXX',
  'XXoXXXXX',
  '.XXXXXX.',
  '..XXXX..',
];

/// Người chạy; `o` là băng đô màu bậc thẻ.
const _runner = [
  '....XX....',
  '...oooo...',
  '....XX....',
  '..XXXXX.X.',
  '.X.XXXXX..',
  'X..XXX....',
  '...XXXX...',
  '..XX..XX..',
  '.XX....XX.',
  'XX......X.',
  '........XX',
];

class _ScenePainter extends CustomPainter {
  const _ScenePainter(this.skin, this.accent, this.seed);

  final RunCardSkin skin;
  final Color accent;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final paint = Paint()..isAntiAlias = false;
    void cell(num x, num y, Color c, {num w = 1, num h = 1, double u = _cell}) {
      paint.color = c;
      canvas.drawRect(Rect.fromLTWH(x * u, y * u, w * u, h * u), paint);
    }

    Color over(Color c, double a) =>
        Color.alphaBlend(c.withValues(alpha: a), skin.field);

    // Trời sáng dần về chân trời theo ba nấc.
    for (final (i, a) in const [0.05, 0.1, 0.16].indexed) {
      cell(0, _horizonRow - 18 + i * 6, over(skin.routeLine, a), w: 50, h: 6);
    }

    for (var i = 0; i < 26; i++) {
      final x = rnd.nextInt(50), y = 6 + rnd.nextInt(28);
      cell(x, y, i % 5 == 0 ? skin.routeLine : skin.ink.withValues(alpha: 0.7));
    }

    for (final (y, row) in _moon.indexed) {
      for (var x = 0; x < row.length; x++) {
        final ch = row[x];
        if (ch == '.') continue;
        cell(
          36 + x,
          9 + y,
          ch == 'o' ? Color.lerp(skin.hero, skin.field, 0.3)! : skin.hero,
        );
      }
    }

    // Hai lớp nhà: lớp xa nhạt và thấp, lớp gần đậm có cửa sổ sáng.
    void skyline(Color wall, int minH, int maxH, {Color? window}) {
      var x = 0;
      while (x < 50) {
        final w = 4 + rnd.nextInt(4);
        final h = minH + rnd.nextInt(maxH - minH + 1);
        cell(x, _horizonRow - h, wall, w: w, h: h);
        if (window != null) {
          for (var wy = 1; wy < h - 1; wy += 2) {
            for (var wx = 1; wx < w - 1; wx += 2) {
              if (rnd.nextInt(3) == 0) {
                cell(x + wx, _horizonRow - h + wy, window);
              }
            }
          }
        }
        x += w;
      }
    }

    skyline(over(skin.ink, 0.08), 8, 20);
    skyline(over(skin.ink, 0.17), 4, 13, window: skin.routeLine);

    cell(0, _horizonRow, over(skin.ink, 0.28), w: 50, h: _groundRows);
    for (var x = 1; x < 50; x += 6) {
      cell(x, _horizonRow + 2, skin.routeLine, w: 3);
    }
    cell(
      0,
      _horizonRow + _groundRows,
      skin.shade,
      w: 50,
      h: 70 - _horizonRow - _groundRows,
    );

    const u = _cell / 2;
    final top = _horizonRow * 2 - _runner.length;
    for (final (y, row) in _runner.indexed) {
      for (var x = 0; x < row.length; x++) {
        final ch = row[x];
        if (ch == '.') continue;
        cell(18 + x, top + y, ch == 'o' ? accent : skin.hero, u: u);
      }
    }
  }

  @override
  bool shouldRepaint(_ScenePainter old) =>
      old.skin != skin || old.accent != accent || old.seed != seed;
}

class PixelBack extends StatelessWidget {
  const PixelBack(this.f, {super.key, this.map = false});

  final RunFace f;
  final bool map;

  @override
  Widget build(BuildContext context) {
    final skin = RunCardSkin.of(context);
    final accent = skin.accent(f.tier);
    return faceBox(
      bg: skin.dataBack,
      ink: skin.hero,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _fitted(_line('3I RUN', 20, accent, ls: 2)),
                  const SizedBox(width: 8),
                  _fitted(_line(f.date, 20, skin.dataLabel, ls: 1), end: true),
                ],
              ),
              const SizedBox(height: 8),
              // 264×224 là 33×28 ô lưới.
              Container(
                height: 224,
                foregroundDecoration: BoxDecoration(
                  border: Border.all(color: skin.hero, width: 2),
                ),
                child: map
                    ? FaceMap(
                        f,
                        dark: skin.darkMap,
                        route: skin.routeLine,
                        stroke: 3.4,
                        padding: const EdgeInsets.all(26),
                        radius: 0,
                      )
                    : CustomPaint(
                        painter: _TilePainter(skin, f.route, f.series),
                      ),
              ),
              const Spacer(),
              for (final (label, value) in [
                ('PACE', '${f.pace} /KM'),
                ('TIME', f.time),
                ('KM', f.km),
              ])
                SizedBox(
                  height: 34,
                  child: Row(
                    children: [
                      _line(label, 26, skin.dataLabel, ls: 2),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: CustomPaint(
                            size: const Size.fromHeight(4),
                            painter: _DotLeader(skin.dataGrid),
                          ),
                        ),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: fit(
                          _line(value, 32, skin.hero, ls: 1),
                          a: Alignment.centerRight,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Hàng ô vuông nối nhãn với số.
class _DotLeader extends CustomPainter {
  const _DotLeader(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..isAntiAlias = false
      ..color = color;
    for (var x = 0.0; x + 4 <= size.width; x += 8) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 4, 4), paint);
    }
  }

  @override
  bool shouldRepaint(_DotLeader old) => old.color != color;
}

/// Đường chạy xếp bằng ô vuông trên nền lưới. Buổi không có GPS thì xếp cột
/// pace: cột cao là đoạn chạy nhanh.
class _TilePainter extends CustomPainter {
  const _TilePainter(this.skin, this.route, this.series);

  final RunCardSkin skin;
  final List<LatLng> route;
  final List<double> series;

  static const _tile = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cols = size.width ~/ _tile, rows = size.height ~/ _tile;
    final paint = Paint()..isAntiAlias = false;
    void tile(int x, int y, Color c) {
      paint.color = c;
      canvas.drawRect(Rect.fromLTWH(x * _tile, y * _tile, _tile, _tile), paint);
    }

    final dim = skin.dataGrid.withValues(alpha: skin.dataGrid.a * 0.5);
    for (var y = 0; y < rows; y++) {
      for (var x = y.isEven ? 0 : 1; x < cols; x += 2) {
        tile(x, y, dim);
      }
    }

    final points = fitRunRoute(
      route,
      Rect.fromLTRB(
        _tile * 2,
        _tile * 2,
        size.width - _tile * 2,
        size.height - _tile * 2,
      ),
    );
    if (points.isEmpty) {
      _bars(cols, rows, tile);
      return;
    }
    (int, int) at(Offset p) => (p.dx ~/ _tile, p.dy ~/ _tile);
    final cells = <(int, int)>{at(points.first)};
    for (var i = 0; i + 1 < points.length; i++) {
      final a = points[i], b = points[i + 1];
      final steps = ((b - a).distance / (_tile / 2)).ceil();
      for (var s = 1; s <= steps; s++) {
        cells.add(at(Offset.lerp(a, b, s / steps)!));
      }
    }
    for (final (x, y) in cells) {
      tile(x, y, skin.routeLine);
    }

    // Xuất phát là ô đặc có viền, đích là cờ ca rô.
    final (sx, sy) = at(points.first);
    paint.color = skin.hero;
    canvas.drawRect(
      Rect.fromLTWH(sx * _tile - 3, sy * _tile - 3, _tile + 6, _tile + 6),
      paint,
    );
    tile(sx, sy, skin.routeStart);
    final (ex, ey) = at(points.last);
    const q = (_tile + 4) / 2;
    for (var i = 0; i < 4; i++) {
      paint.color = (i == 0 || i == 3) ? skin.hero : skin.dataBack;
      canvas.drawRect(
        Rect.fromLTWH(
          ex * _tile - 2 + (i % 2) * q,
          ey * _tile - 2 + (i ~/ 2) * q,
          q,
          q,
        ),
        paint,
      );
    }
  }

  void _bars(int cols, int rows, void Function(int, int, Color) tile) {
    if (series.length < 2) return;
    final slow = series.reduce(math.max), fast = series.reduce(math.min);
    const first = 2;
    final count = (cols - first * 2 + 1) ~/ 2;
    for (var i = 0; i < count; i++) {
      final pace =
          series[(i * (series.length - 1) / math.max(count - 1, 1)).round()];
      final share = slow == fast
          ? 0.6
          : 0.25 + 0.75 * (slow - pace) / (slow - fast);
      final h = math.max(1, (share * (rows - 4)).round());
      for (var y = 0; y < h; y++) {
        tile(first + i * 2, rows - 3 - y, skin.routeLine);
      }
    }
  }

  @override
  bool shouldRepaint(_TilePainter old) =>
      old.skin != skin || old.route != route || old.series != series;
}
