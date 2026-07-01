import 'dart:async';

import 'package:flutter/foundation.dart';
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
  bool _autoSyncStarted = false;
  Future<SyncResult>? _inFlight;

  void startBackgroundSync({bool force = false}) {
    if (!force && _autoSyncStarted) return;
    if (!force) _autoSyncStarted = true;
    unawaited(sync());
  }

  Future<SyncResult> sync() {
    final existing = _inFlight;
    if (existing != null) return existing;
    final future = _performSync();
    _inFlight = future;
    future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
    return future;
  }

  Future<SyncResult> _performSync() async {
    syncing = true;
    message = null;
    notifyListeners();
    try {
      final changed = await _repository.sync();
      lastSyncSucceeded = true;
      completedRevision += 1;
      message = changed == 0
          ? 'Đồng bộ Strava hoàn tất. Không có hoạt động mới.'
          : 'Đồng bộ Strava hoàn tất: cập nhật $changed hoạt động.';
      return SyncResult(succeeded: true, changedActivities: changed);
    } catch (error) {
      lastSyncSucceeded = false;
      message = 'Không thể đồng bộ Strava: $error';
      return SyncResult(succeeded: false, changedActivities: 0, error: error);
    } finally {
      syncing = false;
      notifyListeners();
    }
  }
}
