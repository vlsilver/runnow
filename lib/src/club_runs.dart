import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';

/// Một buổi trong feed club (`GET /v1/club/runs`).
class ClubRunItem {
  const ClubRunItem({required this.ownerUid, required this.activity});

  final String ownerUid;
  final ActivitySummary activity;
}

typedef ClubRunsPage = ({List<ClubRunItem> runs, String? cursor});

/// Dòng hỏng (thiếu uid hay buổi) bị bỏ và ghi log, để một dòng lỗi không làm
/// mất cả trang.
ClubRunsPage clubRunsPageFromJson(Map<String, dynamic> json) {
  final runs = <ClubRunItem>[];
  for (final raw in json['runs'] as List<dynamic>? ?? const []) {
    try {
      final item = raw as Map<String, dynamic>;
      runs.add(
        ClubRunItem(
          ownerUid: item['ownerUid'] as String,
          activity: ActivitySummary.fromMap(
            item['activity'] as Map<String, dynamic>,
            includeRoutePoints: false,
            includePhotos: false,
          ),
        ),
      );
    } on Object catch (error) {
      debugPrint('Bỏ một dòng feed club hỏng: $error');
    }
  }
  return (runs: runs, cursor: json['cursor'] as String?);
}

Future<ClubRunsPage> fetchClubRuns(
  RunNowApiClient api, {
  String? cursor,
  int? limit,
}) async {
  return clubRunsPageFromJson(
    await api.getClubRuns(cursor: cursor, limit: limit),
  );
}

/// Dòng tổng cạnh tiêu đề ngày ở trang "Buổi chạy": "3 buổi · 16.3 km".
String clubRunsDayTotal(Iterable<ActivitySummary> runs) {
  final meters = runs.fold<double>(0, (sum, run) => sum + run.distanceMeters);
  return '${runs.length} buổi · ${(meters / 1000).toStringAsFixed(1)} km';
}

const _hubClubRunsLimit = 5;

/// Mấy buổi mới nhất cho mục "Buổi chạy" ở trang Kèo.
final hubClubRunsProvider = FutureProvider.autoDispose<List<ClubRunItem>>((
  ref,
) async {
  final page = await fetchClubRuns(
    ref.watch(runNowApiClientProvider),
    limit: _hubClubRunsLimit,
  );
  return page.runs;
});
