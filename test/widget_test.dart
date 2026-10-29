import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myrun/src/agents/agent_providers.dart';
import 'package:myrun/src/app.dart';
import 'package:myrun/src/journey/journey_models.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/profile_stats.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/repository.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/run_contract_repository.dart';
import 'package:myrun/src/theme_controller.dart';

void main() {
  var meReads = 0;
  var profileReads = 0;

  /// Bật app ở cỡ điện thoại để dùng bottom nav (layout web rộng có rail
  /// riêng làm thay đổi cây widget/scroll). [agent] null là chưa tải được hồ
  /// sơ bot, như khi chưa đăng nhập.
  Future<void> pumpApp(WidgetTester tester, {AgentMe? agent}) async {
    // Thẻ bot tự lắc mãi; giảm chuyển động thì thẻ đứng yên, chờ settle được.
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activityRepositoryProvider.overrideWithValue(
            DemoActivityRepository(),
          ),
          trainingGoalRepositoryProvider.overrideWithValue(
            DemoTrainingGoalRepository(
              const TrainingGoals(
                weeklyDistanceMeters: 10000,
                monthlyDistanceMeters: 40000,
              ),
            ),
          ),
          userProfileProvider.overrideWith(
            (ref) => Stream.value(UserProfile.demo),
          ),
          stravaConnectionProvider.overrideWithValue(true),
          stravaConnectionLoadingProvider.overrideWithValue(false),
          myActiveContractsProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          runContractRepositoryProvider.overrideWithValue(
            _EmptyRunContractRepository(),
          ),
          membersProvider.overrideWith((ref) => Stream.value(const [])),
          themeControllerProvider.overrideWith(
            (ref) => ThemeController(loadFromStorage: false),
          ),
          journeyLifetimeDistanceProvider.overrideWith((ref) async => 12000),
          journeyRouteSummaryProvider.overrideWith(
            (ref, id) async => JourneyRouteSummary(
              id: id.name,
              name: id.name,
              tagline: '',
              totalLengthMeters: 42195,
            ),
          ),
          profileStatsProvider.overrideWith((ref) async {
            profileReads++;
            return ProfileStatsData(
              today: DateTime(2026, 10, 24),
              days: const {},
              weeks: const {},
              months: const {},
            );
          }),
          agentMeProvider.overrideWith((ref) async {
            meReads++;
            return agent;
          }),
          agentRoomPreviewProvider.overrideWith(
            (ref) async => (messages: const <AgentRoomMessage>[], bots: const <String>[]),
          ),
          firebaseUserProvider.overrideWith((ref) => Stream.value(null)),
          // Tab MyBot dựng client API ngay khi mở; client thật cần Firebase.
          // Hồ sơ bot đã override ở trên nên không request nào tới được đây.
          runNowApiClientProvider.overrideWithValue(
            RunNowApiClient(
              baseUri: Uri.parse('https://api.example.test'),
              tokenProvider: ({required forceRefresh}) async => 'token',
              appVersion: () async => '1.5.0+12',
              appPlatform: 'ios',
              httpClient: MockClient((_) async => http.Response('{}', 404)),
            ),
          ),
        ],
        child: const RunNowApp(requireAuthentication: false),
      ),
    );
    await tester.pumpAndSettle();
  }

  AgentMe agentMe({required bool enabled}) => AgentMe(
    enabled: enabled,
    agent: const AgentProfile(name: 'Sóc', persona: '', created: true),
    memories: const [],
    memoryLimit: 50,
    learned: const [],
  );

  testWidgets('renders contract home in demo mode', (tester) async {
    await pumpApp(tester);
    expect(find.text('Kèo'), findsNWidgets(2));
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.text('Chưa có kèo đang diễn ra'), findsOneWidget);
    expect(find.text('Tổng quan'), findsNothing);
  });

  testWidgets('people without the bot keep the journey tab', (tester) async {
    await pumpApp(tester, agent: agentMe(enabled: false));
    expect(find.text('MyBot'), findsNothing);
    expect(find.text('Hành Trình'), findsOneWidget);
    expect(find.text('Chạy'), findsOneWidget);
  });

  testWidgets('bot users get MyBot in place of the journey tab', (
    tester,
  ) async {
    await pumpApp(tester, agent: agentMe(enabled: true));
    expect(find.text('MyBot'), findsOneWidget);
    expect(find.text('Hành Trình'), findsNothing);
    // Nút Chạy vẫn ở giữa thanh tab, đầu tab Kèo không có nút Chạy riêng.
    expect(find.text('Chạy'), findsOneWidget);
    expect(find.byTooltip('Bắt đầu chạy'), findsNothing);

    // Bấm tab là đọc lại hồ sơ bot: chạy trong app xong mở tab thấy km mới.
    final reads = meReads;
    await tester.tap(find.text('MyBot'));
    await tester.pumpAndSettle();
    expect(meReads, reads + 1);
    expect(find.text('SÓC'), findsOneWidget);
    expect(find.text('Chat riêng'), findsOneWidget);
    // Vẫn ở trong shell: thanh tab còn đó.
    expect(find.text('Chạy'), findsOneWidget);
  });

  testWidgets('Hồ sơ tab replaces Cài đặt and reloads stats', (tester) async {
    await pumpApp(tester);
    expect(find.text('Cài đặt'), findsNothing);

    // Tab sống trong IndexedStack: bấm tab là đọc lại periodStats.
    final reads = profileReads;
    await tester.tap(find.text('Hồ sơ'));
    // Chặng đang chạy nhấp nháy mãi, nên không chờ settle được.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(profileReads, reads + 1);
    expect(find.text('Chưa có buổi chạy nào'), findsOneWidget);
    expect(find.byTooltip('Cài đặt'), findsOneWidget);
    // Châm ngôn và các chặng hành trình nằm luôn trong Hồ sơ.
    expect(find.text('CHÂM NGÔN HÔM NAY'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Marathon Athens'),
      300,
      maxScrolls: 20,
    );
    expect(find.text('Marathon Athens'), findsOneWidget);
  });
}

class _EmptyRunContractRepository implements RunContractRepository {
  @override
  Future<RunContractPage> fetchClubContractsPage({
    int limit = 20,
    Object? cursor,
    bool fromCache = false,
  }) async => const RunContractPage(contracts: [], hasMore: false);

  @override
  Future<RunContractPage> fetchMyContractHistoryPage({
    required RunContractStatus status,
    int limit = 20,
    Object? cursor,
    bool fromCache = false,
  }) async => const RunContractPage(contracts: [], hasMore: false);

  @override
  Stream<List<RunContract>> watchMyActiveContracts() => Stream.value(const []);

  @override
  Stream<RunContract?> watchContract(String contractId) => Stream.value(null);

  @override
  Future<RunContractRoute?> fetchContractRoute(String contractId) async => null;

  @override
  Future<String> create({
    required RunContractDraft draft,
    required RunContractPeriod period,
    required double initialProgress,
    List<String> countedActivityIds = const [],
  }) async => 'unused';

  @override
  Future<void> updateProgress(
    String contractId,
    double progressValue, {
    List<String> countedActivityIds = const [],
  }) async {}

  @override
  Future<void> join(
    String contractId,
    double initialProgress, {
    List<String> countedActivityIds = const [],
  }) async {}

  @override
  Future<void> updateParticipantProgress(
    String contractId,
    double progressValue, {
    List<String> countedActivityIds = const [],
  }) async {}

  @override
  Future<Map<String, String>> activityAssignments() async => const {};

  @override
  Future<void> replaceActivityAssignments(
    String contractId, {
    required List<String> activityIds,
    required double progressValue,
  }) async {}

  @override
  Future<RunContractStatus> finalize(
    String contractId, {
    required double finalProgress,
    required bool targetMet,
    List<String> countedActivityIds = const [],
  }) async => RunContractStatus.completed;

  @override
  Future<void> delete(String contractId) async {}
}
