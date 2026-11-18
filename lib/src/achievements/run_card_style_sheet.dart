import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card.dart';
import 'package:myrun/src/achievements/run_card_models.dart';
import 'package:myrun/src/achievements/run_card_providers.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/achievements/run_card_skin_sheet.dart';
import 'package:myrun/src/achievements/run_card_style.dart';
import 'package:myrun/src/achievements/run_faces/run_face_kit.dart';
import 'package:myrun/src/games/game_card_viewer.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/providers.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';

const _thumbExtent = 70.0;

@visibleForTesting
const runCardMapSwitchKey = ValueKey('run-card-map-switch');

@visibleForTesting
const runCardRouteSizeKey = ValueKey('run-card-route-size');

@visibleForTesting
const runCardTextLayoutKey = ValueKey('run-card-text-layout');

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
        hasArt: subject.artPath != null,
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
    this.hasArt = false,
    this.cardId,
    this.initial,
    this.skin,
    this.onUse,
  });

  final AchievementCardData data;

  /// Thẻ có GPS mới có bản đồ để bật.
  final bool hasRoute;

  /// Thẻ có tranh nền mới chọn được cỡ đường chạy ở mặt trước.
  final bool hasArt;
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
  late bool _bigRoute;
  late bool _follow;
  late RunNowAppearance _appearance;
  late RunNowElement _element;

  /// Mỗi lần mở sheet tay đều ghé các nút một lượt, bấm nút nào là tắt.
  bool _hint = true;

  /// Những chỗ gợi ý tay ghé qua.
  final _sizeSpot = GlobalKey();
  final _textSpot = GlobalKey();
  final _mapSpot = GlobalKey();

  @override
  void initState() {
    super.initState();
    final start = widget.initial ?? RunCardStyle.current;
    _set = start.set;
    _text = start.text;
    _map = start.map;
    _bigRoute = start.bigRoute;
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
    final style = _map && set.hasMapOption
        ? RunCardStyle.withMap(set, text)
        : RunCardStyle(set, text);
    return style.withBigRoute(_bigRoute && set.hasRouteSizeOption);
  }

  void _toggle(VoidCallback change) {
    HapticFeedback.selectionClick();
    setState(() {
      change();
      _hint = false;
    });
  }

  void _nextText() => _text = RunCardTextLayout
      .values[(_text.index + 1) % RunCardTextLayout.values.length];

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
    final canBigRoute =
        _set.hasRouteSizeOption && widget.hasArt && widget.hasRoute;
    final canMap = _set.hasMapOption && widget.hasRoute;
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
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Stack(
                    // Nút nằm sát đáy ảnh, bàn tay gợi ý thò xuống dưới.
                    clipBehavior: Clip.none,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _Preview(
                              widget.data,
                              style,
                              false,
                              key: runCardRouteSizeKey,
                              options: [
                                if (_set.ownColors)
                                  _Option(
                                    label: 'Bố cục chữ',
                                    value: _text.label,
                                    semanticsValue:
                                        '${_text.label}, ${_text.index + 1} '
                                        'trên ${RunCardTextLayout.values.length}',
                                    semanticsKey: runCardTextLayoutKey,
                                    icon: _Icon.text,
                                    step: _text.index,
                                    left: true,
                                    spot: _textSpot,
                                    onTap: () => _toggle(_nextText),
                                  ),
                                if (canBigRoute)
                                  _Option(
                                    label: 'Cỡ đường chạy',
                                    value: _bigRoute
                                        ? 'Đường chạy lớn'
                                        : 'Con dấu tròn',
                                    icon: _bigRoute
                                        ? _Icon.shrink
                                        : _Icon.expand,
                                    toggled: _bigRoute,
                                    spot: _sizeSpot,
                                    byFace: true,
                                    left: true,
                                    onTap: () =>
                                        _toggle(() => _bigRoute = !_bigRoute),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _Preview(
                              widget.data,
                              style,
                              true,
                              key: runCardMapSwitchKey,
                              options: [
                                if (canMap)
                                  _Option(
                                    label: 'Mặt sau',
                                    value: _map ? 'Bản đồ' : 'Nét vẽ',
                                    icon: _Icon.map,
                                    toggled: _map,
                                    spot: _mapSpot,
                                    byFace: true,
                                    onTap: () => _toggle(() => _map = !_map),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (_hint)
                        Positioned.fill(
                          child: _TourHint(
                            spots: [
                              if (canBigRoute) _sizeSpot,
                              if (_set.ownColors) _textSpot,
                              if (canMap) _mapSpot,
                            ],
                          ),
                        ),
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
                  if (choosesColor)
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 62),
                      child: Center(child: _colors(theme)),
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

/// Một lựa chọn đổi được của một mặt thẻ, hiện thành nút icon nổi ngay trên
/// chỗ của mặt thẻ mà nó đổi.
class _Option {
  const _Option({
    required this.label,
    required this.value,
    required this.icon,
    required this.spot,
    required this.onTap,
    this.left = false,
    this.toggled,
    this.step,
    this.semanticsValue,
    this.semanticsKey,
    this.byFace = false,
  });

  /// Lựa chọn này đổi cái gì, đọc cho trình đọc màn hình.
  final String label;

  /// Tên trạng thái đang chọn, hiện giữa ảnh một lúc sau khi bấm.
  final String value;
  final _Icon icon;

  /// Gắn vào nút để gợi ý tay tìm tới.
  final GlobalKey spot;
  final VoidCallback onTap;

  /// Nút nằm góc dưới trái ảnh, xếp liền nhau theo thứ tự; không thì góc dưới
  /// phải. Chỗ cố định cho mọi bộ, để bấm đổi gì nút cũng không dời khỏi tay.
  final bool left;

  /// Lựa chọn hai trạng thái thì là nút bật tắt, bật thì nút đảo màu.
  final bool? toggled;

  /// Lựa chọn ba trạng thái: đang ở trạng thái nào, vẽ thành ba vạch.
  final int? step;
  final String? semanticsValue;
  final Key? semanticsKey;

  /// Bấm thẳng vào ảnh cũng đổi lựa chọn này.
  final bool byFace;
}

/// Ảnh xem trước một mặt thẻ, mỗi lựa chọn là một nút nổi trên chỗ mà nó đổi.
/// Mặt thẻ đánh dấu chỗ con dấu và số km, ảnh đo chỗ đó sau mỗi lần dựng rồi
/// dời nút tới. Bấm xong thì giữa ảnh hiện tên trạng thái mới một lúc.
class _Preview extends StatefulWidget {
  const _Preview(
    this.data,
    this.style,
    this.back, {
    super.key,
    required this.options,
  });

  final AchievementCardData data;
  final RunCardStyle style;
  final bool back;
  final List<_Option> options;

  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  bool _down = false;

  /// Lựa chọn vừa đổi, tên của nó đang hiện giữa ảnh.
  GlobalKey? _flashing;
  bool _showLabel = false;
  Timer? _labelTimer;

  @override
  void dispose() {
    _labelTimer?.cancel();
    super.dispose();
  }

  void _pick(_Option option) {
    option.onTap();
    _labelTimer?.cancel();
    setState(() {
      _flashing = option.spot;
      _showLabel = true;
    });
    _labelTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _showLabel = false);
    });
  }

  /// Dải dưới ảnh cho nút đứng, để nút không che mặt thẻ.
  static const _band = _IconButton.side + 10;

  @override
  Widget build(BuildContext context) {
    final options = widget.options;
    final face = options.where((o) => o.byFace).firstOrNull;
    final flashing = options.where((o) => o.spot == _flashing).firstOrNull;
    return LayoutBuilder(
      builder: (context, box) {
        Widget card = _card(
          widget.data,
          widget.style,
          math.min(box.maxWidth, 180),
          back: widget.back,
        );
        if (face != null) {
          // Nút trên ảnh đã đọc lựa chọn này cho trình đọc màn hình.
          card = GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTapDown: (_) => setState(() => _down = true),
            onTapUp: (_) => setState(() => _down = false),
            onTapCancel: () => setState(() => _down = false),
            onTap: () => _pick(face),
            child: AnimatedScale(
              scale: _down ? 0.97 : 1,
              duration: const Duration(milliseconds: 100),
              child: card,
            ),
          );
        }
        // Tâm nút cách mép ảnh nửa nút cộng bóng, nằm giữa dải dưới.
        const edge = _IconButton.side / 2 + 3 - _IconButton.extent / 2;
        const bottom = _band / 2 - _IconButton.extent / 2;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: _band),
              child: card,
            ),
            if (flashing != null)
              Positioned.fill(
                bottom: _band,
                child: IgnorePointer(
                  child: Center(
                    child: _Label(flashing.value, show: _showLabel),
                  ),
                ),
              ),
            for (final left in [true, false])
              Positioned(
                left: left ? edge : null,
                right: left ? null : edge,
                bottom: bottom,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final option in options)
                      if (option.left == left)
                        KeyedSubtree(
                          key: option.spot,
                          child: _IconButton(
                            option,
                            onTap: () => _pick(option),
                          ),
                        ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

enum _Icon { expand, shrink, text, map }

/// Icon nét 24×24 của nút: mũi tên phóng to, thu vào, chữ Tt, tấm bản đồ gấp.
class _IconPainter extends CustomPainter {
  const _IconPainter(this.icon, this.ink);

  final _Icon icon;
  final Color ink;

  static Path _path(_Icon icon) {
    final p = Path();
    void line(List<(double, double)> points) {
      p.moveTo(points.first.$1, points.first.$2);
      for (final (x, y) in points.skip(1)) {
        p.lineTo(x, y);
      }
    }

    switch (icon) {
      case _Icon.expand:
        line([(14, 4), (20, 4), (20, 10)]);
        line([(20, 4), (13.5, 10.5)]);
        line([(10, 20), (4, 20), (4, 14)]);
        line([(4, 20), (10.5, 13.5)]);
      case _Icon.shrink:
        line([(19, 5), (13.5, 10.5)]);
        line([(14, 5.5), (14, 10), (18.5, 10)]);
        line([(5, 19), (10.5, 13.5)]);
        line([(10, 18.5), (10, 14), (5.5, 14)]);
      case _Icon.text:
        line([(3, 6), (14, 6)]);
        line([(8.5, 6), (8.5, 19)]);
        line([(14, 11), (21, 11)]);
        line([(17.5, 11), (17.5, 19)]);
      case _Icon.map:
        line([(3, 6.5), (9, 4), (15, 6.5), (21, 4), (21, 17.5)]);
        line([(21, 17.5), (15, 20), (9, 17.5), (3, 20), (3, 6.5)]);
        line([(9, 4), (9, 17.5)]);
        line([(15, 6.5), (15, 20)]);
    }
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(
      _path(icon),
      Paint()
        ..color = ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_IconPainter old) => old.icon != icon || old.ink != ink;
}

/// Nút trắng viền đen, bóng lệch cứng, ấn thì lún; bật thì đảo màu. Nút chỉ có
/// trong sheet, thẻ thật không có.
class _IconButton extends StatefulWidget {
  const _IconButton(this.option, {required this.onTap});

  final _Option option;
  final VoidCallback onTap;

  /// Cạnh nút vẽ ra.
  static const side = 28.0;

  /// Cả ô chạm, rộng hơn nút để dễ bấm trên ảnh nhỏ.
  static const extent = 42.0;

  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final option = widget.option;
    final on = option.toggled ?? false;
    final ink = on ? Colors.white : Colors.black;
    final paper = on ? Colors.black : Colors.white;
    final shadow = _down ? 0.0 : 2.0;
    final step = option.step;
    return Semantics(
      key: option.semanticsKey,
      button: true,
      toggled: option.toggled,
      label: option.label,
      value: option.semanticsValue ?? option.value,
      excludeSemantics: true,
      child: GestureDetector(
        // Nuốt chạm để ảnh bên dưới không đổi lựa chọn của nó.
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: SizedBox.square(
          dimension: _IconButton.extent,
          child: Center(
            child: Transform.translate(
              offset: Offset(2 - shadow, 2 - shadow),
              child: Container(
                width: _IconButton.side,
                height: _IconButton.side,
                decoration: BoxDecoration(
                  color: paper,
                  border: Border.all(width: 2),
                  boxShadow: [
                    BoxShadow(color: ink, offset: Offset(shadow, shadow)),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CustomPaint(
                      size: Size.square(step == null ? 16 : 13),
                      painter: _IconPainter(option.icon, ink),
                    ),
                    if (step != null) ...[
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < 3; i++) ...[
                            if (i > 0) const SizedBox(width: 2),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              width: i == step ? 6 : 3,
                              height: 2,
                              color: ink.withValues(alpha: i == step ? 1 : 0.3),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Một bàn tay đi lần lượt qua [spots], mỗi chỗ ấn hai lần kèm vòng sóng, rồi
/// mờ đi. Tay chạm vào giữa từng chỗ.
class _TourHint extends StatefulWidget {
  const _TourHint({required this.spots});

  final List<GlobalKey> spots;

  @override
  State<_TourHint> createState() => _TourHintState();
}

class _TourHintState extends State<_TourHint>
    with SingleTickerProviderStateMixin {
  /// Chờ sheet trượt lên xong rồi tay mới hiện.
  static const _delay = 400;
  static const _fadeIn = 300;
  static const _move = 600;
  static const _tap = 580;
  static const _taps = 2;
  static const _perSpot = _move + _tap * _taps;
  static const _fadeOut = 250;

  /// Tay ghé đủ các nút vài lượt cho người dùng kịp để ý, nghỉ giữa các lượt.
  static const _rounds = 3;
  static const _rest = 700;

  int get _round => _fadeIn + widget.spots.length * _perSpot + _fadeOut + _rest;

  late final _controller = AnimationController(vsync: this)
    ..addListener(_locate);

  /// Điểm chạm của từng chỗ trong toạ độ của gợi ý, đo lại mỗi nhịp vì nút
  /// dời chỗ khi hàng nút đổi.
  List<Offset> _points = const [];

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(_TourHint old) {
    super.didUpdateWidget(old);
    // Đổi bộ thẻ thì chỗ đổi được cũng đổi: chạy lại cho bộ mới.
    if (!_sameSpots(old.spots, widget.spots)) _start();
  }

  bool _sameSpots(List<GlobalKey> a, List<GlobalKey> b) =>
      a.length == b.length &&
      [for (var i = 0; i < a.length; i++) a[i] == b[i]].every((s) => s);

  void _start() {
    final ms = _delay + _rounds * _round - _rest;
    _controller
      ..duration = Duration(milliseconds: ms)
      ..forward(from: 0);
  }

  void _locate() {
    final self = context.findRenderObject();
    if (self is! RenderBox || !self.hasSize) return;
    final points = <Offset>[];
    for (final key in widget.spots) {
      final box = key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      points.add(
        self.globalToLocal(box.localToGlobal(box.size.center(Offset.zero))),
      );
    }
    setState(() => _points = points);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final points = _points;
    final total = _controller.duration?.inMilliseconds ?? 0;
    final elapsed = _controller.value * total - _delay;
    if (points.isEmpty || elapsed < 0 || _controller.isCompleted) {
      return const SizedBox.shrink();
    }
    final ms = elapsed % _round;
    final fade = math
        .min(ms / _fadeIn, (_round - _rest - ms) / _fadeOut)
        .clamp(0.0, 1.0);
    final at = ((ms - _fadeIn) / _perSpot).floor().clamp(0, points.length - 1);
    final local = ms - _fadeIn - at * _perSpot;
    final from = points[math.max(at - 1, 0)];
    final to = points[at];
    Offset where;
    var press = 0.0;
    double? ripple;
    if (local < _move) {
      final t = Curves.easeInOut.transform((local / _move).clamp(0.0, 1.0));
      where = Offset.lerp(from, to, t)!;
    } else {
      where = to;
      final beat = (((local - _move) / _tap) % 1).clamp(0.0, 1.0);
      // Cùng nhịp với gợi ý trên thẻ: hạ ngón nửa đầu, sóng toả nửa sau.
      press = beat < 0.5 ? beat * 2 : 1.0;
      ripple = beat < 0.5 ? 0.0 : (beat - 0.5) * 2;
    }
    const half = TapHintFinger.extent / 2;
    return ExcludeSemantics(
      child: IgnorePointer(
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: where.dx - half,
              top: where.dy - half,
              child: Opacity(
                opacity: fade,
                child: TapHintFinger(press: press, ripple: ripple),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tên chế độ vừa chọn, hiện một lúc giữa ảnh.
class _Label extends StatelessWidget {
  const _Label(this.text, {required this.show});

  final String text;
  final bool show;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: show ? 1 : 0,
    duration: const Duration(milliseconds: 180),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.72),
        borderRadius: context.runNowPalette.radius(8),
      ),
      child: Text(
        text,
        maxLines: 1,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
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
                borderRadius: context.runNowPalette.radius(7),
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
