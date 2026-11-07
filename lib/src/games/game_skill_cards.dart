import 'package:flutter/material.dart';
import 'package:myrun/src/games/game_create_tabs.dart';
import 'package:myrun/src/games/game_models.dart';
import 'package:myrun/src/theme_tokens.dart';

// Thẻ của tab Kỹ năng: chế độ dùng kỹ năng (lựa chọn có Chi tiết) và thẻ km
// mỗi lượt (icon, tên, nhãn ngắn, nút −/+ hoặc công tắc, dòng con). Vẽ theo
// icon, hint, parent backend gửi.

typedef _M = RunNowMoonlitTokens;

/// Ký tự thay icon cho các khoá là con số hay phép tính.
String? _glyph(String key) => switch (key) {
  'sum' => 'Σ',
  'one' => '1',
  _ => null,
};

Widget _iconBox(
  String key, {
  required Color color,
  required Color background,
  double box = 36,
}) {
  final glyph = _glyph(key);
  return Container(
    width: box,
    height: box,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(box * 0.3),
    ),
    child: glyph != null
        ? Text(
            glyph,
            style: TextStyle(
              fontSize: box * 0.52,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          )
        : gameKeyIcon(key, color: color, size: box * 0.5),
  );
}

class _DetailLink extends StatelessWidget {
  const _DetailLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Chi tiết $label',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Text(
            'Chi tiết',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _M.amber,
            ),
          ),
        ),
      ),
    );
  }
}

/// Sheet Chi tiết: mỗi mục một icon, tên đậm và đoạn giải thích.
Future<void> showGameDetailSheet(
  BuildContext context, {
  required String title,
  required List<GameSettingDetail> items,
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
            const SizedBox(height: 14),
            for (final d in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _iconBox(
                      d.icon,
                      color: d.icon == 'wolf' ? _M.phaseTrial : _M.amber,
                      background: _M.well,
                      box: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            d.title,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: _M.ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            d.text,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 1.5,
                              color: _M.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Lựa chọn của một tuỳ chọn kiểu choice dạng thẻ: ký hiệu, tên, nhãn ngắn và
/// nút Chi tiết. Ký hiệu lấy từ icon của mục chi tiết đầu tiên.
class GameModeCards extends StatelessWidget {
  const GameModeCards({
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
        for (final c in setting.choices)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _card(context, c, c.value == value),
          ),
      ],
    );
  }

  Widget _card(BuildContext context, GameSettingChoice c, bool on) {
    final change = onChanged;
    final glyph = c.details.isEmpty ? 'vote' : c.details.first.icon;
    return Semantics(
      selected: on,
      child: Material(
        color: on ? _M.amberTint : _M.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: on ? _M.amber : _M.border),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: change == null ? null : () => change(c.value),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      children: [
                        _iconBox(
                          glyph,
                          color: on ? _M.onAmber : _M.muted,
                          background: on ? _M.amber : _M.well,
                          box: 40,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.label,
                                style: const TextStyle(
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                  color: _M.ink,
                                ),
                              ),
                              Text(
                                c.hint ?? c.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
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
              _DetailLink(
                label: c.label,
                onTap: () => showGameDetailSheet(
                  context,
                  title: c.label,
                  items: c.details.isNotEmpty
                      ? c.details
                      : [
                          GameSettingDetail(
                            icon: glyph,
                            title: c.label,
                            text: c.description,
                          ),
                        ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thiết lập ván đang áp, đọc lại giữa ván: các khối như màn tạo ván, dòng
/// có icon như thẻ kỹ năng, dòng con thụt vào dưới dòng cha.
Future<void> showGameSetupSheet(
  BuildContext context,
  List<GameSetupSection> sections,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: _M.panel,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            const Text(
              'Thiết lập ván',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: _M.ink,
              ),
            ),
            for (final section in sections) ...[
              const SizedBox(height: 18),
              Text(
                section.title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w800,
                  color: _M.faint,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: _M.raised,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _M.border),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    for (final (i, item) in section.items.indexed) ...[
                      if (i > 0 && !item.sub)
                        const Divider(height: 1, color: _M.divider),
                      _SetupRow(item),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

class _SetupRow extends StatelessWidget {
  const _SetupRow(this.item);

  final GameSetupItem item;

  @override
  Widget build(BuildContext context) {
    final sub = item.sub;
    return Padding(
      padding: EdgeInsets.fromLTRB(sub ? 40 : 0, sub ? 0 : 10, 0, 10),
      child: Row(
        children: [
          if (!sub) ...[
            if (item.icon.isNotEmpty)
              _iconBox(
                item.icon,
                color: item.icon == 'wolf' ? _M.phaseTrial : _M.amber,
                background: _M.well,
                box: 28,
              )
            else
              const SizedBox(width: 28),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              item.label,
              style: TextStyle(
                fontSize: sub ? 13 : 14.5,
                fontWeight: sub ? FontWeight.w600 : FontWeight.w700,
                color: sub ? _M.muted : _M.ink,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            item.value,
            style: TextStyle(
              fontSize: sub ? 13 : 14.5,
              fontWeight: FontWeight.w800,
              color: _M.amberBright,
            ),
          ),
        ],
      ),
    );
  }
}

/// Nút −/+ gọn trong khung viền, số ở giữa kèm đơn vị nhỏ.
class GameSkillStepper extends StatelessWidget {
  const GameSkillStepper({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    this.unit,
    this.small = false,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final String? unit;
  final bool small;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final change = onChanged;
    final size = small ? 32.0 : 36.0;
    Widget button(String tip, IconData icon, double next, bool ok) =>
        SizedBox.square(
          dimension: size,
          child: IconButton(
            tooltip: '$tip $label',
            padding: EdgeInsets.zero,
            iconSize: small ? 16 : 18,
            icon: Icon(icon),
            color: _M.amberBright,
            disabledColor: _M.faint.withValues(alpha: 0.4),
            onPressed: change != null && ok
                ? () => change(gameSnap(next))
                : null,
          ),
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _M.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _M.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(
            'Giảm',
            Icons.remove_rounded,
            value - step,
            value - step >= min - 1e-9,
          ),
          ConstrainedBox(
            constraints: BoxConstraints(minWidth: small ? 48 : 58),
            child: Text.rich(
              TextSpan(
                text: gameFormatNumber(value),
                style: TextStyle(
                  fontSize: small ? 16 : 18,
                  fontWeight: FontWeight.w800,
                  color: _M.ink,
                ),
                children: [
                  if (unit case final unit?)
                    TextSpan(
                      text: ' $unit',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _M.faint,
                      ),
                    ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
          button(
            'Tăng',
            Icons.add_rounded,
            value + step,
            value + step <= max + 1e-9,
          ),
        ],
      ),
    );
  }
}

/// Thẻ một tuỳ chọn có icon: icon, tên, nhãn ngắn kèm Chi tiết, bên phải là
/// [trailing] (nút −/+ hay công tắc); [children] là các dòng con. [warn] hiện
/// khi tuỳ chọn đang có tác dụng.
class GameSkillCard extends StatelessWidget {
  const GameSkillCard({
    super.key,
    required this.setting,
    required this.trailing,
    this.warn,
    this.children = const [],
  });

  final GameSetting setting;
  final Widget trailing;
  final String? warn;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final s = setting;
    final icon = s.icon ?? 'tune';
    final hint = s.hint;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        decoration: BoxDecoration(
          color: _M.raised,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _M.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                _iconBox(
                  icon,
                  color: icon == 'wolf' ? _M.phaseTrial : _M.amber,
                  background: _M.well,
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
                      // Hint dài xuống dòng, "Chi tiết" chạy liền sau.
                      Text.rich(
                        TextSpan(
                          style: const TextStyle(fontSize: 12, color: _M.faint),
                          children: [
                            if (hint != null && hint.isNotEmpty)
                              TextSpan(text: '$hint '),
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: _DetailLink(
                                label: s.label,
                                onTap: () => showGameDetailSheet(
                                  context,
                                  title: s.label,
                                  items: [
                                    GameSettingDetail(
                                      icon: icon,
                                      title: s.label,
                                      text: switch (s.warn) {
                                        final w? when w.isNotEmpty =>
                                          '${s.description}\n\n⚠ $w',
                                        _ => s.description,
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                trailing,
              ],
            ),
            for (final c in children) ...[const SizedBox(height: 8), c],
            if (warn case final w? when w.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '⚠ $w',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: _M.phaseTrial,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Dòng con trong thẻ kỹ năng: tên nhỏ (kèm nhãn ngắn) và nút −/+ gọn.
class GameSkillSubLine extends StatelessWidget {
  const GameSkillSubLine({
    super.key,
    required this.setting,
    required this.value,
    required this.onChanged,
  });

  final GameSetting setting;
  final double value;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final s = setting;
    return Padding(
      padding: const EdgeInsets.only(left: 46),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.label,
                  style: const TextStyle(fontSize: 13, color: _M.muted),
                ),
                if (s.hint case final h? when h.isNotEmpty)
                  Text(
                    h,
                    style: const TextStyle(fontSize: 11.5, color: _M.faint),
                  ),
              ],
            ),
          ),
          GameSkillStepper(
            label: s.label,
            value: value,
            min: s.min ?? double.negativeInfinity,
            max: s.max ?? double.infinity,
            step: s.step ?? 1,
            unit: s.unit,
            small: true,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
