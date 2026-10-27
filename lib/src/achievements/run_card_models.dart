/// Model thẻ buổi chạy, khớp JSON của /v1/activities/{id}/card* và doc
/// users/{uid}/runCards/{activityId}. Đọc từ Firestore thì provider đổi
/// Timestamp sang DateTime trước khi parse.
library;

import 'package:latlong2/latlong.dart' show LatLng;
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/theme.dart' show RunNowElement;

String _string(Object? value) => value is String ? value : '';

String? _optString(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int _int(Object? value) => value is num ? value.toInt() : 0;

double _double(Object? value) => value is num ? value.toDouble() : 0;

double? _optDouble(Object? value) => value is num ? value.toDouble() : null;

DateTime? _date(Object? value) => switch (value) {
  final DateTime d => d,
  final String s => DateTime.tryParse(s),
  _ => null,
};

List<T> _list<T>(Object? value, T Function(Map<String, dynamic>) parse) => [
  if (value is List)
    for (final item in value)
      if (item is Map) parse(Map<String, dynamic>.from(item)),
];

Map<String, dynamic>? _map(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

/// Khoá bậc của server. Khoá lạ (server mới thêm bậc) thì hiện như Thường.
GameCardTier runCardTierFromKey(String? key) => switch (key) {
  'rare' => GameCardTier.rare,
  'epic' => GameCardTier.superRare,
  'legendary' => GameCardTier.legendary,
  'mythic' => GameCardTier.mythic,
  _ => GameCardTier.common,
};

/// Bản Ẩn của thẻ: cả thẻ một màu theo một hành. Backend ghi
/// `secret.<hành>`; giá trị lạ (server mới thêm bản khác) thì coi như thẻ
/// thường.
RunNowElement? runCardSecretFromKey(String? key) {
  if (key == null || !key.startsWith('secret.')) return null;
  return RunNowElement.values.asNameMap()[key.substring('secret.'.length)];
}

class RunCardOdd {
  const RunCardOdd({required this.tier, required this.percent});

  factory RunCardOdd.fromJson(Map<String, dynamic> json) => RunCardOdd(
    tier: runCardTierFromKey(_optString(json['tier'])),
    percent: _double(json['percent']),
  );

  final GameCardTier tier;
  final double percent;
}

class RunCardSplit {
  const RunCardSplit({
    required this.distanceMeters,
    required this.movingTimeSeconds,
  });

  factory RunCardSplit.fromJson(Map<String, dynamic> json) => RunCardSplit(
    distanceMeters: _double(json['distanceMeters']),
    movingTimeSeconds: _double(json['movingTimeSeconds']),
  );

  final double distanceMeters;
  final double movingTimeSeconds;

  double get paceSecondsPerKm => movingTimeSeconds / (distanceMeters / 1000);
}

/// Số liệu buổi chạy chụp lại lúc lật, để thẻ còn nguyên khi buổi bị xoá hay
/// sửa sau đó.
class RunCardSnapshot {
  const RunCardSnapshot({
    required this.name,
    required this.sportType,
    required this.distanceMeters,
    required this.movingTimeSeconds,
    required this.elapsedTimeSeconds,
    required this.route,
    required this.splits,
    this.startedAt,
    this.elevationGainMeters,
    this.averageHeartRate,
  });

  factory RunCardSnapshot.fromJson(Map<String, dynamic> json) =>
      RunCardSnapshot(
        name: _string(json['name']),
        sportType: _string(json['sportType']),
        startedAt: _date(json['startedAt']),
        distanceMeters: _double(json['distanceMeters']),
        movingTimeSeconds: _int(json['movingTimeSeconds']),
        elapsedTimeSeconds: _int(json['elapsedTimeSeconds']),
        elevationGainMeters: _optDouble(json['elevationGainMeters']),
        averageHeartRate: _optDouble(json['averageHeartRate']),
        route: [
          if (json['route'] case final List points)
            for (final p in points)
              if (p case {'lat': final num lat, 'lng': final num lng})
                LatLng(lat.toDouble(), lng.toDouble()),
        ],
        splits: _list(json['splits'], RunCardSplit.fromJson),
      );

  final String name;
  final String sportType;
  final DateTime? startedAt;
  final double distanceMeters;
  final int movingTimeSeconds;
  final int elapsedTimeSeconds;
  final double? elevationGainMeters;
  final double? averageHeartRate;

  /// Tối đa 80 điểm; rỗng khi buổi không có GPS.
  final List<LatLng> route;
  final List<RunCardSplit> splits;
}

enum RunCardArtStatus { drawing, done, failed }

/// Tranh nền của thẻ. Vẽ xong (`done`) thì phong cách và tranh cố định.
class RunCardArt {
  const RunCardArt({
    required this.status,
    required this.style,
    required this.attempt,
    this.path,
    this.reason,
    this.photoPath,
    this.note,
    this.requestedAt,
  });

  factory RunCardArt.fromJson(Map<String, dynamic> json) => RunCardArt(
    status: switch (json['status']) {
      'done' => RunCardArtStatus.done,
      'drawing' => RunCardArtStatus.drawing,
      _ => RunCardArtStatus.failed,
    },
    style: _string(json['style']),
    attempt: _int(json['attempt']),
    path: _optString(json['path']),
    reason: _optString(json['reason']),
    photoPath: _optString(json['photoPath']),
    note: _optString(json['note']),
    requestedAt: _date(json['requestedAt']),
  );

  final RunCardArtStatus status;
  final String style;
  final int attempt;

  /// Đường dẫn Storage của tranh, chỉ có khi `done`.
  final String? path;

  /// Vì sao lần vẽ hỏng: blocked, budget, model_error, photo_missing,
  /// style_unavailable.
  final String? reason;
  final String? photoPath;

  /// Mô tả thêm chủ thẻ gõ khi chọn vẽ, cố định cùng tranh.
  final String? note;
  final DateTime? requestedAt;
}

class RunCard {
  const RunCard({
    required this.id,
    required this.tier,
    required this.km,
    required this.odds,
    required this.snapshot,
    this.rolledAt,
    this.art,
    this.secret,
  });

  factory RunCard.fromJson(Map<String, dynamic> json) => RunCard(
    id: _string(json['id']),
    tier: runCardTierFromKey(_optString(json['tier'])),
    km: _double(json['km']),
    odds: _list(json['odds'], RunCardOdd.fromJson),
    rolledAt: _date(json['rolledAt']),
    snapshot: RunCardSnapshot.fromJson(_map(json['snapshot']) ?? const {}),
    art: switch (_map(json['art'])) {
      final art? => RunCardArt.fromJson(art),
      null => null,
    },
    secret: runCardSecretFromKey(_optString(json['variant'])),
  );

  /// Trùng id buổi chạy.
  final String id;
  final GameCardTier tier;

  /// Số km in trên thẻ, server đã làm tròn 0,1.
  final double km;

  /// Tỉ lệ đã dùng lúc quay, để thẻ tự giải thích độ hiếm.
  final List<RunCardOdd> odds;
  final DateTime? rolledAt;
  final RunCardSnapshot snapshot;
  final RunCardArt? art;

  /// Hành của bản Ẩn, null là thẻ thường.
  final RunNowElement? secret;

  /// Tranh đã vẽ xong, null khi chưa có.
  String? get artPath =>
      art?.status == RunCardArtStatus.done ? art?.path : null;
}

/// Trả lời GET thẻ: [card] khi đã lật; chưa lật thì [odds] là tỉ lệ sẽ quay,
/// hoặc [reason] (`card_not_eligible`, `card_duplicate`) khi không lật được.
class RunCardView {
  const RunCardView({
    this.card,
    this.odds = const [],
    this.chance = 100,
    this.reason,
  });

  factory RunCardView.fromJson(Map<String, dynamic> json) => RunCardView(
    card: switch (_map(json['card'])) {
      final card? => RunCard.fromJson(card),
      null => null,
    },
    odds: _list(json['odds'], RunCardOdd.fromJson),
    chance: _optDouble(json['chance']) ?? 100,
    reason: _optString(json['reason']),
  );

  final RunCard? card;

  /// Tỉ lệ từng bậc khi lật ra thẻ.
  final List<RunCardOdd> odds;

  /// Phần trăm cơ hội lật ra thẻ; dưới 100 thì có thể trượt. Backend cũ không
  /// gửi field này, khi đó lật luôn ra thẻ.
  final double chance;
  final String? reason;
}

class ArtStyleFamily {
  const ArtStyleFamily({required this.key, required this.label});

  factory ArtStyleFamily.fromJson(Map<String, dynamic> json) =>
      ArtStyleFamily(key: _string(json['key']), label: _string(json['label']));

  final String key;
  final String label;
}

class ArtStyle {
  const ArtStyle({
    required this.key,
    required this.name,
    required this.family,
    required this.swatch,
    this.example,
  });

  factory ArtStyle.fromJson(Map<String, dynamic> json) => ArtStyle(
    key: _string(json['key']),
    name: _string(json['name']),
    family: _string(json['family']),
    swatch: [
      if (json['swatch'] case final List hexes)
        for (final hex in hexes)
          if (hex is String) hex,
    ],
    example: switch (json['example']) {
      final String path when path.isNotEmpty => path,
      _ => null,
    },
  );

  final String key;
  final String name;
  final String family;

  /// Ba màu đại diện dạng `#rrggbb`, cho ô xem trước.
  final List<String> swatch;

  /// Đường dẫn Storage của ảnh mẫu; null thì ô chỉ có màu [swatch].
  final String? example;
}

class ArtStyleList {
  const ArtStyleList({required this.families, required this.styles});

  factory ArtStyleList.fromJson(Map<String, dynamic> json) => ArtStyleList(
    families: _list(json['families'], ArtStyleFamily.fromJson),
    styles: _list(json['styles'], ArtStyle.fromJson),
  );

  final List<ArtStyleFamily> families;
  final List<ArtStyle> styles;
}
