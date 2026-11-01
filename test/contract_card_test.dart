import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/run_contracts/contract_card_models.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/widgets/contract_card_art.dart';
import 'package:myrun/src/run_contracts/widgets/contract_card_face.dart';
import 'package:myrun/src/run_contracts/widgets/contract_card_panel.dart';
import 'package:myrun/src/runnow_api_client.dart';

/// Thẻ như API trả (lấy từ test emulator của backend): kèo tuần 19–25/10 giờ
/// VN, u1 tích 23,5 km trên mục tiêu 20 km, 2 trên 3 người đạt.
Map<String, dynamic> _cardJson({
  String tier = 'legendary',
  String metric = 'distance',
  double target = 20,
  double progress = 23.5,
  double km = 23.5,
  String title = 'Tuần 30 km',
  String startAt = '2026-10-18T17:00:00Z',
  String endAtExclusive = '2026-10-25T17:00:00Z',
}) => {
  'id': 'k1',
  'contractId': 'k1',
  'tier': tier,
  'km': km,
  'rollPpm': 820000,
  'rolledAt': '2026-10-25T01:00:00Z',
  'odds': [
    {'tier': 'common', 'percent': 2.5},
    {'tier': 'rare', 'percent': 50.5},
    {'tier': 'epic', 'percent': 28.5},
    {'tier': 'legendary', 'percent': 14},
    {'tier': 'mythic', 'percent': 4.5},
  ],
  'snapshot': {
    'title': title,
    'metric': metric,
    'targetValue': target,
    'progressValue': progress,
    'periodType': 'weekly',
    'visibility': 'club',
    'startAt': startAt,
    'endAtExclusive': endAtExclusive,
    'participants': 3,
    'achievers': 2,
    'displayName': 'An',
  },
};

/// API giả: ghi lại lệnh gọi; GET trả [view], POST trả thẻ huyền thoại.
class _Backend {
  final requests = <String>[];
  Map<String, dynamic> view;

  _Backend(this.view);

  RunNowApiClient client() => RunNowApiClient(
    baseUri: Uri.parse('https://api.example.test'),
    tokenProvider: ({required forceRefresh}) async => 'token',
    appVersion: () async => '1.6.0+1',
    appPlatform: 'ios',
    httpClient: MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      final out = request.method == 'POST' ? {'card': _cardJson()} : view;
      return http.Response(
        jsonEncode(out),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
}

RunContract _contract({
  RunContractStatus status = RunContractStatus.completed,
  Map<String, double> progress = const {},
}) {
  final start = DateTime.utc(2026, 10, 18, 17);
  return RunContract(
    id: 'k1',
    creatorUid: 'u1',
    title: 'Tuần 30 km',
    template: RunContractTemplate.weekly10k,
    metric: RunContractMetric.distance,
    targetValue: 20,
    periodType: RunContractPeriodType.weekly,
    startAt: start,
    endAtExclusive: start.add(const Duration(days: 7)),
    finalizeAt: start.add(const Duration(days: 7, hours: 6)),
    status: status,
    visibility: RunContractVisibility.club,
    progressValue: 23.5,
    participants: {
      for (final MapEntry(key: uid, value: value) in progress.entries)
        uid: RunContractParticipant(
          uid: uid,
          progressValue: value,
          joinedAt: start,
          updatedAt: start,
        ),
    },
    createdAt: start,
    updatedAt: start,
  );
}

Future<void> _pump(WidgetTester tester, _Backend backend) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [runNowApiClientProvider.overrideWithValue(backend.client())],
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ContractCardPanel(contract: _contract()),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('đạt kèo thì úp thẻ kèm tỉ lệ theo km tích luỹ, lật ra thẻ', (
    tester,
  ) async {
    final backend = _Backend({
      'card': null,
      'km': 23.5,
      'odds': _cardJson()['odds'],
    });
    await _pump(tester, backend);
    expect(find.text('TỈ LỆ CHO 23,5 KM TÍCH LUỸ'), findsOneWidget);
    expect(find.text('Khoe thẻ'), findsNothing);

    await tester.ensureVisible(find.text('Lật thẻ'));
    await tester.tap(find.text('Lật thẻ'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    expect(backend.requests, [
      'GET /v1/contracts/k1/card',
      'POST /v1/contracts/k1/card',
    ]);
    expect(find.text('Lật thẻ'), findsNothing);
    expect(find.text('Khoe thẻ'), findsOneWidget);
    expect(
      find.textContaining('Huyền thoại · 23,5 km tích luỹ'),
      findsOneWidget,
    );
  });

  testWidgets('kèo chưa chốt mà đã đạt thì xem trước tỉ lệ, chưa lật được', (
    tester,
  ) async {
    final backend = _Backend({
      'card': null,
      'reason': 'card_contract_open',
      'km': 23.5,
      'odds': _cardJson()['odds'],
    });
    await _pump(tester, backend);
    expect(find.text('TỈ LỆ CHO 23,5 KM TÍCH LUỸ'), findsOneWidget);
    // Kèo chốt 25/10 23:00 UTC, tức 06:00 26/10 giờ VN.
    expect(
      find.text(
        'Kèo chốt lúc 06:00 26/10 rồi mới lật được thẻ. Tích thêm km trước '
        'giờ đó thì tỉ lệ còn tăng.',
      ),
      findsOneWidget,
    );
    expect(find.text('CHƯA CHỐT'), findsNothing);
    expect(find.text('Lật thẻ'), findsNothing);
    expect(backend.requests, ['GET /v1/contracts/k1/card']);
  });

  testWidgets('backend cũ báo chưa chốt mà không kèm tỉ lệ thì lá khoá', (
    tester,
  ) async {
    final backend = _Backend({'card': null, 'reason': 'card_contract_open'});
    await _pump(tester, backend);
    expect(find.text('CHƯA CHỐT'), findsOneWidget);
    expect(find.text('Kèo chốt xong mới lật được thẻ.'), findsOneWidget);
    expect(find.text('Lật thẻ'), findsNothing);
  });

  testWidgets('chưa đạt mục tiêu thì lá khoá, không có nút lật', (
    tester,
  ) async {
    final backend = _Backend({'card': null, 'reason': 'card_contract_failed'});
    await _pump(tester, backend);
    expect(find.text('CHƯA ĐẠT'), findsOneWidget);
    expect(
      find.text('Chỉ người đạt mục tiêu của chính mình mới lật được thẻ kèo.'),
      findsOneWidget,
    );
    expect(find.text('Lật thẻ'), findsNothing);
    expect(backend.requests, ['GET /v1/contracts/k1/card']);
  });

  test('đạt mục tiêu là có mục thẻ, kể cả khi kèo chưa chốt', () {
    // Mục tiêu 20 km: u1 đạt 23,5, u2 mới 12.
    const progress = {'u1': 23.5, 'u2': 12.0};
    bool shown(RunContractStatus status, String uid) =>
        contractCardShown(_contract(status: status, progress: progress), uid);
    expect(shown(RunContractStatus.active, 'u1'), isTrue);
    expect(shown(RunContractStatus.active, 'u2'), isFalse);
    expect(shown(RunContractStatus.completed, 'u2'), isTrue);
    expect(shown(RunContractStatus.failed, 'u2'), isTrue);
    expect(shown(RunContractStatus.cancelled, 'u1'), isFalse);
  });

  test('thẻ kèo tuần quãng đường in thời gian, phần vượt và số người đạt', () {
    final data = contractCardData(ContractCard.fromJson(_cardJson()));
    expect(data.tier, GameCardTier.legendary);
    expect(data.kind, 'KÈO TUẦN · QUÃNG ĐƯỜNG');
    expect(data.title, 'Tuần 30 km');
    expect((data.hero, data.heroUnit), ('23,5', 'KM'));
    // 19.10.2026 là thứ Hai, 25.10.2026 là Chủ nhật.
    expect(data.period, (text: 'T2 19.10 → CN 25.10.2026', span: '7 NGÀY'));
    // 23,5 trên mục tiêu 20 km: vượt 3,5 km.
    expect(data.stats, [
      (value: '20 km', label: 'MỤC TIÊU'),
      (value: '+3,5 km', label: 'VƯỢT'),
      (value: '2/3', label: 'NGƯỜI ĐẠT'),
    ]);
    expect(data.owner, 'AN');
  });

  test('kèo tháng đếm buổi: khung tháng, km tích luỹ, phần trăm trên dấu', () {
    // 01.10 → 31.10.2026 giờ VN; 13 buổi trên mục tiêu 12, 61,2 km tích luỹ.
    final data = contractCardData(
      ContractCard.fromJson(
        _cardJson(
          metric: 'activity_count',
          target: 12,
          progress: 13,
          km: 61.2,
          title: '12 buổi tháng 10',
          startAt: '2026-09-30T17:00:00Z',
          endAtExclusive: '2026-10-31T17:00:00Z',
        ),
      ),
    );
    expect(data.kind, 'KÈO THÁNG · SỐ BUỔI');
    expect((data.hero, data.heroUnit), ('13', 'BUỔI'));
    expect(data.period, (text: '01.10 → 31.10.2026', span: '31 NGÀY'));
    expect(data.stats, [
      (value: '12 buổi', label: 'MỤC TIÊU'),
      (value: '61,2', label: 'KM TÍCH LUỸ'),
      (value: '2/3', label: 'NGƯỜI ĐẠT'),
    ]);
    // 13/12 = 108,3% → in 108%.
    expect((data.stamp! as ContractCardStamp).pct, '108%');
    expect(
      (data.backFace! as ContractCardBack).period,
      '01.10 → 31.10.2026 · 31 NGÀY',
    );
    expect((data.art as ContractCardArt).scene, ContractCardScene.count);
  });

  test('kèo trong ngày in thứ và ngày, tờ lịch đúng ngày kèo', () {
    // Chủ nhật 01.11.2026 giờ VN; 3,1 km trên mục tiêu 2 km.
    final data = contractCardData(
      ContractCard.fromJson(
        _cardJson(
          target: 2,
          progress: 3.1,
          km: 3.1,
          startAt: '2026-10-31T17:00:00Z',
          endAtExclusive: '2026-11-01T17:00:00Z',
        ),
      ),
    );
    expect(data.kind, 'KÈO TRONG NGÀY');
    expect(data.period, (text: 'CN 01.11.2026', span: '1 NGÀY'));
    expect(data.stats![1], (value: '+1,1 km', label: 'VƯỢT'));
    final art = data.art as ContractCardArt;
    expect(art.scene, ContractCardScene.today);
    expect((art.day!.day, art.day!.month), (1, 11));
    expect((data.backFace! as ContractCardBack).period, 'CN 01.11.2026');
  });

  test('kèo hẹn chạy in giờ hẹn giờ VN và số người đăng ký', () {
    // Hẹn 05:45 Chủ nhật 25.10.2026 giờ VN = 22:45 UTC hôm trước.
    final data = contractCardData(
      ContractCard.fromJson(
        _cardJson(
          target: 5,
          progress: 6.2,
          km: 6.2,
          startAt: '2026-10-24T17:00:00Z',
          endAtExclusive: '2026-10-25T17:00:00Z',
        ),
      ),
      meetAt: DateTime.utc(2026, 10, 24, 22, 45),
    );
    expect(data.kind, 'KÈO HẸN CHẠY');
    expect(data.period, (text: 'CN 25.10.2026 · HẸN 05:45', span: '1 NGÀY'));
    expect(data.stats, [
      (value: '5 km', label: 'MỤC TIÊU'),
      (value: '3 người', label: 'ĐĂNG KÝ'),
      (value: '2/3', label: 'NGƯỜI ĐẠT'),
    ]);
    expect((data.art as ContractCardArt).scene, ContractCardScene.meet);
    expect(
      (data.backFace! as ContractCardBack).period,
      'CN 25.10.2026 · 05:45',
    );
  });
}
