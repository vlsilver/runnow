import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/screens/activity_detail_screen.dart';
import 'package:myrun/src/screens/club_screen.dart';
import 'package:myrun/src/screens/dashboard_screen.dart';
import 'package:myrun/src/screens/journal_screen.dart';
import 'package:myrun/src/screens/member_profile_screen.dart';
import 'package:myrun/src/screens/onboarding_screen.dart';
import 'package:myrun/src/screens/settings_screen.dart';
import 'package:myrun/src/screens/tracking_screen.dart';
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
              path: '/club',
              builder: (context, state) => const ClubScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/tracking',
              builder: (context, state) => const TrackingScreen(),
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
    GoRoute(
      path: '/tracking/session/:id',
      builder: (context, state) =>
          ActivityDetailScreen(activityId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/club/:uid/activity/:id',
      builder: (context, state) => ActivityDetailScreen(
        activityId: state.pathParameters['id']!,
        ownerUid: state.pathParameters['uid']!,
      ),
    ),
    GoRoute(
      path: '/club/:uid',
      builder: (context, state) =>
          MemberProfileScreen(uid: state.pathParameters['uid']!),
    ),
  ],
);

class RunNowApp extends ConsumerWidget {
  const RunNowApp({super.key, this.requireAuthentication = true});

  final bool requireAuthentication;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeControllerProvider).mode;
    return MaterialApp.router(
      title: 'RunNow',
      debugShowCheckedModeBanner: false,
      theme: buildRunNowLightTheme(),
      darkTheme: buildRunNowDarkTheme(),
      themeMode: themeMode,
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
          borderRadius: 22,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DashboardNavFilter(branchActive: shell.currentIndex == 0),
              ClubNavFilter(branchActive: shell.currentIndex == 2),
              Row(
                children: [
              Expanded(
                child: _NavItem(
                  selected: shell.currentIndex == 0,
                  icon: Icons.insights_outlined,
                  selectedIcon: Icons.insights,
                  label: 'Tổng quan',
                  onTap: () => shell.goBranch(0),
                ),
              ),
              Expanded(
                child: _NavItem(
                  selected: shell.currentIndex == 1,
                  icon: Icons.directions_run_outlined,
                  selectedIcon: Icons.directions_run,
                  label: 'Nhật ký',
                  onTap: () => shell.goBranch(1),
                ),
              ),
              Expanded(
                child: _RunNavItem(
                  selected: shell.currentIndex == 3,
                  onTap: () => shell.goBranch(3),
                ),
              ),
              Expanded(
                child: _NavItem(
                  selected: shell.currentIndex == 2,
                  icon: Icons.groups_2_outlined,
                  selectedIcon: Icons.groups_2,
                  label: 'Club',
                  onTap: () => shell.goBranch(2),
                ),
              ),
              Expanded(
                child: _NavItem(
                  selected: shell.currentIndex == 4,
                  icon: Icons.settings_outlined,
                  selectedIcon: Icons.settings,
                  label: 'Cài đặt',
                  onTap: () => shell.goBranch(4),
                ),
              ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.selected,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? selectedIcon : icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RunNavItem extends StatelessWidget {
  const _RunNavItem({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: selected
                    ? const [
                        Color(0xff19f58a),
                        AppColors.blueGlow,
                        AppColors.red,
                      ]
                    : const [
                        AppColors.red,
                        Color(0xffaa1228),
                        Color(0xff1a0711),
                      ],
              ),
              boxShadow: [
                BoxShadow(
                  color: (selected ? AppColors.blueGlow : AppColors.red)
                      .withValues(alpha: 0.45),
                  blurRadius: 26,
                  spreadRadius: 1,
                ),
              ],
              border: Border.all(
                color: Colors.white.withValues(alpha: selected ? 0.65 : 0.28),
              ),
            ),
            child: const Icon(
              Icons.directions_run_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Chạy',
            style: TextStyle(
              color: selected
                  ? AppColors.blueGlow
                  : Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.76),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
