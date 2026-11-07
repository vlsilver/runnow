import 'package:flutter/material.dart';
import 'package:myrun/src/theme_tokens.dart';

// Chọn giờ cho màn tạo ván: hạn đóng đăng ký (ngày, giờ, phút) và giờ mở vòng
// đầu (lưới 24 giờ), cùng thẻ và ô chọn số vòng của tab Lịch.

typedef _M = RunNowMoonlitTokens;

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

/// Sheet hạn đóng đăng ký: chọn nhanh, 14 ngày tới, giờ, phút. Giờ đã qua thì
/// mờ và không bấm Xong được.
Future<GameDeadlinePick?> showGameDeadlineSheet(
  BuildContext context, {
  DateTime? initial,
  DateTime? now,
}) {
  return showModalBottomSheet<GameDeadlinePick>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _M.panel,
    showDragHandle: true,
    builder: (context) =>
        _DeadlineSheet(initial: initial, now: now ?? DateTime.now()),
  );
}

class _DeadlineSheet extends StatefulWidget {
  const _DeadlineSheet({required this.initial, required this.now});

  final DateTime? initial;
  final DateTime now;

  @override
  State<_DeadlineSheet> createState() => _DeadlineSheetState();
}

class _DeadlineSheetState extends State<_DeadlineSheet> {
  static const _days = 14;
  late int _day;
  late int _hour;
  late int _minute;

  DateTime get _today =>
      DateTime(widget.now.year, widget.now.month, widget.now.day);

  DateTime _at(int day, int hour, int minute) =>
      DateTime(_today.year, _today.month, _today.day + day, hour, minute);

  bool _past(DateTime at) => !at.isAfter(widget.now);

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
    final past = _past(at);
    final weekend = (6 - widget.now.weekday % 7 + 7) % 7;
    final quick = [
      ('Tối nay 21h', 0, 21),
      ('Mai 21h', 1, 21),
      ('Cuối tuần 20h', weekend == 0 ? 7 : weekend, 20),
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
            const _SheetTitle('Đóng đăng ký'),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '${_two(_hour)}:${_two(_minute)}',
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: _M.ink,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        gameDayLabel(at),
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _M.ink,
                        ),
                      ),
                      Text(
                        past ? 'Giờ này đã qua' : gameUntil(at, widget.now),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: past ? _M.danger : _M.faint,
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
                for (final (label, day, hour) in quick)
                  _Pill(
                    label: label,
                    on: _day == day && _hour == hour && _minute == 0,
                    onTap: _past(_at(day, hour, 0))
                        ? null
                        : () => setState(() => _set(day, hour, 0)),
                  ),
              ],
            ),
            const _Label('NGÀY'),
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
            const _Label('GIỜ'),
            GameHourGrid(
              selected: _hour,
              disabled: (h) => _past(_at(_day, h, 45)),
              onSelect: (h) => setState(() => _hour = h),
            ),
            const _Label('PHÚT'),
            Row(
              children: [
                for (final m in const [0, 15, 30, 45]) ...[
                  if (m > 0) const SizedBox(width: 6),
                  Expanded(
                    child: _Pill(
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
                    onPressed: () =>
                        Navigator.pop<GameDeadlinePick>(context, (at: null)),
                    child: const Text('Không đặt hạn'),
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

/// Sheet chọn giờ mở vòng đầu trên lưới 24 giờ; đóng mà không chọn thì null.
Future<int?> showGameHourSheet(
  BuildContext context, {
  required String title,
  required int hour,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _M.panel,
    showDragHandle: true,
    builder: (context) => _HourSheet(title: title, hour: hour),
  );
}

class _HourSheet extends StatefulWidget {
  const _HourSheet({required this.title, required this.hour});

  final String title;
  final int hour;

  @override
  State<_HourSheet> createState() => _HourSheetState();
}

class _HourSheetState extends State<_HourSheet> {
  late int _hour = widget.hour;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SheetTitle(widget.title),
            const SizedBox(height: 8),
            Text(
              '${_hour}h',
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w900,
                color: _M.ink,
              ),
            ),
            const SizedBox(height: 8),
            GameHourGrid(
              selected: _hour,
              disabled: (_) => false,
              onSelect: (h) => setState(() => _hour = h),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop<int>(context),
                    child: const Text('Huỷ'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop<int>(context, _hour),
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
  });

  final int selected;
  final bool Function(int hour) disabled;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
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
class GameScheduleCard extends StatelessWidget {
  const GameScheduleCard({
    super.key,
    required this.icon,
    required this.caption,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String caption;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _M.raised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: _M.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, color: _M.amberBright),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      caption,
                      style: const TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w800,
                        color: _M.faint,
                      ),
                    ),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _M.ink,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: _M.faint),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _M.faint),
            ],
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
  });

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
    final fg = on
        ? _M.onAmber
        : enabled
        ? _M.ink
        : _M.faint;
    return Opacity(
      opacity: enabled || on ? 1 : 0.4,
      child: Material(
        color: on
            ? _M.amber
            : night
            ? _M.lifted
            : _M.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: on ? _M.amber : _M.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
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
  const _SheetTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w900,
        color: _M.ink,
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10.5,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w800,
          color: _M.faint,
        ),
      ),
    );
  }
}
