import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myrun/src/agents/agent_providers.dart';
import 'package:myrun/src/app.dart';
import 'package:myrun/src/auth.dart';
import 'package:myrun/src/garmin_controller.dart';
import 'package:myrun/src/health_sync.dart';
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
  var activityWatches = 0;

  /// Bật app ở cỡ điện thoại để dùng bottom nav (layout web rộng có rail
  /// riêng làm thay đổi cây widget/scroll). [agent] null là chưa tải được hồ
  /// sơ bot, như khi chưa đăng nhập.
  Future<void> pumpApp(
    WidgetTester tester, {
    AgentMe? agent,
    String? signedInUid,
    List<RunContract> activeContracts = const [],
  }) async {
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
            _CountingActivities(() => activityWatches++),
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
          stravaAuthProvider.overrideWith((ref) => _NoStrava()),
          // Tab Hồ sơ là trang Cài đặt; bản thật của ba controller này cần
          // Firebase hoặc plugin máy.
          garminAuthProvider.overrideWith((ref) => _NoGarmin()),
          authControllerProvider.overrideWith((ref) => _NoAuth()),
          healthSyncProvider.overrideWith((ref) => _NoHealth()),
          stravaConnectionProvider.overrideWithValue(true),
          stravaConnectionLoadingProvider.overrideWithValue(false),
          myActiveContractsProvider.overrideWith(
            (ref) => Stream.value(activeContracts),
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
          firebaseUserProvider.overrideWith(
            (ref) => Stream.value(
              signedInUid == null ? null : MockUser(uid: signedInUid),
            ),
          ),
          pushControllerProvider.overrideWithValue(null),
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
        child: RunNowApp(requireAuthentication: signedInUid != null),
      ),
    );
    // Router của app là biến toàn cục nên tab test trước để lại vẫn còn. Đưa
    // về Trang chủ để test nào cũng bắt đầu như lúc mở app. Đợi một frame cho
    // cổng đăng nhập dựng router.
    await tester.pump();
    GoRouter.of(tester.element(find.byType(Navigator).first)).go('/');
    await tester.pumpAndSettle();
  }

  AgentMe agentMe({required bool enabled}) => AgentMe(
    enabled: enabled,
    agent: const AgentProfile(name: 'Sóc', persona: '', created: true),
    memories: const [],
    memoryLimit: 50,
    learned: const [],
  );

  testWidgets('tab Trang chủ mở trang tổng, chưa có kèo thì mời đặt kèo', (
    tester,
  ) async {
    await pumpApp(tester);
    // Tab đầu tên "Trang chủ"; trang không còn chữ "Kèo" đứng riêng nào.
    expect(find.text('Trang chủ'), findsOneWidget);
    expect(find.text('Kèo'), findsNothing);
    expect(find.text('Kèo đang chạy'), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    expect(find.text('Đặt kèo tuần này'), findsOneWidget);
    expect(find.text('Tổng quan'), findsNothing);
  });

  testWidgets('mở app có kèo đang chạy không nghe cả lịch sử buổi chạy', (
    tester,
  ) async {
    final start = DateTime.utc(2026, 11, 2);
    activityWatches = 0;
    await pumpApp(
      tester,
      signedInUid: 'me',
      activeContracts: [
        RunContract(
          id: 'keo',
          creatorUid: 'me',
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
            'me': RunContractParticipant(
              uid: 'me',
              progressValue: 0,
              joinedAt: start,
              updatedAt: start,
            ),
          },
          createdAt: start,
          updatedAt: start,
        ),
      ],
    );

    expect(find.text('Kèo tuần'), findsOneWidget);
    expect(activityWatches, 0);
  });

  testWidgets('Hoạt động tab takes the MyBot slot and reloads stats', (
    tester,
  ) async {
    await pumpApp(tester, agent: agentMe(enabled: true));
    expect(find.text('MyBot'), findsNothing);
    expect(find.text('Hành Trình'), findsNothing);

    // Tab sống trong IndexedStack: bấm tab là đọc lại periodStats.
    final reads = profileReads;
    await tester.tap(find.text('Hoạt động'));
    // Chặng đang chạy nhấp nháy mãi, nên không chờ settle được.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(profileReads, reads + 1);
    expect(find.text('Chưa có buổi chạy nào'), findsOneWidget);
    // Mở lại tab cũng đọc lại, không chỉ lần đầu.
    await tester.tap(find.text('Hồ sơ'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('Hoạt động').last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(profileReads, reads + 2);
    await tester.scrollUntilVisible(
      find.text('Marathon Athens'),
      300,
      maxScrolls: 20,
    );
    expect(find.text('Marathon Athens'), findsOneWidget);
  });

  testWidgets('people without the bot get no MyBot button', (tester) async {
    await pumpApp(tester, agent: agentMe(enabled: false));
    await tester.tap(find.text('Hồ sơ'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Đăng xuất'), findsOneWidget);
    expect(find.byTooltip('MyBot'), findsNothing);
  });

  testWidgets('bot users open MyBot from the Hồ sơ header', (tester) async {
    await pumpApp(tester, agent: agentMe(enabled: true));
    // Nút Chạy vẫn ở giữa thanh tab, đầu tab Kèo không có nút Chạy riêng.
    expect(find.text('Chạy'), findsOneWidget);
    expect(find.byTooltip('Bắt đầu chạy'), findsNothing);
    await tester.tap(find.text('Hồ sơ'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // Mở là đọc lại hồ sơ bot: chạy trong app xong mở thấy km mới.
    final reads = meReads;
    await tester.tap(find.byTooltip('MyBot'));
    await tester.pumpAndSettle();
    expect(meReads, reads + 1);
    expect(find.text('SÓC'), findsOneWidget);
    expect(find.text('Chat riêng'), findsOneWidget);
    // Vẫn ở trong shell: thanh tab còn đó.
    expect(find.text('Chạy'), findsOneWidget);
    // Branch Hồ sơ nhớ màn đang mở qua các test; trả về như lúc đầu.
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Hồ sơ opens straight on settings, cards live in Hoạt động', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Hồ sơ'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    // Các mục cài đặt nằm ngay dưới danh tính, không qua nút bánh răng.
    expect(find.text('Đăng xuất'), findsOneWidget);
    expect(find.text('KẾT NỐI'), findsOneWidget);
    expect(find.byTooltip('Cài đặt'), findsNothing);
    expect(find.text('CHÂM NGÔN HÔM NAY'), findsNothing);
    expect(find.text('BỘ THẺ'), findsNothing);

    await tester.tap(find.text('Hoạt động'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('CHÂM NGÔN HÔM NAY'), findsOneWidget);
    // Bộ thẻ hiện cả khi chưa có buổi chạy nào.
    expect(find.text('BỘ THẺ'), findsOneWidget);
  });
}

/// Cổng đăng nhập chỉ nghe controller này; bản thật cần Firebase và app_links.
class _NoStrava extends ChangeNotifier implements StravaAuthController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoGarmin extends ChangeNotifier implements GarminController {
  @override
  bool get connected => false;
  @override
  bool get loading => false;
  @override
  bool get statusLoading => false;
  @override
  String? get errorMessage => null;
  @override
  DateTime? get lastPushAt => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoAuth extends ChangeNotifier implements AuthController {
  @override
  bool get loading => false;
  @override
  String? get errorMessage => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoHealth extends ChangeNotifier implements HealthSyncController {
  @override
  bool get available => false;
  @override
  bool get connected => false;
  @override
  bool get busy => false;
  @override
  String? get error => null;
  @override
  String get providerName => 'Apple Health';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingActivities extends DemoActivityRepository {
  _CountingActivities(this.onWatch);

  final void Function() onWatch;

  @override
  Stream<List<ActivitySummary>> watchActivities({int? limit}) {
    onWatch();
    return super.watchActivities(limit: limit);
  }
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
