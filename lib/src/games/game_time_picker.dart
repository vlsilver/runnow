import 'package:flutter/material.dart';
import 'package:myrun/src/theme.dart';

// Chọn giờ cho màn tạo ván: hạn đóng đăng ký và giờ chia bài (ngày, giờ,
// phút), cùng thẻ và ô chọn số vòng. Phòng chạy hẹn giờ dùng lại sheet này
// với bộ màu theo theme.

/// Màu của sheet chọn giờ. Ván Ma Sói dùng bộ đêm [moonlit]; màn khác lấy
/// bộ theo theme bằng [GameTimeColors.of].
class GameTimeColors {
  const GameTimeColors({
    required this.panel,
    required this.ink,
    required this.faint,
    required this.danger,
    required this.on,
    required this.onInk,
    required this.cell,
    required this.cellNight,
    required this.border,
  });

  factory GameTimeColors.of(BuildContext context) {
    final palette = context.runNowPalette;
    return GameTimeColors(
      panel: palette.background,
      ink: palette.ink,
      faint: palette.textMuted,
      danger: Theme.of(context).colorScheme.error,
      on: palette.accent,
      onInk: palette.onAccent,
      cell: palette.glassStart,
      cellNight: palette.tint,
      border: palette.border,
    );
  }

  /// Màu của bàn chơi Ma Sói.
  factory GameTimeColors.table(RunNowMoonlit m) => GameTimeColors(
    panel: m.panel,
    ink: m.ink,
    faint: m.faint,
    danger: m.danger,
    on: m.amber,
    onInk: m.onAmber,
    cell: m.raised,
    cellNight: m.lifted,
    border: m.border,
  );

  final Color panel;
  final Color ink;
  final Color faint;
  final Color danger;

  /// Nền ô đang chọn và chữ trên nền đó.
  final Color on;
  final Color onInk;
  final Color cell;

  /// Nền ô giờ tối (18h–6h).
  final Color cellNight;
  final Color border;
}

/// Một lựa chọn nhanh: [day] ngày tính từ hôm nay, lúc [hour]:[minute].
typedef GameTimeQuick = ({String label, int day, int hour, int minute});

/// Thời gian còn lại tới [at], kiểu "còn 1 ngày 3 tiếng"; dưới một tiếng thì
/// tính phút.
String gameUntil(DateTime at, DateTime now) {
  var m = (at.difference(now).inSeconds / 60).round();
  if (m <= 0) return 'đã qua';
  final days = m ~/ 1440;
  m -= days * 1440;
  final hours = m ~/ 60;
  final parts = [
    if (days > 0) '$days ngày',
    if (hours > 0) '$hours tiếng',
    if (days == 0 && hours == 0) '$m phút',
  ];
  return 'còn ${parts.join(' ')}';
}

const _weekdays = ['CN', 'T2', 'T3', 'T4', 'T5', 'T6', 'T7'];

/// "Thứ 7, 08/11", "Chủ nhật, 09/11".
String gameDayLabel(DateTime d) {
  final w = d.weekday % 7;
  final name = w == 0 ? 'Chủ nhật' : 'Thứ ${w + 1}';
  return '$name, ${_two(d.day)}/${_two(d.month)}';
}

String _two(int v) => v.toString().padLeft(2, '0');

/// Kết quả sheet hạn đăng ký: `at` null là không đặt hạn. Sheet đóng mà không
/// chọn thì trả null.
typedef GameDeadlinePick = ({DateTime? at});

/// Sheet chọn ngày giờ (hạn đóng đăng ký, giờ chia bài): chọn nhanh, [days]
/// ngày tới, giờ, phút. Giờ không sau [after] (mặc định lúc này) thì mờ và không
/// bấm Xong được. [noneLabel] null thì nút trái là Huỷ, đóng sheet trả null.
/// [quick] null thì dùng ba mốc buổi tối của ván Ma Sói.
Future<GameDeadlinePick?> showGameDeadlineSheet(
  BuildContext context, {
  DateTime? initial,
  DateTime? now,
  String title = 'Đóng đăng ký',
  DateTime? after,
  String? noneLabel = 'Không đặt hạn',
  int days = 14,
  List<GameTimeQuick>? quick,
  GameTimeColors? colors,
}) {
  colors ??= GameTimeColors.table(context.moonlit);
  final c = colors;
  return showModalBottomSheet<GameDeadlinePick>(
    context: context,
    isScrollControlled: true,
    backgroundColor: c.panel,
    showDragHandle: true,
    builder: (context) => _DeadlineSheet(
      initial: initial,
      now: now ?? DateTime.now(),
      title: title,
      after: after,
      noneLabel: noneLabel,
      days: days,
      quick: quick,
      colors: c,
    ),
  );
}

class _DeadlineSheet extends StatefulWidget {
  const _DeadlineSheet({
    required this.initial,
    required this.now,
    required this.title,
    required this.after,
    required this.noneLabel,
    required this.days,
    required this.quick,
    required this.colors,
  });

  final DateTime? initial;
  final DateTime now;
  final String title;
  final DateTime? after;
  final String? noneLabel;
  final int days;
  final List<GameTimeQuick>? quick;
  final GameTimeColors colors;

  @override
  State<_DeadlineSheet> createState() => _DeadlineSheetState();
}

class _DeadlineSheetState extends State<_DeadlineSheet> {
  int get _days => widget.days;
  late int _day;
  late int _hour;
  late int _minute;

  DateTime get _today =>
      DateTime(widget.now.year, widget.now.month, widget.now.day);

  DateTime _at(int day, int hour, int minute) =>
      DateTime(_today.year, _today.month, _today.day + day, hour, minute);

  bool _past(DateTime at) => !at.isAfter(widget.now);

  bool _early(DateTime at) =>
      _past(at) || (widget.after != null && !at.isAfter(widget.after!));

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    final day = initial == null
        ? -1
        : DateTime(
            initial.year,
            initial.month,
            initial.day,
          ).difference(_today).inDays;
    if (initial != null && day >= 0 && day < _days) {
      _set(day, initial.hour, initial.minute ~/ 15 * 15);
    } else {
      _set(1, 21, 0);
    }
  }

  void _set(int day, int hour, int minute) {
    _day = day;
    _hour = hour;
    _minute = minute;
  }

  @override
  Widget build(BuildContext context) {
    final at = _at(_day, _hour, _minute);
    final past = _early(at);
    final c = widget.colors;
    final weekend = (6 - widget.now.weekday % 7 + 7) % 7;
    final List<GameTimeQuick> quick =
        widget.quick ??
        [
          (label: 'Tối nay 21h', day: 0, hour: 21, minute: 0),
          (label: 'Mai 21h', day: 1, hour: 21, minute: 0),
          (
            label: 'Cuối tuần 20h',
            day: weekend == 0 ? 7 : weekend,
            hour: 20,
            minute: 0,
          ),
        ];
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            _SheetTitle(widget.title, c),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '${_two(_hour)}:${_two(_minute)}',
                  style: context.runNowPalette.heading(
                    TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w900,
                      color: c.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        gameDayLabel(at),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: c.ink,
                        ),
                      ),
                      Text(
                        !past
                            ? gameUntil(at, widget.now)
                            : _past(at)
                            ? 'Giờ này đã qua'
                            : 'Phải sau giờ đóng đăng ký',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: past ? c.danger : c.faint,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final q in quick)
                  _Pill(
                    colors: c,
                    label: q.label,
                    on: _day == q.day && _hour == q.hour && _minute == q.minute,
                    onTap: _past(_at(q.day, q.hour, q.minute))
                        ? null
                        : () => setState(() => _set(q.day, q.hour, q.minute)),
                  ),
              ],
            ),
            _Label('NGÀY', c),
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _days,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (context, i) {
                  final d = _at(i, 0, 0);
                  return SizedBox(
                    width: 46,
                    child: _Pill(
                      colors: c,
                      dense: true,
                      label: '${d.day}',
                      top: i == 0
                          ? 'NAY'
                          : i == 1
                          ? 'MAI'
                          : _weekdays[d.weekday % 7],
                      on: _day == i,
                      onTap: () => setState(() => _day = i),
                    ),
                  );
                },
              ),
            ),
            _Label('GIỜ', c),
            GameHourGrid(
              colors: c,
              selected: _hour,
              disabled: (h) => _past(_at(_day, h, 45)),
              onSelect: (h) => setState(() => _hour = h),
            ),
            _Label('PHÚT', c),
            Row(
              children: [
                for (final m in const [0, 15, 30, 45]) ...[
                  if (m > 0) const SizedBox(width: 6),
                  Expanded(
                    child: _Pill(
                      colors: c,
                      label: ':${_two(m)}',
                      on: _minute == m,
                      onTap: () => setState(() => _minute = m),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => widget.noneLabel == null
                        ? Navigator.pop<GameDeadlinePick>(context)
                        : Navigator.pop<GameDeadlinePick>(context, (at: null)),
                    child: Text(widget.noneLabel ?? 'Huỷ'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: past
                        ? null
                        : () => Navigator.pop<GameDeadlinePick>(context, (
                            at: at,
                          )),
                    child: const Text('Xong'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Lưới 24 giờ, 6 cột; giờ tối (18h–6h) nền đêm.
class GameHourGrid extends StatelessWidget {
  const GameHourGrid({
    super.key,
    required this.selected,
    required this.disabled,
    required this.onSelect,
    this.colors,
  });

  final GameTimeColors? colors;
  final int selected;
  final bool Function(int hour) disabled;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = this.colors ?? GameTimeColors.table(context.moonlit);
    return GridView.count(
      crossAxisCount: 6,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      childAspectRatio: 1.5,
      children: [
        for (var h = 0; h < 24; h++)
          _Pill(
            colors: colors,
            dense: true,
            label: '${h}h',
            on: h == selected,
            night: h >= 18 || h < 6,
            onTap: disabled(h) ? null : () => onSelect(h),
          ),
      ],
    );
  }
}

/// Thẻ lớn của tab Lịch: icon, nhãn nhỏ, giá trị, một dòng phụ; chạm để đổi.
/// [active] false (chưa đặt gì) thì thẻ tối, icon xám.
class GameScheduleCard extends StatelessWidget {
  const GameScheduleCard({
    super.key,
    required this.icon,
    required this.caption,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.active = true,
  });

  final IconData icon;
  final String caption;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(
      borderRadius: context.runNowPalette.radius(16),
      side: BorderSide(
        color: active ? context.moonlit.amberLine : context.moonlit.border,
      ),
    );
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        gradient: active
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [context.moonlit.amberGlow, context.moonlit.panel],
              )
            : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: active
                        ? context.moonlit.amber
                        : context.moonlit.raised,
                    borderRadius: context.runNowPalette.radius(12),
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: active
                        ? context.moonlit.onAmber
                        : context.moonlit.muted,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        caption,
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.3,
                          fontWeight: FontWeight.w700,
                          color: context.moonlit.faint,
                        ),
                      ),
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: 'Barlow Condensed',
                          fontSize: 22,
                          height: 1.1,
                          letterSpacing: 0.4,
                          fontWeight: FontWeight.w800,
                          color: context.moonlit.ink,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.moonlit.faint,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: context.moonlit.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Số vòng mỗi ngày của ván km: mỗi ô một số vòng kèm độ dài vòng.
class GameRoundsSegments extends StatelessWidget {
  const GameRoundsSegments({
    super.key,
    required this.options,
    required this.selected,
    required this.length,
    required this.onSelect,
  });

  final List<int> options;
  final int selected;

  /// Độ dài vòng hiện dưới số vòng, ví dụ "8h".
  final String Function(int rounds) length;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    final select = onSelect;
    return Row(
      children: [
        for (final n in options) ...[
          if (n != options.first) const SizedBox(width: 6),
          Expanded(
            child: Semantics(
              label: '$n vòng',
              button: true,
              selected: n == selected,
              excludeSemantics: true,
              onTap: select == null ? null : () => select(n),
              child: _Pill(
                label: '$n',
                bottom: length(n),
                on: n == selected,
                onTap: select == null ? null : () => select(n),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.on,
    required this.onTap,
    this.top,
    this.bottom,
    this.night = false,
    this.dense = false,
    this.colors,
  });

  final GameTimeColors? colors;

  final String label;
  final String? top;
  final String? bottom;
  final bool on;
  final bool night;

  /// Ô trong lưới có kích thước sẵn: bớt đệm để chữ không tràn.
  final bool dense;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final c = colors ?? GameTimeColors.table(context.moonlit);
    final fg = on
        ? c.onInk
        : enabled
        ? c.ink
        : c.faint;
    return Opacity(
      opacity: enabled || on ? 1 : 0.4,
      child: Material(
        color: on
            ? c.on
            : night
            ? c.cellNight
            : c.cell,
        shape: RoundedRectangleBorder(
          borderRadius: context.runNowPalette.radius(12),
          side: BorderSide(color: on ? c.on : c.border),
        ),
        child: InkWell(
          borderRadius: context.runNowPalette.radius(12),
          onTap: onTap,
          child: Padding(
            padding: dense
                ? const EdgeInsets.all(2)
                : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (top case final top?)
                  Text(
                    top,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: fg.withValues(alpha: 0.7),
                    ),
                  ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
                if (bottom case final bottom?)
                  Text(
                    bottom,
                    style: TextStyle(
                      fontSize: 11,
                      color: fg.withValues(alpha: 0.75),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle(this.text, this.colors);

  final String text;
  final GameTimeColors colors;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: context.runNowPalette.heading(
        TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: colors.ink),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, this.colors);

  final String text;
  final GameTimeColors colors;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w800,
          color: colors.faint,
        ),
      ),
    );
  }
}
