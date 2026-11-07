import 'package:flutter/material.dart';
import 'package:myrun/src/games/game_models.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/theme_tokens.dart';

// Mảnh giao diện của màn tạo ván theo tab. State và việc gửi lên nằm ở
// GameCreateScreen; ở đây chỉ vẽ theo createOptions backend gửi.

typedef _M = RunNowMoonlitTokens;

/// Icon theo khoá backend gửi cho tab và kiểu ván; khoá lạ thì icon chỉnh.
IconData gameCreateIcon(String key) => switch (key) {
  'clock' => Icons.schedule_rounded,
  'moon' => Icons.nightlight_round,
  'people' => Icons.groups_outlined,
  'vote' => Icons.how_to_vote_outlined,
  'run' => Icons.directions_run_rounded,
  'bolt' => Icons.bolt_rounded,
  _ => Icons.tune_rounded,
};

const _paintedRoles = {'wolf', 'seer', 'guard', 'witch', 'hunter', 'cupid'};

/// Chữ nhãn nhỏ viết hoa của từng khối.
class GameCreateLabel extends StatelessWidget {
  const GameCreateLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: _M.faint,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Link nhỏ "Là gì?", "Xem chi tiết".
class GameCreateLink extends StatelessWidget {
  const GameCreateLink(this.text, {super.key, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: _M.amberBright,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(44, 36),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      ),
      child: Text(text),
    );
  }
}

/// Khung tối viền mảnh của các khối trên màn tạo ván.
class GameCreatePanel extends StatelessWidget {
  const GameCreatePanel({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // Material chứ không phải DecoratedBox để ListTile bên trong vẽ được
    // hiệu ứng chạm.
    return Material(
      color: _M.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: _M.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
        child: child,
      ),
    );
  }
}

/// Một ô kiểu ván dựng sẵn.
class GamePresetTile extends StatelessWidget {
  const GamePresetTile({
    super.key,
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final GamePreset preset;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? _M.amberTint : _M.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? _M.amber : _M.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 12, 6, 10),
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: selected ? _M.amber : _M.raised,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    gameCreateIcon(preset.icon),
                    size: 24,
                    color: selected ? _M.onAmber : _M.muted,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  preset.label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: selected ? _M.amberLight : _M.inkSoft,
                  ),
                ),
                if (preset.isDefault) ...[
                  const SizedBox(height: 2),
                  const Text(
                    'Mặc định',
                    style: TextStyle(fontSize: 11, color: _M.faint),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Thanh tab của phần Tuỳ chỉnh: icon trên, chữ dưới, cả hàng vừa một màn.
class GameCreateTabBar extends StatelessWidget {
  const GameCreateTabBar({
    super.key,
    required this.groups,
    required this.selected,
    required this.onSelect,
  });

  final List<GameSettingGroup> groups;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _M.raised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _M.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < groups.length; i++)
            Expanded(
              child: Semantics(
                selected: i == selected,
                button: true,
                child: Material(
                  color: i == selected ? _M.amberTint : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => onSelect(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          Icon(
                            gameCreateIcon(groups[i].icon),
                            size: 18,
                            color: i == selected ? _M.amberBright : _M.faint,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            groups[i].label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: i == selected ? _M.amberBright : _M.faint,
                            ),
                          ),
                        ],
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

/// Ô ghi chú nền tối có icon, cho câu giải thích ngắn trong tab.
class GameCreateNote extends StatelessWidget {
  const GameCreateNote({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _M.raised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _M.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: _M.amberBright),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: _M.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Một dòng tuỳ chọn số: tên bên trái, nút −/+ bên phải.
class GameCreateStepper extends StatelessWidget {
  const GameCreateStepper({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    this.unit,
    this.hint,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final String? unit;
  final String? hint;

  /// null thì không bấm được.
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final change = onChanged;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: _M.ink,
                ),
              ),
              if (hint case final hint?)
                Text(
                  hint,
                  style: const TextStyle(fontSize: 12, color: _M.faint),
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Giảm $label',
          icon: const Icon(Icons.remove_rounded),
          color: _M.amberBright,
          onPressed: change != null && value - step >= min - 1e-9
              ? () => change(gameSnap(value - step))
              : null,
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 56),
          child: Text(
            unit == null
                ? gameFormatNumber(value)
                : '${gameFormatNumber(value)} $unit',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: _M.ink,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Tăng $label',
          icon: const Icon(Icons.add_rounded),
          color: _M.amberBright,
          onPressed: change != null && value + step <= max + 1e-9
              ? () => change(gameSnap(value + step))
              : null,
        ),
      ],
    );
  }
}

/// Danh sách lựa chọn của một tuỳ chọn kiểu choice; lựa chọn đang chọn viền vàng.
class GameCreateChoices extends StatelessWidget {
  const GameCreateChoices({
    super.key,
    required this.setting,
    required this.value,
    required this.onChanged,
  });

  final GameSetting setting;
  final Object? value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final choice in setting.choices) ...[
          Semantics(
            selected: choice.value == value,
            button: true,
            child: Material(
              color: choice.value == value ? _M.amberTint : _M.raised,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: choice.value == value ? _M.amber : _M.border,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onChanged == null
                    ? null
                    : () => onChanged!(choice.value),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              choice.label,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: _M.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              choice.description,
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: _M.faint,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (choice.value == value)
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 20,
                          color: _M.amber,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// Ô vai trong lưới vai: chạm để bật tắt.
/// Thẻ bật tắt thu gọn của một khối tuỳ chọn (như đặc quyền phe Sói): tên,
/// nhãn ngắn, dấu "ĐỂ LỘ" khi có cảnh báo; mở ra thì xem mô tả và cảnh báo.
class GamePowerCard extends StatefulWidget {
  const GamePowerCard({
    super.key,
    required this.setting,
    required this.on,
    required this.onChanged,
  });

  final GameSetting setting;
  final bool on;
  final ValueChanged<bool>? onChanged;

  @override
  State<GamePowerCard> createState() => _GamePowerCardState();
}

class _GamePowerCardState extends State<GamePowerCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.setting;
    final on = widget.on;
    final change = widget.onChanged;
    final warn = s.warn;
    final meta = [
      if (s.hint case final hint? when hint.isNotEmpty) hint.toUpperCase(),
      if (warn != null && warn.isNotEmpty) '⚠ ĐỂ LỘ',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: on ? _M.amberTint : _M.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: on ? _M.amber : _M.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    toggled: on,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: change == null ? null : () => change(!on),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                        child: Row(
                          children: [
                            Icon(
                              on
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              size: 22,
                              color: on ? _M.amber : _M.faint,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.label,
                                    style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w800,
                                      color: _M.ink,
                                    ),
                                  ),
                                  if (meta.isNotEmpty)
                                    Text(
                                      meta,
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        letterSpacing: 0.8,
                                        fontWeight: FontWeight.w800,
                                        color: _M.faint,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _open ? 'Thu gọn ${s.label}' : 'Xem ${s.label}',
                  icon: Icon(
                    _open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                  ),
                  color: _M.faint,
                  onPressed: () => setState(() => _open = !_open),
                ),
              ],
            ),
            if (_open)
              Padding(
                padding: const EdgeInsets.fromLTRB(44, 0, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.description,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: _M.muted,
                      ),
                    ),
                    if (warn != null && warn.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        warn,
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: _M.danger,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class GameRoleChip extends StatelessWidget {
  const GameRoleChip({
    super.key,
    required this.role,
    required this.label,
    required this.on,
    required this.onTap,
  });

  final String role;
  final String label;
  final bool on;

  /// null với vai luôn có (Sói) hoặc lúc đang gửi.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = on ? _M.amberBright : _M.faint;
    return Semantics(
      toggled: on,
      button: onTap != null,
      child: Material(
        color: on ? _M.amberTint : _M.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: on ? _M.amberLine : _M.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Column(
              children: [
                SizedBox.square(
                  dimension: 24,
                  child: _paintedRoles.contains(role)
                      ? CustomPaint(painter: GameRoleIconPainter(role, color))
                      : Icon(_roleIcon(role), size: 22, color: color),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: on ? _M.ink : _M.faint,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static IconData _roleIcon(String role) => switch (role) {
    'elder' => Icons.elderly_rounded,
    'idiot' => Icons.sentiment_very_satisfied_rounded,
    _ => Icons.person_outline_rounded,
  };
}

/// Diễn biến một vòng: thanh bốn pha và giờ từng pha theo giờ mở và độ dài vòng.
class GameRoundTimeline extends StatelessWidget {
  const GameRoundTimeline({
    super.key,
    required this.plan,
    required this.startHour,
    required this.roundHours,
  });

  final GameRoundPlan plan;
  final double startHour;
  final double roundHours;

  /// Mốc h của vòng gốc 24 tiếng, đổi ra giờ trong ngày.
  String _at(double h) => gameClock(startHour * 60 + h * roundHours * 60 / 24);

  @override
  Widget build(BuildContext context) {
    final phases = plan.phases;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 8,
            child: Row(
              children: [
                for (final p in phases)
                  Expanded(
                    flex: ((p.to - p.from) * 10).round().clamp(1, 1000),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      color: gamePhaseColor(p.key),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (final p in phases) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 5, right: 10),
                decoration: BoxDecoration(
                  color: gamePhaseColor(p.key),
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: p.label,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: _M.ink,
                            ),
                          ),
                          TextSpan(
                            text: '  ${_at(p.from)} – ${_at(p.to)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _M.amberBright,
                            ),
                          ),
                        ],
                      ),
                      style: const TextStyle(fontSize: 13.5),
                    ),
                    Text(
                      p.description,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: _M.faint,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        if (plan.reminders.isNotEmpty)
          Text(
            plan.reminders
                .map((m) => '${m.label} lúc ${_at(m.at)}')
                .join(' · '),
            style: const TextStyle(fontSize: 12, color: _M.muted),
          ),
      ],
    );
  }
}

/// Màu của pha theo khoá backend gửi; khoá lạ thì màu thanh thấp.
Color gamePhaseColor(String key) => switch (key) {
  'night' => _M.phaseNight,
  'dawn' => _M.phaseDawn,
  'day' => _M.phaseDay,
  'trial' => _M.phaseTrial,
  _ => _M.barLow,
};

/// Sheet giải thích: tiêu đề và các mục (tên, mô tả).
Future<void> showGameCreateSheet(
  BuildContext context, {
  required String title,
  required List<(String, String)> items,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _M.panel,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: _M.ink,
              ),
            ),
            const SizedBox(height: 12),
            for (final (name, text) in items) ...[
              if (name.isNotEmpty)
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: _M.amberLight,
                  ),
                ),
              Text(
                text,
                style: const TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: _M.muted,
                ),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Giờ trong ngày từ số phút, kiểu "22h", "6h30".
String gameClock(double minutes) {
  final m = (minutes.round() % 1440 + 1440) % 1440;
  final h = m ~/ 60, mm = m % 60;
  return mm == 0 ? '${h}h' : '${h}h${mm.toString().padLeft(2, '0')}';
}

/// Cộng trừ số lẻ như 0.5 cộng dồn sai số; làm tròn để gửi đúng bước.
double gameSnap(double v) => (v * 1000).roundToDouble() / 1000;

String gameFormatNumber(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();
