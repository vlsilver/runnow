import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

  /// Hai người đang chọn cho two_targets, chưa gửi.
  late List<String> _picked = _selectedTargets;

  List<String> get _selectedTargets => [...?widget.action.selected?.targets];

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
    return GlassPanel(
      padding: const EdgeInsets.all(16),
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
              _Window(
                opensAt: action.opensAt,
                closesAt: action.closesAt,
                serverNow: widget.serverNow,
              ),
            ],
          ),
          if (action.help.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(action.help, style: TextStyle(color: palette.textMuted)),
          ],
          const SizedBox(height: 10),
          ..._input(action, active),
          if (!action.enabled && action.disabledReason != null) ...[
            const SizedBox(height: 8),
            Text(
              action.disabledReason!,
              style: TextStyle(color: palette.textMuted),
            ),
          ],
          if (selected != null && action.enabled)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _sending ? null : () => _send(clear: true),
                child: const Text('Bỏ chọn'),
              ),
            ),
        ],
      ),
    );
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in action.options)
                ChoiceChip(
                  label: Text(option.label),
                  selected: option.id == current,
                  onSelected: !active || option.id == current
                      ? null
                      : (_) => choice
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in action.options)
                FilterChip(
                  label: Text(option.label),
                  selected: _picked.contains(option.id),
                  onSelected: !active
                      ? null
                      : (on) => setState(() {
                          if (!on) {
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

/// Giờ mở hoặc đếm ngược tới lúc khoá, theo giờ server.
class _Window extends StatefulWidget {
  const _Window({
    required this.opensAt,
    required this.closesAt,
    required this.serverNow,
  });

  final DateTime? opensAt;
  final DateTime? closesAt;
  final DateTime Function() serverNow;

  @override
  State<_Window> createState() => _WindowState();
}

class _WindowState extends State<_Window> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final now = widget.serverNow();
    final opensAt = widget.opensAt;
    final closesAt = widget.closesAt;
    final String text;
    if (opensAt != null && now.isBefore(opensAt)) {
      text = 'Mở lúc ${DateFormat('HH:mm').format(opensAt.toLocal())}';
    } else if (closesAt == null) {
      return const SizedBox.shrink();
    } else if (!now.isBefore(closesAt)) {
      text = 'Đang chốt…';
    } else {
      text = 'Còn ${_remaining(closesAt.difference(now))}';
    }
    return Text(
      text,
      style: TextStyle(fontWeight: FontWeight.w700, color: palette.accent),
    );
  }

  static String _remaining(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours > 0) return '$hours giờ $minutes phút';
    return '$minutes phút ${d.inSeconds % 60} giây';
  }
}
