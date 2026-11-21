import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/games/game_links.dart';

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
  test('a game invite link opens that game', () {
    expect(
      gameLinkLocation(Uri.parse('https://threei.run/games/Zz7ICw')),
      '/games/Zz7ICw',
    );
  });

  test('other links do not open a game', () {
    for (final link in [
      'https://threei.run/games/new',
      'https://threei.run/games/',
      'https://threei.run/games/g1/chat/wolves',
      'https://threei.run/delete-account',
      'https://evil.example/games/g1',
      'http://threei.run/games/g1',
      'com.threei.run://localhost/oauth?code=1',
    ]) {
      expect(gameLinkLocation(Uri.parse(link)), isNull, reason: link);
    }
  });

  test('the link that launched the app opens once', () async {
    final uri = Uri.parse('https://threei.run/games/g1');
    final links = _FakeLinks(uri);
    final opened = <String>[];

    await GameLinkOpener(links).start(opened.add);
    links.controller.add(uri);
    await pumpEventQueue();

    expect(opened, ['/games/g1']);
  });

  test('links tapped while the app runs open their game', () async {
    final links = _FakeLinks(null);
    final opened = <String>[];

    await GameLinkOpener(links).start(opened.add);
    links.controller.add(Uri.parse('https://threei.run/games/g2'));
    links.controller.add(Uri.parse('https://threei.run/support'));
    await pumpEventQueue();

    expect(opened, ['/games/g2']);
  });

  test('starting twice does not open links twice', () async {
    final links = _FakeLinks(null);
    final opened = <String>[];
    final opener = GameLinkOpener(links);

    await opener.start(opened.add);
    await opener.start(opened.add);
    links.controller.add(Uri.parse('https://threei.run/games/g3'));
    await pumpEventQueue();

    expect(opened, ['/games/g3']);
  });
}
