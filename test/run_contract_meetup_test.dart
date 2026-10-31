import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/run_contracts/run_contract_meetup.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/run_contract_period.dart';
import 'package:myrun/src/run_contracts/run_contract_repository.dart';
import 'package:myrun/src/run_contracts/widgets/run_contract_meetup_panel.dart';
import 'package:myrun/src/theme.dart';

void main() {
  test('kèo hẹn tính trọn ngày hẹn theo giờ máy, luôn public', () {
    final draft = RunContractDraft.meetup(
      meetAt: DateTime(2026, 11, 7, 18, 30),
      km: 3,
    );
    expect(draft.template, RunContractTemplate.meetup);
    expect(draft.period, RunContractPeriodType.custom);
    expect(draft.customStart, DateTime(2026, 11, 7));
    expect(draft.customEnd, DateTime(2026, 11, 8));
    expect(draft.metric, RunContractMetric.distance);
    expect(draft.targetValue, 3);
    expect(draft.visibility, RunContractVisibility.club);
    expect(draft.meetAt, DateTime(2026, 11, 7, 18, 30));
    expect(draft.validate(), isNull);
  });

  test('kèo hẹn lưu giờ hẹn và phòng, đọc lại đúng', () async {
    final firestore = FakeFirebaseFirestore();
    final repository = FirestoreRunContractRepository(
      MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'u1')),
      firestore,
    );
    final meetAt = DateTime(2026, 11, 7, 18, 30);
    final draft = RunContractDraft.meetup(
      meetAt: meetAt,
      km: 3,
    ).copyWith(roomId: 'room-1');
    final id = await repository.create(
      draft: draft,
      period: contractPeriodForDraft(draft, DateTime(2026, 11, 1)),
      initialProgress: 0,
    );

    final contract = (await repository.watchContract(id).first)!;
    expect(contract.meetAt, meetAt);
    expect(contract.roomId, 'room-1');
    expect(contract.template, RunContractTemplate.meetup);
    expect(contract.startAt, DateTime(2026, 11, 7));
    expect(contract.endAtExclusive, DateTime(2026, 11, 8));
  });

  group('createContractWithMeetupRoom', () {
    final meetAt = DateTime(2026, 11, 7, 18, 30);

    test('mở phòng đúng giờ hẹn rồi chốt kèo trỏ tới phòng', () async {
      DateTime? roomStartsAt;
      RunContractDraft? created;
      final id = await createContractWithMeetupRoom(
        RunContractDraft.meetup(meetAt: meetAt, km: 3),
        create: (draft) async {
          created = draft;
          return 'k1';
        },
        openRoom: (startsAt) async {
          roomStartsAt = startsAt;
          return 'room-1';
        },
        closeRoom: (_) async => fail('không được đóng phòng'),
      );
      expect(id, 'k1');
      expect(roomStartsAt, meetAt);
      expect(created!.roomId, 'room-1');
    });

    test('chốt kèo lỗi thì đóng phòng vừa mở, báo lỗi gốc', () async {
      final closed = <String>[];
      await expectLater(
        createContractWithMeetupRoom(
          RunContractDraft.meetup(meetAt: meetAt, km: 3),
          create: (_) async => throw const RunContractLimitReached(),
          openRoom: (_) async => 'room-1',
          closeRoom: (roomId) async => closed.add(roomId),
        ),
        throwsA(isA<RunContractLimitReached>()),
      );
      expect(closed, ['room-1']);
    });

    test('đóng phòng cũng lỗi thì vẫn báo lỗi chốt kèo', () async {
      await expectLater(
        createContractWithMeetupRoom(
          RunContractDraft.meetup(meetAt: meetAt, km: 3),
          create: (_) async => throw const RunContractLimitReached(),
          openRoom: (_) async => 'room-1',
          closeRoom: (_) async => throw StateError('mạng'),
        ),
        throwsA(isA<RunContractLimitReached>()),
      );
    });
  });

  group('RunContractMeetupPanel', () {
    RunContract contract({String? roomId, String status = 'active'}) =>
        RunContract.fromMap({
          'id': 'k1',
          'creatorUid': 'u1',
          'metric': 'distance',
          'targetValue': 3,
          'status': status,
          'meetAt': DateTime(2026, 11, 7, 18, 30),
          'roomId': ?roomId,
        });

    Future<void> pump(WidgetTester tester, RunContract contract) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) =>
                Scaffold(body: RunContractMeetupPanel(contract: contract)),
          ),
          GoRoute(
            path: '/rooms/:id',
            builder: (context, state) =>
                Text('phòng ${state.pathParameters['id']}'),
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp.router(
          theme: buildRunNowTheme(RunNowElement.water),
          routerConfig: router,
        ),
      );
      await tester.pump();
    }

    testWidgets('hiện giờ hẹn, bấm vào phòng mở đúng phòng', (tester) async {
      await pump(tester, contract(roomId: 'room-1'));
      expect(find.textContaining('18:30'), findsOneWidget);
      await tester.tap(find.text('Vào phòng chạy'));
      await tester.pumpAndSettle();
      expect(find.text('phòng room-1'), findsOneWidget);
    });

    testWidgets('chưa có phòng hay kèo đã chốt thì không có nút', (
      tester,
    ) async {
      await pump(tester, contract());
      expect(find.textContaining('18:30'), findsOneWidget);
      expect(find.text('Vào phòng chạy'), findsNothing);

      await pump(tester, contract(roomId: 'room-1', status: 'completed'));
      expect(find.text('Vào phòng chạy'), findsNothing);
    });
  });
}
