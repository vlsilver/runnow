import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/journey/journey_models.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/screens/activity_detail_screen.dart';
import 'package:myrun/src/screens/club_screen.dart';
import 'package:myrun/src/screens/journal_screen.dart';
import 'package:myrun/src/screens/journey_hub_screen.dart';
import 'package:myrun/src/screens/journey_screen.dart';
import 'package:myrun/src/screens/member_profile_screen.dart';
import 'package:myrun/src/screens/onboarding_screen.dart';
import 'package:myrun/src/screens/run_contract_create_screen.dart';
import 'package:myrun/src/screens/run_contract_detail_screen.dart';
import 'package:myrun/src/screens/run_contract_home_screen.dart';
import 'package:myrun/src/screens/run_contract_route_create_screen.dart';
import 'package:myrun/src/screens/settings_screen.dart';
import 'package:myrun/src/screens/tracking_screen.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/web_layout.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/run_now_loading.dart';
import 'package:myrun/src/run_contracts/run_contract_models.dart';
import 'package:myrun/src/run_contracts/run_contract_progress.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final _router = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) =>
          _Scaffold(shell: shell, location: state.uri.path),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const RunContractHomeScreen(),
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
              path: '/profile',
              builder: (context, state) => const JourneyHubScreen(),
              routes: [
                GoRoute(
                  path: 'journey/:campaignId',
                  builder: (context, state) => JourneyScreen(
                    campaignId:
                        parseJourneyCampaignId(
                          state.pathParameters['campaignId'],
                        ) ??
                        JourneyCampaignId.xuyenViet,
                  ),
                ),
                GoRoute(
                  path: 'journal',
                  builder: (context, state) => const JournalScreen(),
                ),
                GoRoute(
                  path: 'stats',
                  redirect: (context, state) => '/profile/journal',
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/settings',
              builder: (context, state) => const SettingsScreen(),
              routes: [
                GoRoute(
                  path: 'profile',
                  redirect: (context, state) => '/profile',
                ),
              ],
            ),
          ],
        ),
      ],
    ),
    GoRoute(path: '/journal', redirect: (context, state) => '/profile/journal'),
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
    // Route riêng cho "LIVE NOW" từ màn chi tiết kèo — KHÔNG dùng path
    // '/tracking' (đó là tab bottom-nav thuộc StatefulShellBranch, chỉ vào
    // đúng qua `shell.goBranch()`; push thẳng path đó từ ngoài shell từng
    // gây màn đen do xung đột với IndexedStack của go_router). Route này
    // nằm ngoài shell nên push/pop bình thường, và nhận `contractId` qua
    // `extra` như cũ.
    GoRoute(
      path: '/tracking/live',
      builder: (context, state) =>
          TrackingScreen(contractId: state.extra as String?),
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
      path: '/club/:uid/journal',
      builder: (context, state) =>
          MemberJournalScreen(uid: state.pathParameters['uid']!),
    ),
    GoRoute(
      path: '/oauth',
      builder: (context, state) => const RunContractHomeScreen(),
    ),
    GoRoute(
      path: '/contracts/new',
      builder: (context, state) => RunContractCreateScreen(
        initialDraft: state.extra is RunContractDraft
            ? state.extra! as RunContractDraft
            : null,
      ),
    ),
    GoRoute(
      path: '/contracts/new/route',
      builder: (context, state) => const RunContractRouteCreateScreen(),
    ),
    GoRoute(
      path: '/contracts/:id',
      builder: (context, state) =>
          RunContractDetailScreen(contractId: state.pathParameters['id']!),
    ),
  ],
);

class RunNowApp extends ConsumerWidget {
  const RunNowApp({super.key, this.requireAuthentication = true});

  final bool requireAuthentication;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeController = ref.watch(themeControllerProvider);
    final selectedTheme = buildRunNowTheme(
      themeController.element,
      appearance: themeController.appearance,
      darkTone: themeController.darkTone,
    );
    return MaterialApp.router(
      title: '3i',
      debugShowCheckedModeBanner: false,
      theme: selectedTheme,
      darkTheme: selectedTheme,
      themeMode: themeController.appearance == RunNowAppearance.light
          ? ThemeMode.light
          : ThemeMode.dark,
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
          data: (user) => user == null
              ? const OnboardingScreen()
              : _AuthenticatedSession(child: child),
          error: (error, stack) =>
              Center(child: Text('Không thể kiểm tra đăng nhập: $error')),
          loading: () => const RunNowLoading(label: 'Đang vào 3i'),
        );
  }
}

class _AuthenticatedSession extends ConsumerStatefulWidget {
  const _AuthenticatedSession({required this.child});
  final Widget child;

  @override
  ConsumerState<_AuthenticatedSession> createState() =>
      _AuthenticatedSessionState();
}

class _AuthenticatedSessionState extends ConsumerState<_AuthenticatedSession> {
  bool _started = false;

  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(stravaConnectionProvider);
    if (connected && !_started) {
      _started = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        final uid = ref.read(firebaseUserProvider).value?.uid;
        final controller = ref.read(runContractControllerProvider);
        final mine =
            [
                ...ref.read(myActiveContractsProvider).value ??
                    const <RunContract>[],
              ]
              ..removeWhere((contract) => contract.completedBy(uid))
              ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        for (final contract in mine) {
          if (contract.creatorUid == uid) {
            if (contractLifecycle(contract, DateTime.now()) ==
                RunContractLifecycle.awaitingFinalize) {
              // Tự chốt kèo quá hạn ngay khi owner mở app, thay vì bắt họ
              // vào tận màn chi tiết kèo rồi bấm "Chốt kết quả" — lỗi (vd
              // Strava sync tạm thời fail) bỏ qua an toàn, kèo vẫn ở
              // awaitingFinalize và sẽ được thử lại ở lần mở app kế tiếp.
              try {
                await controller.finalize(contract);
              } catch (_) {
                // ignore, retried next app open
              }
            } else {
              try {
                await controller.recalculate(contract);
              } catch (_) {
                // ignore (vd Firestore tạm gián đoạn) — thử lại lần mở app
                // kế tiếp; không để 1 kèo lỗi chặn tính lại các kèo còn lại.
              }
            }
          } else {
            try {
              await controller.recalculateParticipant(contract);
            } catch (_) {
              // ignore, cùng lý do — xem comment ở nhánh recalculate() trên.
            }
          }
        }
      });
    }
    return widget.child;
  }
}

class _SyncedActivitiesSheet extends StatefulWidget {
  const _SyncedActivitiesSheet({required this.activities});

  final List<ActivitySummary> activities;

  @override
  State<_SyncedActivitiesSheet> createState() => _SyncedActivitiesSheetState();
}

class _SyncedActivitiesSheetState extends State<_SyncedActivitiesSheet> {
  static const _collapsedLimit = 4;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final now = DateTime.now();
    final sorted = [...widget.activities]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final visible = _expanded || sorted.length <= _collapsedLimit
        ? sorted
        : sorted.take(_collapsedLimit).toList();
    final remaining = sorted.length - visible.length;

    return Padding(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: GlassPanel(
        borderRadius: 22,
        padding: const EdgeInsets.fromLTRB(18, 10, 14, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SyncHeaderIcon(color: palette.accent),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RichText(
                        text: TextSpan(
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: onSurface,
                              ),
                          children: [
                            const TextSpan(text: 'Đã đồng bộ '),
                            TextSpan(
                              text: '${sorted.length}',
                              style: TextStyle(color: palette.accent),
                            ),
                            const TextSpan(text: ' hoạt động'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        sorted.length > 5
                            ? 'Lâu ngày quay lại · từ Strava'
                            : 'Vừa xong · từ Strava',
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  style: IconButton.styleFrom(
                    backgroundColor: onSurface.withValues(alpha: 0.08),
                    foregroundColor: onSurface,
                    shape: const CircleBorder(),
                    minimumSize: const Size(36, 36),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.5,
              ),
              child: SingleChildScrollView(
                child: _groupedActivityList(context, visible, now, palette),
              ),
            ),
            if (remaining > 0) ...[
              const SizedBox(height: 2),
              Center(
                child: TextButton(
                  onPressed: () => setState(() => _expanded = true),
                  child: Text('Xem thêm $remaining hoạt động'),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      context.push('/profile/journal');
                    },
                    child: const Text('Xem Nhật ký'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Đóng'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _groupedActivityList(
    BuildContext context,
    List<ActivitySummary> items,
    DateTime now,
    RunNowPalette palette,
  ) {
    final children = <Widget>[];
    String? lastLabel;
    for (var i = 0; i < items.length; i++) {
      final activity = items[i];
      final label = _dateGroupLabel(activity.startedAt, now);
      if (label != lastLabel) {
        if (lastLabel != null) children.add(const SizedBox(height: 14));
        children.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                color: palette.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
        );
        lastLabel = label;
      } else {
        children.add(const Divider(height: 16));
      }
      children.add(_SyncedActivityRow(activity: activity, palette: palette));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

String _dateGroupLabel(DateTime date, DateTime now) {
  final day = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  if (day == today) return 'Hôm nay';
  if (day == yesterday) return 'Hôm qua';
  const weekdayNames = [
    'Thứ Hai',
    'Thứ Ba',
    'Thứ Tư',
    'Thứ Năm',
    'Thứ Sáu',
    'Thứ Bảy',
    'Chủ Nhật',
  ];
  final weekday = weekdayNames[date.weekday - 1];
  final dd = date.day.toString().padLeft(2, '0');
  final mm = date.month.toString().padLeft(2, '0');
  return '$weekday, $dd/$mm';
}

class _SyncHeaderIcon extends StatelessWidget {
  const _SyncHeaderIcon({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.sync_rounded, color: Colors.white, size: 22),
    );
  }
}

class _SyncedActivityRow extends StatelessWidget {
  const _SyncedActivityRow({required this.activity, required this.palette});

  final ActivitySummary activity;
  final RunNowPalette palette;

  @override
  Widget build(BuildContext context) {
    final isStrava = activity.source == ActivitySource.strava;
    final sourceColor = isStrava ? RunNowBrandColors.strava : palette.accent;
    final sourceLabel = isStrava ? 'Strava' : 'Tự track';
    final time = TimeOfDay.fromDateTime(activity.startedAt).format(context);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () {
        Navigator.of(context).pop();
        context.push('/activity/${activity.id}');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                _iconForKind(activity.kind),
                size: 19,
                color: palette.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: sourceColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        '$sourceLabel · $time',
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    activity.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: onSurface,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatDistance(activity.distanceMeters),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: onSurface,
                  ),
                ),
                if (activity.paceSecondsPerKm != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    formatPace(activity.paceSecondsPerKm),
                    style: TextStyle(color: palette.textMuted, fontSize: 12),
                  ),
                ],
              ],
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.chevron_right_rounded,
              color: palette.textMuted,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForKind(ActivityKind kind) => switch (kind) {
    ActivityKind.run => Icons.directions_run_rounded,
    ActivityKind.trailRun => Icons.trending_up_rounded,
    ActivityKind.virtualRun => Icons.directions_run_rounded,
    ActivityKind.walk => Icons.directions_walk_rounded,
    ActivityKind.hike => Icons.terrain_rounded,
  };
}

class _Scaffold extends StatelessWidget {
  const _Scaffold({required this.shell, required this.location});
  final StatefulNavigationShell shell;
  final String location;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = kIsWeb ? RunNowWebLayout.isDesktop(context) : width >= 760;
    if (wide) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DesktopNavRail(shell: shell),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: RunNowWebLayout.maxContentWidth,
                    ),
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        width >= RunNowWebLayout.wideBreakpoint ? 32 : 20,
                        8,
                        width >= RunNowWebLayout.wideBreakpoint ? 32 : 20,
                        0,
                      ),
                      child: shell,
                    ),
                  ),
                ),
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
              ClubNavFilter(branchActive: shell.currentIndex == 1),
              Row(
                children: [
                  Expanded(
                    child: _NavItem(
                      selected: shell.currentIndex == 0,
                      icon: Icons.flag_outlined,
                      selectedIcon: Icons.flag_rounded,
                      label: 'Kèo',
                      onTap: () => shell.goBranch(0),
                    ),
                  ),
                  Expanded(
                    child: _NavItem(
                      selected: shell.currentIndex == 1,
                      icon: Icons.groups_2_outlined,
                      selectedIcon: Icons.groups_2,
                      label: 'Club',
                      onTap: () => shell.goBranch(1),
                    ),
                  ),
                  if (!kIsWeb)
                    Expanded(
                      child: _RunNavItem(
                        selected: shell.currentIndex == 2,
                        onTap: () => shell.goBranch(2),
                      ),
                    ),
                  Expanded(
                    child: _NavItem(
                      selected: shell.currentIndex == 3,
                      icon: Icons.map_outlined,
                      selectedIcon: Icons.map_rounded,
                      label: 'Hành Trình',
                      onTap: () => shell.goBranch(3),
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

class _DesktopNavRail extends StatelessWidget {
  const _DesktopNavRail({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final extended = width >= 1240;
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;
    final branches = <int>[0, 1, if (!kIsWeb) 2, 3, 4];
    final destinations = <NavigationRailDestination>[
      const NavigationRailDestination(
        icon: Icon(Icons.flag_outlined),
        selectedIcon: Icon(Icons.flag_rounded),
        label: Text('Kèo'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.groups_2_outlined),
        selectedIcon: Icon(Icons.groups_2),
        label: Text('Club'),
      ),
      if (!kIsWeb)
        const NavigationRailDestination(
          icon: Icon(Icons.directions_run_rounded),
          selectedIcon: Icon(Icons.directions_run_rounded),
          label: Text('Chạy'),
        ),
      const NavigationRailDestination(
        icon: Icon(Icons.map_outlined),
        selectedIcon: Icon(Icons.map_rounded),
        label: Text('Hành Trình'),
      ),
      const NavigationRailDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: Text('Cài đặt'),
      ),
    ];
    var selected = branches.indexOf(shell.currentIndex);
    if (selected < 0) selected = 0;
    final palette = context.runNowPalette;
    return Container(
      width: extended ? 216 : 84,
      decoration: BoxDecoration(
        color: palette.glassStart,
        border: Border(right: BorderSide(color: palette.border)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: MediaQuery.sizeOf(context).height - 16,
          ),
          child: NavigationRail(
            extended: extended,
            minWidth: 76,
            minExtendedWidth: 216,
            backgroundColor: Colors.transparent,
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            groupAlignment: -0.85,
            selectedIndex: selected,
            onDestinationSelected: (index) => shell.goBranch(branches[index]),
            indicatorColor: scheme.primary.withValues(alpha: 0.16),
            leading: const Padding(
              padding: EdgeInsets.only(top: 10, bottom: 20),
              child: _RailBrand(),
            ),
            selectedIconTheme: IconThemeData(color: scheme.primary),
            unselectedIconTheme: IconThemeData(
              color: onSurface.withValues(alpha: 0.62),
            ),
            selectedLabelTextStyle: TextStyle(
              color: scheme.primary,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
            unselectedLabelTextStyle: TextStyle(
              color: onSurface.withValues(alpha: 0.62),
              fontWeight: FontWeight.w700,
            ),
            destinations: destinations,
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
    final palette = context.runNowPalette;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [palette.accent, palette.accentDeep],
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
          '3i',
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
    final palette = context.runNowPalette;
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
                    ? [palette.tertiary, palette.secondary, palette.accent]
                    : [
                        palette.accent,
                        palette.accentDeep,
                        palette.backgroundDeep,
                      ],
              ),
              boxShadow: [
                BoxShadow(
                  color: (selected ? palette.secondary : palette.accent)
                      .withValues(alpha: 0.26),
                  blurRadius: 16,
                ),
              ],
              border: Border.all(
                color: palette.glassStart.withValues(
                  alpha: selected ? 0.65 : 0.28,
                ),
              ),
            ),
            child: Icon(
              Icons.directions_run_rounded,
              color: palette.glassStart,
              size: 30,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Chạy',
            style: TextStyle(
              color: selected
                  ? palette.secondary
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
