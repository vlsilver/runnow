import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/app.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/repository.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/run_contract_repository.dart';
import 'package:myrun/src/theme_controller.dart';

void main() {
  testWidgets('renders contract home in demo mode', (tester) async {
    // Ép kích thước điện thoại để dùng bottom nav (layout web rộng có rail
    // riêng làm thay đổi cây widget/scroll).
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
        ],
        child: const RunNowApp(requireAuthentication: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Kèo'), findsNWidgets(2));
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.text('Chưa có kèo đang diễn ra'), findsOneWidget);
    expect(find.text('Tổng quan'), findsNothing);
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
