import 'package:flutter/material.dart';
import 'package:myrun/src/games/game_hero.dart';
import 'package:myrun/src/games/game_km_table.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';

typedef _M = RunNowMoonlitTokens;

/// Khối "km hôm nay" của người xem: mỗi mốc đang nhắm tới một thanh. Mốc của
/// vai lộ vai nên chỉ hiện khi lá ngửa; không còn mốc nào thì không vẽ.
class GameKmGoals extends StatelessWidget {
  const GameKmGoals({
    super.key,
    required this.goals,
    required this.faceUp,
    required this.table,
    required this.myKm,
  });

  final List<GameKmGoal> goals;
  final bool faceUp;
  final GameKmTable? table;

  /// Km đang gom của người xem; null ở ván thử.
  final double? myKm;

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (final goal in goals)
        if (faceUp || !goal.secret) goal,
    ];
    if (shown.isEmpty) return const SizedBox.shrink();
    final km = myKm;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _M.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _M.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  'KM ${(table?.todayLabel ?? 'Hôm nay').toUpperCase()}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                    color: _M.inkSoft,
                  ),
                ),
              ),
              if (km != null)
                Text(
                  '${gameKmText(km)} km',
                  style: const TextStyle(
                    fontFamily: gameTitleFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 22,
                    height: 1,
                    color: _M.ink,
                  ),
                ),
            ],
          ),
          for (final goal in shown) ...[
            const SizedBox(height: 10),
            _GoalRow(goal: goal),
          ],
        ],
      ),
    );
  }
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({required this.goal});

  final GameKmGoal goal;

  @override
  Widget build(BuildContext context) {
    final have = goal.haveKm;
    final missing = have == null ? null : gameKmMissing(have, goal.needKm);
    final done = have != null && missing == null;
    final share = have == null || goal.needKm <= 0
        ? 0.0
        : (have / goal.needKm).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${goal.label} · ${gameKmUnitText(goal.needKm)} km',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _M.ink,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              have == null
                  ? '—'
                  : done
                  ? 'ĐỦ'
                  : 'còn $missing km',
              style: TextStyle(
                fontFamily: gameTitleFont,
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: done ? _M.ink : _M.amberSoft,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _Bar(
          share: share,
          height: 6,
          gradient: LinearGradient(
            colors: done
                ? const [_M.emblemRim, _M.ink]
                : const [_M.amberDeep, _M.amberSoft],
          ),
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.share,
    required this.height,
    this.gradient,
    this.color,
  });

  final double share;
  final double height;
  final Gradient? gradient;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: _M.track),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: share,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(height),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Xếp người còn sống theo km từ cao xuống thấp, người chết xuống cuối. Có
/// bảng km thì xếp theo km đang gom hôm nay, vì đó là số sẽ chốt lúc 22h cho
/// biểu quyết và kỹ năng đêm; bằng nhau thì xét km chốt hôm qua. Chưa có bảng
/// thì xếp theo km chốt. Cùng số thì giữ thứ tự backend gửi.
List<GamePlayer> gameRanked(List<GamePlayer> players, bool live) {
  double km(double? value) => value ?? -1;
  int byKm(GamePlayer a, GamePlayer b) {
    if (a.alive != b.alive) return a.alive ? -1 : 1;
    if (!a.alive) return 0;
    final first = live
        ? km(b.todayKm).compareTo(km(a.todayKm))
        : km(b.lastKm).compareTo(km(a.lastKm));
    if (first != 0 || !live) return first;
    return km(b.lastKm).compareTo(km(a.lastKm));
  }

  // List.sort không giữ thứ tự cho phần tử bằng nhau, nên so thêm vị trí gốc.
  final indexed = players.indexed.toList()
    ..sort((a, b) {
      final order = byKm(a.$2, b.$2);
      return order != 0 ? order : a.$1.compareTo(b.$1);
    });
  return [for (final (_, player) in indexed) player];
}

/// Cả làng trong một danh sách: người sống theo km hôm nay, đường cắt ở mốc
/// khi luật phiếu có người mất phiếu, người đã ngã ở cuối kèm lá đã lật.
class GameVillage extends StatelessWidget {
  const GameVillage({
    super.key,
    required this.players,
    required this.reveals,
    required this.table,
    required this.myUid,
  });

  final List<GamePlayer> players;
  final Map<String, GameRoleReveal> reveals;

  /// Null khi ván không chạy hay tắt km: không thanh, không số km hôm nay.
  final GameKmTable? table;
  final String? myUid;

  @override
  Widget build(BuildContext context) {
    final table = this.table;
    final ranked = gameRanked(players, table != null);
    var top = 0.0;
    for (final p in ranked) {
      if (p.alive && (p.todayKm ?? 0) > top) top = p.todayKm!;
    }
    bool below(GamePlayer p) =>
        table != null && gameKmMissing(p.todayKm ?? 0, table.unitKm) != null;
    final cut = table?.cutLabel;
    var cutShown = false;
    var deadShown = false;
    final rows = <Widget>[];
    for (final player in ranked) {
      final isBelow = player.alive && below(player);
      if (cut != null && isBelow && !cutShown) {
        cutShown = true;
        rows.add(_CutLine(label: cut));
      }
      if (!player.alive && !deadShown) {
        deadShown = true;
        rows.add(const _DeadHeader());
      }
      rows.add(
        _VillagerRow(
          player: player,
          reveal: reveals[player.uid],
          table: table,
          top: top,
          isMe: player.uid == myUid,
          below: isBelow,
          dimmed: cut != null && isBelow,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _M.list,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _M.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: rows,
      ),
    );
  }
}

class _CutLine extends StatelessWidget {
  const _CutLine({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    const dash = Expanded(child: _Dashes());
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 2),
      child: Row(
        children: [
          dash,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              label.toUpperCase(),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1,
                color: _M.amberSoft,
              ),
            ),
          ),
          dash,
        ],
      ),
    );
  }
}

class _Dashes extends StatelessWidget {
  const _Dashes();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = (constraints.maxWidth / 7).floor().clamp(1, 200);
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < count; i++)
              Container(
                width: 4,
                height: 1.5,
                color: _M.amberSoft.withValues(alpha: 0.6),
              ),
          ],
        );
      },
    );
  }
}

class _DeadHeader extends StatelessWidget {
  const _DeadHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 2),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: _M.divider)),
      ),
      child: const Text(
        'ĐÃ NGÃ · LẬT BÀI',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: _M.faint,
        ),
      ),
    );
  }
}

class _VillagerRow extends StatelessWidget {
  const _VillagerRow({
    required this.player,
    required this.reveal,
    required this.table,
    required this.top,
    required this.isMe,
    required this.below,
    required this.dimmed,
  });

  final GamePlayer player;
  final GameRoleReveal? reveal;
  final GameKmTable? table;

  /// Km cao nhất làng, làm mốc cho độ dài thanh.
  final double top;
  final bool isMe;

  /// Chưa tới mốc km.
  final bool below;

  /// Dưới đường cắt: mờ đi, trừ chính mình.
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final alive = player.alive;
    final roleLabel = player.revealedRoleLabel ?? reveal?.roleLabel;
    final cardUrl = player.revealedCardUrl ?? reveal?.cardUrl;
    final table = this.table;
    final String right;
    if (!alive) {
      right = roleLabel ?? 'Đã ngã';
    } else if (table != null) {
      right = player.todayKm == null
          ? '—'
          : '${gameKmText(player.todayKm!)} km';
    } else {
      right = player.lastKm == null ? '' : '${gameKmText(player.lastKm!)} km';
    }
    final km = player.todayKm ?? 0;
    return Opacity(
      opacity: !alive
          ? 0.5
          : dimmed && !isMe
          ? 0.75
          : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            _Avatar(player: player, isMe: isMe),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    isMe ? 'Bạn' : player.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _M.ink,
                    ),
                  ),
                  if (!alive && player.deathRound != null)
                    Text(
                      'Chết vòng ${player.deathRound}',
                      style: const TextStyle(fontSize: 12, color: _M.muted),
                    ),
                  // Kẻ ngốc đã lật mà còn sống: làng đã biết lá của họ.
                  if (alive && roleLabel != null)
                    Text(
                      roleLabel,
                      style: const TextStyle(fontSize: 12, color: _M.amberSoft),
                    ),
                  if (alive && table != null) ...[
                    const SizedBox(height: 5),
                    _Bar(
                      share: top <= 0 ? 0 : (km / top).clamp(0.0, 1.0),
                      height: 4,
                      color: below ? _M.barLow : null,
                      gradient: below
                          ? null
                          : const LinearGradient(
                              colors: [_M.amberDeep, _M.amberBright],
                            ),
                    ),
                  ],
                ],
              ),
            ),
            if (cardUrl != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: Image.network(
                    cardUrl,
                    width: 28,
                    height: 39,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
              ),
            if (right.isNotEmpty)
              Container(
                constraints: const BoxConstraints(minWidth: 56),
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  right,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontFamily: gameTitleFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                    color: !alive
                        ? _M.muted
                        : below
                        ? _M.faint
                        : _M.amberLight,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.player, required this.isMe});

  final GamePlayer player;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final avatar = player.avatarUrl;
    final border = !player.alive
        ? _M.divider
        : isMe
        ? _M.amber
        : player.onTrial
        ? _M.amberStrong
        : _M.border;
    final circle = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isMe ? _M.lifted : _M.raised,
        border: Border.all(color: border, width: 2),
        image: avatar == null
            ? null
            : DecorationImage(
                image: cachedAvatarImage(context, avatar, 40),
                fit: BoxFit.cover,
                colorFilter: player.alive
                    ? null
                    : const ColorFilter.mode(_M.page, BlendMode.saturation),
              ),
      ),
      alignment: Alignment.center,
      child: avatar == null
          ? Text(
              player.name.isEmpty ? '?' : player.name[0].toUpperCase(),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: isMe ? _M.amber : _M.ink,
              ),
            )
          : null,
    );
    if (!player.onTrial) return circle;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        circle,
        Positioned(
          right: -8,
          top: -6,
          child: Container(
            height: 18,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _M.amberStrong,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _M.panel, width: 2),
            ),
            child: const Text(
              'GIÀN',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: _M.onAmber,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
