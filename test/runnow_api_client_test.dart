import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myrun/src/runnow_api_client.dart';

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
}
