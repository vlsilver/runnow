import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/app.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/repository.dart';
import 'package:myrun/src/theme_controller.dart';

void main() {
  testWidgets('renders dashboard in demo mode', (tester) async {
    // Ép kích thước điện thoại để dùng bottom nav (layout web rộng có rail
    // riêng làm thay đổi cây widget/scroll).
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activityRepositoryProvider.overrideWithValue(
            DemoActivityRepository(),
          ),
          trainingGoalRepositoryProvider.overrideWithValue(
            DemoTrainingGoalRepository(
              const TrainingGoals(
                weeklyDistanceMeters: 10000,
                monthlyDistanceMeters: 40000,
              ),
            ),
          ),
          userProfileProvider.overrideWith(
            (ref) => Stream.value(UserProfile.demo),
          ),
          stravaConnectionProvider.overrideWithValue(true),
          themeControllerProvider.overrideWith(
            (ref) => ThemeController(loadFromStorage: false),
          ),
        ],
        child: const RunNowApp(requireAuthentication: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Tổng quan'), findsNWidgets(2));
    expect(find.text('Nhịp luyện tập từ dữ liệu đã đồng bộ'), findsNothing);
    expect(find.textContaining('Đồng bộ Strava hoàn tất'), findsNothing);
    final dashboardScroll = find.byType(Scrollable).first;
    expect(find.text('TIẾN ĐỘ TUẦN'), findsOneWidget);
    // Filter Tuần/7 ngày của card "tiến độ tuần" giờ nằm trong navigation bar.
    expect(find.text('7 ngày'), findsWidgets);
    expect(find.text('Tuần này'), findsWidgets);
    expect(find.text('Quãng đường'), findsOneWidget);
    // Default tổng quan giờ là "Tuần này" nên nhãn mục tiêu hiển thị theo tuần
    // hiện tại thay vì "Mục tiêu tuần" (chế độ 7 ngày gần nhất).
    expect(find.text('Mục tiêu tuần'), findsNothing);
    expect(find.text('MỤC TIÊU'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('KỶ LUẬT & CONSISTENCY'),
      300,
      scrollable: dashboardScroll,
    );
    expect(find.text('KỶ LUẬT & CONSISTENCY'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('CONSISTENCY'),
      300,
      scrollable: dashboardScroll,
    );
    expect(find.text('CONSISTENCY'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('GẦN ĐÂY'),
      300,
      scrollable: dashboardScroll,
    );
    expect(find.text('GẦN ĐÂY'), findsOneWidget);
    expect(find.text('Feed'), findsNothing);
  });
}
