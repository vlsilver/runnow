enum RunContractMetric {
  distance('distance'),
  activityCount('activity_count'),
  activeDays('active_days'),
  longestRun('longest_run'),
  routeCompletion('route_completion');

  const RunContractMetric(this.value);
  final String value;

  static RunContractMetric fromValue(String? value) => switch (value) {
    'activity_count' => RunContractMetric.activityCount,
    'active_days' => RunContractMetric.activeDays,
    'longest_run' => RunContractMetric.longestRun,
    'route_completion' => RunContractMetric.routeCompletion,
    _ => RunContractMetric.distance,
  };
}

/// Chế độ của KÈO HÀNH TRÌNH (kèo tích luỹ km dọc 1 cung đường có thật):
/// - [individual]: mỗi người tích km riêng, xếp hạng ai đi xa nhất.
/// - [team]: cả nhóm gộp km đẩy 1 marker về đích, hiện % đóng góp.
/// Kèo thường (không phải hành trình) mặc định [individual] và bỏ qua field này.
enum RunContractMode {
  individual('individual'),
  team('team');

  const RunContractMode(this.value);
  final String value;

  static RunContractMode fromValue(String? value) =>
      value == 'team' ? RunContractMode.team : RunContractMode.individual;
}

/// 1 điểm mốc trên tuyến tham khảo do người tạo kèo vẽ — chỉ cần toạ độ,
/// khác [RoutePoint] (dùng cho GPS đã ghi thật) vốn bắt buộc có timestamp.
class RunContractRoutePoint {
  const RunContractRoutePoint({
    required this.latitude,
    required this.longitude,
  });

  factory RunContractRoutePoint.fromMap(Map<String, dynamic> map) =>
      RunContractRoutePoint(
        latitude: (map['lat'] as num).toDouble(),
        longitude: (map['lng'] as num).toDouble(),
      );

  final double latitude;
  final double longitude;

  Map<String, dynamic> toMap() => {'lat': latitude, 'lng': longitude};
}

/// Tuyến tham khảo của 1 kèo "theo tuyến" — người tham gia phải chạy bám
/// theo tuyến này (xem `route_matching.dart`) để được tính tiến độ.
class RunContractRoute {
  const RunContractRoute({required this.points, required this.distanceMeters});

  factory RunContractRoute.fromMap(Map<String, dynamic> map) {
    final rawPoints = map['points'] as List<dynamic>? ?? const [];
    return RunContractRoute(
      points: rawPoints
          .whereType<Map<String, dynamic>>()
          .map(RunContractRoutePoint.fromMap)
          .toList(),
      distanceMeters: (map['distanceMeters'] as num?)?.toDouble() ?? 0,
    );
  }

  final List<RunContractRoutePoint> points;
  final double distanceMeters;

  Map<String, dynamic> toMap() => {
    'points': [for (final point in points) point.toMap()],
    'distanceMeters': distanceMeters,
  };
}

enum RunContractPeriodType {
  weekly('weekly'),
  today('today'),
  tomorrow('tomorrow'),
  custom('custom');

  const RunContractPeriodType(this.value);
  final String value;

  static RunContractPeriodType fromValue(String? value) => switch (value) {
    'today' => RunContractPeriodType.today,
    'tomorrow' => RunContractPeriodType.tomorrow,
    'custom' => RunContractPeriodType.custom,
    _ => RunContractPeriodType.weekly,
  };
}

enum RunContractStatus {
  active('active'),
  completed('completed'),
  failed('failed'),
  cancelled('cancelled');

  const RunContractStatus(this.value);
  final String value;

  static RunContractStatus fromValue(String? value) => switch (value) {
    'completed' => RunContractStatus.completed,
    'failed' => RunContractStatus.failed,
    'cancelled' => RunContractStatus.cancelled,
    _ => RunContractStatus.active,
  };
}

enum RunContractVisibility {
  private('private'),
  club('club');

  const RunContractVisibility(this.value);
  final String value;

  static RunContractVisibility fromValue(String? value) => value == 'private'
      ? RunContractVisibility.private
      : RunContractVisibility.club;
}

enum RunContractTemplate {
  weekly10k('weekly_10k'),
  weekly3Runs('weekly_3_runs'),
  today2k('today_2k'),
  custom('custom');

  const RunContractTemplate(this.value);
  final String value;

  static RunContractTemplate fromValue(String? value) => switch (value) {
    'weekly_10k' => RunContractTemplate.weekly10k,
    'weekly_3_runs' => RunContractTemplate.weekly3Runs,
    'today_2k' => RunContractTemplate.today2k,
    _ => RunContractTemplate.custom,
  };
}

class RunContractPeriod {
  const RunContractPeriod({
    required this.type,
    required this.startAt,
    required this.endAtExclusive,
    required this.finalizeAt,
  });

  final RunContractPeriodType type;
  final DateTime startAt;
  final DateTime endAtExclusive;
  final DateTime finalizeAt;
}

class RunContractDraft {
  const RunContractDraft({
    required this.template,
    required this.metric,
    required this.targetValue,
    required this.period,
    required this.visibility,
    this.title,
    this.customStart,
    this.customEnd,
    this.route,
    this.unlimitedRepeat = false,
    this.journeyRouteId,
    this.mode = RunContractMode.individual,
    this.openEnded = false,
  });

  factory RunContractDraft.weekly10k() => RunContractDraft(
    template: RunContractTemplate.weekly10k,
    metric: RunContractMetric.distance,
    targetValue: 10,
    period: RunContractPeriodType.weekly,
    visibility: RunContractVisibility.club,
  );

  final RunContractTemplate template;
  final RunContractMetric metric;
  final double targetValue;
  final RunContractPeriodType period;
  final RunContractVisibility visibility;

  /// Tên kèo ngắn do người dùng đặt (5–10 từ). Bỏ trống thì sinh tự động.
  final String? title;

  /// Thời điểm bắt đầu/kết thúc tùy chọn (giờ địa phương) khi
  /// [period] == [RunContractPeriodType.custom]. Các khung cố định bỏ trống.
  final DateTime? customStart;
  final DateTime? customEnd;

  /// Tuyến tham khảo — bắt buộc khi [metric] == [RunContractMetric.routeCompletion].
  final RunContractRoute? route;

  /// Không giới hạn số lần hoàn thành tuyến được đếm dồn — [targetValue] vẫn
  /// giữ nguyên (thường là 1) để logic "đạt mục tiêu" hiện có hoạt động bình
  /// thường, cờ này chỉ đổi cách hiển thị.
  final bool unlimitedRepeat;

  /// Kèo hành trình: cung đường + chế độ + có/không thời hạn (xem [RunContract]).
  /// [journeyRouteId] dành cho tương lai (chọn cung từ kho seed sẵn); hiện tại
  /// hành trình dùng cung TỰ VẼ nhúng thẳng vào [route], nên marker là
  /// [isJourney] = có route + đếm theo quãng đường tích luỹ.
  final String? journeyRouteId;
  final RunContractMode mode;
  final bool openEnded;

  bool get isJourney =>
      route != null && metric == RunContractMetric.distance;

  RunContractDraft copyWith({
    RunContractTemplate? template,
    RunContractMetric? metric,
    double? targetValue,
    RunContractPeriodType? period,
    RunContractVisibility? visibility,
    String? title,
    DateTime? customStart,
    DateTime? customEnd,
    RunContractRoute? route,
    bool? unlimitedRepeat,
    String? journeyRouteId,
    RunContractMode? mode,
    bool? openEnded,
  }) => RunContractDraft(
    template: template ?? this.template,
    metric: metric ?? this.metric,
    targetValue: targetValue ?? this.targetValue,
    period: period ?? this.period,
    visibility: visibility ?? this.visibility,
    title: title ?? this.title,
    customStart: customStart ?? this.customStart,
    customEnd: customEnd ?? this.customEnd,
    route: route ?? this.route,
    unlimitedRepeat: unlimitedRepeat ?? this.unlimitedRepeat,
    journeyRouteId: journeyRouteId ?? this.journeyRouteId,
    mode: mode ?? this.mode,
    openEnded: openEnded ?? this.openEnded,
  );

  /// Số ngày active tối đa cho phép tùy theo khung thời gian.
  int get maxActiveDays => switch (period) {
    RunContractPeriodType.weekly => 7,
    RunContractPeriodType.custom =>
      (customStart != null && customEnd != null)
          ? (customEnd!.difference(customStart!).inMinutes / 1440).ceil().clamp(
              1,
              31,
            )
          : 7,
    _ => 1,
  };

  String? validate() {
    if (!targetValue.isFinite) return 'Mục tiêu không hợp lệ.';
    // Kèo HÀNH TRÌNH: đích = chiều dài cung (rất dài, không áp trần 500km/khung
    // ngày như kèo thường). Thời hạn tùy chọn — openEnded thì bỏ qua period.
    if (isJourney) {
      if (targetValue < 0.2) return 'Cung đường quá ngắn.';
      if (!openEnded && period == RunContractPeriodType.custom) {
        if (customStart == null || customEnd == null) {
          return 'Hãy chọn thời gian bắt đầu và kết thúc.';
        }
        if (!customEnd!.isAfter(customStart!)) {
          return 'Thời gian kết thúc phải sau thời gian bắt đầu.';
        }
      }
      return null;
    }
    if (period == RunContractPeriodType.custom) {
      if (customStart == null || customEnd == null) {
        return 'Hãy chọn thời gian bắt đầu và kết thúc.';
      }
      if (!customEnd!.isAfter(customStart!)) {
        return 'Thời gian kết thúc phải sau thời gian bắt đầu.';
      }
    }
    final maxDays = maxActiveDays;
    return switch (metric) {
      RunContractMetric.distance when targetValue < 0.1 || targetValue > 500 =>
        'Mục tiêu quãng đường phải từ 0.1 đến 500 km.',
      RunContractMetric.longestRun
          when targetValue < 0.1 || targetValue > 500 =>
        'Quãng đường dài nhất phải từ 0.1 đến 500 km.',
      RunContractMetric.activityCount
          when targetValue != targetValue.roundToDouble() ||
              targetValue < 1 ||
              targetValue > 100 =>
        'Số buổi phải là số nguyên từ 1 đến 100.',
      RunContractMetric.activeDays
          when targetValue != targetValue.roundToDouble() ||
              targetValue < 1 ||
              targetValue > maxDays =>
        maxDays == 1
            ? 'Kèo trong ngày chỉ có thể đặt 1 ngày active.'
            : 'Số ngày active phải từ 1 đến $maxDays.',
      RunContractMetric.routeCompletion when route == null =>
        'Hãy vẽ tuyến tham khảo trước.',
      RunContractMetric.routeCompletion when route!.points.length < 2 =>
        'Tuyến tham khảo cần ít nhất 2 điểm mốc.',
      RunContractMetric.routeCompletion
          when route!.distanceMeters < 100 || route!.distanceMeters > 50000 =>
        'Tuyến tham khảo phải dài từ 0.1 đến 50 km.',
      RunContractMetric.routeCompletion
          when targetValue != targetValue.roundToDouble() ||
              targetValue < 1 ||
              targetValue > 100 =>
        'Số lần hoàn thành phải là số nguyên từ 1 đến 100.',
      _ => null,
    };
  }
}

class RunContractParticipant {
  const RunContractParticipant({
    required this.uid,
    required this.progressValue,
    required this.joinedAt,
    required this.updatedAt,
    this.countedActivityIds = const [],
  });

  factory RunContractParticipant.fromMap(
    String uid,
    Map<String, dynamic> map,
  ) => RunContractParticipant(
    uid: uid,
    progressValue: (map['progressValue'] as num?)?.toDouble() ?? 0,
    joinedAt: _date(map['joinedAt']),
    updatedAt: _date(map['updatedAt']),
    countedActivityIds:
        (map['countedActivityIds'] as List?)?.whereType<String>().toList() ??
        const [],
  );

  final String uid;
  final double progressValue;
  final DateTime joinedAt;
  final DateTime updatedAt;

  /// Cache các activity Strava user đã chủ động gán vào kèo này. Claim document
  /// dưới user mới là nguồn sự thật chống một session thuộc nhiều kèo.
  final List<String> countedActivityIds;
}

class RunContract {
  const RunContract({
    required this.id,
    required this.creatorUid,
    required this.title,
    required this.template,
    required this.metric,
    required this.targetValue,
    required this.periodType,
    required this.startAt,
    required this.endAtExclusive,
    required this.finalizeAt,
    required this.status,
    required this.visibility,
    required this.progressValue,
    required this.createdAt,
    required this.updatedAt,
    this.lastCalculatedAt,
    this.completedAt,
    this.failedAt,
    this.cancelledAt,
    this.participants = const {},
    this.schemaVersion = 1,
    this.route,
    this.unlimitedRepeat = false,
    this.journeyRouteId,
    this.mode = RunContractMode.individual,
    this.openEnded = false,
  });

  factory RunContract.fromMap(Map<String, dynamic> map) {
    final creatorUid = map['creatorUid'] as String? ?? '';
    final progressValue = (map['progressValue'] as num?)?.toDouble() ?? 0;
    final createdAt = _date(map['createdAt']);
    final rawParticipants = map['participants'] as Map<String, dynamic>?;
    final participants = <String, RunContractParticipant>{};
    if (rawParticipants != null) {
      for (final entry in rawParticipants.entries) {
        if (entry.value is Map<String, dynamic>) {
          participants[entry.key] = RunContractParticipant.fromMap(
            entry.key,
            entry.value as Map<String, dynamic>,
          );
        }
      }
    }
    // Backward compatibility: contracts created before group participation
    // implicitly contain the creator as their only participant.
    if (participants.isEmpty && creatorUid.isNotEmpty) {
      participants[creatorUid] = RunContractParticipant(
        uid: creatorUid,
        progressValue: progressValue,
        joinedAt: createdAt,
        updatedAt: _nullableDate(map['updatedAt']) ?? createdAt,
      );
    }
    return RunContract(
      id: map['id'] as String? ?? '',
      creatorUid: creatorUid,
      title: map['title'] as String? ?? 'Kèo chạy',
      template: RunContractTemplate.fromValue(map['templateId'] as String?),
      metric: RunContractMetric.fromValue(map['metric'] as String?),
      targetValue: (map['targetValue'] as num?)?.toDouble() ?? 0,
      periodType: RunContractPeriodType.fromValue(map['periodType'] as String?),
      startAt: _date(map['startAt']),
      endAtExclusive: _date(map['endAtExclusive']),
      finalizeAt: _date(map['finalizeAt']),
      status: RunContractStatus.fromValue(map['status'] as String?),
      visibility: RunContractVisibility.fromValue(map['visibility'] as String?),
      progressValue: progressValue,
      participants: participants,
      lastCalculatedAt: _nullableDate(map['lastCalculatedAt']),
      completedAt: _nullableDate(map['completedAt']),
      failedAt: _nullableDate(map['failedAt']),
      cancelledAt: _nullableDate(map['cancelledAt']),
      createdAt: createdAt,
      updatedAt: _date(map['updatedAt']),
      schemaVersion: (map['schemaVersion'] as num?)?.toInt() ?? 1,
      route: map['route'] is Map<String, dynamic>
          ? RunContractRoute.fromMap(map['route'] as Map<String, dynamic>)
          : null,
      unlimitedRepeat: map['unlimitedRepeat'] as bool? ?? false,
      journeyRouteId: (map['journeyRouteId'] as String?)?.isNotEmpty ?? false
          ? map['journeyRouteId'] as String
          : null,
      mode: RunContractMode.fromValue(map['mode'] as String?),
      openEnded: map['openEnded'] as bool? ?? false,
    );
  }

  final String id;
  final int schemaVersion;
  final String creatorUid;
  final String title;
  final RunContractTemplate template;
  final RunContractMetric metric;
  final double targetValue;
  final RunContractPeriodType periodType;
  final DateTime startAt;
  final DateTime endAtExclusive;
  final DateTime finalizeAt;
  final RunContractStatus status;
  final RunContractVisibility visibility;
  final double progressValue;
  final DateTime? lastCalculatedAt;
  final DateTime? completedAt;
  final DateTime? failedAt;
  final DateTime? cancelledAt;
  final Map<String, RunContractParticipant> participants;
  final DateTime createdAt;
  final DateTime updatedAt;
  final RunContractRoute? route;
  final bool unlimitedRepeat;

  /// Dành cho tương lai (chọn cung từ kho seed). Hiện hành trình dùng cung TỰ
  /// VẼ nhúng trong [route] nên field này thường null.
  final String? journeyRouteId;

  /// Chế độ hành trình (chỉ có ý nghĩa khi [isJourney]).
  final RunContractMode mode;

  /// true = kèo KHÔNG thời hạn (chạy tới khi chinh phục/không kết thúc). Khi đó
  /// bỏ qua [endAtExclusive]/[finalizeAt] về mặt hiển thị & finalize.
  final bool openEnded;

  /// Kèo HÀNH TRÌNH = có cung đường ([route]) + đếm theo quãng đường tích luỹ
  /// (km dồn dọc cung tới khi phủ hết chiều dài). Phân biệt với "Theo tuyến"
  /// (metric routeCompletion — phải chạy đúng tuyến).
  bool get isJourney =>
      route != null && metric == RunContractMetric.distance;

  double get progressRatio =>
      targetValue <= 0 ? 0 : progressValue / targetValue;
  double get progressPercent => (progressRatio * 100).clamp(0, 999).toDouble();
  int get participantCount => participants.length;
  double get overallProgressRatio {
    if (participants.isEmpty) return progressRatio.clamp(0.0, 1.0);
    final completed = participants.values.fold<double>(0, (sum, participant) {
      final ratio = targetValue <= 0
          ? 0.0
          : participant.progressValue / targetValue;
      return sum + ratio.clamp(0.0, 1.0);
    });
    return completed / participants.length;
  }

  double get overallProgressPercent => overallProgressRatio * 100;
  RunContractParticipant? participantFor(String? uid) =>
      uid == null ? null : participants[uid];
  bool completedBy(String? uid) =>
      participantFor(uid)?.progressValue != null &&
      participantFor(uid)!.progressValue >= targetValue;
  bool get isActive => status == RunContractStatus.active;
}

DateTime _date(Object? value) =>
    _nullableDate(value) ?? DateTime.fromMillisecondsSinceEpoch(0);

DateTime? _nullableDate(Object? value) {
  if (value is DateTime) return value.toLocal();
  if (value is String) return DateTime.tryParse(value)?.toLocal();
  return null;
}
