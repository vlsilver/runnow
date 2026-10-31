import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/runnow_api_client.dart';

/// Body giống backend thật: UTF-8, `Content-Type: application/json` không kèm
/// charset.
http.Response _json(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  test('reads backend Strava status with a Firebase bearer token', () async {
    late http.Request captured;
    final client = RunNowApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      tokenProvider: ({required forceRefresh}) async => 'firebase-token',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'connected': true,
            'status': 'active',
            'athleteId': '42',
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);

    final status = await client.getStravaStatus();

    expect(captured.url.path, '/v1/strava/status');
    expect(captured.headers['Authorization'], 'Bearer firebase-token');
    expect(status.connected, isTrue);
    expect(status.athleteId, '42');
  });

  test('mở phòng solo gửi kind, tuyến và không gửi tên', () async {
    late http.Request captured;
    final client = RunNowApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      tokenProvider: ({required forceRefresh}) async => 'firebase-token',
      httpClient: MockClient((request) async {
        captured = request;
        return _json({'id': 'room-1'}, 201);
      }),
    );
    addTearDown(client.close);

    final id = await client.createRunRoom(
      privacy: 'private',
      maxRunners: 8,
      kind: 'solo',
      route: RunContractRoute(
        points: const [
          RunContractRoutePoint(latitude: 21.05, longitude: 105.82),
          RunContractRoutePoint(latitude: 21.06, longitude: 105.83),
        ],
        distanceMeters: 1500,
      ),
    );

    expect(id, 'room-1');
    expect(jsonDecode(captured.body), {
      'privacy': 'private',
      'maxRunners': 8,
      'kind': 'solo',
      'route': {
        'points': [
          {'lat': 21.05, 'lng': 105.82},
          {'lat': 21.06, 'lng': 105.83},
        ],
        'distanceMeters': 1500,
      },
    });
  });

  test('retries once with a refreshed Firebase token after 401', () async {
    var calls = 0;
    final refreshValues = <bool>[];
    final client = RunNowApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      tokenProvider: ({required forceRefresh}) async {
        refreshValues.add(forceRefresh);
        return forceRefresh ? 'fresh-token' : 'stale-token';
      },
      httpClient: MockClient((request) async {
        calls += 1;
        if (calls == 1) return http.Response('{}', 401);
        expect(request.headers['Authorization'], 'Bearer fresh-token');
        return http.Response(
          jsonEncode({'connected': false, 'status': 'disconnected'}),
          200,
        );
      }),
    );
    addTearDown(client.close);

    final status = await client.getStravaStatus();

    expect(status.connected, isFalse);
    expect(refreshValues, [false, true]);
    expect(calls, 2);
  });

  test('returns backend authorization URL', () async {
    final client = RunNowApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      tokenProvider: ({required forceRefresh}) async => 'token',
      httpClient: MockClient((request) async {
        expect(jsonDecode(request.body), {'returnTarget': 'mobile'});
        return http.Response(
          jsonEncode({
            'authorizationUrl': 'https://www.strava.com/oauth/authorize',
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);

    final uri = await client.createStravaAuthorization(returnTarget: 'mobile');

    expect(uri.host, 'www.strava.com');
  });

  test('sends tracked activities to the authenticated backend', () async {
    final client = RunNowApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      tokenProvider: ({required forceRefresh}) async => 'token',
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/activities/tracked');
        expect(jsonDecode(request.body), {
          'activity': {'id': 'runnow-42', 'distanceMeters': 5000},
        });
        return http.Response(
          jsonEncode({
            'status': 'duplicate_of_strava',
            'stravaActivityId': '123',
          }),
          200,
        );
      }),
    );
    addTearDown(client.close);

    final result = await client.saveTrackedActivity({
      'id': 'runnow-42',
      'distanceMeters': 5000,
    });

    expect(result.status, 'duplicate_of_strava');
    expect(result.stravaActivityId, '123');
  });

  test('reads the error code backend writes under "error"', () async {
    final client = RunNowApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      tokenProvider: ({required forceRefresh}) async => 'token',
      httpClient: MockClient(
        (request) async => _json({
          'error': 'requirements_unmet',
          'message': 'Chưa đủ điều kiện đăng ký.',
          'requirements': [
            {'key': 'telegram_linked', 'ok': false, 'label': 'Liên kết'},
          ],
        }, 422),
      ),
    );
    addTearDown(client.close);

    final error = await client.getStravaStatus().then<Object?>(
      (_) => null,
      onError: (Object e) => e,
    );

    expect(error, isA<RunNowApiException>());
    final apiError = error! as RunNowApiException;
    expect(apiError.statusCode, 422);
    expect(apiError.code, 'requirements_unmet');
    expect(apiError.message, 'Chưa đủ điều kiện đăng ký.');
    expect(apiError.body['requirements'], hasLength(1));
  });

  test('sends app version only to game routes', () async {
    final seen = <String, Map<String, String>>{};
    final client = RunNowApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      tokenProvider: ({required forceRefresh}) async => 'token',
      appVersion: () async => '1.5.0+12',
      appPlatform: 'ios',
      httpClient: MockClient((request) async {
        seen[request.url.path] = request.headers;
        if (request.url.path == '/v1/strava/status') {
          return _json({'connected': false, 'status': 'disconnected'});
        }
        // Go encode slice nil thành null.
        return _json({
          'viewer': {'canCreate': false},
          'createOptions': {'roles': null},
          'items': null,
        });
      }),
    );
    addTearDown(client.close);

    final list = await client.listGames();
    await client.getStravaStatus();

    expect(seen['/v1/games']?['X-App-Version'], '1.5.0+12');
    expect(seen['/v1/games']?['X-App-Platform'], 'ios');
    // API đang chạy chỉ cho phép Authorization, Content-Type qua CORS.
    expect(seen['/v1/strava/status'], isNot(contains('X-App-Version')));
    expect(seen['/v1/strava/status'], isNot(contains('X-App-Platform')));
    expect(list.canCreate, isFalse);
    expect(list.roleOptions, isEmpty);
    expect(list.items, isEmpty);
  });

  test('sends profile mutations to the authenticated backend', () async {
    final client = RunNowApiClient(
      baseUri: Uri.parse('https://api.example.test'),
      tokenProvider: ({required forceRefresh}) async => 'token',
      httpClient: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/profile');
        expect(jsonDecode(request.body), {
          'nickname': 'Linh',
          'avatarUrl': null,
          'visibility': 'public',
        });
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.close);

    await client.updateProfile(
      nickname: 'Linh',
      avatarUrl: null,
      visibility: 'public',
    );
  });

  group('Ma Sói', () {
    final requests = <http.Request>[];

    RunNowApiClient gameClient(Object Function(http.Request) respond) {
      requests.clear();
      final client = RunNowApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        tokenProvider: ({required forceRefresh}) async => 'token',
        appVersion: () async => '1.5.0+12',
        appPlatform: 'android',
        httpClient: MockClient((request) async {
          requests.add(request);
          final out = respond(request);
          return out is http.Response ? out : _json(out);
        }),
      );
      addTearDown(client.close);
      return client;
    }

    test('parses game detail the way Go encodes it', () async {
      final client = gameClient(
        (_) => {
          'id': 'g1',
          'title': 'Ma Sói tuần 42',
          'status': 'running',
          'statusLabel': 'Đang chơi',
          'testMode': false,
          'version': 37,
          'serverNow': '2026-10-17T21:59:30.123456789+07:00',
          'refreshAfterSeconds': 30,
          'rulesText': 'Luật',
          'phase': {
            'key': 'r3.day',
            'label': 'Ngày 3',
            'deadline': '2026-10-17T22:00:00+07:00',
            'state': 'closing',
          },
          'players': [
            {'uid': 'u1', 'name': 'An', 'alive': true, 'lastKm': 5},
            {
              'uid': 'u2',
              'name': 'Bình',
              'avatarUrl': 'https://img/u2',
              'alive': false,
              'revealedRoleLabel': 'Sói',
              'revealedCardUrl': 'https://img/wolf',
              'deathRound': 2,
              'onTrial': true,
              'lastKm': 0,
              'fake': true,
            },
          ],
          'playerCount': 2,
          'minPlayers': 8,
          'maxPlayers': 20,
          'registrationDeadline': null,
          'feed': {
            'items': [
              {
                'seq': 9,
                'at': '2026-10-17T10:00:00Z',
                'title': 'Trời sáng',
                'lines': ['Bình chết'],
              },
            ],
            'cursor': 'c9',
          },
          'requirements': [
            {'key': 'telegram_linked', 'ok': true, 'label': 'Đã liên kết'},
            {
              'key': 'app_version',
              'ok': false,
              'label': 'Cập nhật app',
              'action': {'type': 'update_app'},
            },
          ],
          'isRegistered': true,
          'isAdmin': false,
          'minAppVersion': '1.5.0',
        },
      );

      final game = await client.getGame('g/1');

      expect(requests.single.url.path, '/v1/games/g%2F1');
      expect(requests.single.headers['X-App-Version'], '1.5.0+12');
      expect(game.version, 37);
      expect(game.serverNow, DateTime.utc(2026, 10, 17, 14, 59, 30, 123, 456));
      expect(game.phase!.deadline, DateTime.utc(2026, 10, 17, 15));
      expect(game.phase!.isClosing, isTrue);
      expect(game.registrationDeadline, isNull);
      expect(game.winner, isNull);
      expect(game.startError, isNull);

      final an = game.players[0];
      expect(an.avatarUrl, isNull);
      expect(an.revealedRoleLabel, isNull);
      expect(an.deathRound, isNull);
      expect(an.onTrial, isFalse);
      expect(an.lastKm, 5.0);
      final binh = game.players[1];
      expect(binh.alive, isFalse);
      expect(binh.revealedRoleLabel, 'Sói');
      expect(binh.deathRound, 2);
      expect(binh.onTrial, isTrue);
      expect(binh.lastKm, 0.0);
      expect(binh.fake, isTrue);

      expect(game.feed.cursor, 'c9');
      expect(game.feed.items.single.lines, ['Bình chết']);
      expect(game.requirements[0].action, isNull);
      expect(game.requirements[1].ok, isFalse);
      expect(game.requirements[1].action!.type, 'update_app');
      expect(game.requirements[1].action!.url, isNull);
    });

    test('reads Go zero time and empty lists as absent', () async {
      final client = gameClient(
        (_) => {
          'id': 'g1',
          'status': 'registering',
          'serverNow': '2026-10-17T08:00:00Z',
          'phase': null,
          'players': null,
          'feed': {'items': null},
          'requirements': null,
          'startError': {
            'code': 'not_enough_players',
            'message': 'Thiếu người',
            'at': '0001-01-01T00:00:00Z',
          },
        },
      );

      final game = await client.getGame('g1');

      expect(game.phase, isNull);
      expect(game.players, isEmpty);
      expect(game.feed.items, isEmpty);
      expect(game.feed.cursor, isNull);
      expect(game.requirements, isEmpty);
      expect(game.startError!.code, 'not_enough_players');
      expect(game.startError!.at, isNull);
    });

    test('rejects a field of the wrong type instead of blanking it', () async {
      final client = gameClient((_) => {'id': 'g1', 'playerCount': '3'});

      await expectLater(client.getGame('g1'), throwsA(isA<TypeError>()));
    });

    test('parses /me with actions the app draws generically', () async {
      final client = gameClient(
        (_) => {
          'status': 'running',
          'role': 'witch',
          'roleLabel': 'Phù thuỷ',
          'roleRules': 'Một bình cứu, một bình độc',
          'cardUrl': 'https://img/witch',
          'alive': true,
          'potions': {'save': false, 'poison': true},
          'notes': [
            {'round': 1, 'text': 'Đêm 1 sói cắn An'},
          ],
          'inviteLinks': null,
          'actions': [
            {
              'kind': 'witch_poison',
              'label': 'Bình độc',
              'help': 'Chọn một người',
              'input': 'single_target',
              'options': [
                {'id': 'u1', 'label': 'An'},
                {'id': 'u3', 'label': 'Cường', 'avatarUrl': 'https://img/u3'},
              ],
              'selected': {
                'targets': ['u3'],
              },
              'opensAt': '2026-10-17T22:00:00+07:00',
              'closesAt': null,
              'enabled': true,
              'confirmText': 'Chắc chưa?',
            },
            {
              'kind': 'new_kind_from_backend',
              'label': 'Việc mới',
              'help': '',
              'input': 'choice',
              'options': [
                {'id': 'a', 'label': 'A'},
              ],
              'selected': null,
              'opensAt': null,
              'closesAt': null,
              'enabled': false,
              'disabledReason': 'Chưa tới giờ',
            },
          ],
        },
      );

      final me = await client.getGameMe('g1');

      expect(requests.single.url.path, '/v1/games/g1/me');
      expect(me.roleLabel, 'Phù thuỷ');
      expect(me.cardBackUrl, isNull);
      expect(me.potions!.save, isFalse);
      expect(me.potions!.poison, isTrue);
      expect(me.notes.single.round, 1);
      expect(me.inviteLinks, isEmpty);
      expect(me.allRoles, isEmpty);

      final poison = me.actions[0];
      expect(poison.input, 'single_target');
      expect(poison.options[1].avatarUrl, 'https://img/u3');
      expect(poison.selected!.targets, ['u3']);
      expect(poison.selected!.choice, isNull);
      expect(poison.opensAt, DateTime.utc(2026, 10, 17, 15));
      expect(poison.closesAt, isNull);
      expect(poison.disabledReason, isNull);
      expect(poison.confirmText, 'Chắc chưa?');

      final unknown = me.actions[1];
      expect(unknown.kind, 'new_kind_from_backend');
      expect(unknown.selected, isNull);
      expect(unknown.enabled, isFalse);
      expect(unknown.disabledReason, 'Chưa tới giờ');
    });

    test('sends only fields backend knows when acting', () async {
      final client = gameClient((_) => {'status': 'running', 'alive': true});

      await client.submitGameAction('g1', kind: 'vote', targets: ['u2']);
      final voteBody = jsonDecode(requests.single.body);
      await client.submitGameAction('g1', kind: 'witch_save', choice: 'yes');
      final choiceBody = jsonDecode(requests.last.body);
      await client.submitGameAction('g1', kind: 'vote', clear: true);
      final clearBody = jsonDecode(requests.last.body);

      expect(requests.first.method, 'POST');
      expect(requests.first.url.path, '/v1/games/g1/actions');
      expect(voteBody, {
        'kind': 'vote',
        'targets': ['u2'],
      });
      expect(choiceBody, {'kind': 'witch_save', 'choice': 'yes'});
      expect(clearBody, {'kind': 'vote', 'clear': true});
    });

    test('creates a game with only the fields given', () async {
      final client = gameClient((_) => _json({'id': 'g9'}, 201));

      final id = await client.createGame(
        roles: {'cupid': false, 'hunter': true},
        registrationDeadline: DateTime.parse('2026-10-18T20:00:00+07:00'),
      );

      expect(id, 'g9');
      expect(jsonDecode(requests.single.body), {
        'roles': {'cupid': false, 'hunter': true},
        'registrationDeadline': '2026-10-18T13:00:00.000Z',
      });
    });

    test('pages the feed by cursor', () async {
      final client = gameClient(
        (_) => {
          'items': [
            {
              'seq': 1,
              'at': '2026-10-16T15:00:00Z',
              'title': 'Đêm 1',
              'lines': null,
            },
          ],
        },
      );

      final feed = await client.getGameFeed('g1', cursor: 'a b&c');

      expect(requests.single.url.path, '/v1/games/g1/feed');
      expect(requests.single.url.queryParameters, {'cursor': 'a b&c'});
      expect(feed.items.single.lines, isEmpty);
      expect(feed.cursor, isNull);
    });

    test('previews start with dryRun and starts for real', () async {
      final client = gameClient(
        (request) => request.url.queryParameters['dryRun'] == 'true'
            ? {
                'willExclude': [
                  {
                    'uid': 'u5',
                    'name': 'Dũng',
                    'reason': 'not_in_psc',
                    'reasonLabel': 'Chưa vào PSC',
                  },
                ],
                'players': [
                  {'uid': 'u1', 'name': 'An', 'tgUsername': 'an'},
                  {'uid': 'u2', 'name': 'Bot 2', 'fake': true},
                ],
                'count': 2,
                'minPlayers': 8,
                'maxPlayers': 20,
                'canStart': false,
                'balanceScore': null,
              }
            : _json({'status': 'starting', 'attempt': 3}, 202),
      );

      final preview = await client.previewGameStart('g1');
      final attempt = await client.startGame('g1');

      expect(requests.first.url.path, '/v1/games/g1/start');
      expect(requests.last.url.queryParameters, isEmpty);
      expect(preview.willExclude.single.reasonLabel, 'Chưa vào PSC');
      expect(preview.players[0].tgUsername, 'an');
      expect(preview.players[1].tgUsername, isNull);
      expect(preview.players[1].fake, isTrue);
      expect(preview.canStart, isFalse);
      expect(preview.balanceScore, isNull);
      expect(attempt, 3);
    });

    test('calls admin routes', () async {
      final client = gameClient(
        (request) => request.url.path.endsWith('retry-outbox')
            ? {'ok': true, 'requeued': 4}
            : {'ok': true},
      );

      await client.pauseGame('g1');
      await client.resumeGame('g1');
      await client.cancelGame('g1');
      await client.extendGame('g1', minutes: 90);
      final requeued = await client.retryGameOutbox('g1');

      expect(
        [for (final r in requests) r.url.path],
        [
          '/v1/games/g1/admin/pause',
          '/v1/games/g1/admin/resume',
          '/v1/games/g1/admin/cancel',
          '/v1/games/g1/admin/extend',
          '/v1/games/g1/admin/retry-outbox',
        ],
      );
      expect(jsonDecode(requests[3].body), {'minutes': 90});
      expect(requeued, 4);
    });

    test('reads Telegram link status, empty strings as absent', () async {
      final client = gameClient(
        (request) => switch (request.method) {
          'POST' => {
            'code': 'K7Q2',
            'deepLink': 'https://t.me/runnow3i_bot?start=K7Q2',
            'expiresAt': '2026-10-17T08:10:00Z',
          },
          'GET' => {
            'linked': true,
            'tgUsername': 'an',
            'displayName': 'An',
            'inPsc': true,
          },
          _ => {
            'linked': false,
            'tgUsername': '',
            'displayName': '',
            'inPsc': false,
          },
        },
      );

      final code = await client.createTelegramLinkCode();
      final linked = await client.getTelegramLink();
      await client.unlinkTelegram();

      expect(requests[0].url.path, '/v1/telegram/link-code');
      expect(requests[0].headers, isNot(contains('X-App-Version')));
      expect(code.deepLink, 'https://t.me/runnow3i_bot?start=K7Q2');
      expect(code.expiresAt, DateTime.utc(2026, 10, 17, 8, 10));
      expect(linked.tgUsername, 'an');
      expect(linked.inPsc, isTrue);
      expect(requests[2].method, 'DELETE');
      expect(requests[2].url.path, '/v1/telegram/link');
      expect(
        TelegramLinkStatus.fromJson({
          'linked': false,
          'tgUsername': '',
          'displayName': '',
          'inPsc': false,
        }).tgUsername,
        isNull,
      );
    });

    test('push token goes to PUT then DELETE /v1/push-token', () async {
      final client = gameClient((_) => {'ok': true});

      await client.registerPushToken('fcm-token-1', 'ios');
      await client.unregisterPushToken('fcm-token-1');

      expect(requests[0].method, 'PUT');
      expect(requests[0].url.path, '/v1/push-token');
      expect(jsonDecode(requests[0].body), {
        'token': 'fcm-token-1',
        'platform': 'ios',
      });
      expect(requests[1].method, 'DELETE');
      expect(requests[1].url.path, '/v1/push-token');
      expect(jsonDecode(requests[1].body), {'token': 'fcm-token-1'});
    });
  });
}
