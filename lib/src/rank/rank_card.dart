import 'package:flutter/widgets.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/card_share.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/club_ranking.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/rank/rank_card_art.dart';
import 'package:myrun/src/steps_format.dart';

ClubRankingRange? _rangeFrom(Object? key) => switch (key) {
  'week' => ClubRankingRange.currentWeek,
  'month' => ClubRankingRange.currentMonth,
  _ => null,
};

ClubRankingSport? _sportFrom(Object? key) {
  for (final sport in ClubRankingSport.values) {
    if (sport.name == key) return sport;
  }
  return null;
}

/// Ngày "2026-10-19" thành DateTime UTC 00:00 như [PastRankingPeriod].
DateTime? _day(Object? key) =>
    key is String ? DateTime.tryParse('${key}T00:00:00Z') : null;

double _num(Object? value) => (value as num?)?.toDouble() ?? 0;

/// Một người trong top 10 đã chốt, theo thứ tự hạng.
class RankBoardEntry {
  const RankBoardEntry({
    required this.uid,
    required this.rank,
    required this.displayName,
    required this.score,
    this.avatarUrl,
  });

  final String uid;
  final int rank;
  final String displayName;
  final String? avatarUrl;

  /// Mét với Chạy/Đi bộ và Đạp xe, số bước với Bước chân.
  final double score;
}

/// Bảng đã chốt ở rankBoards/{id}; backend ghi một lần lúc chốt kỳ.
class RankBoard {
  const RankBoard({required this.participants, required this.entries});

  factory RankBoard.fromJson(Map<String, dynamic> json) => RankBoard(
    participants: (json['participants'] as num?)?.toInt() ?? 0,
    entries: [
      for (final raw in json['entries'] as List? ?? const [])
        if (raw is Map && raw['uid'] is String)
          RankBoardEntry(
            uid: raw['uid'] as String,
            rank: (raw['rank'] as num?)?.toInt() ?? 0,
            displayName: raw['displayName'] as String? ?? '3i member',
            avatarUrl: raw['avatarUrl'] as String?,
            score: _num(raw['score']),
          ),
    ],
  );

  /// Số người có số trong kỳ, kể cả ngoài top 10.
  final int participants;
  final List<RankBoardEntry> entries;
}

/// Thẻ BXH ở users/{uid}/rankCards/{boardId}. Số liệu và câu nói chốt lúc trao,
/// chủ thẻ chỉ ghi được [revealedAt] một lần (firestore.rules).
class RankCard {
  const RankCard({
    required this.uid,
    required this.boardId,
    required this.range,
    required this.sport,
    required this.periodStart,
    required this.periodEnd,
    required this.rank,
    required this.participants,
    required this.tier,
    required this.score,
    required this.displayName,
    required this.stats,
    required this.quote,
    this.awardedAt,
    this.revealedAt,
  });

  /// Null khi kỳ hay bộ môn lạ (backend mới thêm): app cũ bỏ qua thẻ đó.
  /// Provider đổi Timestamp sang DateTime trước.
  static RankCard? fromJson(
    String uid,
    String boardId,
    Map<String, dynamic> json,
  ) {
    final range = _rangeFrom(json['range']);
    final sport = _sportFrom(json['sport']);
    final start = _day(json['periodStart']);
    final end = _day(json['periodEnd']);
    if (range == null || sport == null || start == null || end == null) {
      return null;
    }
    final awardedAt = json['awardedAt'];
    final revealedAt = json['revealedAt'];
    return RankCard(
      uid: uid,
      boardId: boardId,
      range: range,
      sport: sport,
      periodStart: start,
      periodEnd: end,
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      participants: (json['participants'] as num?)?.toInt() ?? 0,
      tier: runCardTierFromKey(json['tier'] as String?),
      score: _num(json['score']),
      displayName: json['displayName'] as String? ?? '3i member',
      stats: (json['stats'] as Map?)?.cast<String, dynamic>() ?? const {},
      quote: json['quote'] as String? ?? '',
      awardedAt: awardedAt is DateTime ? awardedAt : null,
      revealedAt: revealedAt is DateTime ? revealedAt : null,
    );
  }

  final String uid;
  final String boardId;
  final ClubRankingRange range;
  final ClubRankingSport sport;

  /// Ngày đầu kỳ và ngày đầu kỳ sau (không tính), lịch VN.
  final DateTime periodStart;
  final DateTime periodEnd;
  final int rank;
  final int participants;
  final GameCardTier tier;
  final double score;

  /// Tên lúc chốt, in trên thẻ.
  final String displayName;

  /// Hai số phụ theo bộ môn: runMeters, walkMeters; avgSteps, days10k, days;
  /// rides, longestMeters.
  final Map<String, dynamic> stats;
  final String quote;
  final DateTime? awardedAt;
  final DateTime? revealedAt;

  bool get revealed => revealedAt != null;
  bool get month => range == ClubRankingRange.currentMonth;

  PastRankingPeriod get period =>
      (range: range, start: periodStart, end: periodEnd, closing: false);
}

String _two(int n) => n.toString().padLeft(2, '0');

String _date(DateTime? at) {
  if (at == null) return '';
  final d = at.toLocal();
  return '${_two(d.day)}.${_two(d.month)}.${d.year}';
}

/// "42,6" từ mét.
String rankCardKm(double meters) =>
    (meters / 1000).toStringAsFixed(1).replaceAll('.', ',');

/// Số chính của thẻ: km hay số bước, cùng đơn vị.
(String, String) rankCardHero(ClubRankingSport sport, double score) =>
    switch (sport) {
      ClubRankingSport.steps => (stepThousands(score.round()), 'BƯỚC'),
      _ => (rankCardKm(score), 'KM'),
    };

/// "Quán quân · 42,6 km" dưới thẻ ở mục Kỳ trước.
String rankTitle(int rank) => switch (rank) {
  1 => 'Quán quân',
  2 => 'Á quân',
  3 => 'Hạng ba',
  _ => 'Hạng $rank',
};

/// Kỳ in quanh vành huy chương: "TUẦN 19–25/10", "THÁNG 9 · 2026".
String rankCardPeriod(PastRankingPeriod period) {
  final first = period.start;
  if (period.range == ClubRankingRange.currentMonth) {
    return 'THÁNG ${first.month} · ${first.year}';
  }
  final last = period.end.subtract(const Duration(days: 1));
  final from = first.month == last.month
      ? '${first.day}'
      : '${first.day}/${first.month}';
  return 'TUẦN $from–${last.day}/${last.month}';
}

List<AchievementStat> _extraStats(RankCard card) {
  final s = card.stats;
  return switch (card.sport) {
    ClubRankingSport.run => [
      (value: rankCardKm(_num(s['runMeters'])), label: 'CHẠY · KM'),
      (value: rankCardKm(_num(s['walkMeters'])), label: 'ĐI BỘ · KM'),
    ],
    ClubRankingSport.steps => [
      (value: stepThousands(_num(s['avgSteps']).round()), label: 'TB/NGÀY'),
      (
        value: '${_num(s['days10k']).round()}/${_num(s['days']).round()}',
        label: 'NGÀY ≥ 10K',
      ),
    ],
    ClubRankingSport.bike => [
      (value: '${_num(s['rides']).round()}', label: 'BUỔI'),
      (value: rankCardKm(_num(s['longestMeters'])), label: 'DÀI NHẤT · KM'),
    ],
  };
}

/// Mặt trước: huy chương khắc số hạng, số chính, số phụ và câu nói. Mặt sau:
/// huy chương khắc biểu tượng bộ môn.
AchievementCardData rankCardData(RankCard card) {
  final period = rankCardPeriod(card.period);
  final sportName = rankSportNames[card.sport]!;
  final (hero, unit) = rankCardHero(card.sport, card.score);
  final last = card.periodEnd.subtract(const Duration(days: 1));
  return AchievementCardData(
    tier: card.tier,
    art: RankMedalArt(
      rank: card.rank,
      month: card.month,
      period: period,
      sport: card.sport,
      tier: card.tier,
    ),
    backFace: RankBackArt(
      rank: card.rank,
      month: card.month,
      period: period,
      sport: card.sport,
      tier: card.tier,
    ),
    kind: '${card.month ? 'BXH THÁNG' : 'BXH TUẦN'} · $sportName',
    hero: hero,
    heroUnit: unit,
    title: '${rankTitle(card.rank)} ${card.month ? 'tháng' : 'tuần'}',
    quote: card.quote.isEmpty ? null : '“${card.quote}”',
    stats: [
      (value: '#${card.rank}', label: 'TRÊN ${card.participants}'),
      ..._extraStats(card),
    ],
    owner: card.displayName.toUpperCase(),
    serial: 'HẠNG ${card.rank}',
    desc: '',
    meta:
        '${_two(card.periodStart.day)} – ${_two(last.day)}.${_two(last.month)}.${last.year}',
    date: _date(card.awardedAt),
  );
}

CardShareSubject rankCardShareSubject(RankCard card) => CardShareSubject(
  id: 'rank-${card.boardId}',
  printed: [
    card.tier.name,
    card.boardId,
    card.rank,
    card.participants,
    card.score,
    card.quote,
    card.displayName,
  ].join('|'),
  text:
      '${rankTitle(card.rank)} BXH ${card.month ? 'tháng' : 'tuần'} · '
      '${rankSportNames[card.sport]}\nChia sẻ từ 3i',
);

/// Xem thẻ toàn màn hình. [faceDown] mở lá đang úp để chủ thẻ tự lật; chỉ chủ
/// thẻ ([canShare]) có nút khoe.
Future<void> showRankCardViewer(
  BuildContext context,
  RankCard card, {
  bool faceDown = false,
  bool canShare = false,
}) {
  final data = rankCardData(card);
  return showCardViewer(
    context,
    front: (pose) => AchievementCard(data: data, pose: pose),
    back: (pose) => AchievementCard(data: data, pose: pose, back: true),
    chips: [
      gameCardTiers[card.tier]!.label,
      '${card.month ? 'BXH tháng' : 'BXH tuần'} · ${rankTitle(card.rank)}',
    ],
    cardSize: achievementCardSize,
    startBack: faceDown,
    onShare: canShare
        ? (_, origin) => showCardShare(
            origin,
            subject: rankCardShareSubject(card),
            data: data,
          )
        : null,
  );
}
