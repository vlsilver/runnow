import 'package:myrun/src/run_contracts/run_contract_models.dart';

RunContractPeriod contractPeriod(RunContractPeriodType type, DateTime now) {
  final local = now.toLocal();
  return switch (type) {
    RunContractPeriodType.weekly => _weekly(local),
    RunContractPeriodType.today => _day(local, RunContractPeriodType.today),
    RunContractPeriodType.tomorrow => _day(
      local.add(const Duration(days: 1)),
      RunContractPeriodType.tomorrow,
    ),
    // Khung custom không có ranh giới ngày cố định; dùng contractPeriodForDraft.
    RunContractPeriodType.custom => _weekly(local),
  };
}

/// Tính kỳ hạn cho [draft]. Với khung [RunContractPeriodType.custom] dùng đúng
/// mốc thời gian người dùng chọn; còn lại quy về [contractPeriod].
RunContractPeriod contractPeriodForDraft(RunContractDraft draft, DateTime now) {
  if (draft.period == RunContractPeriodType.custom &&
      draft.customStart != null &&
      draft.customEnd != null) {
    final start = draft.customStart!.toUtc();
    final end = draft.customEnd!.toUtc();
    return RunContractPeriod(
      type: RunContractPeriodType.custom,
      startAt: start,
      endAtExclusive: end,
      finalizeAt: end.add(const Duration(hours: 6)),
    );
  }
  return contractPeriod(draft.period, now);
}

/// Ngày theo lịch địa phương của thiết bị (00:00 giờ máy) cho [instant].
DateTime contractLocalDate(DateTime instant) {
  final local = instant.toLocal();
  return DateTime(local.year, local.month, local.day);
}

Duration timeRemaining(RunContract contract, DateTime now) =>
    contract.endAtExclusive.difference(now.toUtc());

bool isLateToday(DateTime now) {
  final period = contractPeriod(RunContractPeriodType.today, now);
  final remaining = period.endAtExclusive.difference(now.toUtc());
  return !remaining.isNegative && remaining < const Duration(hours: 2);
}

RunContractPeriod nextValidPeriod(RunContract previous, DateTime now) {
  if (previous.periodType == RunContractPeriodType.weekly) {
    return contractPeriod(RunContractPeriodType.weekly, now);
  }
  return contractPeriod(RunContractPeriodType.tomorrow, now);
}

RunContractPeriod _weekly(DateTime local) {
  final day = DateTime(local.year, local.month, local.day);
  final monday = day.subtract(Duration(days: local.weekday - 1));
  final end = monday.add(const Duration(days: 7));
  return RunContractPeriod(
    type: RunContractPeriodType.weekly,
    startAt: monday.toUtc(),
    endAtExclusive: end.toUtc(),
    finalizeAt: end.add(const Duration(hours: 6)).toUtc(),
  );
}

RunContractPeriod _day(DateTime local, RunContractPeriodType type) {
  final start = DateTime(local.year, local.month, local.day);
  final end = start.add(const Duration(days: 1));
  return RunContractPeriod(
    type: type,
    startAt: start.toUtc(),
    endAtExclusive: end.toUtc(),
    finalizeAt: end.add(const Duration(hours: 6)).toUtc(),
  );
}
