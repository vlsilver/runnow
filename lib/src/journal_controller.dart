import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:myrun/src/repository.dart';

/// Giữ state trang Nhật ký (list + phân trang) trong 1 `ChangeNotifier` sống
/// độc lập với vòng đời widget — trước đây state này nằm trong
/// `_JournalScreenState`, nên mỗi lần rời màn rồi quay lại
/// (`context.push('/profile/journal')` tạo widget mới) đều phải chờ lại
/// đúng round-trip Firestore từ đầu, dù vừa mới xem xong (~2s mỗi lần bấm
/// vào, theo báo cáo thực tế). Provider không autoDispose nên cache này
/// sống suốt phiên app — [ensureLoaded] trả về ngay nếu đã có cache, đồng
/// thời âm thầm refresh trang đầu ở nền để không stale mãi.
class JournalController extends ChangeNotifier {
  JournalController(this._repository);

  static const _pageSize = 20;

  final ActivityRepository _repository;

  List<JournalActivityEntry> items = [];
  Object? _cursor;
  bool loadingInitial = true;
  bool loadingMore = false;
  bool hasMore = true;
  Object? error;
  bool _loadedOnce = false;

  /// Gọi từ `initState` của màn hình — chỉ fetch thật nếu chưa từng tải
  /// trong phiên này; ngược lại hiện cache ngay và refresh ngầm.
  Future<void> ensureLoaded() {
    if (_loadedOnce) {
      unawaited(_silentRefresh());
      return Future.value();
    }
    return loadFirstPage();
  }

  Future<void> loadFirstPage() async {
    loadingInitial = true;
    loadingMore = false;
    hasMore = true;
    _cursor = null;
    error = null;
    items = [];
    notifyListeners();
    await _loadPage(reset: true);
  }

  Future<void> loadNextPage() => _loadPage(reset: false);

  Future<void> _loadPage({required bool reset}) async {
    if (!reset && (!hasMore || loadingMore || loadingInitial)) return;
    if (!reset) {
      loadingMore = true;
      notifyListeners();
    }
    try {
      final page = await _repository.fetchJournalActivitiesPage(
        limit: _pageSize,
        cursor: _cursor,
      );
      if (reset) items = [];
      final existingIds = items.map((entry) => entry.activity.id).toSet();
      items = [
        ...items,
        ...page.entries.where((entry) => existingIds.add(entry.activity.id)),
      ];
      _cursor = page.nextCursor;
      hasMore = page.hasMore;
      error = null;
    } catch (e) {
      error = e;
    } finally {
      loadingInitial = false;
      loadingMore = false;
      _loadedOnce = true;
      notifyListeners();
    }
  }

  /// Tải lại trang đầu ở nền, không bật [loadingInitial] (tránh chớp
  /// skeleton khi user chỉ đơn giản quay lại màn đã xem) — lỗi thì bỏ qua
  /// êm, giữ nguyên cache cũ đang hiện.
  Future<void> _silentRefresh() async {
    if (loadingInitial || loadingMore) return;
    try {
      final page = await _repository.fetchJournalActivitiesPage(
        limit: _pageSize,
      );
      items = page.entries;
      _cursor = page.nextCursor;
      hasMore = page.hasMore;
      error = null;
      notifyListeners();
    } catch (_) {
      // Vẫn còn cache cũ để hiện — không cần báo lỗi cho 1 refresh ngầm.
    }
  }
}
