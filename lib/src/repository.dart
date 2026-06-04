import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:myrun/src/dashboard_analytics.dart';
import 'package:myrun/src/strava_client.dart';
import 'package:myrun/src/models.dart';

abstract interface class ActivityRepository {
  Stream<List<ActivitySummary>> watchActivities();
  Future<ActivityDetail> getDetail(String activityId);
  Future<int> sync();
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
  Stream<List<LeaderboardEntry>> watchLeaderboardEntries();
  Future<void> ensureCurrentLeaderboardEntry();
  Future<void> updateCurrentProfile({
    required String nickname,
    required String? avatarUrl,
    required ProfileVisibility visibility,
  });
}

class FirestoreStravaActivityRepository implements ActivityRepository {
  FirestoreStravaActivityRepository(this._auth, this._firestore);

  static const _streamsVersion = 3;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

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
          .toList();
    });
  }

  @override
  Future<ActivityDetail> getDetail(String activityId) async {
    final document = _activities.doc(activityId);
    final cached = await document.get();
    var cachedData = cached.data();
    if (hasCachedActivityDetail(cachedData)) {
      var detailData = cachedData!;
      _debugLog('Detail cache hit for $activityId.');
      if (detailData['hydrated'] != true) {
        await document.set({'hydrated': true}, SetOptions(merge: true));
      }
      if (detailData['streamsVersion'] != _streamsVersion) {
        try {
          final streams = await _fetchStreams(activityId);
          await document.set({
            'streams': streams,
            'streamsHydrated': true,
            'streamsVersion': _streamsVersion,
          }, SetOptions(merge: true));
          detailData = {...detailData, 'streams': streams};
          _debugLog(
            'Backfilled streams version $_streamsVersion for $activityId.',
          );
        } catch (error) {
          _debugLog('Could not backfill streams for $activityId: $error');
        }
      }
      return ActivityDetail.fromMap({...detailData, 'hydrated': true});
    }
    _debugLog('Detail cache miss for $activityId. Hydrating from Strava.');
    final raw = await StravaClient.instance.getActivityDetail(activityId);
    var streamsHydrated = false;
    var streams = <String, List<double>>{};
    try {
      streams = await _fetchStreams(activityId);
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
      ),
      calories: (raw['calories'] as num?)?.toDouble(),
      gearName: (raw['gear'] as Map<String, dynamic>?)?['name'] as String?,
      splits: _normalizeIntervals(raw['splits_metric']),
      laps: _normalizeIntervals(raw['laps']),
      streams: streams,
    );
    await document.set({
      ..._detailToMap(detail),
      'detailHydratedAt': FieldValue.serverTimestamp(),
      'streamsHydrated': streamsHydrated,
      if (streamsHydrated) 'streamsVersion': _streamsVersion,
    }, SetOptions(merge: true));
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
      await _refreshCurrentLeaderboardEntry();
    }
    _debugLog('Sync completed: changed $changed activities.');
    return changed;
  }

  void _debugLog(String message) {
    if (kDebugMode) debugPrint('[ActivityRepository] $message');
  }

  Future<Map<String, List<double>>> _fetchStreams(String activityId) async {
    return _normalizeStreams(
      await StravaClient.instance.getActivityStreams(activityId),
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
  Stream<List<ActivitySummary>> watchActivities() => Stream.value(_activities);

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
              .toList(),
        );
  }

  @override
  Stream<List<LeaderboardEntry>> watchLeaderboardEntries() {
    return _firestore
        .collection('leaderboardEntries')
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((document) {
            final data = document.data();
            final updatedAt = data['updatedAt'];
            return LeaderboardEntry.fromMap({
              ...data,
              'uid': document.id,
              if (updatedAt is Timestamp) 'updatedAt': updatedAt.toDate(),
            });
          }).toList(),
        );
  }

  @override
  Future<void> ensureCurrentLeaderboardEntry() async {
    final existing = await _firestore
        .collection('leaderboardEntries')
        .doc(_uid)
        .get();
    if (existing.exists) return;
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
  }
}

ActivitySummary _summaryFromRaw(
  Map<String, dynamic> raw, {
  bool hydrated = false,
  double? averageHeartRateFallback,
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
    averageHeartRate:
        (raw['average_heartrate'] as num?)?.toDouble() ??
        averageHeartRateFallback,
    averageCadence: (raw['average_cadence'] as num?)?.toDouble(),
    elevationGainMeters: (raw['total_elevation_gain'] as num?)?.toDouble(),
    polyline:
        map?['polyline'] as String? ?? map?['summary_polyline'] as String?,
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
    return MapEntry(
      key,
      data is List<dynamic>
          ? data.whereType<num>().map((item) => item.toDouble()).toList()
          : <double>[],
    );
  });
}

Map<String, dynamic> _summaryToMap(
  ActivitySummary summary, {
  bool includePolyline = true,
  bool includeHydrated = true,
}) {
  return {
    'id': summary.id,
    'name': summary.name,
    'sportType': _sportType(summary.kind),
    'startedAt': summary.startedAt.toUtc().toIso8601String(),
    'distanceMeters': summary.distanceMeters,
    'movingTimeSeconds': summary.movingTimeSeconds,
    'elapsedTimeSeconds': summary.elapsedTimeSeconds,
    'averageHeartRate': summary.averageHeartRate,
    'averageCadence': summary.averageCadence,
    'elevationGainMeters': summary.elevationGainMeters,
    if (includePolyline) 'polyline': summary.polyline,
    if (includeHydrated) 'hydrated': summary.hydrated,
  }..removeWhere((key, value) => value == null);
}

@visibleForTesting
Map<String, dynamic> activitySummaryToSyncMap(ActivitySummary summary) {
  return _summaryToMap(summary, includeHydrated: false);
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
  return LeaderboardStats(
    distanceMeters: summary.distanceMeters,
    movingTimeSeconds: summary.movingTimeSeconds,
    activityCount: summary.activityCount,
    activeDays: _activeDays(activities, start: start, end: end),
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

Map<String, dynamic> _detailToMap(ActivityDetail detail) {
  return {
    ..._summaryToMap(detail.summary),
    'calories': detail.calories,
    'gearName': detail.gearName,
    'splits': detail.splits,
    'laps': detail.laps,
    'streams': detail.streams,
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
