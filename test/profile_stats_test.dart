import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/profile_stats.dart';

LeaderboardStats run(
  double km, {
  int seconds = 0,
  int days = 0,
  int count = 1,
  double longestKm = 0,
  double? fastest,
}) => LeaderboardStats(
  distanceMeters: km * 1000,
  movingTimeSeconds: seconds,
  activityCount: count,
  activeDays: days,
  longestDistanceMeters: longestKm * 1000,
  fastestPaceSecondsPerKm: fastest,
);

// Thứ tư.
final today = DateTime(2026, 10, 14, 21, 30);

ProfileStatsData data({
  Map<String, LeaderboardStats> days = const {},
  Map<String, LeaderboardStats> weeks = const {},
  Map<String, LeaderboardStats> months = const {},
}) => ProfileStatsData(today: today, days: days, weeks: weeks, months: months);

void main() {
  test('tải doc ngày từ đầu tháng trước và tháng này của năm ngoái', () {
    // Lưới bắt đầu thứ 2 14/9, 28 ngày bắt đầu 17/9, tháng trước bắt đầu 1/9.
    expect(profileDayRanges(today), [
      ('2026-09-01', '2026-10-14'),
      ('2025-10-01', '2025-10-14'),
    ]);
  });

  test('tuần so với tuần trước tính tới cùng thứ', () {
    final d = data(
      weeks: {'2026-W42': run(8, seconds: 2400)},
      days: {
        '2026-10-05': run(4, seconds: 1200),
        '2026-10-07': run(2, seconds: 720),
        // Thứ sáu tuần trước: sau thứ tư nên không tính.
        '2026-10-09': run(10, seconds: 3000),
      },
    );
    final p = d.progress(ProfilePeriod.week);
    expect(p.points.length, 12);
    expect(p.points.last.label, '42');
    expect(p.previous.distanceMeters, 6000);
    // 8 km so với 6 km.
    expect(
      metricDelta(p.current, p.previous, ProfileMetric.distance)?.text,
      '+33%',
    );
    // 2400 s so với 1920 s.
    expect(
      metricDelta(p.current, p.previous, ProfileMetric.time)?.text,
      '+25%',
    );
    // 5:00/km so với 5:20/km.
    expect(metricDelta(p.current, p.previous, ProfileMetric.pace), (
      text: 'nhanh hơn 0:20',
      better: true,
    ));
  });

  test('kỳ trước trống thì không so', () {
    final p = data(
      weeks: {'2026-W42': run(8, seconds: 2400)},
    ).progress(ProfilePeriod.week);
    expect(metricDelta(p.current, p.previous, ProfileMetric.distance), isNull);
    expect(metricDelta(p.current, p.previous, ProfileMetric.pace), isNull);
  });

  test('lưới 5 tuần: hôm nay chưa chạy không làm đứt chuỗi', () {
    final d = data(
      days: {
        for (final day in [20, 21, 22, 23, 24]) '2026-09-$day': run(5),
        '2026-10-09': run(5),
        '2026-10-11': run(5),
        '2026-10-12': run(5),
        '2026-10-13': run(5),
      },
    );
    final c = d.consistency(ProfilePeriod.day);
    expect(c.cells.length, 35);
    expect(c.cells.first.date, DateTime(2026, 9, 14));
    expect(c.cells.where((x) => x.future).length, 4);
    expect(c.cells.singleWhere((x) => x.today).date, DateTime(2026, 10, 14));
    // 14/9 tới 14/10 là 31 ngày đã qua.
    expect(c.headline, '9/31 ngày có chạy');
    expect(c.sub, 'Chuỗi hiện tại 3 ngày · dài nhất 5 ngày');
  });

  test('năm so với cùng kỳ năm trước lấy doc ngày cho tháng này', () {
    final d = data(
      months: {
        '2025-03': run(20, days: 4),
        // Doc tháng gồm cả 20/10 (sau ngày 14) nên không được dùng để so.
        '2025-10': run(50, days: 6),
        '2026-02': run(15, days: 3),
        '2026-10': run(25, days: 5),
      },
      days: {'2025-10-05': run(10), '2025-10-20': run(40)},
    );
    final p = d.progress(ProfilePeriod.year);
    expect(p.points.map((x) => x.label), ['2025', '2026']);
    expect(p.current.distanceMeters, 40000);
    expect(p.previous.distanceMeters, 30000);
    final c = d.consistency(ProfilePeriod.year);
    expect(c.headline, '8 ngày chạy năm nay');
    // 8 ngày trong 287 ngày đã qua của năm = 0,195 ngày/tuần.
    expect(c.sub, 'Năm ngoái 10 ngày · trung bình 0,2 ngày/tuần');
  });

  test('kỷ lục và số trọn đời lấy từ doc tháng', () {
    final d = data(
      months: {
        '2024-03': run(
          30,
          seconds: 10800,
          days: 6,
          longestKm: 21.1,
          fastest: 340,
        ),
        '2026-10': run(
          40,
          seconds: 12000,
          days: 8,
          longestKm: 10,
          fastest: 328,
        ),
        '2025-01': run(0, count: 0),
      },
    );
    expect(d.isEmpty, isFalse);
    expect(d.firstMonthKey, '2024-03');
    expect(d.lifetime.distanceMeters, 70000);
    expect(d.lifetime.activeDays, 14);
    expect(d.longestRun, (meters: 21100.0, monthKey: '2024-03'));
    expect(d.fastestRun, (secondsPerKm: 328.0, monthKey: '2026-10'));
    expect(profileHours(d.lifetime.movingTimeSeconds), '6h20');
    expect(profileInt(2248.4), '2.248');
  });

  test('chưa có buổi chạy nào là trống', () {
    expect(data(months: {'2026-10': run(0, count: 0)}).isEmpty, isTrue);
  });

  test('PeriodStat đọc field run*, doc cũ thiếu field thì là 0', () {
    final stat = PeriodStat.fromMap({
      'periodType': 'month',
      'periodKey': '2026-10',
      'distanceMeters': 18800,
      'runDistanceMeters': 15800,
      'runMovingTimeSeconds': 4980,
      'runCount': 3,
      'runActiveDays': 2,
      'runLongestDistanceMeters': 10000,
      'runFastestPaceSecondsPerKm': 300,
    });
    expect(stat.stats.distanceMeters, 18800);
    expect(stat.run.distanceMeters, 15800);
    expect(stat.run.movingTimeSeconds, 4980);
    expect(stat.run.activityCount, 3);
    expect(stat.run.activeDays, 2);
    expect(stat.run.longestDistanceMeters, 10000);
    expect(stat.run.fastestPaceSecondsPerKm, 300);
    final old = PeriodStat.fromMap({'distanceMeters': 5000});
    expect(old.run.distanceMeters, 0);
    expect(old.run.fastestPaceSecondsPerKm, isNull);
  });
}
