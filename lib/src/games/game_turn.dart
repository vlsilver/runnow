import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

enum GameTurnState {
  /// Có việc đang mở và bấm được.
  now,

  /// Đang trong giờ của việc nhưng backend khoá (thiếu km, đã dùng lượt…).
  locked,

  /// Việc của phase này chưa tới giờ mở.
  later,

  /// Phase này vai không có việc gì.
  rest,

  /// Đã bị loại và không còn việc gì (thợ săn chết vẫn có lượt bắn).
  out,
}

class GameTurn {
  const GameTurn(this.state, {this.at, this.reason});

  final GameTurnState state;

  /// [GameTurnState.now]: lúc khoá sớm nhất; [GameTurnState.later]: lúc mở sớm
  /// nhất.
  final DateTime? at;
  final String? reason;
}

/// Giờ này có phải giờ của người chơi không, suy từ `me.actions`. Backend chỉ
/// trả việc của phase hiện tại, kèm cửa sổ và lý do khoá, nên app không cần
/// biết vai nào làm gì lúc mấy giờ.
GameTurn gameTurnOf(
  List<GameAction> actions, {
  required DateTime now,
  required bool alive,
}) {
  bool opened(GameAction a) => a.opensAt == null || !now.isBefore(a.opensAt!);
  bool closed(GameAction a) => a.closesAt != null && !now.isBefore(a.closesAt!);

  final inWindow = [
    for (final a in actions)
      if (opened(a) && !closed(a)) a,
  ];
  final open = inWindow.where((a) => a.enabled).toList();
  if (open.isNotEmpty) {
    final closes = [for (final a in open) ?a.closesAt]..sort();
    return GameTurn(GameTurnState.now, at: closes.firstOrNull);
  }
  if (inWindow.isNotEmpty) {
    return GameTurn(
      GameTurnState.locked,
      reason: inWindow.map((a) => a.disabledReason).nonNulls.firstOrNull,
    );
  }
  final opens = [
    for (final a in actions)
      if (!opened(a)) a.opensAt!,
  ]..sort();
  if (opens.isNotEmpty) return GameTurn(GameTurnState.later, at: opens.first);
  return GameTurn(alive ? GameTurnState.rest : GameTurnState.out);
}

/// Dải trạng thái trên mặt lá: tới giờ của mình chưa, tới mấy giờ. Tự tính
/// lại theo giờ server mỗi 20 giây, để cửa sổ mở hay đóng mà màn chưa tải lại
/// thì dải vẫn đổi.
class GameTurnBanner extends StatefulWidget {
  const GameTurnBanner({
    super.key,
    required this.actions,
    required this.alive,
    required this.serverNow,
  });

  final List<GameAction> actions;
  final bool alive;
  final DateTime Function() serverNow;

  @override
  State<GameTurnBanner> createState() => _GameTurnBannerState();
}

class _GameTurnBannerState extends State<GameTurnBanner> {
  late final Timer _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 20), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final now = widget.serverNow();
    final turn = gameTurnOf(widget.actions, now: now, alive: widget.alive);
    final (
      Color tone,
      IconData icon,
      String title,
      String? detail,
    ) = switch (turn.state) {
      GameTurnState.now => (
        RunNowGameTokens.kmOk,
        Icons.bolt_rounded,
        'Tới giờ của bạn',
        turn.at == null
            ? null
            : 'Còn ${_left(turn.at!.difference(now))}'
                  ' · khoá lúc ${_clock(turn.at!, now)}',
      ),
      GameTurnState.locked => (
        palette.accent,
        Icons.lock_clock_rounded,
        'Tới giờ nhưng chưa bấm được',
        turn.reason,
      ),
      GameTurnState.later => (
        RunNowGameTokens.heroSub,
        Icons.schedule_rounded,
        'Chưa tới giờ của bạn',
        'Mở lúc ${_clock(turn.at!, now)}',
      ),
      GameTurnState.rest => (
        RunNowGameTokens.heroSub,
        Icons.bedtime_rounded,
        'Giờ này bạn nghỉ',
        'Vai của bạn không có việc ở giai đoạn này.',
      ),
      GameTurnState.out => (
        palette.textMuted,
        Icons.visibility_rounded,
        'Bạn đã bị loại',
        'Vẫn xem được diễn biến tới hết ván.',
      ),
    };
    final live = turn.state == GameTurnState.now;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: live ? 0.14 : 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tone.withValues(alpha: live ? 0.5 : 0.22)),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tone.withValues(alpha: live ? 0.22 : 0.12),
                boxShadow: live
                    ? [
                        BoxShadow(
                          color: tone.withValues(alpha: 0.45),
                          blurRadius: 12,
                        ),
                      ]
                    : null,
              ),
              child: Icon(icon, size: 18, color: tone),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: live ? tone : palette.ink,
                    ),
                  ),
                  if (detail != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: palette.textMuted,
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

/// HH:mm, thêm ngày khi không phải hôm nay theo giờ máy.
String _clock(DateTime at, DateTime now) {
  final local = at.toLocal();
  final today = now.toLocal();
  final sameDay =
      local.year == today.year &&
      local.month == today.month &&
      local.day == today.day;
  return DateFormat(sameDay ? 'HH:mm' : 'HH:mm dd/MM').format(local);
}

String _left(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  if (hours > 0) return '$hours giờ $minutes phút';
  return '${d.inMinutes < 1 ? 1 : minutes} phút';
}
