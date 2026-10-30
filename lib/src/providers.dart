import 'dart:async';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:myrun/src/auth.dart';
import 'package:myrun/src/avatar_repository.dart';
import 'package:myrun/src/club_ranking.dart';
import 'package:myrun/src/garmin_controller.dart';
import 'package:myrun/src/health_sync.dart';
import 'package:myrun/src/journal_controller.dart';
import 'package:myrun/src/journey/journey_models.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/period_keys.dart';
import 'package:myrun/src/profile_stats.dart';
import 'package:myrun/src/repository.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/run_contracts/run_contract_controller.dart';
import 'package:myrun/src/run_contracts/run_contract_analytics.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/run_contract_repository.dart';
import 'package:myrun/src/tracking_session.dart';
import 'package:myrun/src/sync.dart';
import 'package:myrun/src/tracking_draft_store.dart';
import 'package:myrun/src/tracking_location_provider.dart';
import 'package:myrun/src/tracking_photo_capture.dart';
import 'package:myrun/src/tracking_photo_repository.dart';
import 'package:myrun/src/theme_controller.dart';

final runNowApiClientProvider = Provider<RunNowApiClient>((ref) {
  final client = RunNowApiClient.firebase(FirebaseAuth.instance);
  ref.onDispose(client.close);
  return client;
});

final activityRepositoryProvider = Provider<ActivityRepository>((ref) {
  return FirestoreStravaActivityRepository(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
    ref.watch(runNowApiClientProvider),
  );
});

final feedRepositoryProvider = Provider<FeedRepository>((ref) {
  return FirestoreFeedRepository(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
  );
});

final memberRepositoryProvider = Provider<MemberRepository>((ref) {
  return FirestoreMemberRepository(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
    ref.watch(runNowApiClientProvider),
  );
});

final trainingGoalRepositoryProvider = Provider<TrainingGoalRepository>((ref) {
  return FirestoreTrainingGoalRepository(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
  );
});

final liveTrackingRepositoryProvider = Provider<LiveTrackingRepository>((ref) {
  return FirestoreLiveTrackingRepository(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
  );
});

final runContractRepositoryProvider = Provider<RunContractRepository>((ref) {
  return FirestoreRunContractRepository(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
  );
});

final runContractAnalyticsProvider = Provider<RunContractAnalytics>((ref) {
  return RunContractAnalytics(FirebaseAnalytics.instance);
});

/// Bộ môn và kỳ đang xem ở màn "Câu lạc bộ".
final clubRankingSportProvider = StateProvider<ClubRankingSport>(
  (ref) => ClubRankingSport.run,
);
final clubRankingRangeProvider = StateProvider<ClubRankingRange>(
  (ref) => ClubRankingRange.currentWeek,
);

final trackingDraftStoreProvider = Provider<TrackingDraftStore>(
  (ref) => const TrackingDraftStore(),
);

final trackingLocationProvider = Provider<TrackingLocationProvider>(
  (ref) => const GeolocatorTrackingLocationProvider(),
);

final trackingPhotoCaptureProvider = Provider<TrackingPhotoCapture>(
  (ref) => const TrackingPhotoCapture(),
);

final trackingPhotoRepositoryProvider = Provider<TrackingPhotoRepository>(
  (ref) =>
      TrackingPhotoRepository(FirebaseAuth.instance, FirebaseStorage.instance),
);

final avatarRepositoryProvider = Provider<AvatarRepository>(
  (ref) => AvatarRepository(FirebaseAuth.instance, FirebaseStorage.instance),
);

final firebaseUserProvider = StreamProvider<User?>(
  (ref) => FirebaseAuth.instance.authStateChanges(),
);

final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  ref.watch(firebaseUserProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(null);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .snapshots()
      .map((snapshot) {
        final data = snapshot.data();
        if (data == null) return null;
        final lastSyncedAt = data['lastSyncedAt'];
        return UserProfile.fromMap({
          ...data,
          if (lastSyncedAt is Timestamp) 'lastSyncedAt': lastSyncedAt.toDate(),
        });
      });
});

final stravaAuthProvider = ChangeNotifierProvider<StravaAuthController>(
  (ref) => StravaAuthController(
    FirebaseAuth.instance,
    ref.watch(runNowApiClientProvider),
  ),
);

final stravaConnectionProvider = Provider<bool>((ref) {
  return ref.watch(stravaAuthProvider).connected;
});

final garminAuthProvider = ChangeNotifierProvider<GarminController>(
  (ref) => GarminController(
    FirebaseAuth.instance,
    ref.watch(runNowApiClientProvider),
  ),
);

/// Đồng bộ Apple Health (iOS). Quản trạng thái kết nối + đồng bộ workout.
final healthSyncProvider = ChangeNotifierProvider<HealthSyncController>(
  (ref) => HealthSyncController(ref.watch(runNowApiClientProvider)),
);

final stravaConnectionLoadingProvider = Provider<bool>((ref) {
  return ref.watch(stravaAuthProvider).statusLoading;
});

/// Cấu hình tích hợp đọc từ appConfig/integrations: cap Strava (admin đặt trên
/// console) + số user đang kết nối (backend đếm). Dùng để ẩn nút connect khi
/// đủ chỗ (app chưa được Strava review, tối đa ~10 athlete).
class IntegrationConfig {
  const IntegrationConfig({this.stravaMax = 10, this.stravaCount = 0});
  final int stravaMax;
  final int stravaCount;

  /// Đã đủ chỗ — không nhận kết nối Strava mới.
  bool get stravaFull => stravaMax > 0 && stravaCount >= stravaMax;
}

final integrationConfigProvider = StreamProvider<IntegrationConfig>((ref) {
  return FirebaseFirestore.instance
      .collection('appConfig')
      .doc('integrations')
      .snapshots()
      .map((snap) {
        final d = snap.data();
        return IntegrationConfig(
          stravaMax: (d?['stravaMaxConnections'] as num?)?.toInt() ?? 10,
          stravaCount: (d?['stravaConnectedCount'] as num?)?.toInt() ?? 0,
        );
      });
});

/// Cấu hình GPS tracking đọc từ **Firebase Remote Config**. ĐIỀU KIỆN theo
/// platform (Android/iOS qua `device.os`) xử lý ở SERVER RC → app chỉ getDouble,
/// không tự rẽ nhánh. Mặc định (lần đầu/offline/chưa fetch) lấy từ setDefaults ở
/// main() theo platform (Android giãn mẫu 15s, iOS 0). Cập nhật **REALTIME** khi
/// admin đổi trên console (onConfigUpdated) — không cần mở lại app.
final trackingConfigProvider = StreamProvider<TrackingConfig>((ref) async* {
  final rc = FirebaseRemoteConfig.instance;
  final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  // Lấy giá trị RC; nếu chưa có (valueStatic — RC init lỗi/chưa fetch) → fallback
  // cứng để KHÔNG bao giờ ra 0 vô lý (vd maxAccuracy=0 sẽ chặn sạch điểm GPS).
  double cfg(String key, double fallback) {
    try {
      final v = rc.getValue(key);
      return v.source == ValueSource.valueStatic ? fallback : v.asDouble();
    } catch (_) {
      return fallback;
    }
  }

  TrackingConfig read() => TrackingConfig(
    maxAccuracyMeters: cfg('tracking_max_accuracy_meters', 25),
    maxRunningSpeedMetersPerSecond: cfg('tracking_max_running_speed_mps', 10),
    minSegmentDistanceMeters: cfg('tracking_min_segment_distance_meters', 2),
    minSampleIntervalSeconds: cfg(
      'tracking_min_sample_interval_seconds',
      isAndroid ? 15 : 0,
    ),
  );
  yield read();
  try {
    // Realtime RC: admin đổi giá trị trên console → tự áp ngay (không cần build/
    // mở lại app). Web / môi trường không hỗ trợ → catch, giữ giá trị đã có.
    await for (final _ in rc.onConfigUpdated) {
      await rc.activate();
      yield read();
    }
  } catch (_) {}
});

/// Cờ HIỆN/ẨN Strava ở Settings — Remote Config `strava_enabled`. Tạm ẩn khi app
/// Strava đang Inactive (không kết nối được); đặt true trên console khi xong việc
/// với Strava để hiện lại (áp realtime). Mặc định/khi chưa fetch = false (ẩn).
final stravaEnabledProvider = StreamProvider<bool>((ref) async* {
  final rc = FirebaseRemoteConfig.instance;
  bool read() {
    try {
      final v = rc.getValue('strava_enabled');
      return v.source == ValueSource.valueStatic ? false : v.asBool();
    } catch (_) {
      return false;
    }
  }

  yield read();
  try {
    await for (final _ in rc.onConfigUpdated) {
      await rc.activate();
      yield read();
    }
  } catch (_) {}
});

/// Cờ HIỆN/ẨN Garmin ở Cài đặt, Remote Config `garmin_enabled`. Bật khi backend
/// đã có key Garmin và endpoint push đã khai trên portal Garmin. Mặc định và
/// khi chưa fetch là false (ẩn).
final garminEnabledProvider = StreamProvider<bool>((ref) async* {
  final rc = FirebaseRemoteConfig.instance;
  bool read() {
    try {
      final v = rc.getValue('garmin_enabled');
      return v.source == ValueSource.valueStatic ? false : v.asBool();
    } catch (_) {
      return false;
    }
  }

  yield read();
  try {
    await for (final _ in rc.onConfigUpdated) {
      await rc.activate();
      yield read();
    }
  } catch (_) {}
});

final authControllerProvider = ChangeNotifierProvider<AuthController>(
  (ref) => AuthController(FirebaseAuth.instance, FirebaseFirestore.instance),
);

final themeControllerProvider = ChangeNotifierProvider<ThemeController>(
  (ref) => ThemeController(),
);

/// Dashboard cần đủ dữ liệu gần đây để tính tuần/tháng/kỷ luật/kỷ lục nhanh,
/// nhưng không nên stream toàn bộ lịch sử Strava vô hạn mỗi lần Firestore đổi.
const _dashboardActivityLimit = 500;

final activitiesProvider = StreamProvider<List<ActivitySummary>>((ref) {
  final uid = ref.watch(firebaseUserProvider).value?.uid;
  if (uid == null) return Stream.value(const []);
  return ref
      .watch(activityRepositoryProvider)
      .watchActivities(limit: _dashboardActivityLimit);
});

final activityDetailProvider = FutureProvider.family<ActivityDetail, String>((
  ref,
  activityId,
) {
  return ref.watch(activityRepositoryProvider).getDetail(activityId);
});

final syncControllerProvider = ChangeNotifierProvider<SyncController>(
  (ref) => SyncController(ref.watch(activityRepositoryProvider)),
);

/// Không autoDispose — cache trang Nhật ký sống suốt phiên app, xem
/// `JournalController` để biết lý do (tránh phải load lại ~2s mỗi lần quay
/// lại màn Nhật ký).
final journalControllerProvider = ChangeNotifierProvider<JournalController>(
  (ref) => JournalController(ref.watch(activityRepositoryProvider)),
);

final runContractControllerProvider = Provider<RunContractController>((ref) {
  return RunContractController(
    ref.watch(runContractRepositoryProvider),
    ref.watch(activityRepositoryProvider),
  );
});

/// Các kèo đang chạy mà user tham gia (tạo hoặc join), tối đa
/// [maxActiveRunContracts].
final myActiveContractsProvider = StreamProvider<List<RunContract>>((ref) {
  final uid = ref.watch(firebaseUserProvider).value?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(runContractRepositoryProvider).watchMyActiveContracts();
});

final runContractProvider = StreamProvider.family<RunContract?, String>((
  ref,
  contractId,
) {
  final uid = ref.watch(firebaseUserProvider).value?.uid;
  if (uid == null) return Stream.value(null);
  return ref.watch(runContractRepositoryProvider).watchContract(contractId);
});

/// Tuyến ĐẦY ĐỦ (polyline) của kèo "Theo tuyến" — đọc lazy từ
/// `runContractRoutes/{id}` khi màn chi tiết cần vẽ bản đồ. Trả `null` nếu kèo
/// không tách tuyến (kèo cũ giữ points inline → dùng thẳng `contract.route`).
final contractRouteProvider =
    FutureProvider.autoDispose.family<RunContractRoute?, String>((
      ref,
      contractId,
    ) {
      final uid = ref.watch(firebaseUserProvider).value?.uid;
      if (uid == null) return Future.value(null);
      return ref
          .watch(runContractRepositoryProvider)
          .fetchContractRoute(contractId);
    });

final feedPostsProvider = StreamProvider<List<FeedPost>>(
  (ref) => ref.watch(feedRepositoryProvider).watchPosts(),
);

final membersProvider = StreamProvider<List<MemberProfile>>(
  (ref) => ref.watch(memberRepositoryProvider).watchMembers(),
);

/// Parse 1 doc stepDays → StepDay (kèm chi tiết theo giờ nếu đã lưu). Dùng chung
/// cho nhật ký của mình lẫn của member.
StepDay _stepDayFromDoc(Map<String, dynamic> m, String id) => StepDay(
  date: m['date'] as String? ?? id,
  steps: (m['steps'] as num?)?.toInt() ?? 0,
  distanceMeters: (m['distanceMeters'] as num?)?.toDouble() ?? 0,
  hourlySteps: (m['hourlySteps'] as List?)
      ?.map((e) => (e as num).toInt())
      .toList(),
  hourlyDistance: (m['hourlyDistance'] as List?)
      ?.map((e) => (e as num).toDouble())
      .toList(),
);

/// Số bước theo NGÀY của CHÍNH MÌNH (mới → cũ) để hiện list ở Nhật ký.
final myStepDaysProvider = StreamProvider<List<StepDay>>((ref) {
  ref.watch(firebaseUserProvider);
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value(const <StepDay>[]);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('stepDays')
      .orderBy('date', descending: true)
      .limit(60)
      .snapshots()
      .map(
        (snap) => snap.docs
            .map(
              (d) => _stepDayFromDoc(d.data(), d.id),
            )
            .toList(),
      );
});

/// Số bước theo NGÀY của MỘT MEMBER khác (public) — để hiện thẻ bước trong nhật
/// ký của họ khi mình bấm xem. Rules cho đọc stepDays nếu profile public.
final memberStepDaysProvider = StreamProvider.autoDispose
    .family<List<StepDay>, String>((ref, uid) {
      return FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('stepDays')
          .orderBy('date', descending: true)
          .limit(60)
          .snapshots()
          .map(
            (snap) => snap.docs
                .map(
                  (d) => _stepDayFromDoc(d.data(), d.id),
                )
                .toList(),
          );
    });

/// Đọc collection `stepLeaderboardEntries` MỘT lần (server) — CHIA SẺ cho cả BXH
/// Bước lẫn BXH Tổng km (trước đây mỗi bên tự `.get()` → đọc trùng gấp đôi cùng
/// data). keepAlive để prefetch lúc khởi động sống tới khi Club dùng. Trả doc thô
/// để mỗi BXH tự map field cần. Pull-to-refresh invalidate provider NÀY để lấy mới.
final stepLeaderboardDocsProvider =
    FutureProvider<List<QueryDocumentSnapshot<Map<String, dynamic>>>>((
      ref,
    ) async {
      ref.watch(firebaseUserProvider);
      final snap = await FirebaseFirestore.instance
          .collection('stepLeaderboardEntries')
          .get(const GetOptions(source: Source.server));
      return snap.docs;
    });

/// Bảng xếp hạng SỐ BƯỚC CHÂN (Apple Health) — riêng với km chạy. Map doc
/// stepLeaderboardEntries về [LeaderboardEntry], nhét số bước vào stats.steps để
/// tái dùng nguyên UI. Dùng CHUNG read với [totalKmLeaderboardProvider].
final stepLeaderboardProvider = FutureProvider<List<LeaderboardEntry>>((
  ref,
) async {
  // steps → xếp hạng BXH Bước; meters (km đi bộ) → cộng vào BXH "Tổng km".
  LeaderboardStats stepStat(int steps, double meters) => LeaderboardStats(
    distanceMeters: meters,
    movingTimeSeconds: 0,
    activityCount: 0,
    activeDays: 0,
    longestDistanceMeters: 0,
    fastestPaceSecondsPerKm: null,
    steps: steps,
  );
  final docs = await ref.watch(stepLeaderboardDocsProvider.future);
  final now = DateTime.now();
  return docs.map((d) {
    final m = d.data();
    final name = (m['displayName'] as String?)?.trim();
    // Doc chỉ được dựng lại khi chủ nó có bước hay buổi mới, nên số của kỳ đã
    // qua không được hiện như kỳ này.
    final current = leaderboardPeriodsCurrent(m, now);
    double dist(String k) => (m[k] as num?)?.toDouble() ?? 0;
    int steps(String k) => (m[k] as num?)?.toInt() ?? 0;
    return LeaderboardEntry(
      uid: m['uid'] as String? ?? d.id,
      displayName: (name?.isNotEmpty ?? false) ? name! : '3i member',
      avatarUrl: m['avatarUrl'] as String?,
      visibility: ProfileVisibility.fromValue(m['profileVisibility'] as String?),
      rollingSevenDays: stepStat(
        steps('rollingSevenDaysSteps'),
        dist('rollingSevenDaysDistance'),
      ),
      currentWeek: current.week
          ? stepStat(steps('currentWeekSteps'), dist('currentWeekDistance'))
          : stepStat(0, 0),
      currentMonth: current.month
          ? stepStat(steps('currentMonthSteps'), dist('currentMonthDistance'))
          : stepStat(0, 0),
    );
  }).toList();
});

/// BXH "Tổng km" = ĐÚNG 1 CON SỐ do BACKEND tính sẵn: stepLeaderboardEntries.
/// *TotalDistance (= km chạy + km đi-bộ, đã khử trùng ở backend). Client CHỈ ĐỌC,
/// TUYỆT ĐỐI không cộng/gộp/phân biệt 2 nguồn. Mỗi user có đúng 1 doc (backend
/// rebuild cho cả người-chỉ-chạy lẫn người-chỉ-đi-bộ khi activity/bước đổi).
final totalKmLeaderboardProvider = FutureProvider<List<LeaderboardEntry>>((
  ref,
) async {
  // Chỉ hiển thị 1 số (quãng đường). Các stat khác để 0 — Tổng km không có
  // pace/buổi (là chạy + đi-bộ gộp), đúng tinh thần "1 con số".
  LeaderboardStats totalStat(double meters) => LeaderboardStats(
    distanceMeters: meters,
    movingTimeSeconds: 0,
    activityCount: 0,
    activeDays: 0,
    longestDistanceMeters: 0,
    fastestPaceSecondsPerKm: null,
    steps: 0,
  );
  final docs = await ref.watch(stepLeaderboardDocsProvider.future);
  final now = DateTime.now();
  return docs.map((d) {
    final m = d.data();
    final name = (m['displayName'] as String?)?.trim();
    final current = leaderboardPeriodsCurrent(m, now);
    double dist(String k) => (m[k] as num?)?.toDouble() ?? 0;
    return LeaderboardEntry(
      uid: m['uid'] as String? ?? d.id,
      displayName: (name?.isNotEmpty ?? false) ? name! : '3i member',
      avatarUrl: m['avatarUrl'] as String?,
      visibility: ProfileVisibility.fromValue(m['profileVisibility'] as String?),
      rollingSevenDays: totalStat(dist('rollingSevenDaysTotalDistance')),
      currentWeek: totalStat(
        current.week ? dist('currentWeekTotalDistance') : 0,
      ),
      currentMonth: totalStat(
        current.month ? dist('currentMonthTotalDistance') : 0,
      ),
    );
  }).toList();
});

/// Docs thô leaderboardEntries — BXH Đạp xe đọc field lồng `ride`.
/// keepAlive + prefetch giống các BXH khác.
final leaderboardDocsProvider =
    FutureProvider<List<QueryDocumentSnapshot<Map<String, dynamic>>>>((
      ref,
    ) async {
      ref.watch(firebaseUserProvider);
      final snap = await FirebaseFirestore.instance
          .collection('leaderboardEntries')
          .get(const GetOptions(source: Source.server));
      return snap.docs;
    });

/// BXH ĐẠP XE — km đạp/kỳ (leaderboardEntries.ride.distanceMeters). Xe đạp
/// KHÔNG cộng vào km chạy/kèo — bảng hoàn toàn riêng.
final bikeLeaderboardProvider = FutureProvider<List<LeaderboardEntry>>((
  ref,
) async {
  LeaderboardStats stat(Map<String, dynamic>? p) => LeaderboardStats(
    distanceMeters: (p?['distanceMeters'] as num?)?.toDouble() ?? 0,
    movingTimeSeconds: 0,
    activityCount: 0,
    activeDays: 0,
    longestDistanceMeters: 0,
    fastestPaceSecondsPerKm: null,
    steps: 0,
  );
  final docs = await ref.watch(leaderboardDocsProvider.future);
  final now = DateTime.now();
  return docs.map((d) {
    final m = d.data();
    final ride = (m['ride'] as Map?)?.cast<String, dynamic>();
    Map<String, dynamic>? period(String k) =>
        (ride?[k] as Map?)?.cast<String, dynamic>();
    final current = leaderboardPeriodsCurrent(m, now);
    final name = (m['displayName'] as String?)?.trim();
    return LeaderboardEntry(
      uid: m['uid'] as String? ?? d.id,
      displayName: (name?.isNotEmpty ?? false) ? name! : '3i member',
      avatarUrl: m['avatarUrl'] as String?,
      visibility: ProfileVisibility.fromValue(
        m['profileVisibility'] as String?,
      ),
      rollingSevenDays: stat(period('rollingSevenDays')),
      currentWeek: stat(current.week ? period('currentWeek') : null),
      currentMonth: stat(current.month ? period('currentMonth') : null),
    );
  }).toList();
});

final clubLiveSessionsProvider =
    StreamProvider.autoDispose<List<LiveTrackingSession>>(
      (ref) =>
          ref.watch(liveTrackingRepositoryProvider).watchClubLiveSessions(),
    );

final liveSessionProvider = StreamProvider.autoDispose
    .family<LiveTrackingSession?, String>(
      (ref, sessionId) =>
          ref.watch(liveTrackingRepositoryProvider).watchSession(sessionId),
    );

/// Vị trí/ảnh live của các buổi chạy đang gắn với 1 kèo theo tuyến cụ thể —
/// dùng cho bản đồ route ở màn chi tiết kèo.
final contractLiveSessionsProvider = StreamProvider.autoDispose
    .family<List<LiveTrackingSession>, String>(
      (ref, contractId) => ref
          .watch(liveTrackingRepositoryProvider)
          .watchContractLiveSessions(contractId),
    );

final memberProfileProvider = StreamProvider.autoDispose
    .family<MemberProfile?, String>((ref, uid) {
      return ref.watch(memberRepositoryProvider).watchMember(uid);
    });

const _clubActivityLogPerMemberLimit = 20;
const _clubActivityLogConcurrency = 4;
const _memberDashboardActivityLimit = 30;

final memberActivitiesProvider = StreamProvider.autoDispose
    .family<List<ActivitySummary>, String>((ref, uid) {
      return ref
          .watch(memberRepositoryProvider)
          .watchMemberActivities(uid, limit: _memberDashboardActivityLimit);
    });

final memberActivityDetailProvider = FutureProvider.autoDispose
    .family<ActivityDetail, ({String uid, String activityId})>((ref, request) {
      return ref
          .watch(memberRepositoryProvider)
          .getMemberActivityDetail(request.uid, request.activityId);
    });

final clubActivityLogProvider =
    FutureProvider.autoDispose<List<ClubActivityLogItem>>((ref) async {
      final cacheLink = ref.keepAlive();
      final cacheTimer = Timer(const Duration(minutes: 2), cacheLink.close);
      ref.onDispose(cacheTimer.cancel);
      final repository = ref.watch(memberRepositoryProvider);
      final members = await ref.watch(membersProvider.future);
      final publicMembers = members.where((member) => member.isPublic).toList();
      if (publicMembers.isEmpty) return const <ClubActivityLogItem>[];
      final activitiesByMember = <String, List<ActivitySummary>>{};
      for (
        var offset = 0;
        offset < publicMembers.length;
        offset += _clubActivityLogConcurrency
      ) {
        final batch = publicMembers
            .skip(offset)
            .take(_clubActivityLogConcurrency);
        final results = await Future.wait([
          for (final member in batch)
            repository
                .listMemberActivities(
                  member.uid,
                  limit: _clubActivityLogPerMemberLimit,
                )
                .then((activities) => (member.uid, activities))
                .catchError((_) => (member.uid, const <ActivitySummary>[])),
        ]);
        for (final result in results) {
          activitiesByMember[result.$1] = result.$2;
        }
      }
      final items = <ClubActivityLogItem>[];
      for (final member in publicMembers) {
        for (final activity
            in activitiesByMember[member.uid] ?? const <ActivitySummary>[]) {
          items.add(ClubActivityLogItem(member: member, activity: activity));
        }
      }
      items.sort(
        (left, right) =>
            right.activity.startedAt.compareTo(left.activity.startedAt),
      );
      return items;
    });

final trainingGoalsProvider = StreamProvider<TrainingGoals>(
  (ref) => ref.watch(trainingGoalRepositoryProvider).watchGoals(),
);

class ClubActivityLogItem {
  const ClubActivityLogItem({required this.member, required this.activity});

  final MemberProfile member;
  final ActivitySummary activity;
}

/// Các buổi chạy đã được ghi nhận (đếm vào tiến độ) của MỌI người tham gia
/// 1 kèo — không chỉ của riêng user hiện tại. Chỉ đọc được hoạt động của
/// participant khác nếu hồ sơ họ để Public (khớp `firestore.rules`:
/// `allow read: if owns(userId) || isPublicProfile(userId)`); participant có
/// hồ sơ Private bị bỏ qua trong feed này (không có cách nào đọc được).
final runContractActivityFeedProvider = StreamProvider.autoDispose
    .family<List<ContractActivityFeedItem>, String>((ref, contractId) {
      final currentUid = ref.watch(firebaseUserProvider).value?.uid;
      if (currentUid == null) return Stream.value(const []);
      final contract = ref.watch(runContractProvider(contractId)).value;
      if (contract == null) return Stream.value(const []);
      final members =
          ref.watch(membersProvider).value ?? const <MemberProfile>[];
      final publicByUid = {
        for (final member in members) member.uid: member.isPublic,
      };
      final repository = ref.watch(memberRepositoryProvider);

      final readableUids = contract.participants.keys
          .where((uid) => uid == currentUid || (publicByUid[uid] ?? false))
          .toList();
      if (readableUids.isEmpty) return Stream.value(const []);

      final controller = StreamController<List<ContractActivityFeedItem>>();
      final latestByUid = <String, List<ActivitySummary>>{};
      final subscriptions = <StreamSubscription<List<ActivitySummary>>>[];

      void emit() {
        final items = <ContractActivityFeedItem>[];
        for (final uid in readableUids) {
          final countedIds =
              contract.participants[uid]?.countedActivityIds.toSet() ??
              const <String>{};
          if (countedIds.isEmpty) continue;
          for (final activity
              in latestByUid[uid] ?? const <ActivitySummary>[]) {
            if (countedIds.contains(activity.id)) {
              items.add(ContractActivityFeedItem(uid: uid, activity: activity));
            }
          }
        }
        items.sort(
          (left, right) =>
              right.activity.startedAt.compareTo(left.activity.startedAt),
        );
        if (!controller.isClosed) controller.add(items);
      }

      for (final uid in readableUids) {
        final countedIds =
            contract.participants[uid]?.countedActivityIds.toSet() ??
            const <String>{};
        if (countedIds.isEmpty) continue;
        subscriptions.add(
          repository.watchMemberActivitiesByIds(uid, countedIds).listen((
            activities,
          ) {
            latestByUid[uid] = activities;
            emit();
          }, onError: controller.addError),
        );
      }

      controller.onCancel = () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      };
      return controller.stream;
    });

class ContractActivityFeedItem {
  const ContractActivityFeedItem({required this.uid, required this.activity});

  final String uid;
  final ActivitySummary activity;
}

/// Bản tóm tắt 1 route "Hành Trình" (tên/tagline/tổng km, KHÔNG có
/// polyline/mốc — xem `JourneyRouteSummary`) — đọc từ Firestore
/// (`journeyRoutes/{routeId}`), cache lại (autoDispose: false) vì nội dung
/// tĩnh dùng chung mọi user. Dùng cho danh sách level ở Journey Hub và tính
/// offset mở khoá — cả hai chỉ cần `totalLengthMeters`, không cần kéo theo
/// polyline nặng của route (xem [journeyRouteDetailProvider] cho việc đó).
final journeyRouteSummaryProvider =
    FutureProvider.family<JourneyRouteSummary, JourneyRouteId>(
      (ref, routeId) => ref
          .watch(memberRepositoryProvider)
          .getJourneyRouteSummary(routeId.value),
    );

/// Toàn bộ dữ liệu 1 route (polyline + mốc) — chỉ dùng khi mở màn chi tiết
/// xem bản đồ (`journey_screen.dart`), đọc thêm subcollection `detail` nặng
/// hơn nhiều so với [journeyRouteSummaryProvider] nên không watch ở Hub.
final journeyRouteDetailProvider =
    FutureProvider.family<JourneyRoute, JourneyRouteId>(
      (ref, routeId) => ref
          .watch(memberRepositoryProvider)
          .getJourneyRouteDetail(routeId.value),
    );

/// Số km cần tích luỹ trước khi 1 chiến dịch Hành Trình bắt đầu tính tiến
/// độ — tổng chiều dài (các) chiến dịch đứng trước nó, tính động từ chính
/// dữ liệu route thật (không hard-code số) nên luôn khớp Firestore. Chiến
/// dịch đầu tiên (`marathon`) có offset 0.
final journeyCampaignOffsetProvider =
    FutureProvider.family<double, JourneyCampaignId>((ref, campaignId) async {
      var offset = 0.0;
      for (final prior in campaignId.priorCampaigns) {
        final summary = await ref.watch(
          journeyRouteSummaryProvider(prior.routeChoices.first).future,
        );
        offset += summary.totalLengthMeters;
      }
      return offset;
    });

/// Tổng km trọn đời của user hiện tại — cộng toàn bộ doc `month` từ
/// `periodStats`, cùng cách "năm" đang cộng cho biểu đồ khối lượng
/// (`training_volume_chart.dart`, range `2000-01`..hiện tại).
final journeyLifetimeDistanceProvider = FutureProvider.autoDispose<double>((
  ref,
) async {
  final uid = ref.watch(firebaseUserProvider).value?.uid;
  if (uid == null) return 0;
  final stats = await ref
      .watch(memberRepositoryProvider)
      .listMemberPeriodStats(
        uid,
        periodType: 'month',
        fromKey: '2000-01',
        toKeyInclusive: monthKey(DateTime.now()),
      );
  return stats.fold<double>(
    0,
    (total, stat) => total + stat.stats.distanceMeters,
  );
});

final memberJourneyLifetimeDistanceProvider = FutureProvider.autoDispose
    .family<double, String>((ref, uid) async {
      final stats = await ref
          .watch(memberRepositoryProvider)
          .listMemberPeriodStats(
            uid,
            periodType: 'month',
            fromKey: '2000-01',
            toKeyInclusive: monthKey(DateTime.now()),
          );
      return stats.fold<double>(
        0,
        (total, stat) => total + stat.stats.distanceMeters,
      );
    });

/// periodStats trang Hồ sơ của user hiện tại: mọi doc tháng, 12 tuần gần nhất
/// và các khoảng doc ngày [profileDayRanges] cần. Bốn query document-id range,
/// chạy song song. Không autoDispose vì tab Hồ sơ sống trong IndexedStack; bấm
/// tab thì app invalidate để đọc lại.
final profileStatsProvider = FutureProvider<ProfileStatsData?>((ref) async {
  final uid = ref.watch(firebaseUserProvider).value?.uid;
  if (uid == null) return null;
  final repo = ref.watch(memberRepositoryProvider);
  final today = DateTime.now();
  Future<Map<String, LeaderboardStats>> load(
    String type,
    String from,
    String to,
  ) async => {
    for (final stat in await repo.listMemberPeriodStats(
      uid,
      periodType: type,
      fromKey: from,
      toKeyInclusive: to,
    ))
      stat.periodKey: stat.run,
  };
  final dayRanges = profileDayRanges(today);
  final (months, weeks, days) = await (
    load('month', '2000-01', monthKey(today)),
    load(
      'week',
      weekKey(today.subtract(const Duration(days: 7 * 11))),
      weekKey(today),
    ),
    Future.wait([for (final (from, to) in dayRanges) load('day', from, to)]),
  ).wait;
  return ProfileStatsData(
    today: today,
    days: {for (final part in days) ...part},
    weeks: weeks,
    months: months,
  );
});

