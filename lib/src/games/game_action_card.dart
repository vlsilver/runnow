import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/games/game_night_theme.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';

typedef GameActionSubmit =
    Future<void> Function({List<String> targets, String? choice, bool clear});

/// Một việc người chơi làm được lúc này. Vẽ theo `input` và `options` của
/// backend, không theo `kind`, nên backend thêm kind mới thì app vẫn vẽ được.
/// Lỗi của [onSubmit] do màn hình báo; card chỉ mở lại nút.
class GameActionCard extends StatefulWidget {
  const GameActionCard({
    super.key,
    required this.action,
    required this.serverNow,
    required this.onSubmit,
  });

  final GameAction action;

  /// Giờ server ước tính; đếm ngược theo mốc này chứ không theo đồng hồ máy.
  final DateTime Function() serverNow;
  final GameActionSubmit onSubmit;

  @override
  State<GameActionCard> createState() => _GameActionCardState();
}

class _GameActionCardState extends State<GameActionCard> {
  bool _sending = false;
  late final Timer _tick;

  /// Hai người đang chọn cho two_targets, chưa gửi.
  late List<String> _picked = _selectedTargets;

  List<String> get _selectedTargets => [...?widget.action.selected?.targets];

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(GameActionCard old) {
    super.didUpdateWidget(old);
    final before = old.action.selected?.targets ?? const [];
    final after = widget.action.selected?.targets ?? const [];
    if (before.join(',') != after.join(',')) _picked = _selectedTargets;
  }

  Future<void> _send({
    List<String> targets = const [],
    String? choice,
    bool clear = false,
  }) async {
    final confirmText = widget.action.confirmText;
    if (!clear && confirmText != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(widget.action.label),
          content: Text(confirmText),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Thôi'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Chắc'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _sending = true);
    try {
      await widget.onSubmit(targets: targets, choice: choice, clear: clear);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final action = widget.action;
    final active = action.enabled && !_sending;
    final selected = action.selected;
    final now = widget.serverNow();
    final opensAt = action.opensAt;
    final closesAt = action.closesAt;
    final notYet = opensAt != null && now.isBefore(opensAt);
    // Đang mở và bấm được thì card sáng viền vàng, để giữa mấy card thấy ngay
    // việc nào cần làm.
    final live = action.enabled && !notYet;
    final summary = _summary(action);
    return Opacity(
      opacity: notYet ? 0.72 : 1,
      child: GlassPanel(
        padding: const EdgeInsets.all(16),
        border: Border.all(
          color: live ? palette.accent.withValues(alpha: 0.5) : palette.border,
        ),
        gradient: live
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  palette.accent.withValues(alpha: 0.12),
                  palette.accent.withValues(alpha: 0.02),
                ],
              )
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    action.label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: palette.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _Window(
                  opensAt: opensAt,
                  closesAt: closesAt,
                  now: now,
                  live: live,
                ),
              ],
            ),
            if (!notYet && opensAt != null && closesAt != null) ...[
              const SizedBox(height: 10),
              _TimeLeft(
                opensAt: opensAt,
                closesAt: closesAt,
                now: now,
                live: live,
              ),
            ],
            if (action.help.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                action.help,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: RunNowGameTokens.heroSub,
                ),
              ),
            ],
            const SizedBox(height: 12),
            ..._input(action, active),
            if (!action.enabled && action.disabledReason != null) ...[
              const SizedBox(height: 10),
              _Locked(reason: action.disabledReason!),
            ] else if (selected != null && action.enabled) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  if (summary != null) ...[
                    const Icon(
                      Icons.check_circle_rounded,
                      size: 16,
                      color: RunNowGameTokens.kmOk,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        summary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: palette.ink,
                        ),
                      ),
                    ),
                  ] else
                    const Spacer(),
                  TextButton(
                    onPressed: _sending ? null : () => _send(clear: true),
                    child: const Text('Bỏ chọn'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "Đã chọn An, Bình" theo nhãn trong options. Confirm không có tên, phần
  /// input đã ghi "Đã chọn." rồi.
  static String? _summary(GameAction action) {
    final selected = action.selected;
    if (selected == null) return null;
    final labels = {for (final o in action.options) o.id: o.label};
    final names = [
      if (selected.choice case final choice? when choice.isNotEmpty)
        labels[choice] ?? choice,
      for (final id in selected.targets) ?labels[id],
    ];
    if (names.isEmpty) return null;
    return 'Đã chọn ${names.join(', ')}';
  }

  List<Widget> _input(GameAction action, bool active) {
    final selected = action.selected;
    switch (action.input) {
      case 'single_target':
      case 'choice':
        final choice = action.input == 'choice';
        final current = choice
            ? selected?.choice
            : selected?.targets.firstOrNull;
        return [
          _OptionGrid(
            children: [
              for (final option in action.options)
                GameOptionButton(
                  label: option.label,
                  selected: option.id == current,
                  onPressed: !active || option.id == current
                      ? null
                      : () => choice
                            ? _send(choice: option.id)
                            : _send(targets: [option.id]),
                ),
            ],
          ),
        ];
      case 'two_targets':
        final ready =
            _picked.length == 2 &&
            _picked.join(',') != _selectedTargets.join(',');
        return [
          _OptionGrid(
            children: [
              for (final option in action.options)
                GameOptionButton(
                  label: option.label,
                  selected: _picked.contains(option.id),
                  onPressed: !active
                      ? null
                      : () => setState(() {
                          if (_picked.contains(option.id)) {
                            _picked = [..._picked]..remove(option.id);
                          } else if (_picked.length < 2) {
                            _picked = [..._picked, option.id];
                          }
                        }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: active && ready ? () => _send(targets: _picked) : null,
            child: Text('Chọn ${_picked.length}/2 người'),
          ),
        ];
      case 'confirm':
        return [
          if (selected != null)
            const Text('Đã chọn.')
          else
            FilledButton(
              onPressed: active ? () => _send() : null,
              child: Text(action.label),
            ),
        ];
      default:
        return const [Text('Bản app này chưa làm được việc này.')];
    }
  }
}

/// Lưới ba cột cho các lựa chọn, như artboard "Cắn ai đêm nay".
class _OptionGrid extends StatelessWidget {
  const _OptionGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    const gap = 8.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - gap * 2) / 3;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

/// Một lựa chọn trong lưới: đang chọn thì nền vàng foil, còn lại viền kính.
class GameOptionButton extends StatelessWidget {
  const GameOptionButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final text = Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
        color: selected
            ? RunNowGameTokens.onGold
            : palette.ink.withValues(alpha: onPressed == null ? 0.45 : 1),
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        type: MaterialType.transparency,
        child: Ink(
          height: 44,
          decoration: BoxDecoration(
            gradient: selected ? gameNightFoil : null,
            borderRadius: BorderRadius.circular(12),
            border: selected
                ? null
                : Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onPressed,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: text,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Giờ mở hoặc đếm ngược tới lúc khoá, theo giờ server.
class _Window extends StatelessWidget {
  const _Window({
    required this.opensAt,
    required this.closesAt,
    required this.now,
    required this.live,
  });

  final DateTime? opensAt;
  final DateTime? closesAt;
  final DateTime now;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final opensAt = this.opensAt;
    final closesAt = this.closesAt;
    final String text;
    IconData? icon;
    if (opensAt != null && now.isBefore(opensAt)) {
      text = 'Mở lúc ${DateFormat('HH:mm').format(opensAt.toLocal())}';
      icon = Icons.lock_outline_rounded;
    } else if (closesAt == null) {
      return const SizedBox.shrink();
    } else if (!now.isBefore(closesAt)) {
      text = 'Đang chốt…';
    } else {
      text = 'Còn ${_remaining(closesAt.difference(now))}';
      icon = Icons.timer_outlined;
    }
    final color = live ? palette.accent : palette.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: live
            ? palette.accent.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  static String _remaining(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours > 0) return '$hours giờ $minutes phút';
    return '$minutes phút ${d.inSeconds % 60} giây';
  }
}

/// Thanh thời gian còn lại của cửa sổ, ngắn dần tới lúc khoá.
class _TimeLeft extends StatelessWidget {
  const _TimeLeft({
    required this.opensAt,
    required this.closesAt,
    required this.now,
    required this.live,
  });

  final DateTime opensAt;
  final DateTime closesAt;
  final DateTime now;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final total = closesAt.difference(opensAt).inSeconds;
    final left = closesAt.difference(now).inSeconds;
    final fraction = total <= 0 ? 0.0 : (left / total).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: SizedBox(
        height: 4,
        width: double.infinity,
        child: ColoredBox(
          color: Colors.white.withValues(alpha: 0.1),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: fraction,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: live ? gameNightFoil : null,
                  color: live ? null : Colors.white.withValues(alpha: 0.3),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lý do backend khoá việc, trong ô có ổ khoá cho khỏi lẫn với lời dặn.
class _Locked extends StatelessWidget {
  const _Locked({required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Icons.lock_outline_rounded,
              size: 15,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              reason,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: palette.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
