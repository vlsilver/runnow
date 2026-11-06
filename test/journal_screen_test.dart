import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/repository.dart';
import 'package:myrun/src/screens/journal_screen.dart';
import 'package:myrun/src/theme_controller.dart';
import 'package:myrun/src/widgets/run_now_loading.dart';

/// Trả nhật ký theo trang, mới trước, như backend; còn lại không dùng tới.
class _PagedRepository implements ActivityRepository {
  _PagedRepository(this.activities);

  final List<ActivitySummary> activities;
  int pageReads = 0;

  @override
  Future<JournalActivityPage> fetchJournalActivitiesPage({
    int limit = 30,
    Object? cursor,
  }) async {
    pageReads++;
    final start = cursor as int? ?? 0;
    final end = (start + limit).clamp(0, activities.length);
    return JournalActivityPage(
      entries: [
        for (final a in activities.sublist(start, end))
          JournalActivityEntry(activity: a),
      ],
      nextCursor: end,
      hasMore: end < activities.length,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Như [_PagedRepository] nhưng mỗi trang chỉ về khi test mở cổng của nó.
class _GatedRepository extends _PagedRepository {
  _GatedRepository(super.activities);

  final gates = <Completer<void>>[];

  @override
  Future<JournalActivityPage> fetchJournalActivitiesPage({
    int limit = 30,
    Object? cursor,
  }) async {
    final gate = Completer<void>();
    gates.add(gate);
    await gate.future;
    return super.fetchJournalActivitiesPage(limit: limit, cursor: cursor);
  }
}

ActivitySummary _activity(String name, ActivityKind kind, int daysAgo) =>
    ActivitySummary(
      id: name,
      name: name,
      kind: kind,
      startedAt: DateTime(2026, 11, 6).subtract(Duration(days: daysAgo)),
      distanceMeters: 5000,
      movingTimeSeconds: 1800,
      elapsedTimeSeconds: 1900,
      hydrated: true,
    );

Future<_PagedRepository> _pumpJournal(
  WidgetTester tester,
  List<ActivitySummary> activities, {
  List<StepDay> stepDays = const [],
}) async {
  final repository = _PagedRepository(activities);
  await _pumpScreen(tester, repository, stepDays: stepDays);
  await tester.pumpAndSettle();
  return repository;
}

Future<void> _pumpScreen(
  WidgetTester tester,
  ActivityRepository repository, {
  List<StepDay> stepDays = const [],
}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        activityRepositoryProvider.overrideWithValue(repository),
        myStepDaysProvider.overrideWith((ref) => Stream.value(stepDays)),
        themeControllerProvider.overrideWith(
          (ref) => ThemeController(loadFromStorage: false),
        ),
      ],
      child: const MaterialApp(home: JournalScreen()),
    ),
  );
}

void main() {
  testWidgets('mỗi tab chỉ hiện đúng loại buổi của nó', (tester) async {
    await _pumpJournal(
      tester,
      [
        _activity('Chạy sáng', ActivityKind.run, 1),
        _activity('Đi dạo', ActivityKind.walk, 2),
        _activity('Đạp xe hồ', ActivityKind.ride, 3),
        _activity('Chạy trail', ActivityKind.trailRun, 4),
        _activity('Leo núi', ActivityKind.hike, 5),
        _activity('Bơi', ActivityKind.swim, 6),
      ],
      stepDays: const [StepDay(date: '2026-11-05', steps: 8000)],
    );

    expect(find.text('Chạy sáng'), findsOneWidget);
    expect(find.text('Chạy trail'), findsOneWidget);
    expect(find.text('Đi dạo'), findsNothing);
    expect(find.text('Đạp xe hồ'), findsNothing);
    expect(find.byType(StepTimelineRow), findsNothing);

    await tester.tap(find.text('Đi bộ'));
    await tester.pumpAndSettle();
    expect(find.text('Đi dạo'), findsOneWidget);
    expect(find.text('Leo núi'), findsOneWidget);
    expect(find.byType(StepTimelineRow), findsOneWidget);
    expect(find.text('Chạy sáng'), findsNothing);

    await tester.tap(find.text('Đạp xe'));
    await tester.pumpAndSettle();
    expect(find.text('Đạp xe hồ'), findsOneWidget);
    expect(find.text('Đi dạo'), findsNothing);
    expect(find.text('Bơi'), findsNothing);
  });

  testWidgets('tab thưa tự tải trang sau tới khi có buổi', (tester) async {
    // Trang đầu (20 buổi) toàn chạy; buổi đạp xe duy nhất nằm ở trang 2.
    final repository = await _pumpJournal(tester, [
      for (var i = 0; i < 25; i++)
        _activity('Chạy $i', ActivityKind.run, i + 1),
      _activity('Đạp xe xa', ActivityKind.ride, 40),
    ]);
    expect(repository.pageReads, 1);

    await tester.tap(find.text('Đạp xe'));
    await tester.pumpAndSettle();
    expect(find.text('Đạp xe xa'), findsOneWidget);
    expect(find.text('Chưa có hoạt động.'), findsNothing);
  });

  testWidgets('tab đang tự tải giữ icon tải liên tục giữa hai trang', (
    tester,
  ) async {
    final repository = _GatedRepository([
      for (var i = 0; i < 45; i++)
        _activity('Chạy $i', ActivityKind.run, i + 1),
      _activity('Đạp xe xa', ActivityKind.ride, 60),
    ]);
    await _pumpScreen(tester, repository);
    await tester.pump();
    repository.gates.single.complete();
    await tester.pump();

    await tester.tap(find.text('Đạp xe'));
    for (var i = 0; i < 10 && repository.gates.length < 2; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(repository.gates, hasLength(2));

    // Trang 2 về mà vẫn chưa có buổi đạp xe: frame ngay sau đó icon vẫn còn.
    repository.gates[1].complete();
    await tester.pump();
    expect(find.byType(RunNowLoading), findsOneWidget);
  });
}
