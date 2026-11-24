import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/games/game_links.dart';

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
}
