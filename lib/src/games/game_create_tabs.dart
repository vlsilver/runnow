import 'package:flutter/material.dart';
import 'package:myrun/src/games/game_card_art.dart';
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
  'cloak' => Icons.visibility_off_outlined,
  'frame' => Icons.theater_comedy_outlined,
  'silent' => Icons.volume_off_outlined,
  'pierce' => Icons.shield_outlined,
  _ => Icons.tune_rounded,
};

const _paintedRoles = {'wolf', 'seer', 'guard', 'witch', 'hunter', 'cupid'};

/// Icon theo khoá backend gửi, gồm cả vai: vai có tranh vẽ thì vẽ bằng
/// [GameRoleIconPainter], còn lại theo [gameCreateIcon].
Widget gameKeyIcon(String key, {required Color color, double size = 20}) {
  if (_paintedRoles.contains(key)) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: GameRoleIconPainter(key, color)),
    );
  }
  return Icon(gameCreateIcon(key), size: size, color: color);
}

/// Đầu màn tạo ván: emblem trăng, tên hai dòng và dòng phụ.
class GameCreateHeader extends StatelessWidget {
  const GameCreateHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        GameMoonEmblem(size: 72),
        SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MỞ VÁN\nMA SÓI',
                style: TextStyle(
                  fontFamily: 'Barlow Condensed',
                  fontWeight: FontWeight.w800,
                  fontSize: 32,
                  height: .95,
                  letterSpacing: .6,
                  color: _M.ink,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Chọn kiểu ván, hẹn giờ, mở.',
                style: TextStyle(fontSize: 13, color: _M.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Nút mở ván ghim dưới màn: nền hổ phách, icon trăng.
class GameCreateOpenButton extends StatelessWidget {
  const GameCreateOpenButton({
    super.key,
    required this.working,
    required this.onPressed,
  });

  final bool working;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_M.amberBright, _M.amber],
        ),
        boxShadow: const [
          BoxShadow(color: _M.ctaGlow, blurRadius: 30, offset: Offset(0, 10)),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onPressed,
          child: SizedBox(
            height: 56,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.nightlight_round, size: 20, color: _M.onAmber),
                const SizedBox(width: 8),
                Text(
                  working ? 'ĐANG MỞ…' : 'MỞ VÁN',
                  style: const TextStyle(
                    fontFamily: 'Barlow Condensed',
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    letterSpacing: 3,
                    color: _M.onAmber,
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

/// Dòng gọn có icon, nhãn, giá trị và mũi tên; chạm để mở sheet chỉnh.
class GameCreateRow extends StatelessWidget {
  const GameCreateRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _M.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: _M.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _M.amberTint,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: _M.amberBright),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _M.ink,
                  ),
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: _M.amberBright,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: _M.faint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chữ nhãn nhỏ viết hoa của từng khối.
class GameCreateLabel extends StatelessWidget {
  const GameCreateLabel(
    this.text, {
    super.key,
    this.trailing,
    this.leading,
    this.color = _M.faint,
  });

  final String text;
  final Widget? trailing;
  final Widget? leading;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (leading case final l?) ...[l, const SizedBox(width: 6)],
        Expanded(
          child: Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.4,
              color: color,
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
    // Kiểu ván không chạy (icon trăng) sáng bạc lam, còn lại hổ phách.
    final moon = preset.icon == 'moon';
    final accent = moon ? _M.moon : _M.amber;
    final tile = Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? (moon ? _M.moonTint : _M.amberTint) : _M.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? accent : _M.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 14, 6, 12),
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: selected ? accent : _M.raised,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    gameCreateIcon(preset.icon),
                    size: 24,
                    color: selected
                        ? (moon ? _M.onMoon : _M.onAmber)
                        : _M.muted,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  preset.label.toUpperCase(),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    fontFamily: 'Barlow Condensed',
                    fontSize: 16,
                    height: 1,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w800,
                    color: selected ? _M.ink : _M.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!preset.isDefault) return tile;
    // Nhãn mặc định nằm vắt trên mép ô như board.
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.passthrough,
      alignment: Alignment.topCenter,
      children: [
        tile,
        Positioned(
          top: -8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: _M.amber,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'MẶC ĐỊNH',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
                color: _M.onAmber,
              ),
            ),
          ),
        ),
      ],
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

/// Ô viền đứt cho lựa chọn "chủ phòng tự làm": không có gì để chỉnh.
class GameCreateManual extends StatelessWidget {
  const GameCreateManual({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: const _DashedBorder(color: _M.border, radius: 14),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: _M.raised,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 20, color: _M.muted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 13, color: _M.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ).deflate(0.6),
      );
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) =>
      old.color != color || old.radius != radius;
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
    final hint = s.hint;
    final hasHint = hint != null && hint.isNotEmpty;
    final exposes = warn != null && warn.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: on ? _M.wolfSoft : _M.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: on ? _M.wolfLine : _M.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              toggled: on,
              child: InkWell(
                onTap: change == null ? null : () => change(!on),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _M.well,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: gameKeyIcon(
                          s.icon ?? 'wolf',
                          color: on ? _M.wolf : _M.faint,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: on ? _M.ink : _M.muted,
                              ),
                            ),
                            if (hasHint || exposes)
                              Text.rich(
                                TextSpan(
                                  children: [
                                    if (hasHint)
                                      TextSpan(text: hint.toUpperCase()),
                                    if (hasHint && exposes)
                                      const TextSpan(text: ' · '),
                                    if (exposes)
                                      const TextSpan(
                                        text: '⚠ ĐỂ LỘ',
                                        style: TextStyle(color: _M.phaseTrial),
                                      ),
                                  ],
                                ),
                                style: const TextStyle(
                                  fontSize: 11,
                                  letterSpacing: 0.55,
                                  fontWeight: FontWeight.w700,
                                  color: _M.faint,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: on ? _M.wolf : null,
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: on ? _M.wolf : _M.border,
                            width: 1.5,
                          ),
                        ),
                        child: on
                            ? const Icon(
                                Icons.check_rounded,
                                size: 16,
                                color: _M.ink,
                              )
                            : null,
                      ),
                      IconButton(
                        tooltip: _open
                            ? 'Thu gọn ${s.label}'
                            : 'Xem ${s.label}',
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
                ),
              ),
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
    'villager' => Icons.people_outline_rounded,
    _ => Icons.person_outline_rounded,
  };
}

/// Hai hay vài lựa chọn nằm ngang, ô đang chọn tô vàng.
class GameCreateSegment extends StatelessWidget {
  const GameCreateSegment({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelect,
    this.subs,
  });

  final List<String> labels;

  /// Dòng nhỏ dưới từng nhãn, cùng thứ tự với [labels]; null thì một dòng.
  final List<String>? subs;
  final int selected;

  /// null thì không bấm được.
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    final select = onSelect;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _M.raised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _M.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                selected: i == selected,
                button: true,
                child: Material(
                  color: i == selected ? _M.amber : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: select == null || i == selected
                        ? null
                        : () => select(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            labels[i],
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: i == selected ? _M.onAmber : _M.muted,
                            ),
                          ),
                          if (subs case final subs?)
                            Text(
                              subs[i],
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: i == selected ? _M.onAmber : _M.faint,
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

/// Bảng chia chuẩn theo số người, ô chứa [players] sáng lên.
class GameDeckTiers extends StatelessWidget {
  const GameDeckTiers({super.key, required this.plan, required this.players});

  final GameDeckPlan plan;
  final int players;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 8.0;
        final width = (box.maxWidth - gap * 2) / 3;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final t in plan.tiers)
              SizedBox(
                width: width,
                child: _tier(t, players >= t.from && players <= t.to),
              ),
          ],
        );
      },
    );
  }

  Widget _tier(({int from, int to, int wolves, int specials}) t, bool on) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: on ? _M.amberTint : _M.raised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: on ? _M.amberLine : _M.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${t.from == t.to ? t.from : '${t.from}–${t.to}'} người',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: on ? _M.amberBright : _M.ink,
            ),
          ),
          Text(
            '${t.wolves} sói · ${t.specials} vai',
            style: const TextStyle(fontSize: 11.5, color: _M.faint),
          ),
        ],
      ),
    );
  }
}

/// Một vai trong bộ bài: icon, tên, số lá; có [onAdd]/[onRemove] thì hiện nút
/// −/+ cạnh số. Vai 0 lá vẽ mờ.
class GameDeckTile extends StatelessWidget {
  const GameDeckTile({
    super.key,
    required this.role,
    required this.label,
    required this.count,
    this.onAdd,
    this.onRemove,
    this.editable = false,
  });

  final String role;
  final String label;
  final int count;
  final VoidCallback? onAdd;
  final VoidCallback? onRemove;

  /// Vẽ nút −/+ (nút không bấm được khi callback null).
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final on = count > 0;
    final wolf = role == 'wolf';
    final color = !on
        ? _M.faint.withValues(alpha: 0.5)
        : wolf
        ? _M.wolf
        : _M.amberBright;
    Widget button(String tip, IconData icon, VoidCallback? tap) => SizedBox(
      width: 22,
      height: 22,
      child: IconButton(
        tooltip: '$tip $label',
        padding: EdgeInsets.zero,
        iconSize: 14,
        icon: Icon(icon),
        color: _M.amberBright,
        disabledColor: _M.faint.withValues(alpha: 0.4),
        onPressed: tap,
      ),
    );
    final number = Text(
      '$count',
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        color: on ? _M.ink : _M.faint,
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 8),
      decoration: BoxDecoration(
        color: !on
            ? Colors.transparent
            : wolf
            ? _M.wolfSoft
            : _M.amberTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: !on
              ? _M.border
              : wolf
              ? _M.wolfLine
              : _M.amberLine,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? _M.well : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: SizedBox.square(
              dimension: 20,
              child: _paintedRoles.contains(role)
                  ? CustomPaint(painter: GameRoleIconPainter(role, color))
                  : Icon(GameRoleChip._roleIcon(role), size: 19, color: color),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: on ? _M.ink : _M.faint,
            ),
          ),
          const SizedBox(height: 2),
          if (editable)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                button('Bớt', Icons.remove_rounded, onRemove),
                const SizedBox(width: 4),
                number,
                const SizedBox(width: 4),
                button('Thêm', Icons.add_rounded, onAdd),
              ],
            )
          else
            SizedBox(height: 22, child: Center(child: number)),
        ],
      ),
    );
  }
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
