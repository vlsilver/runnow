import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/push.dart';
import 'package:myrun/src/run_contracts/contract_gift.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/widgets/contract_gift_section.dart';
import 'package:myrun/src/runnow_api_client.dart';

/// Doc contractGifts/k1 đúng các key backend ghi (contract_gift.go): bốc thăm,
/// Áo ×1 rồi Tất ×3, đã chốt với 5 vé.
Map<String, dynamic> _doc({
  String kind = 'draw',
  List<String> entrants = const ['an', 'binh', 'chi', 'dung', 'em'],
  List<Map<String, dynamic>>? winners,
}) => {
  'contractId': 'k1',
  'creatorUid': 'u1',
  'kind': kind,
  'giverName': 'Bình',
  'items': [
    {
      'id': 'ao',
      'name': 'Áo PSC',
      'icon': 'shirt',
      'slots': 1,
      'photos': ['contractGifts/u1/k1/a.jpg'],
    },
    {'id': 'tat', 'name': 'Tất', 'icon': 'socks', 'slots': 3, 'photos': []},
  ],
  'resolvedAt': DateTime.utc(2026, 11, 2, 23),
  'entrants': entrants,
  'winners':
      winners ??
      [
        {'slot': 0, 'itemId': 'ao', 'uid': 'chi'},
        {'slot': 1, 'itemId': 'tat', 'uid': 'an'},
        {
          'slot': 2,
          'itemId': 'tat',
          'uid': 'em',
          'givenAt': DateTime.utc(2026, 11, 3),
        },
        {'slot': 3, 'itemId': 'tat', 'uid': 'dung'},
      ],
};

/// Kèo 20 km của u1. [progress] là km từng người, kể cả chủ kèo.
RunContract _contract(
  Map<String, double> progress, {
  RunContractMetric metric = RunContractMetric.distance,
}) {
  final start = DateTime.utc(2026, 10, 25, 17);
  return RunContract(
    id: 'k1',
    creatorUid: 'u1',
    title: 'Tuần 20 km',
    template: RunContractTemplate.weekly10k,
    metric: metric,
    targetValue: 20,
    periodType: RunContractPeriodType.weekly,
    startAt: start,
    endAtExclusive: start.add(const Duration(days: 7)),
    finalizeAt: start.add(const Duration(days: 7, hours: 6)),
    status: RunContractStatus.completed,
    visibility: RunContractVisibility.club,
    progressValue: 0,
    participants: {
      for (final MapEntry(key: uid, value: km) in progress.entries)
        uid: RunContractParticipant(
          uid: uid,
          progressValue: km,
          joinedAt: start,
          updatedAt: start,
        ),
    },
    createdAt: start,
    updatedAt: start,
  );
}

class _Backend {
  _Backend({this.status = 200});

  /// Mã HTTP mọi request nhận.
  final int status;
  final requests = <String>[];

  RunNowApiClient client() => RunNowApiClient(
    baseUri: Uri.parse('https://api.example.test'),
    tokenProvider: ({required forceRefresh}) async => 'token',
    appVersion: () async => '1.6.0+1',
    appPlatform: 'ios',
    httpClient: MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      return http.Response(
        status == 200 ? '{}' : '{"error":"internal","message":"Server down"}',
        status,
      );
    }),
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required RunContract contract,
  required ContractGift gift,
  required String uid,
  _Backend? backend,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runNowApiClientProvider.overrideWithValue(
          (backend ?? _Backend()).client(),
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ContractGiftSection(
              contract: contract,
              gift: gift,
              uid: uid,
              names: const {
                'an': 'An',
                'binh': 'Bình',
                'chi': 'Chi',
                'dung': 'Dũng',
                'em': 'Em',
              },
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('đọc doc quà backend ghi', () {
    final gift = ContractGift.fromJson('k1', _doc())!;
    expect(gift.kind, ContractGiftKind.draw);
    expect(gift.slots, 4);
    expect(gift.badge, '4 quà');
    expect(gift.resolved, isTrue);
    expect(gift.item('ao')?.photos, ['contractGifts/u1/k1/a.jpg']);
    expect(gift.winnerFor('chi')?.itemId, 'ao');
    expect(gift.winnerFor('binh'), isNull);
    expect(ContractGift.fromJson('k1', {..._doc(), 'kind': 'all'}), isNull);
  });

  test('đã trao đủ 14 ngày thì tính là đã nhận', () {
    final given = DateTime.utc(2026, 11, 3);
    final w = ContractGiftWinner(
      slot: 0,
      itemId: 'ao',
      uid: 'an',
      givenAt: given,
    );
    expect(w.receivedBy(given.add(const Duration(days: 13))), isFalse);
    expect(w.receivedBy(given.add(const Duration(days: 14))), isTrue);
  });

  test('chỉ kèo công khai trong Club, không theo tuyến, treo được quà', () {
    expect(
      contractGiftAllowed(
        RunContractVisibility.club,
        RunContractMetric.distance,
      ),
      isTrue,
    );
    expect(
      contractGiftAllowed(
        RunContractVisibility.private,
        RunContractMetric.distance,
      ),
      isFalse,
    );
    expect(
      contractGiftAllowed(
        RunContractVisibility.club,
        RunContractMetric.routeCompletion,
      ),
      isFalse,
    );
  });

  test('người đạt không kể chủ kèo, xếp theo km giảm dần', () {
    final contract = _contract({'u1': 30, 'an': 20, 'binh': 19.9, 'chi': 22});
    expect(contractGiftQualified(contract).map((p) => p.uid), ['chi', 'an']);
  });

  test('push quà kèo mở màn kèo', () {
    expect(
      pushLocation({'kind': 'contract_gift', 'contractId': 'k1'}),
      '/contracts/k1',
    );
  });

  testWidgets('kèo còn chạy: chưa đạt thì thấy còn bao nhiêu km để có vé', (
    tester,
  ) async {
    final gift = ContractGift.fromJson('k1', {
      ..._doc(),
      'resolvedAt': null,
      'entrants': const <String>[],
      'winners': const <Object>[],
    })!;
    final contract = _contract({'u1': 30, 'an': 15, 'binh': 21, 'chi': 20});
    await _pump(tester, contract: contract, gift: gift, uid: 'an');
    expect(find.text('Còn 5 km để có vé'), findsOneWidget);
    expect(find.text('2 vé · 4 suất'), findsOneWidget);

    await _pump(tester, contract: contract, gift: gift, uid: 'binh');
    expect(find.text('Bạn có vé bốc thăm · cơ hội 2/2'), findsOneWidget);
  });

  test('phần còn thiếu làm tròn lên, không ra 0 km khi chưa đạt', () {
    expect(contractValueLabel(RunContractMetric.distance, 0.04), '0.1 km');
    expect(contractValueLabel(RunContractMetric.distance, 3.2), '3.2 km');
    // 21 - 17.9 ra 3.1000000000000014 trong double.
    expect(contractValueLabel(RunContractMetric.distance, 21 - 17.9), '3.1 km');
    expect(contractValueLabel(RunContractMetric.distance, 4.96), '5 km');
    expect(contractValueLabel(RunContractMetric.activityCount, 1.2), '2 buổi');
  });

  testWidgets(
    'kèo chạy dài: chưa đạt thì cần một buổi đủ dài, không cộng dồn',
    (tester) async {
      final gift = ContractGift.fromJson('k1', {
        ..._doc(),
        'resolvedAt': null,
        'entrants': const <String>[],
        'winners': const <Object>[],
      })!;
      final contract = _contract({
        'u1': 0,
        'an': 15,
      }, metric: RunContractMetric.longestRun);
      await _pump(tester, contract: contract, gift: gift, uid: 'an');
      expect(find.text('Cần 1 buổi ≥ 20 km để có vé'), findsOneWidget);
    },
  );

  testWidgets('trúng quà: báo đã nhận gọi API', (tester) async {
    final backend = _Backend();
    final gift = ContractGift.fromJson('k1', _doc())!;
    await _pump(
      tester,
      contract: _contract({'u1': 0, 'chi': 25}),
      gift: gift,
      uid: 'chi',
      backend: backend,
    );
    expect(find.text('Bạn trúng Áo PSC'), findsOneWidget);
    // Telegram người trao không nằm trong doc ai cũng đọc; hỏi API lúc bấm.
    await tester.tap(find.text('Nhắn Bình'));
    await tester.pumpAndSettle();
    expect(find.text('Bình chưa liên kết Telegram.'), findsOneWidget);
    await tester.tap(find.text('Tôi đã nhận quà'));
    await tester.pumpAndSettle();
    expect(backend.requests, [
      'GET /v1/contracts/k1/gifts/contact',
      'POST /v1/contracts/k1/gifts/received',
    ]);
  });

  testWidgets('hỏi liên hệ lỗi thì không báo nhầm là chưa liên kết', (
    tester,
  ) async {
    await _pump(
      tester,
      contract: _contract({'u1': 0, 'chi': 25}),
      gift: ContractGift.fromJson('k1', _doc())!,
      uid: 'chi',
      backend: _Backend(status: 500),
    );
    await tester.tap(find.text('Nhắn Bình'));
    await tester.pumpAndSettle();
    expect(find.text('Bình chưa liên kết Telegram.'), findsNothing);
    expect(find.text('Server down'), findsOneWidget);
  });

  testWidgets('vé nhiều hơn suất mà không trúng thì báo chưa trúng', (
    tester,
  ) async {
    final gift = ContractGift.fromJson('k1', _doc())!;
    await _pump(
      tester,
      contract: _contract({'u1': 0, 'binh': 25}),
      gift: gift,
      uid: 'binh',
    );
    expect(find.text('Lần này chưa trúng · 5 vé, 4 suất'), findsOneWidget);
    expect(find.text('Xem bốc thăm'), findsOneWidget);

    await _pump(
      tester,
      contract: _contract({'u1': 0, 'binh': 25}),
      gift: ContractGift.fromJson('k1', _doc(kind: 'rank'))!,
      uid: 'binh',
    );
    expect(
      find.text('Lần này chưa có quà · 5 người đạt, 4 suất'),
      findsOneWidget,
    );
    expect(find.text('Xem bốc thăm'), findsNothing);
  });

  testWidgets('chủ kèo bấm Đã trao rồi Hoàn tác thì gỡ lại', (tester) async {
    final backend = _Backend();
    final gift = ContractGift.fromJson('k1', _doc())!;
    await _pump(
      tester,
      contract: _contract({'u1': 0}),
      gift: gift,
      uid: 'u1',
      backend: backend,
    );
    // em được trao từ 3/11, quá 14 ngày nên tính là đã nhận, còn ba nút.
    expect(find.widgetWithText(TextButton, 'Đã trao'), findsNWidgets(3));
    expect(find.text('Đã nhận'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Đã trao').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hoàn tác'));
    await tester.pumpAndSettle();
    expect(backend.requests, [
      'POST /v1/contracts/k1/gifts/winners/chi/given',
      'DELETE /v1/contracts/k1/gifts/winners/chi/given',
    ]);
  });

  testWidgets('rời màn rồi mới bấm Hoàn tác thì vẫn gỡ đánh dấu', (
    tester,
  ) async {
    final backend = _Backend();
    final gift = ContractGift.fromJson('k1', _doc())!;
    await _pump(
      tester,
      contract: _contract({'u1': 0}),
      gift: gift,
      uid: 'u1',
      backend: backend,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Đã trao').first);
    await tester.pumpAndSettle();
    // Cùng ProviderScope và MaterialApp nên snackbar còn, khối quà thì đã gỡ.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runNowApiClientProvider.overrideWithValue(backend.client()),
        ],
        child: const MaterialApp(home: Scaffold(body: SizedBox())),
      ),
    );
    await tester.tap(find.text('Hoàn tác'));
    await tester.pumpAndSettle();
    expect(
      backend.requests.last,
      'DELETE /v1/contracts/k1/gifts/winners/chi/given',
    );
  });

  testWidgets('đủ suất cho mọi người đạt thì không có bốc thăm, dư suất', (
    tester,
  ) async {
    final gift = ContractGift.fromJson(
      'k1',
      _doc(
        entrants: ['an', 'chi'],
        winners: [
          {'slot': 0, 'itemId': 'ao', 'uid': 'an'},
          {'slot': 1, 'itemId': 'tat', 'uid': 'chi'},
        ],
      ),
    )!;
    await _pump(tester, contract: _contract({'u1': 0}), gift: gift, uid: 'u1');
    expect(find.text('Xem bốc thăm'), findsNothing);
    expect(find.text('Dư 2 suất'), findsOneWidget);
  });

  testWidgets('không ai về đích thì không trao', (tester) async {
    final gift = ContractGift.fromJson(
      'k1',
      _doc(entrants: const [], winners: const []),
    )!;
    await _pump(tester, contract: _contract({'u1': 0}), gift: gift, uid: 'u1');
    expect(find.text('Không ai về đích, quà không trao.'), findsOneWidget);
  });
}
