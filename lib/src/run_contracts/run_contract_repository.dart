import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';

/// Số kèo CHƯA HOÀN THÀNH tối đa mỗi người được tham gia (tạo + join) cùng lúc.
const int maxActiveRunContracts = 5;

/// schemaVersion kèo cao nhất mà bản app NÀY hiểu & render đúng. Kèo có
/// schemaVersion lớn hơn (loại mới hơn do bản app mới tạo) sẽ bị ẩn ở client
/// này thay vì hiển thị sai. Bản này hiểu tới 2 (2 = kèo hành trình).
const int kSupportedRunContractSchemaVersion = 2;

class RunContractPage {
  const RunContractPage({
    required this.contracts,
    required this.hasMore,
    this.nextCursor,
  });

  final List<RunContract> contracts;
  final Object? nextCursor;
  final bool hasMore;
}

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

  /// Tuyến ĐẦY ĐỦ (polyline) của kèo "Theo tuyến" — lưu tách ở
  /// `runContractRoutes/{contractId}` để doc kèo trong danh sách khỏi cõng cả
  /// polyline nặng. Trả `null` nếu kèo không có tuyến / chưa tách (kèo cũ vẫn
  /// giữ points inline trong chính doc kèo).
  Future<RunContractRoute?> fetchContractRoute(String contractId);
  /// [fromCache] = true đọc thẳng cache đĩa Firestore (vẽ tức thì, né cold-start
  /// query đầu); mặc định serverAndCache để lấy dữ liệu tươi.
  Future<RunContractPage> fetchClubContractsPage({
    int limit = 20,
    Object? cursor,
    bool fromCache = false,
  });

  /// Các kèo (tạo hoặc join) đã kết thúc — hoàn thành, thất bại hoặc bị huỷ.
  Future<RunContractPage> fetchMyContractHistoryPage({
    required RunContractStatus status,
    int limit = 20,
    Object? cursor,
    bool fromCache = false,
  });
  Future<String> create({
    required RunContractDraft draft,
    required RunContractPeriod period,
    required double initialProgress,
    List<String> countedActivityIds = const [],
  });
  Future<void> updateProgress(
    String contractId,
    double progressValue, {
    List<String> countedActivityIds = const [],
  });
  Future<void> join(
    String contractId,
    double initialProgress, {
    List<String> countedActivityIds = const [],
  });
  Future<void> updateParticipantProgress(
    String contractId,
    double progressValue, {
    List<String> countedActivityIds = const [],
  });

  /// Assignment hiện tại của user: activity ID -> contract ID.
  Future<Map<String, String>> activityAssignments();
  Future<void> replaceActivityAssignments(
    String contractId, {
    required List<String> activityIds,
    required double progressValue,
  });
  Future<RunContractStatus> finalize(
    String contractId, {
    required double finalProgress,
    required bool targetMet,
    List<String> countedActivityIds = const [],
  });

  /// Xóa hẳn kèo — chỉ người tạo mới gọi được, và chỉ khi chưa ai khác tham
  /// gia. Ném `StateError` nếu không đúng người tạo hoặc đã có người khác.
  Future<void> delete(String contractId);
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

  /// Polyline đầy đủ của kèo "Theo tuyến", tách khỏi doc kèo cho danh sách nhẹ.
  CollectionReference<Map<String, dynamic>> get _routes =>
      _firestore.collection('runContractRoutes');

  @override
  Future<RunContractRoute?> fetchContractRoute(String contractId) async {
    final snap = await _routes.doc(contractId).get();
    final data = snap.data();
    if (data == null) return null;
    final route = RunContractRoute.fromMap(data);
    // Doc route mà không có points thì coi như chưa có (để caller fallback về
    // points inline của kèo cũ, không nhầm là "tuyến rỗng").
    if (route.points.isEmpty) return null;
    return route;
  }

  CollectionReference<Map<String, dynamic>> get _activityClaims => _firestore
      .collection('users')
      .doc(_uid)
      .collection('runContractActivityClaims');

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
  Future<RunContractPage> fetchClubContractsPage({
    int limit = 20,
    Object? cursor,
    bool fromCache = false,
  }) async {
    Query<Map<String, dynamic>> query = _contracts
        .where('visibility', isEqualTo: RunContractVisibility.club.value)
        .where('status', isEqualTo: RunContractStatus.active.value)
        .orderBy('updatedAt', descending: true);
    if (cursor is DocumentSnapshot<Map<String, dynamic>>) {
      query = query.startAfterDocument(cursor);
    }
    return _fetchPage(query, limit, fromCache: fromCache);
  }

  @override
  Future<RunContractPage> fetchMyContractHistoryPage({
    required RunContractStatus status,
    int limit = 20,
    Object? cursor,
    bool fromCache = false,
  }) async {
    Query<Map<String, dynamic>> query = _contracts
        .where('participantUids', arrayContains: _uid)
        .where('status', isEqualTo: status.value)
        .orderBy('updatedAt', descending: true);
    if (cursor is DocumentSnapshot<Map<String, dynamic>>) {
      query = query.startAfterDocument(cursor);
    }
    return _fetchPage(query, limit, fromCache: fromCache);
  }

  Future<RunContractPage> _fetchPage(
    Query<Map<String, dynamic>> query,
    int limit, {
    bool fromCache = false,
  }) async {
    final snapshot = await query.limit(limit).get(
      GetOptions(source: fromCache ? Source.cache : Source.serverAndCache),
    );
    return RunContractPage(
      contracts: _contractsFromDocuments(snapshot.docs),
      nextCursor: snapshot.docs.isEmpty ? null : snapshot.docs.last,
      hasMore: snapshot.docs.length == limit,
    );
  }

  List<RunContract> _sortedContracts(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) => _contractsFromDocuments(snapshot.docs);

  List<RunContract> _contractsFromDocuments(
    Iterable<DocumentSnapshot<Map<String, dynamic>>> documents,
  ) {
    final contracts = documents
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
    List<String> countedActivityIds = const [],
  }) async {
    final validation = draft.validate();
    if (validation != null) throw StateError(validation);
    await _ensureUnderLimit();
    final contractRef = _contracts.doc();
    final route = draft.route;
    // Chỉ TÁCH tuyến cho kèo "Theo tuyến" (routeCompletion). Kèo HÀNH TRÌNH cũng
    // có route nhưng giữ inline như cũ (feature riêng, có hạ tầng route khác) —
    // không đụng để khỏi sinh bug.
    final splitRoute =
        route != null &&
        draft.metric == RunContractMetric.routeCompletion &&
        route.points.isNotEmpty;
    if (splitRoute) {
      // Ghi polyline ra doc riêng TRƯỚC khi tạo kèo — doc kèo chỉ giữ bản nhẹ.
      // creatorUid nhúng kèm để rule tự kiểm quyền ghi (khỏi đọc chéo doc kèo).
      await _routes.doc(contractRef.id).set({
        ...route.toMap(),
        'pointCount': route.points.length,
        'creatorUid': _uid,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await contractRef.set({
      'id': contractRef.id,
      // Kèo hành trình là loại mới (schema 2): app cũ chưa hiểu sẽ ẩn đi thay
      // vì hiển thị sai (xem lọc theo schemaVersion ở phía đọc).
      'schemaVersion': draft.isJourney ? 2 : 1,
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
      'sourcePolicy': 'official_activity',
      'progressValue': initialProgress,
      'participantUids': [_uid],
      'participants': {
        _uid: {
          'uid': _uid,
          'progressValue': initialProgress,
          'countedActivityIds': countedActivityIds,
          'joinedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
      },
      'eligibilityVersion': 2,
      'lastCalculatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      // routeCompletion → nhúng bản NHẸ (points nằm ở runContractRoutes).
      // Journey / trường hợp khác → giữ route inline như cũ.
      if (route != null) 'route': splitRoute ? route.toLightMap() : route.toMap(),
      'unlimitedRepeat': draft.unlimitedRepeat,
      // Kèo hành trình: cung tự vẽ (đã ghi ở 'route') + chế độ + cờ không-hạn.
      if (draft.isJourney) 'mode': draft.mode.value,
      if (draft.journeyRouteId != null) 'journeyRouteId': draft.journeyRouteId,
      if (draft.openEnded) 'openEnded': true,
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
    return snapshot.docs.where((document) {
      final data = document.data();
      final participants = data['participants'] as Map<String, dynamic>?;
      final mine = participants?[_uid] as Map<String, dynamic>?;
      final progress =
          (mine?['progressValue'] as num?)?.toDouble() ??
          (data['creatorUid'] == _uid
              ? (data['progressValue'] as num?)?.toDouble() ?? 0
              : 0);
      final target = (data['targetValue'] as num?)?.toDouble() ?? 0;
      return target <= 0 || progress < target;
    }).length;
  }

  @override
  Future<void> updateProgress(
    String contractId,
    double progressValue, {
    List<String> countedActivityIds = const [],
  }) async {
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
      final participants = data['participants'];
      final creatorParticipant = participants is Map
          ? participants[_uid] as Map<String, dynamic>?
          : null;
      final existingIds =
          (creatorParticipant?['countedActivityIds'] as List?)
              ?.whereType<String>()
              .toSet() ??
          const <String>{};
      final idsUnchanged =
          existingIds.length == countedActivityIds.length &&
          existingIds.containsAll(countedActivityIds);
      if ((existing - progressValue).abs() < 0.000001 && idsUnchanged) return;
      final joinedAt =
          creatorParticipant?['joinedAt'] ?? FieldValue.serverTimestamp();
      transaction.update(ref, {
        'progressValue': progressValue,
        'participants.$_uid': {
          'uid': _uid,
          'progressValue': progressValue,
          'countedActivityIds': countedActivityIds,
          'joinedAt': joinedAt,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        'lastCalculatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  @override
  Future<void> join(
    String contractId,
    double initialProgress, {
    List<String> countedActivityIds = const [],
  }) async {
    _validateProgress(initialProgress);
    final ref = _contracts.doc(contractId);
    // Chặn vượt giới hạn nếu đây là kèo mới (chưa tham gia). Đọc trước transaction
    // vì transaction không chạy được query đếm.
    final pre = await ref.get();
    final preParticipants =
        pre.data()?['participants'] as Map<String, dynamic>?;
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
              'countedActivityIds': countedActivityIds,
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
          'countedActivityIds': countedActivityIds,
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
          (current['countedActivityIds'] as List?)
              ?.whereType<String>()
              .toSet() ??
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
  Future<Map<String, String>> activityAssignments() async {
    final snapshot = await _activityClaims.get();
    return {
      for (final document in snapshot.docs)
        if (document.data()['contractId'] is String)
          document.id: document.data()['contractId'] as String,
    };
  }

  @override
  Future<void> replaceActivityAssignments(
    String contractId, {
    required List<String> activityIds,
    required double progressValue,
  }) async {
    _validateProgress(progressValue);
    final selectedIds = activityIds.toSet();
    if (selectedIds.length > 200) {
      throw StateError('Một kèo không thể gán quá 200 buổi chạy.');
    }
    final contractRef = _contracts.doc(contractId);
    await _firestore.runTransaction((transaction) async {
      final contractSnapshot = await transaction.get(contractRef);
      final data = contractSnapshot.data();
      if (data == null) throw StateError('Không tìm thấy kèo chạy.');
      if (RunContractStatus.fromValue(data['status'] as String?) !=
          RunContractStatus.active) {
        throw StateError('Kèo này đã kết thúc.');
      }
      final participants = data['participants'] as Map<String, dynamic>?;
      final current = participants?[_uid] as Map<String, dynamic>?;
      if (current == null) throw StateError('Bạn chưa tham gia kèo này.');
      final target = (data['targetValue'] as num?)?.toDouble() ?? 0;
      final currentProgress =
          (current['progressValue'] as num?)?.toDouble() ?? 0;
      if (target > 0 && currentProgress >= target) {
        throw StateError('Kèo đã hoàn thành nên không thể đổi buổi chạy.');
      }

      final previousIds =
          (current['countedActivityIds'] as List?)
              ?.whereType<String>()
              .toSet() ??
          const <String>{};
      final affectedIds = {...previousIds, ...selectedIds};
      final claimSnapshots = <String, DocumentSnapshot<Map<String, dynamic>>>{};
      for (final activityId in affectedIds) {
        claimSnapshots[activityId] = await transaction.get(
          _activityClaims.doc(activityId),
        );
      }

      for (final activityId in selectedIds) {
        final existingContractId =
            claimSnapshots[activityId]?.data()?['contractId'] as String?;
        if (existingContractId != null && existingContractId != contractId) {
          throw StateError('Buổi chạy này đã được gán cho một kèo khác.');
        }
      }
      for (final activityId in previousIds.difference(selectedIds)) {
        final claim = claimSnapshots[activityId];
        if (claim?.data()?['contractId'] == contractId) {
          transaction.delete(_activityClaims.doc(activityId));
        }
      }
      for (final activityId in selectedIds.difference(previousIds)) {
        transaction.set(_activityClaims.doc(activityId), {
          'activityId': activityId,
          'contractId': contractId,
          'uid': _uid,
          'assignedAt': FieldValue.serverTimestamp(),
        });
      }

      final participant = {
        'uid': _uid,
        'progressValue': progressValue,
        'countedActivityIds': selectedIds.toList()..sort(),
        'joinedAt': current['joinedAt'],
        'updatedAt': FieldValue.serverTimestamp(),
      };
      transaction.update(contractRef, {
        if (data['creatorUid'] == _uid) ...{
          'progressValue': progressValue,
          'lastCalculatedAt': FieldValue.serverTimestamp(),
        },
        'participants.$_uid': participant,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
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

  @override
  Future<void> delete(String contractId) async {
    final ref = _contracts.doc(contractId);
    final claimsSnapshot = await _activityClaims
        .where('contractId', isEqualTo: contractId)
        .get();
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final data = snapshot.data();
      if (data == null) return;
      if (data['creatorUid'] != _uid) {
        throw StateError('Chỉ người tạo kèo mới có thể xóa.');
      }
      final participants = data['participants'] as Map<String, dynamic>?;
      if ((participants?.length ?? 1) > 1) {
        throw StateError('Kèo đã có người khác tham gia nên không thể xóa.');
      }
      for (final claim in claimsSnapshot.docs) {
        transaction.delete(claim.reference);
      }
      transaction.delete(ref);
    });
  }

  RunContract? _contractFromDocument(
    DocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    if (data == null) return null;
    // Version gate: kèo loại mới hơn (schemaVersion cao hơn mức app này hiểu)
    // bị ẩn thay vì render sai — vd app cũ gặp kèo hành trình (schema 2).
    final schema = (data['schemaVersion'] as num?)?.toInt() ?? 1;
    if (schema > kSupportedRunContractSchemaVersion) return null;
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
    RunContractMetric.routeCompletion =>
      'Kèo theo tuyến ${((draft.route?.distanceMeters ?? 0) / 1000).toStringAsFixed(1)}km',
  };
}
