import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/run_contract_period.dart';
import 'package:myrun/src/run_contracts/run_contract_progress.dart';

/// Thời gian còn lại dạng ngắn cho card: "còn 3n 20g", "còn 5g 40p",
/// "còn 35p". Phần lẻ dưới một phút làm tròn lên để không hiện "còn 0p".
String timeLeftLabel(Duration left) {
  if (left <= Duration.zero) return 'hết giờ';
  final minutes = (left.inSeconds + 59) ~/ 60;
  final days = minutes ~/ (24 * 60);
  final hours = minutes % (24 * 60) ~/ 60;
  final mins = minutes % 60;
  if (days > 0) return hours > 0 ? 'còn ${days}n ${hours}g' : 'còn ${days}n';
  if (hours > 0) return mins > 0 ? 'còn ${hours}g ${mins}p' : 'còn ${hours}g';
  return 'còn ${mins}p';
}

class DailyNeed {
  const DailyNeed({
    required this.metric,
    required this.remaining,
    required this.daysLeft,
  });

  final RunContractMetric metric;

  /// Còn thiếu bao nhiêu: km với kèo quãng đường, ngày với kèo ngày active.
  final double remaining;

  /// Số ngày lịch còn lại, tính cả hôm nay.
  final int daysLeft;

  double get perDay => remaining / daysLeft;

  /// Kèo ngày active: số ngày còn lại không dư ra ngày nào để nghỉ.
  bool get mustRunToday =>
      metric == RunContractMetric.activeDays && daysLeft <= remaining;
}

/// Mỗi ngày còn lại [uid] cần chạy bao nhiêu để kịp kèo. Null khi không có gì
/// để nhắc: đã đủ, ngoài kỳ, kèo không hạn, không tham gia, hoặc kèo đo kiểu
/// khác (số buổi, buổi dài nhất, theo tuyến) mà chia theo ngày không có nghĩa.
///
/// Kèo ngày active: nếu hôm nay đã chạy thì hôm nay đã nằm trong tiến độ mà
/// vẫn được đếm là một ngày còn lại, nên nhắc có thể nhẹ hơn thực tế một ngày.
DailyNeed? dailyNeed(RunContract contract, String uid, DateTime now) {
  if (contract.openEnded || contract.isJourney) return null;
  if (contract.metric != RunContractMetric.distance &&
      contract.metric != RunContractMetric.activeDays) {
    return null;
  }
  final participant = contract.participantFor(uid);
  if (participant == null) return null;
  final instant = now.toUtc();
  if (instant.isBefore(contract.startAt.toUtc()) ||
      !instant.isBefore(contract.endAtExclusive.toUtc())) {
    return null;
  }
  final remaining = contract.targetValue - participant.progressValue;
  if (remaining <= 0) return null;
  final today = contractLocalDate(now);
  final lastDay = contractLocalDate(
    contract.endAtExclusive.subtract(const Duration(seconds: 1)),
  );
  // Đếm theo ngày lịch chứ không chia giờ: qua đêm đổi giờ (DST) vẫn đúng.
  final daysLeft =
      DateTime.utc(
        lastDay.year,
        lastDay.month,
        lastDay.day,
      ).difference(DateTime.utc(today.year, today.month, today.day)).inDays +
      1;
  return DailyNeed(
    metric: contract.metric,
    remaining: remaining,
    daysLeft: daysLeft,
  );
}

/// Như [contractUiState] nhưng xét theo người đang xem: người đã tham gia xét
/// theo tiến độ của chính họ, hành trình nhóm xét theo tổng cả nhóm, người
/// ngoài kèo thấy như trung bình club. Kèo đã chốt hay chưa tới giờ thì giữ
/// nguyên trạng thái chung.
RunContractUiState contractUiStateFor(
  RunContract contract,
  DateTime now,
  String? uid,
) {
  final shared = contractUiState(contract, now);
  if (contractLifecycle(contract, now) != RunContractLifecycle.running) {
    return shared;
  }
  final percent = contractPercentFor(contract, uid);
  if (percent >= 100) return RunContractUiState.saved;
  if (timeRemaining(contract, now) <= const Duration(hours: 48)) {
    return percent >= 70
        ? RunContractUiState.rescuable
        : RunContractUiState.atRisk;
  }
  return percent < 20
      ? RunContractUiState.newContract
      : RunContractUiState.onTrack;
}

/// Phần trăm tiến độ người đang xem thấy trên card, cùng cách xét với
/// [contractUiStateFor].
double contractPercentFor(RunContract contract, String? uid) {
  if (contract.targetValue <= 0) return 0;
  if (contract.isJourney && contract.mode == RunContractMode.team) {
    final total = contract.participants.values.fold<double>(
      0,
      (sum, p) => sum + p.progressValue,
    );
    return total / contract.targetValue * 100;
  }
  final participant = contract.participantFor(uid);
  if (participant != null) {
    return participant.progressValue / contract.targetValue * 100;
  }
  return contract.overallProgressPercent;
}

/// Nhãn loại kèo ở đầu màn chi tiết.
String contractKindLabel(RunContract contract) {
  if (contract.isJourney) {
    return contract.mode == RunContractMode.team
        ? 'HÀNH TRÌNH NHÓM'
        : 'HÀNH TRÌNH';
  }
  if (contract.metric == RunContractMetric.routeCompletion) {
    return 'KÈO THEO TUYẾN';
  }
  return contract.participantCount > 1 ? 'KÈO NHÓM' : 'KÈO CÁ NHÂN';
}
