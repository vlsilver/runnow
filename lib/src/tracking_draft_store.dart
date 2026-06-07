import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:myrun/src/tracking_session.dart';

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

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<TrackingDraft?> load() async {
    final file = await _file();
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return TrackingDraft.fromMap(map);
    } catch (_) {
      await file.delete();
      return null;
    }
  }

  Future<void> save(TrackingDraft draft) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(draft.toMap()), flush: true);
  }

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/tracking/current_trial_session.json');
  }
}
