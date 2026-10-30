import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/club_runs.dart';
import 'package:myrun/src/models.dart';

void main() {
  group('feedWhenLabel', () {
    final now = DateTime(2026, 10, 30, 21, 0);

    test('phút, giờ, hôm qua, rồi ngày tháng', () {
      expect(
        feedWhenLabel(DateTime(2026, 10, 30, 20, 59, 40), now),
        'vừa xong',
      );
      expect(
        feedWhenLabel(DateTime(2026, 10, 30, 20, 35), now),
        '25 phút trước',
      );
      expect(feedWhenLabel(DateTime(2026, 10, 30, 4, 10), now), '16 giờ trước');
      expect(feedWhenLabel(DateTime(2026, 10, 29, 23, 30), now), 'hôm qua');
      expect(feedWhenLabel(DateTime(2026, 10, 25, 6), now), '25/10');
    });
  });

  group('ClubRunItem.fromJson', () {
    test('lấy uid người tập và buổi, bỏ qua dòng hỏng', () {
      final page = clubRunsPageFromJson({
        'runs': [
          {
            'ownerUid': 'u1',
            'activity': {
              'id': 'a1',
              'name': 'Chạy sáng',
              'sportType': 'Run',
              'startedAt': '2026-10-30T04:10:00Z',
              'distanceMeters': 8200,
              'movingTimeSeconds': 2723,
            },
          },
          {'ownerUid': 'u2'},
        ],
        'cursor': 'c1',
      });
      expect(page.cursor, 'c1');
      expect(page.runs, hasLength(1));
      final run = page.runs.single;
      expect(run.ownerUid, 'u1');
      expect(run.activity.id, 'a1');
      expect(run.activity.kind, ActivityKind.run);
      expect(run.activity.distanceMeters, 8200);
    });

    test('không có cursor là hết trang', () {
      expect(clubRunsPageFromJson({'runs': []}).cursor, isNull);
    });
  });
}
