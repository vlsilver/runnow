import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/achievements/card_share.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/theme.dart';

final _card = RunCard(
  id: 'r1',
  tier: GameCardTier.rare,
  km: 6.4,
  odds: const [],
  snapshot: RunCardSnapshot(
    name: 'Một vòng hồ Tây',
    sportType: 'Run',
    distanceMeters: 6400,
    movingTimeSeconds: 2150,
    elapsedTimeSeconds: 2200,
    startedAt: DateTime(2026, 10, 25, 6, 5),
    route: const [],
    splits: const [],
  ),
);

CardShareFiles _files(int mark) => CardShareFiles(
  front: Uint8List.fromList([mark, 1]),
  back: Uint8List.fromList([mark, 2]),
  motion: Uint8List.fromList([mark, 3]),
  motionType: 'video/mp4',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;

  setUp(() {
    support = Directory.systemTemp.createTempSync('run_card_share');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => support.path,
        );
  });

  tearDown(() => support.deleteSync(recursive: true));

  final dark = RunCardSkin.forTheme(RunNowAppearance.dark, RunNowElement.fire);
  final light = RunCardSkin.forTheme(
    RunNowAppearance.light,
    RunNowElement.water,
  );

  // Khoá tính tay bằng FNV-1a 32 bit trên chuỗi 'rare||An|8' (bậc, tranh
  // nền, chủ, phiên bản). Đổi số này là file khoe đã lưu của mọi người phải
  // ghi lại.
  test('a run card keeps the cache key its saved files were made with', () {
    expect(runCardShareKey(_card, 'An', skin: dark), startsWith('8617428a.'));
  });

  test('each skin keeps its own files across app restarts', () async {
    final darkKey = runCardShareKey(_card, 'An', skin: dark);
    final lightKey = runCardShareKey(_card, 'An', skin: light);
    final store = CardShareStore();
    await store.save('r1', darkKey, _files(1));
    await store.save('r1', lightKey, _files(2));

    // Mở lại app: bộ nhớ trống, chỉ còn file trên máy.
    final reopened = CardShareStore();
    expect((await reopened.load('r1', darkKey))?.motion, [1, 3]);
    expect((await reopened.load('r1', lightKey))?.motion, [2, 3]);
  });

  test('files of what the card no longer shows are removed', () async {
    final before = runCardShareKey(_card, 'An', skin: dark);
    final renamed = runCardShareKey(_card, 'An Nguyễn', skin: light);
    final store = CardShareStore();
    await store.save('r1', before, _files(1));
    await store.save('r1', renamed, _files(2));

    final reopened = CardShareStore();
    expect(await reopened.load('r1', before), isNull);
    expect((await reopened.load('r1', renamed))?.motion, [2, 3]);
    expect(
      Directory('${support.path}/run_card_share/r1').listSync(),
      hasLength(1),
    );
  });
}
