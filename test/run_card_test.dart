import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card.dart';
import 'package:myrun/src/achievements/run_card_art_sheet.dart';
import 'package:myrun/src/achievements/run_card_panel.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/widgets/photo_viewer.dart';

/// Doc thẻ như API trả: thời gian là chuỗi, bậc là khoá server. startedAt
/// không có múi giờ để test chạy ở máy nào cũng ra 06:12.
Map<String, dynamic> _cardJson({
  String tier = 'epic',
  Map<String, dynamic>? art,
  List<Map<String, dynamic>> route = const [
    {'lat': 21.0, 'lng': 105.8},
    {'lat': 21.01, 'lng': 105.8},
  ],
  List<Map<String, dynamic>> splits = const [],
  double? elevation = 40,
}) => {
  'id': 'r1',
  'activityId': 'r1',
  'tier': tier,
  'km': 15.0,
  'rollPpm': 123,
  'rolledAt': '2026-10-24T08:00:00Z',
  'startedAt': '2026-10-23T23:12:00Z',
  'odds': [
    {'tier': 'common', 'percent': 0},
    {'tier': 'rare', 'percent': 63.5},
    {'tier': 'epic', 'percent': 25.2},
    {'tier': 'legendary', 'percent': 9.1},
    {'tier': 'mythic', 'percent': 2.2},
  ],
  'snapshot': {
    'name': 'Dọc bờ sông Hồng',
    'sportType': 'Run',
    // Thứ Bảy.
    'startedAt': '2026-10-24T06:12:00',
    'distanceMeters': 15000,
    'movingTimeSeconds': 4965,
    'elapsedTimeSeconds': 5100,
    'elevationGainMeters': ?elevation,
    'route': route,
    'splits': splits,
  },
  'art': ?art,
};

RunCard _card({
  String tier = 'epic',
  Map<String, dynamic>? art,
  List<Map<String, dynamic>> route = const [
    {'lat': 21.0, 'lng': 105.8},
    {'lat': 21.01, 'lng': 105.8},
  ],
  List<Map<String, dynamic>> splits = const [],
  double? elevation = 40,
}) => RunCard.fromJson(
  _cardJson(
    tier: tier,
    art: art,
    route: route,
    splits: splits,
    elevation: elevation,
  ),
);

const _done = {
  'status': 'done',
  'style': 'linocut',
  'attempt': 1,
  'path': 'users/u1/runCards/r1/art.png',
};

ActivitySummary _run({List<ActivityPhoto> photos = const []}) =>
    ActivitySummary(
      id: 'r1',
      name: 'Dọc bờ sông Hồng',
      kind: ActivityKind.run,
      startedAt: DateTime(2026, 10, 24, 6, 12),
      distanceMeters: 14960,
      movingTimeSeconds: 4965,
      elapsedTimeSeconds: 5100,
      photos: photos,
    );

const _runPhotoPath = 'users/u1/activities/r1/photos/p1.jpg';

final _runPhoto = ActivityPhoto(
  id: 'p1',
  capturedAt: DateTime(2026, 10, 24, 6, 40),
  latitude: 21,
  longitude: 105.8,
  distanceMeters: 5000,
  storagePath: _runPhotoPath,
);

/// Ảnh PNG 1x1 thật, vì app đọc loại ảnh từ byte đầu.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

/// Danh sách phong cách như GET /v1/art-styles; nhóm không có phong cách nào
/// thì app ẩn.
const _styles = {
  'families': [
    {'key': 'painting', 'label': 'Hội hoạ'},
    {'key': 'anime', 'label': 'Anime'},
    {'key': 'empty', 'label': 'Nhóm trống'},
  ],
  'styles': [
    {
      'key': 'oil',
      'version': 1,
      'name': 'Sơn dầu',
      'family': 'painting',
      'swatch': ['#7a4b2a', '#d9a441', '#2f4f6f'],
    },
    {
      'key': 'anime_cel',
      'version': 1,
      'name': 'Anime cel',
      'family': 'anime',
      'swatch': ['#ff6fa8', '#6fd3ff'],
    },
  ],
};

/// Thư viện ảnh giả: trả [bytes] khi chọn, ghi lại mỗi lần tải lên.
class _Photos extends RunCardPhotos {
  _Photos([this.bytes]);

  Uint8List? bytes;
  final uploads = <String>[];

  @override
  Future<Uint8List?> pick() async => bytes;

  @override
  Future<String> upload(
    String activityId,
    Uint8List bytes,
    String contentType,
  ) async {
    uploads.add('$activityId $contentType ${bytes.length}');
    return 'users/u1/runCards/$activityId/src.jpg';
  }
}

/// Độ sáng trung bình RGB tại điểm (fx, fy) tính theo tỉ lệ khung 300x420.
Future<int Function(double, double)> _paintArt(
  WidgetTester tester,
  List<LatLng> points,
) async {
  final boundary = GlobalKey();
  await tester.pumpWidget(
    Center(
      child: RepaintBoundary(
        key: boundary,
        child: SizedBox(
          width: 300,
          height: 420,
          child: RunRouteArt(points: points, tier: GameCardTier.rare),
        ),
      ),
    ),
  );
  late ByteData pixels;
  await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    pixels = (await (await render.toImage()).toByteData())!;
  });
  return (fx, fy) {
    final i = ((420 * fy).toInt() * 300 + (300 * fx).toInt()) * 4;
    return (pixels.getUint8(i) +
            pixels.getUint8(i + 1) +
            pixels.getUint8(i + 2)) ~/
        3;
  };
}

/// API giả: ghi lại lệnh gọi, POST lật thẻ đẩy thẻ vào stream như Firestore.
class _Backend {
  final requests = <String>[];
  final artBodies = <Map<String, dynamic>>[];
  final cards = StreamController<RunCard?>.broadcast();
  Map<String, dynamic> view = {'card': null, 'odds': _cardJson()['odds']};

  /// Mã lỗi 409 trả cho lệnh vẽ; null thì nhận và đẩy thẻ đang vẽ.
  String? artError;

  /// Lật thì trượt như buổi ngắn quay hụt: 409 card_missed, view báo trượt.
  bool missRoll = false;

  RunNowApiClient client() => RunNowApiClient(
    baseUri: Uri.parse('https://api.example.test'),
    tokenProvider: ({required forceRefresh}) async => 'token',
    appVersion: () async => '1.6.0+1',
    appPlatform: 'ios',
    httpClient: MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      Object out = view;
      var status = 200;
      if (request.url.path == '/v1/art-styles') {
        out = _styles;
      } else if (request.url.path.endsWith('/art')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        artBodies.add(body);
        if (artError case final code?) {
          status = 409;
          out = {'error': code, 'message': 'bị từ chối'};
        } else {
          final card = _cardJson(
            art: {
              'status': 'drawing',
              'attempt': 1,
              'requestedAt': DateTime.now().toUtc().toIso8601String(),
              ...body,
            },
          );
          cards.add(RunCard.fromJson(card));
          out = {'card': card};
        }
      } else if (request.method == 'POST' && missRoll) {
        status = 409;
        out = {'error': 'card_missed', 'message': 'Lần lật này không ra thẻ.'};
        view = {'card': null, 'reason': 'card_missed'};
      } else if (request.method == 'POST') {
        final card = _cardJson(tier: 'mythic');
        cards.add(RunCard.fromJson(card));
        out = {'card': card};
      }
      return http.Response(
        jsonEncode(out),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
}

Future<void> _pumpPanel(
  WidgetTester tester,
  _Backend backend, {
  RunCard? initial,
  List<ActivityPhoto> photos = const [],
  _Photos? picker,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runNowApiClientProvider.overrideWithValue(backend.client()),
        runCardPhotosProvider.overrideWithValue(picker ?? _Photos()),
        runCardProvider('r1').overrideWith((ref) async* {
          yield initial;
          yield* backend.cards.stream;
        }),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RunCardPanel(
              activity: _run(photos: photos),
              owner: 'An',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// Cho sheet và dialog chạy xong hiệu ứng mở/đóng. Không dùng pumpAndSettle
/// vì vòng xoay "đang vẽ" chạy mãi.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

/// Cuộn tới [text] rồi chạm. ensureVisible chỉ đặt vị trí cuộn, cần một frame
/// để layout theo kịp.
Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.pump();
  await tester.tap(find.text(text));
  await _settle(tester);
}

/// Nút Vẽ ở chân sheet có bật không.
bool _drawEnabled(WidgetTester tester, String label) => tester
    .widget<ButtonStyleButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
      ),
    )
    .enabled;

/// Đồng ý gửi ảnh, bấm Vẽ ở chân sheet rồi xác nhận trong dialog.
Future<void> _consentAndDraw(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.byType(Checkbox));
  await tester.pump();
  await tester.tap(find.byType(Checkbox));
  await tester.pump();
  await _confirmDraw(tester, label);
}

Future<void> _confirmDraw(WidgetTester tester, String label) async {
  await _tapText(tester, label);
  expect(find.text('$label?'), findsOne);
  await tester.tap(find.widgetWithText(FilledButton, 'Vẽ'));
  await _settle(tester);
}

void main() {
  test('server tier keys map onto the five card tiers', () {
    // Khoá lấy từ backend run_card.go: common, rare, epic, legendary, mythic.
    expect(runCardTierFromKey('common'), GameCardTier.common);
    expect(runCardTierFromKey('rare'), GameCardTier.rare);
    expect(runCardTierFromKey('epic'), GameCardTier.superRare);
    expect(runCardTierFromKey('legendary'), GameCardTier.legendary);
    expect(runCardTierFromKey('mythic'), GameCardTier.mythic);
    expect(runCardTierFromKey('cosmic'), GameCardTier.common);
  });

  test('only running activities get a card', () {
    ActivitySummary kind(ActivityKind k) => ActivitySummary(
      id: 'a',
      name: 'a',
      kind: k,
      startedAt: DateTime(2026),
      distanceMeters: 40000,
      movingTimeSeconds: 3600,
      elapsedTimeSeconds: 3600,
    );
    expect(hasRunCard(kind(ActivityKind.run)), isTrue);
    expect(hasRunCard(kind(ActivityKind.trailRun)), isTrue);
    expect(hasRunCard(kind(ActivityKind.virtualRun)), isTrue);
    expect(hasRunCard(kind(ActivityKind.ride)), isFalse);
    expect(hasRunCard(kind(ActivityKind.walk)), isFalse);
    expect(hasRunCard(kind(ActivityKind.motorbike)), isFalse);
  });

  test('a card parses from the API and from a Firestore doc alike', () {
    final api = _card(art: _done);
    expect(api.tier, GameCardTier.superRare);
    expect(api.km, 15);
    expect(api.odds.map((o) => o.percent), [0, 63.5, 25.2, 9.1, 2.2]);
    expect(api.rolledAt, DateTime.utc(2026, 10, 24, 8));
    expect(api.snapshot.route, const [LatLng(21, 105.8), LatLng(21.01, 105.8)]);
    expect(api.artPath, 'users/u1/runCards/r1/art.png');

    // Doc Firestore đã đổi Timestamp sang DateTime; map con là Map thường.
    final doc = RunCard.fromJson({
      ..._cardJson(),
      'rolledAt': DateTime.utc(2026, 10, 24, 8),
      'art': <Object?, Object?>{
        'status': 'drawing',
        'style': 'linocut',
        'attempt': 2,
        'requestedAt': DateTime.utc(2026, 10, 24, 9),
      },
    });
    expect(doc.rolledAt, DateTime.utc(2026, 10, 24, 8));
    expect(doc.art!.status, RunCardArtStatus.drawing);
    expect(doc.art!.requestedAt, DateTime.utc(2026, 10, 24, 9));
    expect(doc.artPath, isNull, reason: 'đang vẽ thì chưa có tranh');
  });

  test('card text comes from the snapshot', () {
    final data = runCardData(_card(), owner: 'An Nguyễn');
    expect(data.tier, GameCardTier.superRare);
    expect(data.kind, 'BUỔI CHẠY');
    expect(data.hero, '15,0');
    expect(data.title, 'Dọc bờ sông Hồng');
    expect(data.owner, 'AN NGUYỄN');
    expect(data.serial, '06:12');
    // 4965 s cho 15 km là 331 s/km.
    expect(data.desc, 'Pace 5:31 /km · 1:22:45 · leo 40 m');
    expect(data.meta, 'THỨ BẢY · SÁNG');
    expect(data.date, '24.10.2026');
    expect(
      runCardData(_card(elevation: null), owner: 'An').desc,
      'Pace 5:31 /km · 1:22:45',
    );
  });

  test('the drawn art replaces the route, which moves into a stamp', () {
    final plain = runCardData(_card(), owner: 'An');
    expect(plain.art, isA<RunRouteArt>());
    expect(plain.stamp, isNull);

    final drawing = runCardData(
      _card(art: {'status': 'drawing', 'style': 'linocut', 'attempt': 1}),
      owner: 'An',
    );
    expect(drawing.art, isA<RunRouteArt>());

    final drawn = runCardData(_card(art: _done), owner: 'An');
    expect(drawn.art, isA<StoragePhoto>());
    expect(drawn.stamp, isA<RunRouteStamp>());

    final noGps = runCardData(
      _card(art: _done, route: const []),
      owner: 'An',
    );
    expect(noGps.stamp, isNull);
  });

  test('a short last split stays out of the pace chart', () {
    final paces = runCardSplitPaces([
      const RunCardSplit(distanceMeters: 1000, movingTimeSeconds: 330),
      const RunCardSplit(distanceMeters: 1000, movingTimeSeconds: 320),
      const RunCardSplit(distanceMeters: 150, movingTimeSeconds: 40),
    ]);
    expect(paces, [330, 320]);
  });

  testWidgets('route art draws the run as a bright line across the card', (
    tester,
  ) async {
    // Đường thẳng bắc–nam: hình vẽ nằm giữa thẻ theo chiều ngang, trong khoảng
    // trống phía trên khối chữ.
    final luma = await _paintArt(tester, const [
      LatLng(21.00, 105.8),
      LatLng(21.01, 105.8),
    ]);
    expect(luma(0.5, 0.38), greaterThan(200), reason: 'nét đường chạy');
    expect(luma(0.05, 0.05), lessThan(80), reason: 'nền');

    final empty = await _paintArt(tester, const []);
    expect(empty(0.5, 0.38), lessThan(80), reason: 'không GPS thì chỉ có nền');
  });

  testWidgets('the back shows the map, per-km pace and the three numbers', (
    tester,
  ) async {
    final card = _card(
      tier: 'mythic',
      splits: const [
        {'distanceMeters': 1000, 'movingTimeSeconds': 330},
        {'distanceMeters': 1000, 'movingTimeSeconds': 320},
        {'distanceMeters': 1000, 'movingTimeSeconds': 341},
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: AchievementCard(
            data: runCardData(card, owner: 'An'),
            back: true,
            animate: false,
          ),
        ),
      ),
    );
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('NHANH NHẤT · KM 2 · 5:20'), findsOneWidget);
    expect(find.text('15,0'), findsOneWidget);
    expect(find.text('1:22:45'), findsOneWidget);
    expect(find.text('5:31'), findsOneWidget);
    expect(find.text('THẦN THOẠI'), findsOneWidget);
    expect(find.text('Dọc bờ sông Hồng'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a run without GPS or splits has a back without map or chart', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: AchievementCard(
            data: runCardData(_card(route: const []), owner: 'An'),
            back: true,
            animate: false,
          ),
        ),
      ),
    );
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.textContaining('NHANH NHẤT'), findsNothing);
    expect(find.text('1:22:45'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unrolled run shows its odds and flips into the card', (
    tester,
  ) async {
    final backend = _Backend();
    await _pumpPanel(tester, backend);
    expect(find.text('LẬT ĐỂ XEM ĐỘ HIẾM'), findsOneWidget);
    expect(find.text('TỈ LỆ CHO BUỔI 15,0 KM'), findsOneWidget);
    // Bậc 0% không hiện.
    expect(find.text('Thường'), findsNothing);
    expect(find.text('63,5%'), findsOneWidget);
    expect(find.text('2,2%'), findsOneWidget);

    await tester.ensureVisible(find.text('Lật thẻ'));
    await tester.tap(find.text('Lật thẻ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(backend.requests, [
      'GET /v1/activities/r1/card',
      'POST /v1/activities/r1/card',
    ]);
    expect(find.text('Lật thẻ'), findsNothing);
    expect(find.textContaining('Thần thoại · 15,0 km'), findsOneWidget);
    expect(find.text('Khoe thẻ'), findsOneWidget);
  });

  testWidgets('a short run shows its chance and a miss is final', (
    tester,
  ) async {
    final backend = _Backend()
      ..view = {'card': null, 'odds': _cardJson()['odds'], 'chance': 20}
      ..missRoll = true;
    await _pumpPanel(tester, backend);
    expect(find.textContaining('20% cơ hội ra thẻ'), findsOneWidget);

    await tester.ensureVisible(find.text('Lật thẻ'));
    await tester.pump();
    await tester.tap(find.text('Lật thẻ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(backend.requests, [
      'GET /v1/activities/r1/card',
      'POST /v1/activities/r1/card',
      'GET /v1/activities/r1/card',
    ]);
    expect(find.textContaining('không ra thẻ'), findsOneWidget);
    expect(find.text('Lật thẻ'), findsNothing);
    // Trượt là kết quả, không báo như lỗi.
    expect(find.textContaining('Không lật được thẻ'), findsNothing);
  });

  testWidgets('a duplicate run says why it has no card', (tester) async {
    final backend = _Backend()
      ..view = {'card': null, 'reason': 'card_duplicate'};
    await _pumpPanel(tester, backend);
    expect(find.textContaining('trùng một buổi khác'), findsOneWidget);
    expect(find.text('Lật thẻ'), findsNothing);
  });

  testWidgets('a rolled card can be turned to its data side for sharing', (
    tester,
  ) async {
    final backend = _Backend();
    await _pumpPanel(tester, backend, initial: _card());
    expect(backend.requests, isEmpty, reason: 'đã có thẻ thì không hỏi tỉ lệ');
    expect(find.text('MẶT SAU · DỮ LIỆU'), findsNothing);

    await tester.ensureVisible(find.text('Mặt sau'));
    await tester.tap(find.text('Mặt sau'));
    await tester.pump();
    expect(find.text('MẶT SAU · DỮ LIỆU'), findsOneWidget);
  });

  test('a picked photo is typed from its first bytes', () {
    // Chữ ký file: JPEG bắt đầu FF D8, PNG bắt đầu 89 'PNG'.
    expect(
      runCardPhotoType(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])),
      'image/jpeg',
    );
    expect(runCardPhotoType(_png), 'image/png');
    expect(runCardPhotoType(utf8.encode('GIF89a')), isNull);
    expect(runCardPhotoType(Uint8List(0)), isNull);
  });

  testWidgets('a card without art draws with a style and a run photo', (
    tester,
  ) async {
    final backend = _Backend();
    await _pumpPanel(tester, backend, initial: _card(), photos: [_runPhoto]);
    await _tapText(tester, 'Vẽ tranh nền');

    expect(find.text('Thẻ Siêu hiếm · vẽ một lần, xong là cố định'), findsOne);
    expect(find.text('Hội hoạ'), findsOne);
    expect(find.text('Nhóm trống'), findsNothing);
    expect(find.text('Sơn dầu'), findsOne);
    expect(find.text('Anime cel'), findsNothing, reason: 'khác nhóm đang mở');
    expect(_drawEnabled(tester, 'Chọn một phong cách'), isFalse);

    await _tapText(tester, 'Sơn dầu');
    expect(_drawEnabled(tester, 'Vẽ bằng Sơn dầu'), isTrue);

    await tester.tap(find.bySemanticsLabel('Ảnh buổi chạy'));
    await tester.pump();
    expect(
      _drawEnabled(tester, 'Vẽ bằng Sơn dầu'),
      isFalse,
      reason: 'có ảnh thì phải đồng ý gửi ảnh trước',
    );

    await _consentAndDraw(tester, 'Vẽ bằng Sơn dầu');
    expect(backend.artBodies, [
      {'style': 'oil', 'photoPath': _runPhotoPath},
    ]);
    expect(find.text('Chọn phong cách'), findsNothing, reason: 'sheet đóng');
    expect(find.text('Đang vẽ tranh nền'), findsOne);
    expect(find.text('Vẽ lại'), findsNothing, reason: 'vừa gửi thì chưa kẹt');
  });

  testWidgets('an uploaded PNG goes up before the draw request', (
    tester,
  ) async {
    final backend = _Backend();
    final picker = _Photos(utf8.encode('GIF89a....'));
    await _pumpPanel(tester, backend, initial: _card(), picker: picker);
    await _tapText(tester, 'Vẽ tranh nền');
    await _tapText(tester, 'Anime');
    await _tapText(tester, 'Anime cel');

    await _tapText(tester, 'Tải ảnh');
    expect(find.text('Chỉ dùng được ảnh JPEG hoặc PNG.'), findsOne);
    expect(find.byType(Checkbox), findsNothing, reason: 'GIF không được nhận');

    picker.bytes = _png;
    await _tapText(tester, 'Tải ảnh');
    await _consentAndDraw(tester, 'Vẽ bằng Anime cel');
    expect(picker.uploads, ['r1 image/png ${_png.length}']);
    expect(backend.artBodies, [
      {'style': 'anime_cel', 'photoPath': 'users/u1/runCards/r1/src.jpg'},
    ]);
  });

  testWidgets('a refused draw keeps the sheet open with the reason', (
    tester,
  ) async {
    final backend = _Backend()..artError = 'art_fixed';
    await _pumpPanel(tester, backend, initial: _card());
    await _tapText(tester, 'Vẽ tranh nền');
    await _tapText(tester, 'Sơn dầu');
    await _confirmDraw(tester, 'Vẽ bằng Sơn dầu');

    expect(backend.artBodies, [
      {'style': 'oil'},
    ]);
    expect(find.text('Thẻ này đã có tranh, không vẽ lại được.'), findsOne);
    expect(find.text('Chọn phong cách'), findsOne);
  });

  testWidgets('a failed draw says why and reopens with the old choice', (
    tester,
  ) async {
    final backend = _Backend();
    await _pumpPanel(
      tester,
      backend,
      initial: _card(
        art: {
          'status': 'failed',
          'style': 'anime_cel',
          'attempt': 1,
          'reason': 'budget',
        },
      ),
    );
    expect(
      find.text('Hôm nay 3i đã dùng hết hạn mức vẽ tranh. Mai thử lại nhé.'),
      findsOne,
    );
    await _tapText(tester, 'Chọn lại và vẽ');
    expect(find.text('Vẽ bằng Anime cel'), findsOne);
  });

  testWidgets('a stuck draw offers to send the same choice again', (
    tester,
  ) async {
    final backend = _Backend();
    await _pumpPanel(
      tester,
      backend,
      initial: _card(
        art: {
          'status': 'drawing',
          'style': 'oil',
          'attempt': 1,
          'photoPath': _runPhotoPath,
          'requestedAt': DateTime.now()
              .toUtc()
              .subtract(const Duration(minutes: 10))
              .toIso8601String(),
        },
      ),
    );
    expect(find.text('Lâu quá chưa xong, có thể lần vẽ bị kẹt.'), findsOne);
    await _tapText(tester, 'Vẽ lại');
    expect(backend.artBodies, [
      {'style': 'oil', 'photoPath': _runPhotoPath},
    ]);
  });
}
