import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/app.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/repository.dart';

void main() {
  testWidgets('renders dashboard in demo mode', (tester) async {
    final feedRepository = DemoFeedRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activityRepositoryProvider.overrideWithValue(
            DemoActivityRepository(),
          ),
          feedRepositoryProvider.overrideWithValue(feedRepository),
        ],
        child: const RunNowApp(requireAuthentication: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tổng quan'), findsNWidgets(2));
    expect(find.text('7 NGÀY GẦN NHẤT'), findsOneWidget);
    expect(find.text('Phân bổ km theo thời gian'), findsOneWidget);
    expect(find.text('QUÃNG ĐƯỜNG'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('CONSISTENCY'), 300);
    expect(find.text('CONSISTENCY'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('PHÂN BỔ 7 NGÀY'), 300);
    expect(find.text('PHÂN BỔ 7 NGÀY'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Gần đây'), 300);
    expect(find.text('Gần đây'), findsOneWidget);
    await tester.tap(find.text('Feed'));
    await tester.pumpAndSettle();
    expect(
      find.text('Chưa có bài đăng. Mở một hoạt động và chọn “Đăng lên feed”.'),
      findsOneWidget,
    );
    feedRepository.dispose();
  });
}
