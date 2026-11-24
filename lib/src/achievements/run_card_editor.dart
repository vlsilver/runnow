import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:myrun/src/achievements/achievement_card.dart';
import 'package:myrun/src/achievements/run_card_layout.dart';
import 'package:myrun/src/achievements/run_card_skin.dart';
import 'package:myrun/src/achievements/run_card_style.dart';
import 'package:myrun/src/achievements/run_faces/face_edit.dart';
import 'package:myrun/src/achievements/run_faces/run_faces.dart';
import 'package:myrun/src/games/game_role_card.dart';

/// Mở màn chỉnh mặt trước của [style]. Trả bố cục mới, null là huỷ.
Future<RunCardLayout?> showRunCardEditor(
  BuildContext context, {
  required AchievementCardData data,
  required RunCardStyle style,
  required RunCardSkin skin,
}) => Navigator.of(context).push(
  MaterialPageRoute<RunCardLayout>(
    fullscreenDialog: true,
    builder: (_) => RunCardEditor(data: data, style: style, skin: skin),
  ),
);

class RunCardEditor extends StatefulWidget {
  const RunCardEditor({
    super.key,
    required this.data,
    required this.style,
    required this.skin,
  });

  final AchievementCardData data;
  final RunCardStyle style;
  final RunCardSkin skin;

  @override
  State<RunCardEditor> createState() => _RunCardEditorState();
}

/// Gần trục giữa trong khoảng này (phần trăm) thì hít vào trục.
const _snapX = 2.5;
const _snapY = 2.0;

/// Chữ không được ra sát mép thẻ hơn khoảng này (phần trăm).
const _edge = 2.0;

/// Độ sáng của tám tông trong bảng "Màu khác", từ tối tới sáng.
const _shades = [0.12, 0.24, 0.36, 0.48, 0.6, 0.72, 0.84, 0.94];

/// Thứ tự bấm trúng: chữ nằm trên đường chạy.
const _hitOrder = [CardPart.km, CardPart.time, CardPart.pace, CardPart.route];

class _RunCardEditorState extends State<RunCardEditor> {
  late RunCardLayout _layout = widget.style.layout;
  late final List<FaceTone> _tones = faceTones(widget.style.set);
  final _keys = {for (final p in CardPart.values) p: GlobalKey()};
  final _face = GlobalKey();
  final _art = GlobalKey();
  final _area = GlobalKey();
  CardPart? _selected;

  /// Các phần bộ này có vẽ, biết sau khung hình đầu.
  Set<CardPart> _present = const {};

  /// Đang mở bảng "Màu khác" và màu gốc đang xem trong bảng.
  bool _picking = false;
  double _hue = 20;

  /// Phần đang kéo và điểm neo chưa làm tròn của nó, để kéo chậm không bị
  /// kẹt ở số nguyên.
  CardPart? _dragging;
  Offset _at = Offset.zero;
  ({bool x, bool y}) _snapped = (x: false, y: false);

  PartPlacement _of(CardPart part) => _layout.of(part);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _findParts());
  }

  void _findParts() {
    if (!mounted) return;
    final present = {
      for (final part in CardPart.values)
        if (_keys[part]!.currentContext != null) part,
    };
    if (present.length != _present.length || !present.containsAll(_present)) {
      setState(() => _present = present);
    }
  }

  RenderBox? _box(GlobalKey key) =>
      switch (key.currentContext?.findRenderObject()) {
        final RenderBox box when box.attached && box.hasSize => box,
        _ => null,
      };

  /// Khung đang vẽ của [part] trong toạ độ của [space].
  Rect? _rectOf(CardPart part, RenderBox space) {
    final box = _box(_keys[part]!);
    if (box == null) return null;
    return Rect.fromPoints(
      space.globalToLocal(box.localToGlobal(Offset.zero)),
      space.globalToLocal(box.localToGlobal(box.size.bottomRight(Offset.zero))),
    );
  }

  /// Đường chạy vẽ trên nền lưu theo vùng tranh; chữ và con dấu đường chạy
  /// (thẻ có tranh) lưu theo mặt thẻ.
  RenderBox? _spaceOf(CardPart part) => _onArt(part) ? _box(_art) : _box(_face);

  bool _onArt(CardPart part) => part == CardPart.route && _box(_art) != null;

  /// Phần trên cùng dưới tay; phần nhỏ được nới vùng bấm cho dễ trúng.
  CardPart? _hit(Offset point) {
    final area = _box(_area);
    if (area == null) return null;
    for (final part in _hitOrder) {
      if (!_present.contains(part) || _of(part).hidden) continue;
      if (_rectOf(part, area)?.inflate(8).contains(point) ?? false) return part;
    }
    return null;
  }

  void _select(CardPart? part) => setState(() {
    _selected = part;
    _picking = false;
  });

  void _start(DragStartDetails details) {
    final part = _hit(details.localPosition);
    final space = part == null ? null : _spaceOf(part);
    final rect = space == null ? null : _rectOf(part!, space);
    if (part == null || space == null || rect == null) return;
    // Phần chưa dời thì bắt đầu từ chỗ nó đang đứng trong bố cục gốc.
    final anchor = editAnchorOf(_keys[part]!) ?? Alignment.center;
    final point = anchor.withinRect(rect);
    setState(() {
      _selected = part;
      _picking = false;
      _dragging = part;
      _at = Offset(
        point.dx / space.size.width * 100,
        point.dy / space.size.height * 100,
      );
    });
  }

  void _move(DragUpdateDetails details) {
    final part = _dragging;
    final space = part == null ? null : _spaceOf(part);
    final rect = space == null ? null : _rectOf(part!, space);
    if (part == null || space == null || rect == null) return;
    final from = space.globalToLocal(details.globalPosition - details.delta);
    final to = space.globalToLocal(details.globalPosition);
    final size = space.size;
    _at += Offset(
      (to.dx - from.dx) / size.width * 100,
      (to.dy - from.dy) / size.height * 100,
    );
    final anchor = editAnchorOf(_keys[part]!) ?? Alignment.center;
    final ax = (anchor.x + 1) / 2;
    final ay = (anchor.y + 1) / 2;
    final w = rect.width / size.width * 100;
    final h = rect.height / size.height * 100;
    double x;
    double y;
    final onArt = _onArt(part);
    if (onArt) {
      // Khung đường chạy được ra ngoài tranh, chỉ tâm phải nằm trong.
      x = _at.dx.clamp(0, 100);
      y = _at.dy.clamp(0, 100);
    } else {
      x = _clamp(_at.dx, _edge + ax * w, 100 - _edge - (1 - ax) * w);
      y = _clamp(_at.dy, _edge + ay * h, 100 - _edge - (1 - ay) * h);
    }
    // Kéo quá mép rồi kéo lại thì phần đi theo tay ngay, không có khúc chết.
    _at = Offset(x, y);
    final toCenterX = (0.5 - ax) * w;
    final toCenterY = (0.5 - ay) * h;
    // Trục giữa vẽ theo thẻ, nên chỉ phần lưu theo thẻ mới hít trục.
    final snapX = !onArt && (x + toCenterX - 50).abs() < _snapX;
    final snapY = !onArt && (y + toCenterY - 50).abs() < _snapY;
    if (snapX) x = 50 - toCenterX;
    if (snapY) y = 50 - toCenterY;
    if (snapX && !_snapped.x || snapY && !_snapped.y) {
      HapticFeedback.selectionClick();
    }
    final placement = _of(
      part,
    ).moveTo(x.round().clamp(0, 100), y.round().clamp(0, 100));
    setState(() {
      _snapped = (x: snapX, y: snapY);
      _layout = _layout.place(part, placement);
    });
  }

  /// Phần to hơn vùng đứng thì đứng giữa vùng.
  static double _clamp(double v, double low, double high) =>
      low > high ? (low + high) / 2 : v.clamp(low, high);

  void _end() => setState(() {
    _dragging = null;
    _snapped = (x: false, y: false);
  });

  void _change(CardPart part, PartPlacement Function(PartPlacement) edit) =>
      setState(() => _layout = _layout.place(part, edit(_of(part))));

  void _resize(int step) {
    final part = _selected;
    if (part == null) return;
    _change(
      part,
      (at) => at.copyWith(
        size: (at.size + step).clamp(0, PartPlacement.scales.length - 1),
      ),
    );
  }

  void _setHidden(CardPart part, bool hidden) {
    _change(part, (at) => at.copyWith(hidden: hidden));
    if (hidden && _selected == part) _select(null);
  }

  void _paint(PartColor color) {
    final part = _selected;
    if (part == null) return;
    _change(part, (at) => at.withColor(color));
  }

  void _openPicker() {
    final custom = switch (_selected) {
      final part? => _of(part).color,
      null => null,
    };
    setState(() {
      _picking = !_picking;
      if (custom case PartCustom(:final color)) {
        _hue = HSLColor.fromColor(color).hue;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selected;
    final style = widget.style.withLayout(_layout);
    final color = selected == null ? null : _of(selected).color;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.style.set.label),
        actions: [
          TextButton(
            onPressed: () => setState(() {
              _layout = RunCardLayout.initial;
              _selected = null;
              _picking = false;
            }),
            child: const Text('Đặt lại'),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(_layout),
              child: const Text('Xong'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) {
            final width = (box.maxWidth - 48).clamp(200.0, 320.0);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Center(
                  child: SizedBox(
                    key: _area,
                    width: width,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (d) => _select(_hit(d.localPosition)),
                      onPanStart: _start,
                      onPanUpdate: _move,
                      onPanEnd: (_) => _end(),
                      onPanCancel: _end,
                      child: Stack(
                        children: [
                          RunCardSkinScope(
                            skin: widget.skin,
                            child: RunCardStyleScope.fixed(
                              style: style,
                              child: CardEditScope(
                                keys: _keys,
                                face: _face,
                                art: _art,
                                selected: selected,
                                outline: theme.colorScheme.primary,
                                child: IgnorePointer(
                                  child: GameCardScaled(
                                    width: width,
                                    size: achievementCardSize,
                                    child: AchievementCard(
                                      data: widget.data,
                                      animate: false,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_dragging != null)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: CustomPaint(
                                  painter: _Guides(
                                    x: _snapped.x,
                                    y: _snapped.y,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          selected?.label ?? 'Chạm một phần để chỉnh',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Nhỏ hơn',
                        onPressed: selected == null ? null : () => _resize(-1),
                        icon: const Icon(Icons.remove_rounded),
                      ),
                      IconButton(
                        tooltip: 'To hơn',
                        onPressed: selected == null ? null : () => _resize(1),
                        icon: const Icon(Icons.add_rounded),
                      ),
                      IconButton(
                        tooltip: 'Ẩn',
                        onPressed: selected == null || !selected.canHide
                            ? null
                            : () => _setHidden(selected, true),
                        icon: const Icon(Icons.visibility_off_outlined),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final part in CardPart.values)
                      if (part.canHide && _present.contains(part))
                        FilterChip(
                          label: Text(part.label),
                          selected: !_of(part).hidden,
                          onSelected: (_) =>
                              _setHidden(part, !_of(part).hidden),
                        ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final (index, tone) in _tones.indexed)
                      _Swatch(
                        label: 'Màu ${tone.label}',
                        fill: BoxDecoration(color: tone.color),
                        selected: color == PartTone(index),
                        onTap: selected == null
                            ? null
                            : () => _paint(PartTone(index)),
                      ),
                    _Swatch(
                      label: 'Màu khác',
                      fill: switch (color) {
                        PartCustom(:final color) => BoxDecoration(color: color),
                        _ => BoxDecoration(gradient: _rainbow),
                      },
                      selected: color is PartCustom,
                      onTap: selected == null ? null : _openPicker,
                    ),
                  ],
                ),
                if (_picking && selected != null) ...[
                  const SizedBox(height: 10),
                  Slider(
                    value: _hue,
                    max: 360,
                    label: 'Sắc màu',
                    onChanged: (v) => setState(() => _hue = v),
                  ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final light in _shades)
                        _Swatch(
                          label: 'Tông ${(light * 100).round()}',
                          fill: BoxDecoration(color: _shade(_hue, light)),
                          selected: color == PartCustom(_shade(_hue, light)),
                          onTap: () => _paint(PartCustom(_shade(_hue, light))),
                        ),
                    ],
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(RunCardEditor old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) => _findParts());
  }
}

Color _shade(double hue, double light) =>
    HSLColor.fromAHSL(1, hue, 0.8, light).toColor();

/// Vòng màu của ô "Màu khác" khi phần chưa có màu tự chọn.
final _rainbow = SweepGradient(
  colors: [for (var hue = 0.0; hue <= 360; hue += 60) _shade(hue, 0.55)],
);

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.label,
    required this.fill,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final BoxDecoration fill;
  final bool selected;

  /// Null khi chưa chọn phần nào để tô.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final line = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.35 : 1,
          child: Container(
            width: 36,
            height: 36,
            decoration: fill.copyWith(
              shape: BoxShape.circle,
              border: Border.all(color: line, width: selected ? 3 : 1),
            ),
          ),
        ),
      ),
    );
  }
}

/// Trục giữa hiện khi phần đang kéo hít vào nó.
class _Guides extends CustomPainter {
  const _Guides({required this.x, required this.y, required this.color});

  final bool x;
  final bool y;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    if (x) {
      canvas.drawLine(
        Offset(size.width / 2, 0),
        Offset(size.width / 2, size.height),
        paint,
      );
    }
    if (y) {
      canvas.drawLine(
        Offset(0, size.height / 2),
        Offset(size.width, size.height / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Guides old) =>
      old.x != x || old.y != y || old.color != color;
}
