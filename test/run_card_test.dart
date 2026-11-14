import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

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
import 'package:myrun/src/achievements/run_card_art_steps.dart';
import 'package:myrun/src/achievements/run_card_collection.dart';
import 'package:myrun/src/achievements/run_card_flow.dart';
import 'package:myrun/src/achievements/run_card_panel.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/achievements/card_share.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/photo_viewer.dart';
import 'package:myrun/src/widgets/storage_image.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

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
      'example': 'artStyles/examples/oil.jpg',
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
  final downloads = <String>[];
  final focuses = <Alignment>[];

  @override
  Future<Uint8List?> pick() async => bytes;

  @override
  Future<Uint8List> download(String path) async {
    downloads.add(path);
    return _png;
  }

  @override
  Future<Uint8List> cropToCard(Uint8List bytes, Alignment focus) async {
    focuses.add(focus);
    return bytes;
  }

  @override
  Future<String> upload(
    String activityId,
    Uint8List bytes,
    String contentType, {
    String file = 'src.jpg',
  }) async {
    uploads.add('$activityId $file $contentType ${bytes.length}');
    return 'users/u1/runCards/$activityId/$file';
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

/// Bảng chia sẻ của máy: ghi lại thứ được gửi đi.
class _FakeShare extends SharePlatform {
  final shared = <ShareParams>[];

  @override
  Future<ShareResult> share(ShareParams params) async {
    shared.add(params);
    return const ShareResult('ok', ShareResultStatus.success);
  }
}

final share = _FakeShare();

/// File khoe giữ trong bộ nhớ thay cho thư mục của app.
class _MemoryShareStore extends CardShareStore {
  final saved = <String, CardShareFiles>{};
  int saves = 0;

  @override
  Future<CardShareFiles?> load(String cardId, String key) async =>
      saved['$cardId/$key'];

  @override
  Future<void> save(String cardId, String key, CardShareFiles files) async {
    saves++;
    saved['$cardId/$key'] = files;
  }

  @override
  Future<void> clear(String cardId) async =>
      saved.removeWhere((k, _) => k.startsWith('$cardId/'));
}

/// API giả: ghi lại lệnh gọi, POST lật thẻ đẩy thẻ vào stream như Firestore.
class _Backend {
  final requests = <String>[];
  final artBodies = <Map<String, dynamic>>[];
  final cards = StreamController<RunCard?>.broadcast();
  Map<String, dynamic> view = {'card': null, 'odds': _cardJson()['odds']};

  /// Mã lỗi 409 trả cho lệnh vẽ; null thì nhận và đẩy thẻ đang vẽ.
  String? artError;

  /// Danh sách GET /v1/art-styles trả về; có [stylesGate] thì đợi nó xong mới trả.
  Map<String, dynamic> styles = _styles;
  Completer<void>? stylesGate;

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
        await stylesGate?.future;
        out = styles;
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
  CardShareStore? shareStore,
  List<RunCard> collection = const [],
  VoidCallback? onDone,
}) async {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runNowApiClientProvider.overrideWithValue(backend.client()),
        cardShareStoreProvider.overrideWithValue(
          shareStore ?? _MemoryShareStore(),
        ),
        runCardPhotosProvider.overrideWithValue(picker ?? _Photos()),
        runCardsProvider.overrideWith((ref) => Stream.value(collection)),
        runCardProvider('r1').overrideWith((ref) async* {
          yield initial;
          yield* backend.cards.stream;
        }),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: RunCardPanel(
            activity: _run(photos: photos),
            owner: 'An',
            onDone: onDone ?? () {},
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

/// Ô mô tả thêm ở bước xác nhận, cuộn tới cho nó được dựng.
Future<Finder> _noteField(WidgetTester tester) async {
  final field = find.widgetWithText(TextField, 'Mô tả thêm');
  await tester.scrollUntilVisible(
    field,
    200,
    scrollable: find
        .descendant(
          of: find.byType(RunCardArtSteps),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        )
        .first,
  );
  return field;
}

Future<void> _tapTip(WidgetTester tester, String tooltip) async {
  await tester.tap(find.byTooltip(tooltip));
  await _settle(tester);
}

Future<void> _next(WidgetTester tester) => _tapTip(tester, 'Tiếp');

/// Từ thẻ vẽ hỏng đi tới bước chọn phong cách.
Future<void> _openRedraw(WidgetTester tester) async {
  await _tapText(tester, 'Vẽ lại');
  await _next(tester);
}

bool _navEnabled(WidgetTester tester, String tooltip) =>
    tester
        .widget<IconButton>(
          find.ancestor(
            of: find.byTooltip(tooltip),
            matching: find.byType(IconButton),
          ),
        )
        .onPressed !=
    null;

/// Từ màn kết quả đi tới bước chọn phong cách.
Future<void> _openStyles(WidgetTester tester) async {
  await _tapText(tester, 'Vẽ tranh nền');
  await _next(tester);
}

/// Tích đồng ý rồi bấm nút cuối.
Future<void> _consentAndSend(WidgetTester tester, String tooltip) async {
  await tester.ensureVisible(find.byType(Checkbox));
  await tester.pump();
  await tester.tap(find.byType(Checkbox));
  await tester.pump();
  await _tapTip(tester, tooltip);
}

const _srcPath = 'users/u1/runCards/r1/src.jpg';

void main() {
  setUpAll(() => SharePlatform.instance = share);

  test('server tier keys map onto the five card tiers', () {
    // Khoá lấy từ backend run_card.go: common, rare, epic, legendary, mythic.
    expect(runCardTierFromKey('common'), GameCardTier.common);
    expect(runCardTierFromKey('rare'), GameCardTier.rare);
    expect(runCardTierFromKey('epic'), GameCardTier.superRare);
    expect(runCardTierFromKey('legendary'), GameCardTier.legendary);
    expect(runCardTierFromKey('mythic'), GameCardTier.mythic);
    expect(runCardTierFromKey('cosmic'), GameCardTier.common);
  });

  test('a secret variant names its element, anything else is a plain card', () {
    // Khoá lấy từ backend run_card.go: "secret." + tên hành.
    expect(runCardSecretFromKey('secret.metal'), RunNowElement.metal);
    expect(runCardSecretFromKey('secret.wood'), RunNowElement.wood);
    expect(runCardSecretFromKey('secret.water'), RunNowElement.water);
    expect(runCardSecretFromKey('secret.fire'), RunNowElement.fire);
    expect(runCardSecretFromKey('secret.earth'), RunNowElement.earth);
    expect(runCardSecretFromKey('secret.gold'), isNull);
    expect(runCardSecretFromKey('fire'), isNull);
    expect(runCardSecretFromKey(null), isNull);

    expect(_card().secret, isNull);
    final secret = RunCard.fromJson({..._cardJson(), 'variant': 'secret.fire'});
    expect(secret.secret, RunNowElement.fire);
    expect(runCardData(secret, owner: 'An').secret, RunNowElement.fire);
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
    expect(plain.art, isA<RunDefaultArt>());
    expect(plain.stamp, isNull);

    final drawing = runCardData(
      _card(art: {'status': 'drawing', 'style': 'linocut', 'attempt': 1}),
      owner: 'An',
    );
    expect(drawing.art, isA<RunDefaultArt>());

    final drawn = runCardData(_card(art: _done), owner: 'An');
    expect(drawn.art, isA<StoragePhoto>());
    expect((drawn.art as StoragePhoto).placeholder, isA<RunDefaultArt>());
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

  test('the fine pace line is read only when it can draw a line', () {
    final pace = RunCardPace.fromJson({
      'stepMeters': 500,
      'secondsPerKm': [300, 310.5],
    })!;
    expect(pace.stepMeters, 500);
    expect(pace.secondsPerKm, [300, 310.5]);
    expect(RunCardPace.fromJson(null), isNull);
    expect(
      RunCardPace.fromJson({
        'stepMeters': 500,
        'secondsPerKm': [300],
      }),
      isNull,
    );
    expect(
      RunCardPace.fromJson({
        'stepMeters': 0,
        'secondsPerKm': [300, 310],
      }),
      isNull,
    );
  });

  test('the chart title names the step it draws', () {
    RunCardPace pace(int step) =>
        RunCardPace(stepMeters: step, secondsPerKm: const [300, 310]);
    expect(runCardPaceTitle(null), 'PACE MỖI KM');
    expect(runCardPaceTitle(pace(200)), 'PACE MỖI 200 M');
    expect(runCardPaceTitle(pace(500)), 'PACE MỖI 500 M');
    expect(runCardPaceTitle(pace(1000)), 'PACE MỖI KM');
  });

  test('the mark sits inside the km the header calls fastest', () {
    // Km 2 nhanh nhất, gồm điểm 2 và 3 ở bước 500 m. Điểm 0 nhanh hơn hẳn nhưng
    // nằm ở km 1 nên không được đánh dấu.
    const paces = [240.0, 330.0, 310.0, 300.0, 340.0, 335.0];
    expect(
      runCardPaceMark(paces, kmPaces: const [320, 305, 338], stepMeters: 500),
      3,
    );
    expect(runCardPaceMark(paces, kmPaces: const [], stepMeters: 500), 0);
    expect(runCardPaceMark(paces, kmPaces: const [320, 305]), 0);
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

  testWidgets('the back draws the fine line when the card has one', (
    tester,
  ) async {
    final json = _cardJson(
      tier: 'mythic',
      route: const [
        {'lat': 21.0, 'lng': 105.8},
        {'lat': 21.01, 'lng': 105.8},
      ],
      splits: const [
        {'distanceMeters': 1000, 'movingTimeSeconds': 330},
        {'distanceMeters': 1000, 'movingTimeSeconds': 320},
      ],
    );
    (json['snapshot'] as Map)['pace'] = {
      'stepMeters': 500,
      'secondsPerKm': [335, 325, 322, 318],
    };
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: AchievementCard(
            data: runCardData(RunCard.fromJson(json), owner: 'An'),
            back: true,
            animate: false,
          ),
        ),
      ),
    );
    expect(find.text('PACE MỖI 500 M'), findsOneWidget);
    expect(find.text('NHANH NHẤT · KM 2 · 5:20'), findsOneWidget);
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
    // Khoe là một nút ở góc phải trên, không còn nút Xong.
    expect(find.byTooltip('Khoe thẻ'), findsOneWidget);
    expect(find.text('Khoe thẻ'), findsNothing);
    expect(find.text('Xong'), findsNothing);
    final share = tester.getCenter(find.byTooltip('Khoe thẻ'));
    final close = tester.getCenter(find.byTooltip('Đóng'));
    expect(share.dy, close.dy);
    expect(share.dx, greaterThan(close.dx));
    expect(find.text('Vẽ tranh nền'), findsOneWidget);
  });

  testWidgets('X closes the screen', (tester) async {
    var closed = 0;
    await _pumpPanel(
      tester,
      _Backend(),
      initial: _card(),
      onDone: () => closed++,
    );
    await _tapTip(tester, 'Đóng');
    expect(closed, 1);
  });

  testWidgets('a finger shows how to touch a just-flipped card, then leaves', (
    tester,
  ) async {
    final backend = _Backend();
    await _pumpPanel(tester, backend);
    await tester.tap(find.text('Lật thẻ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byIcon(Icons.touch_app_rounded), findsOneWidget);
    expect(find.textContaining('chạm thẻ'), findsNothing);

    await tester.pump(const Duration(seconds: 4));
    await tester.pump();
    expect(find.byIcon(Icons.touch_app_rounded), findsNothing);
  });

  testWidgets('reopening an old card shows no finger', (tester) async {
    await _pumpPanel(tester, _Backend(), initial: _card());
    expect(find.byIcon(Icons.touch_app_rounded), findsNothing);
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
    // Hiệu ứng lật chạy từ lúc view báo trượt, sau lần tải lại.
    await tester.pump(const Duration(milliseconds: 800));
    expect(backend.requests, [
      'GET /v1/activities/r1/card',
      'POST /v1/activities/r1/card',
      'GET /v1/activities/r1/card',
    ]);
    expect(find.textContaining('không ra thẻ'), findsOneWidget);
    expect(find.text('Lật thẻ'), findsNothing);
    expect(find.text('LẬT THẤT BẠI'), findsOneWidget);
    expect(find.text('LẬT ĐỂ XEM ĐỘ HIẾM'), findsNothing);
    // Trượt là kết quả, không báo như lỗi.
    expect(find.textContaining('Không lật được thẻ'), findsNothing);
  });

  testWidgets('a duplicate run points to the main run, not a failure', (
    tester,
  ) async {
    final backend = _Backend()
      ..view = {'card': null, 'reason': 'card_duplicate'};
    await _pumpPanel(tester, backend);
    expect(find.text('ĐÃ MỞ Ở BUỔI CHÍNH'), findsOneWidget);
    expect(find.textContaining('thẻ nằm ở buổi chính'), findsOneWidget);
    expect(find.text('Lật thẻ'), findsNothing);
    expect(find.text('KHÔNG CÓ THẺ'), findsNothing);
    expect(find.byIcon(Icons.heart_broken_rounded), findsNothing);
  });

  testWidgets('a run that cannot have a card still says so', (tester) async {
    final backend = _Backend()
      ..view = {'card': null, 'reason': 'card_not_eligible'};
    await _pumpPanel(tester, backend);
    expect(find.text('KHÔNG CÓ THẺ'), findsOneWidget);
    expect(find.byIcon(Icons.heart_broken_rounded), findsOneWidget);
  });

  testWidgets('Khoe thẻ reuses the saved files and shares the chosen one', (
    tester,
  ) async {
    final backend = _Backend();
    final card = _card();
    // Byte giả: màn khoe không giải mã video, chỉ gửi đi.
    final video = Uint8List.fromList([0, 0, 0, 24, 102, 116, 121, 112]);
    // Đã khoe một lần: ba file nằm trong máy theo khoá của thẻ này.
    final store = _MemoryShareStore()
      ..saved['r1/${runCardShareKey(card, runCardData(card, owner: 'An').owner, skin: RunCardSkin.classic)}'] =
          CardShareFiles(
            front: _png,
            back: _png,
            motion: video,
            motionType: 'video/mp4',
          );
    await _pumpPanel(tester, backend, initial: card, shareStore: store);
    expect(backend.requests, isEmpty, reason: 'đã có thẻ thì không hỏi tỉ lệ');

    await _tapTip(tester, 'Khoe thẻ');
    await _settle(tester);
    expect(store.saves, 0, reason: 'có sẵn thì không tạo lại');
    for (final label in ['Mặt trước', 'Mặt sau', 'Video 3D']) {
      expect(find.text(label), findsOneWidget);
    }

    // Đổi kiểu nằm cạnh nút Khoe, không còn trên thanh tiêu đề.
    final styleButton = find.byTooltip('Kiểu thẻ');
    expect(
      find.descendant(of: find.byType(AppBar), matching: styleButton),
      findsNothing,
    );
    expect(
      tester.getCenter(styleButton).dx,
      lessThan(tester.getCenter(find.text('Khoe')).dx),
    );
    expect(
      (tester.getCenter(styleButton).dy -
              tester.getCenter(find.text('Khoe')).dy)
          .abs(),
      lessThan(4),
    );

    await tester.tap(find.text('Khoe'));
    await tester.pump();
    final first = share.shared.last;
    expect(first.fileNameOverrides, ['3i-r1-motion.mp4']);
    expect(first.files!.single.mimeType, 'video/mp4');
    expect(await first.files!.single.readAsBytes(), video);
    expect(first.text, startsWith('Dọc bờ sông Hồng · 15'));

    await tester.tap(find.text('Mặt sau'));
    await tester.pump();
    await tester.tap(find.text('Khoe'));
    await tester.pump();
    final second = share.shared.last;
    expect(second.fileNameOverrides, ['3i-r1-back.png']);
    expect(second.files!.single.mimeType, 'image/png');
  });

  testWidgets('picking a skin on the share screen shares that skin\'s files', (
    tester,
  ) async {
    final card = _card();
    final owner = runCardData(card, owner: 'An').owner;
    CardShareFiles files(int mark) => CardShareFiles(
      front: _png,
      back: _png,
      motion: Uint8List.fromList([0, 0, 0, 24, 102, 116, 121, mark]),
      motionType: 'video/mp4',
    );
    final fire = RunCardSkin.forTheme(
      RunNowAppearance.dark,
      RunNowElement.fire,
    );
    final store = _MemoryShareStore()
      ..saved['r1/${runCardShareKey(card, owner, skin: RunCardSkin.classic)}'] =
          files(1)
      ..saved['r1/${runCardShareKey(card, owner, skin: fire)}'] = files(2);
    await _pumpPanel(tester, _Backend(), initial: card, shareStore: store);

    await _tapTip(tester, 'Khoe thẻ');
    await _settle(tester);
    await tester.tap(find.byTooltip('Hỏa'));
    await _settle(tester);
    expect(store.saves, 0, reason: 'bộ màu đã có file thì không ghi lại');

    await tester.tap(find.text('Khoe'));
    await tester.pump();
    expect(
      await share.shared.last.files!.single.readAsBytes(),
      files(2).motion,
    );
  });

  testWidgets('a secret card keeps its own colours on screen and in shares', (
    tester,
  ) async {
    final card = RunCard.fromJson({..._cardJson(), 'variant': 'secret.water'});
    final owner = runCardData(card, owner: 'An').owner;
    // File khoe của thẻ Ẩn nằm theo bộ màu của hành, dù máy đang chọn bộ khác.
    final store = _MemoryShareStore()
      ..saved['r1/${runCardShareKey(card, owner, skin: RunCardSkin.secret(RunNowElement.water))}'] =
          CardShareFiles(
            front: _png,
            back: _png,
            motion: Uint8List.fromList([0, 0, 0, 24, 102, 116, 121, 112]),
            motionType: 'video/mp4',
          );
    await _pumpPanel(tester, _Backend(), initial: card, shareStore: store);
    expect(find.byTooltip('Kiểu thẻ'), findsNothing);

    await _tapTip(tester, 'Khoe thẻ');
    await _settle(tester);
    expect(store.saves, 0, reason: 'mở đúng file của bộ màu hành Thủy');
    expect(find.byTooltip('Hỏa'), findsNothing, reason: 'không có chọn bộ màu');
  });

  test('the share cache key follows what the card shows', () {
    final plain = _card();
    final drawn = _card(art: {'status': 'done', 'path': 'u/a/r1.png'});
    String key(RunCard card, String owner, [RunCardSkin? skin]) =>
        runCardShareKey(card, owner, skin: skin ?? RunCardSkin.classic);
    expect(key(plain, 'An'), key(_card(), 'An'));
    expect(key(plain, 'An'), isNot(key(drawn, 'An')));
    expect(key(plain, 'An'), isNot(key(plain, 'Bình')));
    expect(key(plain, 'An'), isNot(key(_card(tier: 'rare'), 'An')));
    final paperFire = RunCardSkin.forTheme(
      RunNowAppearance.light,
      RunNowElement.fire,
    );
    expect(key(plain, 'An'), isNot(key(plain, 'An', paperFire)));
    expect(
      key(plain, 'An', paperFire),
      isNot(
        key(
          plain,
          'An',
          RunCardSkin.forTheme(RunNowAppearance.light, RunNowElement.water),
        ),
      ),
    );
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

  testWidgets(
    'reopening the steps shows the last styles at once and refreshes them',
    (tester) async {
      final backend = _Backend();
      await _pumpPanel(tester, backend, initial: _card());
      await _openStyles(tester);
      expect(find.text('Sơn dầu'), findsOne);
      await _tapTip(tester, 'Quay lại');
      await _tapTip(tester, 'Quay lại');

      backend.stylesGate = Completer<void>();
      backend.styles = {
        ..._styles,
        'styles': [
          ...(_styles['styles']! as List),
          {
            'key': 'ink',
            'version': 1,
            'name': 'Thuỷ mặc',
            'family': 'painting',
            'swatch': ['#222222', '#f4f1ea'],
          },
        ],
      };
      await _openStyles(tester);
      expect(find.text('Sơn dầu'), findsOne, reason: 'hiện ngay bản lần trước');
      expect(find.text('Thuỷ mặc'), findsNothing);

      backend.stylesGate!.complete();
      await _settle(tester);
      expect(
        find.text('Thuỷ mặc'),
        findsOne,
        reason: 'tải ngầm xong thì cập nhật',
      );
      expect(
        backend.requests.where((r) => r == 'GET /v1/art-styles'),
        hasLength(2),
      );
    },
  );

  testWidgets('a run photo plus a style crops, uploads, then draws', (
    tester,
  ) async {
    final backend = _Backend();
    final picker = _Photos();
    await _pumpPanel(
      tester,
      backend,
      initial: _card(),
      photos: [_runPhoto],
      picker: picker,
    );
    await _openStyles(tester);

    expect(find.text('Chọn style'), findsOne);
    expect(find.text('Nhóm trống'), findsNothing);
    expect(find.text('Anime cel'), findsNothing, reason: 'khác nhóm đang mở');
    expect(
      _navEnabled(tester, 'Tiếp'),
      isFalse,
      reason: 'backend chưa bật dùng thẳng ảnh thì phải chọn phong cách',
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is StorageImage && w.path == 'artStyles/examples/oil.jpg',
      ),
      findsOne,
      reason: 'Sơn dầu có ảnh mẫu thì ô hiện ảnh đó',
    );

    await _tapText(tester, 'Sơn dầu');
    expect(find.text('Sơn dầu'), findsNWidgets(2), reason: 'tên hiện giữa nav');
    await _next(tester);
    expect(
      _navEnabled(tester, 'Vẽ'),
      isFalse,
      reason: 'có ảnh thì phải đồng ý gửi ảnh trước',
    );
    expect(find.textContaining('Google Gemini'), findsOne);

    await _consentAndSend(tester, 'Vẽ');
    expect(picker.downloads, [_runPhotoPath]);
    expect(picker.focuses, [Alignment.center]);
    expect(picker.uploads, ['r1 src.jpg image/png ${_png.length}']);
    expect(backend.artBodies, [
      {'style': 'oil', 'photoPath': _srcPath},
    ]);
    expect(find.byType(RunCardArtSteps), findsNothing);
    expect(find.text('Đang vẽ tranh nền'), findsNothing);
    expect(find.text('Vẽ lại'), findsNothing, reason: 'vừa gửi thì chưa kẹt');
  });

  Future<void> openCollected(WidgetTester tester, RunCard card) async {
    StorageImage.debugPutDownloadUrl(_runPhotoPath, 'https://x.test/p.jpg');
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runNowApiClientProvider.overrideWithValue(_Backend().client()),
          runCardsProvider.overrideWith((ref) => Stream.value(const [])),
          userProfileProvider.overrideWith((ref) => Stream.value(null)),
          activityDetailProvider.overrideWith(
            (ref, id) async =>
                ActivityDetail(summary: _run(photos: [_runPhoto])),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                final collected = CollectedRunCard(card);
                return TextButton(
                  onPressed: () =>
                      collected.open(context, collected.data('An')),
                  child: const Text('mở'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('mở'));
    await _settle(tester);
  }

  testWidgets('a card without art offers to draw and opens the draw steps', (
    tester,
  ) async {
    await openCollected(tester, _card());
    expect(find.text('Khoe thẻ'), findsOneWidget);
    expect(find.byIcon(Icons.touch_app_rounded), findsOneWidget);
    expect(find.textContaining('chạm để lật'), findsNothing);
    expect(
      tester.getCenter(find.text('Vẽ nền')).dy,
      tester.getCenter(find.text('Khoe thẻ')).dy,
    );

    await tester.tap(find.text('Vẽ nền'));
    await _settle(tester);
    await _settle(tester);

    expect(find.byType(GameCardViewer), findsNothing);
    expect(find.byType(RunCardDrawScreen), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) => w is StorageImage && w.path == _runPhotoPath,
      ),
      findsWidgets,
      reason: 'ảnh buổi chạy phải có trong bước chọn ảnh',
    );
  });

  testWidgets('a failed drawing offers to draw again from the viewer', (
    tester,
  ) async {
    await openCollected(
      tester,
      _card(art: const {'status': 'failed', 'style': 'oil', 'attempt': 1}),
    );
    expect(find.text('Vẽ lại'), findsOneWidget);
    expect(find.text('Vẽ nền'), findsNothing);
  });

  testWidgets('a drawn or drawing card has no draw button in the viewer', (
    tester,
  ) async {
    await openCollected(tester, _card(art: _done));
    expect(find.text('Vẽ nền'), findsNothing);
    expect(find.text('Vẽ lại'), findsNothing);
    await tester.pumpWidget(const SizedBox());

    await openCollected(
      tester,
      _card(art: const {'status': 'drawing', 'style': 'oil', 'attempt': 1}),
    );
    expect(find.text('Vẽ nền'), findsNothing);
    expect(find.text('Vẽ lại'), findsNothing);
  });

  testWidgets('drawing from the viewer on the result step opens the steps', (
    tester,
  ) async {
    await _pumpPanel(tester, _Backend(), initial: _card());
    await tester.tap(find.byType(AchievementCard));
    await _settle(tester);

    await tester.tap(find.text('Vẽ nền'));
    await _settle(tester);

    expect(find.byType(GameCardViewer), findsNothing);
    expect(find.byType(RunCardArtSteps), findsOneWidget);
  });

  testWidgets('art finished while the card is open appears in the viewer', (
    tester,
  ) async {
    StorageImage.debugPutDownloadUrl('u/a/r1.png', 'https://x.test/a.png');
    final backend = _Backend();
    await _pumpPanel(
      tester,
      backend,
      initial: _card(
        art: const {'status': 'drawing', 'style': 'oil', 'attempt': 1},
      ),
    );
    await tester.tap(find.byType(AchievementCard));
    await _settle(tester);
    final art = find.descendant(
      of: find.byType(GameCardViewer),
      matching: find.byWidgetPredicate(
        (w) => w is StorageImage && w.path == 'u/a/r1.png',
      ),
    );
    expect(art, findsNothing);

    backend.cards.add(
      _card(
        art: const {
          'status': 'done',
          'style': 'oil',
          'attempt': 1,
          'path': 'u/a/r1.png',
        },
      ),
    );
    await _settle(tester);

    expect(art, findsWidgets);
  });

  testWidgets('an image still downloading shows its loading widget', (
    tester,
  ) async {
    StorageImage.debugPutDownloadUrl('u/a/slow.png', 'https://x.test/s.png');
    await tester.pumpWidget(
      const MaterialApp(
        home: StorageImage(path: 'u/a/slow.png', loading: Text('chờ')),
      ),
    );
    await tester.pump();

    expect(find.text('chờ'), findsOneWidget);
  });

  testWidgets('drawing from the viewer does not replay the flip', (
    tester,
  ) async {
    await _pumpPanel(tester, _Backend());
    await tester.tap(find.text('Lật thẻ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.tap(find.byType(AchievementCard));
    await _settle(tester);
    await tester.tap(find.text('Vẽ nền'));
    await _settle(tester);

    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pump();

    expect(find.byType(CardFlipReveal), findsNothing);
  });

  testWidgets('a photo goes on the card as is when no style is chosen', (
    tester,
  ) async {
    final backend = _Backend()..styles = {..._styles, 'plain': true};
    final picker = _Photos(_png);
    await _pumpPanel(tester, backend, initial: _card(), picker: picker);
    await _tapText(tester, 'Vẽ tranh nền');
    await tester.tap(find.bySemanticsLabel('Tải ảnh'));
    await _settle(tester);
    await _next(tester);

    expect(find.text('Không style'), findsNWidgets(2), reason: 'mặc định chọn');
    await _next(tester);
    expect(find.widgetWithText(TextField, 'Mô tả thêm'), findsNothing);
    expect(find.textContaining('Gemini'), findsNothing, reason: 'không gửi đi');
    expect(_navEnabled(tester, 'Dùng ảnh này'), isFalse);

    await _consentAndSend(tester, 'Dùng ảnh này');
    expect(picker.uploads, ['r1 src.jpg image/png ${_png.length}']);
    expect(backend.artBodies, [
      {'style': 'plain', 'photoPath': _srcPath},
    ]);
  });

  testWidgets('without a photo a style is required', (tester) async {
    final backend = _Backend()..styles = {..._styles, 'plain': true};
    await _pumpPanel(tester, backend, initial: _card());
    await _openStyles(tester);

    expect(find.text('Không style'), findsNothing);
    expect(_navEnabled(tester, 'Tiếp'), isFalse);
  });

  testWidgets('dragging the card reframes the photo that gets uploaded', (
    tester,
  ) async {
    final backend = _Backend()..styles = {..._styles, 'plain': true};
    final picker = _Photos();
    await _pumpPanel(
      tester,
      backend,
      initial: _card(),
      photos: [_runPhoto],
      picker: picker,
    );
    await _openStyles(tester);

    await tester.drag(find.byType(AchievementCard), const Offset(0, -60));
    await _settle(tester);
    await _next(tester);
    await _consentAndSend(tester, 'Dùng ảnh này');

    expect(
      picker.focuses.single.y,
      greaterThan(0),
      reason: 'kéo lên xem phần dưới',
    );
    expect(picker.focuses.single.x, 0);
  });

  test('style usage counts only finished drawings from the list', () {
    RunCard drawn(String style, {String status = 'done'}) => _card(
      art: {'status': status, 'style': style, 'attempt': 1, 'path': 'x.png'},
    );
    expect(
      runCardStyleUsage([
        drawn('oil'),
        drawn('anime_cel'),
        drawn('anime_cel'),
        drawn('anime_cel', status: 'failed'),
        drawn('oil', status: 'drawing'),
        drawn('plain'),
        drawn('custom'),
        _card(),
      ]),
      {'oil': 1, 'anime_cel': 2},
    );
  });

  testWidgets('styles used most come first under Hay dùng', (tester) async {
    RunCard drawn(String style) => _card(
      art: {'status': 'done', 'style': style, 'attempt': 1, 'path': 'x.png'},
    );
    final backend = _Backend();
    await _pumpPanel(
      tester,
      backend,
      initial: _card(),
      collection: [drawn('oil'), drawn('anime_cel'), drawn('anime_cel')],
    );
    await _openStyles(tester);
    await _settle(tester);
    await _tapText(tester, 'Hay dùng');

    expect(
      tester.getCenter(find.text('Anime cel')).dx,
      lessThan(tester.getCenter(find.text('Sơn dầu')).dx),
    );
    expect(find.text('2'), findsOne, reason: 'số lần dùng ở góc ô');
  });

  testWidgets('a note goes with the draw, trimmed and capped at 200 runes', (
    tester,
  ) async {
    final backend = _Backend();
    await _pumpPanel(tester, backend, initial: _card());
    await _openStyles(tester);
    await _tapText(tester, 'Sơn dầu');
    await _next(tester);
    final note = await _noteField(tester);

    await tester.enterText(note, 'ệ' * 201);
    await tester.pump();
    expect(
      tester.widget<TextField>(note).controller!.text.runes.length,
      200,
      reason: 'cùng cách đếm rune với backend',
    );
    expect(find.text('200/200'), findsOne);

    await tester.enterText(note, '  áo đỏ, chạy cùng chú chó  ');
    await _tapTip(tester, 'Vẽ');
    expect(backend.artBodies, [
      {'style': 'oil', 'note': 'áo đỏ, chạy cùng chú chó'},
    ]);
  });

  testWidgets('an uploaded PNG goes up before the draw request', (
    tester,
  ) async {
    final backend = _Backend();
    final picker = _Photos(utf8.encode('GIF89a....'));
    await _pumpPanel(tester, backend, initial: _card(), picker: picker);
    await _tapText(tester, 'Vẽ tranh nền');

    await tester.tap(find.bySemanticsLabel('Tải ảnh'));
    await _settle(tester);
    expect(find.text('Chỉ dùng được ảnh JPEG hoặc PNG.'), findsOne);

    picker.bytes = _png;
    await tester.tap(find.bySemanticsLabel('Tải ảnh'));
    await _settle(tester);
    await _next(tester);
    await _tapText(tester, 'Anime');
    await _tapText(tester, 'Anime cel');
    await _next(tester);
    await _consentAndSend(tester, 'Vẽ');
    expect(picker.downloads, isEmpty, reason: 'ảnh đã có trên máy');
    expect(picker.uploads, ['r1 src.jpg image/png ${_png.length}']);
    expect(backend.artBodies, [
      {'style': 'anime_cel', 'photoPath': _srcPath},
    ]);
  });

  testWidgets('a custom style uploads the style image and draws from it', (
    tester,
  ) async {
    final backend = _Backend()..styles = {..._styles, 'custom': true};
    final picker = _Photos(_png);
    await _pumpPanel(tester, backend, initial: _card(), picker: picker);
    await _openStyles(tester);
    expect(_navEnabled(tester, 'Tiếp'), isFalse);

    await _tapText(tester, 'Style từ Ảnh');
    await _next(tester);
    expect(
      _navEnabled(tester, 'Vẽ'),
      isFalse,
      reason: 'ảnh mẫu cũng gửi cho Gemini nên phải đồng ý trước',
    );
    await _consentAndSend(tester, 'Vẽ');
    expect(picker.uploads, ['r1 style.jpg image/png ${_png.length}']);
    // Backend tự lấy style.jpg của thẻ, nên lệnh vẽ chỉ mang tên phong cách.
    expect(backend.artBodies, [
      {'style': 'custom'},
    ]);
  });

  testWidgets('a refused draw stays on the confirm step with the reason', (
    tester,
  ) async {
    final backend = _Backend()..artError = 'art_fixed';
    await _pumpPanel(tester, backend, initial: _card());
    await _openStyles(tester);
    await _tapText(tester, 'Sơn dầu');
    await _next(tester);
    await _tapTip(tester, 'Vẽ');

    expect(backend.artBodies, [
      {'style': 'oil'},
    ]);
    expect(find.text('Thẻ này đã có tranh, không vẽ lại được.'), findsOne);
    expect(find.byTooltip('Vẽ'), findsOne);
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
          'note': 'áo đỏ',
        },
      ),
    );
    expect(
      find.text('Hôm nay 3i đã dùng hết hạn mức vẽ tranh. Mai thử lại nhé.'),
      findsOne,
    );
    await _tapText(tester, 'Vẽ lại');
    await _next(tester);
    expect(find.text('Anime cel'), findsNWidgets(2));
    await _next(tester);
    final note = await _noteField(tester);
    expect(tester.widget<TextField>(note).controller!.text, 'áo đỏ');
  });

  testWidgets('an unreadable photo is dropped when the draw reopens', (
    tester,
  ) async {
    final backend = _Backend()..styles = {..._styles, 'plain': true};
    await _pumpPanel(
      tester,
      backend,
      initial: _card(
        art: {
          'status': 'failed',
          'style': 'plain',
          'attempt': 1,
          'reason': 'photo_invalid',
          'photoPath': _srcPath,
        },
      ),
    );
    expect(find.text('Ảnh này không dùng được. Chọn ảnh khác.'), findsOne);
    await _openRedraw(tester);
    expect(find.text('Không style'), findsNothing);
    expect(_navEnabled(tester, 'Tiếp'), isFalse);
  });

  testWidgets('a lost style image asks for a new one before redrawing', (
    tester,
  ) async {
    final backend = _Backend()..styles = {..._styles, 'custom': true};
    final picker = _Photos(_png);
    await _pumpPanel(
      tester,
      backend,
      picker: picker,
      initial: _card(
        art: {
          'status': 'failed',
          'style': 'custom',
          'attempt': 1,
          'reason': 'style_photo_missing',
        },
      ),
    );
    expect(
      find.text('Không tìm thấy ảnh mẫu. Tải lại ảnh mẫu rồi vẽ.'),
      findsOne,
    );
    await _openRedraw(tester);
    expect(_navEnabled(tester, 'Tiếp'), isFalse);

    await _tapText(tester, 'Style từ Ảnh');
    await _next(tester);
    await _consentAndSend(tester, 'Vẽ');
    expect(picker.uploads, ['r1 style.jpg image/png ${_png.length}']);
    expect(backend.artBodies, [
      {'style': 'custom'},
    ]);
  });

  testWidgets('a failed custom draw redraws from the kept style image', (
    tester,
  ) async {
    final backend = _Backend()..styles = {..._styles, 'custom': true};
    final picker = _Photos(_png);
    await _pumpPanel(
      tester,
      backend,
      picker: picker,
      initial: _card(
        art: {
          'status': 'failed',
          'style': 'custom',
          'attempt': 1,
          'reason': 'budget',
        },
      ),
    );
    await _openRedraw(tester);
    await _next(tester);
    await _consentAndSend(tester, 'Vẽ');
    expect(picker.uploads, isEmpty, reason: 'style.jpg cũ vẫn còn');
    expect(backend.artBodies, [
      {'style': 'custom'},
    ]);
  });

  group('cropToCard', () {
    // Ảnh 40x20, nửa trái đỏ, nửa phải xanh.
    Future<Uint8List> halves() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder)
        ..drawRect(
          const Rect.fromLTWH(0, 0, 20, 20),
          Paint()..color = const Color(0xFFFF0000),
        )
        ..drawRect(
          const Rect.fromLTWH(20, 0, 20, 20),
          Paint()..color = const Color(0xFF0000FF),
        );
      final image = await recorder.endRecording().toImage(40, 20);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    }

    Future<ui.Image> decode(Uint8List bytes) async =>
        (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image;

    Future<List<int>> centerRgb(ui.Image image) async {
      final data = (await image.toByteData())!;
      final i = (image.height ~/ 2 * image.width + image.width ~/ 2) * 4;
      return [data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2)];
    }

    testWidgets('keeps the part of a wide photo the user framed', (
      tester,
    ) async {
      await tester.runAsync(() async {
        const photos = RunCardPhotos();
        final source = await halves();
        final right = await decode(
          await photos.cropToCard(source, Alignment.centerRight),
        );
        final left = await decode(
          await photos.cropToCard(source, Alignment.centerLeft),
        );
        // Cao 20, tỉ lệ 5:7 nên ngang 14,3, làm tròn 14; cao 14 / (5/7) = 19,6.
        expect(right.width, 14);
        expect(right.height, 20);
        expect(await centerRgb(right), [0, 0, 255]);
        expect(await centerRgb(left), [255, 0, 0]);
      });
    });

    testWidgets('shrinks a big photo to 1080 wide', (tester) async {
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(const Color(0xFF00FF00), BlendMode.src);
        final big = await recorder.endRecording().toImage(2000, 2000);
        final data = await big.toByteData(format: ui.ImageByteFormat.png);
        final out = await decode(
          await const RunCardPhotos().cropToCard(
            data!.buffer.asUint8List(),
            Alignment.center,
          ),
        );
        // 1080 / (5/7) = 1512.
        expect(out.width, 1080);
        expect(out.height, 1512);
      });
    });
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
          'note': 'áo đỏ',
          'requestedAt': DateTime.now()
              .toUtc()
              .subtract(const Duration(minutes: 10))
              .toIso8601String(),
        },
      ),
    );
    expect(find.text('Lâu quá chưa xong'), findsOne);
    await _tapText(tester, 'Vẽ lại');
    // Thiếu note thì backend coi là lựa chọn khác và báo đang vẽ.
    expect(backend.artBodies, [
      {'style': 'oil', 'photoPath': _runPhotoPath, 'note': 'áo đỏ'},
    ]);
  });
}
