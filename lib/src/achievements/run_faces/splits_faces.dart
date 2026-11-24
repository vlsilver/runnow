import 'package:flutter/material.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/achievements/run_faces/face_map.dart';
import 'package:myrun/src/achievements/run_faces/run_face_kit.dart';

/// Mặt sau liệt kê pace từng km, tối đa 10 hàng, theo bộ màu thẻ.
class SplitsBack extends StatelessWidget {
  const SplitsBack(this.f, {super.key, this.map = false});

  final RunFace f;
  final bool map;

  @override
  Widget build(BuildContext context) {
    final skin = RunCardSkin.of(context);
    final rows = f.rows(map ? 6 : 10);
    // Ít hàng thì các hàng nằm sát nhau, chỗ thừa nhường cho bản đồ hoặc đường
    // chạy lớn. Không có đường chạy thì bảng giữ giữa khung.
    final compact = map || (f.hasRoute && rows.length <= 6);
    final pitch = map ? 21.0 : (compact ? 24.0 : 30.0);
    final table = Container(
      padding: EdgeInsets.symmetric(vertical: map ? 6 : 9),
      decoration: BoxDecoration(
        border: Border.symmetric(horizontal: BorderSide(color: skin.dataGrid)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final row in rows)
            if (compact)
              SizedBox(height: pitch, child: _row(skin, row))
            else
              Flexible(
                child: SizedBox(height: pitch, child: _row(skin, row)),
              ),
        ],
      ),
    );
    // Phần dưới ô vẽ đường chạy: chân thẻ, cộng bảng nếu có.
    final below = 85.0 + (rows.isEmpty ? 0 : 30 + 24 * rows.length);
    return faceBox(
      bg: skin.dataBack,
      ink: skin.hero,
      children: [
        if (f.hasRoute && !map)
          FaceMap(
            f,
            dark: skin.darkMap,
            route: null,
            // Đường chạy lớn thì map trùng nét vẽ, còn icon nhỏ ở tiêu đề thì
            // map chỉ cần nằm giữa thẻ.
            padding: compact
                ? EdgeInsets.fromLTRB(19, 71, 19, below + 3)
                : const EdgeInsets.fromLTRB(40, 70, 40, 100),
            maxZoom: 22,
            tileFilter: faceMapWash(
              skin.hero,
              dark: skin.darkMap,
              strength: 0.26,
            ),
            creditAt: Alignment.bottomCenter,
            creditPadding: const EdgeInsets.only(bottom: 14),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            children: [
              SizedBox(
                height: 44,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        txt('3I RUN', 11, ls: 2.2, c: skin.routeLine),
                        txt('TỪNG KM', 25, h: 1.05),
                      ],
                    ),
                    if (f.hasRoute && !compact)
                      FaceRoute(
                        f.route,
                        size: 44,
                        color: skin.routeLine,
                        stroke: 12,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (compact) ...[
                Expanded(
                  child: map
                      ? FaceMap(
                          f,
                          dark: skin.darkMap,
                          route: skin.routeLine,
                          padding: const EdgeInsets.all(10),
                          radius: 8,
                        )
                      : CustomPaint(
                          painter: FaceRoutePainter(f.route, skin.routeLine, 3),
                          size: Size.infinite,
                        ),
                ),
                if (rows.isNotEmpty) ...[const SizedBox(height: 10), table],
              ] else
                Expanded(child: table),
              const SizedBox(height: 10),
              statColumns(
                [(f.km, 'KM'), (f.time, 'THỜI GIAN'), (f.pace, 'PACE /KM')],
                value: 26,
                ls: 1.3,
                labelColor: skin.dataLabel,
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  txt(f.date, 10, w: w6, ls: 1.3, c: skin.dataLabel),
                  txt(f.rarity, 10, ls: 2.2, c: skin.routeLine),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(RunCardSkin skin, FaceRow row) => Row(
    children: [
      SizedBox(
        width: 16,
        child: fit(
          Text(
            row.km,
            style: faceStyle(map ? 14 : 16, w: w7, c: skin.dataLabel),
          ),
        ),
      ),
      const SizedBox(width: 9),
      Expanded(
        child: Container(
          height: map ? 8 : 13,
          alignment: Alignment.centerLeft,
          clipBehavior: Clip.hardEdge,
          decoration: BoxDecoration(
            color: skin.dataGrid,
            borderRadius: BorderRadius.circular(3),
          ),
          child: FractionallySizedBox(
            widthFactor: row.share,
            heightFactor: 1,
            child: ColoredBox(
              color: row.best
                  ? skin.hero
                  : skin.routeLine.withValues(alpha: 0.42),
            ),
          ),
        ),
      ),
      const SizedBox(width: 9),
      SizedBox(
        width: 44,
        child: txt(
          row.pace,
          map ? 16 : 20,
          a: TextAlign.right,
          c: row.best ? skin.hero : skin.hero.withValues(alpha: 0.82),
        ),
      ),
    ],
  );
}
