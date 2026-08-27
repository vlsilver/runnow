import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:myrun/src/activity_eligibility.dart';
import 'package:myrun/src/dashboard_analytics.dart';
import 'package:myrun/src/journey/journey_models.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/tracking_session.dart';

abstract interface class ActivityRepository {
  Stream<List<ActivitySummary>> watchActivities({int? limit});
  Stream<List<ActivitySummary>> watchTrackedTrialActivities();
  Future<JournalActivityPage> fetchJournalActivitiesPage({
    int limit = 30,
    Object? cursor,
  });
  Future<List<ActivitySummary>> listOfficialActivities({
    required DateTime start,
    required DateTime endExclusive,
    int? limit,
  });

  /// Raw lookup by ID, bỏ qua bước khử trùng Strava/3i của
  /// [listOfficialActivities] — cần để 1 activity đã claim vào kèo vẫn được
  /// tính dù sau đó có 1 activity khác (Strava) trùng nó đồng bộ về, và để
  /// kiểm tra trùng lặp trước khi cho claim thêm.
  Future<Map<String, ActivitySummary>> getActivitiesByIds(Set<String> ids);
  Future<ActivityDetail> getDetail(String activityId);
  Future<ActivitySyncOutcome> sync({bool fullResync = false});
  Future<TrackedActivitySaveResult> saveTrackedActivity(
    ActivityDetail detail, {
    Map<String, dynamic>? trackingDebug,
  });

  /// Đẩy DẦN 1 đoạn điểm route (append-only) vào
  /// `users/{uid}/activities/{activityId}/track/{seq}` trong lúc chạy (~10s/lần)
  /// để không mất buổi khi crash/hết pin. [points] là điểm LEAN (lat/lng/ts).
  Future<void> appendTrackChunk({
    required String activityId,
    required int seq,
    required List<Map<String, dynamic>> points,
  });

  /// Trạng thái chunk đã ghi (dùng khi khôi phục buổi chạy bị kill giữa chừng):
  /// [nextSeq] để ghi tiếp không đè, [flushedPoints] tổng điểm đã đẩy để không
  /// đẩy lặp phần đầu.
  Future<({int nextSeq, int flushedPoints})> trackChunkState(String activityId);

  /// Hoàn tất buổi đã sync theo chunk: gửi summary NHẸ (không routePoints),
  /// backend ghép chunk thành route đầy đủ rồi lưu.
  Future<TrackedActivitySaveResult> finalizeTrackedActivity(
    ActivityDetail detail,
  );
}

class ActivitySyncOutcome {
  const ActivitySyncOutcome({
    required this.changedCount,
    this.changedActivities = const [],
    this.queued = false,
  });

  final int changedCount;
  final List<ActivitySummary> changedActivities;
  final bool queued;
}

class JournalActivityEntry {
  const JournalActivityEntry({
    required this.activity,
    this.preferredStravaActivityId,
  });

  final ActivitySummary activity;
  final String? preferredStravaActivityId;

  bool get isSupersededByStrava => preferredStravaActivityId != null;
}

class JournalActivityPage {
  const JournalActivityPage({
    required this.entries,
    required this.hasMore,
    this.nextCursor,
  });

  final List<JournalActivityEntry> entries;
  final Object? nextCursor;
  final bool hasMore;
}

@visibleForTesting
List<JournalActivityEntry> buildJournalActivityEntries(
  Iterable<ActivitySummary> activities,
) {
  final all = activities.toList();
  final duplicates = preferredStravaDuplicates(all);
  final entries = <JournalActivityEntry>[
    for (final activity in all)
      if (activity.source == ActivitySource.strava ||
          isCountedNonStravaRun(activity))
        JournalActivityEntry(
          activity: activity,
          preferredStravaActivityId: activity.source == ActivitySource.runnow
              ? duplicates[activity.id]?.id
              : null,
        ),
  ];
  entries.sort(
    (left, right) =>
        right.activity.startedAt.compareTo(left.activity.startedAt),
  );
  return entries;
}

@visibleForTesting
List<JournalActivityEntry> buildJournalPageEntries(
  Iterable<ActivitySummary> pageActivities,
  Iterable<ActivitySummary> overlapContext,
) {
  final entriesById = {
    for (final entry in buildJournalActivityEntries(overlapContext))
      entry.activity.id: entry,
  };
  return pageActivities
      .map((activity) => entriesById[activity.id])
      .whereType<JournalActivityEntry>()
      .toList();
}

enum TrackedActivitySaveStatus {
  counted,
  belowMinimumDistance,
  duplicateOfStrava,
}

class TrackedActivitySaveResult {
  const TrackedActivitySaveResult({
    required this.status,
    this.stravaActivityId,
  });

  final TrackedActivitySaveStatus status;
  final String? stravaActivityId;

  bool get countsTowardStats => status == TrackedActivitySaveStatus.counted;
}

abstract interface class FeedRepository {
  Stream<List<FeedPost>> watchPosts();
  Future<void> publish(ActivitySummary activity);
  Future<void> remove(ActivitySummary activity);
}

abstract interface class TrainingGoalRepository {
  Stream<TrainingGoals> watchGoals();
  Future<void> saveGoals(TrainingGoals goals);
}

abstract interface class MemberRepository {
  Stream<List<MemberProfile>> watchMembers();
  Stream<MemberProfile?> watchMember(String uid);
  Stream<List<ActivitySummary>> watchMemberActivities(String uid, {int? limit});
  Future<List<ActivitySummary>> listMemberActivities(
    String uid, {
    int limit = 40,
  });
  Stream<List<ActivitySummary>> watchMemberActivitiesByIds(
    String uid,
    Set<String> activityIds,
  );
  Future<ActivityDetail> getMemberActivityDetail(String uid, String activityId);

  /// Số liệu tổng hợp theo kỳ (backend tính sẵn) của 1 thành viên — dùng cho
  /// biểu đồ khối lượng tập thay vì tải toàn bộ activity thô. [fromKey] và
  /// [toKeyInclusive] là periodKey cùng loại [periodType] (vd `2025-08` →
  /// `2026-07`); key sort đúng thứ tự thời gian nên so theo chuỗi là đủ.
  Future<List<PeriodStat>> listMemberPeriodStats(
    String uid, {
    required String periodType,
    required String fromKey,
    required String toKeyInclusive,
  });
  Future<List<LeaderboardEntry>> getLeaderboardEntries();
  Future<void> updateCurrentProfile({
    required String nickname,
    required String? avatarUrl,
    required ProfileVisibility visibility,
  });

  /// Đánh dấu đã hiện popup "chúc mừng lên hạng" cho [key] (mã hoá
  /// metric+range+kỳ+hạng) — chỉ ghi field riêng lên `users/{uid}`, không
  /// cần lan sang `publicProfiles`/`leaderboardEntries` như
  /// [updateCurrentProfile] vì đây là cờ nội bộ, không hiển thị public.
  Future<void> markRankCelebrated(String key);

  /// Lưu cung đường "Hành Trình" user chọn (`coastal` | `hcm_trail`) — cờ
  /// nội bộ như [markRankCelebrated], vị trí/mốc đều derive từ tổng km nên
  /// không cần lưu gì khác ngoài lựa chọn cung.
  Future<void> setJourneyRoute(String routeId);

  /// Bản tóm tắt 1 route "Hành Trình" (không kèm points/milestones nặng) —
  /// đủ cho danh sách level ở Journey Hub, chỉ đọc đúng 1 doc nhẹ
  /// `journeyRoutes/{routeId}`.
  Future<JourneyRouteSummary> getJourneyRouteSummary(String routeId);

  /// Toàn bộ dữ liệu 1 route, gồm cả polyline + mốc — chỉ cần khi mở màn
  /// chi tiết xem bản đồ (`journey_screen.dart`), không dùng ở Hub vì nặng
  /// hơn nhiều (route có thể tới hàng ngàn điểm).
  Future<JourneyRoute> getJourneyRouteDetail(String routeId);
}

abstract interface class LiveTrackingRepository {
  Stream<List<LiveTrackingSession>> watchClubLiveSessions();
  Stream<List<LiveTrackingSession>> watchContractLiveSessions(
    String contractId,
  );
  Future<void> publishSnapshot({
    required TrackingSessionSnapshot snapshot,
    required LiveTrackingStatus status,
    required List<RoutePoint> routePreview,
    String? contractId,
  });
  Future<void> publishPhoto({
    required String sessionId,
    required ActivityPhoto photo,
  });
  Future<void> finishSession(String sessionId, LiveTrackingStatus status);
}

class FirestoreStravaActivityRepository implements ActivityRepository {
  FirestoreStravaActivityRepository(this._auth, this._firestore, this._api);

  static const _streamsVersion = 4;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final RunNowApiClient _api;
  final Map<String, Future<ActivityDetail>> _detailRequests = {};

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Bạn chưa đăng nhập Firebase.');
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _activities =>
      _firestore.collection('users').doc(_uid).collection('activities');

  @override
  Stream<List<ActivitySummary>> watchActivities({int? limit}) {
    Query<Map<String, dynamic>> query = _activities.orderBy(
      'startedAt',
      descending: true,
    );
    if (limit != null) query = query.limit(limit);
    return query.snapshots().map((snapshot) {
      final all = snapshot.docs
          .map(
            (document) => ActivitySummary.fromMap(
              document.data(),
              includeRoutePoints: false,
              includePhotos: false,
            ),
          )
          .toList();
      return selectOfficialActivities(all);
    });
  }

  @override
  Future<JournalActivityPage> fetchJournalActivitiesPage({
    int limit = 30,
    Object? cursor,
  }) async {
    Query<Map<String, dynamic>> query = _activities.orderBy(
      'startedAt',
      descending: true,
    );
    final documentCursor = cursor;
    if (documentCursor is DocumentSnapshot<Map<String, dynamic>>) {
      query = query.startAfterDocument(documentCursor);
    }
    final snapshot = await query.limit(limit).get();
    final activities = snapshot.docs
        .map(
          (document) => ActivitySummary.fromMap(
            document.data(),
            includeRoutePoints: false,
            includePhotos: false,
          ),
        )
        .toList();
    // Backend đã tự stamp `duplicateOfActivityId` lên doc lúc sync (cả lúc
    // 3i activity được tạo lẫn lúc Strava activity trùng giờ sync về sau,
    // xem `markRunNowDuplicates`/`SaveTracked` trong `activity_service.go`)
    // — đọc thẳng field đó thay vì query lại `startedAt` ±24h quanh từng
    // activity runnow trên trang để tự tính overlap, tránh N query phụ mỗi
    // lần tải trang.
    return JournalActivityPage(
      entries: [
        for (final activity in activities)
          if (activity.source == ActivitySource.strava ||
              isCountedNonStravaRun(activity))
            JournalActivityEntry(
              activity: activity,
              preferredStravaActivityId:
                  activity.source == ActivitySource.runnow
                  ? activity.duplicateOfActivityId
                  : null,
            ),
      ],
      nextCursor: snapshot.docs.isEmpty ? cursor : snapshot.docs.last,
      hasMore: snapshot.docs.length == limit,
    );
  }

  @override
  Stream<List<ActivitySummary>> watchTrackedTrialActivities() {
    return _activities
        .where('source', isEqualTo: ActivitySource.runnow.value)
        .limit(100)
        .snapshots()
        .map((snapshot) {
          final activities = snapshot.docs
              .map((document) => ActivitySummary.fromMap(document.data()))
              .toList();
          activities.sort((a, b) => b.startedAt.compareTo(a.startedAt));
          return activities;
        });
  }

  @override
  Future<List<ActivitySummary>> listOfficialActivities({
    required DateTime start,
    required DateTime endExclusive,
    int? limit,
  }) async {
    final queryStart = start.subtract(const Duration(hours: 24));
    Query<Map<String, dynamic>> query = _activities
        .where(
          'startedAt',
          isGreaterThanOrEqualTo: queryStart.toUtc().toIso8601String(),
        )
        .where('startedAt', isLessThan: endExclusive.toUtc().toIso8601String())
        .orderBy('startedAt', descending: true);
    if (limit != null) query = query.limit(limit);
    final snapshot = await query.get();
    return selectOfficialActivities(
          snapshot.docs
              .map((document) => ActivitySummary.fromMap(document.data()))
              .toList(),
        )
        .where(
          (activity) =>
              !activity.startedAt.isBefore(start) &&
              activity.startedAt.isBefore(endExclusive),
        )
        .toList();
  }

  @override
  Future<Map<String, ActivitySummary>> getActivitiesByIds(
    Set<String> ids,
  ) async {
    if (ids.isEmpty) return const {};
    final documents = await Future.wait(
      ids.map((id) => _activities.doc(id).get()),
    );
    return {
      for (final document in documents)
        if (document.data() case final data?)
          document.id: ActivitySummary.fromMap(data),
    };
  }

  @override
  Future<ActivityDetail> getDetail(String activityId) async {
    final existing = _detailRequests[activityId];
    if (existing != null) return existing;
    final request = _loadDetail(activityId);
    _detailRequests[activityId] = request;
    try {
      return await request;
    } finally {
      _detailRequests.remove(activityId);
    }
  }

  Future<ActivityDetail> _loadDetail(String activityId) async {
    final document = _activities.doc(activityId);
    final cached = await document.get();
    final cachedData = cached.data();
    final source = ActivitySource.fromValue(cachedData?['source'] as String?);
    if (source == ActivitySource.runnow && cachedData != null) {
      return ActivityDetail.fromMap({...cachedData, 'hydrated': true});
    }
    if (hasCachedActivityDetail(cachedData) &&
        !shouldBackfillStravaStreams(
          cachedData!,
          currentStreamsVersion: _streamsVersion,
        )) {
      return ActivityDetail.fromMap({...cachedData, 'hydrated': true});
    }

    await _api.hydrateActivity(activityId);
    try {
      final hydrated = await document
          .snapshots()
          .map((snapshot) => snapshot.data())
          .firstWhere(
            (data) =>
                hasCachedActivityDetail(data) &&
                data?['streamsHydrated'] == true &&
                data?['streamsVersion'] == _streamsVersion,
          )
          .timeout(const Duration(seconds: 35));
      return ActivityDetail.fromMap({...hydrated!, 'hydrated': true});
    } on TimeoutException {
      // Detail summary remains useful while a large Strava stream continues in
      // Cloud Tasks. Reopening the screen will hit the completed cache later.
      if (hasCachedActivityDetail(cachedData)) {
        return ActivityDetail.fromMap({...cachedData!, 'hydrated': true});
      }
      throw StateError(
        'Backend đang tải chi tiết hoạt động. Hãy mở lại sau ít phút.',
      );
    }
  }

  @override
  Future<ActivitySyncOutcome> sync({bool fullResync = false}) async {
    await _api.requestStravaRepair(full: fullResync);
    return const ActivitySyncOutcome(changedCount: 0, queued: true);
  }

  @override
  Future<TrackedActivitySaveResult> saveTrackedActivity(
    ActivityDetail detail, {
    Map<String, dynamic>? trackingDebug,
  }) async {
    if (detail.summary.source != ActivitySource.runnow) {
      throw StateError('Chỉ lưu activity tracking nội bộ bằng API này.');
    }
    final result = await _api.saveTrackedActivity(
      trackedActivityToFirestoreMap(detail, trackingDebug: trackingDebug),
    );
    return _mapTrackedResult(result);
  }

  CollectionReference<Map<String, dynamic>> _trackChunks(String activityId) =>
      _activities.doc(activityId).collection('track');

  @override
  Future<void> appendTrackChunk({
    required String activityId,
    required int seq,
    required List<Map<String, dynamic>> points,
  }) async {
    if (points.isEmpty) return;
    await _trackChunks(activityId).doc('$seq').set({
      'seq': seq,
      'points': points,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<({int nextSeq, int flushedPoints})> trackChunkState(
    String activityId,
  ) async {
    final snapshot = await _trackChunks(activityId).get();
    if (snapshot.docs.isEmpty) return (nextSeq: 0, flushedPoints: 0);
    var maxSeq = -1;
    var flushedPoints = 0;
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final seq = (data['seq'] as num?)?.toInt() ?? -1;
      if (seq > maxSeq) maxSeq = seq;
      final points = data['points'];
      if (points is List) flushedPoints += points.length;
    }
    return (nextSeq: maxSeq + 1, flushedPoints: flushedPoints);
  }

  @override
  Future<TrackedActivitySaveResult> finalizeTrackedActivity(
    ActivityDetail detail,
  ) async {
    if (detail.summary.source != ActivitySource.runnow) {
      throw StateError('Chỉ lưu activity tracking nội bộ bằng API này.');
    }
    final summary = trackedActivityToFirestoreMap(detail);
    // Route đã được đẩy sẵn qua các chunk → bỏ khỏi summary cho payload nhẹ.
    // Backend tự ghép route từ chunk. Streams (~50KB) vẫn gửi kèm ở đây.
    summary.remove('routePoints');
    final result = await _api.finalizeTrackedActivity(summary);
    return _mapTrackedResult(result);
  }

  TrackedActivitySaveResult _mapTrackedResult(
    TrackedActivityBackendResult result,
  ) {
    return TrackedActivitySaveResult(
      status: switch (result.status) {
        'below_minimum_distance' =>
          TrackedActivitySaveStatus.belowMinimumDistance,
        'duplicate_of_strava' => TrackedActivitySaveStatus.duplicateOfStrava,
        _ => TrackedActivitySaveStatus.counted,
      },
      stravaActivityId: result.stravaActivityId,
    );
  }
}

class DemoActivityRepository implements ActivityRepository {
  final List<ActivitySummary> _activities = [
    ActivitySummary(
      id: 'demo-run',
      name: 'Chạy buổi sáng',
      kind: ActivityKind.run,
      startedAt: DateTime.now().subtract(const Duration(days: 1)),
      distanceMeters: 8240,
      movingTimeSeconds: 2922,
      elapsedTimeSeconds: 3060,
      averageHeartRate: 151,
      averageCadence: 82,
      elevationGainMeters: 42,
      hydrated: true,
    ),
    ActivitySummary(
      id: 'demo-walk',
      name: 'Đi bộ hồi phục',
      kind: ActivityKind.walk,
      startedAt: DateTime.now().subtract(const Duration(days: 3)),
      distanceMeters: 3210,
      movingTimeSeconds: 2530,
      elapsedTimeSeconds: 2750,
      averageHeartRate: 101,
      elevationGainMeters: 12,
      hydrated: true,
    ),
  ];

  @override
  Stream<List<ActivitySummary>> watchActivities({int? limit}) {
    return Stream.value(selectOfficialActivities(_activities));
  }

  @override
  Future<JournalActivityPage> fetchJournalActivitiesPage({
    int limit = 30,
    Object? cursor,
  }) async {
    final activities = [..._activities]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final start = cursor is int ? cursor : 0;
    final end = math.min(start + limit, activities.length);
    final pageActivities = activities.sublist(start, end);
    return JournalActivityPage(
      entries: buildJournalPageEntries(pageActivities, _activities),
      nextCursor: end,
      hasMore: end < activities.length,
    );
  }

  @override
  Stream<List<ActivitySummary>> watchTrackedTrialActivities() {
    return Stream.value(
      _activities
          .where((activity) => activity.source == ActivitySource.runnow)
          .toList(),
    );
  }

  @override
  Future<List<ActivitySummary>> listOfficialActivities({
    required DateTime start,
    required DateTime endExclusive,
    int? limit,
  }) async {
    final activities =
        selectOfficialActivities(_activities)
            .where(
              (activity) =>
                  !activity.startedAt.isBefore(start) &&
                  activity.startedAt.isBefore(endExclusive),
            )
            .toList()
          ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return limit == null ? activities : activities.take(limit).toList();
  }

  @override
  Future<Map<String, ActivitySummary>> getActivitiesByIds(
    Set<String> ids,
  ) async {
    return {
      for (final activity in _activities)
        if (ids.contains(activity.id)) activity.id: activity,
    };
  }

  @override
  Future<ActivityDetail> getDetail(String activityId) async {
    final summary = _activities.firstWhere(
      (activity) => activity.id == activityId,
    );
    return ActivityDetail(
      summary: summary,
      calories: 518,
      gearName: 'Daily Trainer',
    );
  }

  @override
  Future<ActivitySyncOutcome> sync({bool fullResync = false}) async =>
      ActivitySyncOutcome(changedCount: _activities.length);

  @override
  Future<TrackedActivitySaveResult> saveTrackedActivity(
    ActivityDetail detail, {
    Map<String, dynamic>? trackingDebug,
  }) async {
    _activities.removeWhere((activity) => activity.id == detail.summary.id);
    _activities.insert(0, detail.summary);
    if (!isCountedNonStravaRun(detail.summary)) {
      return const TrackedActivitySaveResult(
        status: TrackedActivitySaveStatus.belowMinimumDistance,
      );
    }
    final duplicate = preferredStravaDuplicate(detail.summary, _activities);
    return TrackedActivitySaveResult(
      status: duplicate == null
          ? TrackedActivitySaveStatus.counted
          : TrackedActivitySaveStatus.duplicateOfStrava,
      stravaActivityId: duplicate?.id,
    );
  }

  @override
  Future<void> appendTrackChunk({
    required String activityId,
    required int seq,
    required List<Map<String, dynamic>> points,
  }) async {}

  @override
  Future<({int nextSeq, int flushedPoints})> trackChunkState(
    String activityId,
  ) async => (nextSeq: 0, flushedPoints: 0);

  @override
  Future<TrackedActivitySaveResult> finalizeTrackedActivity(
    ActivityDetail detail,
  ) => saveTrackedActivity(detail);
}

class DemoFeedRepository implements FeedRepository {
  final _controller = StreamController<List<FeedPost>>.broadcast();
  final List<FeedPost> _posts = [];

  @override
  Stream<List<FeedPost>> watchPosts() async* {
    yield List.unmodifiable(_posts);
    yield* _controller.stream;
  }

  @override
  Future<void> publish(ActivitySummary activity) async {
    _posts.removeWhere((post) => post.activity.id == activity.id);
    _posts.insert(
      0,
      FeedPost(
        id: 'demo:${activity.id}',
        authorUid: 'demo',
        authorName: 'Demo runner',
        activity: activity,
        createdAt: DateTime.now(),
      ),
    );
    _controller.add(List.unmodifiable(_posts));
  }

  @override
  Future<void> remove(ActivitySummary activity) async {
    _posts.removeWhere((post) => post.activity.id == activity.id);
    _controller.add(List.unmodifiable(_posts));
  }

  void dispose() {
    _controller.close();
  }
}

class DemoTrainingGoalRepository implements TrainingGoalRepository {
  DemoTrainingGoalRepository([TrainingGoals goals = TrainingGoals.empty])
    : _goals = goals;

  final _controller = StreamController<TrainingGoals>.broadcast();
  TrainingGoals _goals;

  @override
  Stream<TrainingGoals> watchGoals() async* {
    yield _goals;
    yield* _controller.stream;
  }

  @override
  Future<void> saveGoals(TrainingGoals goals) async {
    _goals = goals;
    _controller.add(_goals);
  }

  void dispose() {
    _controller.close();
  }
}

class FirestoreTrainingGoalRepository implements TrainingGoalRepository {
  FirestoreTrainingGoalRepository(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Bạn chưa đăng nhập Firebase.');
    return uid;
  }

  DocumentReference<Map<String, dynamic>> get _userDocument =>
      _firestore.collection('users').doc(_uid);

  @override
  Stream<TrainingGoals> watchGoals() {
    return _userDocument.snapshots().map((snapshot) {
      final data = snapshot.data();
      return TrainingGoals.fromMap(
        data?['trainingGoals'] as Map<String, dynamic>?,
      );
    });
  }

  @override
  Future<void> saveGoals(TrainingGoals goals) {
    final historyDocument = _userDocument
        .collection('trainingGoalHistory')
        .doc();
    final now = DateTime.now();
    final weekStart = _startOfWeek(now);
    final monthStart = DateTime(now.year, now.month);

    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(_userDocument);
      final previousGoals = TrainingGoals.fromMap(
        snapshot.data()?['trainingGoals'] as Map<String, dynamic>?,
      );
      final changedFields = _changedGoalFields(previousGoals, goals);
      if (changedFields.isEmpty) return;

      transaction.set(_userDocument, {
        'trainingGoals': goals.toMap(),
        'trainingGoalsUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      transaction.set(historyDocument, {
        'previousGoals': previousGoals.toMap(),
        'trainingGoals': goals.toMap(),
        'changedFields': changedFields,
        'effectiveWeekStart': Timestamp.fromDate(weekStart),
        'effectiveMonthStart': Timestamp.fromDate(monthStart),
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  DateTime _startOfWeek(DateTime date) {
    final localDate = DateTime(date.year, date.month, date.day);
    return localDate.subtract(Duration(days: localDate.weekday - 1));
  }

  List<String> _changedGoalFields(TrainingGoals before, TrainingGoals after) {
    return [
      if (before.weeklyDistanceMeters != after.weeklyDistanceMeters)
        'weeklyDistanceMeters',
      if (before.monthlyDistanceMeters != after.monthlyDistanceMeters)
        'monthlyDistanceMeters',
    ];
  }
}

class FirestoreFeedRepository implements FeedRepository {
  FirestoreFeedRepository(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Bạn chưa đăng nhập Firebase.');
    return uid;
  }

  @override
  Stream<List<FeedPost>> watchPosts() {
    return _firestore
        .collection('feedPosts')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((document) {
            final data = document.data();
            final createdAt = data['createdAt'];
            return FeedPost.fromMap({
              ...data,
              'id': document.id,
              if (createdAt is Timestamp) 'createdAt': createdAt.toDate(),
            });
          }).toList(),
        );
  }

  @override
  Future<void> publish(ActivitySummary activity) async {
    await _firestore.collection('feedPosts').doc('$_uid:${activity.id}').set({
      'authorUid': _uid,
      'authorName': 'Strava athlete',
      'activity': _summaryToMap(activity, includePolyline: false),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> remove(ActivitySummary activity) {
    return _firestore
        .collection('feedPosts')
        .doc('$_uid:${activity.id}')
        .delete();
  }
}

List<List<String>> _chunkStrings(List<String> values, int size) {
  final chunks = <List<String>>[];
  for (var index = 0; index < values.length; index += size) {
    final end = math.min(index + size, values.length);
    chunks.add(values.sublist(index, end));
  }
  return chunks;
}

class FirestoreMemberRepository implements MemberRepository {
  FirestoreMemberRepository(this._auth, this._firestore, this._api);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final RunNowApiClient _api;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Bạn chưa đăng nhập Firebase.');
    return uid;
  }

  @override
  Stream<List<MemberProfile>> watchMembers() {
    return _firestore
        .collection('publicProfiles')
        .orderBy('displayName')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((document) {
            final data = document.data();
            final updatedAt = data['updatedAt'];
            return MemberProfile.fromMap({
              ...data,
              'uid': document.id,
              if (updatedAt is Timestamp) 'updatedAt': updatedAt.toDate(),
            });
          }).toList(),
        );
  }

  @override
  Stream<MemberProfile?> watchMember(String uid) {
    return _firestore.collection('publicProfiles').doc(uid).snapshots().map((
      document,
    ) {
      final data = document.data();
      if (data == null) return null;
      final updatedAt = data['updatedAt'];
      return MemberProfile.fromMap({
        ...data,
        'uid': document.id,
        if (updatedAt is Timestamp) 'updatedAt': updatedAt.toDate(),
      });
    });
  }

  @override
  Future<List<PeriodStat>> listMemberPeriodStats(
    String uid, {
    required String periodType,
    required String fromKey,
    required String toKeyInclusive,
  }) async {
    // Doc ID có dạng `{periodType}:{periodKey}` và key sort đúng thứ tự thời
    // gian, nên range theo document ID là đủ — không cần composite index.
    final snapshot = await _firestore
        .collection('users')
        .doc(uid)
        .collection('periodStats')
        .orderBy(FieldPath.documentId)
        .startAt(['$periodType:$fromKey'])
        .endAt(['$periodType:$toKeyInclusive'])
        .get();
    return [
      for (final document in snapshot.docs) PeriodStat.fromMap(document.data()),
    ];
  }

  @override
  Stream<List<ActivitySummary>> watchMemberActivities(
    String uid, {
    int? limit,
  }) {
    Query<Map<String, dynamic>> query = _firestore
        .collection('users')
        .doc(uid)
        .collection('activities')
        .orderBy('startedAt', descending: true);
    final boundedQuery = limit == null ? query : query.limit(limit);
    return boundedQuery.snapshots().map(
      (snapshot) => selectOfficialActivities(
        snapshot.docs
            .map(
              (document) => ActivitySummary.fromMap(
                document.data(),
                includeRoutePoints: false,
                includePhotos: false,
              ),
            )
            .toList(),
      ),
    );
  }

  @override
  Future<List<ActivitySummary>> listMemberActivities(
    String uid, {
    int limit = 40,
  }) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(uid)
        .collection('activities')
        .orderBy('startedAt', descending: true)
        .limit(limit)
        .get();
    return selectOfficialActivities(
      snapshot.docs
          .map(
            (document) => ActivitySummary.fromMap(
              document.data(),
              includeRoutePoints: false,
              includePhotos: false,
            ),
          )
          .toList(),
    );
  }

  @override
  Stream<List<ActivitySummary>> watchMemberActivitiesByIds(
    String uid,
    Set<String> activityIds,
  ) {
    if (activityIds.isEmpty) return Stream.value(const <ActivitySummary>[]);
    final chunks = _chunkStrings(activityIds.toList()..sort(), 30);
    final controller = StreamController<List<ActivitySummary>>();
    final latestByChunk = <int, List<ActivitySummary>>{};
    final subscriptions =
        <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];

    void emit() {
      final activities = <ActivitySummary>[];
      for (var index = 0; index < chunks.length; index++) {
        activities.addAll(latestByChunk[index] ?? const <ActivitySummary>[]);
      }
      activities.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      if (!controller.isClosed) {
        controller.add(selectOfficialActivities(activities));
      }
    }

    for (var index = 0; index < chunks.length; index++) {
      final ids = chunks[index];
      final subscription = _firestore
          .collection('users')
          .doc(uid)
          .collection('activities')
          .where(FieldPath.documentId, whereIn: ids)
          .snapshots()
          .listen((snapshot) {
            latestByChunk[index] = snapshot.docs
                .map((document) => ActivitySummary.fromMap(document.data()))
                .toList();
            emit();
          }, onError: controller.addError);
      subscriptions.add(subscription);
    }

    controller.onCancel = () async {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    };
    return controller.stream;
  }

  @override
  Future<ActivityDetail> getMemberActivityDetail(
    String uid,
    String activityId,
  ) async {
    final document = await _firestore
        .collection('users')
        .doc(uid)
        .collection('activities')
        .doc(activityId)
        .get();
    final data = document.data();
    if (data == null) throw StateError('Không tìm thấy hoạt động.');
    if (hasCachedActivityDetail(data)) {
      return ActivityDetail.fromMap(data);
    }
    return ActivityDetail(summary: ActivitySummary.fromMap(data));
  }

  @override
  Future<List<LeaderboardEntry>> getLeaderboardEntries() async {
    // GET thẳng từ SERVER (không cache, không listener). Leaderboard đã precompute
    // nên đọc 1 lần là đủ nhanh; muốn tươi lại thì pull-to-refresh.
    final snapshot = await _firestore
        .collection('leaderboardEntries')
        .get(const GetOptions(source: Source.server));
    final now = DateTime.now();
    return snapshot.docs.map((document) {
      final data = document.data();
      final updatedAt = data['updatedAt'];
      return LeaderboardEntry.fromMap(
        normalizeLeaderboardEntryPeriods({
          ...data,
          'uid': document.id,
          if (updatedAt is Timestamp) 'updatedAt': updatedAt.toDate(),
        }, now),
      );
    }).toList();
  }

  @override
  Future<void> updateCurrentProfile({
    required String nickname,
    required String? avatarUrl,
    required ProfileVisibility visibility,
  }) async {
    final trimmedNickname = nickname.trim();
    if (trimmedNickname.isEmpty) {
      throw StateError('Nickname không được để trống.');
    }

    final sanitizedAvatar = avatarUrl?.trim();
    final avatarValue = sanitizedAvatar?.isEmpty == true
        ? null
        : sanitizedAvatar;
    await _api.updateProfile(
      nickname: trimmedNickname,
      avatarUrl: avatarValue,
      visibility: visibility.value,
    );
  }

  @override
  Future<void> markRankCelebrated(String key) async {
    await _firestore.collection('users').doc(_uid).set({
      'lastCelebratedRankKey': key,
    }, SetOptions(merge: true));
  }

  @override
  Future<void> setJourneyRoute(String routeId) async {
    final batch = _firestore.batch();
    batch.set(_firestore.collection('users').doc(_uid), {
      'journeyRouteId': routeId,
    }, SetOptions(merge: true));
    batch.set(_firestore.collection('publicProfiles').doc(_uid), {
      'journeyRouteId': routeId,
    }, SetOptions(merge: true));
    await batch.commit();
  }

  @override
  Future<JourneyRouteSummary> getJourneyRouteSummary(String routeId) async {
    final snapshot = await _firestore
        .collection('journeyRoutes')
        .doc(routeId)
        .get();
    return JourneyRouteSummary.fromMap(snapshot.data() ?? {});
  }

  @override
  Future<JourneyRoute> getJourneyRouteDetail(String routeId) async {
    final routeRef = _firestore.collection('journeyRoutes').doc(routeId);
    final results = await Future.wait([
      routeRef.get(),
      routeRef.collection('detail').doc('data').get(),
    ]);
    final summarySnapshot = results[0];
    final detailSnapshot = results[1];
    return JourneyRoute.fromMap({
      ...?summarySnapshot.data(),
      ...?detailSnapshot.data(),
    });
  }
}

class FirestoreLiveTrackingRepository implements LiveTrackingRepository {
  FirestoreLiveTrackingRepository(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  Map<String, dynamic>? _cachedOwner;
  String? _cachedOwnerUid;
  DateTime? _cachedOwnerAt;

  static const _ownerCacheDuration = Duration(seconds: 30);

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Bạn chưa đăng nhập Firebase.');
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _liveSessions =>
      _firestore.collection('liveSessions');

  static const _visibleLiveSessionLimit = 50;
  static const _activeStatusValues = ['running', 'paused'];

  @override
  Stream<List<LiveTrackingSession>> watchClubLiveSessions() {
    return _liveSessions
        .where('visibility', isEqualTo: LiveTrackingVisibility.club.value)
        .where('status', whereIn: _activeStatusValues)
        .orderBy('updatedAt', descending: true)
        .limit(_visibleLiveSessionLimit)
        .snapshots()
        .map((snapshot) {
          final now = DateTime.now();
          final items =
              snapshot.docs
                  .map((document) {
                    final data = document.data();
                    final startedAt = data['startedAt'];
                    final updatedAt = data['updatedAt'];
                    return LiveTrackingSession.fromMap({
                      ...data,
                      'id': document.id,
                      if (startedAt is Timestamp)
                        'startedAt': startedAt.toDate(),
                      if (updatedAt is Timestamp)
                        'updatedAt': updatedAt.toDate(),
                    });
                  })
                  .where(
                    (session) => session.isActive && !session.isExpired(now),
                  )
                  .toList()
                ..sort(
                  (left, right) => right.updatedAt.compareTo(left.updatedAt),
                );
          return items;
        });
  }

  @override
  Future<void> publishSnapshot({
    required TrackingSessionSnapshot snapshot,
    required LiveTrackingStatus status,
    required List<RoutePoint> routePreview,
    String? contractId,
  }) async {
    final owner = await _ownerProfile();
    final profileVisibility = ProfileVisibility.fromValue(
      owner['profileVisibility'] as String?,
    );
    final liveVisibility = profileVisibility == ProfileVisibility.public
        ? LiveTrackingVisibility.club
        : LiveTrackingVisibility.private;
    final data = <String, dynamic>{
      'id': snapshot.id,
      'ownerUid': _uid,
      'ownerName': owner['displayName'] as String? ?? '3i member',
      'visibility': liveVisibility.value,
      'status': status.value,
      'startedAt': Timestamp.fromDate(snapshot.startedAt.toUtc()),
      'updatedAt': FieldValue.serverTimestamp(),
      'distanceMeters': snapshot.distanceMeters,
      'movingTimeSeconds': snapshot.movingTimeSeconds,
      'avgPaceSecondsPerKm': snapshot.averagePaceSecondsPerKm,
      if (snapshot.routePoints.isNotEmpty)
        'lastLocation': snapshot.routePoints.last.toMap(),
      if (routePreview.isNotEmpty)
        'routePreview': routePreview.map((point) => point.toMap()).toList(),
      'contractId': contractId,
    }..removeWhere((key, value) => value == null);
    final avatarUrl = owner['avatarUrl'] as String?;
    if (avatarUrl != null && avatarUrl.trim().isNotEmpty) {
      data['ownerAvatarUrl'] = avatarUrl.trim();
    }
    await _liveSessions.doc(snapshot.id).set(data, SetOptions(merge: true));
  }

  @override
  Future<void> publishPhoto({
    required String sessionId,
    required ActivityPhoto photo,
  }) async {
    await _liveSessions.doc(sessionId).set({
      'livePhotos': FieldValue.arrayUnion([photo.toMap()]),
    }, SetOptions(merge: true));
  }

  @override
  Stream<List<LiveTrackingSession>> watchContractLiveSessions(
    String contractId,
  ) {
    return _liveSessions
        .where('contractId', isEqualTo: contractId)
        .where('status', whereIn: _activeStatusValues)
        .orderBy('updatedAt', descending: true)
        .limit(_visibleLiveSessionLimit)
        .snapshots()
        .map((snapshot) {
          final now = DateTime.now();
          final items =
              snapshot.docs
                  .map((document) {
                    final data = document.data();
                    final startedAt = data['startedAt'];
                    final updatedAt = data['updatedAt'];
                    return LiveTrackingSession.fromMap({
                      ...data,
                      'id': document.id,
                      if (startedAt is Timestamp)
                        'startedAt': startedAt.toDate(),
                      if (updatedAt is Timestamp)
                        'updatedAt': updatedAt.toDate(),
                    });
                  })
                  .where(
                    (session) => session.isActive && !session.isExpired(now),
                  )
                  .toList()
                ..sort(
                  (left, right) => right.updatedAt.compareTo(left.updatedAt),
                );
          return items;
        });
  }

  @override
  Future<void> finishSession(
    String sessionId,
    LiveTrackingStatus status,
  ) async {
    await _liveSessions.doc(sessionId).set({
      'ownerUid': _uid,
      'status': status.value,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>> _ownerProfile() async {
    final uid = _uid;
    final cached = _cachedOwner;
    final cachedAt = _cachedOwnerAt;
    if (cached != null &&
        _cachedOwnerUid == uid &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _ownerCacheDuration) {
      return cached;
    }
    final publicProfile = await _firestore
        .collection('publicProfiles')
        .doc(uid)
        .get();
    final userProfile = await _firestore.collection('users').doc(uid).get();
    final data = {...?userProfile.data(), ...?publicProfile.data()};
    _cachedOwner = data;
    _cachedOwnerUid = uid;
    _cachedOwnerAt = DateTime.now();
    return data;
  }
}

@visibleForTesting
Map<String, List<double>> downsampleStreams(
  Map<String, List<double>> streams, {
  required int maxSamples,
}) {
  if (maxSamples < 2) return streams;
  return streams.map((key, values) {
    final finiteValues = values.where((item) => item.isFinite).toList();
    if (finiteValues.isEmpty) return MapEntry(key, <double>[]);
    final valuesToSample = finiteValues;
    if (valuesToSample.length <= maxSamples) {
      return MapEntry(key, valuesToSample);
    }
    final lastIndex = valuesToSample.length - 1;
    return MapEntry(key, [
      for (var outputIndex = 0; outputIndex < maxSamples; outputIndex++)
        valuesToSample[(outputIndex * lastIndex / (maxSamples - 1)).round()],
    ]);
  })..removeWhere((key, value) => value.isEmpty);
}

@visibleForTesting
List<RoutePoint> stravaRoutePointsFromStreams(
  Map<String, dynamic> streams, {
  required DateTime startedAt,
}) {
  final latLngData = _streamData(streams['latlng']);
  if (latLngData.length < 2) return const [];
  final timeData = _streamData(streams['time']);
  final points = <RoutePoint>[];
  for (var index = 0; index < latLngData.length; index += 1) {
    final rawPoint = latLngData[index];
    if (rawPoint is! List<dynamic> || rawPoint.length < 2) continue;
    final latitude = rawPoint[0];
    final longitude = rawPoint[1];
    if (latitude is! num || longitude is! num) continue;
    final seconds = index < timeData.length && timeData[index] is num
        ? (timeData[index] as num).round()
        : index;
    points.add(
      RoutePoint(
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
        timestamp: startedAt.toLocal().add(Duration(seconds: seconds)),
      ),
    );
  }
  return points.length < 2 ? const [] : points;
}

List<dynamic> _streamData(dynamic stream) {
  if (stream is! Map<String, dynamic>) return const [];
  final data = stream['data'];
  return data is List<dynamic> ? data : const [];
}

Map<String, dynamic> _summaryToMap(
  ActivitySummary summary, {
  bool includePolyline = true,
  bool includeHydrated = true,
}) {
  return {
    'schemaVersion': summary.schemaVersion,
    'id': summary.id,
    'name': summary.name,
    'source': summary.source.value,
    'sourceActivityId': summary.sourceActivityId,
    'manual': summary.manual,
    'recordingDevice': summary.recordingDevice,
    'sportType': _sportType(summary.kind),
    'startedAt': summary.startedAt.toUtc().toIso8601String(),
    'distanceMeters': summary.distanceMeters,
    'movingTimeSeconds': summary.movingTimeSeconds,
    'elapsedTimeSeconds': summary.elapsedTimeSeconds,
    'averageHeartRate': summary.averageHeartRate,
    'averageCadence': summary.averageCadence,
    'elevationGainMeters': summary.elevationGainMeters,
    if (includePolyline) 'polyline': summary.polyline,
    if (summary.routePoints.isNotEmpty)
      'routePoints': summary.routePoints.map((point) => point.toMap()).toList(),
    if (includeHydrated) 'hydrated': summary.hydrated,
  }..removeWhere((key, value) => value == null);
}

@visibleForTesting
Map<String, dynamic> activitySummaryToSyncMap(ActivitySummary summary) {
  return _summaryToMap(summary, includeHydrated: false);
}

@visibleForTesting
Map<String, dynamic> trackedActivityToFirestoreMap(
  ActivityDetail detail, {
  Map<String, dynamic>? trackingDebug,
  Object? savedAt,
}) {
  if (detail.summary.source != ActivitySource.runnow) {
    throw StateError('Tracked activity phải có source=runnow.');
  }
  return {
    ..._detailToMap(detail),
    'hydrated': true,
    'streamsHydrated': true,
    'streamsVersion': FirestoreStravaActivityRepository._streamsVersion,
    'trackingDebug': ?trackingDebug,
    'trackingSavedAt': ?savedAt,
  };
}

@visibleForTesting
bool activitySummaryHasChanges(
  Map<String, dynamic>? existingData,
  Map<String, dynamic> nextData,
) {
  if (existingData == null) return true;
  for (final entry in nextData.entries) {
    if (!_firestoreValuesEqual(existingData[entry.key], entry.value)) {
      return true;
    }
  }
  return false;
}

bool _firestoreValuesEqual(Object? left, Object? right) {
  if (left is num && right is num) {
    return left.toDouble() == right.toDouble();
  }
  if (left is Map<String, dynamic> && right is Map<String, dynamic>) {
    return _mapsEqual(left, right);
  }
  return left == right;
}

/// Prevents an aggregate from a previous week/month being presented under the
/// current period label. Period keys are authoritative for new documents;
/// `updatedAt` keeps legacy documents safe until their owner refreshes them.
@visibleForTesting
Map<String, dynamic> normalizeLeaderboardEntryPeriods(
  Map<String, dynamic> data,
  DateTime now,
) {
  final normalized = Map<String, dynamic>.from(data);
  final updatedAt = switch (data['updatedAt']) {
    Timestamp value => value.toDate(),
    DateTime value => value,
    _ => null,
  };
  final weekStart = startOfCurrentWeek(now);
  final monthStart = DateTime(now.year, now.month);

  if (!_leaderboardPeriodIsCurrent(
    storedKey: data['currentWeekStart'],
    expectedKey: _leaderboardPeriodKey(weekStart),
    legacyUpdatedAt: updatedAt,
    periodStart: weekStart,
  )) {
    normalized['currentWeek'] = const <String, dynamic>{};
  }
  if (!_leaderboardPeriodIsCurrent(
    storedKey: data['currentMonthStart'],
    expectedKey: _leaderboardPeriodKey(monthStart),
    legacyUpdatedAt: updatedAt,
    periodStart: monthStart,
  )) {
    normalized['currentMonth'] = const <String, dynamic>{};
  }
  return normalized;
}

bool _leaderboardPeriodIsCurrent({
  required Object? storedKey,
  required String expectedKey,
  required DateTime? legacyUpdatedAt,
  required DateTime periodStart,
}) {
  if (storedKey is String) return storedKey == expectedKey;
  return legacyUpdatedAt != null && !legacyUpdatedAt.isBefore(periodStart);
}

String _leaderboardPeriodKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

bool _mapsEqual(Map<String, dynamic> left, Map<String, dynamic> right) {
  if (left.length != right.length) return false;
  for (final entry in right.entries) {
    if (!_firestoreValuesEqual(left[entry.key], entry.value)) return false;
  }
  return true;
}

@visibleForTesting
bool hasCachedActivityDetail(Map<String, dynamic>? data) {
  if (data == null) return false;
  if (data['hydrated'] == true) return true;

  // Older syncs could overwrite hydrated=false after detail had been cached.
  return data.containsKey('splits') &&
      data.containsKey('laps') &&
      data.containsKey('streams');
}

@visibleForTesting
bool shouldBackfillStravaStreams(
  Map<String, dynamic> data, {
  required int currentStreamsVersion,
}) {
  final source = ActivitySource.fromValue(data['source'] as String?);
  return source == ActivitySource.strava &&
      (data['streamsHydrated'] != true ||
          data['streamsVersion'] != currentStreamsVersion);
}

Map<String, dynamic> _detailToMap(
  ActivityDetail detail, {
  bool includeStreams = true,
}) {
  return {
    ..._summaryToMap(detail.summary),
    'calories': detail.calories,
    'gearName': detail.gearName,
    'splits': detail.splits,
    'laps': detail.laps,
    if (includeStreams) 'streams': detail.streams,
    if (detail.photos.isNotEmpty)
      'photos': detail.photos.map((photo) => photo.toMap()).toList(),
  }..removeWhere((key, value) => value == null);
}

String _sportType(ActivityKind kind) {
  return switch (kind) {
    ActivityKind.run => 'Run',
    ActivityKind.trailRun => 'TrailRun',
    ActivityKind.virtualRun => 'VirtualRun',
    ActivityKind.walk => 'Walk',
    ActivityKind.hike => 'Hike',
    ActivityKind.ride => 'Ride',
    ActivityKind.swim => 'Swim',
    ActivityKind.gym => 'Gym',
  };
}
