import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/training_plan/plan_schedule_view.dart';
import 'package:myrun/src/training_plan/training_plan_models.dart';

/// Giáo án hai tuần bắt đầu Thứ Hai 02/11/2026. Tuần 1: chạy nhẹ 5 km (T2),
/// tempo 6 km (T4). Tuần 2: chạy dài 12 km (T3), về đích 10 km (CN).
TrainingPlan _plan({List<String>? weekThemes, bool firstDone = false}) {
  Map<String, dynamic> day(
    int week,
    String type,
    String title, {
    double? km,
    String? purpose,
    bool done = false,
  }) => {
    'week': week,
    'label': '',
    'type': type,
    'title': title,
    'distanceKm': ?km,
    'purpose': ?purpose,
    'done': done,
  };
  final rest = day(0, 'rest', 'Nghỉ');
  return TrainingPlan.fromMap('p1', {
    'goal': 'Chạy 10km dưới 60 phút',
    'goalDistanceKm': 10,
    'weeks': 2,
    'startDate': '2026-11-02',
    'targetDate': '2026-11-15',
    'summary': '',
    'weekThemes': ?weekThemes,
    'days': [
      day(
        1,
        'easy',
        'Chạy nhẹ',
        km: 5,
        purpose: 'Làm quen lại với nhịp chạy đều.',
        done: firstDone,
      ),
      {...rest, 'week': 1},
      day(1, 'tempo', 'Tempo', km: 6),
      for (var i = 0; i < 4; i++) {...rest, 'week': 1},
      {...rest, 'week': 2},
      day(2, 'long', 'Chạy dài', km: 12),
      for (var i = 0; i < 4; i++) {...rest, 'week': 2},
      day(2, 'race', 'Về đích 10km', km: 10),
    ],
  });
}

Future<void> _pump(
  WidgetTester tester,
  TrainingPlan plan, {
  required DateTime today,
  void Function(TrainingDay)? onOpenDay,
  void Function(TrainingDay)? onToggleDone,
}) async {
  tester.view.physicalSize = const Size(390, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildRunNowTheme(
        RunNowElement.water,
        appearance: RunNowAppearance.light,
      ),
      home: Scaffold(
        body: PlanScheduleView(
          plan: plan,
          today: today,
          onOpenDay: onOpenDay,
          onToggleDone: onToggleDone,
        ),
      ),
    ),
  );
}

void main() {
  group('TrainingDay purpose', () {
    test('uses what the coach wrote, else the line of its workout type', () {
      final days = _plan().days;
      expect(days[0].purposeText, 'Làm quen lại với nhịp chạy đều.');
      expect(days[2].purpose, isNull);
      expect(days[2].purposeText, 'Tập giữ nhịp nhanh mà không đuối.');
    });

    test('a blank purpose from the backend counts as missing', () {
      final day = TrainingDay.fromMap({
        'type': 'long',
        'purpose': '  ',
      }, date: DateTime(2026, 11, 2));
      expect(day.purposeText, 'Tập cho cơ thể quen chạy lâu như ngày đua.');
    });
  });

  group('TrainingPlan.weekTheme', () {
    test('takes the coach theme for that week', () {
      final plan = _plan(weekThemes: ['Xây nền', 'Về đích']);
      expect(plan.weekTheme(1), 'Xây nền');
      expect(plan.weekTheme(2), 'Về đích');
    });

    test('without themes only the race week is named', () {
      final plan = _plan();
      expect(plan.weekTheme(1), isNull);
      expect(plan.weekTheme(2), 'Giảm tải, về đích');
    });
  });

  testWidgets('today card says what the session is for', (tester) async {
    await _pump(tester, _plan(), today: DateTime(2026, 11, 4));

    expect(find.text('HÔM NAY · GIỮ NHỊP'), findsOneWidget);
    expect(
      find.textContaining('Để làm gì: Tập giữ nhịp nhanh', findRichText: true),
      findsOneWidget,
    );
  });

  testWidgets('opens on the current week and switches when a week is tapped', (
    tester,
  ) async {
    await _pump(tester, _plan(), today: DateTime(2026, 11, 2));

    expect(find.text('TUẦN 1 · 11 KM'), findsOneWidget);
    expect(find.text('Làm quen lại với nhịp chạy đều.'), findsOneWidget);
    expect(find.textContaining('Chạy dài', findRichText: true), findsNothing);

    await tester.tap(find.byKey(const ValueKey('plan-week-2')));
    await tester.pump();

    expect(find.text('TUẦN 2 · 22 KM · GIẢM TẢI, VỀ ĐÍCH'), findsOneWidget);
    expect(find.textContaining('Chạy dài', findRichText: true), findsOneWidget);
    expect(find.text('Làm quen lại với nhịp chạy đều.'), findsNothing);
  });

  testWidgets('rest days are left out of the week list', (tester) async {
    await _pump(tester, _plan(), today: DateTime(2026, 11, 2));
    expect(find.textContaining('Nghỉ', findRichText: true), findsNothing);
  });

  testWidgets('progress counts done sessions out of real sessions', (
    tester,
  ) async {
    await _pump(tester, _plan(firstDone: true), today: DateTime(2026, 11, 3));
    expect(find.textContaining('1/4', findRichText: true), findsOneWidget);
  });

  testWidgets('a viewer who has not joined cannot mark or open sessions', (
    tester,
  ) async {
    await _pump(tester, _plan(), today: DateTime(2026, 11, 4));

    expect(find.byKey(const ValueKey('plan-today-done')), findsNothing);
    expect(find.text('Bắt đầu'), findsNothing);
  });

  testWidgets('today card says Đã xong once the session is marked done', (
    tester,
  ) async {
    await _pump(
      tester,
      _plan(firstDone: true),
      today: DateTime(2026, 11, 2),
      onToggleDone: (_) {},
    );

    expect(find.text('Đã xong'), findsOneWidget);
    expect(find.text('Bắt đầu'), findsNothing);
  });

  testWidgets('the check button marks today and Bắt đầu opens the session', (
    tester,
  ) async {
    final opened = <String>[];
    final toggled = <String>[];
    await _pump(
      tester,
      _plan(),
      today: DateTime(2026, 11, 4),
      onOpenDay: (d) => opened.add(d.title),
      onToggleDone: (d) => toggled.add(d.title),
    );

    await tester.tap(find.byKey(const ValueKey('plan-today-done')));
    await tester.tap(find.text('Bắt đầu'));

    expect(toggled, ['Tempo']);
    expect(opened, ['Tempo']);
  });

  test('session colours get stronger with load, in the chosen accent', () {
    for (final element in RunNowElement.values) {
      final palette = RunNowPalette.forSelection(
        element,
        appearance: RunNowAppearance.light,
      );
      double lum(WorkoutType t) =>
          workoutLoadColor(t, palette).computeLuminance();
      expect(workoutLoadColor(WorkoutType.long, palette), palette.accent);
      expect(lum(WorkoutType.easy), greaterThan(lum(WorkoutType.long)));
      expect(lum(WorkoutType.long), greaterThan(lum(WorkoutType.tempo)));
      expect(lum(WorkoutType.tempo), greaterThan(lum(WorkoutType.interval)));
    }
  });
}
