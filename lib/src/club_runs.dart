import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
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

/// "vừa xong", "25 phút trước", "16 giờ trước", "hôm qua", hoặc "25/10".
String feedWhenLabel(DateTime startedAt, DateTime now) {
  final local = startedAt.toLocal();
  final ago = now.difference(local);
  if (ago.inMinutes < 1) return 'vừa xong';
  if (ago.inMinutes < 60) return '${ago.inMinutes} phút trước';
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final daysAgo = today.difference(day).inDays;
  if (daysAgo == 0) return '${ago.inHours} giờ trước';
  if (daysAgo == 1) return 'hôm qua';
  return DateFormat('dd/MM').format(local);
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
