import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/games/telegram_link_controller.dart';
import 'package:myrun/src/runnow_api_client.dart';

import 'support/fake_game_backend.dart';

void main() {
  late FakeGameBackend backend;
  late List<Uri> opened;
  late bool openOk;
  late TelegramLinkController controller;

  void setup() {
    backend = FakeGameBackend(() => DateTime.utc(2026, 10, 17, 14));
    opened = [];
    openOk = true;
    controller = TelegramLinkController(
      api: backend.client(),
      openUrl: (uri) async {
        opened.add(uri);
        return openOk;
      },
    );
  }

  int linkReads() =>
      backend.calls.where((c) => c == 'GET /v1/telegram/link').length;

  testWidgets('opens the deep link and polls until linked', (tester) async {
    setup();
    await controller.load();
    expect(controller.status!.linked, isFalse);

    await controller.link();
    expect(opened, [Uri.parse('https://t.me/runnow3i_bot?start=K7Q2')]);
    expect(controller.waiting, isTrue);

    await tester.pump(const Duration(seconds: 3));
    expect(linkReads(), 2);
    backend.telegram = {
      'linked': true,
      'tgUsername': 'an',
      'displayName': 'An',
      'inPsc': true,
    };
    await tester.pump(const Duration(seconds: 3));
    expect(controller.status!.linked, isTrue);
    expect(controller.status!.tgUsername, 'an');
    expect(controller.waiting, isFalse);

    await tester.pump(const Duration(minutes: 1));
    expect(linkReads(), 3);
    controller.dispose();
  });

  testWidgets('gives up polling after two minutes', (tester) async {
    setup();
    await controller.link();

    await tester.pump(const Duration(minutes: 2));
    expect(linkReads(), 40);
    expect(controller.waiting, isFalse);
    await tester.pump(const Duration(minutes: 1));
    expect(linkReads(), 40);
    controller.dispose();
  });

  testWidgets('reports when Telegram cannot open, without polling', (
    tester,
  ) async {
    setup();
    openOk = false;

    await expectLater(controller.link(), throwsStateError);
    expect(controller.waiting, isFalse);
    expect(controller.busy, isFalse);
    controller.dispose();
  });

  testWidgets('reads again on resume until linked', (tester) async {
    setup();
    await controller.load();

    controller.onResume();
    await tester.pump();
    expect(linkReads(), 2);

    backend.telegram = {
      'linked': true,
      'tgUsername': 'an',
      'displayName': 'An',
      'inPsc': false,
    };
    controller.onResume();
    await tester.pump();
    controller.onResume();
    await tester.pump();
    expect(linkReads(), 3);
    controller.dispose();
  });

  testWidgets('keeps the read error until a read succeeds', (tester) async {
    setup();
    backend.failures['GET /v1/telegram/link'] = (
      500,
      {'error': 'internal', 'message': 'Lỗi.'},
    );
    await controller.load();
    expect(controller.status, isNull);
    expect(controller.error, isA<RunNowApiException>());

    backend.failures.clear();
    await controller.load();
    expect(controller.error, isNull);
    expect(controller.status!.linked, isFalse);
    controller.dispose();
  });

  testWidgets('unlinks, and keeps the link when backend refuses', (
    tester,
  ) async {
    setup();
    backend.telegram = {
      'linked': true,
      'tgUsername': 'an',
      'displayName': 'An',
      'inPsc': true,
    };
    await controller.load();

    backend.failures['DELETE /v1/telegram/link'] = (
      409,
      {'error': 'in_game', 'message': 'Đang trong ván, chưa huỷ được.'},
    );
    await expectLater(
      controller.unlink(),
      throwsA(
        isA<RunNowApiException>().having((e) => e.code, 'code', 'in_game'),
      ),
    );
    expect(controller.status!.linked, isTrue);

    backend.failures.clear();
    await controller.unlink();
    expect(controller.status!.linked, isFalse);
    expect(backend.calls.last, 'DELETE /v1/telegram/link');
    controller.dispose();
  });
}
