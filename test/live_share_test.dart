import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/achievements/run_faces/face_map.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/rooms/live_board.dart';
import 'package:myrun/src/rooms/live_screen.dart';
import 'package:myrun/src/rooms/live_share.dart';
import 'package:myrun/src/rooms/run_room_models.dart';
import 'package:myrun/src/theme.dart';

void main() {
  final at = DateTime(2026, 11, 22, 6, 5);

  LiveTrackingSession session(
    String id,
    String name, {
    double lat = 10.78,
    double lng = 106.70,
    bool located = true,
    LiveTrackingVisibility visibility = LiveTrackingVisibility.club,
    LiveTrackingStatus status = LiveTrackingStatus.running,
    DateTime? updatedAt,
  }) => LiveTrackingSession(
    id: id,
    ownerUid: 'u-$id',
    ownerName: name,
    visibility: visibility,
    status: status,
    startedAt: at.subtract(const Duration(minutes: 20)),
    updatedAt: updatedAt ?? at,
    distanceMeters: 3470,
    movingTimeSeconds: 1200,
    lastLocation: located
        ? RoutePoint(latitude: lat, longitude: lng, timestamp: at)
        : null,
  );

  Future<void> show(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildRunNowTheme(RunNowElement.water),
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pump();
  }

  test('khoe live một người: club kèm link xem, riêng tư thì không', () {
    expect(
      liveSessionCaption(session('s 1', 'Lan')),
      'Lan đang chạy live trên 3i: 3.47 km\nhttps://threei.run/live/s%201',
    );
    expect(
      liveSessionCaption(
        session('s1', 'Lan', visibility: LiveTrackingVisibility.private),
      ),
      'Lan đang chạy live trên 3i: 3.47 km',
    );
    expect(
      liveBoardCaption(12),
      '12 người đang chạy live trên 3i\nhttps://threei.run/live',
    );
  });

  test('link live mở đúng màn Live hoặc màn xem một người', () {
    expect(liveLinkLocation(Uri.parse('https://threei.run/live')), '/live');
    expect(liveLinkLocation(Uri.parse('https://threei.run/live/')), '/live');
    expect(
      liveLinkLocation(Uri.parse('https://threei.run/live/s%201')),
      '/live/s%201',
    );
    for (final link in [
      'https://threei.run/live/a/b',
      'https://threei.run/lively',
      'https://evil.example/live/s1',
      'http://threei.run/live/s1',
      'https://threei.run/games/g1',
    ]) {
      expect(liveLinkLocation(Uri.parse(link)), isNull, reason: link);
    }
  });

  test('chỉ khoe được khi đang live, có vị trí, và là club hoặc chính chủ', () {
    final soon = at.add(const Duration(minutes: 2));
    expect(canShareLive(session('a', 'A'), 'u-x', soon), isTrue);
    // Mất tín hiệu quá 3 phút thì không còn live.
    expect(
      canShareLive(
        session('a', 'A'),
        'u-x',
        at.add(const Duration(minutes: 4)),
      ),
      isFalse,
    );
    expect(
      canShareLive(
        session('a', 'A', status: LiveTrackingStatus.finished),
        'u-x',
        at,
      ),
      isFalse,
    );
    expect(canShareLive(session('a', 'A', located: false), 'u-a', at), isFalse);
    final private = session(
      'a',
      'A',
      visibility: LiveTrackingVisibility.private,
    );
    expect(canShareLive(private, 'u-x', at), isFalse);
    expect(canShareLive(private, 'u-a', at), isTrue);
  });

  test(
    'cả màn Live chỉ lấy người trong phòng đang chạy và người chạy riêng',
    () {
      RunRoom room(String id) => RunRoom(
        id: id,
        hostUid: 'h',
        hostName: 'H',
        title: id,
        privacy: RunRoomPrivacy.public,
        maxRunners: 8,
        runnerCount: 1,
        ended: false,
        startsAt: at,
        closesAt: at.add(const Duration(hours: 2)),
      );
      LiveTrackingSession inRoom(String id, String roomId) =>
          LiveTrackingSession(
            id: id,
            ownerUid: 'u-$id',
            ownerName: id,
            visibility: LiveTrackingVisibility.club,
            status: LiveTrackingStatus.running,
            startedAt: at,
            updatedAt: at,
            distanceMeters: 0,
            movingTimeSeconds: 0,
            roomId: roomId,
          );
      final board = LiveBoard(
        liveRooms: [room('live')],
        upcomingRooms: [room('soon')],
        solos: [SoloLive(session: session('solo', 'S'))],
        myStates: const {},
        meLive: false,
        runners: [
          inRoom('r1', 'live'),
          inRoom('r2', 'soon'),
          session('solo', 'S'),
          session('lạ', 'L'),
        ],
      );
      expect(board.everyoneOnMap.map((s) => s.id), ['r1', 'solo']);
    },
  );

  testWidgets('ảnh một người có nhãn LIVE, giờ chụp, tên và số km', (
    tester,
  ) async {
    await show(tester, LiveSessionPoster(session: session('a', 'Lan'), at: at));
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('06:05 · 22/11'), findsOneWidget);
    expect(find.text('Lan'), findsOneWidget);
    expect(find.textContaining('3.47'), findsOneWidget);
    // Chưa có pace thì chỉ in thời gian.
    expect(find.text('20:00'), findsOneWidget);
    expect(find.text(mapCreditLine()), findsOneWidget);
  });

  testWidgets('ảnh cả màn Live đếm người và gộp cụm người đứng sát nhau', (
    tester,
  ) async {
    await show(
      tester,
      LiveBoardPoster(
        sessions: [
          session('hn', 'Minh', lat: 21.03, lng: 105.85),
          session('sg1', 'Hùng', lat: 10.7800, lng: 106.7000),
          session('sg2', 'Lan', lat: 10.7801, lng: 106.7001),
        ],
        at: at,
      ),
    );
    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('3 người đang chạy'), findsOneWidget);
    // Hai người HCM cách nhau ~15 m: một avatar kèm số 2.
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('màn Live có nút khoe khi có người đang chạy có vị trí', (
    tester,
  ) async {
    Future<void> pumpBoard(List<LiveTrackingSession> runners) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            liveBoardProvider.overrideWithValue(
              AsyncValue.data(
                LiveBoard(
                  liveRooms: const <RunRoom>[],
                  upcomingRooms: const <RunRoom>[],
                  solos: [for (final r in runners) SoloLive(session: r)],
                  myStates: const {},
                  meLive: false,
                  runners: runners,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: buildRunNowTheme(RunNowElement.water),
            home: const LiveScreen(),
          ),
        ),
      );
      await tester.pump();
    }

    await pumpBoard([session('x', 'X', located: false)]);
    expect(find.byTooltip('Khoe live'), findsNothing);

    await pumpBoard([session('a', 'Lan')]);
    expect(find.byTooltip('Khoe live'), findsOneWidget);
  });
}
