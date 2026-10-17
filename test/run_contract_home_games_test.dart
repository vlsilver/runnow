import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/repository.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/run_contract_repository.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/screens/run_contract_home_screen.dart';
import 'package:myrun/src/sync.dart';
import 'package:myrun/src/training_plan/training_plan_models.dart';
import 'package:myrun/src/training_plan/training_plan_repository.dart';

class _FakeUser implements User {
  @override
  String get uid => 'me';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeContracts implements RunContractRepository {
  _FakeContracts(this.contracts);

  final List<RunContract> contracts;

  @override
  Future<RunContractPage> fetchClubContractsPage({
    int limit = 20,
    Object? cursor,
    bool fromCache = false,
  }) async => RunContractPage(contracts: contracts, hasMore: false);

  @override
  Future<RunContractPage> fetchMyContractHistoryPage({
    required RunContractStatus status,
    int limit = 20,
    Object? cursor,
    bool fromCache = false,
  }) async => const RunContractPage(contracts: [], hasMore: false);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

RunContract _contract(String title) {
  final now = DateTime.now();
  return RunContract(
    id: 'k1',
    creatorUid: 'owner',
    title: title,
    template: RunContractTemplate.weekly10k,
    metric: RunContractMetric.distance,
    targetValue: 10,
    periodType: RunContractPeriodType.weekly,
    startAt: now,
    endAtExclusive: now.add(const Duration(days: 7)),
    finalizeAt: now.add(const Duration(days: 7, hours: 6)),
    status: RunContractStatus.active,
    visibility: RunContractVisibility.club,
    progressValue: 0,
    participants: const {},
    createdAt: now,
    updatedAt: now,
  );
}

http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

Map<String, dynamic> _games(List<Map<String, dynamic>> items) => {
  'viewer': {'canCreate': false},
  'createOptions': {'roles': null},
  'items': items,
};

Map<String, dynamic> _game(String title, {bool hasTodo = false}) => {
  'id': 'g1',
  'title': title,
  'subtitle': 'Đêm 2',
  'status': 'running',
  'statusLabel': 'Đang chơi',
  'playerCount': 12,
  'minPlayers': 8,
  'maxPlayers': 20,
  'hasTodo': hasTodo,
  'nextDeadline': null,
  'updatedAt': '2026-10-17T10:00:00Z',
  'testMode': false,
};

Future<void> _pump(
  WidgetTester tester, {
  required List<RunContract> contracts,
  required Future<http.Response> Function() games,
}) async {
  final api = RunNowApiClient(
    baseUri: Uri.parse('https://api.example.test'),
    tokenProvider: ({required forceRefresh}) async => 'token',
    appVersion: () async => '1.5.0+12',
    appPlatform: 'ios',
    httpClient: MockClient((request) => games()),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runNowApiClientProvider.overrideWithValue(api),
        firebaseUserProvider.overrideWith((ref) => Stream.value(_FakeUser())),
        userProfileProvider.overrideWith((ref) => Stream.value(null)),
        membersProvider.overrideWith(
          (ref) => Stream.value(const <MemberProfile>[]),
        ),
        myActiveContractsProvider.overrideWith(
          (ref) => Stream.value(const <RunContract>[]),
        ),
        coachPlanProvider.overrideWith((ref) => Stream.value(null)),
        publicCoachPlansProvider.overrideWith(
          (ref) => Stream.value(const <TrainingPlan>[]),
        ),
        stravaConnectionProvider.overrideWithValue(false),
        syncControllerProvider.overrideWith(
          (ref) => SyncController(DemoActivityRepository()),
        ),
        runContractRepositoryProvider.overrideWithValue(
          _FakeContracts(contracts),
        ),
      ],
      child: const MaterialApp(home: RunContractHomeScreen()),
    ),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('shows contracts when the games API fails', (tester) async {
    await _pump(
      tester,
      contracts: [_contract('Kèo 10km tuần này')],
      games: () async =>
          _json({'error': 'internal_error', 'message': 'Lỗi máy chủ'}, 500),
    );

    expect(find.text('Kèo 10km tuần này'), findsOneWidget);
    expect(find.text('MA SÓI'), findsNothing);
  });

  testWidgets('shows contracts while the games API hangs', (tester) async {
    final never = Completer<http.Response>();
    await _pump(
      tester,
      contracts: [_contract('Kèo 10km tuần này')],
      games: () => never.future,
    );

    expect(find.text('Kèo 10km tuần này'), findsOneWidget);
    expect(find.text('MA SÓI'), findsNothing);

    // Client bỏ request sau 25 giây: vẫn là list kèo, không có card.
    await tester.pump(const Duration(seconds: 26));
    expect(find.text('Kèo 10km tuần này'), findsOneWidget);
    expect(find.text('MA SÓI'), findsNothing);

    // Provider tự retry; rời màn rồi chờ timeout của request đang treo.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 30));
  });

  testWidgets('puts the game card first and counts it as content', (
    tester,
  ) async {
    await _pump(
      tester,
      contracts: const [],
      games: () async =>
          _json(_games([_game('Ma Sói tuần 42', hasTodo: true)])),
    );

    expect(find.text('Ma Sói tuần 42'), findsOneWidget);
    expect(find.text('Có việc cho bạn'), findsOneWidget);
    expect(find.text('12/20 người'), findsOneWidget);
    // Có ván thì không phải màn rỗng.
    expect(find.text('Chưa có kèo đang diễn ra'), findsNothing);
  });

  testWidgets('game card leads the running filter only', (tester) async {
    await _pump(
      tester,
      contracts: [_contract('Kèo 10km tuần này')],
      games: () async => _json(_games([_game('Ma Sói tuần 42')])),
    );

    expect(
      tester.getTopLeft(find.text('Ma Sói tuần 42')).dy,
      lessThan(tester.getTopLeft(find.text('Kèo 10km tuần này')).dy),
    );

    await tester.tap(find.text('Hoàn thành'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Ma Sói tuần 42'), findsNothing);
  });
}
