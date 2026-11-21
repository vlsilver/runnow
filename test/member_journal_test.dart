import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/activity_eligibility.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/screens/member_profile_screen.dart';

ActivitySummary _activity(String name, ActivityKind kind, int day) =>
    ActivitySummary(
      id: name,
      name: name,
      kind: kind,
      startedAt: DateTime(2026, 11, day, 6),
      distanceMeters: 5000,
      movingTimeSeconds: 1800,
      elapsedTimeSeconds: 1900,
      hydrated: true,
    );

void main() {
  final activities = [
    _activity('Chạy sáng', ActivityKind.run, 6),
    _activity('Đi dạo', ActivityKind.walk, 4),
    _activity('Đạp xe hồ', ActivityKind.ride, 5),
    _activity('Chạy trail', ActivityKind.trailRun, 3),
    _activity('Bơi', ActivityKind.swim, 2),
  ];
  const steps = [StepDay(date: '2026-11-05', steps: 8000)];

  List<String> names(JournalTab tab) => [
    for (final row in memberJournalRows(
      tab: tab,
      activities: activities,
      stepDays: steps,
    ))
      row.activity?.name ?? 'bước ${row.step!.date}',
  ];

  test('nhật ký thành viên chia buổi theo môn, mới nhất ở trên', () {
    expect(names(JournalTab.run), ['Chạy sáng', 'Chạy trail']);
    expect(names(JournalTab.ride), ['Đạp xe hồ']);
  });

  test('thẻ bước chỉ nằm ở tab Đi bộ, xếp theo ngày cùng buổi đi bộ', () {
    expect(names(JournalTab.walk), ['bước 2026-11-05', 'Đi dạo']);
  });
}
