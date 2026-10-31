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
import 'package:myrun/src/rooms/run_room_voice.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

class _FakeVoiceLink implements VoiceLink {
  final joins = <String>[];
  var leaves = 0;

  @override
  Future<int> join(
    String url,
    String token, {
    required void Function(int peers) onPeers,
    required void Function() onDropped,
  }) async {
    joins.add('$url $token');
    return 2;
  }

  @override
  Future<void> leave() async => leaves++;
}

void main() {
  const runner = 'runner-3';
  late FakeFirebaseFirestore firestore;
  late _FakeVoiceLink link;
  late List<String> calls;

  DocumentReference<Map<String, dynamic>> room() =>
      firestore.collection('runRooms').doc('room-1');

  Future<void> seed() async {
    await room().set({
      'hostUid': 'host-1',
      'hostName': 'Minh Anh',
      'title': 'Chạy đêm',
      'privacy': 'private',
      'kind': 'group',
      'maxRunners': 8,
      'runnerCount': 2,
      'status': 'open',
      'closesAt': Timestamp.fromDate(
        DateTime.now().add(const Duration(hours: 3)),
      ),
    });
    await room().collection('members').doc(runner).set({
      'uid': runner,
      'name': 'Gia Huy',
      'role': 'runner',
      'state': 'joined',
    });
  }

  Future<void> pump(
    WidgetTester tester, {
    int status = 200,
    String body = '{"url":"wss://voice.example.test","token":"lk-token-1"}',
  }) async {
    final client = RunNowApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      tokenProvider: ({required forceRefresh}) async => 'token',
      httpClient: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        return http.Response(
          body,
          status,
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
            (ref) => Stream.value(MockUser(uid: runner)),
          ),
          runNowApiClientProvider.overrideWithValue(client),
          voiceLinkFactoryProvider.overrideWithValue(() => link),
        ],
        child: MaterialApp(
          theme: buildRunNowTheme(RunNowElement.water),
          home: const Scaffold(body: RunRoomRunPanel(roomId: 'room-1')),
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    link = _FakeVoiceLink();
    calls = [];
  });

  testWidgets('bấm Nói chuyện thì lấy vé của phòng rồi vào phòng thoại', (
    tester,
  ) async {
    await seed();
    await pump(tester);

    await tester.tap(find.text('Nói chuyện'));
    await tester.pump();
    await tester.pump();

    expect(calls, ['POST /v1/run-rooms/room-1/voice']);
    expect(link.joins, ['wss://voice.example.test lk-token-1']);
    expect(find.text('Đang nói · 2 người nghe'), findsOneWidget);
  });

  testWidgets('bị mời ra khỏi phòng thì tự thoát thoại', (tester) async {
    await seed();
    await pump(tester);
    await tester.tap(find.text('Nói chuyện'));
    await tester.pump();
    await tester.pump();
    expect(link.leaves, 0);

    await room().collection('members').doc(runner).update({'state': 'kicked'});
    await tester.pump();
    await tester.pump();

    expect(link.leaves, 1);
    expect(find.text('Nói chuyện'), findsNothing);
  });

  testWidgets('chưa bật thoại thì báo câu của backend, không vào phòng thoại', (
    tester,
  ) async {
    await seed();
    await pump(
      tester,
      status: 503,
      body:
          '{"error":"voice_unavailable","message":"Chưa bật nói chuyện trong phòng."}',
    );

    await tester.tap(find.text('Nói chuyện'));
    await tester.pump();
    await tester.pump();

    expect(link.joins, isEmpty);
    expect(find.text('Chưa bật nói chuyện trong phòng.'), findsOneWidget);
    expect(find.text('Nói chuyện'), findsOneWidget);
  });
}
