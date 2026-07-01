import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:myrun/src/dashboard_analytics.dart';
import 'package:myrun/src/strava_client.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/tracking_session.dart';

abstract interface class ActivityRepository {
  Stream<List<ActivitySummary>> watchActivities();
  Stream<List<ActivitySummary>> watchTrackedTrialActivities();
  Future<List<ActivitySummary>> listStravaActivities({
    required DateTime start,
    required DateTime endExclusive,
  });
  Future<ActivityDetail> getDetail(String activityId);
  Future<int> sync();
  Future<void> saveTrackedActivity(
    ActivityDetail detail, {
    Map<String, dynamic>? trackingDebug,
  });
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
  Stream<List<ActivitySummary>> watchMemberActivities(String uid);
  Future<ActivityDetail> getMemberActivityDetail(String uid, String activityId);
  Stream<List<LeaderboardEntry>> watchLeaderboardEntries();
  Future<void> ensureCurrentLeaderboardEntry();
  Future<void> updateCurrentProfile({
    required String nickname,
    required String? avatarUrl,
    required ProfileVisibility visibility,
  });
}

abstract interface class LiveTrackingRepository {
  Stream<List<LiveTrackingSession>> watchClubLiveSessions();
  Future<void> publishSnapshot({
    required TrackingSessionSnapshot snapshot,
    required LiveTrackingStatus status,
    required List<RoutePoint> routePreview,
  });
  Future<void> finishSession(String sessionId, LiveTrackingStatus status);
}

class FirestoreStravaActivityRepository implements ActivityRepository {
  FirestoreStravaActivityRepository(this._auth, this._firestore);

  static const _streamsVersion = 4;
  static const _maxCachedStreamSamples = 300;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final Map<String, Future<ActivityDetail>> _detailRequests = {};

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Bạn chưa đăng nhập Firebase.');
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _activities =>
      _firestore.collection('users').doc(_uid).collection('activities');

  @override
  Stream<List<ActivitySummary>> watchActivities() {
    return _activities.orderBy('startedAt', descending: true).snapshots().map((
      snapshot,
    ) {
      _debugLog('Firestore snapshot: ${snapshot.docs.length} activities.');
      return snapshot.docs
          .map((document) => ActivitySummary.fromMap(document.data()))
          .where((activity) => activity.source == ActivitySource.strava)
          .toList();
    });
  }

  @override
  Stream<List<ActivitySummary>> watchTrackedTrialActivities() {
    return _activities.orderBy('startedAt', descending: true).snapshots().map((
      snapshot,
    ) {
      return snapshot.docs
          .map((document) => ActivitySummary.fromMap(document.data()))
          .where((activity) => activity.source == ActivitySource.runnow)
          .toList();
    });
  }

  @override
  Future<List<ActivitySummary>> listStravaActivities({
    required DateTime start,
    required DateTime endExclusive,
  }) async {
    final snapshot = await _activities
        .where(
          'startedAt',
          isGreaterThanOrEqualTo: start.toUtc().toIso8601String(),
        )
        .where('startedAt', isLessThan: endExclusive.toUtc().toIso8601String())
        .get();
    return snapshot.docs
        .map((document) => ActivitySummary.fromMap(document.data()))
        .where((activity) => activity.source == ActivitySource.strava)
        .toList();
  }

  @override
  Future<ActivityDetail> getDetail(String activityId) async {
    final existing = _detailRequests[activityId];
    if (existing != null) {
      _debugLog('Detail request already running for $activityId. Reusing it.');
      return existing;
    }
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
    var cachedData = cached.data();
    if (hasCachedActivityDetail(cachedData)) {
      var detailData = cachedData!;
      _debugLog('Detail cache hit for $activityId.');
      if (detailData['hydrated'] != true) {
        await document.set({'hydrated': true}, SetOptions(merge: true));
      }
      if (shouldBackfillStravaStreams(
        detailData,
        currentStreamsVersion: _streamsVersion,
      )) {
        try {
          final fetchedStreams = await _fetchStreams(
            activityId,
            startedAt: DateTime.parse(detailData['startedAt'] as String),
          );
          await document.set({
            'streams': fetchedStreams.streams,
            if (fetchedStreams.routePoints.isNotEmpty)
              'routePoints': fetchedStreams.routePoints
                  .map((point) => point.toMap())
                  .toList(),
            'streamsHydrated': true,
            'streamsVersion': _streamsVersion,
          }, SetOptions(merge: true));
          detailData = {
            ...detailData,
            'streams': fetchedStreams.streams,
            if (fetchedStreams.routePoints.isNotEmpty)
              'routePoints': fetchedStreams.routePoints
                  .map((point) => point.toMap())
                  .toList(),
          };
          _debugLog(
            'Backfilled streams version $_streamsVersion for $activityId.',
          );
        } catch (error) {
          _debugLog('Could not backfill streams for $activityId: $error');
          await document.set({
            'streamsHydrated': false,
            'streamsVersion': _streamsVersion,
          }, SetOptions(merge: true));
        }
      }
      return ActivityDetail.fromMap({...detailData, 'hydrated': true});
    }
    _debugLog('Detail cache miss for $activityId. Hydrating from Strava.');
    final raw = await StravaClient.instance.getActivityDetail(activityId);
    var streamsHydrated = false;
    var streams = <String, List<double>>{};
    var routePoints = <RoutePoint>[];
    try {
      final fetchedStreams = await _fetchStreams(
        activityId,
        startedAt: DateTime.parse(raw['start_date'] as String),
      );
      streams = fetchedStreams.streams;
      routePoints = fetchedStreams.routePoints;
      streamsHydrated = true;
      _debugLog(
        'Hydrated streams for $activityId: '
        '${streams.map((key, value) => MapEntry(key, value.length))}.',
      );
    } catch (error) {
      _debugLog('Could not hydrate streams for $activityId: $error');
    }
    final detail = ActivityDetail(
      summary: _summaryFromRaw(
        raw,
        hydrated: true,
        averageHeartRateFallback: _average(streams['heartrate']),
        routePoints: routePoints,
      ),
      calories: (raw['calories'] as num?)?.toDouble(),
      gearName: (raw['gear'] as Map<String, dynamic>?)?['name'] as String?,
      splits: _normalizeIntervals(raw['splits_metric']),
      laps: _normalizeIntervals(raw['laps']),
      streams: streams,
    );
    await document.set({
      ..._detailToMap(detail, includeStreams: false),
      'detailHydratedAt': FieldValue.serverTimestamp(),
      'streamsHydrated': false,
    }, SetOptions(merge: true));
    if (streamsHydrated) {
      try {
        await document.set({
          'streams': streams,
          'streamsHydrated': true,
          'streamsVersion': _streamsVersion,
        }, SetOptions(merge: true));
      } catch (error) {
        _debugLog('Could not cache streams for $activityId: $error');
        try {
          await document.set({
            'streamsHydrated': false,
            'streamsVersion': _streamsVersion,
          }, SetOptions(merge: true));
        } catch (markerError) {
          _debugLog(
            'Could not mark streams cache failure for $activityId: $markerError',
          );
        }
      }
    }
    return detail;
  }

  @override
  Future<int> sync() async {
    int page = 1;
    int changed = 0;
    _debugLog('Starting full Strava sync.');
    while (true) {
      final activities = await StravaClient.instance.listActivities(page: page);
      final batch = _firestore.batch();
      var pageHasChanges = false;
      final supported = activities.whereType<Map<String, dynamic>>().where((
        activity,
      ) {
        final sportType =
            activity['sport_type'] as String? ?? activity['type'] as String?;
        final accepted = parseActivityKind(sportType) != null;
        if (!accepted) {
          _debugLog(
            'Skipping unsupported activity ${activity['id']}: $sportType.',
          );
        }
        return accepted;
      }).toList();
      _debugLog(
        'Page $page: received ${activities.length}, '
        'accepted ${supported.length}.',
      );
      for (final activity in supported) {
        final summary = _summaryFromRaw(activity);
        final document = _activities.doc(summary.id);
        final nextData = activitySummaryToSyncMap(summary);
        final existing = await document.get();
        if (!activitySummaryHasChanges(existing.data(), nextData)) {
          continue;
        }
        batch.set(document, nextData, SetOptions(merge: true));
        changed += 1;
        pageHasChanges = true;
      }
      if (pageHasChanges) {
        await batch.commit();
        _debugLog('Page $page committed to Firestore.');
      } else {
        _debugLog('Page $page has no Firestore changes.');
        break;
      }
      if (activities.length < 100) break;
      page += 1;
    }
    if (changed > 0) {
      await _firestore.collection('users').doc(_uid).set({
        'athleteId': StravaClient.instance.athleteId,
        'lastSyncedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await _refreshCurrentLeaderboardEntry();
    _debugLog('Sync completed: changed $changed activities.');
    return changed;
  }

  @override
  Future<void> saveTrackedActivity(
    ActivityDetail detail, {
    Map<String, dynamic>? trackingDebug,
  }) async {
    if (detail.summary.source != ActivitySource.runnow) {
      throw StateError('Chỉ lưu activity tracking nội bộ bằng API này.');
    }
    final document = _activities.doc(detail.summary.id);
    await document.set(
      trackedActivityToFirestoreMap(
        detail,
        trackingDebug: trackingDebug,
        savedAt: FieldValue.serverTimestamp(),
      ),
      SetOptions(merge: true),
    );
    _debugLog('Saved tracked trial activity ${detail.summary.id}.');
  }

  void _debugLog(String message) {
    if (kDebugMode) debugPrint('[ActivityRepository] $message');
  }

  Future<_FetchedStreams> _fetchStreams(
    String activityId, {
    required DateTime startedAt,
  }) async {
    final rawStreams = await StravaClient.instance.getActivityStreams(
      activityId,
    );
    return _FetchedStreams(
      streams: downsampleStreams(
        _normalizeStreams(rawStreams),
        maxSamples: _maxCachedStreamSamples,
      ),
      routePoints: stravaRoutePointsFromStreams(
        rawStreams,
        startedAt: startedAt,
      ),
    );
  }

  Future<void> _refreshCurrentLeaderboardEntry() async {
    await refreshLeaderboardEntryForUser(
      uid: _uid,
      firestore: _firestore,
      debugLog: _debugLog,
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
  Stream<List<ActivitySummary>> watchActivities() {
    return Stream.value(
      _activities
          .where((activity) => activity.source == ActivitySource.strava)
          .toList(),
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
  Future<List<ActivitySummary>> listStravaActivities({
    required DateTime start,
    required DateTime endExclusive,
  }) async => _activities
      .where(
        (activity) =>
            activity.source == ActivitySource.strava &&
            !activity.startedAt.isBefore(start) &&
            activity.startedAt.isBefore(endExclusive),
      )
      .toList();

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
  Future<int> sync() async => _activities.length;

  @override
  Future<void> saveTrackedActivity(
    ActivityDetail detail, {
    Map<String, dynamic>? trackingDebug,
  }) async {
    _activities.removeWhere((activity) => activity.id == detail.summary.id);
    _activities.insert(0, detail.summary);
  }
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

class FirestoreMemberRepository implements MemberRepository {
  FirestoreMemberRepository(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

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
  Stream<List<ActivitySummary>> watchMemberActivities(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .collection('activities')
        .orderBy('startedAt', descending: true)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((document) => ActivitySummary.fromMap(document.data()))
              .where((activity) => activity.source == ActivitySource.strava)
              .toList(),
        );
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
  Stream<List<LeaderboardEntry>> watchLeaderboardEntries() {
    return _firestore.collection('leaderboardEntries').snapshots().map((
      snapshot,
    ) {
      return snapshot.docs.map((document) {
        final data = document.data();
        final updatedAt = data['updatedAt'];
        return LeaderboardEntry.fromMap({
          ...data,
          'uid': document.id,
          if (updatedAt is Timestamp) 'updatedAt': updatedAt.toDate(),
        });
      }).toList();
    });
  }

  @override
  Future<void> ensureCurrentLeaderboardEntry() async {
    final now = DateTime.now();
    final existing = await _firestore
        .collection('leaderboardEntries')
        .doc(_uid)
        .get();
    final data = existing.data();
    if (existing.exists &&
        data != null &&
        _leaderboardEntryHasModernStats(data) &&
        !shouldRefreshLeaderboardEntry(data, now)) {
      return;
    }
    await refreshLeaderboardEntryForUser(
      uid: _uid,
      firestore: _firestore,
      debugLog: (message) {
        if (kDebugMode) {
          debugPrint('[MemberRepository] $message');
        }
      },
    );
  }

  @visibleForTesting
  bool shouldRefreshLeaderboardEntry(Map<String, dynamic> data, DateTime now) {
    final updatedAt = data['updatedAt'];
    DateTime? lastRefresh;
    if (updatedAt is Timestamp) {
      lastRefresh = updatedAt.toDate();
    } else if (updatedAt is DateTime) {
      lastRefresh = updatedAt;
    }
    if (lastRefresh == null) return true;

    final rollingStart = startOfRollingSevenDays(now);
    final currentWeekStart = startOfCurrentWeek(now);
    final currentMonthStart = DateTime(now.year, now.month);
    return lastRefresh.isBefore(rollingStart) ||
        lastRefresh.isBefore(currentWeekStart) ||
        lastRefresh.isBefore(currentMonthStart);
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

    final userRef = _firestore.collection('users').doc(_uid);
    final publicRef = _firestore.collection('publicProfiles').doc(_uid);
    final snapshot = await userRef.get();
    final userData = snapshot.data() ?? const <String, dynamic>{};
    final sanitizedAvatar = avatarUrl?.trim();
    final avatarValue = sanitizedAvatar?.isEmpty == true
        ? null
        : sanitizedAvatar;
    final publicProfile = <String, dynamic>{
      'uid': _uid,
      'displayName': trimmedNickname,
      'nickname': trimmedNickname,
      'profileVisibility': visibility.value,
      'stravaConnected': userData['stravaConnected'] as bool? ?? false,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    publicProfile['avatarUrl'] = avatarValue ?? FieldValue.delete();
    final privateProfile = <String, dynamic>{
      'nickname': trimmedNickname,
      'displayName': trimmedNickname,
      'profileVisibility': visibility.value,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    privateProfile['avatarUrl'] = avatarValue ?? FieldValue.delete();

    final batch = _firestore.batch();
    batch.set(userRef, privateProfile, SetOptions(merge: true));
    batch.set(publicRef, publicProfile, SetOptions(merge: true));
    batch.set(
      _firestore.collection('leaderboardEntries').doc(_uid),
      {
        'uid': _uid,
        'displayName': trimmedNickname,
        'nickname': trimmedNickname,
        'profileVisibility': visibility.value,
        'updatedAt': FieldValue.serverTimestamp(),
        'avatarUrl': avatarValue ?? FieldValue.delete(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();
    await refreshLeaderboardEntryForUser(
      uid: _uid,
      firestore: _firestore,
      debugLog: (message) {
        if (kDebugMode) {
          debugPrint('[MemberRepository] $message');
        }
      },
    );
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

  @override
  Stream<List<LiveTrackingSession>> watchClubLiveSessions() {
    return _liveSessions
        .where('visibility', isEqualTo: LiveTrackingVisibility.club.value)
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
      'ownerName': owner['displayName'] as String? ?? 'RunNow member',
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
    }..removeWhere((key, value) => value == null);
    final avatarUrl = owner['avatarUrl'] as String?;
    if (avatarUrl != null && avatarUrl.trim().isNotEmpty) {
      data['ownerAvatarUrl'] = avatarUrl.trim();
    }
    await _liveSessions.doc(snapshot.id).set(data, SetOptions(merge: true));
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

bool _leaderboardEntryHasModernStats(Map<String, dynamic> data) {
  for (final key in const ['rollingSevenDays', 'currentWeek', 'currentMonth']) {
    final stats = data[key];
    if (stats is! Map<String, dynamic>) return false;
    if (!stats.containsKey('longestDistanceMeters')) return false;
    final distance = (stats['distanceMeters'] as num?)?.toDouble() ?? 0;
    if (distance > 0 && !stats.containsKey('fastestPaceSecondsPerKm')) {
      return false;
    }
  }
  return true;
}

ActivitySummary _summaryFromRaw(
  Map<String, dynamic> raw, {
  bool hydrated = false,
  double? averageHeartRateFallback,
  List<RoutePoint> routePoints = const [],
}) {
  final sportType = raw['sport_type'] as String? ?? raw['type'] as String?;
  final map = raw['map'] as Map<String, dynamic>?;
  return ActivitySummary(
    id: '${raw['id']}',
    name: raw['name'] as String? ?? 'Hoạt động',
    kind: parseActivityKind(sportType) ?? ActivityKind.run,
    startedAt: DateTime.parse(raw['start_date'] as String).toLocal(),
    distanceMeters: (raw['distance'] as num?)?.toDouble() ?? 0,
    movingTimeSeconds: (raw['moving_time'] as num?)?.toInt() ?? 0,
    elapsedTimeSeconds: (raw['elapsed_time'] as num?)?.toInt() ?? 0,
    source: ActivitySource.strava,
    sourceActivityId: '${raw['id']}',
    manual: raw['manual'] as bool?,
    recordingDevice: raw['device_name'] as String?,
    averageHeartRate:
        (raw['average_heartrate'] as num?)?.toDouble() ??
        averageHeartRateFallback,
    averageCadence: (raw['average_cadence'] as num?)?.toDouble(),
    elevationGainMeters: (raw['total_elevation_gain'] as num?)?.toDouble(),
    polyline:
        map?['polyline'] as String? ?? map?['summary_polyline'] as String?,
    routePoints: routePoints,
    hydrated: hydrated,
  );
}

double? _average(List<double>? values) {
  if (values == null || values.isEmpty) return null;
  return values.reduce((left, right) => left + right) / values.length;
}

List<Map<String, dynamic>> _normalizeIntervals(dynamic intervals) {
  if (intervals is! List<dynamic>) return const [];
  return intervals.whereType<Map<String, dynamic>>().map((interval) {
    return {
      'name': interval['name'],
      'split': interval['split'],
      'distanceMeters': interval['distance'],
      'movingTimeSeconds': interval['moving_time'],
      'elapsedTimeSeconds': interval['elapsed_time'],
      'averageSpeedMetersPerSecond': interval['average_speed'],
      'averageHeartRate': interval['average_heartrate'],
    }..removeWhere((key, value) => value == null);
  }).toList();
}

Map<String, List<double>> _normalizeStreams(Map<String, dynamic> streams) {
  return streams.map((key, value) {
    final data = value is Map<String, dynamic> ? value['data'] : null;
    final values = data is List<dynamic>
        ? data
              .whereType<num>()
              .map((item) => item.toDouble())
              .where((item) => item.isFinite)
              .toList()
        : <double>[];
    return MapEntry(key, values);
  })..removeWhere((key, value) => value.isEmpty);
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

class _FetchedStreams {
  const _FetchedStreams({required this.streams, required this.routePoints});

  final Map<String, List<double>> streams;
  final List<RoutePoint> routePoints;
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

Future<void> refreshLeaderboardEntryForUser({
  required String uid,
  required FirebaseFirestore firestore,
  void Function(String message)? debugLog,
}) async {
  final activities = await firestore
      .collection('users')
      .doc(uid)
      .collection('activities')
      .orderBy('startedAt', descending: true)
      .get()
      .then(
        (snapshot) => snapshot.docs
            .map((document) => ActivitySummary.fromMap(document.data()))
            .where((activity) => activity.source == ActivitySource.strava)
            .toList(),
      );
  final user = await firestore.collection('users').doc(uid).get();
  final userData = user.data() ?? const <String, dynamic>{};
  final publicProfile = await firestore
      .collection('publicProfiles')
      .doc(uid)
      .get();
  final publicData = publicProfile.data() ?? const <String, dynamic>{};
  final leaderboardRef = firestore.collection('leaderboardEntries').doc(uid);
  final nextData = leaderboardEntryToMap(
    uid: uid,
    profile: {...userData, ...publicData},
    activities: activities,
  );
  final existing = await leaderboardRef.get();
  if (!leaderboardEntryHasChanges(existing.data(), nextData)) {
    debugLog?.call('Leaderboard aggregate has no changes.');
    return;
  }
  await leaderboardRef.set(nextData, SetOptions(merge: true));
  debugLog?.call('Leaderboard aggregate refreshed.');
}

@visibleForTesting
Map<String, dynamic> leaderboardEntryToMap({
  required String uid,
  required Map<String, dynamic> profile,
  required List<ActivitySummary> activities,
  DateTime? now,
}) {
  final currentTime = now ?? DateTime.now();
  final rollingStart = startOfRollingSevenDays(currentTime);
  final rollingEnd = endOfToday(currentTime);
  final weekStart = startOfCurrentWeek(currentTime);
  final monthStart = DateTime(currentTime.year, currentTime.month);
  final avatarUrl = profile['avatarUrl'] as String?;
  final displayName =
      (profile['nickname'] as String?)?.trim().isNotEmpty == true
      ? (profile['nickname'] as String).trim()
      : (profile['displayName'] as String?)?.trim().isNotEmpty == true
      ? (profile['displayName'] as String).trim()
      : 'RunNow member';
  return {
    'uid': uid,
    'displayName': displayName,
    'nickname': displayName,
    'profileVisibility':
        profile['profileVisibility'] as String? ??
        ProfileVisibility.private.value,
    if (avatarUrl != null && avatarUrl.trim().isNotEmpty)
      'avatarUrl': avatarUrl.trim(),
    'rollingSevenDays': _leaderboardStatsMap(
      activities,
      start: rollingStart,
      end: rollingEnd,
    ),
    'currentWeek': _leaderboardStatsMap(
      activities,
      start: weekStart,
      end: weekStart.add(const Duration(days: 7)),
    ),
    'currentMonth': _leaderboardStatsMap(
      activities,
      start: monthStart,
      end: DateTime(currentTime.year, currentTime.month + 1),
    ),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

@visibleForTesting
bool leaderboardEntryHasChanges(
  Map<String, dynamic>? existingData,
  Map<String, dynamic> nextData,
) {
  if (existingData == null) return true;
  for (final entry in nextData.entries) {
    if (entry.value is FieldValue) continue;
    if (!_firestoreValuesEqual(existingData[entry.key], entry.value)) {
      return true;
    }
  }
  return false;
}

Map<String, dynamic> _leaderboardStatsMap(
  List<ActivitySummary> activities, {
  required DateTime start,
  required DateTime end,
}) {
  final summary = trainingSummary(activities, start: start, end: end);
  final selected = activities.where(
    (activity) =>
        !activity.startedAt.isBefore(start) && activity.startedAt.isBefore(end),
  );
  var longestDistance = 0.0;
  double? fastestPace;
  for (final activity in selected) {
    if (activity.distanceMeters > longestDistance) {
      longestDistance = activity.distanceMeters;
    }
    final pace = activity.paceSecondsPerKm;
    if (pace != null &&
        pace > 0 &&
        (fastestPace == null || pace < fastestPace)) {
      fastestPace = pace;
    }
  }
  return LeaderboardStats(
    distanceMeters: summary.distanceMeters,
    movingTimeSeconds: summary.movingTimeSeconds,
    activityCount: summary.activityCount,
    activeDays: _activeDays(activities, start: start, end: end),
    longestDistanceMeters: longestDistance,
    fastestPaceSecondsPerKm: fastestPace,
  ).toMap();
}

int _activeDays(
  List<ActivitySummary> activities, {
  required DateTime start,
  required DateTime end,
}) {
  return activities
      .where(
        (activity) =>
            !activity.startedAt.isBefore(start) &&
            activity.startedAt.isBefore(end),
      )
      .map(
        (activity) => DateTime(
          activity.startedAt.year,
          activity.startedAt.month,
          activity.startedAt.day,
        ),
      )
      .toSet()
      .length;
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
  }..removeWhere((key, value) => value == null);
}

String _sportType(ActivityKind kind) {
  return switch (kind) {
    ActivityKind.run => 'Run',
    ActivityKind.trailRun => 'TrailRun',
    ActivityKind.virtualRun => 'VirtualRun',
    ActivityKind.walk => 'Walk',
    ActivityKind.hike => 'Hike',
  };
}
