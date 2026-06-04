import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:myrun/src/repository.dart';

class SyncController extends ChangeNotifier {
  SyncController(this._repository);
  final ActivityRepository _repository;

  bool syncing = false;
  String? message;
  bool lastSyncSucceeded = false;
  bool _autoSyncStarted = false;

  void startBackgroundSync({bool force = false}) {
    if (!force && _autoSyncStarted) return;
    if (!force) _autoSyncStarted = true;
    unawaited(sync());
  }

  Future<void> sync() async {
    if (syncing) return;
    syncing = true;
    message = null;
    notifyListeners();
    try {
      final changed = await _repository.sync();
      lastSyncSucceeded = true;
      message = changed == 0
          ? 'Đồng bộ Strava hoàn tất. Không có hoạt động mới.'
          : 'Đồng bộ Strava hoàn tất: cập nhật $changed hoạt động.';
    } catch (error) {
      lastSyncSucceeded = false;
      message = 'Không thể đồng bộ Strava: $error';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }
}
