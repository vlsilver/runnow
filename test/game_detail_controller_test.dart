import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/games/game_detail_controller.dart';

import 'support/fake_game_backend.dart';

void main() {
  late DateTime now;
  late FakeGameBackend backend;
  late GameDetailController controller;

  void start(WidgetTester tester) {
    now = DateTime.utc(2026, 10, 17, 14);
    backend = FakeGameBackend(() => now);
  }

  Future<void> open(WidgetTester tester) async {
    controller = GameDetailController(
      api: backend.client(),
      gameId: 'g1',
      clock: () => now,
    );
    controller.setActive(true);
    await tester.pump();
  }

  /// Cho đồng hồ ván và timer của test cùng tiến.
  Future<void> elapse(WidgetTester tester, Duration d) async {
    now = now.add(d);
    await tester.pump(d);
  }

  testWidgets('reads /me only for registered players', (tester) async {
    start(tester);
    backend.game = {'id': 'g1', 'status': 'registering', 'isRegistered': false};
    await open(tester);

    expect(controller.detail!.status, 'registering');
    expect(controller.me, isNull);
    expect(backend.calls, ['GET /v1/games/g1']);
    controller.dispose();
  });

  testWidgets('polls at the interval backend asks for', (tester) async {
    start(tester);
    backend.game = {
      'id': 'g1',
      'status': 'running',
      'isRegistered': true,
      'refreshAfterSeconds': 45,
      'rulesText': 'Luật cũ',
    };
    await open(tester);
    expect(controller.detail!.rulesText, 'Luật cũ');
    expect(controller.me, isNotNull);

    backend.game['rulesText'] = 'Luật mới';
    await elapse(tester, const Duration(seconds: 44));
    expect(controller.detail!.rulesText, 'Luật cũ');
    await elapse(tester, const Duration(seconds: 1));
    expect(controller.detail!.rulesText, 'Luật mới');
    expect(backend.calls, [
      'GET /v1/games/g1',
      'GET /v1/games/g1/me',
      'GET /v1/games/g1',
      'GET /v1/games/g1/me',
    ]);
    controller.dispose();
  });

  testWidgets('shows closing past deadline, reads result a minute later', (
    tester,
  ) async {
    start(tester);
    backend.game = {
      'id': 'g1',
      'status': 'running',
      'refreshAfterSeconds': 300,
      'phase': {
        'key': 'r1.day',
        'label': 'Ngày 1',
        'deadline': now.add(const Duration(seconds: 10)).toIso8601String(),
        'state': 'open',
      },
    };
    await open(tester);
    expect(controller.phaseClosing, isFalse);

    var notified = 0;
    controller.addListener(() => notified++);
    await elapse(tester, const Duration(seconds: 10));
    // Chưa đọc lại mà đã qua hạn: không được coi phase cũ là đang mở.
    expect(backend.calls, hasLength(1));
    expect(controller.phaseClosing, isTrue);
    expect(notified, 1);

    backend.game['phase'] = {
      'key': 'r1.dusk',
      'label': 'Hoàng hôn 1',
      'deadline': now.add(const Duration(hours: 5)).toIso8601String(),
      'state': 'open',
    };
    await elapse(tester, const Duration(seconds: 59));
    expect(backend.calls, hasLength(1));
    await elapse(tester, const Duration(seconds: 1));
    expect(backend.calls, hasLength(2));
    expect(controller.detail!.phase!.label, 'Hoàng hôn 1');
    expect(controller.phaseClosing, isFalse);
    controller.dispose();
  });

  testWidgets('counts down by server clock, not device clock', (tester) async {
    start(tester);
    // Máy chạy chậm 2 phút so với server.
    backend.now = () => now.add(const Duration(minutes: 2));
    backend.game = {
      'id': 'g1',
      'status': 'running',
      'phase': {
        'key': 'r1.day',
        'label': 'Ngày 1',
        'deadline': now.add(const Duration(minutes: 3)).toIso8601String(),
        'state': 'open',
      },
    };
    await open(tester);

    expect(controller.serverNow(), now.add(const Duration(minutes: 2)));
    await elapse(tester, const Duration(minutes: 1));
    expect(controller.phaseClosing, isTrue);
    controller.dispose();
  });

  testWidgets('a refresh started before an action keeps the action /me', (
    tester,
  ) async {
    start(tester);
    backend.game = {'id': 'g1', 'status': 'running', 'isRegistered': true};
    await open(tester);

    final release = Completer<void>();
    backend.holdMe = release.future;
    final pending = controller.refresh();
    await tester.pump();
    await controller.submitAction(kind: 'vote', targets: ['u2']);
    final seen = <int>[];
    controller.addListener(() => seen.add(controller.me!.notes.length));

    backend.holdMe = null;
    release.complete();
    await pending;
    await tester.pump();

    // Lượt refresh cũ trả /me cũ (chưa có ghi chú): không được hiện lại,
    // kể cả thoáng qua. Lượt chạy thêm sau action đọc /me mới.
    expect(seen, isNotEmpty);
    expect(seen, everyElement(1));
    expect(controller.me!.notes.single.text, 'từ action');
    expect(backend.calls.where((c) => c == 'GET /v1/games/g1').length, 3);
    controller.dispose();
  });

  testWidgets('stops polling in background and refreshes on resume', (
    tester,
  ) async {
    start(tester);
    backend.game = {'id': 'g1', 'status': 'running', 'refreshAfterSeconds': 30};
    await open(tester);

    controller.setActive(false);
    await elapse(tester, const Duration(minutes: 10));
    expect(backend.calls, hasLength(1));

    controller.setActive(true);
    await tester.pump();
    expect(backend.calls, hasLength(2));
    await elapse(tester, const Duration(seconds: 30));
    expect(backend.calls, hasLength(3));
    controller.dispose();
  });

  testWidgets('keeps the last detail when a refresh fails', (tester) async {
    start(tester);
    backend.game = {'id': 'g1', 'status': 'running', 'title': 'Ván 1'};
    await open(tester);

    backend.game = {'playerCount': 'không phải số'};
    await controller.refresh();

    expect(controller.error, isNotNull);
    expect(controller.detail!.title, 'Ván 1');

    backend.game = {'id': 'g1', 'status': 'running', 'title': 'Ván 1b'};
    await elapse(tester, GameDetailController.fallbackPoll);
    expect(controller.error, isNull);
    expect(controller.detail!.title, 'Ván 1b');
    controller.dispose();
  });

  testWidgets('pages older feed and merges by seq', (tester) async {
    start(tester);
    Map<String, dynamic> item(int seq) => {
      'seq': seq,
      'at': '2026-10-17T10:00:00Z',
      'title': 'Tin $seq',
      'lines': null,
    };
    backend.game = {
      'id': 'g1',
      'status': 'running',
      'feed': {
        'items': [item(5), item(4)],
        'cursor': 'c4',
      },
    };
    backend.feedPages = {
      'c4': {
        'items': [item(3), item(2)],
        'cursor': 'c2',
      },
      'c2': {
        'items': [item(1)],
      },
    };
    await open(tester);
    expect(controller.hasOlderFeed, isTrue);

    await controller.loadOlderFeed();
    // Tin mới tới đẩy trang đầu: 6,5 ở trang đầu, 4 rơi sang trang cũ.
    backend.game['feed'] = {
      'items': [item(6), item(5)],
      'cursor': 'c5',
    };
    await controller.refresh();
    await controller.loadOlderFeed();

    expect([for (final i in controller.feedItems) i.seq], [6, 5, 4, 3, 2, 1]);
    expect(controller.hasOlderFeed, isFalse);
    expect(backend.calls.where((c) => c.endsWith('/feed')), hasLength(2));
    controller.dispose();
  });
}
