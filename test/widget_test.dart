import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/app.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/repository.dart';

void main() {
  testWidgets('renders dashboard in demo mode', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activityRepositoryProvider.overrideWithValue(
            DemoActivityRepository(),
          ),
        ],
        child: const RunNowApp(requireAuthentication: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tổng quan'), findsNWidgets(2));
    expect(find.text('7 NGÀY GẦN NHẤT'), findsOneWidget);
    expect(find.text('Nhịp luyện tập từ dữ liệu đã đồng bộ'), findsNothing);
    expect(find.textContaining('Đồng bộ Strava hoàn tất'), findsNothing);
    expect(find.text('Quãng đường'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('CONSISTENCY'), 300);
    expect(find.text('CONSISTENCY'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Gần đây'), 300);
    expect(find.text('Gần đây'), findsOneWidget);
    expect(find.text('Feed'), findsNothing);
  });
}
