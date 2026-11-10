import 'package:flutter/material.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/achievements/run_faces/face_map.dart';
import 'package:myrun/src/achievements/run_faces/run_face_kit.dart';

/// Basic không có bảng màu riêng: chữ và nền theo bộ màu thẻ.
class BasicFront extends StatelessWidget {
  const BasicFront(this.f, {super.key});

  final RunFace f;

  @override
  Widget build(BuildContext context) {
    final base = RunCardSkin.of(context);
    final skin = f.data.artFollowsSkin ? base : base.onDarkArt ?? base;
    return faceBox(
      bg: skin.field,
      ink: skin.hero,
      children: [
        artOf(f),
        badgeAt(f, l: 17, t: 17),
        pin(
          l: 14,
          r: 14,
          b: 14,
          h: 44,
          c: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: skin.shade.withValues(alpha: 0.74),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: skin.ink.withValues(alpha: 0.32)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(flex: 3, child: fit(hero(f.km, 25, 11))),
                const SizedBox(width: 6),
                Flexible(
                  flex: 3,
                  child: fit(
                    Text('${f.pace} /km', style: faceStyle(15, w: w6)),
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  flex: 3,
                  child: fit(Text(f.time, style: faceStyle(15, w: w6))),
                ),
                const SizedBox(width: 6),
                txt('3I', 11, w: w7, ls: 1.5, c: skin.accent(f.tier)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class BasicBack extends StatelessWidget {
  const BasicBack(this.f, {super.key, this.map = false});

  final RunFace f;
  final bool map;

  @override
  Widget build(BuildContext context) {
    final skin = RunCardSkin.of(context);
    return faceBox(
      bg: skin.dataBack,
      ink: skin.hero,
      children: [
        if (f.hasRoute && !map)
          FaceMap(
            f,
            dark: skin.darkMap,
            route: null,
            // Chừa đúng ô vẽ đường chạy để map trùng nét vẽ.
            padding: const EdgeInsets.fromLTRB(39, 71, 39, 127),
            maxZoom: 22,
            tileFilter: faceMapWash(
              skin.hero,
              dark: skin.darkMap,
              strength: 0.3,
            ),
            creditPadding: const EdgeInsets.fromLTRB(0, 0, 18, 18),
          ),
        Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              txt('3I RUN', 11, ls: 2.2, c: skin.routeLine),
              Expanded(
                child: map
                    ? Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 12),
                        child: FaceMap(
                          f,
                          dark: skin.darkMap,
                          route: skin.routeLine,
                          stroke: 3.4,
                          padding: const EdgeInsets.all(26),
                          radius: 10,
                        ),
                      )
                    : Center(
                        child: f.hasRoute
                            ? FaceRoute(
                                f.route,
                                size: 230,
                                color: skin.routeLine,
                                stroke: 4,
                              )
                            : f.series.length > 1
                            ? SizedBox(
                                width: double.infinity,
                                height: 120,
                                child: FaceChart(
                                  f.series,
                                  color: skin.routeLine,
                                  stroke: 3,
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
              ),
              statColumns(
                [(f.km, 'KM'), (f.time, 'THỜI GIAN'), (f.pace, 'PACE /KM')],
                value: 32,
                label: 11,
                ls: 1.3,
                labelColor: skin.dataLabel,
              ),
              const SizedBox(height: 10),
              txt(f.date, 11, w: w6, ls: 1.3, c: skin.dataLabel),
            ],
          ),
        ),
      ],
    );
  }
}
