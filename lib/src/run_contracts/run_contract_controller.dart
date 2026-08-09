import 'package:myrun/src/models.dart';
import 'package:myrun/src/repository.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/run_contract_period.dart';
import 'package:myrun/src/run_contracts/run_contract_progress.dart';
import 'package:myrun/src/run_contracts/run_contract_repository.dart';

class RunContractPreview {
  const RunContractPreview({required this.progress, required this.hardTarget});

  final RunContractProgress progress;
  final bool hardTarget;
}

class RunContractActivityOption {
  const RunContractActivityOption({
    required this.activity,
    required this.assignedContractId,
  });

  final ActivitySummary activity;
  final String? assignedContractId;
}

/// 1 kèo active dưới góc nhìn "áp dụng buổi chạy X vào kèo nào" — dùng cho
/// màn chi tiết hoạt động (chiều ngược lại với [RunContractActivityOption]).
class ContractApplyOption {
  const ContractApplyOption({
    required this.contract,
    required this.eligible,
    this.ineligibleReason,
    required this.currentValue,
    this.previewValue,
  });

  final RunContract contract;
  final bool eligible;

  /// Lý do không thể áp dụng — `null` khi [eligible] là `true`.
  final String? ineligibleReason;

  /// Tiến độ hiện tại của kèo (đơn vị theo `contract.metric`).
  final double currentValue;

  /// Tiến độ nếu áp dụng buổi chạy này vào kèo — `null` khi [eligible] là
  /// `false` (không tính preview cho kèo không hợp lệ).
  final double? previewValue;
}

class RunContractController {
  RunContractController(this._contracts, this._activities, [Object? _]);

  final RunContractRepository _contracts;
  final ActivityRepository _activities;

  Future<RunContractPreview> preview(
    RunContractDraft draft, {
    DateTime? now,
  }) async {
    final validation = draft.validate();
    if (validation != null) throw StateError(validation);
    final period = contractPeriodForDraft(draft, now ?? DateTime.now());
    var hardTarget = false;
    if (draft.metric == RunContractMetric.distance &&
        draft.period == RunContractPeriodType.weekly) {
      final historyStart = period.startAt.subtract(const Duration(days: 28));
      final history = await _activities.listOfficialActivities(
        start: historyStart,
        endExclusive: period.startAt,
      );
      final historyContract = RunContract(
        id: 'history-preview',
        creatorUid: 'preview',
        title: 'History',
        template: RunContractTemplate.custom,
        metric: RunContractMetric.distance,
        targetValue: 1,
        periodType: RunContractPeriodType.weekly,
        startAt: historyStart,
        endAtExclusive: period.startAt,
        finalizeAt: period.startAt,
        status: RunContractStatus.active,
        visibility: RunContractVisibility.private,
        progressValue: 0,
        createdAt: historyStart,
        updatedAt: historyStart,
      );
      final average =
          calculateRunContractProgress(historyContract, history).value / 4;
      hardTarget = average > 0 && draft.targetValue > average * 1.5;
    }
    return RunContractPreview(
      progress: const RunContractProgress(value: 0, eligibleActivities: []),
      hardTarget: hardTarget,
    );
  }

  Future<String> create(RunContractDraft draft, {DateTime? now}) async {
    final instant = now ?? DateTime.now();
    final period = contractPeriodForDraft(draft, instant);
    await preview(draft, now: instant);
    return _contracts.create(draft: draft, period: period, initialProgress: 0);
  }

  Future<RunContractProgress> recalculate(RunContract contract) async {
    final progress = await _calculateProgress(contract);
    await _contracts.updateProgress(
      contract.id,
      progress.value,
      countedActivityIds: progress.eligibleActivities
          .map((activity) => activity.id)
          .toList(),
    );
    return progress;
  }

  Future<RunContractProgress> join(RunContract contract) async {
    await _contracts.join(contract.id, 0);
    return const RunContractProgress(value: 0, eligibleActivities: []);
  }

  Future<RunContractProgress> recalculateParticipant(
    RunContract contract,
  ) async {
    final progress = await _calculateProgress(contract);
    await _contracts.updateParticipantProgress(
      contract.id,
      progress.value,
      countedActivityIds: progress.eligibleActivities
          .map((activity) => activity.id)
          .toList(),
    );
    return progress;
  }

  /// Kèo HÀNH TRÌNH: TỰ cộng MỌI buổi chạy hợp lệ trong kỳ (khác kèo thường —
  /// phải tự áp từng buổi). Cố ý KHÔNG "claim" buổi chạy nào (countedActivityIds
  /// rỗng) để hành trình chỉ TÍNH mà không CHIẾM — cùng 1 buổi vẫn đếm được cho
  /// cả hành trình lẫn kèo tuần/tháng khác. Cập nhật tiến độ của CHÍNH user
  /// hiện tại (creator hoặc participant đã tham gia).
  Future<RunContractProgress> recalculateJourney(
    RunContract contract,
    String currentUid,
  ) async {
    final (activities, _) = await _officialActivitiesFor(contract);
    final progress = calculateRunContractProgress(contract, activities);
    if (contract.creatorUid == currentUid) {
      await _contracts.updateProgress(
        contract.id,
        progress.value,
        countedActivityIds: const [],
      );
    } else {
      await _contracts.updateParticipantProgress(
        contract.id,
        progress.value,
        countedActivityIds: const [],
      );
    }
    return progress;
  }

  /// Activity "chính thức" trong khoảng của [contract] (đã khử trùng
  /// Strava/3i), CỘNG với những activity đã claim vào đúng kèo này nhưng vừa
  /// "thua" bước khử trùng đó (vd 1 activity 3i đã áp vào kèo, sau đó Strava
  /// sync về đúng buổi chạy đó) — activity cũ vẫn tiếp tục được tính bình
  /// thường cho tới khi user tự gỡ, không tự động thay bằng bản Strava mới.
  Future<(List<ActivitySummary>, Map<String, String>)> _officialActivitiesFor(
    RunContract contract, {
    int? limit,
  }) async {
    final official = await _activities.listOfficialActivities(
      start: contract.startAt,
      endExclusive: contract.endAtExclusive,
      limit: limit,
    );
    final assignments = await _contracts.activityAssignments();
    final officialIds = official.map((activity) => activity.id).toSet();
    final assignedHereIds = {
      for (final entry in assignments.entries)
        if (entry.value == contract.id) entry.key,
    };
    final orphanedIds = assignedHereIds.difference(officialIds);
    if (orphanedIds.isEmpty) return (official, assignments);
    final orphaned = await _activities.getActivitiesByIds(orphanedIds);
    return ([...official, ...orphaned.values], assignments);
  }

  Future<RunContractProgress> _calculateProgress(RunContract contract) async {
    final (activities, assignments) = await _officialActivitiesFor(contract);
    final assignedIds = {
      for (final entry in assignments.entries)
        if (entry.value == contract.id) entry.key,
    };
    return calculateRunContractProgress(
      contract,
      activities,
      includeIds: assignedIds,
    );
  }

  Future<List<RunContractActivityOption>> activityOptions(
    RunContract contract, {
    int? limit,
  }) async {
    final (activities, assignments) = await _officialActivitiesFor(
      contract,
      limit: limit,
    );
    final options = activities
        .where((activity) => isEligibleForContract(activity, contract))
        .map(
          (activity) => RunContractActivityOption(
            activity: activity,
            assignedContractId: assignments[activity.id],
          ),
        )
        .toList();
    options.sort(
      (a, b) => b.activity.startedAt.compareTo(a.activity.startedAt),
    );
    return options;
  }

  /// Whether [activity] trùng (Strava/3i cùng 1 buổi chạy thật) với 1
  /// activity khác đang được claim ở bất kỳ kèo nào (trong [assignments]) —
  /// đọc thẳng field `duplicateOfActivityId` (backend ghi sẵn lúc save/sync),
  /// không tự tính lại overlap ratio ở client.
  Future<bool> _duplicateOfClaimed(
    ActivitySummary activity,
    Map<String, String> assignments,
  ) async {
    final otherClaimedIds = assignments.keys
        .where((id) => id != activity.id)
        .toSet();
    if (otherClaimedIds.isEmpty) return false;
    // Chiều 1: activity là bản 3i, bản Strava trùng của nó đang bị claim.
    if (otherClaimedIds.contains(activity.duplicateOfActivityId)) return true;
    // Chiều 2: activity là bản Strava, có 1 activity 3i đang bị claim trỏ
    // `duplicateOfActivityId` về đúng activity này.
    final claimed = await _activities.getActivitiesByIds(otherClaimedIds);
    return claimed.values.any(
      (other) => other.duplicateOfActivityId == activity.id,
    );
  }

  /// Ném lỗi nếu [activity] trùng (Strava/3i cùng 1 buổi chạy thật) với 1
  /// activity khác đang được claim ở bất kỳ kèo nào — thiết kế là chặn hẳn,
  /// không tự động thay thế claim cũ; user phải tự gỡ claim cũ trước khi áp
  /// bản mới.
  Future<void> _ensureNoDuplicateClaim(
    ActivitySummary activity,
    Map<String, String> assignments,
  ) async {
    if (!await _duplicateOfClaimed(activity, assignments)) return;
    throw StateError(
      'Buổi chạy này trùng với 1 buổi chạy khác đã áp vào kèo. '
      'Hãy gỡ buổi chạy cũ khỏi kèo đó trước khi áp buổi chạy này.',
    );
  }

  Future<RunContractProgress> replaceActivityAssignments(
    RunContract contract,
    Set<String> selectedActivityIds,
  ) async {
    final options = await activityOptions(contract);
    final available = {
      for (final option in options)
        if (option.assignedContractId == null ||
            option.assignedContractId == contract.id)
          option.activity.id: option.activity,
    };
    if (!selectedActivityIds.every(available.containsKey)) {
      throw StateError('Có buổi chạy không hợp lệ hoặc đã thuộc kèo khác.');
    }
    final previouslyAssignedHereIds = {
      for (final option in options)
        if (option.assignedContractId == contract.id) option.activity.id,
    };
    final newlyAddedIds = selectedActivityIds.difference(
      previouslyAssignedHereIds,
    );
    if (newlyAddedIds.isNotEmpty) {
      final assignments = await _contracts.activityAssignments();
      for (final id in newlyAddedIds) {
        await _ensureNoDuplicateClaim(available[id]!, assignments);
      }
    }
    final selectedActivities = [
      for (final id in selectedActivityIds) available[id]!,
    ];
    final progress = calculateRunContractProgress(
      contract,
      selectedActivities,
      includeIds: selectedActivityIds,
    );
    await _contracts.replaceActivityAssignments(
      contract.id,
      activityIds: progress.eligibleActivities
          .map((activity) => activity.id)
          .toList(),
      progressValue: progress.value,
    );
    return progress;
  }

  /// Handles only contracts whose user-assigned activity changed in this sync.
  /// Sync never auto-assigns a new activity to a contract.
  Future<void> processChangedActivities({
    required List<RunContract> activeContracts,
    required List<ActivitySummary> changedActivities,
    required String currentUid,
  }) async {
    if (activeContracts.isEmpty || changedActivities.isEmpty) return;
    final changedIds = changedActivities.map((activity) => activity.id).toSet();
    for (final contract in activeContracts) {
      // Hành trình: TỰ cộng mọi buổi mới — không gate theo buổi đã-claim (nó
      // không claim buổi nào), chỉ cần có buổi nào đó vừa đổi là tính lại.
      if (contract.isJourney) {
        if (contract.participantFor(currentUid) == null) continue;
        try {
          await recalculateJourney(contract, currentUid);
        } catch (_) {
          // Bỏ qua — snapshot activity đổi lần sau sẽ tự tính lại.
        }
        continue;
      }
      final countedIds =
          contract.participantFor(currentUid)?.countedActivityIds ?? const [];
      if (!countedIds.any(changedIds.contains)) continue;
      try {
        if (contract.creatorUid == currentUid) {
          await recalculate(contract);
        } else {
          await recalculateParticipant(contract);
        }
      } catch (_) {
        // Bỏ qua — lần snapshot activity thay đổi tiếp theo sẽ tự tính lại.
      }
    }
  }

  /// Tính, với mỗi kèo trong [activeContracts], buổi chạy [activity] có áp
  /// dụng được không (và lý do nếu không), cùng tiến độ hiện tại/sau khi áp
  /// dụng — dùng cho picker "Áp dụng vào kèo nào?" ở màn chi tiết hoạt động.
  Future<List<ContractApplyOption>> applyOptionsFor(
    ActivitySummary activity,
    List<RunContract> activeContracts,
  ) async {
    final globalAssignments = await _contracts.activityAssignments();
    final duplicateClaimed = await _duplicateOfClaimed(
      activity,
      globalAssignments,
    );
    final options = <ContractApplyOption>[];
    for (final contract in activeContracts) {
      final withinWindow =
          !activity.startedAt.toUtc().isBefore(contract.startAt.toUtc()) &&
          activity.startedAt.toUtc().isBefore(contract.endAtExclusive.toUtc());
      final meetsThreshold = meetsMetricDistanceThreshold(
        activity,
        contract.metric,
      );
      final (activities, assignments) = await _officialActivitiesFor(
        contract,
      );
      final assignedIds = {
        for (final entry in assignments.entries)
          if (entry.value == contract.id) entry.key,
      };
      final currentProgress = calculateRunContractProgress(
        contract,
        activities,
        includeIds: assignedIds,
      );
      if (!withinWindow || !meetsThreshold || duplicateClaimed) {
        options.add(
          ContractApplyOption(
            contract: contract,
            eligible: false,
            ineligibleReason: !withinWindow
                ? 'Ngoài khoảng thời gian kèo'
                : !meetsThreshold
                ? 'Chưa đạt ngưỡng tối thiểu 1km/buổi'
                : 'Trùng với 1 buổi chạy khác đã áp vào kèo — hãy gỡ buổi cũ trước',
            currentValue: currentProgress.value,
          ),
        );
        continue;
      }
      final activitiesWithCandidate =
          activities.any((existing) => existing.id == activity.id)
          ? activities
          : [...activities, activity];
      final previewProgress = calculateRunContractProgress(
        contract,
        activitiesWithCandidate,
        includeIds: {...assignedIds, activity.id},
      );
      options.add(
        ContractApplyOption(
          contract: contract,
          eligible: true,
          currentValue: currentProgress.value,
          previewValue: previewProgress.value,
        ),
      );
    }
    return options;
  }

  /// Kèo mà [activityId] hiện đang được áp dụng vào (nếu có) — dùng để hiện
  /// chip "Đang áp dụng cho..." ở màn chi tiết hoạt động.
  Future<String?> currentContractIdFor(String activityId) async {
    final assignments = await _contracts.activityAssignments();
    return assignments[activityId];
  }

  /// Áp dụng [activity] vào [contract], giữ nguyên các activity đã gán từ
  /// trước. Ném `StateError` (từ [replaceActivityAssignments]) nếu activity
  /// vừa bị kèo khác giành mất suất (race condition).
  Future<void> applyActivityToContract(
    RunContract contract,
    ActivitySummary activity,
  ) async {
    final options = await activityOptions(contract);
    final alreadyAssignedIds = {
      for (final option in options)
        if (option.assignedContractId == contract.id) option.activity.id,
    };
    await replaceActivityAssignments(contract, {
      ...alreadyAssignedIds,
      activity.id,
    });
  }

  /// Gỡ [activity] khỏi [contract], giữ nguyên các activity khác đã gán.
  Future<void> removeActivityFromContract(
    RunContract contract,
    ActivitySummary activity,
  ) async {
    final options = await activityOptions(contract);
    final remainingIds = {
      for (final option in options)
        if (option.assignedContractId == contract.id &&
            option.activity.id != activity.id)
          option.activity.id,
    };
    await replaceActivityAssignments(contract, remainingIds);
  }

  Future<RunContractStatus> finalize(
    RunContract contract, {
    DateTime? now,
  }) async {
    final instant = now ?? DateTime.now();
    if (contractLifecycle(contract, instant) !=
        RunContractLifecycle.awaitingFinalize) {
      throw StateError('Kèo chưa đến thời điểm chốt kết quả.');
    }
    final progress = await _calculateProgress(contract);
    return _contracts.finalize(
      contract.id,
      finalProgress: progress.value,
      targetMet: contractTargetMet(contract, progress.value),
      countedActivityIds: progress.eligibleActivities
          .map((activity) => activity.id)
          .toList(),
    );
  }

  /// Xóa hẳn kèo do user tạo, chỉ khi chưa ai khác tham gia. Ném `StateError`
  /// (từ [RunContractRepository.delete]) nếu không phải người tạo hoặc kèo
  /// vừa có người khác tham gia (race condition).
  Future<void> deleteContract(RunContract contract) =>
      _contracts.delete(contract.id);

  RunContractDraft recontractDraft(RunContract contract) => RunContractDraft(
    template: contract.template,
    metric: contract.metric,
    targetValue: contract.targetValue,
    period: contract.periodType == RunContractPeriodType.weekly
        ? RunContractPeriodType.weekly
        : RunContractPeriodType.tomorrow,
    visibility: contract.visibility,
    title: contract.title,
  );
}
