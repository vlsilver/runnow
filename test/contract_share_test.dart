import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/widgets/contract_share.dart';
import 'package:myrun/src/run_contracts/widgets/run_contract_card.dart';
import 'package:myrun/src/theme.dart';
import 'package:share_plus_platform_interface/share_plus_platform_interface.dart';

class _FakeShare extends SharePlatform {
  final shared = <ShareParams>[];

  @override
  Future<ShareResult> share(ShareParams params) async {
    shared.add(params);
    return const ShareResult('ok', ShareResultStatus.success);
  }
}

RunContract _contract({
  RunContractVisibility visibility = RunContractVisibility.club,
}) {
  final now = DateTime(2026, 6, 28);
  return RunContract(
    id: 'k1',
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
    visibility: visibility,
    progressValue: 7.5,
    participants: {
      'owner': RunContractParticipant(
        uid: 'owner',
        progressValue: 7.5,
        joinedAt: now,
        updatedAt: now,
      ),
    },
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  test('caption kèo nhóm có tiến độ của người khoe và link', () {
    expect(
      contractShareCaption(_contract(), 'owner'),
      'Kèo 10km: 7.5 / 10 km\nhttps://threei.run/contracts/k1',
    );
  });

  test('người ngoài kèo khoe thì caption chỉ có tên và link', () {
    expect(
      contractShareCaption(_contract(), 'khach'),
      'Kèo 10km\nhttps://threei.run/contracts/k1',
    );
  });

  test('kèo riêng tư không kèm link', () {
    expect(
      contractShareCaption(
        _contract(visibility: RunContractVisibility.private),
        'owner',
      ),
      'Kèo 10km: 7.5 / 10 km',
    );
  });

  testWidgets('Khoe kèo gửi một ảnh PNG khổ Story kèm caption', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final share = _FakeShare();
    SharePlatform.instance = share;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: buildRunNowDarkTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showContractShare(
                  context,
                  contract: _contract(),
                  currentUid: 'owner',
                  ownerName: 'Runner',
                  ownerAvatarUrl: null,
                  participantAvatarUrls: const [null],
                ),
                child: const Text('mở'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('mở'));
    await tester.pumpAndSettle();
    expect(find.byType(RunContractPoster), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.text('Khoe kèo'));
      for (var i = 0; i < 40 && share.shared.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump();
      }
    });
    await tester.pumpAndSettle();

    final params = share.shared.single;
    expect(
      params.text,
      'Kèo 10km: 7.5 / 10 km\nhttps://threei.run/contracts/k1',
    );
    final file = params.files!.single;
    expect(file.mimeType, 'image/png');
    final bytes = await tester.runAsync(file.readAsBytes);
    final image = await tester.runAsync(() => decodeImageFromList(bytes!));
    expect((image!.width, image.height), (1080, 1920));
    expect(find.text('Khoe kèo'), findsNothing);
  });
}
