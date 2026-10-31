import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/games/game_turn.dart';
import 'package:myrun/src/runnow_api_client.dart';

GameAction _action({
  bool enabled = true,
  String? opensAt,
  String? closesAt,
  String? reason,
}) => GameAction.fromJson({
  'kind': 'any_kind',
  'label': 'Việc',
  'help': '',
  'input': 'single_target',
  'enabled': enabled,
  'opensAt': ?opensAt,
  'closesAt': ?closesAt,
  'disabledReason': ?reason,
});

void main() {
  final now = DateTime.utc(2026, 10, 17, 14);

  test('an open action inside its window is your turn until it closes', () {
    final turn = gameTurnOf(
      [
        _action(
          opensAt: '2026-10-17T13:00:00Z',
          closesAt: '2026-10-17T15:05:00Z',
        ),
      ],
      now: now,
      alive: true,
    );
    expect(turn.state, GameTurnState.now);
    expect(turn.at, DateTime.utc(2026, 10, 17, 15, 5));
  });

  test('with two open actions the earlier close wins', () {
    final turn = gameTurnOf(
      [
        _action(closesAt: '2026-10-17T17:00:00Z'),
        _action(closesAt: '2026-10-17T15:00:00Z'),
      ],
      now: now,
      alive: true,
    );
    expect(turn.at, DateTime.utc(2026, 10, 17, 15));
  });

  test('inside the window but locked says why', () {
    final turn = gameTurnOf(
      [
        _action(
          enabled: false,
          closesAt: '2026-10-17T15:00:00Z',
          reason: 'Bạn chưa chạy đủ km.',
        ),
        _action(enabled: false, opensAt: '2026-10-17T17:00:00Z'),
      ],
      now: now,
      alive: true,
    );
    expect(turn.state, GameTurnState.locked);
    expect(turn.reason, 'Bạn chưa chạy đủ km.');
  });

  test('a window not open yet gives the earliest opening time', () {
    final turn = gameTurnOf(
      [
        _action(enabled: false, opensAt: '2026-10-17T20:00:00Z'),
        _action(enabled: false, opensAt: '2026-10-17T17:00:00Z'),
      ],
      now: now,
      alive: true,
    );
    expect(turn.state, GameTurnState.later);
    expect(turn.at, DateTime.utc(2026, 10, 17, 17));
  });

  test('a closed window is not your turn any more', () {
    final turn = gameTurnOf(
      [_action(closesAt: '2026-10-17T14:00:00Z')],
      now: now,
      alive: true,
    );
    expect(turn.state, GameTurnState.rest);
  });

  test('no action means rest while alive, out once dead', () {
    expect(gameTurnOf([], now: now, alive: true).state, GameTurnState.rest);
    expect(gameTurnOf([], now: now, alive: false).state, GameTurnState.out);
  });
}
