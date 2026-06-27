import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Lưu draft tracking ra file (mobile/desktop có dart:io).
class DraftStorage {
  const DraftStorage();

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/tracking/current_trial_session.json');
  }

  Future<String?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    try {
      return await file.readAsString();
    } catch (_) {
      await file.delete();
      return null;
    }
  }

  Future<void> write(String data) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(data, flush: true);
  }

  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) {
      await file.delete();
    }
  }
}

DraftStorage createDraftStorage() => const DraftStorage();
