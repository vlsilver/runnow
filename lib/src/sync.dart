import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:myrun/src/repository.dart';

class SyncController extends ChangeNotifier {
  SyncController(this._repository);
  final ActivityRepository _repository;

  bool syncing = false;
  String? message;
  bool lastSyncSucceeded = false;

  void startBackgroundSync() {
    unawaited(sync());
  }

  Future<void> sync() async {
    if (syncing) return;
    syncing = true;
    message = null;
    notifyListeners();
    try {
      final imported = await _repository.sync();
      lastSyncSucceeded = true;
      message = 'Đồng bộ Strava hoàn tất: $imported hoạt động.';
    } catch (error) {
      lastSyncSucceeded = false;
      message = 'Không thể đồng bộ Strava: $error';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }
}
