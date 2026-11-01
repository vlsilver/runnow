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

  test('tổng của ngày: số buổi và tổng km', () {
    ActivitySummary run(double meters) => ActivitySummary(
      id: '$meters',
      name: '',
      kind: ActivityKind.run,
      startedAt: DateTime(2026, 10, 30),
      distanceMeters: meters,
      movingTimeSeconds: 0,
      elapsedTimeSeconds: 0,
    );
    // 8.2 + 5.1 + 3.0 = 16.3
    expect(
      clubRunsDayTotal([run(8200), run(5100), run(3000)]),
      '3 buổi · 16.3 km',
    );
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

    test('đọc dáng tuyến; dáng hỏng thì bỏ dáng, giữ buổi', () {
      Map<String, dynamic> run(String id, Object? sketch) => {
        'ownerUid': 'u1',
        'activity': {
          'id': id,
          'sportType': 'Run',
          'startedAt': '2026-10-30T04:10:00Z',
          'routeSketch': sketch,
        },
      };
      final page = clubRunsPageFromJson({
        'runs': [
          run('ok', [0, 500, 1000, 500, 1000, 0]),
          run('le', [0, 500, 1000]),
          run('chu', [0, 'x']),
          run('thieu', null),
        ],
      });
      expect(page.runs.map((r) => r.activity.routeSketch).toList(), [
        [0, 500, 1000, 500, 1000, 0],
        null,
        null,
        null,
      ]);
    });

    test('không có cursor là hết trang', () {
      expect(clubRunsPageFromJson({'runs': []}).cursor, isNull);
    });
  });
}
