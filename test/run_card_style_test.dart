import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/card_share.dart';
import 'package:myrun/src/achievements/run_card.dart';
import 'package:myrun/src/achievements/run_card_editor.dart';
import 'package:myrun/src/achievements/run_card_layout.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/achievements/run_card_panel.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/achievements/run_card_skin_choice.dart';
import 'package:myrun/src/achievements/run_card_style.dart';
import 'package:myrun/src/achievements/run_card_style_sheet.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/achievements/run_faces/face_map.dart';
import 'package:myrun/src/achievements/run_faces/run_face_kit.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/theme_controller.dart';

const _route = [
  {'lat': 21.05, 'lng': 105.82},
  {'lat': 21.06, 'lng': 105.83},
  {'lat': 21.07, 'lng': 105.82},
  {'lat': 21.06, 'lng': 105.81},
  {'lat': 21.05, 'lng': 105.82},
];

RunCard _card({
  String id = 'r1',
  double km = 6.1,
  int seconds = 3609,
  String name = 'Morning Run',
  bool gps = true,
  String? secret,
  bool art = false,
  List<(double, int)> splits = const [
    (1000, 581),
    (1000, 598),
    (1000, 612),
    (1000, 587),
    (1000, 595),
    (1000, 576),
  ],
}) => RunCard.fromJson({
  'id': id,
  'activityId': id,
  'tier': 'epic',
  'km': km,
  'rollPpm': 1,
  'rolledAt': '2026-11-10T08:00:00Z',
  'startedAt': '2026-11-10T13:52:00Z',
  'odds': const [],
  'variant': ?secret,
  if (art)
    'art': {
      'status': 'done',
      'style': 'linocut',
      'attempt': 1,
      'path': 'users/u1/runCards/r1/art.png',
    },
  'snapshot': {
    'name': name,
    'sportType': 'Run',
    'startedAt': '2026-11-10T20:52:00',
    'distanceMeters': km * 1000,
    'movingTimeSeconds': seconds,
    'elapsedTimeSeconds': seconds,
    'route': gps ? _route : const [],
    'splits': [
      for (final (meters, time) in splits)
        {'distanceMeters': meters, 'movingTimeSeconds': time},
    ],
  },
});

Future<void> _loadCardFont() async {
  final loader = FontLoader('Barlow Condensed');
  for (final weight in ['SemiBold', 'Bold', 'ExtraBold']) {
    final file = File(
      'assets/fonts/barlow_condensed/BarlowCondensed-$weight.ttf',
    );
    final bytes = await file.readAsBytes();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

Widget _face(
  RunCard card,
  RunCardStyle style, {
  bool back = false,
  bool routeArt = false,
}) => MaterialApp(
  home: RunCardSkinScope(
    skin: RunCardSkin.classic,
    child: RunCardStyleScope.fixed(
      style: style,
      child: Center(
        child: GameCardScaled(
          width: 300,
          size: achievementCardSize,
          child: AchievementCard(
            data: runCardData(
              card,
              owner: 'NGUYEN VAN A',
              previewArt: routeArt
                  ? null
                  : const ColoredBox(color: Color(0xFF55708A)),
            ),
            back: back,
            animate: false,
          ),
        ),
      ),
    ),
  ),
);

/// Màu chủ thẻ phủ lên phần chứa [f]; null là phần giữ màu gốc.
Color? _tint(WidgetTester tester, Finder f) {
  final tinted = find.ancestor(of: f, matching: find.byType(ColorFiltered));
  if (tinted.evaluate().isEmpty) return null;
  final filter = tester.widget<ColorFiltered>(tinted.first).colorFilter;
  for (final color in [
    RunFaceTokens.ironCoal,
    RunFaceTokens.ironPaper,
    RunFaceTokens.ironRed,
    const Color(0xFF3366CC),
    const Color(0xFF18DC18),
  ]) {
    if (filter == ColorFilter.mode(color, BlendMode.srcIn)) return color;
  }
  fail('màu lạ: $filter');
}

/// Phần chứa [f] đang hiện (ẩn thì vẫn giữ chỗ trong bố cục).
bool _shown(WidgetTester tester, Finder f) => find
    .ancestor(of: f, matching: find.byType(Visibility))
    .evaluate()
    .every((e) => (e.widget as Visibility).visible);

void main() {
  group('RunCardStyleController', () {
    RunCardStyleController controller() =>
        RunCardStyleController(loadFromStorage: false);

    setUp(() => FlutterSecureStorage.setMockInitialValues({}));

    final before = DateTime.utc(2026, 11, 9);
    final applied = DateTime.utc(2026, 11, 10);
    final after = DateTime.utc(2026, 11, 11);
    const city = RunCardStyle(RunCardSet.city, RunCardTextLayout.top);

    test('thẻ cũ giữ kiểu, thẻ lật sau theo mặc định mới', () async {
      final styles = controller();
      await styles.apply(city, cardId: 'viewed', now: applied);

      expect(styles.styleOf('viewed', before), city);
      expect(styles.styleOf('old', before), RunCardStyle.current);
      expect(styles.styleOf('new', after), city);
    });

    test('đổi mặc định lần hai không đổi thẻ của mặc định trước', () async {
      final styles = controller();
      await styles.apply(city, now: applied);
      await styles.apply(
        const RunCardStyle(RunCardSet.medal),
        now: applied.add(const Duration(days: 2)),
      );

      expect(styles.styleOf('between', after), city);
    });

    test('lưu rồi đọc lại ra đúng lựa chọn', () async {
      final styles = controller();
      await styles.apply(city, cardId: 'viewed', now: applied);

      final restored = controller()..decode(styles.encode());

      expect(restored.styleOf('viewed', before), city);
      expect(restored.styleOf('new', after), city);
    });
  });

  group('RunCardStyle đường chạy lớn', () {
    // Mẫu backend chép từ run_card_look.go: tối đa ba đoạn, quá là 400.
    final backend = RegExp(r'^[A-Za-z0-9]{1,24}(\.[A-Za-z0-9]{1,24}){1,2}$');

    test('bật đường lớn lưu được lên backend và đọc lại đúng', () {
      final big = const RunCardStyle(RunCardSet.current).withBigRoute(true);

      expect(big.id, 'current.full.route');
      expect(RunCardStyle.parse('current.full.route'), big);
      expect(big, isNot(RunCardStyle.current));
      expect(backend.hasMatch(big.id), isTrue);
    });

    test('vừa bản đồ vừa đường lớn vẫn chỉ ba đoạn', () {
      final both = const RunCardStyle.withMap(
        RunCardSet.splits,
      ).withBigRoute(true);

      expect(both.id, 'splits.full.mapRoute');
      expect(RunCardStyle.parse('splits.full.mapRoute'), both);
      expect(both.map, isTrue);
      expect(both.bigRoute, isTrue);
      expect(backend.hasMatch(both.id), isTrue);
    });

    test('id cũ đọc ra con dấu tròn', () {
      expect(RunCardStyle.parse('splits.full.map')!.bigRoute, isFalse);
      expect(RunCardStyle.parse('current.full')!.bigRoute, isFalse);
    });

    test('mọi bộ có lựa chọn đường chạy, trừ Pixel không dùng tranh', () {
      expect(
        [
          for (final set in RunCardSet.values)
            if (!set.hasRouteSizeOption) set.name,
        ],
        ['pixel'],
      );
    });
  });

  group('RunCardStyle bản đồ', () {
    test('id đã lưu của bản cũ giữ nguyên và đọc ra là tắt', () {
      final old = RunCardStyle.parse('city.top');

      expect(old, const RunCardStyle(RunCardSet.city, RunCardTextLayout.top));
      expect(old!.map, isFalse);
      expect(old.id, 'city.top');
    });

    test('bật bản đồ là kiểu khác, lưu rồi đọc lại vẫn bật', () {
      const on = RunCardStyle.withMap(RunCardSet.city, RunCardTextLayout.top);

      expect(on.id, 'city.top.map');
      expect(RunCardStyle.parse('city.top.map'), on);
      expect(
        on,
        isNot(const RunCardStyle(RunCardSet.city, RunCardTextLayout.top)),
      );
    });

    test('bộ Pixel lưu dưới tên pixel, đọc lại ra đúng bộ', () {
      const on = RunCardStyle.withMap(RunCardSet.pixel);

      expect(on.id, 'pixel.full.map');
      expect(RunCardStyle.parse('pixel.full.map'), on);
      expect(
        RunCardStyle.parse('pixel.full'),
        const RunCardStyle(RunCardSet.pixel),
      );
    });

    test('hậu tố lạ thì bỏ, thẻ vẽ kiểu gốc', () {
      expect(RunCardStyle.parse('city.top.lạ'), isNull);
    });

    test('đúng 16 bộ có công tắc bản đồ', () {
      expect(
        [
          for (final set in RunCardSet.values)
            if (set.hasMapOption) set.name,
        ],
        [
          'basic',
          'splits',
          'blueprint',
          'city',
          'cassette',
          'constellation',
          'blocks',
          'stopwatch',
          'flipBoard',
          'bib',
          'finish',
          'paperMap',
          'receipt',
          'medal',
          'iron',
          'pixel',
        ],
      );
    });
  });

  group('parseRunCardSets', () {
    test('giữ thứ tự cấu hình, bỏ tên lạ và tên trùng', () {
      expect(parseRunCardSets('medal, blueprint,nope,medal'), [
        RunCardSet.medal,
        RunCardSet.blueprint,
      ]);
    });

    test('cấu hình rỗng thì đủ mọi bộ', () {
      expect(parseRunCardSets(''), RunCardSet.values);
    });
  });

  group('RunFace.rows', () {
    final card = _card(
      km: 8.1,
      splits: const [
        (1000, 600),
        (1000, 600),
        (1000, 300),
        (1000, 500),
        (1000, 400),
        (1000, 400),
        (1000, 500),
        (1000, 500),
        (100, 30),
      ],
    );
    final face = RunFace(card, runCardData(card, owner: 'A'));

    test('gộp km liền nhau, pace tính trên tổng thời gian của nhóm', () {
      final rows = face.rows(4);

      expect([for (final r in rows) r.km], ['2', '4', '6', '8']);
      expect([for (final r in rows) r.pace], ['10:00', '6:40', '6:40', '8:20']);
      expect(rows[0].share, closeTo(0.6, 1e-9));
      expect(rows[1].share, closeTo(1.0, 1e-9));
      expect(rows[3].share, closeTo(0.8, 1e-9));
    });

    test('hai nhóm nhanh bằng nhau thì chỉ nhóm đầu là nhanh nhất', () {
      expect(
        [for (final r in face.rows(4)) r.best],
        [false, true, false, false],
      );
    });

    test('buổi ngắn hơn số hàng thì không gộp và bỏ đoạn lẻ cuối', () {
      expect(face.rows(10).length, 8);
    });
  });

  group('khoá cache khoe', () {
    final subject = runCardShareSubject(_card(), 'An');

    test('kiểu gốc giữ nguyên khoá đã có trên máy', () {
      expect(
        cardShareKey(
          subject,
          skin: RunCardSkin.classic,
          style: RunCardStyle.current,
        ),
        cardShareKey(subject, skin: RunCardSkin.classic),
      );
    });

    test('mỗi kiểu thẻ một khoá, cùng phần nội dung', () {
      final top = cardShareKey(
        subject,
        skin: RunCardSkin.classic,
        style: const RunCardStyle(RunCardSet.city, RunCardTextLayout.top),
      );
      final compact = cardShareKey(
        subject,
        skin: RunCardSkin.classic,
        style: const RunCardStyle(RunCardSet.city, RunCardTextLayout.compact),
      );

      expect(top, isNot(compact));
      expect(top.split('.').first, compact.split('.').first);
    });

    test('bật bản đồ là file khoe riêng, không đè bản không map', () {
      final off = cardShareKey(
        subject,
        skin: RunCardSkin.classic,
        style: const RunCardStyle(RunCardSet.city),
      );
      final on = cardShareKey(
        subject,
        skin: RunCardSkin.classic,
        style: const RunCardStyle.withMap(RunCardSet.city),
      );

      expect(on, isNot(off));
      expect(on.split('.').first, off.split('.').first);
    });
  });

  group('mặt thẻ', () {
    Rect inFace(WidgetTester tester, Finder f) {
      final card = tester.getRect(find.byType(AchievementCard));
      final at = tester.getRect(f);
      final k = 300 / card.width;
      return Rect.fromLTRB(
        (at.left - card.left) * k,
        (at.top - card.top) * k,
        (at.right - card.left) * k,
        (at.bottom - card.top) * k,
      );
    }

    Finder ironKm() => find.byWidgetPredicate(
      (w) => w is Text && (w.style?.fontSize ?? 0) > 100,
    );
    Finder ironTime() => find
        .byWidgetPredicate((w) => w is Text && w.style?.fontSize == 40)
        .first;
    Finder ironPace() =>
        find.ancestor(of: find.text('/KM'), matching: find.byType(Row)).first;

    testWidgets('Thép có bố cục mà chưa dời phần nào thì trùng chỗ gốc', (
      tester,
    ) async {
      await tester.runAsync(_loadCardFont);
      // Số ngắn, số dài phải thu cho vừa, giờ có và không có phần giờ.
      for (final (km, seconds) in [(5.0, 1776), (21.1, 7400), (42.2, 15000)]) {
        final card = _card(km: km, seconds: seconds);
        const plain = RunCardStyle(RunCardSet.iron);
        await tester.pumpWidget(_face(card, plain));
        final before = [
          for (final f in [ironKm(), ironTime(), ironPace()]) inFace(tester, f),
        ];

        // Chỉ tô đường chạy: bố cục khác rỗng nhưng chữ không được xê dịch.
        final edited = plain.withLayout(RunCardLayout.parse('route:,,2,1'));
        await tester.pumpWidget(_face(card, edited));
        final after = [
          for (final f in [ironKm(), ironTime(), ironPace()]) inFace(tester, f),
        ];
        expect(after, before, reason: '$km');
      }
    });

    testWidgets('Thép đã chỉnh vẽ đúng chỗ, cỡ, màu, ẩn của từng phần', (
      tester,
    ) async {
      await tester.runAsync(_loadCardFont);
      const plain = RunCardStyle(RunCardSet.iron);
      await tester.pumpWidget(_face(_card(), plain));
      final size = inFace(tester, ironKm()).size;

      await tester.pumpWidget(
        _face(
          _card(),
          plain.withLayout(RunCardLayout.parse('km:10,50,4,1;time:20,80,2,h')),
        ),
      );
      final km = inFace(tester, ironKm());
      // Neo đáy trái: 10% là 30 điểm, 50% là 210 điểm; bậc 4 là gấp 1,45.
      expect(km.left, closeTo(30, 0.01));
      expect(km.bottom, closeTo(210, 0.01));
      expect(km.width, closeTo(size.width * 1.45, 0.01));
      // Màu đặc trưng thứ hai của Thép là Đen.
      expect(_tint(tester, ironKm()), RunFaceTokens.ironCoal);
      expect(_tint(tester, ironPace()), isNull, reason: 'pace giữ màu gốc');
      expect(_shown(tester, ironTime()), isFalse);
      expect(_shown(tester, ironPace()), isTrue);
    });

    testWidgets('kiểu Số trên cũng dời theo bố cục, neo góc trên', (
      tester,
    ) async {
      await tester.runAsync(_loadCardFont);
      const top = RunCardStyle(RunCardSet.iron, RunCardTextLayout.top);
      await tester.pumpWidget(
        _face(_card(), top.withLayout(RunCardLayout.parse('km:10,50,2'))),
      );
      final km = inFace(tester, ironKm());
      expect(km.left, closeTo(30, 0.01));
      expect(km.top, closeTo(210, 0.01));
    });

    testWidgets('màu tự chọn phủ lên nét của phần', (tester) async {
      await tester.runAsync(_loadCardFont);
      await tester.pumpWidget(
        _face(
          _card(),
          const RunCardStyle(
            RunCardSet.iron,
          ).withLayout(RunCardLayout.parse('pace:,,2,3366cc')),
        ),
      );
      expect(_tint(tester, ironPace()), const Color(0xFF3366CC));
      expect(_tint(tester, ironKm()), isNull);
    });

    const blueprint = RunCardStyle(RunCardSet.blueprint);

    testWidgets('thẻ có tranh: Tròn có con dấu, Lớn vẽ đường trên tranh', (
      tester,
    ) async {
      const round = RunCardStyle(RunCardSet.current);
      await tester.pumpWidget(_face(_card(), round));
      expect(find.byType(RunRouteStamp), findsOneWidget);

      await tester.pumpWidget(_face(_card(), round.withBigRoute(true)));
      expect(find.byType(RunRouteStamp), findsNothing);
      expect(
        find.descendant(
          of: find.byType(RunBigRouteOverArt),
          matching: find.byType(CustomPaint),
        ),
        findsWidgets,
      );
    });

    testWidgets('bộ có mặt trước riêng cũng đổi được con dấu sang đường lớn', (
      tester,
    ) async {
      await tester.runAsync(_loadCardFont);
      for (final set in RunCardSet.values.where((s) => s.hasRouteSizeOption)) {
        final round = RunCardStyle(set);
        await tester.pumpWidget(_face(_card(), round));
        expect(find.byType(RunRouteStamp), findsOneWidget, reason: set.name);

        await tester.pumpWidget(_face(_card(), round.withBigRoute(true)));
        expect(find.byType(RunRouteStamp), findsNothing, reason: set.name);
        expect(find.byType(RunBigRouteOverArt), findsOneWidget);
      }
    });

    testWidgets('thẻ thường đổi theo kiểu', (tester) async {
      await tester.pumpWidget(_face(_card(), blueprint));

      expect(find.text('QUÃNG ĐƯỜNG'), findsOneWidget);
    });

    testWidgets('thẻ Ẩn giữ nguyên, không theo kiểu', (tester) async {
      await tester.pumpWidget(_face(_card(secret: 'secret.fire'), blueprint));

      expect(find.text('QUÃNG ĐƯỜNG'), findsNothing);
    });

    testWidgets('Từng km ít hàng thì các hàng nằm sát nhau', (tester) async {
      await tester.runAsync(_loadCardFont);
      await tester.pumpWidget(
        _face(
          _card(km: 2, seconds: 1178, splits: const [(1000, 583), (1000, 595)]),
          const RunCardStyle(RunCardSet.splits),
          back: true,
        ),
      );
      final first = tester.getCenter(find.text('9:43')).dy;
      final second = tester.getCenter(find.text('9:55')).dy;
      expect(second - first, closeTo(24, 0.5));
    });

    testWidgets('Từng km không GPS thì bảng ít hàng nằm giữa, không giãn', (
      tester,
    ) async {
      await tester.runAsync(_loadCardFont);
      await tester.pumpWidget(
        _face(
          _card(
            km: 2,
            seconds: 1178,
            gps: false,
            splits: const [(1000, 583), (1000, 595)],
          ),
          const RunCardStyle(RunCardSet.splits),
          back: true,
        ),
      );
      final first = tester.getCenter(find.text('9:43')).dy;
      final second = tester.getCenter(find.text('9:55')).dy;
      expect(second - first, closeTo(30, 0.5));
    });

    testWidgets('mọi bộ vừa khung với buổi ngắn, dài, GPS và không GPS', (
      tester,
    ) async {
      await tester.runAsync(_loadCardFont);
      final longSplits = [for (var i = 0; i < 123; i++) (1000.0, 585)];
      final cards = [
        _card(),
        _card(gps: false),
        _card(km: 1.2, seconds: 700, splits: const [(1000, 583), (200, 117)]),
        _card(gps: false, splits: const []),
        _card(
          km: 123.4,
          seconds: 72009,
          name: 'Ultra Trail quanh Hồ Tây lúc nửa đêm về sáng cuối tuần',
          splits: longSplits,
        ),
      ];
      for (final set in RunCardSet.values) {
        // Mặt sau gốc có bản đồ cần plugin, run_card_test đã phủ.
        if (set == RunCardSet.current) continue;
        for (final card in cards) {
          for (final text in RunCardTextLayout.values) {
            await tester.pumpWidget(_face(card, RunCardStyle(set, text)));
            expect(tester.takeException(), isNull, reason: '$set $text');
          }
          await tester.pumpWidget(_face(card, RunCardStyle(set), back: true));
          expect(tester.takeException(), isNull, reason: '$set mặt sau');
        }
      }
    });

    group('bản đồ mặt sau', () {
      final mapSets = [
        for (final set in RunCardSet.values)
          if (set.hasMapOption) set,
      ];
      const washedWhenOff = {
        RunCardSet.medal,
        RunCardSet.receipt,
        RunCardSet.finish,
        RunCardSet.bib,
        RunCardSet.flipBoard,
        RunCardSet.stopwatch,
        RunCardSet.basic,
        RunCardSet.splits,
        RunCardSet.cassette,
        RunCardSet.city,
        RunCardSet.constellation,
        RunCardSet.blueprint,
        RunCardSet.paperMap,
      };

      testWidgets('tắt công tắc vẫn có bản đồ mờ, đủ ghi công', (tester) async {
        await tester.runAsync(_loadCardFont);
        for (final set in washedWhenOff) {
          await tester.pumpWidget(
            _face(_card(), RunCardStyle(set), back: true),
          );
          expect(find.byType(FlutterMap), findsOneWidget, reason: '$set');
          expect(
            find.byWidgetPredicate((w) => w is PolylineLayer),
            findsNothing,
            reason: '$set',
          );
          expect(
            find.textContaining('OpenStreetMap'),
            findsOneWidget,
            reason: '$set',
          );
        }
      });

      testWidgets('Thành phố tắt công tắc thì bỏ hình tròn chứa đường chạy', (
        tester,
      ) async {
        await tester.runAsync(_loadCardFont);
        await tester.pumpWidget(
          _face(_card(), const RunCardStyle(RunCardSet.city), back: true),
        );
        expect(find.byType(FlutterMap), findsOneWidget);
        expect(find.byType(FaceRoute), findsNothing);
      });

      testWidgets('tắt thì không có bản đồ, bật thì có và ghi công OSM', (
        tester,
      ) async {
        await tester.runAsync(_loadCardFont);
        final credit = find.textContaining('OpenStreetMap');
        for (final set in mapSets) {
          if (washedWhenOff.contains(set)) continue;
          await tester.pumpWidget(
            _face(_card(), RunCardStyle(set), back: true),
          );
          expect(find.byType(FlutterMap), findsNothing, reason: '$set tắt');

          await tester.pumpWidget(
            _face(_card(), RunCardStyle.withMap(set), back: true),
          );
          expect(find.byType(FlutterMap), findsOneWidget, reason: '$set bật');
          expect(credit, findsOneWidget, reason: '$set ghi công');
        }
      });

      testWidgets(
        'Bản vẽ, Bản đồ giấy, Chòm sao chỉ thêm nền, không vẽ đường thứ hai',
        (tester) async {
          await tester.runAsync(_loadCardFont);
          for (final set in [
            RunCardSet.blueprint,
            RunCardSet.paperMap,
            RunCardSet.constellation,
          ]) {
            await tester.pumpWidget(
              _face(_card(), RunCardStyle.withMap(set), back: true),
            );
            expect(find.byType(FlutterMap), findsOneWidget, reason: '$set');
            expect(
              find.byWidgetPredicate((w) => w is PolylineLayer),
              findsNothing,
              reason: '$set',
            );
          }
        },
      );

      testWidgets('Chòm sao tắt thì map mờ, bật thì map rõ', (tester) async {
        await tester.runAsync(_loadCardFont);
        ColorFilter? filterOf(RunCardStyle style) =>
            tester.widget<StillRouteMap>(find.byType(StillRouteMap)).tileFilter;

        const off = RunCardStyle(RunCardSet.constellation);
        await tester.pumpWidget(_face(_card(), off, back: true));
        expect(filterOf(off), isNotNull);

        const on = RunCardStyle.withMap(RunCardSet.constellation);
        await tester.pumpWidget(_face(_card(), on, back: true));
        expect(filterOf(on), isNull);
      });

      testWidgets('Huy chương bật bản đồ vẫn có nền map mờ ngoài đĩa', (
        tester,
      ) async {
        await tester.runAsync(_loadCardFont);
        await tester.pumpWidget(
          _face(
            _card(),
            const RunCardStyle.withMap(RunCardSet.medal),
            back: true,
          ),
        );
        final maps = tester
            .widgetList<StillRouteMap>(find.byType(StillRouteMap))
            .toList();
        expect(maps, hasLength(2));
        expect(maps.where((m) => m.tileFilter == null), hasLength(1));
        expect(find.textContaining('OpenStreetMap'), findsOneWidget);
      });

      testWidgets('thẻ không GPS bật bản đồ vẫn ra mặt sau thường', (
        tester,
      ) async {
        await tester.runAsync(_loadCardFont);
        for (final set in mapSets) {
          await tester.pumpWidget(
            _face(_card(gps: false), RunCardStyle.withMap(set), back: true),
          );
          expect(find.byType(FlutterMap), findsNothing, reason: '$set');
        }
      });

      testWidgets('vừa khung với buổi ngắn và buổi dài', (tester) async {
        await tester.runAsync(_loadCardFont);
        final cards = [
          _card(),
          _card(km: 1.2, seconds: 700, splits: const [(1000, 583), (200, 117)]),
          _card(splits: const []),
          _card(
            km: 123.4,
            seconds: 72009,
            splits: [for (var i = 0; i < 123; i++) (1000.0, 585)],
          ),
        ];
        for (final set in mapSets) {
          for (final card in cards) {
            await tester.pumpWidget(
              _face(card, RunCardStyle.withMap(set), back: true),
            );
            expect(tester.takeException(), isNull, reason: '$set ${card.km}');
          }
        }
      });
    });

    testWidgets('thẻ chưa vẽ tranh: bộ có màu riêng vẽ nền của bộ, bộ theo bộ '
        'màu thẻ giữ nền đường chạy; thẻ không GPS vẫn vẽ được', (
      tester,
    ) async {
      await tester.runAsync(_loadCardFont);
      const followSkin = {
        RunCardSet.current,
        RunCardSet.basic,
        RunCardSet.splits,
      };
      for (final set in RunCardSet.values) {
        for (final gps in [true, false]) {
          await tester.pumpWidget(
            _face(_card(gps: gps), RunCardStyle(set), routeArt: true),
          );
          expect(tester.takeException(), isNull, reason: '$set gps=$gps');
          expect(
            find.byType(RunRouteArt),
            followSkin.contains(set) ? findsOneWidget : findsNothing,
            reason: '$set gps=$gps',
          );
        }
      }
    });

    testWidgets('khung đường chạy không nằm dưới chữ ở mọi bộ, mọi kiểu chữ', (
      tester,
    ) async {
      await tester.runAsync(_loadCardFont);
      Rect onScreen(RenderBox box, Rect local) =>
          MatrixUtils.transformRect(box.getTransformTo(null), local);

      final covered = <String>[];
      for (final set in RunCardSet.values) {
        // Pixel tự vẽ cảnh ở mặt trước, không có tranh đường chạy.
        if (set == RunCardSet.pixel) continue;
        for (final layout in RunCardTextLayout.values) {
          await tester.pumpWidget(
            _face(_card(), RunCardStyle(set, layout), routeArt: true),
          );
          final art = find.byType(RunDefaultArt);
          final artBox = tester.renderObject<RenderBox>(art);
          final route = onScreen(
            artBox,
            RunRouteBand.boxIn(tester.element(art), artBox.size),
          );
          for (final label in find.byType(RichText).evaluate()) {
            final box = label.renderObject! as RenderBox;
            if (onScreen(box, Offset.zero & box.size).overlaps(route)) {
              final text = (label.widget as RichText).text.toPlainText();
              covered.add('${set.name} ${layout.name}: $text');
            }
          }
        }
      }

      expect(covered, isEmpty);
    });
  });

  group('sheet Kiểu thẻ', () {
    Future<(RunCardStyleController, RunCardSkinController)> open(
      WidgetTester tester, {
      required RunCard card,
      AchievementCardData? data,
    }) async {
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final styles = RunCardStyleController(loadFromStorage: false);
      final skins = RunCardSkinController(loadFromStorage: false);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            themeControllerProvider.overrideWith(
              (ref) => ThemeController(loadFromStorage: false),
            ),
            runCardStyleControllerProvider.overrideWith((ref) => styles),
            runCardSkinControllerProvider.overrideWith((ref) => skins),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      showRunCardStyleSheet(context, card: card, data: data),
                  child: const Text('mở'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('mở'));
      await tester.pumpAndSettle();
      return (styles, skins);
    }

    testWidgets('Dùng áp bộ và kiểu chữ cho thẻ đang xem và thẻ sau', (
      tester,
    ) async {
      final card = _card();
      final (styles, _) = await open(tester, card: card);

      await tester.tap(find.text('Bản vẽ'));
      await tester.pump();
      // Nút chữ đi từ Đầy đủ sang Số trên.
      await tester.tap(find.byKey(runCardTextLayoutKey));
      await tester.pump();
      await tester.tap(find.text('Dùng'));
      await tester.pumpAndSettle();

      const expected = RunCardStyle(
        RunCardSet.blueprint,
        RunCardTextLayout.top,
      );
      expect(styles.styleOf(card.id, card.rolledAt), expected);
      expect(
        styles.styleOf('later', DateTime.now().add(const Duration(days: 1))),
        expected,
      );
    });

    group('chỉnh Thép', () {
      Future<RunCardStyleController> openEditor(
        WidgetTester tester, {
        bool fromThumb = false,
      }) async {
        await tester.runAsync(_loadCardFont);
        final (styles, _) = await open(tester, card: _card());
        await tester.dragUntilVisible(
          find.text('Thép'),
          find.byType(ListView),
          const Offset(-200, 0),
        );
        if (fromThumb) {
          await tester.tap(find.bySemanticsLabel('Chỉnh Thép'));
        } else {
          await tester.tap(find.text('Thép'));
          await tester.pump();
          await tester.tap(find.byKey(runCardEditKey));
        }
        await tester.pumpAndSettle();
        return styles;
      }

      Finder inEditor(Finder f) =>
          find.descendant(of: find.byType(RunCardEditor), matching: f);
      Finder km() => inEditor(find.text('6,1'));
      // Thời gian là chữ cỡ 40 đầu tiên; pace cũng cỡ 40 nhưng đứng sau.
      Finder time() => inEditor(
        find.byWidgetPredicate((w) => w is Text && w.style?.fontSize == 40),
      ).first;

      Rect cardRect(WidgetTester tester) =>
          tester.getRect(inEditor(find.byType(AchievementCard)));

      testWidgets('nút bút trên ô Thép mở thẳng màn chỉnh', (tester) async {
        await openEditor(tester, fromThumb: true);
        expect(find.byType(RunCardEditor), findsOneWidget);
        expect(km(), findsOneWidget);
      });

      testWidgets('kéo số km đi đúng quãng tay kéo, Xong rồi Dùng thì lưu', (
        tester,
      ) async {
        final card = _card();
        final styles = await openEditor(tester);
        // Thẻ trong màn chỉnh rộng 320, mỗi phần trăm ngang là 3,2 điểm.
        expect(cardRect(tester).width, 320);

        final gesture = await tester.startGesture(tester.getCenter(km()));
        // Kéo quá ngưỡng nhận pan trước, rồi mới đo quãng. Số km Thép rộng
        // gần hết thẻ nên chỉ kéo dọc được; 10% dọc là 44,8 điểm.
        await gesture.moveBy(const Offset(0, -40));
        await tester.pump();
        final before = tester.getRect(km());
        await gesture.moveBy(const Offset(0, -44.8));
        await tester.pump();
        await gesture.up();
        await tester.pump();
        final after = tester.getRect(km());
        final c = cardRect(tester);
        expect(after.top - before.top, closeTo(-44.8, 2.3));
        expect(after.left, before.left);

        await tester.tap(find.text('Xong'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Dùng'));
        await tester.pumpAndSettle();

        final saved = styles.styleOf(card.id, card.rolledAt);
        expect(saved.id, 'iron.full');
        // Chỗ lưu là góc đáy trái của số km, theo phần trăm thẻ trên màn.
        final at = saved.layout.of(CardPart.km);
        expect(at.x, ((after.left - c.left) / 3.2).round());
        expect(at.y, ((after.bottom - c.top) / 4.48).round());
      });

      testWidgets('kéo quá mép thì cả khung phần vẫn nằm trong thẻ', (
        tester,
      ) async {
        await openEditor(tester);
        final gesture = await tester.startGesture(tester.getCenter(time()));
        await gesture.moveBy(const Offset(-40, 0));
        await tester.pump();
        await gesture.moveBy(const Offset(-600, 900));
        await tester.pump();
        await gesture.up();
        await tester.pump();

        final card = cardRect(tester);
        final part = tester.getRect(time());
        // Mép 2% là 6,4 điểm; đáy không quá 98% của 448 điểm.
        expect(part.left, greaterThanOrEqualTo(card.left + 6.4 - 1.6));
        expect(part.left, lessThan(card.left + 6.4 + 3.2));
        expect(part.bottom, lessThanOrEqualTo(card.top + 448 * 0.98 + 2.3));
        expect(part.bottom, greaterThan(card.top + 448 * 0.98 - 4.5));
      });

      testWidgets('gần trục giữa thì tâm thật của phần hít vào giữa thẻ', (
        tester,
      ) async {
        await openEditor(tester);
        final card = cardRect(tester);
        final gesture = await tester.startGesture(tester.getCenter(time()));
        await gesture.moveBy(const Offset(40, 0));
        await tester.pump();
        // Kéo tâm phần thời gian tới cách trục giữa 4 điểm, tức 1,25%.
        final at = tester.getRect(time()).center.dx;
        await gesture.moveBy(Offset(card.center.dx - 4 - at, 0));
        await tester.pump();
        // Chỗ lưu làm tròn tới 1%, tức 3,2 điểm.
        expect(tester.getRect(time()).center.dx, closeTo(card.center.dx, 1.6));
        await gesture.up();
      });

      testWidgets('số km không ẩn được, thời gian ẩn được', (tester) async {
        await openEditor(tester);
        IconButton hide() => tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.visibility_off_outlined),
        );

        await tester.tap(km());
        await tester.pump();
        expect(hide().onPressed, isNull);
        expect(find.widgetWithText(FilterChip, 'Số km'), findsNothing);

        final text = tester.widget<Text>(time()).data!;
        await tester.tap(time());
        await tester.pump();
        expect(hide().onPressed, isNotNull);
        hide().onPressed!();
        await tester.pump();
        expect(_shown(tester, inEditor(find.text(text))), isFalse);
        // Ẩn rồi thì bật lại bằng chip của phần đó.
        await tester.tap(find.widgetWithText(FilterChip, 'Thời gian'));
        await tester.pump();
        expect(_shown(tester, inEditor(find.text(text))), isTrue);
      });

      testWidgets('màu tô cho phần đang chọn, phần khác giữ màu', (
        tester,
      ) async {
        await openEditor(tester);
        final black = find.bySemanticsLabel('Màu Đen');

        // Chưa chọn phần nào thì ô màu không tô gì.
        await tester.tap(black);
        await tester.pump();
        expect(_tint(tester, time()), isNull);

        await tester.tap(time());
        await tester.pump();
        await tester.tap(black);
        await tester.pump();

        expect(_tint(tester, time()), RunFaceTokens.ironCoal);
        expect(_tint(tester, km()), isNull);
      });

      Future<RunCardLayout> saveAndRead(
        WidgetTester tester,
        RunCardStyleController styles,
      ) async {
        await tester.tap(find.text('Xong'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Dùng'));
        await tester.pumpAndSettle();
        final card = _card();
        return styles.styleOf(card.id, card.rolledAt).layout;
      }

      testWidgets('Màu khác: chọn sắc rồi tông thì phần mang đúng màu đó', (
        tester,
      ) async {
        final styles = await openEditor(tester);
        await tester.tap(time());
        await tester.pump();
        await tester.tap(find.bySemanticsLabel('Màu khác'));
        await tester.pump();
        tester.widget<Slider>(find.byType(Slider)).onChanged!(120);
        await tester.pump();
        await tester.tap(find.bySemanticsLabel('Tông 48'));
        await tester.pump();

        // HSL(120°, 80%, 48%): C = 0,96 × 0,8 = 0,768, m = 0,096, nên
        // RGB = (0,096; 0,864; 0,096) × 255 = (24, 220, 24) = 18dc18.
        expect(_tint(tester, time()), const Color(0xFF18DC18));
        final layout = await saveAndRead(tester, styles);
        expect(layout.code, 'time:,,2,18dc18');
      });

      testWidgets('kéo đường chạy thì đường chạy dời, chữ đứng yên', (
        tester,
      ) async {
        final styles = await openEditor(tester);
        final c = cardRect(tester);
        final kmBefore = tester.getRect(km());
        // Nửa trên thẻ Thép chỉ có đường chạy, chữ nằm cả ở nửa dưới.
        final gesture = await tester.startGesture(
          Offset(c.center.dx, c.top + c.height * 0.25),
        );
        await gesture.moveBy(const Offset(40, 0));
        await tester.pump();
        await gesture.moveBy(const Offset(32, 0));
        await tester.pump();
        await gesture.up();
        await tester.pump();
        expect(tester.getRect(km()), kmBefore);

        final layout = await saveAndRead(tester, styles);
        expect(layout.parts.keys, [CardPart.route]);
        expect(layout.of(CardPart.route).moved, isTrue);
      });

      testWidgets('Đặt lại về chỗ mặc định, huỷ thì không đổi gì', (
        tester,
      ) async {
        final card = _card();
        final styles = await openEditor(tester);
        final text = tester.widget<Text>(time()).data!;
        await tester.tap(time());
        await tester.pump();
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.visibility_off_outlined),
            )
            .onPressed!();
        await tester.pump();
        await tester.tap(find.text('Đặt lại'));
        await tester.pump();
        expect(_shown(tester, inEditor(find.text(text))), isTrue);

        await tester.tap(time());
        await tester.pump();
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.visibility_off_outlined),
            )
            .onPressed!();
        await tester.pump();
        await tester.tap(find.byType(CloseButton));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Dùng'));
        await tester.pumpAndSettle();
        expect(
          styles.styleOf(card.id, card.rolledAt).layout,
          RunCardLayout.initial,
        );
      });
    });

    Future<void> openViewer(WidgetTester tester, RunCard card) async {
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            themeControllerProvider.overrideWith(
              (ref) => ThemeController(loadFromStorage: false),
            ),
            runCardStyleControllerProvider.overrideWith(
              (ref) => RunCardStyleController(loadFromStorage: false),
            ),
            runCardSkinControllerProvider.overrideWith(
              (ref) => RunCardSkinController(loadFromStorage: false),
            ),
            runCardProvider.overrideWith((ref, id) => Stream.value(card)),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showRunCardViewer(
                    context,
                    card,
                    runCardData(card, owner: 'Linh'),
                  ),
                  child: const Text('xem'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('xem'));
      // Frame đầu của route mới còn offstage cho Hero đo vị trí.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('màn xem thẻ đã lật mở được sheet Kiểu thẻ', (tester) async {
      await openViewer(tester, _card());

      await tester.tap(find.byTooltip('Kiểu thẻ'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Dùng'), findsOneWidget);
      // Để hiệu ứng gợi ý chạm của màn xem chạy hết.
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('màn xem thẻ Ẩn không có nút Kiểu thẻ', (tester) async {
      await openViewer(tester, _card(secret: 'secret.fire'));

      expect(find.text('Khoe thẻ'), findsOneWidget);
      expect(find.byTooltip('Kiểu thẻ'), findsNothing);
      await tester.pump(const Duration(seconds: 4));
    });

    // Ảnh xem trước bấm được thì là một nút bật tắt.
    Finder toggleIn(Key face) => find.descendant(
      of: find.byKey(face),
      matching: find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.toggled != null,
      ),
    );

    group('gợi ý chạm vào ảnh thẻ', () {
      final hint = find.byType(TapHintFinger);

      // Thẻ không tranh, bộ Thành phố: đổi được bố cục chữ và bản đồ.
      Future<void> openCity(WidgetTester tester) async {
        await open(tester, card: _card());
        await tester.tap(find.text('Thành phố'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
      }

      testWidgets('chờ sheet lên rồi chạy, mở lại sheet thì chạy lại', (
        tester,
      ) async {
        await openCity(tester);
        expect(hint, findsNothing);
        await tester.pump(const Duration(milliseconds: 400));
        expect(hint, findsOneWidget);
        // Ba chỗ (Chỉnh, chữ, mặt sau) một lượt chừng 6,5 giây: giây thứ 7
        // tay đang ở lượt hai.
        await tester.pump(const Duration(milliseconds: 6500));
        expect(hint, findsOneWidget);
        // Ba lượt (chừng 19,3 giây) xong thì thôi.
        await tester.pump(const Duration(seconds: 13));
        expect(hint, findsNothing);
        await tester.pumpWidget(const SizedBox());

        await openCity(tester);
        await tester.pump(const Duration(milliseconds: 400));
        expect(hint, findsOneWidget);
        await tester.pump(const Duration(seconds: 15));
      });

      testWidgets('tay ghé nút Chỉnh, rồi nút chữ, rồi nút mặt sau', (
        tester,
      ) async {
        await openCity(tester);
        final edit = tester.getRect(find.byKey(runCardEditKey));
        final text = tester.getRect(find.byKey(runCardTextLayoutKey));
        final back = tester.getRect(toggleIn(runCardMapSwitchKey));

        // Giữa lần ấn đầu ở từng chỗ, mỗi chỗ cách nhau 1,76 giây.
        await tester.pump(const Duration(milliseconds: 1500));
        expect(edit.contains(tester.getCenter(hint)), isTrue);
        await tester.pump(const Duration(milliseconds: 1760));
        expect(text.contains(tester.getCenter(hint)), isTrue);
        expect(edit.contains(tester.getCenter(hint)), isFalse);
        await tester.pump(const Duration(milliseconds: 1760));
        expect(back.contains(tester.getCenter(hint)), isTrue);
        expect(text.contains(tester.getCenter(hint)), isFalse);
        await tester.pump(const Duration(seconds: 15));
      });

      testWidgets('bấm vào ảnh thì tắt gợi ý', (tester) async {
        await openCity(tester);
        await tester.pump(const Duration(milliseconds: 400));
        expect(hint, findsOneWidget);

        await tester.tap(find.byKey(runCardMapSwitchKey));
        await tester.pump();
        expect(hint, findsNothing);
        await tester.pump(const Duration(seconds: 15));
      });

      testWidgets('bấm nút chữ cũng tắt gợi ý', (tester) async {
        await openCity(tester);
        await tester.tap(find.byKey(runCardTextLayoutKey));
        await tester.pump();
        expect(hint, findsNothing);
        await tester.pump(const Duration(seconds: 15));
      });
    });

    group('nút chữ trên mặt trước', () {
      final button = find.byKey(runCardTextLayoutKey);

      testWidgets('bấm vòng qua ba bố cục rồi về Đầy đủ', (tester) async {
        await open(tester, card: _card());
        await tester.tap(find.text('Bản vẽ'));
        await tester.pump();

        final seen = <String?>[];
        for (var i = 0; i < 4; i++) {
          seen.add(tester.widget<Semantics>(button).properties.value);
          await tester.tap(button);
          await tester.pump();
        }
        expect(seen, [
          'Đầy đủ, 1 trên 3',
          'Số trên, 2 trên 3',
          'Gọn, 3 trên 3',
          'Đầy đủ, 1 trên 3',
        ]);
        await tester.pump(const Duration(seconds: 15));
      });

      testWidgets('bấm nút chữ trên thẻ có tranh không đổi cỡ đường chạy', (
        tester,
      ) async {
        final card = _card(art: true);
        final (styles, _) = await open(
          tester,
          card: card,
          data: runCardData(
            card,
            owner: 'Bạn',
            previewArt: const ColoredBox(color: Color(0xFF55708A)),
          ),
        );
        await tester.tap(find.text('Bản vẽ'));
        await tester.pump();

        await tester.tap(button);
        await tester.pump();
        await tester.tap(find.text('Dùng'));
        await tester.pumpAndSettle();

        expect(styles.styleOf(card.id, card.rolledAt).id, 'blueprint.top');
      });
    });

    group('bấm mặt trước đổi cỡ đường chạy', () {
      final picker = find.byKey(runCardRouteSizeKey);
      final choice = toggleIn(runCardRouteSizeKey);

      // Tranh thật tải từ Storage, nên xem trước bằng một nền màu.
      Future<RunCardStyleController> openWithArt(WidgetTester tester) async {
        final card = _card(art: true);
        final (styles, _) = await open(
          tester,
          card: card,
          data: runCardData(
            card,
            owner: 'Bạn',
            previewArt: const ColoredBox(color: Color(0xFF55708A)),
          ),
        );
        return styles;
      }

      testWidgets('thẻ có tranh chọn Lớn rồi Dùng thì lưu đường lớn', (
        tester,
      ) async {
        final styles = await openWithArt(tester);
        final card = _card(art: true);
        expect(choice, findsOneWidget);

        await tester.tap(picker);
        await tester.pump();
        await tester.tap(find.text('Dùng'));
        await tester.pumpAndSettle();

        expect(styles.styleOf(card.id, card.rolledAt).id, 'current.full.route');
      });

      testWidgets('ba nút mặt trước đứng sát nhau ở góc dưới trái', (
        tester,
      ) async {
        await openWithArt(tester);
        await tester.tap(find.text('Bản vẽ'));
        await tester.pump();
        final preview = tester.getRect(picker);
        final size = tester.getRect(choice);
        final text = tester.getRect(find.byKey(runCardTextLayoutKey));
        final edit = tester.getRect(find.byKey(runCardEditKey));

        expect(size.center.dy, text.center.dy);
        expect(edit.center.dy, text.center.dy);
        // Liền nhau theo thứ tự chữ, Chỉnh, cỡ đường chạy.
        expect(edit.left, greaterThanOrEqualTo(text.right));
        expect(edit.left - text.right, lessThan(16));
        expect(size.left, greaterThanOrEqualTo(edit.right));
        expect(size.left - edit.right, lessThan(16));
        // Ba nút vượt quá giữa ảnh nhưng vẫn nằm trong ảnh.
        expect(size.right, lessThan(preview.right));
        expect(text.center.dy, greaterThan(preview.bottom - 30));
      });

      testWidgets('bấm nút icon cũng đổi, và nút đọc tên trạng thái', (
        tester,
      ) async {
        final styles = await openWithArt(tester);
        final card = _card(art: true);
        expect(
          tester.widget<Semantics>(choice).properties.value,
          'Con dấu tròn',
        );

        await tester.tap(choice);
        await tester.pump();
        expect(
          tester.widget<Semantics>(choice).properties.value,
          'Đường chạy lớn',
        );
        await tester.tap(find.text('Dùng'));
        await tester.pumpAndSettle();

        expect(styles.styleOf(card.id, card.rolledAt).id, 'current.full.route');
      });

      testWidgets('đổi sang bộ không có lựa chọn thì ẩn và không lưu cờ', (
        tester,
      ) async {
        final styles = await openWithArt(tester);
        final card = _card(art: true);
        await tester.tap(picker);
        await tester.pump();

        // Pixel nằm cuối dải, phải kéo tới mới dựng.
        await tester.dragUntilVisible(
          find.text('Pixel'),
          find.byType(ListView),
          const Offset(-200, 0),
        );
        await tester.tap(find.text('Pixel'));
        await tester.pump();
        expect(choice, findsNothing);
        await tester.tap(picker);
        await tester.pump();

        await tester.tap(find.text('Dùng'));
        await tester.pumpAndSettle();
        expect(styles.styleOf(card.id, card.rolledAt).id, 'pixel.full');
      });

      testWidgets('thẻ chưa có tranh không có lựa chọn', (tester) async {
        await open(tester, card: _card());
        expect(picker, findsOneWidget);
        expect(choice, findsNothing);
      });
    });

    group('bấm mặt sau bật bản đồ', () {
      final toggle = find.byKey(runCardMapSwitchKey);
      final choice = toggleIn(runCardMapSwitchKey);

      testWidgets('bật rồi Dùng thì thẻ có bản đồ, mặc định là tắt', (
        tester,
      ) async {
        final card = _card();
        final (styles, _) = await open(tester, card: card);

        await tester.tap(find.text('Thành phố'));
        await tester.pump();
        // Tắt là map mờ không có đường chạy, bật mới có đường chạy trên map.
        final mapRoute = find.byWidgetPredicate((w) => w is PolylineLayer);
        expect(choice, findsOneWidget);
        expect(mapRoute, findsNothing);

        await tester.tap(toggle);
        await tester.pump();
        expect(mapRoute, findsOneWidget);

        await tester.tap(find.text('Dùng'));
        await tester.pumpAndSettle();
        expect(
          styles.styleOf(card.id, card.rolledAt),
          const RunCardStyle.withMap(RunCardSet.city),
        );
      });

      testWidgets('bấm nút icon dưới mặt sau cũng bật bản đồ', (tester) async {
        final card = _card();
        final (styles, _) = await open(tester, card: card);
        await tester.tap(find.text('Thành phố'));
        await tester.pump();

        await tester.tap(choice);
        await tester.pump();
        expect(tester.widget<Semantics>(choice).properties.value, 'Bản đồ');
        await tester.tap(find.text('Dùng'));
        await tester.pumpAndSettle();

        expect(
          styles.styleOf(card.id, card.rolledAt),
          const RunCardStyle.withMap(RunCardSet.city),
        );
      });

      testWidgets('bộ không có tuỳ chọn thì không hiện, và không lưu cờ', (
        tester,
      ) async {
        await tester.runAsync(_loadCardFont);
        final card = _card();
        final (styles, _) = await open(tester, card: card);
        await tester.tap(find.text('Thành phố'));
        await tester.pump();
        await tester.tap(toggle);
        await tester.pump();

        await tester.tap(find.text('Hiện tại'));
        await tester.pump();
        expect(choice, findsNothing);

        await tester.tap(find.text('Dùng'));
        await tester.pumpAndSettle();
        expect(
          styles.styleOf(card.id, card.rolledAt),
          const RunCardStyle(RunCardSet.current),
        );
      });

      testWidgets('thẻ không GPS không có công tắc', (tester) async {
        await open(tester, card: _card(gps: false));

        await tester.tap(find.text('Thành phố'));
        await tester.pump();

        expect(choice, findsNothing);
      });
    });

    testWidgets('bộ có màu riêng không đổi bộ màu chung', (tester) async {
      final (_, skins) = await open(tester, card: _card());
      await skins.setChoice((RunNowAppearance.dark, RunNowElement.fire));

      await tester.tap(find.text('Bản vẽ'));
      await tester.pump();
      await tester.tap(find.text('Dùng'));
      await tester.pumpAndSettle();

      expect(skins.choice, (RunNowAppearance.dark, RunNowElement.fire));
    });

    testWidgets('nút bố cục chữ đứng cùng một chỗ ở mọi bộ', (tester) async {
      await open(tester, card: _card());
      final button = find.byKey(runCardTextLayoutKey);
      Rect? first;
      // Ba bộ để số km ở ba chỗ khác nhau.
      for (final set in ['Bản vẽ', 'Thành phố', 'Cassette']) {
        await tester.dragUntilVisible(
          find.text(set),
          find.byType(ListView),
          const Offset(-120, 0),
        );
        await tester.tap(find.text(set));
        await tester.pump();
        final rect = tester.getRect(button);
        first ??= rect;
        expect(rect, first, reason: set);
      }
      final preview = tester.getRect(find.byKey(runCardRouteSizeKey));
      expect(first!.center.dx, lessThan(preview.center.dx));
      await tester.pump(const Duration(seconds: 15));
    });

    testWidgets('bấm nút bố cục chữ thì nút đứng yên dưới tay', (tester) async {
      await open(tester, card: _card());
      await tester.tap(find.text('Bản vẽ'));
      await tester.pump();
      await tester.pump();
      final button = find.byKey(runCardTextLayoutKey);
      final before = tester.getRect(button);

      for (var i = 0; i < 3; i++) {
        await tester.tap(button);
        await tester.pump();
        await tester.pump();
        expect(tester.getRect(button), before);
      }
      await tester.pump(const Duration(seconds: 7));
    });

    testWidgets('bộ theo màu thì hiện chấm màu thay cho kiểu chữ', (
      tester,
    ) async {
      await open(tester, card: _card());

      expect(find.text('Thủy'), findsOneWidget);
      expect(find.byKey(runCardTextLayoutKey), findsNothing);

      await tester.tap(find.text('Bản vẽ'));
      await tester.pump();

      expect(find.text('Thủy'), findsNothing);
      expect(find.byKey(runCardTextLayoutKey), findsOneWidget);
    });
  });
}
