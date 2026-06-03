import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/screens/activity_detail_screen.dart';
import 'package:myrun/src/screens/dashboard_screen.dart';
import 'package:myrun/src/screens/feed_screen.dart';
import 'package:myrun/src/screens/journal_screen.dart';
import 'package:myrun/src/screens/onboarding_screen.dart';
import 'package:myrun/src/screens/settings_screen.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';

final _router = GoRouter(
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => _Scaffold(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const DashboardScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/journal',
              builder: (context, state) => const JournalScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/feed',
              builder: (context, state) => const FeedScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/activity/:id',
      builder: (context, state) =>
          ActivityDetailScreen(activityId: state.pathParameters['id']!),
    ),
  ],
);

class RunNowApp extends StatelessWidget {
  const RunNowApp({super.key, this.requireAuthentication = true});

  final bool requireAuthentication;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'RunNow',
      debugShowCheckedModeBanner: false,
      theme: buildRunNowTheme(),
      routerConfig: _router,
      builder: (context, child) => RunNowBackdrop(
        child: requireAuthentication ? _AuthGate(child: child!) : child!,
      ),
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(firebaseUserProvider)
        .when(
          data: (user) => user == null ? const OnboardingScreen() : child,
          error: (error, stack) =>
              Center(child: Text('Không thể kiểm tra đăng nhập: $error')),
          loading: () => const Center(child: CircularProgressIndicator()),
        );
  }
}

class _Scaffold extends StatelessWidget {
  const _Scaffold({required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: GlassPanel(
          borderRadius: 16,
          child: NavigationBar(
            height: 70,
            backgroundColor: Colors.transparent,
            indicatorColor: AppColors.red.withValues(alpha: 0.85),
            selectedIndex: shell.currentIndex,
            onDestinationSelected: shell.goBranch,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights),
                label: 'Tổng quan',
              ),
              NavigationDestination(
                icon: Icon(Icons.directions_run_outlined),
                selectedIcon: Icon(Icons.directions_run),
                label: 'Nhật ký',
              ),
              NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: 'Feed',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Cài đặt',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
