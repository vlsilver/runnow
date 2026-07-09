import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/repository.dart';

class SyncResult {
  const SyncResult({
    required this.succeeded,
    required this.changedActivities,
    this.error,
  });

  final bool succeeded;
  final int changedActivities;
  final Object? error;
}

class SyncController extends ChangeNotifier {
  SyncController(this._repository);
  final ActivityRepository _repository;

  bool syncing = false;
  String? message;
  bool lastSyncSucceeded = false;
  int completedRevision = 0;
  List<ActivitySummary> lastChangedActivities = const [];
  bool _autoSyncStarted = false;
  Future<SyncResult>? _inFlight;

  void startBackgroundSync({bool force = false, bool fullResync = false}) {
    if (!force && _autoSyncStarted) return;
    if (!force) _autoSyncStarted = true;
    unawaited(sync(fullResync: fullResync));
  }

  Future<SyncResult> sync({bool fullResync = false}) {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = _performSync(fullResync: fullResync);
    _inFlight = future;
    future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
    return future;
  }

  Future<SyncResult> _performSync({bool fullResync = false}) async {
    syncing = true;
    message = null;
    notifyListeners();
    try {
      final outcome = await _repository.sync(fullResync: fullResync);
      lastSyncSucceeded = true;
      lastChangedActivities = outcome.changedActivities;
      completedRevision += 1;
      message = outcome.changedCount == 0
          ? 'Đồng bộ Strava hoàn tất. Không có hoạt động mới.'
          : 'Đồng bộ Strava hoàn tất: cập nhật ${outcome.changedCount} hoạt động.';
      return SyncResult(
        succeeded: true,
        changedActivities: outcome.changedCount,
      );
    } catch (error) {
      lastSyncSucceeded = false;
      lastChangedActivities = const [];
      message = 'Không thể đồng bộ Strava: $error';
      return SyncResult(succeeded: false, changedActivities: 0, error: error);
    } finally {
      syncing = false;
      notifyListeners();
    }
  }
}
