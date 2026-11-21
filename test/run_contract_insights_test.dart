import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/run_contracts/run_contract_insights.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/run_contract_progress.dart';

// Tuần 27/10 (thứ Hai) tới hết Chủ nhật 2/11, giờ máy.
final _start = DateTime(2026, 10, 27);
final _end = DateTime(2026, 11, 3);
// Thứ Năm 30/10, 03:00.
final _thu = DateTime(2026, 10, 30, 3);

void main() {
  test('timeLeftLabel: ngày và giờ, giờ và phút, phút, rồi hết giờ', () {
    expect(
      timeLeftLabel(const Duration(days: 3, hours: 20, minutes: 15)),
      'còn 3n 20g',
    );
    expect(timeLeftLabel(const Duration(days: 2)), 'còn 2n');
    expect(timeLeftLabel(const Duration(hours: 5, minutes: 40)), 'còn 5g 40p');
    expect(timeLeftLabel(const Duration(hours: 5)), 'còn 5g');
    expect(timeLeftLabel(const Duration(minutes: 35)), 'còn 35p');
    expect(timeLeftLabel(const Duration(seconds: 20)), 'còn 1p');
    expect(timeLeftLabel(Duration.zero), 'hết giờ');
  });

  group('dailyNeed', () {
    test('chia số km còn thiếu cho số ngày còn lại, tính cả hôm nay', () {
      final need = dailyNeed(_contract({'me': 12.4}, target: 30), 'me', _thu)!;
      // Thứ Năm, Sáu, Bảy, Chủ nhật: 4 ngày; 30 − 12.4 = 17.6; 17.6 / 4 = 4.4.
      expect(need.daysLeft, 4);
      expect(need.remaining, closeTo(17.6, 1e-9));
      expect(need.perDay, closeTo(4.4, 1e-9));
      expect(need.mustRunToday, isFalse);
    });

    test(
      'kèo ngày: phải chạy hôm nay khi số ngày còn lại bằng số ngày thiếu',
      () {
        final c = _contract(
          {'me': 0},
          target: 4,
          metric: RunContractMetric.activeDays,
        );
        expect(dailyNeed(c, 'me', _thu)!.mustRunToday, isTrue);
        final ahead = _contract(
          {'me': 2},
          target: 4,
          metric: RunContractMetric.activeDays,
        );
        expect(dailyNeed(ahead, 'me', _thu)!.mustRunToday, isFalse);
      },
    );

    test(
      'null khi đã đủ, ngoài kỳ, không hạn, không tham gia, hay đo kiểu khác',
      () {
        expect(
          dailyNeed(_contract({'me': 30}, target: 30), 'me', _thu),
          isNull,
        );
        expect(
          dailyNeed(_contract({'me': 1}), 'me', DateTime(2026, 11, 4)),
          isNull,
        );
        expect(
          dailyNeed(_contract({'me': 1}, openEnded: true), 'me', _thu),
          isNull,
        );
        expect(dailyNeed(_contract({'x': 1}), 'me', _thu), isNull);
        expect(
          dailyNeed(
            _contract({'me': 5}, metric: RunContractMetric.longestRun),
            'me',
            _thu,
          ),
          isNull,
        );
      },
    );
  });

  group('contractUiStateFor', () {
    // Chủ nhật 2/11 08:00: còn dưới 48 giờ.
    final soon = DateTime(2026, 11, 2, 8);

    test('người đã tham gia xét theo tiến độ của chính mình', () {
      final c = _contract({'me': 8, 'x': 0, 'y': 0}, target: 10);
      expect(contractUiState(c, soon), RunContractUiState.atRisk);
      expect(contractUiStateFor(c, soon, 'me'), RunContractUiState.rescuable);
      final behind = _contract({'me': 1, 'x': 10, 'y': 10}, target: 10);
      expect(contractUiState(behind, soon), RunContractUiState.rescuable);
      expect(contractUiStateFor(behind, soon, 'me'), RunContractUiState.atRisk);
    });

    test('hành trình nhóm xét theo tổng cả nhóm', () {
      final c = _contract({'me': 50, 'x': 40}, target: 100, team: true);
      expect(contractUiStateFor(c, soon, 'me'), RunContractUiState.rescuable);
    });

    test('người ngoài kèo thấy như trung bình club', () {
      final c = _contract({'x': 1, 'y': 1}, target: 10);
      expect(contractUiStateFor(c, soon, 'me'), RunContractUiState.atRisk);
    });

    test('kèo đã chốt giữ nguyên trạng thái đã chốt', () {
      final c = _contract(
        {'me': 10},
        target: 10,
        status: RunContractStatus.failed,
      );
      expect(contractUiStateFor(c, soon, 'me'), RunContractUiState.broken);
    });
  });

  group('contractKindLabel', () {
    test('theo chế độ và số người', () {
      expect(contractKindLabel(_contract({'me': 0})), 'KÈO CÁ NHÂN');
      expect(contractKindLabel(_contract({'me': 0, 'x': 0})), 'KÈO NHÓM');
      expect(
        contractKindLabel(_contract({'me': 0, 'x': 0}, team: true)),
        'HÀNH TRÌNH NHÓM',
      );
      expect(
        contractKindLabel(_contract({'me': 0}, journey: true)),
        'HÀNH TRÌNH',
      );
      expect(
        contractKindLabel(
          _contract({'me': 0}, metric: RunContractMetric.routeCompletion),
        ),
        'KÈO THEO TUYẾN',
      );
    });
  });
}

RunContract _contract(
  Map<String, double> progress, {
  double target = 30,
  RunContractMetric metric = RunContractMetric.distance,
  RunContractStatus status = RunContractStatus.active,
  bool openEnded = false,
  bool team = false,
  bool journey = false,
}) {
  final hasRoute =
      team || journey || metric == RunContractMetric.routeCompletion;
  return RunContract(
    id: 'c',
    creatorUid: progress.keys.first,
    title: 'c',
    template: RunContractTemplate.custom,
    metric: metric,
    targetValue: target,
    periodType: RunContractPeriodType.weekly,
    startAt: _start,
    endAtExclusive: _end,
    finalizeAt: _end.add(const Duration(hours: 6)),
    status: status,
    visibility: RunContractVisibility.club,
    progressValue: progress.values.first,
    participants: {
      for (final entry in progress.entries)
        entry.key: RunContractParticipant(
          uid: entry.key,
          progressValue: entry.value,
          joinedAt: _start,
          updatedAt: _start,
        ),
    },
    createdAt: _start,
    updatedAt: _start,
    route: hasRoute
        ? RunContractRoute(points: const [], distanceMeters: target * 1000)
        : null,
    mode: team ? RunContractMode.team : RunContractMode.individual,
    openEnded: openEnded,
  );
}
