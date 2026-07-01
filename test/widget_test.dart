import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/app.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/repository.dart';
import 'package:myrun/src/theme_controller.dart';

void main() {
  testWidgets('renders contract home in demo mode', (tester) async {
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
          myActiveContractsProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          clubRunContractsProvider.overrideWith(
            (ref) => Stream.value(const []),
          ),
          membersProvider.overrideWith((ref) => Stream.value(const [])),
          themeControllerProvider.overrideWith(
            (ref) => ThemeController(loadFromStorage: false),
          ),
        ],
        child: const RunNowApp(requireAuthentication: false),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Kèo'), findsNWidgets(2));
    expect(find.text('Tạo kèo'), findsOneWidget);
    expect(find.text('Chưa có kèo đang diễn ra'), findsOneWidget);
    expect(find.text('Tổng quan'), findsNothing);
  });
}
