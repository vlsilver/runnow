import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/club_ranking.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/rank/rank_card.dart';

/// Doc users/{uid}/rankCards/{boardId} như backend ghi, Timestamp đã đổi sang
/// DateTime.
Map<String, dynamic> _doc({
  String range = 'week',
  String sport = 'run',
  Map<String, dynamic>? stats,
  DateTime? revealedAt,
}) => {
  'boardId': 'week_2026-10-26_run',
  'range': range,
  'sport': sport,
  'periodStart': '2026-10-26',
  'periodEnd': '2026-11-02',
  'rank': 1,
  'participants': 3,
  'tier': 'legendary',
  'score': 21000,
  'displayName': 'Bình',
  'stats': stats ?? {'runMeters': 20000, 'walkMeters': 1000},
  'quote': 'Dẫn đầu cả tuần.',
  'awardedAt': DateTime(2026, 11, 2, 12),
  'revealedAt': revealedAt,
};

void main() {
  test('parses the card the backend wrote', () {
    final card = RankCard.fromJson('binh', 'week_2026-10-26_run', _doc())!;

    expect(card.range, ClubRankingRange.currentWeek);
    expect(card.sport, ClubRankingSport.run);
    expect(card.tier, GameCardTier.legendary);
    expect(card.periodStart, DateTime.utc(2026, 10, 26));
    expect(card.periodEnd, DateTime.utc(2026, 11, 2));
    expect(card.revealed, isFalse);
    expect(
      RankCard.fromJson(
        'binh',
        'week_2026-10-26_run',
        _doc(revealedAt: DateTime(2026, 11, 2, 13)),
      )!.revealed,
      isTrue,
    );
  });

  test('skips a card of a sport this app does not know', () {
    expect(RankCard.fromJson('a', 'week_x_swim', _doc(sport: 'swim')), isNull);
    expect(RankCard.fromJson('a', 'year_x_run', _doc(range: 'year')), isNull);
  });

  test('run card shows total km, run and walk split, rank of participants', () {
    final data = rankCardData(
      RankCard.fromJson('binh', 'week_2026-10-26_run', _doc())!,
    );

    expect(data.kind, 'BXH TUẦN · CHẠY · ĐI BỘ');
    expect((data.hero, data.heroUnit), ('21,0', 'KM'));
    expect(data.title, 'Quán quân tuần');
    expect(data.quote, '“Dẫn đầu cả tuần.”');
    expect(data.owner, 'BÌNH');
    expect(data.stats, [
      (value: '#1', label: 'TRÊN 3'),
      (value: '20,0', label: 'CHẠY · KM'),
      (value: '1,0', label: 'ĐI BỘ · KM'),
    ]);
    expect(data.meta, '26 – 01.11.2026');
  });

  test('steps card shows step count, daily average and 10k days', () {
    final data = rankCardData(
      RankCard.fromJson('an', 'week_2026-10-26_steps', {
        ..._doc(
          sport: 'steps',
          stats: {'avgSteps': 3285, 'days10k': 2, 'days': 7},
        ),
        'score': 23000,
      })!,
    );

    expect((data.hero, data.heroUnit), ('23.000', 'BƯỚC'));
    expect(data.stats!.skip(1), [
      (value: '3.285', label: 'TB/NGÀY'),
      (value: '2/7', label: 'NGÀY ≥ 10K'),
    ]);
  });

  test('period on the medal rim', () {
    final week = RankCard.fromJson('a', 'b', _doc())!.period;
    expect(rankCardPeriod(week), 'TUẦN 26/10–1/11');
    final month = RankCard.fromJson('a', 'b', {
      ..._doc(range: 'month'),
      'periodStart': '2026-09-01',
      'periodEnd': '2026-10-01',
    })!.period;
    expect(rankCardPeriod(month), 'THÁNG 9 · 2026');
  });

  test('board keeps entries in rank order and drops malformed ones', () {
    final board = RankBoard.fromJson({
      'participants': 4,
      'entries': [
        {'uid': 'an', 'rank': 1, 'displayName': 'An', 'score': 9000},
        {'rank': 2, 'displayName': 'Không uid'},
        {'uid': 'chi', 'rank': 2, 'displayName': 'Chi', 'score': 4000},
      ],
    });

    expect(board.participants, 4);
    expect(board.entries.map((e) => (e.uid, e.rank, e.score)), [
      ('an', 1, 9000.0),
      ('chi', 2, 4000.0),
    ]);
  });
}
