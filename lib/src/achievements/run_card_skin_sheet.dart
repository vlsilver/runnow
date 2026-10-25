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
      _AppTheme(child: RunCardSkinSheet(sample: sample ?? _sample())),
);

/// Sheet là cài đặt của app nên luôn mặc theme app, kể cả khi mở từ màn có
/// theme riêng: kính của theme đêm Ma Sói gần trong suốt, sheet đè lên màn
/// ván sẽ không đọc được.
class _AppTheme extends ConsumerWidget {
  const _AppTheme({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final app = ref.watch(themeControllerProvider);
    return Theme(
      data: buildRunNowTheme(
        app.element,
        appearance: app.appearance,
        darkTone: app.darkTone,
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

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(themeControllerProvider);
    final appearance = _follow ? app.appearance : _appearance;
    final element = _follow ? app.element : _element;
    final heading = Theme.of(context).textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w900,
      letterSpacing: 1.4,
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        14,
        0,
        14,
        MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: GlassPanel(
        borderRadius: 22,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.88,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('BỘ MÀU THẺ', style: heading),
                const SizedBox(height: 12),
                RunCardSkinScope(
                  skin: RunCardSkin.forTheme(appearance, element),
                  child: _Preview(sample: widget.sample),
                ),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Theo theme app'),
                  subtitle: Text(
                    'Đang là ${app.element.label} · ${app.appearance.label}',
                  ),
                  value: _follow,
                  onChanged: (value) => setState(() {
                    _follow = value;
                    // Tắt theo app thì bắt đầu từ đúng màu đang thấy.
                    if (!value) {
                      _appearance = app.appearance;
                      _element = app.element;
                    }
                  }),
                ),
                const SizedBox(height: 4),
                SegmentedButton<RunNowAppearance>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: RunNowAppearance.light,
                      icon: Icon(Icons.light_mode_outlined),
                      label: Text('Sáng'),
                    ),
                    ButtonSegment(
                      value: RunNowAppearance.dark,
                      icon: Icon(Icons.dark_mode_outlined),
                      label: Text('Tối'),
                    ),
                  ],
                  selected: {appearance},
                  onSelectionChanged: _follow
                      ? null
                      : (values) => setState(() => _appearance = values.single),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final e in RunNowElement.values)
                      ChoiceChip(
                        avatar: Icon(e.icon, color: e.ramp[2]),
                        label: Text(e.label),
                        selected: element == e,
                        onSelected: _follow
                            ? null
                            : (_) => setState(() => _element = e),
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

/// Hai mặt thẻ cạnh nhau, thu vừa bề ngang sheet.
class _Preview extends StatelessWidget {
  const _Preview({required this.sample});

  final AchievementCardData sample;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(150.0, (constraints.maxWidth - 12) / 2);
        Widget face({required bool back}) => GameCardScaled(
          width: width,
          size: achievementCardSize,
          child: AchievementCard(data: sample, back: back, animate: false),
        );
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            face(back: false),
            const SizedBox(width: 12),
            face(back: true),
          ],
        );
      },
    );
  }
}

/// Thẻ mẫu khi chưa có thẻ thật để xem trước: một vòng quanh hồ Tây.
AchievementCardData _sample() => runCardData(
  RunCard(
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
  ),
  owner: 'Bạn',
);
