import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:myrun/src/admin/admin_screen.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'dart:convert';

class _FakeUser implements User {
  @override
  String get uid => 'me';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MemberProfile _member(String uid, String name) => MemberProfile(
  uid: uid,
  displayName: name,
  visibility: ProfileVisibility.public,
);

void main() {
  final calls = <String>[];
  var admin = true;
  late Map<String, List<String>> roles;

  setUp(() {
    calls.clear();
    admin = true;
    roles = {
      'admin': ['me', 'an'],
      'tester': [],
      'bot': ['ghost'],
    };
  });

  RunNowApiClient client() => RunNowApiClient(
    baseUri: Uri.parse('https://api.example.test'),
    tokenProvider: ({required forceRefresh}) async => 'token',
    appVersion: () async => '1.5.0+12',
    appPlatform: 'web',
    httpClient: MockClient((request) async {
      final path = request.url.path;
      calls.add('${request.method} $path');
      if (!admin) {
        return http.Response(
          '{"error":"not_admin","message":"Chỉ admin làm được việc này."}',
          403,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      Object out = {'ok': true};
      final parts = path.split('/');
      switch ((request.method, path)) {
        case ('GET', '/v1/admin/settings'):
          out = {
            'roles': roles,
            'telegram': {'chatId': '-1001', 'botUsername': 'threei_bot'},
          };
        case ('POST', final p) when p.startsWith('/v1/admin/roles/'):
          roles[parts[4]]!.add(parts[5]);
        case ('DELETE', final p) when p.startsWith('/v1/admin/roles/'):
          roles[parts[4]]!.remove(parts[5]);
        default:
          return http.Response('{"error":"not_found"}', 404);
      }
      return http.Response(
        jsonEncode(out),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );

  Future<void> pump(WidgetTester tester) async {
    // Đủ cao để cả trang dựng hết, khỏi phải cuộn.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runNowApiClientProvider.overrideWithValue(client()),
          firebaseUserProvider.overrideWith((ref) => Stream.value(_FakeUser())),
          membersProvider.overrideWith(
            (ref) => Stream.value([
              _member('me', 'Tôi'),
              _member('an', 'An'),
              _member('dung', 'Dũng'),
            ]),
          ),
        ],
        child: const MaterialApp(home: AdminScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('grants and revokes roles, never my own admin', (tester) async {
    await pump(tester);
    expect(find.text('-1001'), findsOneWidget);
    expect(find.text('@threei_bot'), findsOneWidget);
    // uid không có hồ sơ thì hiện uid để admin vẫn bỏ được.
    expect(find.text('ghost'), findsOneWidget);
    // Hai admin, nhưng chỉ dòng của An có nút bỏ; ghost ở quyền bot có nút.
    expect(find.byTooltip('Bỏ quyền'), findsNWidgets(2));

    await tester.tap(find.text('Thêm').at(1));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'dũ');
    await tester.pumpAndSettle();
    expect(find.text('An'), findsOneWidget); // An ở trang admin phía sau
    await tester.tap(find.text('Dũng'));
    await tester.pumpAndSettle();
    expect(calls, contains('POST /v1/admin/roles/tester/dung'));
    expect(find.text('Dũng'), findsOneWidget);

    await tester.tap(find.byTooltip('Bỏ quyền').first);
    await tester.pumpAndSettle();
    expect(find.text('Bỏ quyền Admin của An?'), findsOneWidget);
    await tester.tap(find.text('Bỏ quyền').last);
    await tester.pumpAndSettle();
    expect(calls, contains('DELETE /v1/admin/roles/admin/an'));
    expect(roles['admin'], ['me']);
  });

  testWidgets('non-admins see no settings', (tester) async {
    admin = false;
    await pump(tester);
    expect(find.text('Chỉ admin xem được trang này.'), findsOneWidget);
    expect(find.text('Thêm'), findsNothing);
  });
}
