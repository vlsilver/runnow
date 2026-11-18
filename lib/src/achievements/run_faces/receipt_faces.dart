import 'package:flutter/material.dart';
import 'package:myrun/src/achievements/run_card_style.dart';
import 'package:myrun/src/achievements/run_faces/face_map.dart';
import 'package:myrun/src/achievements/run_faces/run_face_kit.dart';
import '../../theme_tokens.dart';

const _coal = RunFaceTokens.receiptCoal;
const _paper = RunFaceTokens.receiptPaper;
const _grey = RunFaceTokens.receiptGrey;
const _rowLabel = RunFaceTokens.receiptRowLabel;

const _barWidths = [
  2, 1, 3, 1, 1, 2, 4, 1, 2, 1, 3, 2, 1, 1, 4, //
  2, 1, 3, 1, 2, 1, 1, 3, 1, 4, 2, 1, 2, 1, 3,
];

Widget _dash() => const DashLine(color: RunFaceTokens.dashGray);

Widget _head(RunFace f, {Widget? trailing}) => Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        txt('3I RUN', 26, h: 1, ls: 1),
        txt('${f.date} · ${f.clock}', 11, w: w6, ls: 1.2, c: _grey),
      ],
    ),
    ?trailing,
  ],
);

Widget _total(RunFace f) => Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  crossAxisAlignment: CrossAxisAlignment.baseline,
  textBaseline: TextBaseline.alphabetic,
  children: [
    txt('TỔNG', 16, ls: 1),
    const SizedBox(width: 10),
    Flexible(
      child: slotKm(
        fit(
          Text('${f.km} KM', maxLines: 1, style: faceStyle(44, h: 0.95)),
          a: Alignment.centerRight,
        ),
        a: Alignment.centerRight,
      ),
    ),
  ],
);

/// [slots] là khe của từng dòng, cùng thứ tự với [items]; thiếu thì dòng đó
/// không chỉnh được.
Widget _rows(
  List<(String, String)> items, {
  double gap = 3,
  List<Widget Function(Widget, {Alignment a})> slots = const [],
}) => Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    for (final (i, (a, b)) in items.indexed)
      Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : gap),
        child: switch (Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            txt(a, 15, w: w6, c: _rowLabel),
            txt(b, 15, w: w7),
          ],
        )) {
          final row when i < slots.length => slots[i](row),
          final row => row,
        },
      ),
  ],
);

Widget _code(RunFace f, double height) => Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, w) in _barWidths.indexed)
            Expanded(
              flex: w,
              child: Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 2),
                child: ColoredBox(color: i.isEven ? _coal : Colors.transparent),
              ),
            ),
        ],
      ),
    ),
    const SizedBox(height: 3),
    txt('${f.rarity} · ${f.owner}', 11, w: w7, ls: 2),
  ],
);

Widget _ticket(List<Widget> stack, EdgeInsets pad, {Widget? backdrop}) =>
    faceBox(
      bg: RunFaceTokens.nightBlue,
      ink: _coal,
      children: [
        pin(
          l: 24,
          r: 24,
          t: 14,
          h: 396,
          c: ColoredBox(
            color: _paper,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ?backdrop,
                Padding(
                  padding: pad,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (i, w) in stack.indexed) ...[
                        if (i > 0) const SizedBox(height: 8),
                        w,
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );

Widget receiptFront(RunFace f, RunCardTextLayout t) {
  final art = Expanded(
    child: ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          artOf(f),
          badgeAt(f, l: 8, t: 8),
          stampAt(f, r: 6, t: 6, size: 52),
        ],
      ),
    ),
  );
  final rows = _rows(
    [('Thời gian', f.time), ('Pace', '${f.pace} /km')],
    slots: [slotTime, slotPace],
  );
  return _ticket(switch (t) {
    RunCardTextLayout.full => [
      _head(f),
      art,
      _dash(),
      _total(f),
      rows,
      _code(f, 26),
    ],
    RunCardTextLayout.top => [_total(f), _dash(), rows, art, _code(f, 26)],
    RunCardTextLayout.compact => [art, _dash(), _total(f), _code(f, 26)],
  }, const EdgeInsets.fromLTRB(16, 14, 16, 18));
}

/// Bản đồ in đơn sắc, chỉ còn ba dòng số để giấy đủ chỗ.
Widget _receiptMapBack(RunFace f) => _ticket([
  _head(f),
  _dash(),
  Expanded(
    child: FaceMap(
      f,
      dark: false,
      route: _coal,
      stroke: 2.6,
      padding: const EdgeInsets.all(10),
      tileFilter: faceMapMono,
    ),
  ),
  _rows([
    ('Thời gian', f.time),
    ('Pace', '${f.pace} /km'),
    if (f.bestPace case final best?) ('Km nhanh nhất', best),
  ], gap: 5),
  _dash(),
  _total(f),
  _code(f, 20),
], const EdgeInsets.fromLTRB(16, 14, 16, 20));

Widget receiptBack(RunFace f, {bool map = false}) {
  if (map) return _receiptMapBack(f);
  final climb = f.snap.elevationGainMeters?.round() ?? 0;
  final heart = f.snap.averageHeartRate?.round() ?? 0;
  return _ticket(
    [
      _head(
        f,
        trailing: f.hasRoute
            ? SizedBox(
                width: 50,
                height: 50,
                child: FaceRoute(f.route, size: 50, color: _coal, stroke: 12),
              )
            : null,
      ),
      _dash(),
      _rows([
        ('Thời gian', f.time),
        ('Pace', '${f.pace} /km'),
        if (f.bestPace case final best?) ('Km nhanh nhất', best),
        if (climb > 0) ('Leo', '+$climb m'),
        if (heart > 0) ('Nhịp tim', '$heart bpm'),
      ], gap: 5),
      _dash(),
      _total(f),
      const Spacer(),
      _code(f, 34),
    ],
    const EdgeInsets.fromLTRB(16, 14, 16, 20),
    backdrop: f.hasRoute
        ? FaceMap(
            f,
            dark: false,
            route: null,
            padding: const EdgeInsets.all(40),
            maxZoom: 22,
            tileFilter: faceMapWash(_coal, dark: false, strength: 0.22),
            creditAt: Alignment.bottomCenter,
            creditPadding: const EdgeInsets.only(bottom: 5),
          )
        : null,
  );
}
