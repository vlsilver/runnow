import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/repository.dart';
import 'package:myrun/src/rooms/run_room_actions.dart';
import 'package:myrun/src/rooms/run_room_models.dart';
import 'package:myrun/src/rooms/run_room_repository.dart';
import 'package:myrun/src/rooms/run_room_route_sketch.dart';
import 'package:myrun/src/rooms/run_room_screen.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/tracking_draft_store.dart';
import 'package:myrun/src/tracking_session.dart';

void main() {
  const me = 'runner-me';

  group('publishSnapshot trong phòng', () {
    late FakeFirebaseFirestore firestore;
    late FirestoreLiveTrackingRepository repository;
    late TrackingSessionSnapshot snapshot;

    setUp(() async {
      firestore = FakeFirebaseFirestore();
      repository = FirestoreLiveTrackingRepository(
        MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: me)),
        firestore,
      );
      // Hồ sơ công khai: ngoài phòng thì buổi live hiện cho cả club.
      await firestore.collection('publicProfiles').doc(me).set({
        'displayName': 'Me',
        'profileVisibility': 'public',
      });
      snapshot = (TrackingSession(
        id: 'run-1',
      )..start(DateTime.utc(2026, 10, 31, 6))).snapshot();
    });

    Future<Map<String, dynamic>> publish({
      String? roomId,
      bool roomOnly = false,
    }) async {
      await repository.publishSnapshot(
        snapshot: snapshot,
        status: LiveTrackingStatus.running,
        routePreview: const [],
        roomId: roomId,
        roomOnly: roomOnly,
      );
      return (await firestore.collection('liveSessions').doc('run-1').get())
          .data()!;
    }

    test('phòng kín: chỉ người trong phòng xem dù hồ sơ công khai', () async {
      final data = await publish(roomId: 'room-a', roomOnly: true);
      expect(data['visibility'], 'private');
      expect(data['roomId'], 'room-a');
    });

    test('phòng công khai: club vẫn thấy, kèm roomId', () async {
      final data = await publish(roomId: 'room-a');
      expect(data['visibility'], 'club');
      expect(data['roomId'], 'room-a');
    });

    test('ngoài phòng: không ghi roomId', () async {
      final data = await publish();
      expect(data['visibility'], 'club');
      expect(data.containsKey('roomId'), isFalse);
    });
  });

  group('RunRoomRepository', () {
    late FakeFirebaseFirestore firestore;
    late RunRoomRepository repository;
    final now = DateTime.utc(2026, 10, 31, 6);

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repository = RunRoomRepository(firestore);
    });

    Future<void> member(
      String roomId,
      String uid,
      String state,
      DateTime updatedAt,
    ) => firestore
        .collection('runRooms')
        .doc(roomId)
        .collection('members')
        .doc(uid)
        .set({
          'uid': uid,
          'name': uid,
          'role': 'runner',
          'state': state,
          'updatedAt': Timestamp.fromDate(updatedAt),
        });

    test(
      'phòng của mình: đang ở hay chờ duyệt, trong 8 ngày gần nhất',
      () async {
        await member(
          'joined',
          me,
          'joined',
          now.subtract(const Duration(hours: 1)),
        );
        await member(
          'asked',
          me,
          'requested',
          now.subtract(const Duration(days: 7)),
        );
        // Phòng đã qua lâu: member vẫn joined vì kết thúc phòng không đổi state.
        await member(
          'old',
          me,
          'joined',
          now.subtract(const Duration(days: 9)),
        );
        await member('gone', me, 'left', now);
        await member('kicked', me, 'kicked', now);
        await member('joined', 'someone-else', 'joined', now);

        final rooms = await repository.watchMyRooms(me, now).first;

        expect(
          {for (final r in rooms) r.roomId: r.state},
          {
            'joined': RunRoomMemberState.joined,
            'asked': RunRoomMemberState.requested,
          },
        );
      },
    );

    test(
      'live của phòng: chỉ buổi đang chạy hay tạm dừng của phòng đó',
      () async {
        final fresh = Timestamp.fromDate(DateTime.now());
        Future<void> live(String id, String roomId, String status) =>
            firestore.collection('liveSessions').doc(id).set({
              'ownerUid': id,
              'ownerName': id,
              'visibility': 'private',
              'status': status,
              'roomId': roomId,
              'startedAt': fresh,
              'updatedAt': fresh,
              'distanceMeters': 1000,
              'movingTimeSeconds': 300,
            });
        await live('a', 'room-a', 'running');
        await live('b', 'room-a', 'paused');
        await live('c', 'room-a', 'finished');
        await live('d', 'room-b', 'running');

        final sessions = await repository.watchRoomLive('room-a').first;

        expect(sessions.map((s) => s.id).toSet(), {'a', 'b'});
        expect(sessions.map((s) => s.roomId).toSet(), {'room-a'});
      },
    );

    test('phòng công khai: bỏ phòng solo, đọc được tuyến', () async {
      Future<void> room(String id, Map<String, dynamic> extra) =>
          firestore.collection('runRooms').doc(id).set({
            'title': id,
            'privacy': 'public',
            'status': 'open',
            'closesAt': Timestamp.fromDate(now.add(const Duration(hours: 2))),
            ...extra,
          });
      await room('group', {
        'kind': 'group',
        'route': {
          'distanceMeters': 6400,
          'points': [
            {'lat': 21.05, 'lng': 105.82},
            {'lat': 21.06, 'lng': 105.83},
          ],
        },
      });
      await room('solo', {'kind': 'solo'});

      final rooms = await repository.watchPublicRooms(now).first;

      expect(rooms.map((r) => r.id), ['group']);
      expect(rooms.single.kind, RunRoomKind.group);
      expect(rooms.single.route?.distanceMeters, 6400);
      expect(rooms.single.route?.points.last.longitude, 105.83);
      expect(RunRoom.fromMap('cũ', const {}).kind, RunRoomKind.group);
      expect(RunRoom.fromMap('cũ', const {}).route, isNull);
    });

    test('cổ vũ: ghi đúng field rules cho phép, TTL 6 ngày', () async {
      await repository.sendMessage('room-a', uid: me, text: '🔥', emoji: true);

      final docs = await firestore
          .collection('runRooms')
          .doc('room-a')
          .collection('messages')
          .get();
      final data = docs.docs.single.data();
      expect(data.keys.toSet(), {'uid', 'kind', 'text', 'at', 'expiresAt'});
      expect(data['kind'], 'emoji');
      final expires = (data['expiresAt'] as Timestamp).toDate();
      expect(
        expires.difference(DateTime.now()).inHours,
        inInclusiveRange(6 * 24 - 1, 6 * 24),
      );
    });
  });

  test('tuyến gửi lên phòng: tối đa 120 điểm, giữ đầu cuối và quãng gốc', () {
    final long = RunContractRoute(
      points: [
        for (var i = 0; i < 1000; i++)
          RunContractRoutePoint(latitude: 21 + i / 10000, longitude: 105.8),
      ],
      distanceMeters: 11120,
    );

    final preview = runRoomRoutePreview(long);

    expect(preview.points, hasLength(120));
    expect(preview.points.first.latitude, 21);
    expect(preview.points.last.latitude, closeTo(21.0999, 1e-9));
    expect(preview.distanceMeters, 11120);

    final short = RunContractRoute(
      points: long.points.take(50).toList(),
      distanceMeters: 550,
    );
    expect(runRoomRoutePreview(short).points, hasLength(50));
  });

  test('draft giữ phòng để mở lại app vẫn chạy chung phòng', () {
    final draft = TrackingDraft(
      session: TrackingSession(id: 'run-1')..start(DateTime.utc(2026, 10, 31)),
      roomId: 'room-a',
    );

    final restored = TrackingDraft.fromMap(draft.toMap());

    expect(restored.roomId, 'room-a');
  });

  group('runRoomErrorText khi bị khoá vì sai mật khẩu', () {
    String locked(int seconds) => runRoomErrorText(
      RunNowApiException(
        statusCode: 429,
        code: 'room_locked',
        message: 'locked',
        body: {'retryAfterSeconds': seconds},
      ),
    );

    test('dưới một giờ thì nói phút, làm tròn lên', () {
      expect(locked(599), 'Sai mật khẩu nhiều lần. Thử lại sau 10 phút.');
    });

    test('từ một giờ thì nói giờ, làm tròn lên', () {
      expect(locked(3600), 'Sai mật khẩu nhiều lần. Thử lại sau 1 giờ.');
      expect(
        locked(23 * 3600 + 1),
        'Sai mật khẩu nhiều lần. Thử lại sau 24 giờ.',
      );
    });
  });

  test('phòng quá giờ đóng thì không còn mở', () {
    final room = RunRoom.fromMap('r', {
      'status': 'open',
      'closesAt': Timestamp.fromDate(DateTime.utc(2026, 10, 31, 12)),
    });

    expect(room.isOpen(DateTime.utc(2026, 10, 31, 11, 59)), isTrue);
    expect(room.isOpen(DateTime.utc(2026, 10, 31, 12)), isFalse);
  });

  group('RunRoomScreen khi chưa vào phòng', () {
    late FakeFirebaseFirestore firestore;

    Future<void> seedRoom(
      String privacy, {
      String? myState,
      Map<String, Object>? route,
    }) async {
      final room = firestore.collection('runRooms').doc('room-a');
      await room.set({
        'route': ?route,
        'hostUid': 'host-1',
        'hostName': 'Chủ',
        'title': 'Hồ Tây sáng',
        'privacy': privacy,
        'maxRunners': 8,
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
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            runRoomRepositoryProvider.overrideWithValue(
              RunRoomRepository(firestore),
            ),
            firebaseUserProvider.overrideWith(
              (ref) => Stream.value(MockUser(uid: me)),
            ),
          ],
          child: MaterialApp(
            theme: buildRunNowTheme(RunNowElement.water),
            home: const RunRoomScreen(roomId: 'room-a'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    setUp(() => firestore = FakeFirebaseFirestore());

    testWidgets('phòng chủ duyệt thì nút là xin vào', (tester) async {
      await seedRoom('private');
      await pump(tester);
      expect(find.text('Xin vào phòng'), findsOneWidget);
      expect(find.text('Chạy cùng phòng'), findsNothing);
    });

    testWidgets('phòng mật khẩu thì nút hỏi mật khẩu', (tester) async {
      await seedRoom('password');
      await pump(tester);
      expect(find.text('Nhập mật khẩu để vào'), findsOneWidget);
    });

    testWidgets('đã xin vào thì chờ duyệt và huỷ được', (tester) async {
      await seedRoom('private', myState: 'requested');
      await pump(tester);
      expect(
        find.text('Đã xin vào, đang chờ chủ phòng duyệt.'),
        findsOneWidget,
      );
      expect(find.text('Huỷ xin vào'), findsOneWidget);
      expect(find.text('Xin vào phòng'), findsNothing);
    });

    testWidgets('phòng có tuyến thì người ngoài thấy quãng và hình tuyến', (
      tester,
    ) async {
      await seedRoom(
        'public',
        route: {
          'distanceMeters': 6400,
          'points': [
            {'lat': 21.05, 'lng': 105.82},
            {'lat': 21.06, 'lng': 105.83},
          ],
        },
      );
      await pump(tester);
      expect(find.text('Tuyến 6,4 km'), findsOneWidget);
      expect(find.byType(RunRoomRouteSketch), findsOneWidget);
    });

    testWidgets('bị mời ra thì không có nút vào lại', (tester) async {
      await seedRoom('public', myState: 'kicked');
      await pump(tester);
      expect(
        find.text('Chủ phòng đã mời bạn ra khỏi phòng này.'),
        findsOneWidget,
      );
      expect(find.text('Vào phòng'), findsNothing);
    });
  });

  test('buổi chạy riêng có phòng solo kín vẫn live cho cả club', () {
    bool roomOnly(RunRoomKind? kind, RunRoomPrivacy? privacy) =>
        runRoomLiveRoomOnly(roomId: 'r1', kind: kind, privacy: privacy);

    expect(roomOnly(RunRoomKind.solo, RunRoomPrivacy.private), isFalse);
    expect(roomOnly(RunRoomKind.group, RunRoomPrivacy.private), isTrue);
    expect(roomOnly(RunRoomKind.group, RunRoomPrivacy.public), isFalse);
    // Chưa đọc được phòng thì giữ kín cho an toàn.
    expect(roomOnly(null, null), isTrue);
    expect(
      runRoomLiveRoomOnly(roomId: null, kind: null, privacy: null),
      isFalse,
    );
  });
}
