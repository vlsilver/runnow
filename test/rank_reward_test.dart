import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/club_ranking.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/push.dart';
import 'package:myrun/src/rank/rank_card.dart';
import 'package:myrun/src/rank/rank_reward.dart';
import 'package:myrun/src/rank/rank_reward_widgets.dart';

LeaderboardStats _stats() => const LeaderboardStats(
  distanceMeters: 0,
  movingTimeSeconds: 0,
  activityCount: 0,
  activeDays: 0,
  longestDistanceMeters: 0,
  fastestPaceSecondsPerKm: null,
  steps: 0,
);

ClubRankedMember _ranked(String uid, int rank, double km) => ClubRankedMember(
  rank: rank,
  score: km * 1000,
  entry: LeaderboardEntry(
    uid: uid,
    displayName: uid,
    visibility: ProfileVisibility.public,
    rollingSevenDays: _stats(),
    currentWeek: _stats(),
    currentMonth: _stats(),
  ),
);

const _rewards = RankRewards(
  giverName: 'Bình',
  items: [
    RankRewardItem(id: 'a', fromRank: 1, toRank: 1, name: 'Áo', icon: 'shirt'),
    RankRewardItem(id: 't', fromRank: 2, toRank: 3, name: 'Tất', icon: 'socks'),
  ],
);

void main() {
  test('reward board key is the running period, Vietnam calendar', () {
    // CN 1/11 23:30 giờ VN: vẫn tuần 26/10, tháng 11 đã bắt đầu từ 0:00 1/11.
    final sunday = DateTime.utc(2026, 11, 1, 16, 30);
    expect(
      rankBoardId(
        currentRankingPeriod(sunday, ClubRankingRange.currentWeek),
        ClubRankingSport.run,
      ),
      'week_2026-10-26_run',
    );
    expect(
      rankBoardId(
        currentRankingPeriod(sunday, ClubRankingRange.currentMonth),
        ClubRankingSport.bike,
      ),
      'month_2026-11-01_bike',
    );
    // T2 2/11 00:00 giờ VN là tuần mới.
    expect(
      rankBoardId(
        currentRankingPeriod(
          DateTime.utc(2026, 11, 1, 17),
          ClubRankingRange.currentWeek,
        ),
        ClubRankingSport.steps,
      ),
      'week_2026-11-02_steps',
    );
  });

  test('gap hint aims at the nearest better reward, ties share the rank', () {
    // an 30, binh và chi 20 (cùng hạng 2), dung 15.
    final ranked = [
      _ranked('an', 1, 30),
      _ranked('binh', 2, 20),
      _ranked('chi', 2, 20),
      _ranked('dung', 4, 15),
    ];
    final sport = ClubRankingSport.run;
    expect(
      rankRewardGapLabel(ranked, 3, _rewards, sport),
      'Thêm 5.00 km để lên #3 nhận Tất',
    );
    expect(
      rankRewardGapLabel(ranked, 1, _rewards, sport),
      'Thêm 10.00 km để lên #1 nhận Áo',
    );
    expect(rankRewardGapLabel(ranked, 0, _rewards, sport), isNull);
  });

  test('gap hint skips rewards below me when the ranges have a hole', () {
    // Quà #1–3 và #8–10; người hạng 5 nhắm #3 (chi 20 km), không nhắm #8–10.
    const holes = RankRewards(
      giverName: 'Bình',
      items: [
        RankRewardItem(
          id: 'a',
          fromRank: 1,
          toRank: 3,
          name: 'Áo',
          icon: 'shirt',
        ),
        RankRewardItem(
          id: 't',
          fromRank: 8,
          toRank: 10,
          name: 'Tất',
          icon: 'socks',
        ),
      ],
    );
    final ranked = [
      _ranked('an', 1, 30),
      _ranked('binh', 2, 25),
      _ranked('chi', 3, 20),
      _ranked('dung', 4, 18),
      _ranked('em', 5, 12),
    ];
    expect(
      rankRewardGapLabel(ranked, 4, holes, ClubRankingSport.run),
      'Thêm 8.00 km để lên #3 nhận Áo',
    );
  });

  test('a reward push opens the club on that board', () {
    expect(
      pushLocation({'kind': 'rank_reward', 'boardId': 'week_2026-10-26_run'}),
      '/club?board=week_2026-10-26_run',
    );
    expect(pushLocation({'kind': 'rank_reward'}), isNull);
  });

  test('card reward parses and counts as received 14 days after giving', () {
    final given = DateTime.utc(2026, 11, 3, 9);
    final card = RankCard.fromJson('chi', 'week_2026-10-26_run', {
      'range': 'week',
      'sport': 'run',
      'periodStart': '2026-10-26',
      'periodEnd': '2026-11-02',
      'rank': 2,
      'reward': {
        'itemId': 't',
        'name': 'Tất',
        'icon': 'socks',
        'photos': ['rankRewards/week_2026-10-26_run/a1.jpg'],
        'giverName': 'Bình',
        'givenAt': given,
        'receivedAt': null,
      },
    })!;
    final reward = card.reward!;
    expect(
      [reward.name, reward.giverName, reward.photos.length],
      ['Tất', 'Bình', 1],
    );
    expect(reward.receivedBy(DateTime.utc(2026, 11, 17, 8)), isFalse);
    expect(reward.receivedBy(DateTime.utc(2026, 11, 17, 9)), isTrue);
    final none = RankCard.fromJson('dung', 'week_2026-10-26_run', {
      'range': 'week',
      'sport': 'run',
      'periodStart': '2026-10-26',
      'periodEnd': '2026-11-02',
      'rank': 4,
    })!;
    expect(none.reward, isNull);
  });

  testWidgets(
    'Nhắn người trao hỏi backend, lỗi thì không báo nhầm chưa liên kết',
    (tester) async {
      final card = RankCard.fromJson('chi', 'week_2026-10-26_run', {
        'range': 'week',
        'sport': 'run',
        'periodStart': '2026-10-26',
        'periodEnd': '2026-11-02',
        'rank': 2,
        'reward': {
          'itemId': 't',
          'name': 'Tất',
          'icon': 'socks',
          'photos': <String>[],
          'giverName': 'Bình',
          'givenAt': null,
          'receivedAt': null,
        },
      })!;
      Future<List<String>> open(int status) async {
        final requests = <String>[];
        final api = RunNowApiClient(
          baseUri: Uri.parse('https://api.example.test'),
          tokenProvider: ({required forceRefresh}) async => 'token',
          appVersion: () async => '1.6.0+1',
          appPlatform: 'ios',
          httpClient: MockClient((request) async {
            requests.add('${request.method} ${request.url.path}');
            return http.Response(
              status == 200
                  ? '{"giverTg":""}'
                  : '{"error":"internal","message":"Server down"}',
              status,
            );
          }),
        );
        await tester.pumpWidget(
          ProviderScope(
            // Cây mới mỗi lần, không dính sheet hay snackbar của lần trước.
            key: UniqueKey(),
            overrides: [
              runNowApiClientProvider.overrideWithValue(api),
              rankCardProvider((
                uid: 'chi',
                boardId: 'week_2026-10-26_run',
              )).overrideWith((ref) => Stream.value(card)),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showRankCardRewardSheet(context, card),
                    child: const Text('mở'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('mở'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Nhắn Bình'));
        await tester.pumpAndSettle();
        return requests;
      }

      expect(await open(200), [
        'GET /v1/rank-cards/week_2026-10-26_run/reward/contact',
      ]);
      expect(find.text('Bình chưa liên kết Telegram.'), findsOneWidget);

      await open(500);
      expect(find.text('Server down'), findsOneWidget);
    // Snackbar xếp hàng: chờ cái lỗi tắt rồi mới chắc không có câu sai đi sau.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
      expect(find.text('Bình chưa liên kết Telegram.'), findsNothing);
    },
  );
}
