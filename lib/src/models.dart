enum ActivityKind { run, trailRun, virtualRun, walk, hike }

enum ProfileVisibility {
  public('public'),
  private('private');

  const ProfileVisibility(this.value);

  factory ProfileVisibility.fromValue(String? value) {
    return switch (value) {
      'public' => ProfileVisibility.public,
      _ => ProfileVisibility.private,
    };
  }

  final String value;
}

enum ActivitySource {
  strava('strava'),
  runnow('runnow');

  const ActivitySource(this.value);

  factory ActivitySource.fromValue(String? value) {
    return switch (value) {
      'runnow' => ActivitySource.runnow,
      _ => ActivitySource.strava,
    };
  }

  final String value;
}

class RoutePoint {
  const RoutePoint({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.altitudeMeters,
    this.accuracyMeters,
    this.speedMetersPerSecond,
    this.headingDegrees,
  });

  factory RoutePoint.fromMap(Map<String, dynamic> map) {
    return RoutePoint(
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0,
      timestamp: DateTime.parse(map['timestamp'] as String).toLocal(),
      altitudeMeters: (map['altitudeMeters'] as num?)?.toDouble(),
      accuracyMeters: (map['accuracyMeters'] as num?)?.toDouble(),
      speedMetersPerSecond: (map['speedMetersPerSecond'] as num?)?.toDouble(),
      headingDegrees: (map['headingDegrees'] as num?)?.toDouble(),
    );
  }

  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double? altitudeMeters;
  final double? accuracyMeters;
  final double? speedMetersPerSecond;
  final double? headingDegrees;

  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'altitudeMeters': altitudeMeters,
      'accuracyMeters': accuracyMeters,
      'speedMetersPerSecond': speedMetersPerSecond,
      'headingDegrees': headingDegrees,
    }..removeWhere((key, value) => value == null);
  }
}

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
    this.email,
    this.avatarUrl,
    this.nickname,
    this.visibility = ProfileVisibility.private,
    this.stravaConnected = false,
    this.lastSyncedAt,
  });

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    final athlete = map['athlete'] as Map<String, dynamic>? ?? const {};
    final firstName = athlete['firstname'] as String? ?? '';
    final lastName = athlete['lastname'] as String? ?? '';
    final athleteName = '$firstName $lastName'.trim();
    final nickname = map['nickname'] as String?;
    final displayName = map['displayName'] as String?;
    final syncedAt = map['lastSyncedAt'];
    return UserProfile(
      athleteId: '${map['stravaAthleteId'] ?? map['athleteId'] ?? ''}',
      displayName: nickname?.trim().isNotEmpty == true
          ? nickname!.trim()
          : displayName?.trim().isNotEmpty == true
          ? displayName!.trim()
          : athleteName.isEmpty
          ? 'RunNow member'
          : athleteName,
      email: map['email'] as String?,
      avatarUrl: map['avatarUrl'] as String?,
      nickname: nickname,
      visibility: ProfileVisibility.fromValue(
        map['profileVisibility'] as String?,
      ),
      stravaConnected: map['stravaConnected'] as bool? ?? false,
      lastSyncedAt: syncedAt is DateTime ? syncedAt.toLocal() : null,
    );
  }

  static final demo = UserProfile(
    athleteId: 'demo',
    displayName: 'Demo runner',
    stravaConnected: true,
    lastSyncedAt: DateTime.now(),
  );

  final String athleteId;
  final String displayName;
  final String? email;
  final String? avatarUrl;
  final String? nickname;
  final ProfileVisibility visibility;
  final bool stravaConnected;
  final DateTime? lastSyncedAt;
}

class MemberProfile {
  const MemberProfile({
    required this.uid,
    required this.displayName,
    required this.visibility,
    this.avatarUrl,
    this.stravaConnected = false,
    this.updatedAt,
  });

  factory MemberProfile.fromMap(Map<String, dynamic> map) {
    final nickname = map['nickname'] as String?;
    final displayName = map['displayName'] as String?;
    return MemberProfile(
      uid: map['uid'] as String? ?? '',
      displayName: nickname?.trim().isNotEmpty == true
          ? nickname!.trim()
          : displayName?.trim().isNotEmpty == true
          ? displayName!.trim()
          : 'RunNow member',
      avatarUrl: map['avatarUrl'] as String?,
      visibility: ProfileVisibility.fromValue(
        map['profileVisibility'] as String?,
      ),
      stravaConnected: map['stravaConnected'] as bool? ?? false,
      updatedAt: map['updatedAt'] is DateTime
          ? (map['updatedAt'] as DateTime).toLocal()
          : null,
    );
  }

  final String uid;
  final String displayName;
  final String? avatarUrl;
  final ProfileVisibility visibility;
  final bool stravaConnected;
  final DateTime? updatedAt;

  bool get isPublic => visibility == ProfileVisibility.public;
}

class LeaderboardStats {
  const LeaderboardStats({
    required this.distanceMeters,
    required this.movingTimeSeconds,
    required this.activityCount,
    required this.activeDays,
    required this.longestDistanceMeters,
    required this.fastestPaceSecondsPerKm,
  });

  factory LeaderboardStats.fromMap(Map<String, dynamic>? map) {
    return LeaderboardStats(
      distanceMeters: (map?['distanceMeters'] as num?)?.toDouble() ?? 0,
      movingTimeSeconds: (map?['movingTimeSeconds'] as num?)?.toInt() ?? 0,
      activityCount: (map?['activityCount'] as num?)?.toInt() ?? 0,
      activeDays: (map?['activeDays'] as num?)?.toInt() ?? 0,
      longestDistanceMeters:
          (map?['longestDistanceMeters'] as num?)?.toDouble() ?? 0,
      fastestPaceSecondsPerKm: (map?['fastestPaceSecondsPerKm'] as num?)
          ?.toDouble(),
    );
  }

  final double distanceMeters;
  final int movingTimeSeconds;
  final int activityCount;
  final int activeDays;
  final double longestDistanceMeters;
  final double? fastestPaceSecondsPerKm;

  Map<String, dynamic> toMap() {
    return {
      'distanceMeters': distanceMeters,
      'movingTimeSeconds': movingTimeSeconds,
      'activityCount': activityCount,
      'activeDays': activeDays,
      'longestDistanceMeters': longestDistanceMeters,
      if (fastestPaceSecondsPerKm != null)
        'fastestPaceSecondsPerKm': fastestPaceSecondsPerKm,
    };
  }
}

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.uid,
    required this.displayName,
    required this.visibility,
    required this.rollingSevenDays,
    required this.currentWeek,
    required this.currentMonth,
    this.avatarUrl,
    this.updatedAt,
  });

  factory LeaderboardEntry.fromMap(Map<String, dynamic> map) {
    final nickname = map['nickname'] as String?;
    final displayName = map['displayName'] as String?;
    return LeaderboardEntry(
      uid: map['uid'] as String? ?? '',
      displayName: nickname?.trim().isNotEmpty == true
          ? nickname!.trim()
          : displayName?.trim().isNotEmpty == true
          ? displayName!.trim()
          : 'RunNow member',
      avatarUrl: map['avatarUrl'] as String?,
      visibility: ProfileVisibility.fromValue(
        map['profileVisibility'] as String?,
      ),
      rollingSevenDays: LeaderboardStats.fromMap(
        map['rollingSevenDays'] as Map<String, dynamic>?,
      ),
      currentWeek: LeaderboardStats.fromMap(
        map['currentWeek'] as Map<String, dynamic>?,
      ),
      currentMonth: LeaderboardStats.fromMap(
        map['currentMonth'] as Map<String, dynamic>?,
      ),
      updatedAt: map['updatedAt'] is DateTime
          ? (map['updatedAt'] as DateTime).toLocal()
          : null,
    );
  }

  final String uid;
  final String displayName;
  final String? avatarUrl;
  final ProfileVisibility visibility;
  final LeaderboardStats rollingSevenDays;
  final LeaderboardStats currentWeek;
  final LeaderboardStats currentMonth;
  final DateTime? updatedAt;

  bool get isPublic => visibility == ProfileVisibility.public;
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
    this.source = ActivitySource.strava,
    this.sourceActivityId,
    this.recordingDevice,
    this.averageHeartRate,
    this.averageCadence,
    this.elevationGainMeters,
    this.polyline,
    this.routePoints = const [],
    this.hydrated = false,
    this.schemaVersion = 1,
  });

  factory ActivitySummary.fromMap(Map<String, dynamic> map) {
    final rawRoutePoints = map['routePoints'] as List<dynamic>? ?? const [];
    return ActivitySummary(
      id: '${map['id']}',
      name: map['name'] as String? ?? 'Hoạt động',
      kind: parseActivityKind(map['sportType'] as String?) ?? ActivityKind.run,
      startedAt: DateTime.parse(map['startedAt'] as String).toLocal(),
      distanceMeters: (map['distanceMeters'] as num?)?.toDouble() ?? 0,
      movingTimeSeconds: (map['movingTimeSeconds'] as num?)?.toInt() ?? 0,
      elapsedTimeSeconds: (map['elapsedTimeSeconds'] as num?)?.toInt() ?? 0,
      source: ActivitySource.fromValue(map['source'] as String?),
      sourceActivityId: map['sourceActivityId'] as String?,
      recordingDevice: map['recordingDevice'] as String?,
      averageHeartRate: (map['averageHeartRate'] as num?)?.toDouble(),
      averageCadence: (map['averageCadence'] as num?)?.toDouble(),
      elevationGainMeters: (map['elevationGainMeters'] as num?)?.toDouble(),
      polyline: map['polyline'] as String?,
      routePoints: rawRoutePoints
          .whereType<Map<String, dynamic>>()
          .map(RoutePoint.fromMap)
          .toList(),
      hydrated: map['hydrated'] as bool? ?? false,
      schemaVersion: (map['schemaVersion'] as num?)?.toInt() ?? 1,
    );
  }

  final String id;
  final String name;
  final ActivityKind kind;
  final DateTime startedAt;
  final double distanceMeters;
  final int movingTimeSeconds;
  final int elapsedTimeSeconds;
  final ActivitySource source;
  final String? sourceActivityId;
  final String? recordingDevice;
  final double? averageHeartRate;
  final double? averageCadence;
  final double? elevationGainMeters;
  final String? polyline;
  final List<RoutePoint> routePoints;
  final bool hydrated;
  final int schemaVersion;

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

  Map<String, dynamic> toMap() {
    return {
      'weeklyDistanceMeters': weeklyDistanceMeters,
      'monthlyDistanceMeters': monthlyDistanceMeters,
    };
  }
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
