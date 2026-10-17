import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/games/game_chat_screen.dart';
import 'package:myrun/src/providers.dart';

import 'support/fake_game_backend.dart';

class _FakeUser implements User {
  @override
  String get uid => 'me';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _msg(
  int seq,
  String uid,
  String text, {
  bool system = false,
}) => {
  'seq': seq,
  'uid': uid,
  'name': uid.toUpperCase(),
  'text': text,
  'system': system,
  'at': DateTime.utc(2026, 10, 17, 15, seq).toIso8601String(),
};

void main() {
  late DateTime now;
  late FakeGameBackend backend;

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runNowApiClientProvider.overrideWithValue(backend.client()),
          firebaseUserProvider.overrideWith((ref) => Stream.value(_FakeUser())),
        ],
        child: const MaterialApp(
          home: GameChatScreen(gameId: 'g1', chatKey: 'wolves'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  /// Chữ của các tin theo thứ tự trên màn hình, từ trên xuống.
  List<String> shownTexts(WidgetTester tester) {
    final texts = <(double, String)>[];
    // Tin hệ thống có giờ nối phía sau nên tìm theo phần đầu.
    final finders = {
      for (final text in ['a', 'c', 'mới', 'cũ'])
        text: find.text(text, findRichText: true),
      'W1 chọn cắn V2.': find.textContaining('W1 chọn cắn V2.'),
    };
    for (final MapEntry(key: text, value: finder) in finders.entries) {
      for (final el in finder.evaluate()) {
        final box = el.renderObject! as RenderBox;
        texts.add((box.localToGlobal(Offset.zero).dy, text));
      }
    }
    texts.sort((x, y) => x.$1.compareTo(y.$1));
    return [for (final t in texts) t.$2];
  }

  setUp(() {
    now = DateTime.utc(2026, 10, 17, 16);
    backend = FakeGameBackend(() => now);
    backend.chatPages[''] = {
      'key': 'wolves',
      'label': 'Phe Sói',
      'canSend': true,
      'messages': [
        _msg(3, 'me', 'c'),
        _msg(2, 'w1', 'W1 chọn cắn V2.', system: true),
        _msg(1, 'w1', 'a'),
      ],
    };
  });

  testWidgets('shows oldest on top and sends a message', (tester) async {
    await pumpScreen(tester);
    expect(find.text('Phe Sói'), findsOneWidget);
    expect(shownTexts(tester), ['a', 'W1 chọn cắn V2.', 'c']);
    // Tên người gửi hiện với tin của người khác, không hiện với tin của mình.
    expect(find.text('W1'), findsOneWidget);
    expect(find.text('ME'), findsNothing);

    await tester.enterText(find.byType(TextField), '  mới  ');
    await tester.tap(find.byTooltip('Gửi'));
    await tester.pump();
    await tester.pump();

    final post = backend.requests.lastWhere((r) => r.method == 'POST');
    expect(post.url.path, '/v1/games/g1/chats/wolves');
    expect(jsonDecode(post.body), {'text': 'mới'});
    expect(shownTexts(tester), ['a', 'W1 chọn cắn V2.', 'c', 'mới']);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
    await close(tester);
  });

  testWidgets('keeps the text and shows the error when send fails', (
    tester,
  ) async {
    backend.failures['POST /v1/games/g1/chats/wolves'] = (
      429,
      {'error': 'too_fast', 'message': 'Gửi chậm lại một chút.'},
    );
    await pumpScreen(tester);
    await tester.enterText(find.byType(TextField), 'dồn');
    await tester.tap(find.byTooltip('Gửi'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Gửi chậm lại một chút.'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'dồn',
    );
    await close(tester);
  });

  testWidgets('read-only chat has no composer', (tester) async {
    backend.chatPages['']!['canSend'] = false;
    await pumpScreen(tester);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Bạn chỉ xem được chat này.'), findsOneWidget);
    await close(tester);
  });

  testWidgets('polls new messages while open', (tester) async {
    await pumpScreen(tester);
    final page = backend.chatPages['']!;
    backend.chatPages[''] = {
      ...page,
      'messages': [_msg(4, 'w1', 'mới'), ...(page['messages'] as List)],
    };
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('mới'), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('mới'), findsOneWidget);
    await close(tester);
  });

  testWidgets('loads older messages before the oldest one shown', (
    tester,
  ) async {
    backend.chatPages['']!['cursor'] = '1';
    backend.chatPages['1'] = {
      'key': 'wolves',
      'label': 'Phe Sói',
      'canSend': true,
      'messages': [_msg(0, 'w1', 'cũ')],
    };
    await pumpScreen(tester);
    await tester.tap(find.text('Tải tin cũ hơn'));
    await tester.pump();
    await tester.pump();

    expect(backend.requests.last.url.queryParameters['cursor'], '1');
    expect(shownTexts(tester).first, 'cũ');
    expect(find.text('Tải tin cũ hơn'), findsNothing);
    await close(tester);
  });
}
