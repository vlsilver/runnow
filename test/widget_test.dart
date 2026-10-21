import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/agents/agent_providers.dart';
import 'package:myrun/src/app.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/repository.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/run_contract_repository.dart';
import 'package:myrun/src/theme_controller.dart';

void main() {
  /// Bật app ở cỡ điện thoại để dùng bottom nav (layout web rộng có rail
  /// riêng làm thay đổi cây widget/scroll). [agent] null là chưa tải được hồ
  /// sơ bot, như khi chưa đăng nhập.
  Future<void> pumpApp(WidgetTester tester, {AgentMe? agent}) async {
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
          agentMeProvider.overrideWith((ref) async => agent),
          agentRoomPreviewProvider.overrideWith(
            (ref) async => (messages: const <AgentRoomMessage>[], bots: 0),
          ),
          firebaseUserProvider.overrideWith((ref) => Stream.value(null)),
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

  testWidgets('people without the bot keep the run tab in the middle', (
    tester,
  ) async {
    await pumpApp(tester, agent: agentMe(enabled: false));
    expect(find.text('MyBot'), findsNothing);
    // Chỉ có nút Chạy giữa thanh tab, đầu tab Kèo không có nút Chạy.
    expect(find.text('Chạy'), findsOneWidget);
    expect(find.byTooltip('Bắt đầu chạy'), findsNothing);
  });

  testWidgets('bot users get MyBot in the middle and run from the Kèo header', (
    tester,
  ) async {
    await pumpApp(tester, agent: agentMe(enabled: true));
    expect(find.text('MyBot'), findsOneWidget);
    expect(find.byTooltip('Bắt đầu chạy'), findsOneWidget);
    // Thanh tab không còn nút Chạy, chữ "Chạy" duy nhất là nút trên đầu Kèo.
    expect(find.text('Chạy'), findsOneWidget);

    await tester.tap(find.text('MyBot'));
    await tester.pumpAndSettle();
    expect(find.text('Sóc'), findsOneWidget);
    expect(find.text('Chat riêng'), findsOneWidget);
    // Vẫn ở trong shell: thanh tab còn đó.
    expect(find.text('Hành Trình'), findsOneWidget);
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
