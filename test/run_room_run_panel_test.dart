import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/rooms/run_room_repository.dart';
import 'package:myrun/src/rooms/run_room_run_panel.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

void main() {
  const host = 'host-1';
  late FakeFirebaseFirestore firestore;
  late List<String> calls;

  Future<void> seed({required String kind}) async {
    final room = firestore.collection('runRooms').doc('solo-1');
    await room.set({
      'hostUid': host,
      'hostName': 'Minh Anh',
      'title': 'Minh Anh',
      'privacy': 'private',
      'kind': kind,
      'maxRunners': 20,
      'runnerCount': 1,
      'status': 'open',
      'closesAt': Timestamp.fromDate(
        DateTime.now().add(const Duration(hours: 3)),
      ),
    });
    await room.collection('members').doc(host).set({
      'uid': host,
      'name': 'Minh Anh',
      'role': 'host',
      'state': 'joined',
    });
    await room.collection('members').doc('runner-2').set({
      'uid': 'runner-2',
      'name': 'Bảo Ngọc',
      'role': 'runner',
      'state': 'requested',
    });
  }

  Future<void> pump(WidgetTester tester, {required String uid}) async {
    final client = RunNowApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      tokenProvider: ({required forceRefresh}) async => 'token',
      httpClient: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        return http.Response(
          '{}',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runRoomRepositoryProvider.overrideWithValue(
            RunRoomRepository(firestore),
          ),
          firebaseUserProvider.overrideWith(
            (ref) => Stream.value(MockUser(uid: uid)),
          ),
          runNowApiClientProvider.overrideWithValue(client),
        ],
        child: MaterialApp(
          theme: buildRunNowTheme(RunNowElement.water),
          home: const Scaffold(body: RunRoomRunPanel(roomId: 'solo-1')),
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    calls = [];
  });

  testWidgets(
    'chủ buổi chạy riêng duyệt người xin chạy cùng ngay trên màn chạy',
    (tester) async {
      await seed(kind: 'solo');
      await pump(tester, uid: host);

      expect(find.text('Đang nhận người chạy cùng'), findsOneWidget);
      expect(find.text('Bảo Ngọc'), findsOneWidget);
      await tester.tap(find.text('Cho vào'));
      await tester.pump();

      expect(calls, ['POST /v1/run-rooms/solo-1/members/runner-2/approve']);
    },
  );

  testWidgets('người chạy cùng thấy tên chủ buổi, không thấy ai xin vào', (
    tester,
  ) async {
    await seed(kind: 'solo');
    await firestore
        .collection('runRooms')
        .doc('solo-1')
        .collection('members')
        .doc('runner-3')
        .set({
          'uid': 'runner-3',
          'name': 'Gia Huy',
          'role': 'runner',
          'state': 'joined',
        });
    await pump(tester, uid: 'runner-3');

    expect(find.text('Chạy cùng Minh Anh'), findsOneWidget);
    expect(find.text('Bảo Ngọc'), findsNothing);
    expect(find.text('Cho vào'), findsNothing);
  });
}
