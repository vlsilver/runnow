import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/widgets/keo_scene.dart';

void main() {
  RunContract contract(RunContractMetric metric, {DateTime? meetAt}) {
    final now = DateTime(2026, 11, 1);
    return RunContract(
      id: 'k1',
      creatorUid: 'owner',
      title: 'Kèo',
      template: RunContractTemplate.weekly10k,
      metric: metric,
      targetValue: 10,
      periodType: RunContractPeriodType.weekly,
      startAt: now,
      endAtExclusive: now.add(const Duration(days: 7)),
      finalizeAt: now.add(const Duration(days: 7, hours: 6)),
      status: RunContractStatus.active,
      visibility: RunContractVisibility.club,
      progressValue: 0,
      participants: const {},
      createdAt: now,
      updatedAt: now,
      meetAt: meetAt,
    );
  }

  test('a meet-up shows the meet scene whatever it measures', () {
    final meetAt = DateTime(2026, 11, 2, 5, 30);
    for (final metric in RunContractMetric.values) {
      expect(
        KeoScene.forContract(contract(metric, meetAt: meetAt)),
        KeoScene.meet,
        reason: metric.name,
      );
    }
  });

  test('other contracts show the scene of their metric', () {
    expect(
      KeoScene.forContract(contract(RunContractMetric.distance)),
      KeoScene.distance,
    );
    expect(
      KeoScene.forContract(contract(RunContractMetric.activeDays)),
      KeoScene.activeDays,
    );
    expect(
      KeoScene.forContract(contract(RunContractMetric.activityCount)),
      KeoScene.activityCount,
    );
    expect(
      KeoScene.forContract(contract(RunContractMetric.longestRun)),
      KeoScene.longestRun,
    );
    expect(
      KeoScene.forContract(contract(RunContractMetric.routeCompletion)),
      KeoScene.route,
    );
  });

  // Cùng một kèo phải ra cùng một bố cục ở mọi lần mở app, nên giá trị được
  // ghim: 'a' = 97 → 1, 'b' = 98 → 2, 'ab' = 97·31 + 98 = 3105 → 0 (mod 3).
  test('layout variant is fixed per id', () {
    expect(keoSceneVariant('a'), 1);
    expect(keoSceneVariant('b'), 2);
    expect(keoSceneVariant('ab'), 0);
    expect(keoSceneVariant(''), 0);
  });
}
