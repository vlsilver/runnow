import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/games/game_action_card.dart';
import 'package:myrun/src/runnow_api_client.dart';

const _people = [
  {'id': 'u1', 'label': 'An'},
  {'id': 'u2', 'label': 'Bình'},
  {'id': 'u3', 'label': 'Chi'},
];

GameAction _action(Map<String, dynamic> json) => GameAction.fromJson({
  'kind': 'new_kind',
  'label': 'Chọn người',
  'help': '',
  'enabled': true,
  'options': _people,
  ...json,
});

void main() {
  /// Mỗi lần gửi ghi thành `targets|choice|clear`.
  late List<String> sent;
  late DateTime now;

  Future<void> pumpCard(WidgetTester tester, GameAction action) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GameActionCard(
            action: action,
            serverNow: () => now,
            onSubmit: ({targets = const [], choice, clear = false}) async {
              sent.add('${targets.join(',')}|$choice|$clear');
            },
          ),
        ),
      ),
    );
  }

  setUp(() {
    sent = [];
    now = DateTime.utc(2026, 10, 17, 14);
  });

  testWidgets('single target sends the picked person, whatever the kind', (
    tester,
  ) async {
    await pumpCard(
      tester,
      _action({
        'input': 'single_target',
        'selected': {
          'targets': ['u2'],
        },
      }),
    );

    await tester.tap(find.text('Bình'));
    await tester.pump();
    expect(sent, isEmpty);

    await tester.tap(find.text('An'));
    await tester.pump();
    expect(sent, ['u1|null|false']);
  });

  testWidgets('asks again when the backend gives confirm text', (tester) async {
    await pumpCard(
      tester,
      _action({
        'input': 'single_target',
        'confirmText': 'Chọn rồi không đổi được. Chắc chưa?',
      }),
    );

    await tester.tap(find.text('An'));
    await tester.pumpAndSettle();
    expect(find.text('Chọn rồi không đổi được. Chắc chưa?'), findsOneWidget);
    await tester.tap(find.text('Thôi'));
    await tester.pumpAndSettle();
    expect(sent, isEmpty);

    await tester.tap(find.text('An'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chắc'));
    await tester.pumpAndSettle();
    expect(sent, ['u1|null|false']);
  });

  testWidgets('two targets waits for two people', (tester) async {
    await pumpCard(tester, _action({'input': 'two_targets'}));

    await tester.tap(find.text('An'));
    await tester.pump();
    final button = find.widgetWithText(FilledButton, 'Chọn 1/2 người');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);

    await tester.tap(find.text('Bình'));
    await tester.tap(find.text('Chi'));
    await tester.pump();
    await tester.tap(find.text('Chọn 2/2 người'));
    await tester.pump();
    expect(sent, ['u1,u2|null|false']);
  });

  testWidgets('two targets follows a new selection from the backend', (
    tester,
  ) async {
    await pumpCard(
      tester,
      _action({
        'input': 'two_targets',
        'selected': {
          'targets': ['u1', 'u2'],
        },
      }),
    );
    await pumpCard(
      tester,
      _action({
        'input': 'two_targets',
        'selected': {
          'targets': ['u2', 'u3'],
        },
      }),
    );

    bool picked(String name) => tester
        .widget<GameOptionButton>(find.widgetWithText(GameOptionButton, name))
        .selected;
    expect([picked('An'), picked('Bình'), picked('Chi')], [false, true, true]);
  });

  testWidgets('choice sends the option id', (tester) async {
    await pumpCard(
      tester,
      _action({
        'input': 'choice',
        'options': [
          {'id': 'hang', 'label': 'Treo'},
          {'id': 'spare', 'label': 'Tha'},
        ],
      }),
    );

    await tester.tap(find.text('Treo'));
    await tester.pump();
    expect(sent, ['|hang|false']);
  });

  testWidgets('confirm sends the kind alone, and clears once chosen', (
    tester,
  ) async {
    await pumpCard(
      tester,
      _action({'input': 'confirm', 'label': 'Bình cứu', 'options': []}),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Bình cứu'));
    await tester.pump();
    expect(sent, ['|null|false']);

    await pumpCard(
      tester,
      _action({
        'input': 'confirm',
        'label': 'Bình cứu',
        'options': [],
        'selected': <String, dynamic>{},
      }),
    );
    expect(find.text('Đã chọn.'), findsOneWidget);
    await tester.tap(find.text('Bỏ chọn'));
    await tester.pump();
    expect(sent.last, '|null|true');
  });

  testWidgets('a locked action shows why and sends nothing', (tester) async {
    await pumpCard(
      tester,
      _action({
        'input': 'single_target',
        'enabled': false,
        'disabledReason': 'Bạn chưa chạy đủ km.',
        'selected': {
          'targets': ['u2'],
        },
      }),
    );

    expect(find.text('Bạn chưa chạy đủ km.'), findsOneWidget);
    expect(find.text('Bỏ chọn'), findsNothing);
    await tester.tap(find.text('An'));
    await tester.pump();
    expect(sent, isEmpty);
  });

  testWidgets('names who is picked, by the option labels', (tester) async {
    await pumpCard(
      tester,
      _action({
        'input': 'two_targets',
        'selected': {
          'targets': ['u3', 'u1'],
        },
      }),
    );
    expect(find.text('Đã chọn Chi, An'), findsOneWidget);
    expect(find.text('Bỏ chọn'), findsOneWidget);
  });

  testWidgets('an unknown input says the app is too old for it', (
    tester,
  ) async {
    await pumpCard(tester, _action({'input': 'map_pick'}));
    expect(find.text('Bản app này chưa làm được việc này.'), findsOneWidget);
  });

  testWidgets('counts down on server time', (tester) async {
    await pumpCard(
      tester,
      _action({'input': 'single_target', 'closesAt': '2026-10-17T15:05:00Z'}),
    );
    expect(find.text('Còn 1 giờ 5 phút'), findsOneWidget);

    now = DateTime.utc(2026, 10, 17, 15, 4, 30);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Còn 0 phút 30 giây'), findsOneWidget);

    now = DateTime.utc(2026, 10, 17, 15, 5);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Đang chốt…'), findsOneWidget);
  });

  testWidgets('shows when a closed window opens', (tester) async {
    await pumpCard(
      tester,
      _action({
        'input': 'single_target',
        'enabled': false,
        'opensAt': '2026-10-17T17:00:00Z',
        'closesAt': '2026-10-17T22:00:00Z',
      }),
    );
    expect(find.textContaining('Mở lúc '), findsOneWidget);
    expect(find.textContaining('Còn '), findsNothing);
  });
}
