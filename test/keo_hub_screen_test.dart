import 'dart:async';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/club_card.dart';
import 'package:myrun/src/achievements/club_card_widgets.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/club_runs.dart';
import 'package:myrun/src/games/game_providers.dart';
import 'package:myrun/src/hearts.dart';
import 'package:myrun/src/home_digest.dart';
import 'package:myrun/src/live_cheers.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/repository.dart';
import 'package:myrun/src/rooms/run_room_models.dart';
import 'package:myrun/src/rooms/run_room_repository.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/run_contract_repository.dart';
import 'package:myrun/src/screens/keo_hub_screen.dart';
import 'package:myrun/src/sync.dart';
import 'package:myrun/src/training_plan/training_plan_models.dart';
import 'package:myrun/src/training_plan/training_plan_repository.dart';

class _FakeHearts implements HeartRepository {
  final counted = <String>[];

  @override
  Stream<Hearts> watch(String target) => Stream.value(Hearts.empty);

  @override
  Future<int> count(String target) async {
    counted.add(target);
    return 0;
  }

  @override
  Future<void> like(String target) async {}

  @override
  Future<void> unlike(String target) async {}
}

class _FakeCheers implements LiveCheerRepository {
  @override
  Stream<List<LiveCheer>> watch(String sessionId) => Stream.value(const []);

  @override
  Future<void> send(String sessionId, String emoji) async {}
}

LeaderboardEntry _runner(String name, double km) {
  final stats = LeaderboardStats(
    distanceMeters: km * 1000,
    movingTimeSeconds: 0,
    activityCount: 0,
    activeDays: 0,
    longestDistanceMeters: 0,
    fastestPaceSecondsPerKm: null,
  );
  return LeaderboardEntry(
    uid: name,
    displayName: name,
    visibility: ProfileVisibility.public,
    rollingSevenDays: stats,
    currentWeek: stats,
    currentMonth: stats,
  );
}

RunContract _contract() {
  final start = DateTime.now().toUtc().subtract(const Duration(days: 1));
  return RunContract(
    id: 'keo',
    creatorUid: 'u2',
    title: 'Kèo tuần',
    template: RunContractTemplate.custom,
    metric: RunContractMetric.distance,
    targetValue: 20,
    periodType: RunContractPeriodType.weekly,
    startAt: start,
    endAtExclusive: start.add(const Duration(days: 7)),
    finalizeAt: start.add(const Duration(days: 8)),
    status: RunContractStatus.active,
    visibility: RunContractVisibility.club,
    progressValue: 0,
    participants: {
      'u2': RunContractParticipant(
        uid: 'u2',
        progressValue: 0,
        joinedAt: start,
        updatedAt: start,
      ),
    },
    createdAt: start,
    updatedAt: start,
  );
}

ClubCard _card(String id, String tier) =>
    ClubCard.fromJson({'ownerUid': 'u1', 'activityId': id, 'tier': tier})!;

/// Số lần trang chủ gọi từng nguồn danh sách.
class _Fetches {
  var contracts = 0;
  var runs = 0;
}

/// Dựng trang chủ trong khung thấp: mục Kèo ở đầu và mục Buổi chạy ở cuối
/// không cùng nằm trong vùng dựng sẵn mặc định của ListView.
Future<_Fetches> _pumpHome(
  WidgetTester tester, {
  List<ClubCard>? cards,
  _FakeHearts? hearts,
  Future<List<LeaderboardEntry>>? leaderboard,
  String? uid,
  Stream<List<ClubCard>>? cardStream,
  double height = 100,
  Stream<List<RunRoom>>? publicRooms,
  Future<RunContractPage>? clubContracts,
}) async {
  tester.view.physicalSize = Size(400, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fetches = _Fetches();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseUserProvider.overrideWith(
          (ref) => Stream.value(uid == null ? null : MockUser(uid: uid)),
        ),
        homeDigestProvider.overrideWith((ref) => Stream.value(null)),
        membersProvider.overrideWith((ref) => Stream.value(const [])),
        myActiveContractsProvider.overrideWith(
          (ref) => Stream.value(const <RunContract>[]),
        ),
        clubLiveSessionsProvider.overrideWith(
          (ref) => Stream.value(const <LiveTrackingSession>[]),
        ),
        publicRunRoomsProvider.overrideWith(
          (ref) => publicRooms ?? Stream.value(const <RunRoom>[]),
        ),
        myRunRoomsProvider.overrideWith(
          (ref) => Stream.value(const <RunRoomMembership>[]),
        ),
        coachPlanProvider.overrideWith(
          (ref) => Stream<TrainingPlan?>.value(null),
        ),
        gameListProvider.overrideWith((ref) async => null),
        totalKmLeaderboardProvider.overrideWith(
          (ref) => leaderboard ?? Future.value(const <LeaderboardEntry>[]),
        ),
        hubClubContractsProvider.overrideWith((ref) {
          fetches.contracts++;
          return clubContracts ??
              Future.value(
                const RunContractPage(contracts: [], hasMore: false),
              );
        }),
        hubClubRunsProvider.overrideWith((ref) async {
          fetches.runs++;
          return const <ClubRunItem>[];
        }),
        clubCardsProvider.overrideWith(
          (ref) => cardStream ?? Stream.value(cards ?? [_card('a1', 'rare')]),
        ),
        heartRepositoryProvider.overrideWithValue(hearts ?? _FakeHearts()),
        liveCheerRepositoryProvider.overrideWithValue(_FakeCheers()),
        stravaConnectionProvider.overrideWithValue(false),
        syncControllerProvider.overrideWith(
          (ref) => SyncController(DemoActivityRepository()),
        ),
      ],
      child: const MaterialApp(home: KeoHubScreen()),
    ),
  );
  await _settle(tester);
  return fetches;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Engine báo từng trạng thái một, không nhảy thẳng từ nền lên.
Future<void> _walk(WidgetTester tester, List<AppLifecycleState> states) async {
  for (final state in states) {
    tester.binding.handleAppLifecycleStateChanged(state);
    await _settle(tester);
  }
}

void main() {
  testWidgets('cuộn lên xuống không gọi lại danh sách kèo và buổi chạy', (
    tester,
  ) async {
    final fetches = await _pumpHome(tester);
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    for (var i = 0; i < 2; i++) {
      position.jumpTo(position.maxScrollExtent);
      await _settle(tester);
      position.jumpTo(0);
      await _settle(tester);
    }

    expect(fetches.contracts, 1);
    expect(fetches.runs, 1);
  });

  testWidgets('quay lại app thì tải lại danh sách kèo và buổi chạy', (
    tester,
  ) async {
    final fetches = await _pumpHome(tester);

    await _walk(tester, const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]);
    expect(fetches.contracts, 1);

    await _walk(tester, const [
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);
    expect(fetches.contracts, 2);
    expect(fetches.runs, 2);
  });

  testWidgets('chỉ đếm tim các thẻ còn có thể lọt 10 thẻ đầu', (tester) async {
    final hearts = _FakeHearts();
    await _pumpHome(
      tester,
      hearts: hearts,
      cards: [
        for (var i = 0; i < 10; i++) _card('legend$i', 'legendary'),
        for (var i = 0; i < 5; i++) _card('rare$i', 'rare'),
      ],
    );

    expect(hearts.counted, hasLength(10));
    expect(hearts.counted.where((target) => target.contains('rare')), isEmpty);
  });

  testWidgets('kèo về sau không đẩy các mục dưới xuống', (tester) async {
    final page = Completer<RunContractPage>();
    await _pumpHome(tester, clubContracts: page.future);
    final header = find.text('Thẻ nổi bật', skipOffstage: false);
    final before = tester.getTopLeft(header).dy;

    page.complete(RunContractPage(contracts: [_contract()], hasMore: false));
    await _settle(tester);

    expect(find.text('Kèo tuần', skipOffstage: false), findsOneWidget);
    expect(tester.getTopLeft(header).dy, before);
  });

  testWidgets('Live về sau không đẩy các mục dưới xuống', (tester) async {
    final rooms = StreamController<List<RunRoom>>();
    addTearDown(rooms.close);
    await _pumpHome(tester, publicRooms: rooms.stream);
    final header = find.text('Kèo đang chạy', skipOffstage: false);
    final before = tester.getTopLeft(header).dy;

    rooms.add(const []);
    await _settle(tester);

    expect(find.text('Chưa ai đang chạy live', skipOffstage: false), findsOne);
    expect(tester.getTopLeft(header).dy, before);
  });

  testWidgets('Live đang tải thì chưa mời chạy', (tester) async {
    final rooms = StreamController<List<RunRoom>>();
    addTearDown(rooms.close);
    await _pumpHome(tester, publicRooms: rooms.stream, height: 1400);

    expect(find.text('Chưa ai đang chạy live').hitTestable(), findsNothing);
  });

  testWidgets('BXH về sau không đẩy mục Thẻ xuống', (tester) async {
    final board = Completer<List<LeaderboardEntry>>();
    await _pumpHome(tester, leaderboard: board.future, uid: 'an');
    // Khung thấp nên hai mục này nằm trong vùng dựng sẵn, ngoài màn hình.
    final header = find.text('Thẻ nổi bật', skipOffstage: false);
    final before = tester.getTopLeft(header).dy;

    board.complete([_runner('Bình', 20), _runner('an', 12)]);
    await _settle(tester);

    expect(find.text('Bình', skipOffstage: false), findsOneWidget);
    // Dòng hạng cao theo font thật, nên chỉ đòi lệch không quá một dòng chữ.
    expect(tester.getTopLeft(header).dy, moreOrLessEquals(before, epsilon: 20));
  });

  testWidgets('thẻ về sau không làm trang dài ra', (tester) async {
    final cards = StreamController<List<ClubCard>>();
    addTearDown(cards.close);
    await _pumpHome(tester, cardStream: cards.stream);
    final position = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    final before = position.maxScrollExtent;

    cards.add([_card('a1', 'rare')]);
    await _settle(tester);

    expect(find.byType(ClubCardThumb, skipOffstage: false), findsOneWidget);
    expect(position.maxScrollExtent, before);
  });

  group('hiệu ứng thẻ ở mục Thẻ nổi bật', () {
    bool motion(WidgetTester tester) => TickerMode.valuesOf(
      tester.element(find.byType(AchievementCard, skipOffstage: false)),
    ).enabled;

    ScrollPosition pagePosition(WidgetTester tester) =>
        tester.state<ScrollableState>(find.byType(Scrollable).first).position;

    testWidgets('thẻ ngoài màn hình không giữ app vẽ liên tục', (tester) async {
      await _pumpHome(tester, cards: [_card('a1', 'mythic')]);

      expect(motion(tester), isFalse);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });

    testWidgets('mở trang mà thẻ đã trên màn hình thì chạy luôn', (
      tester,
    ) async {
      await _pumpHome(tester, cards: [_card('a1', 'mythic')], height: 1400);

      expect(motion(tester), isTrue);
    });

    testWidgets('cuộn tới thẻ thì chạy, đang cuộn thì dừng', (tester) async {
      await _pumpHome(tester, cards: [_card('a1', 'mythic')]);
      final position = pagePosition(tester);
      final header = find.text('Thẻ nổi bật', skipOffstage: false);

      position.jumpTo(tester.getTopLeft(header).dy + position.pixels);
      await _settle(tester);
      expect(motion(tester), isTrue);

      final drag = await tester.startGesture(const Offset(200, 50));
      await drag.moveBy(const Offset(0, -30));
      await _settle(tester);
      expect(motion(tester), isFalse);

      await drag.up();
      await tester.pump(const Duration(seconds: 2));
      await _settle(tester);
      expect(motion(tester), isTrue);
    });

    testWidgets('cuộn khỏi thẻ thì dừng hẳn', (tester) async {
      await _pumpHome(tester, cards: [_card('a1', 'mythic')]);
      final position = pagePosition(tester);
      final header = find.text('Thẻ nổi bật', skipOffstage: false);

      position.jumpTo(tester.getTopLeft(header).dy + position.pixels);
      await _settle(tester);
      position.jumpTo(0);
      await _settle(tester);

      expect(motion(tester), isFalse);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  testWidgets('kéo màn thông báo xuống rồi thả không tải lại', (tester) async {
    final fetches = await _pumpHome(tester);

    await _walk(tester, const [
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]);

    expect(fetches.contracts, 1);
    expect(fetches.runs, 1);
  });
}
