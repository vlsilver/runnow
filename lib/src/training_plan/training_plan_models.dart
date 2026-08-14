import 'package:flutter/widgets.dart';

import '../theme_tokens.dart';

/// Loại bài trong giáo án. Mỗi loại có 1 màu (ngũ hành) + glyph riêng để liếc
/// là biết cường độ — xem [workoutTypeColor] / [WorkoutGlyph].
enum WorkoutType { easy, long, tempo, interval, rest, race }

WorkoutType workoutTypeFromValue(String? v) => switch (v) {
  'easy' => WorkoutType.easy,
  'long' => WorkoutType.long,
  'tempo' => WorkoutType.tempo,
  'interval' => WorkoutType.interval,
  'rest' => WorkoutType.rest,
  'race' => WorkoutType.race,
  _ => WorkoutType.easy,
};

extension WorkoutTypeInfo on WorkoutType {
  String get value => name;

  /// Tên tiếng Việt + hành ngũ hành (dùng ở pill sheet chi tiết).
  String get label => switch (this) {
    WorkoutType.easy => 'Chạy nhẹ',
    WorkoutType.long => 'Chạy dài',
    WorkoutType.tempo => 'Chạy nhịp',
    WorkoutType.interval => 'Biến tốc',
    WorkoutType.rest => 'Nghỉ',
    WorkoutType.race => 'Về đích',
  };

  String get element => switch (this) {
    WorkoutType.easy => 'Mộc',
    WorkoutType.long => 'Thuỷ',
    WorkoutType.tempo => 'Thổ',
    WorkoutType.interval => 'Hoả',
    WorkoutType.rest => 'Kim',
    WorkoutType.race => 'Hoả',
  };

  bool get isRest => this == WorkoutType.rest;

  /// Card "nặng" (interval/long/race) có wash gradient + viền màu type; nhẹ
  /// (easy/tempo) nền đặc mảnh; rest viền dashed.
  bool get isHeavy =>
      this == WorkoutType.interval ||
      this == WorkoutType.long ||
      this == WorkoutType.race;
}

/// Màu loại bài theo bảng ngũ hành trong design handoff (cố định, KHÔNG theo
/// accent người dùng chọn — nó mã hoá cường độ bài tập).
Color workoutTypeColor(WorkoutType type, {required bool dark}) {
  switch (type) {
    case WorkoutType.easy:
      return dark ? RunNowDataColors.coachEasyDark : RunNowDataColors.coachEasyLight;
    case WorkoutType.long:
      return dark ? RunNowDataColors.coachLongDark : RunNowDataColors.coachLongLight;
    case WorkoutType.tempo:
      return dark ? RunNowDataColors.coachTempoDark : RunNowDataColors.coachTempoLight;
    case WorkoutType.interval:
      return dark
          ? RunNowDataColors.coachIntervalDark
          : RunNowDataColors.coachIntervalLight;
    case WorkoutType.rest:
      return dark ? RunNowDataColors.coachRestDark : RunNowDataColors.coachRestLight;
    case WorkoutType.race:
      return dark ? RunNowDataColors.coachRaceDark : RunNowDataColors.coachRaceLight;
  }
}

/// Một ngày trong giáo án. `date` suy ra từ [TrainingPlan.startDate] + vị trí
/// trong danh sách, không lưu riêng.
class TrainingDay {
  const TrainingDay({
    required this.week,
    required this.label,
    required this.type,
    required this.title,
    required this.date,
    this.distanceKm,
    this.detail,
    this.paceHint,
    this.note,
    this.done = false,
    this.matchedActivityId,
  });

  final int week;
  final String label; // "Thứ 2"
  final WorkoutType type;
  final String title;
  final DateTime date; // ngày lịch thật (startDate + index)
  final double? distanceKm;
  final String? detail; // "5×400m nghỉ 90s"
  final String? paceHint; // "6:15"
  final String? note; // lời khuyên HLV
  final bool done;
  final String? matchedActivityId;

  bool get isRest => type.isRest;

  factory TrainingDay.fromMap(
    Map<String, dynamic> map, {
    required DateTime date,
  }) => TrainingDay(
    week: (map['week'] as num?)?.toInt() ?? 1,
    label: map['label'] as String? ?? '',
    type: workoutTypeFromValue(map['type'] as String?),
    title: map['title'] as String? ?? '',
    date: date,
    distanceKm: (map['distanceKm'] as num?)?.toDouble(),
    detail: map['detail'] as String?,
    paceHint: map['paceHint'] as String?,
    note: map['note'] as String?,
    done: map['done'] as bool? ?? false,
    matchedActivityId: map['matchedActivityId'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'week': week,
    'label': label,
    'type': type.value,
    'title': title,
    if (distanceKm != null) 'distanceKm': distanceKm,
    if (detail != null) 'detail': detail,
    if (paceHint != null) 'paceHint': paceHint,
    if (note != null) 'note': note,
    'done': done,
    if (matchedActivityId != null) 'matchedActivityId': matchedActivityId,
  };

  TrainingDay copyWith({bool? done, String? matchedActivityId}) => TrainingDay(
    week: week,
    label: label,
    type: type,
    title: title,
    date: date,
    distanceKm: distanceKm,
    detail: detail,
    paceHint: paceHint,
    note: note,
    done: done ?? this.done,
    matchedActivityId: matchedActivityId ?? this.matchedActivityId,
  );
}

/// Coach tự đánh giá mục tiêu so với nền hiện tại của runner. Hiện ở màn xác
/// nhận để user biết mình sắp cam kết cái gì.
enum PlanFeasibility { comfortable, challenging, tooHard, unknown }

PlanFeasibility feasibilityFromValue(String? v) => switch (v) {
  'vừa sức' => PlanFeasibility.comfortable,
  'thử thách' => PlanFeasibility.challenging,
  'quá sức' => PlanFeasibility.tooHard,
  _ => PlanFeasibility.unknown,
};

extension PlanFeasibilityInfo on PlanFeasibility {
  String get label => switch (this) {
    PlanFeasibility.comfortable => 'Vừa sức',
    PlanFeasibility.challenging => 'Thử thách',
    PlanFeasibility.tooHard => 'Quá sức',
    PlanFeasibility.unknown => '',
  };
}

/// Ai thấy được giáo án. `private` = chỉ owner (giáo án cá nhân, như cũ);
/// `club` = hiện thành card trên feed Kèo, ai cũng xem/tham gia được.
enum CoachVisibility {
  private,
  club;

  String get value => this == CoachVisibility.private ? 'private' : 'club';

  /// Mặc định private khi thiếu field — an toàn, không vô tình lộ giáo án cá nhân.
  static CoachVisibility fromValue(String? v) =>
      v == 'club' ? CoachVisibility.club : CoachVisibility.private;

  bool get isPublic => this == CoachVisibility.club;
}

/// Một người theo giáo án. Mỗi người có tiến độ RIÊNG (buổi nào đã tick) — lịch
/// dùng chung, nhưng "đã xong" thì của từng người.
class CoachParticipant {
  const CoachParticipant({
    required this.uid,
    this.doneIndices = const {},
    this.joinedAt,
    this.displayName,
  });

  final String uid;
  final Set<int> doneIndices; // index buổi trong days đã hoàn thành
  final DateTime? joinedAt;
  final String? displayName;

  factory CoachParticipant.fromMap(String uid, Map<String, dynamic> m) {
    // Phòng thủ: 1 doc hỏng (doneIndices sai kiểu) không được làm ném parse rồi
    // đánh sập hiển thị coach cho cả nhóm — kiểu lạ thì coi như rỗng.
    final rawList = m['doneIndices'];
    final raw = rawList is List ? rawList : const [];
    final joined = m['joinedAt'];
    return CoachParticipant(
      uid: uid,
      doneIndices: raw.whereType<num>().map((e) => e.toInt()).toSet(),
      joinedAt: joined is DateTime ? joined : null,
      displayName: (m['displayName'] as String?)?.trim().isEmpty ?? true
          ? null
          : (m['displayName'] as String).trim(),
    );
  }
}

/// Giáo án chạy do AI sinh. UI render động bất kỳ plan nào (số tuần / số buổi
/// thay đổi). Các giá trị dẫn xuất (tổng buổi, đã xong, streak…) tính ở client.
///
/// Từ khi coach chia sẻ được: plan là entity top-level `coachPlans/{ownerUid}`.
/// `days` là LỊCH dùng chung; "đã xong" nằm ở [participants] theo từng người —
/// khi parse với `currentUid`, mỗi [TrainingDay.done] phản ánh tiến độ của
/// riêng người đang xem.
class TrainingPlan {
  const TrainingPlan({
    required this.id,
    required this.goal,
    required this.goalDistanceKm,
    required this.weeks,
    required this.startDate,
    required this.targetDate,
    required this.summary,
    required this.days,
    this.baselineKm,
    this.createdAt,
    this.rationale,
    this.feasibility = PlanFeasibility.unknown,
    this.warnings = const [],
    this.targetPaceSec,
    this.goalTimeSec,
    this.totalKm,
    this.isDraft = false,
    this.ownerUid,
    this.visibility = CoachVisibility.private,
    this.participants = const {},
  });

  final String id;
  final String goal; // "Chạy 10km"
  final double goalDistanceKm;
  final int weeks;
  final DateTime startDate;
  final DateTime targetDate;
  final String summary;
  final List<TrainingDay> days; // weeks*7, mỗi ngày 1 bài
  final double? baselineKm; // nền ban đầu (mốc trái thanh tiến tới đích)
  final DateTime? createdAt; // để app biết plan MỚI vừa được sinh

  /// Vì sao coach dựng lịch như thế này — 2–4 câu, user đọc trước khi xác nhận.
  final String? rationale;
  final PlanFeasibility feasibility;

  /// Những điều cần biết trước khi bắt đầu: mục tiêu đã bị hạ, khối lượng nhảy
  /// hơn mức an toàn, dữ liệu lịch sử quá ít. Rỗng = không có gì đáng lo.
  final List<String> warnings;

  /// Pace giáo án nhắm tới, giây/km. Có thể THẤP HƠN con số user đòi khi coach
  /// hạ mục tiêu vì quá sức — khi đó warnings sẽ nói rõ.
  final int? targetPaceSec;
  final int? goalTimeSec; // thời gian đích user nêu, giây
  final double? totalKm; // tổng km cả giáo án

  /// true = bản nháp chờ xác nhận (coach/draft), chưa phải giáo án đang chạy.
  final bool isDraft;

  /// Chủ giáo án (trưởng nhóm) — chỉ người này sửa được lịch. null với bản nháp.
  final String? ownerUid;

  /// private = giáo án cá nhân; club = hiện trên feed Kèo cho mọi người tham gia.
  final CoachVisibility visibility;

  /// Những người đang theo giáo án, kèm tiến độ riêng. Key = uid.
  final Map<String, CoachParticipant> participants;

  bool isOwner(String? uid) => uid != null && uid == ownerUid;
  bool hasJoined(String? uid) => uid != null && participants.containsKey(uid);
  int get participantCount => participants.length;

  /// Tiến độ (buổi đã xong) của một người trong nhóm.
  CoachParticipant? progressOf(String? uid) =>
      uid == null ? null : participants[uid];

  String? get targetPaceLabel {
    final p = targetPaceSec;
    if (p == null || p <= 0) return null;
    return '${p ~/ 60}:${(p % 60).toString().padLeft(2, '0')}/km';
  }

  String? get goalTimeLabel {
    final t = goalTimeSec;
    if (t == null || t <= 0) return null;
    final h = t ~/ 3600, m = (t % 3600) ~/ 60;
    return h > 0 ? '${h}h${m.toString().padLeft(2, '0')}' : '$m phút';
  }

  int get totalSessions => days.where((d) => !d.isRest).length;
  int get doneSessions => days.where((d) => d.done).length;
  bool get completed => totalSessions > 0 && doneSessions >= totalSessions;

  int daysLeft(DateTime today) {
    final t = DateTime(today.year, today.month, today.day);
    final end = DateTime(targetDate.year, targetDate.month, targetDate.day);
    final d = end.difference(t).inDays;
    return d < 0 ? 0 : d;
  }

  int currentWeek(DateTime today) {
    for (final d in days) {
      if (_sameDay(d.date, today)) return d.week;
    }
    // Ngoài khoảng: trước start → tuần 1, sau target → tuần cuối.
    if (today.isBefore(startDate)) return 1;
    return weeks;
  }

  /// Số buổi (không tính rest) liên tiếp gần nhất đã done — tính từ cuối chuỗi
  /// các buổi đã tới ngày, lùi về.
  int streak(DateTime today) {
    final past = days
        .where((d) => !d.isRest && !d.date.isAfter(today))
        .toList();
    var s = 0;
    for (var i = past.length - 1; i >= 0; i--) {
      if (past[i].done) {
        s++;
      } else {
        break;
      }
    }
    return s;
  }

  /// Cự ly dài nhất trong các buổi đã done — cho thanh tiến tới đích.
  double get longestDoneKm {
    double m = 0;
    for (final d in days) {
      if (d.done && (d.distanceKm ?? 0) > m) m = d.distanceKm!;
    }
    return m;
  }

  double weekKm(int week) => days
      .where((d) => d.week == week)
      .fold<double>(0, (s, d) => s + (d.distanceKm ?? 0));

  TrainingDay? todaySession(DateTime today) {
    for (final d in days) {
      if (_sameDay(d.date, today) && !d.isRest) return d;
    }
    return null;
  }

  List<TrainingDay> daysOfWeek(int week) =>
      days.where((d) => d.week == week).toList();

  factory TrainingPlan.fromMap(
    String id,
    Map<String, dynamic> map, {
    DateTime? createdAt,
    String? currentUid,
  }) {
    final start = DateTime.parse(map['startDate'] as String);
    final rawDays = (map['days'] as List?) ?? const [];
    final participants = _parseParticipants(map['participants']);
    // "Đã xong" là của TỪNG người: nếu biết người đang xem, done mỗi buổi lấy từ
    // doneIndices của họ; nếu không (bản nháp/template) rơi về cờ done trong days.
    final mine = currentUid == null ? null : participants[currentUid];
    final days = <TrainingDay>[];
    for (var i = 0; i < rawDays.length; i++) {
      final m = rawDays[i];
      if (m is Map<String, dynamic>) {
        var day = TrainingDay.fromMap(m, date: start.add(Duration(days: i)));
        if (mine != null) day = day.copyWith(done: mine.doneIndices.contains(i));
        days.add(day);
      }
    }
    return TrainingPlan(
      id: id,
      ownerUid: map['ownerUid'] as String?,
      visibility: CoachVisibility.fromValue(map['visibility'] as String?),
      participants: participants,
      goal: map['goal'] as String? ?? '',
      goalDistanceKm: (map['goalDistanceKm'] as num?)?.toDouble() ?? 0,
      weeks: (map['weeks'] as num?)?.toInt() ?? (days.length / 7).ceil(),
      startDate: start,
      targetDate: DateTime.parse(map['targetDate'] as String),
      summary: map['summary'] as String? ?? '',
      days: days,
      baselineKm: (map['baselineKm'] as num?)?.toDouble(),
      createdAt: createdAt,
      rationale: (map['rationale'] as String?)?.trim().isEmpty ?? true
          ? null
          : (map['rationale'] as String).trim(),
      feasibility: feasibilityFromValue(map['feasibility'] as String?),
      warnings:
          (map['warnings'] as List?)?.whereType<String>().toList() ?? const [],
      targetPaceSec: (map['targetPaceSec'] as num?)?.toInt(),
      goalTimeSec: (map['goalTimeSec'] as num?)?.toInt(),
      totalKm: (map['totalKm'] as num?)?.toDouble(),
      isDraft: map['status'] == 'draft',
    );
  }

  Map<String, dynamic> toMap() => {
    'goal': goal,
    'goalDistanceKm': goalDistanceKm,
    'weeks': weeks,
    'startDate': _dateKey(startDate),
    'targetDate': _dateKey(targetDate),
    'summary': summary,
    if (baselineKm != null) 'baselineKm': baselineKm,
    'days': days.map((d) => d.toMap()).toList(),
    if (ownerUid != null) 'ownerUid': ownerUid,
    'visibility': visibility.value,
  };
}

Map<String, CoachParticipant> _parseParticipants(dynamic raw) {
  if (raw is! Map) return const {};
  final out = <String, CoachParticipant>{};
  raw.forEach((k, v) {
    if (k is String && v is Map) {
      out[k] = CoachParticipant.fromMap(k, Map<String, dynamic>.from(v));
    }
  });
  return out;
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
