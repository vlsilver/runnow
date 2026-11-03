import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/achievements/club_card.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/club_runs.dart';
import 'package:myrun/src/games/game_providers.dart';
import 'package:myrun/src/hearts.dart';
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
}) async {
  tester.view.physicalSize = const Size(400, 100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final fetches = _Fetches();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseUserProvider.overrideWith((ref) => Stream.value(null)),
        membersProvider.overrideWith((ref) => Stream.value(const [])),
        myActiveContractsProvider.overrideWith(
          (ref) => Stream.value(const <RunContract>[]),
        ),
        clubLiveSessionsProvider.overrideWith(
          (ref) => Stream.value(const <LiveTrackingSession>[]),
        ),
        publicRunRoomsProvider.overrideWith(
          (ref) => Stream.value(const <RunRoom>[]),
        ),
        myRunRoomsProvider.overrideWith(
          (ref) => Stream.value(const <RunRoomMembership>[]),
        ),
        coachPlanProvider.overrideWith(
          (ref) => Stream<TrainingPlan?>.value(null),
        ),
        gameListProvider.overrideWith((ref) async => null),
        totalKmLeaderboardProvider.overrideWith(
          (ref) async => const <LeaderboardEntry>[],
        ),
        hubClubContractsProvider.overrideWith((ref) async {
          fetches.contracts++;
          return const RunContractPage(contracts: [], hasMore: false);
        }),
        hubClubRunsProvider.overrideWith((ref) async {
          fetches.runs++;
          return const <ClubRunItem>[];
        }),
        clubCardsProvider.overrideWith(
          (ref) => Stream.value(cards ?? [_card('a1', 'rare')]),
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
