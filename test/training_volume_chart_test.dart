import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/period_keys.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/repository.dart';
import 'package:myrun/src/widgets/training_volume_chart.dart';

void main() {
  Future<void> pumpChart(
    WidgetTester tester, {
    required List<PeriodStat> stats,
    required Widget chart,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          memberRepositoryProvider.overrideWithValue(
            _FakeMemberRepository(stats),
          ),
        ],
        child: MaterialApp(home: Scaffold(body: chart)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders weekly training distance by day', (tester) async {
    await pumpChart(
      tester,
      stats: [
        _dayStat('2026-06-01', 5000),
        _dayStat('2026-06-02', 3200),
      ],
      chart: TrainingVolumeChart(
        uid: 'member',
        now: DateTime(2026, 6, 2),
        period: TrainingVolumePeriod.week,
      ),
    );

    expect(find.text('THEO NGÀY'), findsOneWidget);
    expect(find.text('8.2 km'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('T2'), findsOneWidget);
    expect(find.text('CN'), findsOneWidget);
  });

  testWidgets('renders monthly training distance by month labels', (
    tester,
  ) async {
    await pumpChart(
      tester,
      stats: [_monthStat('2026-06', 12000, activityCount: 2)],
      chart: TrainingVolumeChart(
        uid: 'member',
        now: DateTime(2026, 6, 15),
        period: TrainingVolumePeriod.month,
      ),
    );

    expect(find.text('THEO TUẦN'), findsOneWidget);
    expect(find.text('12.0 km'), findsWidgets);
    expect(find.text('07/2025'), findsOneWidget);
    expect(find.text('06/2026'), findsOneWidget);
  });

  testWidgets('renders eight week training distance trend', (tester) async {
    await pumpChart(
      tester,
      stats: [
        _weekStat(weekKey(DateTime(2026, 4, 14)), 5000),
        _weekStat(weekKey(DateTime(2026, 6, 2)), 7000),
      ],
      chart: TrainingVolumeChart(
        uid: 'member',
        now: DateTime(2026, 6, 3),
        period: TrainingVolumePeriod.eightWeeks,
      ),
    );

    expect(find.text('THEO TUẦN'), findsOneWidget);
    expect(find.text('12.0 km'), findsOneWidget);
    expect(find.text('T-7'), findsOneWidget);
    expect(find.text('NAY'), findsOneWidget);
  });

  testWidgets('switches between bar and line chart across time ranges', (
    tester,
  ) async {
    await pumpChart(
      tester,
      stats: [
        _monthStat('2025-08', 6000),
        _monthStat('2026-06', 7000),
      ],
      chart: TrainingVolumeChart(
        uid: 'member',
        now: DateTime(2026, 6, 3),
        period: TrainingVolumePeriod.month,
        showControls: true,
      ),
    );

    expect(find.text('KIỂU'), findsOneWidget);
    expect(find.text('RANGE'), findsOneWidget);
    expect(find.byType(BarChart), findsOneWidget);

    await tester.tap(find.text('KIỂU'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Line').last);
    await tester.pumpAndSettle();
    expect(find.byType(LineChart), findsOneWidget);

    await tester.tap(find.text('RANGE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Quý').last);
    await tester.pumpAndSettle();
    expect(find.text('Q2/2026'), findsOneWidget);

    await tester.tap(find.text('RANGE'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Năm').last);
    await tester.pumpAndSettle();
    expect(find.text('THEO THÁNG'), findsOneWidget);
    expect(find.text('2025'), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);
  });
}

PeriodStat _dayStat(String key, double distanceMeters) =>
    _stat('day', key, distanceMeters, 1);

PeriodStat _weekStat(String key, double distanceMeters) =>
    _stat('week', key, distanceMeters, 1);

PeriodStat _monthStat(
  String key,
  double distanceMeters, {
  int activityCount = 1,
}) => _stat('month', key, distanceMeters, activityCount);

PeriodStat _stat(
  String periodType,
  String periodKey,
  double distanceMeters,
  int activityCount,
) {
  return PeriodStat(
    periodType: periodType,
    periodKey: periodKey,
    stats: LeaderboardStats(
      distanceMeters: distanceMeters,
      movingTimeSeconds: 1800,
      activityCount: activityCount,
      activeDays: 1,
      longestDistanceMeters: distanceMeters,
      fastestPaceSecondsPerKm: null,
    ),
  );
}

class _FakeMemberRepository implements MemberRepository {
  _FakeMemberRepository(this.stats);

  final List<PeriodStat> stats;

  @override
  Future<List<PeriodStat>> listMemberPeriodStats(
    String uid, {
    required String periodType,
    required String fromKey,
    required String toKeyInclusive,
  }) async {
    return [
      for (final stat in stats)
        if (stat.periodType == periodType &&
            stat.periodKey.compareTo(fromKey) >= 0 &&
            stat.periodKey.compareTo(toKeyInclusive) <= 0)
          stat,
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
