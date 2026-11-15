import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/training_plan/plan_share.dart';
import 'package:myrun/src/training_plan/training_plan_models.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

class _FakeShare extends SharePlatform {
  final shared = <ShareParams>[];

  @override
  Future<ShareResult> share(ShareParams params) async {
    shared.add(params);
    return const ShareResult('ok', ShareResultStatus.success);
  }
}

/// Font thật của app, vì font giả của test thấp hơn nên không lộ chỗ tràn.
Future<void> _loadFonts() async {
  const fonts = {
    'Exo 2': ['exo2/Exo2-Variable.ttf'],
    'Barlow Condensed': [
      'barlow_condensed/BarlowCondensed-SemiBold.ttf',
      'barlow_condensed/BarlowCondensed-Bold.ttf',
      'barlow_condensed/BarlowCondensed-ExtraBold.ttf',
    ],
    'VT323': ['vt323/VT323-Regular.ttf'],
  };
  for (final MapEntry(key: family, value: files) in fonts.entries) {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = await File('assets/fonts/$file').readAsBytes();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}

/// Giáo án hai tuần, 4 buổi chạy. "owner" đã xong buổi đầu, "ban" theo nhưng
/// chưa xong buổi nào.
TrainingPlan _plan({
  String visibility = 'club',
  String? uid = 'owner',
  String goal = 'Chạy 10km dưới 60 phút',
}) {
  Map<String, dynamic> day(int week, String type, {double? km}) => {
    'week': week,
    'label': '',
    'type': type,
    'title': type,
    'distanceKm': ?km,
  };
  return TrainingPlan.fromMap('p1', {
    'goal': goal,
    'goalDistanceKm': 10,
    'weeks': 2,
    'startDate': '2026-11-02',
    'targetDate': '2026-11-15',
    'summary': '',
    'ownerUid': 'owner',
    'visibility': visibility,
    'participants': {
      'owner': {
        'doneIndices': [0],
      },
      'ban': {'doneIndices': <int>[]},
    },
    'days': [
      day(1, 'easy', km: 5),
      day(1, 'rest'),
      day(1, 'tempo', km: 6),
      for (var i = 0; i < 4; i++) day(1, 'rest'),
      day(2, 'rest'),
      day(2, 'long', km: 12),
      for (var i = 0; i < 4; i++) day(2, 'rest'),
      day(2, 'race', km: 10),
    ],
  }, currentUid: uid);
}

void main() {
  test('caption giáo án nhóm có số buổi của người khoe và link', () {
    expect(
      planShareCaption(_plan(), 'owner'),
      'Chạy 10km dưới 60 phút: 1/4 buổi\nhttps://threei.run/coach/p1',
    );
  });

  test('người theo giáo án khoe số buổi của chính họ', () {
    expect(
      planShareCaption(_plan(uid: 'ban'), 'ban'),
      'Chạy 10km dưới 60 phút: 0/4 buổi\nhttps://threei.run/coach/p1',
    );
  });

  test('người chưa tham gia khoe thì caption chỉ có mục tiêu và link', () {
    expect(
      planShareCaption(_plan(uid: 'khach'), 'khach'),
      'Chạy 10km dưới 60 phút\nhttps://threei.run/coach/p1',
    );
  });

  test('giáo án riêng tư không kèm link', () {
    expect(
      planShareCaption(_plan(visibility: 'private'), 'owner'),
      'Chạy 10km dưới 60 phút: 1/4 buổi',
    );
  });

  test('buổi tiếp theo là buổi chưa xong gần nhất từ hôm nay', () {
    // Buổi 02/11 đã xong; 04/11 tempo; 10/11 chạy dài; 15/11 về đích.
    final plan = _plan();
    expect(
      plan.nextSession(DateTime(2026, 11, 3))!.date,
      DateTime(2026, 11, 4),
    );
    expect(
      plan.nextSession(DateTime(2026, 11, 4))!.date,
      DateTime(2026, 11, 4),
    );
    // Qua ngày 04/11 mà chưa chạy thì buổi đó không còn là buổi sắp tới.
    expect(
      plan.nextSession(DateTime(2026, 11, 5))!.date,
      DateTime(2026, 11, 10),
    );
    expect(plan.nextSession(DateTime(2026, 11, 16)), isNull);
  });

  testWidgets('Ảnh giáo án không tràn khi tên hai dòng và có buổi tiếp theo', (
    tester,
  ) async {
    await tester.runAsync(_loadFonts);
    for (final style in RunNowStyle.values) {
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(style),
          theme: buildRunNowTheme(RunNowElement.fire, style: style),
          home: Material(
            child: Center(
              child: TrainingPlanPoster(
                plan: _plan(goal: 'Half Marathon trong 6 tuần'),
                today: DateTime(2026, 11, 4),
              ),
            ),
          ),
        ),
      );
      expect(find.text('HÔM NAY · GIỮ NHỊP'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: style.name);
    }
  });

  testWidgets('Khoe giáo án gửi một ảnh PNG khổ Story kèm caption', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    final share = _FakeShare();
    SharePlatform.instance = share;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildRunNowDarkTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showPlanShare(
                  context,
                  plan: _plan(),
                  currentUid: 'owner',
                  today: DateTime(2026, 11, 4),
                ),
                child: const Text('mở'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('mở'));
    await tester.pumpAndSettle();
    expect(find.byType(TrainingPlanPoster), findsOneWidget);
    // 1 trên 4 buổi.
    expect(find.text('25'), findsOneWidget);
    expect(find.text('1/4 buổi'), findsOneWidget);
    expect(find.text('TUẦN 1/2'), findsOneWidget);
    // 04/11 là ngày có buổi tempo 6 km chưa xong.
    expect(find.text('HÔM NAY · GIỮ NHỊP'), findsOneWidget);
    expect(find.text('6 km'), findsOneWidget);
    expect(find.text('10 km · 15/11 · còn 11 ngày'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Khoe giáo án'));
      for (var i = 0; i < 40 && share.shared.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();

    final params = share.shared.single;
    expect(
      params.text,
      'Chạy 10km dưới 60 phút: 1/4 buổi\nhttps://threei.run/coach/p1',
    );
    final file = params.files!.single;
    expect(file.mimeType, 'image/png');
    final bytes = await tester.runAsync(file.readAsBytes);
    final image = await tester.runAsync(() => decodeImageFromList(bytes!));
    expect((image!.width, image.height), (1080, 1920));
    expect(find.text('Khoe giáo án'), findsNothing);
  });
}
