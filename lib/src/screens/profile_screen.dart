import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:myrun/src/journey/journey_timeline.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/profile_stats.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/activity_tile.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/run_now_loading.dart';

/// Tab Hồ sơ: đều đặn và tiến bộ của riêng buổi chạy, theo Ngày/Tuần/Tháng/
/// Năm. Cài đặt nằm dưới `/me/settings`.
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  ProfilePeriod _period = ProfilePeriod.week;
  ProfileMetric _metric = ProfileMetric.distance;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(userProfileProvider).value;
    final element = ref.watch(themeControllerProvider).element;
    final statsState = ref.watch(profileStatsProvider);
    final stats = statsState.value;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: RefreshIndicator(
              onRefresh: () {
                unawaited(ref.read(journalControllerProvider).ensureLoaded());
                return ref.refresh(profileStatsProvider.future);
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
                children: [
                  _Header(onSettings: () => context.push('/me/settings')),
                  const SizedBox(height: 12),
                  const _DailyQuoteCard(),
                  const SizedBox(height: 14),
                  _Identity(
                    profile: profile,
                    subtitle: _identitySubtitle(element, stats),
                  ),
                  const SizedBox(height: 16),
                  if (stats == null && statsState.hasError)
                    _LoadError(
                      error: statsState.error!,
                      onRetry: () => ref.invalidate(profileStatsProvider),
                    )
                  else if (stats == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: RunNowLoading(),
                    )
                  else if (stats.isEmpty)
                    ..._empty(stats)
                  else
                    ..._content(stats),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _identitySubtitle(RunNowElement element, ProfileStatsData? stats) {
    final first = stats?.firstMonthKey;
    if (stats == null) return 'Hành ${element.label}';
    if (first == null) return 'Hành ${element.label} · mới vào 3i';
    return 'Hành ${element.label} · chạy cùng 3i từ '
        '${profileMonthLabel(first)}';
  }

  List<Widget> _content(ProfileStatsData stats) {
    final lifetime = stats.lifetime;
    return [
      Row(
        children: [
          Expanded(
            child: _StatTile(
              label: 'Tổng km',
              value: profileInt(lifetime.distanceMeters / 1000),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatTile(
              label: 'Giờ chạy',
              value: profileInt(lifetime.movingTimeSeconds ~/ 3600),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _StatTile(
              label: 'Ngày chạy',
              value: profileInt(lifetime.activeDays),
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      _PeriodTabs(
        value: _period,
        onChanged: (p) => setState(() => _period = p),
      ),
      const SizedBox(height: 14),
      _ConsistencyCard(view: stats.consistency(_period)),
      const SizedBox(height: 12),
      _ProgressCard(
        view: stats.progress(_period),
        metric: _metric,
        onMetric: (m) => setState(() => _metric = m),
      ),
      const SizedBox(height: 20),
      const _JournalSection(),
      const SizedBox(height: 20),
      const _JourneySection(),
    ];
  }

  List<Widget> _empty(ProfileStatsData stats) {
    final palette = context.runNowPalette;
    final week = stats
        .consistency(ProfilePeriod.day)
        .cells
        .skip(7 * (consistencyGridWeeks - 1))
        .toList();
    return [
      _Card(
        children: [
          const _Caption('Đều đặn'),
          const SizedBox(height: 8),
          _Headline('Chưa có buổi chạy nào', size: 22),
          const SizedBox(height: 4),
          _Muted(
            'Mỗi ngày bạn chạy sẽ sáng một ô. Chạy buổi đầu để bắt đầu chuỗi.',
          ),
          const SizedBox(height: 14),
          _DayGrid(cells: week),
        ],
      ),
      const SizedBox(height: 12),
      _Card(
        children: [
          const _Caption('Tiến bộ'),
          const SizedBox(height: 12),
          Text(
            'Kết nối nơi bạn ghi buổi chạy, 3i lấy lịch sử cũ để vẽ quãng '
            'đường, thời gian và pace của bạn.',
            style: TextStyle(
              fontSize: 15,
              height: 1.45,
              color: palette.foreground.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => context.push('/me/settings'),
            child: const Text('Kết nối Strava hoặc Apple Health'),
          ),
          if (!kIsWeb) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () =>
                  StatefulNavigationShell.maybeOf(context)?.goBranch(2),
              child: const Text('Chạy với 3i ngay'),
            ),
          ],
        ],
      ),
      const SizedBox(height: 20),
      const _JourneySection(),
    ];
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Row(
      children: [
        Expanded(
          child: Text(
            'Hồ sơ',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: palette.foreground,
            ),
          ),
        ),
        IconButton.outlined(
          tooltip: 'Cài đặt',
          onPressed: onSettings,
          style: IconButton.styleFrom(
            minimumSize: const Size(44, 44),
            side: BorderSide(color: palette.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.settings_outlined, size: 20),
        ),
      ],
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({required this.profile, required this.subtitle});

  final UserProfile? profile;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final name = profile?.displayName ?? '';
    final avatarUrl = profile?.avatarUrl;
    return Row(
      children: [
        CircleAvatar(
          radius: 32,
          backgroundColor: palette.accent.withValues(alpha: 0.22),
          backgroundImage: avatarUrl == null
              ? null
              : cachedAvatarImage(context, avatarUrl, 64),
          child: avatarUrl != null
              ? null
              : Text(
                  name.isEmpty ? '' : name.characters.first.toUpperCase(),
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: palette.accent,
                  ),
                ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                  color: palette.foreground,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(fontSize: 13, color: palette.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _Card(
    children: [
      const _Headline('Không tải được số liệu chạy', size: 18),
      const SizedBox(height: 4),
      _Muted('$error'),
      const SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(onPressed: onRetry, child: const Text('Thử lại')),
      ),
    ],
  );
}

class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => GlassPanel(
    borderRadius: 20,
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.5,
      color: context.runNowPalette.textMuted,
    ),
  );
}

class _Headline extends StatelessWidget {
  const _Headline(this.text, {this.size = 24});

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w900,
      color: context.runNowPalette.foreground,
    ),
  );
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(fontSize: 13, color: context.runNowPalette.textMuted),
  );
}

class _CardTitle extends StatelessWidget {
  const _CardTitle(this.title, this.range);

  final String title;
  final String range;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: _Caption(title)),
      Text(
        range,
        style: TextStyle(fontSize: 12, color: context.runNowPalette.textMuted),
      ),
    ],
  );
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => GlassPanel(
    borderRadius: 16,
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Caption(label),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: _Headline(value, size: 22),
        ),
      ],
    ),
  );
}

class _PeriodTabs extends StatelessWidget {
  const _PeriodTabs({required this.value, required this.onChanged});

  final ProfilePeriod value;
  final ValueChanged<ProfilePeriod> onChanged;

  static const _labels = {
    ProfilePeriod.day: 'Ngày',
    ProfilePeriod.week: 'Tuần',
    ProfilePeriod.month: 'Tháng',
    ProfilePeriod.year: 'Năm',
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return GlassPanel(
      borderRadius: 14,
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          for (final p in ProfilePeriod.values)
            Expanded(
              child: Semantics(
                selected: p == value,
                button: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(p),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: p == value ? palette.accent : null,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _labels[p]!,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: p == value
                            ? palette.background
                            : palette.foreground.withValues(alpha: 0.78),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ConsistencyCard extends StatelessWidget {
  const _ConsistencyCard({required this.view});

  final ConsistencyView view;

  @override
  Widget build(BuildContext context) => _Card(
    children: [
      _CardTitle('Đều đặn', view.range),
      const SizedBox(height: 8),
      _Headline(view.headline),
      const SizedBox(height: 2),
      _Muted(view.sub),
      const SizedBox(height: 14),
      if (view.cells.isNotEmpty) ...[
        _DayGrid(cells: view.cells),
        const SizedBox(height: 10),
        const _GridLegend(),
      ] else
        _GoalBars(view: view),
    ],
  );
}

/// Màu ô theo quãng đường của ngày, cùng ngưỡng với canvas: nghỉ, dưới 6 km,
/// dưới 10 km, từ 10 km.
Color _cellColor(RunNowPalette palette, double meters) {
  if (meters <= 0) return palette.foreground.withValues(alpha: 0.07);
  if (meters < 6000) return palette.accent.withValues(alpha: 0.3);
  if (meters < 10000) return palette.accent.withValues(alpha: 0.6);
  return palette.accent;
}

class _DayGrid extends StatelessWidget {
  const _DayGrid({required this.cells});

  final List<ConsistencyCell> cells;

  static const _weekdays = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final rows = <List<ConsistencyCell>>[
      for (var i = 0; i < cells.length; i += 7) cells.sublist(i, i + 7),
    ];
    return Column(
      children: [
        Row(
          children: [
            for (final w in _weekdays)
              Expanded(
                child: Text(
                  w,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: palette.textMuted,
                  ),
                ),
              ),
          ],
        ),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Row(
              children: [
                for (final c in row)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.5),
                      child: Tooltip(
                        message:
                            '${c.date.day}/${c.date.month}: '
                            '${c.distanceMeters > 0 ? '${profileDecimal(c.distanceMeters / 1000)} km' : 'nghỉ'}',
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: c.future
                                  ? palette.foreground.withValues(alpha: 0.03)
                                  : _cellColor(palette, c.distanceMeters),
                              borderRadius: BorderRadius.circular(7),
                              border: c.today
                                  ? Border.all(
                                      color: palette.foreground,
                                      width: 2,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _GridLegend extends StatelessWidget {
  const _GridLegend();

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final style = TextStyle(fontSize: 11, color: palette.textMuted);
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('Nghỉ', style: style),
        for (final m in const [0.0, 3000.0, 8000.0, 12000.0])
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(left: 5),
            decoration: BoxDecoration(
              color: _cellColor(palette, m),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        const SizedBox(width: 5),
        Text('Dài', style: style),
      ],
    );
  }
}

/// Nhãn trục: thưa một nửa khi nhiều cột, luôn giữ nhãn cột cuối.
List<String> _axisLabels(List<String> labels) => [
  for (final (i, l) in labels.indexed)
    labels.length <= 6 || i.isEven || i == labels.length - 1 ? l : '',
];

class _AxisLabels extends StatelessWidget {
  const _AxisLabels(this.labels);

  final List<String> labels;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (final l in _axisLabels(labels))
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.5),
            child: Text(
              l,
              textAlign: TextAlign.center,
              maxLines: 1,
              style: TextStyle(
                fontSize: 10,
                color: context.runNowPalette.textMuted,
              ),
            ),
          ),
        ),
    ],
  );
}

class _GoalBars extends StatelessWidget {
  const _GoalBars({required this.view});

  final ConsistencyView view;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final maxCap = view.bars.map((b) => b.capDays).reduce(math.max);
    final goalFraction = (view.goalDays / maxCap).clamp(0.0, 1.0);
    return Column(
      children: [
        SizedBox(
          height: 118,
          child: LayoutBuilder(
            builder: (context, box) {
              final goalTop = box.maxHeight * (1 - goalFraction);
              return Stack(
                children: [
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: palette.border),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final b in view.bars)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2.5,
                              ),
                              child: Tooltip(
                                message: '${b.activeDays}/${b.capDays} ngày',
                                child: Container(
                                  height: math.max(
                                    3,
                                    box.maxHeight * b.activeDays / maxCap,
                                  ),
                                  decoration: BoxDecoration(
                                    color: b.current
                                        ? palette.accent
                                        : palette.accent.withValues(
                                            // Đạt mục tiêu (quy theo số ngày
                                            // của kỳ) thì đậm hơn.
                                            alpha:
                                                b.activeDays >=
                                                    view.goalDays *
                                                        b.capDays /
                                                        maxCap
                                                ? 0.6
                                                : 0.28,
                                          ),
                                    borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(5),
                                      bottom: Radius.circular(2),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: goalTop,
                    child: CustomPaint(
                      painter: _DashPainter(palette.textMuted),
                      size: const Size.fromHeight(1),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: math.max(0, goalTop - 14),
                    child: Text(
                      view.goalLabel,
                      style: TextStyle(fontSize: 10, color: palette.textMuted),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        _AxisLabels([for (final b in view.bars) b.label]),
      ],
    );
  }
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 7) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(math.min(x + 4, size.width), 0),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color;
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.view,
    required this.metric,
    required this.onMetric,
  });

  final ProgressView view;
  final ProfileMetric metric;
  final ValueChanged<ProfileMetric> onMetric;

  static const _labels = {
    ProfileMetric.distance: 'Quãng đường',
    ProfileMetric.time: 'Thời gian',
    ProfileMetric.pace: 'Pace',
  };

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final delta = metricDelta(view.current, view.previous, metric);
    final values = [for (final p in view.points) metricValue(p.stats, metric)];
    return _Card(
      children: [
        _CardTitle('Tiến bộ', view.range),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in ProfileMetric.values)
              Semantics(
                button: true,
                selected: m == metric,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onMetric(m),
                  child: Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: m == metric
                          ? palette.accent.withValues(alpha: 0.2)
                          : null,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: m == metric ? palette.accent : palette.border,
                      ),
                    ),
                    child: Center(
                      widthFactor: 1,
                      child: Text(
                        _labels[m]!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: palette.foreground.withValues(
                            alpha: m == metric ? 1 : 0.78,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 10,
          children: [
            _Headline(formatMetric(view.current, metric), size: 30),
            if (delta != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  delta.text,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: delta.better
                        ? RunNowSemanticColors.success
                        : RunNowSemanticColors.warning,
                  ),
                ),
              ),
          ],
        ),
        Text(
          metric == ProfileMetric.pace
              ? '${view.caption}. Pace trung bình chỉ tính chạy.'
              : view.caption,
          style: TextStyle(fontSize: 12, color: palette.textMuted),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 130,
          child: metric == ProfileMetric.pace
              ? _PaceLine(values: values)
              : _ValueBars(
                  values: [for (final v in values) v ?? 0],
                  current: [for (final p in view.points) p.current],
                  tips: [
                    for (final p in view.points)
                      '${p.label}: ${formatMetric(p.stats, metric)}',
                  ],
                ),
        ),
        const SizedBox(height: 6),
        _AxisLabels([for (final p in view.points) p.label]),
      ],
    );
  }
}

class _ValueBars extends StatelessWidget {
  const _ValueBars({
    required this.values,
    required this.current,
    required this.tips,
  });

  final List<double> values;
  final List<bool> current;
  final List<String> tips;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final top = values.fold<double>(0, math.max);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: LayoutBuilder(
        builder: (context, box) => Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final (i, v) in values.indexed)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.5),
                  child: Tooltip(
                    message: tips[i],
                    child: Container(
                      height: top <= 0 || v <= 0
                          ? 0
                          : math.max(3, box.maxHeight * v / top),
                      decoration: BoxDecoration(
                        color: current[i]
                            ? palette.accent
                            : palette.accent.withValues(alpha: 0.38),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(5),
                          bottom: Radius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pace theo kỳ, càng cao càng nhanh. Kỳ không chạy thì bỏ điểm, đường nối
/// qua.
class _PaceLine extends StatelessWidget {
  const _PaceLine({required this.values});

  final List<double?> values;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: _PacePainter(
              values: values,
              line: palette.accent,
              axis: palette.border,
              background: palette.background,
            ),
          ),
        ),
        Row(
          children: [
            Text(
              'nhanh hơn',
              style: TextStyle(fontSize: 10, color: palette.textMuted),
            ),
            Icon(Icons.arrow_upward, size: 11, color: palette.textMuted),
          ],
        ),
      ],
    );
  }
}

class _PacePainter extends CustomPainter {
  _PacePainter({
    required this.values,
    required this.line,
    required this.axis,
    required this.background,
  });

  final List<double?> values;
  final Color line;
  final Color axis;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()..color = axis,
    );
    final known = [for (final v in values) ?v];
    if (known.isEmpty) return;
    final fastest = known.reduce(math.min);
    final slowest = known.reduce(math.max);
    final span = math.max(slowest - fastest, 1);
    // Cột chia đều như biểu đồ cột, điểm nằm giữa mỗi cột. Chừa 18px trên
    // cho nhãn, 10px dưới cho chấm cuối.
    final step = size.width / values.length;
    final points = <Offset>[
      for (final (i, v) in values.indexed)
        if (v != null)
          Offset(
            step * (i + 0.5),
            18 + (size.height - 28) * (v - fastest) / span,
          ),
    ];
    final paint = Paint()
      ..color = line
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(Path()..addPolygon(points, false), paint);
    if (values.last != null) {
      canvas.drawCircle(points.last, 6, Paint()..color = background);
      canvas.drawCircle(points.last, 4.5, Paint()..color = line);
    }
  }

  @override
  bool shouldRepaint(_PacePainter old) =>
      !listEquals(old.values, values) ||
      old.line != line ||
      old.axis != axis ||
      old.background != background;
}

/// Số buổi gần nhất hiện trong Hồ sơ; xem hết thì mở trang Nhật ký.
const profileRecentActivityCount = 5;

/// Vài buổi chạy gần nhất, ngay trong Hồ sơ. Dùng chung cache với trang Nhật
/// ký, nên mở trang đầy đủ thì có ngay, không phải tải lại.
class _JournalSection extends ConsumerStatefulWidget {
  const _JournalSection();

  @override
  ConsumerState<_JournalSection> createState() => _JournalSectionState();
}

class _JournalSectionState extends ConsumerState<_JournalSection> {
  @override
  void initState() {
    super.initState();
    // Controller báo đổi state ngay khi tải, không được chạy trong lúc build.
    Future.microtask(() => ref.read(journalControllerProvider).ensureLoaded());
  }

  @override
  Widget build(BuildContext context) {
    final journal = ref.watch(journalControllerProvider);
    final recent = journal.items.take(profileRecentActivityCount);
    final Widget body;
    if (recent.isNotEmpty) {
      body = Column(
        children: [
          for (final entry in recent)
            ActivityTile(
              activity: entry.activity,
              preferredStravaActivityId: entry.preferredStravaActivityId,
            ),
        ],
      );
    } else if (journal.loadingInitial) {
      body = const RunNowLoading(compact: true, label: 'Đang mở nhật ký');
    } else if (journal.error != null) {
      body = Row(
        children: [
          Expanded(child: _Muted('Không tải được nhật ký: ${journal.error}')),
          TextButton(
            onPressed: journal.loadFirstPage,
            child: const Text('Thử lại'),
          ),
        ],
      );
    } else {
      body = _Muted('Chưa có buổi chạy nào.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Row(
            children: [
              const Expanded(child: _Caption('Nhật ký chạy')),
              IconButton(
                tooltip: 'Tất cả buổi chạy',
                visualDensity: VisualDensity.compact,
                color: context.runNowPalette.accent,
                onPressed: () => context.push('/journal'),
                icon: const Icon(Icons.view_list_rounded),
              ),
            ],
          ),
        ),
        body,
      ],
    );
  }
}

/// Các chặng hành trình theo tổng km, ngay trong Hồ sơ.
class _JourneySection extends StatelessWidget {
  const _JourneySection();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: _Caption('Hành trình'),
        ),
        JourneyTimeline(),
      ],
    );
  }
}

/// Card "Châm ngôn hôm nay" — tách riêng, nền vàng nhạt, đúng nguyên bản
/// thiết kế (không lồng vào trong card hero tối như bản trước).
class _DailyQuoteCard extends StatelessWidget {
  const _DailyQuoteCard();

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '"',
            style: TextStyle(
              color: palette.accentDeep,
              fontSize: 20,
              height: 0.7,
              fontFamily: 'Georgia',
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CHÂM NGÔN HÔM NAY',
                  style: TextStyle(
                    color: palette.accentDeep,
                    fontSize: 9,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Mỗi kilomet là một dấu chân đặt lên bản đồ. Đi đủ lâu, '
                  'đường xa cũng thành câu chuyện của mình.',
                  style: TextStyle(
                    color: palette.ink.withValues(alpha: 0.82),
                    fontSize: 12,
                    height: 1.45,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
