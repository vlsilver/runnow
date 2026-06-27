import 'dart:convert';

import 'package:myrun/src/tracking_session.dart';
import 'package:myrun/src/tracking_draft_storage_stub.dart'
    if (dart.library.io) 'package:myrun/src/tracking_draft_storage_io.dart';

class TrackingDraft {
  const TrackingDraft({required this.session, this.gpsWarmup});

  final TrackingSession session;
  final Map<String, dynamic>? gpsWarmup;

  TrackingSessionSnapshot snapshot() => session.snapshot();

  Map<String, dynamic> toMap() {
    return {
      'schemaVersion': 1,
      'session': session.toDraftMap(),
      if (gpsWarmup != null) 'gpsWarmup': gpsWarmup,
    };
  }

  factory TrackingDraft.fromMap(Map<String, dynamic> map) {
    return TrackingDraft(
      session: TrackingSession.fromDraftMap(
        map['session'] as Map<String, dynamic>,
      ),
      gpsWarmup: map['gpsWarmup'] as Map<String, dynamic>?,
    );
  }
}

class TrackingDraftStore {
  const TrackingDraftStore();

  Future<void> clear() => createDraftStorage().clear();

  Future<TrackingDraft?> load() async {
    final storage = createDraftStorage();
    final raw = await storage.read();
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return TrackingDraft.fromMap(map);
    } catch (_) {
      await storage.clear();
      return null;
    }
  }

  Future<void> save(TrackingDraft draft) =>
      createDraftStorage().write(jsonEncode(draft.toMap()));
}
