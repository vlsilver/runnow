import 'package:myrun/src/models.dart';
import 'package:myrun/src/repository.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/run_contract_period.dart';
import 'package:myrun/src/run_contracts/run_contract_progress.dart';
import 'package:myrun/src/run_contracts/run_contract_repository.dart';
import 'package:myrun/src/sync.dart';

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
  RunContractController(this._contracts, this._activities, this._sync);

  final RunContractRepository _contracts;
  final ActivityRepository _activities;
  final SyncController _sync;

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

  Future<RunContractProgress> _calculateProgress(RunContract contract) async {
    final activities = await _activities.listOfficialActivities(
      start: contract.startAt,
      endExclusive: contract.endAtExclusive,
    );
    final assignments = await _contracts.activityAssignments();
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
    RunContract contract,
  ) async {
    final activities = await _activities.listOfficialActivities(
      start: contract.startAt,
      endExclusive: contract.endAtExclusive,
    );
    final assignments = await _contracts.activityAssignments();
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

  /// Tự động gán activity vừa sync về vào kèo active duy nhất của user, nếu
  /// có. Không đụng tới activity/kèo nào khác — chỉ bổ sung thêm activity
  /// hợp lệ, chưa thuộc kèo nào, vào kèo hiện có (giữ nguyên các activity đã
  /// gán từ trước qua [replaceActivityAssignments]).
  Future<void> autoAssignSoleActiveContract(
    List<RunContract> activeContracts,
    List<ActivitySummary> newlySyncedActivities,
  ) async {
    if (newlySyncedActivities.isEmpty || activeContracts.length != 1) return;
    final contract = activeContracts.single;
    final options = await activityOptions(contract);
    final alreadyAssignedIds = {
      for (final option in options)
        if (option.assignedContractId == contract.id) option.activity.id,
    };
    final newlySyncedIds = newlySyncedActivities
        .map((activity) => activity.id)
        .toSet();
    final newEligibleIds = {
      for (final option in options)
        if (option.assignedContractId == null &&
            newlySyncedIds.contains(option.activity.id))
          option.activity.id,
    };
    if (newEligibleIds.isEmpty) return;
    await replaceActivityAssignments(contract, {
      ...alreadyAssignedIds,
      ...newEligibleIds,
    });
  }

  /// Tính, với mỗi kèo trong [activeContracts], buổi chạy [activity] có áp
  /// dụng được không (và lý do nếu không), cùng tiến độ hiện tại/sau khi áp
  /// dụng — dùng cho picker "Áp dụng vào kèo nào?" ở màn chi tiết hoạt động.
  Future<List<ContractApplyOption>> applyOptionsFor(
    ActivitySummary activity,
    List<RunContract> activeContracts,
  ) async {
    final assignments = await _contracts.activityAssignments();
    final options = <ContractApplyOption>[];
    for (final contract in activeContracts) {
      final withinWindow =
          !activity.startedAt.toUtc().isBefore(contract.startAt.toUtc()) &&
          activity.startedAt.toUtc().isBefore(
            contract.endAtExclusive.toUtc(),
          );
      final meetsThreshold = meetsMetricDistanceThreshold(
        activity,
        contract.metric,
      );
      final assignedIds = {
        for (final entry in assignments.entries)
          if (entry.value == contract.id) entry.key,
      };
      final activities = await _activities.listOfficialActivities(
        start: contract.startAt,
        endExclusive: contract.endAtExclusive,
      );
      final currentProgress = calculateRunContractProgress(
        contract,
        activities,
        includeIds: assignedIds,
      );
      if (!withinWindow || !meetsThreshold) {
        options.add(
          ContractApplyOption(
            contract: contract,
            eligible: false,
            ineligibleReason: !withinWindow
                ? 'Ngoài khoảng thời gian kèo'
                : 'Chưa đạt ngưỡng tối thiểu 1km/buổi',
            currentValue: currentProgress.value,
          ),
        );
        continue;
      }
      final activitiesWithCandidate = activities.any(
        (existing) => existing.id == activity.id,
      )
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
    final syncResult = await _sync.sync();
    if (!syncResult.succeeded) {
      throw StateError('Không thể đồng bộ Strava. Hãy thử chốt lại sau.');
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
