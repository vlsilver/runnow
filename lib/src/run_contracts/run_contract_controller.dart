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
