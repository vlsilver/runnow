import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
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
    int imported = 0;
    _debugLog('Starting full Strava sync.');
    while (true) {
      final activities = await StravaClient.instance.listActivities(page: page);
      final batch = _firestore.batch();
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
        batch.set(
          _activities.doc(summary.id),
          activitySummaryToSyncMap(summary),
          SetOptions(merge: true),
        );
        imported += 1;
      }
      await batch.commit();
      _debugLog('Page $page committed to Firestore.');
      if (activities.length < 100) break;
      page += 1;
    }
    await _firestore.collection('users').doc(_uid).set({
      'athleteId': StravaClient.instance.athleteId,
      'lastSyncedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    _debugLog('Sync completed: imported $imported activities.');
    return imported;
  }

  void _debugLog(String message) {
    if (kDebugMode) debugPrint('[ActivityRepository] $message');
  }

  Future<Map<String, List<double>>> _fetchStreams(String activityId) async {
    return _normalizeStreams(
      await StravaClient.instance.getActivityStreams(activityId),
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
    return _userDocument.set({
      'trainingGoals': {
        'weeklyDistanceMeters': goals.weeklyDistanceMeters,
        'monthlyDistanceMeters': goals.monthlyDistanceMeters,
      },
      'trainingGoalsUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
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
