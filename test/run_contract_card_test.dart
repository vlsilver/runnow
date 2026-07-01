import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/widgets/run_contract_card.dart';
import 'package:myrun/src/theme.dart';

void main() {
  testWidgets('shows participant count and capped overall completion', (
    tester,
  ) async {
    final now = DateTime(2026, 6, 28);
    final contract = RunContract(
      id: 'group',
      creatorUid: 'owner',
      title: 'Kèo 10km',
      template: RunContractTemplate.weekly10k,
      metric: RunContractMetric.distance,
      targetValue: 10,
      periodType: RunContractPeriodType.weekly,
      startAt: now,
      endAtExclusive: now.add(const Duration(days: 7)),
      finalizeAt: now.add(const Duration(days: 7, hours: 6)),
      status: RunContractStatus.active,
      visibility: RunContractVisibility.club,
      progressValue: 12,
      participants: {
        'owner': RunContractParticipant(
          uid: 'owner',
          progressValue: 12,
          joinedAt: now,
          updatedAt: now,
        ),
        'member': RunContractParticipant(
          uid: 'member',
          progressValue: 5,
          joinedAt: now,
          updatedAt: now,
        ),
      },
      createdAt: now,
      updatedAt: now,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildRunNowDarkTheme(),
        home: Scaffold(
          body: RunContractCard(
            contract: contract,
            ownerName: 'Runner',
            currentUid: 'owner',
          ),
        ),
      ),
    );

    expect(find.textContaining('75%'), findsOneWidget);
    expect(find.textContaining('120%'), findsOneWidget);
    expect(find.text('2 người · TB'), findsOneWidget);
  });
}
