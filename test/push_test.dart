import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myrun/src/push.dart';
import 'package:myrun/src/runnow_api_client.dart';

class _FakeMessaging implements PushMessaging {
  _FakeMessaging(this.status, {this.answer = PushPermission.granted});

  PushPermission status;

  /// Người dùng trả lời hộp thoại hỏi quyền thế này.
  final PushPermission answer;
  String? current = 'fcm-a';
  int asked = 0;
  final refresh = StreamController<String>.broadcast();
  final tapStream = StreamController<Map<String, dynamic>>.broadcast();
  Map<String, dynamic>? launch;

  @override
  Future<PushPermission> permission() async => status;

  @override
  Future<PushPermission> requestPermission() async {
    asked++;
    return status = answer;
  }

  @override
  Future<String?> token() async => current;

  @override
  Stream<String> get tokenRefresh => refresh.stream;

  @override
  Future<Map<String, dynamic>?> launchTap() async => launch;

  @override
  Stream<Map<String, dynamic>> get taps => tapStream.stream;
}

void main() {
  late List<http.Request> requests;
  late RunNowApiClient api;

  setUp(() {
    requests = [];
    api = RunNowApiClient(
      tokenProvider: ({required forceRefresh}) async => 'id-token',
      baseUri: Uri.parse('https://api.test'),
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response('{"ok":true}', 200);
      }),
    );
  });

  List<Object?> calls() => [
    for (final r in requests) [r.method, jsonDecode(r.body)],
  ];

  PushController controller(MockFirebaseAuth auth, _FakeMessaging fcm) {
    final c = PushController(auth, api, fcm, 'ios');
    addTearDown(c.dispose);
    return c;
  }

  test('app open registers only when permission was already given', () async {
    controller(
      MockFirebaseAuth(signedIn: true),
      _FakeMessaging(PushPermission.granted),
    );
    await pumpEventQueue();
    expect(calls(), [
      [
        'PUT',
        {'token': 'fcm-a', 'platform': 'ios'},
      ],
    ]);

    requests.clear();
    final notAsked = _FakeMessaging(PushPermission.notAsked);
    controller(MockFirebaseAuth(signedIn: true), notAsked);
    await pumpEventQueue();
    expect(calls(), isEmpty);
    expect(notAsked.asked, 0);
  });

  test('joining a room asks once, then registers if allowed', () async {
    final fcm = _FakeMessaging(PushPermission.notAsked);
    final push = controller(MockFirebaseAuth(signedIn: true), fcm);
    await pumpEventQueue();

    await push.askForRooms();
    await push.askForRooms();
    expect(fcm.asked, 1);
    expect(calls(), [
      [
        'PUT',
        {'token': 'fcm-a', 'platform': 'ios'},
      ],
    ]);

    requests.clear();
    final refuses = _FakeMessaging(
      PushPermission.notAsked,
      answer: PushPermission.denied,
    );
    final refused = controller(MockFirebaseAuth(signedIn: true), refuses);
    await refused.askForRooms();
    await refused.askForRooms();
    expect(refuses.asked, 1);
    expect(calls(), isEmpty);
  });

  test('late or new token is registered; sign out removes it', () async {
    // iOS chưa có APNs token lúc mở app: token FCM tới sau qua refresh.
    final fcm = _FakeMessaging(PushPermission.granted)..current = null;
    final auth = MockFirebaseAuth(signedIn: true);
    final push = controller(auth, fcm);
    await pumpEventQueue();
    expect(calls(), isEmpty);

    fcm.refresh.add('fcm-b');
    await pumpEventQueue();
    await push.beforeSignOut();
    await auth.signOut();
    await pumpEventQueue();
    fcm.refresh.add('fcm-c');
    await pumpEventQueue();
    await push.beforeSignOut();

    expect(calls(), [
      [
        'PUT',
        {'token': 'fcm-b', 'platform': 'ios'},
      ],
      [
        'DELETE',
        {'token': 'fcm-b'},
      ],
    ]);
  });

  test(
    'signed out elsewhere: next account registers the token again',
    () async {
      final auth = MockFirebaseAuth(signedIn: true);
      controller(auth, _FakeMessaging(PushPermission.granted));
      await pumpEventQueue();
      await auth.signOut();
      await pumpEventQueue();
      await auth.signInAnonymously();
      await pumpEventQueue();

      expect(calls(), [
        [
          'PUT',
          {'token': 'fcm-a', 'platform': 'ios'},
        ],
        [
          'PUT',
          {'token': 'fcm-a', 'platform': 'ios'},
        ],
      ]);
    },
  );

  test('tapping a room notification opens that room', () async {
    final fcm = _FakeMessaging(PushPermission.notAsked)
      ..launch = {'kind': 'room_starting', 'roomId': 'r1'};
    final push = controller(MockFirebaseAuth(signedIn: true), fcm);
    final opened = <String>[];

    push.handleTaps(opened.add);
    push.handleTaps(opened.add);
    await pumpEventQueue();
    fcm.tapStream.add({'kind': 'room_request', 'roomId': 'r2'});
    fcm.tapStream.add({'kind': 'other', 'roomId': 'r3'});
    fcm.tapStream.add({'kind': 'room_denied'});
    await pumpEventQueue();

    expect(opened, ['/rooms/r1', '/rooms/r2']);
  });
}
