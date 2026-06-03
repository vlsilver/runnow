enum ActivityKind { run, trailRun, virtualRun, walk, hike }

ActivityKind? parseActivityKind(String? value) {
  return switch (value) {
    'Run' => ActivityKind.run,
    'TrailRun' => ActivityKind.trailRun,
    'VirtualRun' => ActivityKind.virtualRun,
    'Walk' => ActivityKind.walk,
    'Hike' => ActivityKind.hike,
    _ => null,
  };
}

class UserProfile {
  const UserProfile({
    required this.athleteId,
    required this.displayName,
    this.lastSyncedAt,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    final athlete = map['athlete'] as Map<String, dynamic>? ?? const {};
    final firstName = athlete['firstname'] as String? ?? '';
    final lastName = athlete['lastname'] as String? ?? '';
    final name = '$firstName $lastName'.trim();
    final syncedAt = map['lastSyncedAt'];
    return UserProfile(
      athleteId: '${map['athleteId'] ?? ''}',
      displayName: name.isEmpty ? 'Strava athlete' : name,
      lastSyncedAt: syncedAt is DateTime ? syncedAt.toLocal() : null,
    );
  }

  static final demo = UserProfile(
    athleteId: 'demo',
    displayName: 'Demo runner',
    lastSyncedAt: DateTime.now(),
  );

  final String athleteId;
  final String displayName;
  final DateTime? lastSyncedAt;
}

class ActivitySummary {
  const ActivitySummary({
    required this.id,
    required this.name,
    required this.kind,
    required this.startedAt,
    required this.distanceMeters,
    required this.movingTimeSeconds,
    required this.elapsedTimeSeconds,
    this.averageHeartRate,
    this.averageCadence,
    this.elevationGainMeters,
    this.polyline,
    this.hydrated = false,
  });

  factory ActivitySummary.fromMap(Map<String, dynamic> map) {
    return ActivitySummary(
      id: '${map['id']}',
      name: map['name'] as String? ?? 'Hoạt động',
      kind: parseActivityKind(map['sportType'] as String?) ?? ActivityKind.run,
      startedAt: DateTime.parse(map['startedAt'] as String).toLocal(),
      distanceMeters: (map['distanceMeters'] as num?)?.toDouble() ?? 0,
      movingTimeSeconds: (map['movingTimeSeconds'] as num?)?.toInt() ?? 0,
      elapsedTimeSeconds: (map['elapsedTimeSeconds'] as num?)?.toInt() ?? 0,
      averageHeartRate: (map['averageHeartRate'] as num?)?.toDouble(),
      averageCadence: (map['averageCadence'] as num?)?.toDouble(),
      elevationGainMeters: (map['elevationGainMeters'] as num?)?.toDouble(),
      polyline: map['polyline'] as String?,
      hydrated: map['hydrated'] as bool? ?? false,
    );
  }

  final String id;
  final String name;
  final ActivityKind kind;
  final DateTime startedAt;
  final double distanceMeters;
  final int movingTimeSeconds;
  final int elapsedTimeSeconds;
  final double? averageHeartRate;
  final double? averageCadence;
  final double? elevationGainMeters;
  final String? polyline;
  final bool hydrated;

  double get distanceKm => distanceMeters / 1000;
  double? get paceSecondsPerKm =>
      distanceMeters <= 0 ? null : movingTimeSeconds / distanceKm;
}

class ActivityDetail {
  const ActivityDetail({
    required this.summary,
    this.calories,
    this.gearName,
    this.splits = const [],
    this.laps = const [],
    this.streams = const {},
  });

  factory ActivityDetail.fromMap(Map<String, dynamic> map) {
    final summary = ActivitySummary.fromMap(map);
    return ActivityDetail(
      summary: summary,
      calories: (map['calories'] as num?)?.toDouble(),
      gearName: map['gearName'] as String?,
      splits: (map['splits'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>(),
      laps: (map['laps'] as List<dynamic>? ?? const [])
          .cast<Map<String, dynamic>>(),
      streams: (map['streams'] as Map<String, dynamic>? ?? const {}).map(
        (key, value) => MapEntry(
          key,
          (value as List<dynamic>)
              .map((item) => (item as num).toDouble())
              .toList(),
        ),
      ),
    );
  }

  final ActivitySummary summary;
  final double? calories;
  final String? gearName;
  final List<Map<String, dynamic>> splits;
  final List<Map<String, dynamic>> laps;
  final Map<String, List<double>> streams;
}

class TrainingGoals {
  const TrainingGoals({
    required this.weeklyDistanceMeters,
    required this.monthlyDistanceMeters,
  });

  factory TrainingGoals.fromMap(Map<String, dynamic>? map) {
    return TrainingGoals(
      weeklyDistanceMeters:
          (map?['weeklyDistanceMeters'] as num?)?.toDouble() ?? 0,
      monthlyDistanceMeters:
          (map?['monthlyDistanceMeters'] as num?)?.toDouble() ?? 0,
    );
  }

  static const empty = TrainingGoals(
    weeklyDistanceMeters: 0,
    monthlyDistanceMeters: 0,
  );

  final double weeklyDistanceMeters;
  final double monthlyDistanceMeters;

  bool get hasAnyGoal => weeklyDistanceMeters > 0 || monthlyDistanceMeters > 0;
}

class FeedPost {
  const FeedPost({
    required this.id,
    required this.authorUid,
    required this.authorName,
    required this.activity,
    required this.createdAt,
  });

  factory FeedPost.fromMap(Map<String, dynamic> map) {
    return FeedPost(
      id: map['id'] as String,
      authorUid: map['authorUid'] as String,
      authorName: map['authorName'] as String? ?? 'Strava athlete',
      activity: ActivitySummary.fromMap(
        (map['activity'] as Map<String, dynamic>?) ?? const {},
      ),
      createdAt: (map['createdAt'] as DateTime?)?.toLocal() ?? DateTime.now(),
    );
  }

  final String id;
  final String authorUid;
  final String authorName;
  final ActivitySummary activity;
  final DateTime createdAt;
}
