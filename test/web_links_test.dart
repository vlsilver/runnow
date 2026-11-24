import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/games/game_links.dart';
import 'package:myrun/src/web_links.dart';

class _FakeLinks extends Fake implements AppLinks {
  _FakeLinks(this.initial);

  final Uri? initial;
  final controller = StreamController<Uri>.broadcast();

  @override
  Future<Uri?> getInitialLink() async => initial;

  @override
  Stream<Uri> get uriLinkStream => controller.stream;
}

void main() {
  test('app mở link mời vào ván và link khoe live, link khác thì không', () {
    expect(
      webLinkLocation(Uri.parse('https://threei.run/games/g1')),
      '/games/g1',
    );
    expect(webLinkLocation(Uri.parse('https://threei.run/live')), '/live');
    expect(
      webLinkLocation(Uri.parse('https://threei.run/live/s1')),
      '/live/s1',
    );
    expect(webLinkLocation(Uri.parse('https://threei.run/support')), isNull);
  });

  test('link bảng đã chốt mở tab Club đúng bảng, khoá sai dạng thì không', () {
    expect(
      webLinkLocation(Uri.parse('https://threei.run/bxh/week_2026-11-23_run')),
      '/club?board=week_2026-11-23_run',
    );
    expect(webLinkLocation(Uri.parse('https://threei.run/bxh/abc')), isNull);
    expect(
      webLinkLocation(
        Uri.parse('https://evil.example/bxh/week_2026-11-23_run'),
      ),
      isNull,
    );
  });

  test('the link that launched the app opens once', () async {
    final uri = Uri.parse('https://threei.run/games/g1');
    final links = _FakeLinks(uri);
    final opened = <String>[];

    await WebLinkOpener(links, gameLinkLocation).start(opened.add);
    links.controller.add(uri);
    await pumpEventQueue();

    expect(opened, ['/games/g1']);
  });

  test('links tapped while the app runs open their game', () async {
    final links = _FakeLinks(null);
    final opened = <String>[];

    await WebLinkOpener(links, gameLinkLocation).start(opened.add);
    links.controller.add(Uri.parse('https://threei.run/games/g2'));
    links.controller.add(Uri.parse('https://threei.run/support'));
    await pumpEventQueue();

    expect(opened, ['/games/g2']);
  });

  test('starting twice does not open links twice', () async {
    final links = _FakeLinks(null);
    final opened = <String>[];
    final opener = WebLinkOpener(links, gameLinkLocation);

    await opener.start(opened.add);
    await opener.start(opened.add);
    links.controller.add(Uri.parse('https://threei.run/games/g3'));
    await pumpEventQueue();

    expect(opened, ['/games/g3']);
  });
}
