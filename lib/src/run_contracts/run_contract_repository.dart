import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';

/// Số kèo CHƯA HOÀN THÀNH tối đa mỗi người được tham gia (tạo + join) cùng lúc.
const int maxActiveRunContracts = 2;

class RunContractLimitReached implements Exception {
  const RunContractLimitReached();

  @override
  String toString() =>
      'Bạn đang tham gia $maxActiveRunContracts kèo chưa hoàn thành. '
      'Hãy chốt một kèo trước khi tạo hoặc tham gia kèo mới.';
}

abstract interface class RunContractRepository {
  /// Các kèo đang chạy mà user tham gia (tạo hoặc join) — tối đa
  /// [maxActiveRunContracts].
  Stream<List<RunContract>> watchMyActiveContracts();
  Stream<RunContract?> watchContract(String contractId);
  Stream<List<RunContract>> watchClubContracts();
  Future<String> create({
    required RunContractDraft draft,
    required RunContractPeriod period,
    required double initialProgress,
  });
  Future<void> updateProgress(String contractId, double progressValue);
  Future<void> join(String contractId, double initialProgress);
  Future<void> updateParticipantProgress(
    String contractId,
    double progressValue, {
    List<String> countedActivityIds,
  });

  /// ID các activity đã được các kèo KHÁC mà user tham gia (không tính kèo
  /// [excludeContractId] và kèo đã huỷ) ghi nhận — để loại trừ, một session chỉ
  /// tính cho đúng một kèo.
  Future<Set<String>> claimedActivityIds({required String excludeContractId});
  Future<RunContractStatus> finalize(
    String contractId, {
    required double finalProgress,
    required bool targetMet,
    List<String> countedActivityIds,
  });
}

class FirestoreRunContractRepository implements RunContractRepository {
  FirestoreRunContractRepository(this._auth, this._firestore);

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  String get _uid {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw StateError('Bạn chưa đăng nhập Firebase.');
    return uid;
  }

  CollectionReference<Map<String, dynamic>> get _contracts =>
      _firestore.collection('runContracts');

  @override
  Stream<List<RunContract>> watchMyActiveContracts() => _contracts
      .where('participantUids', arrayContains: _uid)
      .where('status', isEqualTo: RunContractStatus.active.value)
      .snapshots()
      .map(_sortedContracts);

  @override
  Stream<RunContract?> watchContract(String contractId) =>
      _contracts.doc(contractId).snapshots().map(_contractFromDocument);

  @override
  Stream<List<RunContract>> watchClubContracts() => _contracts
      .where('visibility', isEqualTo: RunContractVisibility.club.value)
      .where('status', isEqualTo: RunContractStatus.active.value)
      .snapshots()
      .map(_sortedContracts);

  List<RunContract> _sortedContracts(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final contracts = snapshot.docs
        .map(_contractFromDocument)
        .whereType<RunContract>()
        .toList();
    contracts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return contracts;
  }

  @override
  Future<String> create({
    required RunContractDraft draft,
    required RunContractPeriod period,
    required double initialProgress,
  }) async {
    final validation = draft.validate();
    if (validation != null) throw StateError(validation);
    await _ensureUnderLimit();
    final contractRef = _contracts.doc();
    await contractRef.set({
      'id': contractRef.id,
      'schemaVersion': 1,
      'type': 'group',
      'creatorUid': _uid,
      'title': _titleFor(draft),
      'templateId': draft.template.value,
      'metric': draft.metric.value,
      'targetValue': draft.targetValue,
      'periodType': period.type.value,
      'timezone': DateTime.now().timeZoneName,
      'timezoneOffsetMinutes': DateTime.now().timeZoneOffset.inMinutes,
      'startAt': Timestamp.fromDate(period.startAt),
      'endAtExclusive': Timestamp.fromDate(period.endAtExclusive),
      'finalizeAt': Timestamp.fromDate(period.finalizeAt),
      'status': RunContractStatus.active.value,
      'visibility': draft.visibility.value,
      'sourcePolicy': 'strava_only',
      'progressValue': initialProgress,
      'participantUids': [_uid],
      'participants': {
        _uid: {
          'uid': _uid,
          'progressValue': initialProgress,
          'joinedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      },
      'eligibilityVersion': 1,
      'lastCalculatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return contractRef.id;
  }

  Future<void> _ensureUnderLimit() async {
    if (await _activeParticipationCount() >= maxActiveRunContracts) {
      throw const RunContractLimitReached();
    }
  }

  Future<int> _activeParticipationCount() async {
    final snapshot = await _contracts
        .where('participantUids', arrayContains: _uid)
        .where('status', isEqualTo: RunContractStatus.active.value)
        .get();
    return snapshot.docs.length;
  }

  @override
  Future<void> updateProgress(String contractId, double progressValue) async {
    if (!progressValue.isFinite || progressValue < 0) {
      throw StateError('Tiến độ không hợp lệ.');
    }
    final ref = _contracts.doc(contractId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (data == null) throw StateError('Không tìm thấy kèo chạy.');
      if (RunContractStatus.fromValue(data['status'] as String?) !=
          RunContractStatus.active) {
        return;
      }
      final existing = (data['progressValue'] as num?)?.toDouble() ?? 0;
      if ((existing - progressValue).abs() < 0.000001) return;
      final participants = data['participants'];
      final creatorParticipant = participants is Map
          ? participants[_uid] as Map<String, dynamic>?
          : null;
      final joinedAt =
          creatorParticipant?['joinedAt'] ?? FieldValue.serverTimestamp();
      transaction.update(ref, {
        'progressValue': progressValue,
        'participants.$_uid': {
          'uid': _uid,
          'progressValue': progressValue,
          'joinedAt': joinedAt,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'lastCalculatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<void> join(String contractId, double initialProgress) async {
    _validateProgress(initialProgress);
    final ref = _contracts.doc(contractId);
    // Chặn vượt giới hạn nếu đây là kèo mới (chưa tham gia). Đọc trước transaction
    // vì transaction không chạy được query đếm.
    final pre = await ref.get();
    final preParticipants = pre.data()?['participants'] as Map<String, dynamic>?;
    if (preParticipants?.containsKey(_uid) != true) {
      await _ensureUnderLimit();
    }
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (data == null) throw StateError('Không tìm thấy kèo chạy.');
      if (RunContractStatus.fromValue(data['status'] as String?) !=
          RunContractStatus.active) {
        throw StateError('Kèo này đã kết thúc.');
      }
      if (RunContractVisibility.fromValue(data['visibility'] as String?) !=
          RunContractVisibility.club) {
        throw StateError('Kèo riêng tư không thể tham gia.');
      }
      final participants = data['participants'] as Map<String, dynamic>?;
      if (participants?.containsKey(_uid) == true) return;
      if (participants == null) {
        final creatorUid = data['creatorUid'] as String;
        transaction.update(ref, {
          'participants': {
            creatorUid: {
              'uid': creatorUid,
              'progressValue': (data['progressValue'] as num?)?.toDouble() ?? 0,
              'joinedAt': data['createdAt'],
              'updatedAt': data['updatedAt'],
            },
            _uid: {
              'uid': _uid,
              'progressValue': initialProgress,
              'joinedAt': FieldValue.serverTimestamp(),
              'updatedAt': FieldValue.serverTimestamp(),
            },
          },
          'participantUids': FieldValue.arrayUnion([creatorUid, _uid]),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        return;
      }
      transaction.update(ref, {
        'participants.$_uid': {
          'uid': _uid,
          'progressValue': initialProgress,
          'joinedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'participantUids': FieldValue.arrayUnion([_uid]),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<void> updateParticipantProgress(
    String contractId,
    double progressValue, {
    List<String> countedActivityIds = const [],
  }) async {
    _validateProgress(progressValue);
    final ref = _contracts.doc(contractId);
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (data == null) throw StateError('Không tìm thấy kèo chạy.');
      if (RunContractStatus.fromValue(data['status'] as String?) !=
          RunContractStatus.active) {
        return;
      }
      final participants = data['participants'] as Map<String, dynamic>?;
      final current = participants?[_uid] as Map<String, dynamic>?;
      if (current == null) throw StateError('Bạn chưa tham gia kèo này.');
      final existing = (current['progressValue'] as num?)?.toDouble() ?? 0;
      final existingIds =
          (current['countedActivityIds'] as List?)?.whereType<String>().toSet() ??
          const <String>{};
      final unchanged =
          (existing - progressValue).abs() < 0.000001 &&
          existingIds.length == countedActivityIds.length &&
          existingIds.containsAll(countedActivityIds);
      if (unchanged) return;
      transaction.update(ref, {
        'participants.$_uid': {
          'uid': _uid,
          'progressValue': progressValue,
          'countedActivityIds': countedActivityIds,
          'joinedAt': current['joinedAt'],
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<Set<String>> claimedActivityIds({
    required String excludeContractId,
  }) async {
    final query = await _contracts
        .where('participantUids', arrayContains: _uid)
        .get();
    final ids = <String>{};
    for (final doc in query.docs) {
      if (doc.id == excludeContractId) continue;
      final data = doc.data();
      if (RunContractStatus.fromValue(data['status'] as String?) ==
          RunContractStatus.cancelled) {
        continue;
      }
      final participants = data['participants'] as Map<String, dynamic>?;
      final mine = participants?[_uid] as Map<String, dynamic>?;
      final counted = (mine?['countedActivityIds'] as List?)
          ?.whereType<String>();
      if (counted != null) ids.addAll(counted);
    }
    return ids;
  }

  void _validateProgress(double progressValue) {
    if (!progressValue.isFinite || progressValue < 0) {
      throw StateError('Tiến độ không hợp lệ.');
    }
  }

  @override
  Future<RunContractStatus> finalize(
    String contractId, {
    required double finalProgress,
    required bool targetMet,
    List<String> countedActivityIds = const [],
  }) async {
    if (!finalProgress.isFinite || finalProgress < 0) {
      throw StateError('Tiến độ cuối không hợp lệ.');
    }
    final ref = _contracts.doc(contractId);
    return _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (data == null) throw StateError('Không tìm thấy kèo chạy.');
      final current = RunContractStatus.fromValue(data['status'] as String?);
      if (current != RunContractStatus.active) return current;
      final next = targetMet
          ? RunContractStatus.completed
          : RunContractStatus.failed;
      final participants = data['participants'] as Map<String, dynamic>?;
      final hasMine = participants?[_uid] is Map<String, dynamic>;
      transaction.update(ref, {
        'progressValue': finalProgress,
        if (hasMine) ...{
          'participants.$_uid.progressValue': finalProgress,
          'participants.$_uid.countedActivityIds': countedActivityIds,
          'participants.$_uid.updatedAt': FieldValue.serverTimestamp(),
        },
        'lastCalculatedAt': FieldValue.serverTimestamp(),
        'status': next.value,
        if (targetMet)
          'completedAt': FieldValue.serverTimestamp()
        else
          'failedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return next;
    });
  }

  RunContract? _contractFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) return null;
    final rawParticipants = data['participants'];
    final participants = rawParticipants is Map<String, dynamic>
        ? {
            for (final entry in rawParticipants.entries)
              entry.key: entry.value is Map<String, dynamic>
                  ? {
                      ...(entry.value as Map<String, dynamic>),
                      for (final field in const ['joinedAt', 'updatedAt'])
                        if ((entry.value as Map<String, dynamic>)[field]
                            is Timestamp)
                          field:
                              ((entry.value as Map<String, dynamic>)[field]
                                      as Timestamp)
                                  .toDate(),
                    }
                  : entry.value,
          }
        : rawParticipants;
    return RunContract.fromMap({
      ...data,
      'id': document.id,
      'participants': ?participants,
      for (final field in const [
        'startAt',
        'endAtExclusive',
        'finalizeAt',
        'lastCalculatedAt',
        'completedAt',
        'failedAt',
        'cancelledAt',
        'createdAt',
        'updatedAt',
      ])
        if (data[field] is Timestamp)
          field: (data[field] as Timestamp).toDate(),
    });
  }
}

String _titleFor(RunContractDraft draft) {
  final custom = draft.title?.trim();
  if (custom != null && custom.isNotEmpty) return custom;
  return switch (draft.metric) {
    RunContractMetric.distance =>
      'Kèo ${draft.targetValue.toStringAsFixed(draft.targetValue % 1 == 0 ? 0 : 1)}km',
    RunContractMetric.longestRun =>
      'Kèo chạy dài ${draft.targetValue.toStringAsFixed(draft.targetValue % 1 == 0 ? 0 : 1)}km',
    RunContractMetric.activityCount =>
      'Kèo ${draft.targetValue.toInt()} buổi chạy',
    RunContractMetric.activeDays =>
      'Kèo ${draft.targetValue.toInt()} ngày active',
  };
}
