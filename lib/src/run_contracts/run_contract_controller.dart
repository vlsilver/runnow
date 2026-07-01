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
    final contract = _previewContract(draft, period);
    final activities = await _activities.listStravaActivities(
      start: period.startAt,
      endExclusive: period.endAtExclusive,
    );
    final progress = calculateRunContractProgress(contract, activities);
    var hardTarget = false;
    if (draft.metric == RunContractMetric.distance &&
        draft.period == RunContractPeriodType.weekly) {
      final historyStart = period.startAt.subtract(const Duration(days: 28));
      final history = await _activities.listStravaActivities(
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
    return RunContractPreview(progress: progress, hardTarget: hardTarget);
  }

  Future<String> create(RunContractDraft draft, {DateTime? now}) async {
    final instant = now ?? DateTime.now();
    final period = contractPeriodForDraft(draft, instant);
    final progress = await preview(draft, now: instant);
    return _contracts.create(
      draft: draft,
      period: period,
      initialProgress: progress.progress.value,
    );
  }

  Future<RunContractProgress> recalculate(RunContract contract) async {
    final progress = await _calculateProgress(contract);
    await _contracts.updateProgress(contract.id, progress.value);
    return progress;
  }

  Future<RunContractProgress> join(RunContract contract) async {
    final progress = await _calculateProgress(contract);
    await _contracts.join(contract.id, progress.value);
    return progress;
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
    final activities = await _activities.listStravaActivities(
      start: contract.startAt,
      endExclusive: contract.endAtExclusive,
    );
    // Loại các activity đã được kèo khác của user ghi nhận (first-counted wins).
    final excludeIds = await _contracts.claimedActivityIds(
      excludeContractId: contract.id,
    );
    return calculateRunContractProgress(
      contract,
      activities,
      excludeIds: excludeIds,
    );
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
    final activities = await _activities.listStravaActivities(
      start: contract.startAt,
      endExclusive: contract.endAtExclusive,
    );
    final excludeIds = await _contracts.claimedActivityIds(
      excludeContractId: contract.id,
    );
    final progress = calculateRunContractProgress(
      contract,
      activities,
      excludeIds: excludeIds,
    );
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

  RunContract _previewContract(
    RunContractDraft draft,
    RunContractPeriod period,
  ) => RunContract(
    id: 'preview',
    creatorUid: 'preview',
    title: 'Kèo chạy',
    template: draft.template,
    metric: draft.metric,
    targetValue: draft.targetValue,
    periodType: period.type,
    startAt: period.startAt,
    endAtExclusive: period.endAtExclusive,
    finalizeAt: period.finalizeAt,
    status: RunContractStatus.active,
    visibility: draft.visibility,
    progressValue: 0,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}
