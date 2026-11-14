import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/achievements/run_card_skin_sheet.dart';
import 'package:myrun/src/achievements/run_card_style.dart';
import 'package:myrun/src/achievements/run_faces/run_face_kit.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';

const _thumbExtent = 70.0;

@visibleForTesting
const runCardMapSwitchKey = ValueKey('run-card-map-switch');

/// Chọn bộ thẻ, kiểu chữ và bộ màu ngay trên [card]. Không có thẻ thật thì xem
/// trước thẻ mẫu và chỉ đổi mặc định.
///
/// Có [onUse] thì lựa chọn chỉ trả về cho nơi mở, không lưu: màn khoe đổi file
/// của riêng lần khoe đó, và bộ màu do chính màn khoe chọn nên truyền [skin].
Future<void> showRunCardStyleSheet(
  BuildContext context, {
  RunCard? card,
  AchievementCardData? data,
  RunCardStyle? initial,
  RunCardSkin? skin,
  ValueChanged<RunCardStyle>? onUse,
}) {
  final subject = card ?? runCardSample();
  final shown = data ?? runCardData(subject, owner: 'Bạn');
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => RunCardSheetTheme(
      child: RunCardStyleSheet(
        cardId: card?.id,
        data: shown,
        hasRoute: RunFace(subject, shown).hasRoute,
        initial:
            initial ??
            (card == null
                ? null
                : ProviderScope.containerOf(
                    context,
                    listen: false,
                  ).read(runCardStyleControllerProvider).styleFor(card)),
        skin: skin,
        onUse: onUse,
      ),
    ),
  );
}

class RunCardStyleButton extends StatelessWidget {
  const RunCardStyleButton({super.key, required this.onPressed, this.ring});

  final VoidCallback onPressed;

  /// Màu viền tròn trên sân khấu; null là nút thường trên thanh tiêu đề.
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final ring = this.ring;
    return IconButton(
      tooltip: 'Kiểu thẻ',
      onPressed: onPressed,
      style: ring == null
          ? null
          : IconButton.styleFrom(
              foregroundColor: ring,
              fixedSize: const Size.square(48),
              side: BorderSide(color: ring, width: 2),
            ),
      icon: const Icon(Icons.style_outlined),
    );
  }
}

class RunCardStyleSheet extends ConsumerStatefulWidget {
  const RunCardStyleSheet({
    super.key,
    required this.data,
    required this.hasRoute,
    this.cardId,
    this.initial,
    this.skin,
    this.onUse,
  });

  final AchievementCardData data;

  /// Thẻ có GPS mới có bản đồ để bật.
  final bool hasRoute;
  final String? cardId;
  final RunCardStyle? initial;
  final RunCardSkin? skin;
  final ValueChanged<RunCardStyle>? onUse;

  @override
  ConsumerState<RunCardStyleSheet> createState() => _RunCardStyleSheetState();
}

class _RunCardStyleSheetState extends ConsumerState<RunCardStyleSheet> {
  final _strip = ScrollController();
  late RunCardSet _set;
  late RunCardTextLayout _text;
  late bool _map;
  late bool _follow;
  late RunNowAppearance _appearance;
  late RunNowElement _element;

  @override
  void initState() {
    super.initState();
    final start = widget.initial ?? RunCardStyle.current;
    _set = start.set;
    _text = start.text;
    _map = start.map;
    final choice = ref.read(runCardSkinControllerProvider).choice;
    final app = ref.read(themeControllerProvider);
    _follow = choice == null;
    _appearance = choice?.$1 ?? app.appearance;
    _element = choice?.$2 ?? app.element;
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
  }

  @override
  void dispose() {
    _strip.dispose();
    super.dispose();
  }

  /// Mở sheet là thấy ngay bộ đang dùng, dù nó nằm cuối dải.
  void _revealSelected() {
    if (!_strip.hasClients) return;
    final at = _sets.indexOf(_set);
    if (at < 0) return;
    final offset = at * _thumbExtent - _strip.position.viewportDimension / 3;
    _strip.jumpTo(offset.clamp(0.0, _strip.position.maxScrollExtent));
  }

  List<RunCardSet> get _sets =>
      ref.read(runCardSetsProvider).value ?? RunCardSet.values;

  /// Bộ đi theo bộ màu chỉ có một bố cục chữ.
  RunCardStyle _styleOf(RunCardSet set) {
    final text = set.ownColors ? _text : RunCardTextLayout.full;
    return _map && set.hasMapOption
        ? RunCardStyle.withMap(set, text)
        : RunCardStyle(set, text);
  }

  void _pickElement(RunNowElement element) => setState(() {
    if (_follow) _appearance = ref.read(themeControllerProvider).appearance;
    _follow = false;
    _element = element;
  });

  Future<void> _use() async {
    final style = _styleOf(_set);
    if (widget.onUse case final onUse?) {
      Navigator.of(context).pop();
      onUse(style);
      return;
    }
    // Lấy controller trước khi đóng sheet: đóng rồi thì ref không dùng được.
    final styles = ref.read(runCardStyleControllerProvider);
    final skins = ref.read(runCardSkinControllerProvider);
    Navigator.of(context).pop();
    await Future.wait([
      styles.apply(style, cardId: widget.cardId),
      // Bộ có màu riêng không dùng bộ màu, đừng đổi màu của các thẻ khác.
      if (!_set.ownColors)
        skins.setChoice(_follow ? null : (_appearance, _element)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(themeControllerProvider);
    final sets = ref.watch(runCardSetsProvider).value ?? RunCardSet.values;
    final theme = Theme.of(context);
    final fixedSkin = widget.skin;
    final skin =
        fixedSkin ??
        RunCardSkin.forTheme(
          _follow ? app.appearance : _appearance,
          _follow ? app.element : _element,
        );
    final style = _styleOf(_set);
    final choosesColor = !_set.ownColors && fixedSkin == null;
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
            child: RunCardSkinScope(
              skin: skin,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: 38,
                    child: Row(
                      children: [
                        Text(
                          'Kiểu thẻ',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        if (choosesColor && !_follow)
                          RunCardAppearanceToggle(
                            value: _appearance,
                            onChanged: (value) =>
                                setState(() => _appearance = value),
                          ),
                        if (_set.hasMapOption && widget.hasRoute) ...[
                          const SizedBox(width: 12),
                          _MapSwitch(
                            value: _map,
                            onChanged: (value) => setState(() => _map = value),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _Preview(widget.data, style, false)),
                      const SizedBox(width: 10),
                      Expanded(child: _Preview(widget.data, style, true)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 112,
                    child: ListView.builder(
                      controller: _strip,
                      scrollDirection: Axis.horizontal,
                      itemExtent: _thumbExtent,
                      itemCount: sets.length,
                      itemBuilder: (context, index) {
                        final set = sets[index];
                        return _Thumb(
                          data: widget.data,
                          style: _styleOf(set),
                          selected: set == _set,
                          onTap: () => setState(() => _set = set),
                        );
                      },
                    ),
                  ),
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 62),
                    child: Center(
                      child: _set.ownColors
                          ? _TextLayoutPicker(
                              value: _text,
                              onChanged: (value) =>
                                  setState(() => _text = value),
                            )
                          : choosesColor
                          ? _colors(theme)
                          : const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: _use, child: const Text('Dùng')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _colors(ThemeData theme) => Row(
    children: [
      Expanded(
        child: RunCardSwatch(
          label: 'App',
          icon: Icons.smartphone_rounded,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
          iconColor: theme.colorScheme.onSurface,
          selected: _follow,
          size: 32,
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
            size: 32,
            onTap: () => _pickElement(e),
          ),
        ),
    ],
  );
}

Widget _card(
  AchievementCardData data,
  RunCardStyle style,
  double width, {
  bool back = false,
}) => IgnorePointer(
  child: RepaintBoundary(
    child: RunCardStyleScope.fixed(
      style: style,
      child: GameCardScaled(
        width: width,
        size: achievementCardSize,
        child: AchievementCard(data: data, back: back, animate: false),
      ),
    ),
  ),
);

class _Preview extends StatelessWidget {
  const _Preview(this.data, this.style, this.back);

  final AchievementCardData data;
  final RunCardStyle style;
  final bool back;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) =>
        _card(data, style, math.min(box.maxWidth, 180), back: back),
  );
}

class _Thumb extends StatelessWidget {
  const _Thumb({
    required this.data,
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final AchievementCardData data;
  final RunCardStyle style;
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: selected ? ink : Colors.transparent,
                  width: 2,
                ),
              ),
              child: _card(data, style, 58),
            ),
            const SizedBox(height: 5),
            SizedBox(
              width: 64,
              child: Text(
                style.set.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: selected ? ink : ink.withValues(alpha: 0.55),
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapSwitch extends StatelessWidget {
  const _MapSwitch({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    return Semantics(
      button: true,
      toggled: value,
      child: GestureDetector(
        key: runCardMapSwitchKey,
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(!value),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Bản đồ',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 46,
              height: 28,
              padding: const EdgeInsets.all(3),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(
                color: value ? ink : ink.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: value ? theme.colorScheme.surface : ink,
                ),
                child: const SizedBox.square(dimension: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextLayoutPicker extends StatelessWidget {
  const _TextLayoutPicker({required this.value, required this.onChanged});

  final RunCardTextLayout value;
  final ValueChanged<RunCardTextLayout> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(19),
      ),
      child: Row(
        children: [
          for (final item in RunCardTextLayout.values)
            Expanded(
              child: Semantics(
                button: true,
                selected: item == value,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(item),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: item == value
                          ? scheme.onSurface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      item.label,
                      maxLines: 1,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: item == value
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: item == value
                            ? scheme.surface
                            : scheme.onSurface.withValues(alpha: 0.66),
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
