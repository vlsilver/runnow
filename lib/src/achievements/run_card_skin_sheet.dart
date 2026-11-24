import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/achievements/run_card_skin_choice.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';

/// Chọn bộ màu thẻ: theo theme app, hay tự chọn nền sáng/tối và hành. Xem
/// trước hai mặt của [sample]; không có thì của một thẻ mẫu.
Future<void> showRunCardSkinSheet(
  BuildContext context, {
  AchievementCardData? sample,
}) => showModalBottomSheet<void>(
  context: context,
  useSafeArea: true,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) =>
      RunCardSheetTheme(child: RunCardSkinSheet(sample: sample ?? _sample())),
);

/// Nút mở bộ màu thẻ: chấm tròn hai màu của bộ đang dùng.
class RunCardSkinButton extends StatelessWidget {
  const RunCardSkinButton({super.key, required this.onPressed, this.ring});

  final VoidCallback onPressed;

  /// Màu viền; null thì theo chữ của theme.
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final skin = RunCardSkin.of(context);
    final tone = skin.accent(GameCardTier.legendary);
    return IconButton(
      tooltip: 'Bộ màu thẻ',
      onPressed: onPressed,
      icon: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: context.runNowPalette.round,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [skin.backTop, skin.backTop, tone, tone],
            stops: const [0, 0.5, 0.5, 1],
          ),
          border: Border.all(
            color:
                ring ??
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
            width: 1.5,
          ),
        ),
      ),
    );
  }
}

/// Sheet là cài đặt của app nên luôn mặc theme app, kể cả khi mở từ màn có
/// theme riêng: kính của theme đêm Ma Sói gần trong suốt, sheet đè lên màn
/// ván sẽ không đọc được.
class RunCardSheetTheme extends ConsumerWidget {
  const RunCardSheetTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(themeControllerProvider);
    return Theme(
      data: buildRunNowTheme(
        app.element,
        appearance: app.appearance,
        darkTone: app.darkTone,
        style: app.style,
      ),
      child: child,
    );
  }
}

/// Nhãn ngắn của lựa chọn đã lưu cho dòng cài đặt.
String runCardSkinLabel(RunCardSkinChoice? choice) => switch (choice) {
  null => 'Theo app',
  (final appearance, final element) => '${element.label} · ${appearance.label}',
};

class RunCardSkinSheet extends ConsumerStatefulWidget {
  const RunCardSkinSheet({super.key, required this.sample});

  final AchievementCardData sample;

  @override
  ConsumerState<RunCardSkinSheet> createState() => _RunCardSkinSheetState();
}

class _RunCardSkinSheetState extends ConsumerState<RunCardSkinSheet> {
  late bool _follow;
  late RunNowAppearance _appearance;
  late RunNowElement _element;

  @override
  void initState() {
    super.initState();
    final choice = ref.read(runCardSkinControllerProvider).choice;
    final app = ref.read(themeControllerProvider);
    _follow = choice == null;
    _appearance = choice?.$1 ?? app.appearance;
    _element = choice?.$2 ?? app.element;
  }

  /// Chọn một hành thì thôi theo app; đang theo app thì sáng tối bắt đầu từ
  /// đúng màu đang thấy.
  void _pickElement(RunNowElement element) => setState(() {
    if (_follow) _appearance = ref.read(themeControllerProvider).appearance;
    _follow = false;
    _element = element;
  });

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(themeControllerProvider);
    final appearance = _follow ? app.appearance : _appearance;
    final element = _follow ? app.element : _element;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        14,
        0,
        14,
        MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: GlassPanel(
        borderRadius: 22,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 38,
                  child: Row(
                    children: [
                      Text(
                        'Bộ màu',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      if (!_follow)
                        RunCardAppearanceToggle(
                          value: _appearance,
                          onChanged: (value) =>
                              setState(() => _appearance = value),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                RunCardSkinScope(
                  skin: RunCardSkin.forTheme(appearance, element),
                  child: _FlipPreview(sample: widget.sample),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: RunCardSwatch(
                        label: 'App',
                        icon: Icons.smartphone_rounded,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.08,
                        ),
                        iconColor: theme.colorScheme.onSurface,
                        selected: _follow,
                        onTap: () => setState(() => _follow = true),
                      ),
                    ),
                    for (final e in RunNowElement.values)
                      Expanded(
                        child: RunCardSwatch(
                          label: e.label,
                          icon: e.icon,
                          color: e.ramp[2],
                          iconColor: Colors.white,
                          selected: !_follow && _element == e,
                          onTap: () => _pickElement(e),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: _apply, child: const Text('Áp dụng')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _apply() async {
    // Lấy controller trước khi đóng sheet: đóng rồi thì ref không dùng được.
    final controller = ref.read(runCardSkinControllerProvider);
    Navigator.of(context).pop();
    await controller.setChoice(_follow ? null : (_appearance, _element));
  }
}

/// Hai icon sáng và tối ở góc sheet.
class RunCardAppearanceToggle extends StatelessWidget {
  const RunCardAppearanceToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final RunNowAppearance value;
  final ValueChanged<RunNowAppearance> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget option(RunNowAppearance item, IconData icon) {
      final selected = item == value;
      return Tooltip(
        message: item.label,
        child: Semantics(
          button: true,
          selected: selected,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(item),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 40,
              height: 32,
              decoration: BoxDecoration(
                color: selected ? scheme.onSurface : Colors.transparent,
                borderRadius: context.runNowPalette.radius(16),
              ),
              child: Icon(
                icon,
                size: 18,
                color: selected
                    ? scheme.surface
                    : scheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.07),
        borderRadius: context.runNowPalette.radius(19),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          option(RunNowAppearance.light, Icons.light_mode_outlined),
          option(RunNowAppearance.dark, Icons.dark_mode_outlined),
        ],
      ),
    );
  }
}

/// Một chấm trong hàng màu.
class RunCardSwatch extends StatelessWidget {
  const RunCardSwatch({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.iconColor,
    required this.selected,
    required this.onTap,
    this.size = 36,
  });

  final double size;
  final String label;
  final IconData icon;
  final Color color;
  final Color iconColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: context.runNowPalette.round,
                border: Border.all(
                  color: selected ? ink : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: context.runNowPalette.round,
                  color: color,
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              style: theme.textTheme.labelSmall?.copyWith(
                color: selected ? ink : ink.withValues(alpha: 0.55),
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Một thẻ lớn, chạm để lật. Hai mặt luôn được dựng: dựng mặt sau lúc lật thì
/// bản đồ phải tải tile lại từ đầu.
class _FlipPreview extends StatefulWidget {
  const _FlipPreview({required this.sample});

  final AchievementCardData sample;

  @override
  State<_FlipPreview> createState() => _FlipPreviewState();
}

class _FlipPreviewState extends State<_FlipPreview> {
  static const _maxWidth = 204.0;

  bool _back = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(_maxWidth, constraints.maxWidth);
        Widget face({required bool back}) => GameCardScaled(
          width: width,
          size: achievementCardSize,
          child: AchievementCard(
            data: widget.sample,
            back: back,
            animate: false,
          ),
        );
        final front = face(back: false);
        final back = face(back: true);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _back = !_back),
          child: Column(
            children: [
              IgnorePointer(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: _back ? 1 : 0),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeInOut,
                  builder: (context, turn, _) {
                    final showBack = turn >= 0.5;
                    return Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0012)
                        ..rotateY(turn * math.pi),
                      child: Stack(
                        children: [
                          Opacity(opacity: showBack ? 0 : 1, child: front),
                          Opacity(
                            opacity: showBack ? 1 : 0,
                            child: Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.rotationY(math.pi),
                              child: back,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Chạm để lật',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

AchievementCardData _sample() => runCardData(runCardSample(), owner: 'Bạn');

/// Thẻ mẫu khi chưa có thẻ thật để xem trước: một vòng quanh hồ Tây.
RunCard runCardSample() => RunCard(
  id: 'sample',
  tier: GameCardTier.rare,
  km: 6.4,
  odds: const [],
  snapshot: RunCardSnapshot(
    name: 'Một vòng hồ Tây',
    sportType: 'Run',
    distanceMeters: 6400,
    movingTimeSeconds: 2150,
    elapsedTimeSeconds: 2200,
    startedAt: DateTime(2026, 10, 25, 6, 5),
    route: const [
      LatLng(21.0578, 105.8125),
      LatLng(21.0641, 105.8152),
      LatLng(21.0669, 105.8233),
      LatLng(21.0637, 105.8311),
      LatLng(21.0566, 105.8336),
      LatLng(21.0497, 105.8302),
      LatLng(21.0474, 105.8221),
      LatLng(21.0512, 105.8147),
      LatLng(21.0578, 105.8125),
    ],
    splits: const [
      RunCardSplit(distanceMeters: 1000, movingTimeSeconds: 342),
      RunCardSplit(distanceMeters: 1000, movingTimeSeconds: 336),
      RunCardSplit(distanceMeters: 1000, movingTimeSeconds: 331),
      RunCardSplit(distanceMeters: 1000, movingTimeSeconds: 338),
      RunCardSplit(distanceMeters: 1000, movingTimeSeconds: 327),
      RunCardSplit(distanceMeters: 1000, movingTimeSeconds: 319),
    ],
  ),
);
