import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/games/game_hero.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

/// Tách chữ backend gửi thành từng ý ngắn, để không hiện cả đoạn dài. Chỉ cắt
/// ở dấu chấm hay hai chấm có khoảng trắng phía sau, nên 22:00 và 1.5 km còn
/// nguyên.
List<String> gameRuleLines(String text) => [
  for (final part in text.split(RegExp(r'(?<=[.:])\s+')))
    if (part.replaceAll(RegExp(r'[.:]+$'), '').trim() case final line
        when line.isNotEmpty)
      line[0].toUpperCase() + line.substring(1),
];

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
  const GameTurn(this.state, {this.at});

  final GameTurnState state;

  /// [GameTurnState.now]: lúc khoá sớm nhất; [GameTurnState.later]: lúc mở sớm
  /// nhất.
  final DateTime? at;
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
    return const GameTurn(GameTurnState.locked);
  }
  final opens = [
    for (final a in actions)
      if (!opened(a)) a.opensAt!,
  ]..sort();
  if (opens.isNotEmpty) return GameTurn(GameTurnState.later, at: opens.first);
  return GameTurn(alive ? GameTurnState.rest : GameTurnState.out);
}

/// Đầu khối lá bài: tới giờ của mình chưa, việc đó là gì, tới mấy giờ. Tự tính
/// lại theo giờ server mỗi 20 giây, để cửa sổ mở hay đóng mà màn chưa tải lại
/// thì chữ vẫn đổi.
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
    final (String title, String? detail) = switch (turn.state) {
      GameTurnState.now => (
        'TỚI LƯỢT BẠN',
        turn.at == null
            ? null
            : 'Còn ${_left(turn.at!.difference(now))}'
                  ' · khoá lúc ${_clock(turn.at!, now)}',
      ),
      // Lý do đã nằm trong ô khoá của từng việc ngay bên dưới.
      GameTurnState.locked => ('CHƯA BẤM ĐƯỢC', null),
      GameTurnState.later => (
        'CHƯA TỚI GIỜ',
        'Mở lúc ${_clock(turn.at!, now)}',
      ),
      GameTurnState.rest => ('GIỜ NÀY BẠN NGHỈ', null),
      GameTurnState.out => ('BẠN ĐÃ BỊ LOẠI', null),
    };
    final live = turn.state == GameTurnState.now;
    final tone = live ? palette.accent : palette.textMuted;
    // Nhiều việc thì mỗi việc tự có tiêu đề bên dưới.
    final question = widget.actions.length == 1
        ? gameRuleLines(widget.actions.single.help).firstOrNull
        : null;
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(shape: BoxShape.circle, color: tone),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: gameTitleFont,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: tone,
                  ),
                ),
              ),
            ],
          ),
          if (question != null) ...[
            const SizedBox(height: 8),
            Text(
              question,
              style: TextStyle(
                fontSize: 18,
                height: 1.25,
                fontWeight: FontWeight.w700,
                color: palette.ink,
              ),
            ),
          ],
          // Đang tới lượt thì giờ chốt đã nằm ở header.
          if (detail != null && !(live && question != null)) ...[
            const SizedBox(height: 6),
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
