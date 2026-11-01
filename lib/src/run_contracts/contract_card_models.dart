/// Model thẻ Kèo, khớp JSON của /v1/contracts/{id}/card.
library;

import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/theme.dart' show RunNowElement;

String _string(Object? value) => value is String ? value : '';

double _double(Object? value) => value is num ? value.toDouble() : 0;

int _int(Object? value) => value is num ? value.toInt() : 0;

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

Map<String, dynamic> _map(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : const {};

List<RunCardOdd> _odds(Object? value) => [
  if (value is List)
    for (final raw in value)
      if (raw is Map) RunCardOdd.fromJson(raw.cast<String, dynamic>()),
];

/// Thông tin và kết quả kèo server chép vào thẻ lúc lật.
class ContractCardSnapshot {
  const ContractCardSnapshot({
    required this.title,
    required this.metric,
    required this.targetValue,
    required this.progressValue,
    required this.participants,
    required this.achievers,
    required this.displayName,
    this.startAt,
    this.endAtExclusive,
  });

  factory ContractCardSnapshot.fromJson(Map<String, dynamic> json) =>
      ContractCardSnapshot(
        title: _string(json['title']),
        metric: RunContractMetric.fromValue(json['metric'] as String?),
        targetValue: _double(json['targetValue']),
        progressValue: _double(json['progressValue']),
        participants: _int(json['participants']),
        achievers: _int(json['achievers']),
        displayName: _string(json['displayName']),
        startAt: _date(json['startAt']),
        endAtExclusive: _date(json['endAtExclusive']),
      );

  final String title;
  final RunContractMetric metric;
  final double targetValue;

  /// Tiến độ của chủ thẻ lúc lật.
  final double progressValue;
  final int participants;

  /// Số người đạt mục tiêu của chính mình.
  final int achievers;
  final String displayName;
  final DateTime? startAt;
  final DateTime? endAtExclusive;
}

class ContractCard {
  const ContractCard({
    required this.contractId,
    required this.tier,
    required this.km,
    required this.odds,
    required this.snapshot,
    this.rolledAt,
    this.secret,
  });

  factory ContractCard.fromJson(Map<String, dynamic> json) => ContractCard(
    contractId: _string(json['contractId']),
    tier: runCardTierFromKey(json['tier'] as String?),
    km: _double(json['km']),
    odds: _odds(json['odds']),
    snapshot: ContractCardSnapshot.fromJson(_map(json['snapshot'])),
    rolledAt: _date(json['rolledAt']),
    secret: runCardSecretFromKey(json['variant'] as String?),
  );

  final String contractId;
  final GameCardTier tier;

  /// Km tích luỹ trong kèo đem tra bảng tỉ lệ, server đã làm tròn 0,1.
  final double km;
  final List<RunCardOdd> odds;
  final ContractCardSnapshot snapshot;
  final DateTime? rolledAt;

  /// Hành của bản Ẩn, null là thẻ thường.
  final RunNowElement? secret;
}

/// Trả lời GET thẻ kèo: [card] khi đã lật; chưa lật thì [odds] theo [km], hoặc
/// [reason] (`card_contract_open`, `card_contract_failed`,
/// `card_contract_cancelled`) khi không lật được.
class ContractCardView {
  const ContractCardView({
    this.card,
    this.odds = const [],
    this.km = 0,
    this.reason,
  });

  factory ContractCardView.fromJson(Map<String, dynamic> json) =>
      ContractCardView(
        card: json['card'] is Map
            ? ContractCard.fromJson(_map(json['card']))
            : null,
        odds: _odds(json['odds']),
        km: _double(json['km']),
        reason: json['reason'] as String?,
      );

  final ContractCard? card;
  final List<RunCardOdd> odds;
  final double km;
  final String? reason;
}
