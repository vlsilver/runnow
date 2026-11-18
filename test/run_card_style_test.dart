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
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/achievements/run_card_panel.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/achievements/run_card_skin_choice.dart';
import 'package:myrun/src/achievements/run_card_style.dart';
import 'package:myrun/src/achievements/run_card_style_sheet.dart';
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
      await tester.tap(find.text('Số trên'));
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

    group('chọn cỡ đường chạy', () {
      final picker = find.byKey(runCardRouteSizeKey);

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
        expect(picker, findsOneWidget);

        await tester.tap(find.text('Lớn'));
        await tester.pump();
        await tester.tap(find.text('Dùng'));
        await tester.pumpAndSettle();

        expect(styles.styleOf(card.id, card.rolledAt).id, 'current.full.route');
      });

      testWidgets('đổi sang bộ không có lựa chọn thì ẩn và không lưu cờ', (
        tester,
      ) async {
        final styles = await openWithArt(tester);
        final card = _card(art: true);
        await tester.tap(find.text('Lớn'));
        await tester.pump();

        // Pixel nằm cuối dải, phải kéo tới mới dựng.
        await tester.dragUntilVisible(
          find.text('Pixel'),
          find.byType(ListView),
          const Offset(-200, 0),
        );
        await tester.tap(find.text('Pixel'));
        await tester.pump();
        expect(picker, findsNothing);

        await tester.tap(find.text('Dùng'));
        await tester.pumpAndSettle();
        expect(styles.styleOf(card.id, card.rolledAt).id, 'pixel.full');
      });

      testWidgets('thẻ chưa có tranh không có lựa chọn', (tester) async {
        await open(tester, card: _card());
        expect(picker, findsNothing);
      });
    });

    group('công tắc Bản đồ', () {
      final toggle = find.byKey(runCardMapSwitchKey);

      testWidgets('bật rồi Dùng thì thẻ có bản đồ, mặc định là tắt', (
        tester,
      ) async {
        final card = _card();
        final (styles, _) = await open(tester, card: card);

        await tester.tap(find.text('Thành phố'));
        await tester.pump();
        // Tắt là map mờ không có đường chạy, bật mới có đường chạy trên map.
        final mapRoute = find.byWidgetPredicate((w) => w is PolylineLayer);
        expect(toggle, findsOneWidget);
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
        expect(toggle, findsNothing);

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

        expect(toggle, findsNothing);
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

    testWidgets('bộ theo màu thì hiện chấm màu thay cho kiểu chữ', (
      tester,
    ) async {
      await open(tester, card: _card());

      expect(find.text('Thủy'), findsOneWidget);
      expect(find.text('Số trên'), findsNothing);

      await tester.tap(find.text('Bản vẽ'));
      await tester.pump();

      expect(find.text('Thủy'), findsNothing);
      expect(find.text('Số trên'), findsOneWidget);
    });
  });
}
