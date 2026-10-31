import 'dart:convert';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myrun/src/repository.dart';
import 'package:myrun/src/runnow_api_client.dart';

Map<String, dynamic> _activity(
  String id,
  String name,
  String source, {
  String sportType = 'Run',
  double distanceMeters = 5000,
  String? duplicateOf,
}) => {
  'id': id,
  'name': name,
  'source': source,
  'sportType': sportType,
  'startedAt': '2026-10-23T06:00:00Z',
  'distanceMeters': distanceMeters,
  'movingTimeSeconds': 1800,
  'elapsedTimeSeconds': 1900,
  'duplicateOfActivityId': ?duplicateOf,
};

void main() {
  test(
    'journal pages come from the backend list, not Firestore docs',
    () async {
      final firestore = FakeFirebaseFirestore();
      // Doc trên Firestore khác hẳn dữ liệu backend: đọc nhầm Firestore là lộ.
      await firestore
          .doc('users/me/activities/old')
          .set(_activity('old', 'Từ Firestore', 'strava'));
      final requests = <Uri>[];
      final api = RunNowApiClient(
        baseUri: Uri.parse('https://api.example.test'),
        tokenProvider: ({required forceRefresh}) async => 'token',
        httpClient: MockClient((request) async {
          requests.add(request.url);
          final body = request.url.queryParameters.containsKey('cursor')
              ? {'activities': <Object>[]}
              : {
                  'activities': [
                    _activity('c', 'Strava sáng', 'strava'),
                    _activity('b', '3i sáng', 'runnow', duplicateOf: 'c'),
                    // Đi bộ ngắn từ Health không tính, nhật ký bỏ như trước.
                    _activity(
                      'w',
                      'Đi bộ',
                      'apple_health',
                      sportType: 'Walk',
                      distanceMeters: 800,
                    ),
                  ],
                  'cursor': '2026-10-23T06:00:00Z|w',
                };
          return http.Response.bytes(
            utf8.encode(jsonEncode(body)),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(api.close);
      final repository = FirestoreStravaActivityRepository(
        MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'me')),
        firestore,
        api,
      );

      final first = await repository.fetchJournalActivitiesPage(limit: 20);
      expect(requests.single.path, '/v1/activities');
      expect(requests.single.queryParameters, {'limit': '20'});
      expect(
        [for (final e in first.entries) e.activity.name],
        ['Strava sáng', '3i sáng'],
      );
      expect(first.entries[1].preferredStravaActivityId, 'c');
      expect(first.hasMore, isTrue);

      final second = await repository.fetchJournalActivitiesPage(
        limit: 20,
        cursor: first.nextCursor,
      );
      expect(requests.last.queryParameters, {
        'limit': '20',
        'cursor': '2026-10-23T06:00:00Z|w',
      });
      expect(second.entries, isEmpty);
      expect(second.hasMore, isFalse);
    },
  );
}
