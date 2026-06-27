import 'package:flutter/foundation.dart' show kIsWeb;
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
    GoRoute(
      path: '/oauth',
      builder: (context, state) => const DashboardScreen(),
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
      builder: (context, child) {
        final content = requireAuthentication
            ? _AuthGate(child: child!)
            : child!;
        // Nền phủ toàn màn; ràng buộc bề rộng do từng màn xử lý (shell có rail
        // riêng khi rộng, các màn nội dung tự gò cột giữa).
        return RunNowBackdrop(child: content);
      },
    );
  }
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(stravaAuthProvider);
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
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 760;
    if (wide) {
      final contentMaxWidth = width >= 1500
          ? 1360.0
          : width >= 1180
          ? 1180.0
          : 900.0;
      return Scaffold(
        body: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DesktopNavRail(shell: shell),
              Expanded(
                child: _DesktopContent(shell: shell, maxWidth: contentMaxWidth),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: shell,
        ),
      ),
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
                  if (!kIsWeb)
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

class _DesktopContent extends StatelessWidget {
  const _DesktopContent({required this.shell, required this.maxWidth});

  final StatefulNavigationShell shell;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          children: [
            const SizedBox(height: 14),
            _DesktopCommandBar(shell: shell),
            const SizedBox(height: 8),
            Expanded(child: shell),
          ],
        ),
      ),
    );
  }
}

class _DesktopCommandBar extends ConsumerWidget {
  const _DesktopCommandBar({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = switch (shell.currentIndex) {
      0 => const DashboardNavFilter(branchActive: true, showFallback: true),
      2 => const ClubNavFilter(branchActive: true),
      _ => null,
    };
    final title = switch (shell.currentIndex) {
      0 => 'Tổng quan',
      1 => 'Nhật ký',
      2 => 'Câu lạc bộ',
      3 => 'Chạy thử',
      4 => 'Cài đặt',
      _ => 'RunNow',
    };
    final subtitle = switch (shell.currentIndex) {
      0 => 'Training cockpit',
      1 => 'Activity log',
      2 => 'Club command center',
      3 => 'Tracking lab',
      4 => 'Preferences',
      _ => 'Your training space',
    };
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: GlassPanel(
        borderRadius: 26,
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
        gradient: LinearGradient(
          colors: Theme.of(context).brightness == Brightness.light
              ? const [Color(0xece8edf5), Color(0xded9e0ea)]
              : const [Color(0xd10a1c30), Color(0xa5081324)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: const LinearGradient(
                  colors: [AppColors.accent, AppColors.accentDeep],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.22),
                    blurRadius: 18,
                  ),
                ],
              ),
              child: const Icon(
                Icons.directions_run_rounded,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 14),
            SizedBox(
              width: 210,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onSurface,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.52),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeOutCubic,
                child:
                    filter ??
                    _DesktopStatusStrip(key: ValueKey(shell.currentIndex)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopStatusStrip extends StatelessWidget {
  const _DesktopStatusStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Icon(
          Icons.bolt_rounded,
          size: 18,
          color: AppColors.accent.withValues(alpha: 0.9),
        ),
        const SizedBox(width: 8),
        Text(
          'RUNNOW WEB',
          style: TextStyle(
            color: onSurface.withValues(alpha: 0.58),
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.6,
          ),
        ),
      ],
    );
  }
}

class _DesktopNavRail extends StatelessWidget {
  const _DesktopNavRail({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final extended = width >= 1100;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final branches = <int>[0, 1, if (!kIsWeb) 3, 2, 4];
    final destinations = <NavigationRailDestination>[
      const NavigationRailDestination(
        icon: Icon(Icons.insights_outlined),
        selectedIcon: Icon(Icons.insights),
        label: Text('Tổng quan'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.directions_run_outlined),
        selectedIcon: Icon(Icons.directions_run),
        label: Text('Nhật ký'),
      ),
      if (!kIsWeb)
        const NavigationRailDestination(
          icon: Icon(Icons.directions_run_rounded),
          selectedIcon: Icon(Icons.directions_run_rounded),
          label: Text('Chạy'),
        ),
      const NavigationRailDestination(
        icon: Icon(Icons.groups_2_outlined),
        selectedIcon: Icon(Icons.groups_2),
        label: Text('Club'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: Text('Cài đặt'),
      ),
    ];
    var selected = branches.indexOf(shell.currentIndex);
    if (selected < 0) selected = 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
      child: GlassPanel(
        borderRadius: 26,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.sizeOf(context).height - 40,
            ),
            child: IntrinsicHeight(
              child: NavigationRail(
                extended: extended,
                minExtendedWidth: 188,
                backgroundColor: Colors.transparent,
                labelType: NavigationRailLabelType.all,
                groupAlignment: -0.85,
                selectedIndex: selected,
                onDestinationSelected: (index) =>
                    shell.goBranch(branches[index]),
                indicatorColor: AppColors.accent.withValues(alpha: 0.18),
                leading: const Padding(
                  padding: EdgeInsets.only(top: 10, bottom: 16),
                  child: _RailBrand(),
                ),
                selectedIconTheme: const IconThemeData(color: AppColors.accent),
                unselectedIconTheme: IconThemeData(
                  color: onSurface.withValues(alpha: 0.7),
                ),
                selectedLabelTextStyle: const TextStyle(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
                unselectedLabelTextStyle: TextStyle(
                  color: onSurface.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                destinations: destinations,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RailBrand extends StatelessWidget {
  const _RailBrand();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [AppColors.accent, AppColors.accentDeep],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Icon(
            Icons.directions_run_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'RunNow',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w900,
            fontSize: 12,
            letterSpacing: 0.5,
          ),
        ),
      ],
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
                        AppColors.accent,
                        Color(0xff123f7e),
                        Color(0xff0a1622),
                      ],
              ),
              boxShadow: [
                BoxShadow(
                  color: (selected ? AppColors.blueGlow : AppColors.red)
                      .withValues(alpha: 0.26),
                  blurRadius: 16,
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
