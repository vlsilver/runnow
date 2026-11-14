import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/games/game_night_theme.dart';
import 'package:myrun/src/theme.dart';

void main() {
  Future<RunNowMoonlit> tokensUnder(
    WidgetTester tester,
    RunNowStyle style,
  ) async {
    late RunNowMoonlit seen;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildRunNowTheme(
          RunNowElement.water,
          appearance: RunNowAppearance.light,
          style: style,
        ),
        home: GameThemed(
          moonlit: true,
          child: Builder(
            builder: (context) {
              seen = context.moonlit;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return seen;
  }

  testWidgets('kiểu Thép: bàn Ma Sói nền đen, nhấn đỏ, không phủ lọc màu', (
    tester,
  ) async {
    final m = await tokensUnder(tester, RunNowStyle.iron);

    expect(m.page, const Color(0xFF121212));
    expect(m.amber, const Color(0xFFE63B1F));
    // Lọc màu cả màn làm ảnh đại diện và thẻ vai mất màu gốc.
    expect(find.byType(ColorFiltered), findsNothing);
  });

  testWidgets('kiểu thường: bàn Ma Sói giữ tông ánh trăng', (tester) async {
    final m = await tokensUnder(tester, RunNowStyle.elemental);

    expect(m.page, const Color(0xFF020306));
    expect(m.amber, const Color(0xFFE5B04C));
  });
}
