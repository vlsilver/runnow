import 'package:myrun/src/models.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/run_contract_period.dart';

enum RunContractLifecycle {
  scheduled,
  running,
  syncGrace,
  awaitingFinalize,
  completed,
  failed,
  cancelled,
}

enum RunContractUiState {
  scheduled,
  newContract,
  onTrack,
  rescuable,
  atRisk,
  saved,
  syncGrace,
  awaitingFinalize,
  broken,
  cancelled,
}

class RunContractProgress {
  const RunContractProgress({
    required this.value,
    required this.eligibleActivities,
  });

  final double value;
  final List<ActivitySummary> eligibleActivities;
}

bool isEligibleForContract(
  ActivitySummary activity,
  RunContract contract, {
  Set<String> excludeIds = const {},
}) =>
    activity.source == ActivitySource.strava &&
    activity.kind == ActivityKind.run &&
    activity.manual != true &&
    activity.distanceMeters > 0 &&
    !excludeIds.contains(activity.id) &&
    !activity.startedAt.toUtc().isBefore(contract.startAt.toUtc()) &&
    activity.startedAt.toUtc().isBefore(contract.endAtExclusive.toUtc());

RunContractProgress calculateRunContractProgress(
  RunContract contract,
  Iterable<ActivitySummary> activities, {
  Set<String> excludeIds = const {},
}) {
  final eligible = activities
      .where(
        (activity) =>
            isEligibleForContract(activity, contract, excludeIds: excludeIds),
      )
      .toList();
  switch (contract.metric) {
    case RunContractMetric.distance:
      final value =
          eligible.fold<double>(0, (sum, item) => sum + item.distanceMeters) /
          1000;
      return RunContractProgress(value: value, eligibleActivities: eligible);
    case RunContractMetric.activityCount:
      return RunContractProgress(
        value: eligible.length.toDouble(),
        eligibleActivities: eligible,
      );
    case RunContractMetric.activeDays:
      final days = eligible
          .map((item) => contractLocalDate(item.startedAt))
          .toSet()
          .length;
      return RunContractProgress(
        value: days.toDouble(),
        eligibleActivities: eligible,
      );
    case RunContractMetric.longestRun:
      // Chỉ buổi chạy dài nhất quyết định kết quả; cũng chỉ buổi đó bị "ghi nhận"
      // để không khóa các session khác khỏi kèo khác.
      if (eligible.isEmpty) {
        return const RunContractProgress(value: 0, eligibleActivities: []);
      }
      var best = eligible.first;
      for (final item in eligible) {
        if (item.distanceMeters > best.distanceMeters) best = item;
      }
      return RunContractProgress(
        value: best.distanceMeters / 1000,
        eligibleActivities: [best],
      );
  }
}

bool contractTargetMet(RunContract contract, double progressValue) =>
    (contract.metric == RunContractMetric.distance ||
        contract.metric == RunContractMetric.longestRun)
    ? (progressValue * 1000).round() >= (contract.targetValue * 1000).round()
    : progressValue >= contract.targetValue;

RunContractLifecycle contractLifecycle(RunContract contract, DateTime now) {
  if (contract.status == RunContractStatus.completed) {
    return RunContractLifecycle.completed;
  }
  if (contract.status == RunContractStatus.failed) {
    return RunContractLifecycle.failed;
  }
  if (contract.status == RunContractStatus.cancelled) {
    return RunContractLifecycle.cancelled;
  }
  final instant = now.toUtc();
  if (instant.isBefore(contract.startAt.toUtc())) {
    return RunContractLifecycle.scheduled;
  }
  if (instant.isBefore(contract.endAtExclusive.toUtc())) {
    return RunContractLifecycle.running;
  }
  if (instant.isBefore(contract.finalizeAt.toUtc())) {
    return RunContractLifecycle.syncGrace;
  }
  return RunContractLifecycle.awaitingFinalize;
}

RunContractUiState contractUiState(RunContract contract, DateTime now) {
  final lifecycle = contractLifecycle(contract, now);
  switch (lifecycle) {
    case RunContractLifecycle.scheduled:
      return RunContractUiState.scheduled;
    case RunContractLifecycle.syncGrace:
      return RunContractUiState.syncGrace;
    case RunContractLifecycle.awaitingFinalize:
      return RunContractUiState.awaitingFinalize;
    case RunContractLifecycle.completed:
      return RunContractUiState.saved;
    case RunContractLifecycle.failed:
      return RunContractUiState.broken;
    case RunContractLifecycle.cancelled:
      return RunContractUiState.cancelled;
    case RunContractLifecycle.running:
      break;
  }
  final progress = contract.overallProgressPercent;
  if (progress >= 100) return RunContractUiState.saved;
  final remaining = timeRemaining(contract, now);
  if (remaining <= const Duration(hours: 48)) {
    return progress >= 70
        ? RunContractUiState.rescuable
        : RunContractUiState.atRisk;
  }
  return progress < 20
      ? RunContractUiState.newContract
      : RunContractUiState.onTrack;
}
