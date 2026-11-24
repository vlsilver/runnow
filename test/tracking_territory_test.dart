import 'dart:async';
import 'dart:io';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/repository.dart';
import 'package:myrun/src/rooms/run_room_repository.dart';
import 'package:myrun/src/screens/tracking_screen.dart';
import 'package:myrun/src/territory/territory_repository.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/tracking_location_provider.dart';
import 'package:myrun/src/tracking_session.dart';

/// GPS giả: lúc dò thì trả đủ mẫu tốt cho màn khoá vị trí, lúc chạy thì trả
/// điểm do test đẩy vào.
class _FakeLocation implements TrackingLocationProvider {
  final running = StreamController<TrackingLocationSample>.broadcast();

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.always;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.always;

  @override
  Future<void> openAppSettings() async {}

  @override
  Future<void> openLocationSettings() async {}

  @override
  Stream<TrackingLocationSample> warmupSamples() => Stream.fromIterable([
    for (var i = 0; i < 10; i++)
      TrackingLocationSample(
        latitude: 10.772,
        longitude: 106.698,
        timestamp: DateTime.now(),
        accuracyMeters: 5,
        speedMetersPerSecond: 0,
      ),
  ]);

  @override
  Stream<TrackingLocationSample> runningSamples() => running.stream;
}

/// Buổi live không đi đâu: hồ sơ trong test là private nên màn không bật live,
/// chỉ còn lần báo kết thúc.
class _FakeLive implements LiveTrackingRepository {
  @override
  Stream<List<LiveTrackingSession>> watchClubLiveSessions() =>
      Stream.value(const []);

  @override
  Stream<LiveTrackingSession?> watchSession(String sessionId) =>
      Stream.value(null);

  @override
  Stream<List<LiveTrackingSession>> watchContractLiveSessions(
    String contractId,
  ) => Stream.value(const []);

  @override
  Future<void> publishSnapshot({
    required TrackingSessionSnapshot snapshot,
    required LiveTrackingStatus status,
    required List<RoutePoint> routePreview,
    String? contractId,
    String? roomId,
    bool roomOnly = false,
  }) async {}

  @override
  Future<void> publishPhoto({
    required String sessionId,
    required ActivityPhoto photo,
  }) async {}

  @override
  Future<void> finishSession(
    String sessionId,
    LiveTrackingStatus status,
  ) async {}
}

/// Ghi lại id buổi màn chạy vừa lưu.
class _SavingRepository extends DemoActivityRepository {
  final saved = <String>[];
  // finalize của bản demo gọi lại saveTrackedActivity nên một buổi có thể ghi hai lần.

  @override
  Future<TrackedActivitySaveResult> saveTrackedActivity(
    ActivityDetail detail, {
    Map<String, dynamic>? trackingDebug,
  }) {
    saved.add(detail.summary.id);
    return super.saveTrackedActivity(detail, trackingDebug: trackingDebug);
  }

  @override
  Future<TrackedActivitySaveResult> finalizeTrackedActivity(
    ActivityDetail detail,
  ) {
    saved.add(detail.summary.id);
    return super.finalizeTrackedActivity(detail);
  }
}

void main() {
  testWidgets('chạy xong, lưu xong thì màn kết thúc hiện +N ô khi backend '
      'ghi kết quả của đúng buổi vừa lưu', (tester) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final messenger = tester.binding.defaultBinaryMessenger;
    // Nháp buổi chạy ghi file vào thư mục app.
    final dir = Directory.systemTemp.createTempSync('tracking_territory');
    addTearDown(() => dir.deleteSync(recursive: true));
    const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(pathProvider, (_) async => dir.path);
    addTearDown(() => messenger.setMockMethodCallHandler(pathProvider, null));
    // Màn giữ sáng máy lúc chạy.
    const wakelock =
        'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle';
    messenger.setMockMessageHandler(
      wakelock,
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[]),
    );
    addTearDown(() => messenger.setMockMessageHandler(wakelock, null));

    final firestore = FakeFirebaseFirestore();
    final location = _FakeLocation();
    final activities = _SavingRepository();
    addTearDown(location.running.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackingLocationProvider.overrideWithValue(location),
          activityRepositoryProvider.overrideWithValue(activities),
          liveTrackingRepositoryProvider.overrideWithValue(_FakeLive()),
          clubLiveSessionsProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          publicRunRoomsProvider.overrideWith((ref) => Stream.value(const [])),
          myRunRoomsProvider.overrideWith((ref) => Stream.value(const [])),
          trackingConfigProvider.overrideWith(
            (ref) => Stream.value(const TrackingConfig()),
          ),
          firebaseUserProvider.overrideWith(
            (ref) => Stream.value(MockUser(uid: 'an')),
          ),
          userProfileProvider.overrideWith((ref) => Stream.value(null)),
          membersProvider.overrideWith((ref) => Stream.value(const [])),
          territoryRepositoryProvider.overrideWithValue(
            TerritoryRepository(firestore),
          ),
          territoryEnabledProvider.overrideWith((ref) => Stream.value(true)),
          leaderboardDocsProvider.overrideWith((ref) async => const []),
        ],
        child: MaterialApp(
          theme: buildRunNowTheme(RunNowElement.water),
          home: const TrackingScreen(),
        ),
      ),
    );
    await tester.pump();

    // Nháp ghi file thật, nên bấm và chờ trong runAsync tới khi thấy nút sau.
    Future<void> tapUntil(String label, Finder next) =>
        tester.runAsync(() async {
          await tester.tap(find.text(label));
          for (var i = 0; i < 100 && next.evaluate().isEmpty; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            await tester.pump();
          }
        });

    await tapUntil('QUÉT GPS', find.text('BẮT ĐẦU CHẠY'));
    await tapUntil('BẮT ĐẦU CHẠY', find.text('TẠM DỪNG'));
    await tapUntil('TẠM DỪNG', find.text('KẾT THÚC'));
    // Chưa đủ 500 m nên màn hỏi lại trước khi lưu.
    await tapUntil('KẾT THÚC', find.text('Dừng và lưu'));
    // Chờ tới dòng báo đã lưu: lúc đó màn mới biết id buổi.
    await tapUntil('Dừng và lưu', find.textContaining('Đã lưu'));
    expect(find.text('QUÉT GPS CHO BUỔI MỚI'), findsOneWidget);
    expect(find.byType(ActionChip), findsNothing);

    final id = activities.saved.toSet().single;
    final results = firestore.collection('territoryResults');
    // Kết quả của buổi khác không làm hiện chip.
    await results.doc('an_khac').set({'uid': 'an', 'gained': 9, 'taken': {}});
    await tester.pump();
    expect(find.byType(ActionChip), findsNothing);

    // Backend ghi vài giây sau khi lưu: chip hiện lúc đó, không cần mở lại màn.
    await results.doc('an_$id').set({
      'uid': 'an',
      'activityId': id,
      'gained': 4,
      'taken': {},
      'chunk': '6523_3849',
    });
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(find.text('+4 ô'), findsOneWidget);
    // Hết giờ dòng báo đã lưu để test không còn timer treo.
    await tester.pump(const Duration(seconds: 5));
  });
}
