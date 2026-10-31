import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/rooms/run_room_repository.dart';
import 'package:myrun/src/rooms/run_together_button.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

void main() {
  const me = 'runner-me';
  late FakeFirebaseFirestore firestore;
  late List<String> calls;

  final session = LiveTrackingSession(
    id: 'live-1',
    ownerUid: 'host-1',
    ownerName: 'Minh Anh',
    visibility: LiveTrackingVisibility.club,
    status: LiveTrackingStatus.running,
    startedAt: DateTime.now().subtract(const Duration(minutes: 20)),
    updatedAt: DateTime.now(),
    distanceMeters: 3000,
    movingTimeSeconds: 1200,
    roomId: 'solo-1',
  );

  Future<void> seed({required String kind, String? myState}) async {
    final room = firestore.collection('runRooms').doc('solo-1');
    await room.set({
      'hostUid': 'host-1',
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
    if (myState != null) {
      await room.collection('members').doc(me).set({
        'uid': me,
        'name': 'Me',
        'role': 'runner',
        'state': myState,
      });
    }
  }

  Future<void> pump(WidgetTester tester) async {
    final client = RunNowApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      tokenProvider: ({required forceRefresh}) async => 'token',
      httpClient: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        return http.Response(
          '{"state":"requested"}',
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
            (ref) => Stream.value(MockUser(uid: me)),
          ),
          runNowApiClientProvider.overrideWithValue(client),
        ],
        child: MaterialApp(
          theme: buildRunNowTheme(RunNowElement.water),
          home: Scaffold(body: RunTogetherButton(session: session)),
        ),
      ),
    );
    // Doc phòng về rồi nút mới nghe state của mình: cần thêm một nhịp.
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    calls = [];
  });

  testWidgets('phòng solo cần duyệt: bấm Xin chạy cùng thì gửi xin vào', (
    tester,
  ) async {
    await seed(kind: 'solo');
    await pump(tester);

    await tester.tap(find.text('Xin chạy cùng'));
    await tester.pump();

    expect(calls, ['POST /v1/run-rooms/solo-1/join']);
  });

  testWidgets('đang chờ duyệt thì huỷ được', (tester) async {
    await seed(kind: 'solo', myState: 'requested');
    await pump(tester);

    expect(find.text('Xin chạy cùng'), findsNothing);
    await tester.tap(find.text('Đang chờ duyệt · Huỷ'));
    await tester.pump();

    expect(calls, ['POST /v1/run-rooms/solo-1/leave']);
  });

  testWidgets('phòng group thì không có nút chạy cùng', (tester) async {
    await seed(kind: 'group');
    await pump(tester);

    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });
}
