import 'package:flutter/material.dart';
import 'package:myrun/src/games/game_hero.dart';
import 'package:myrun/src/games/game_journal.dart';
import 'package:myrun/src/games/game_role_card.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';
import 'package:share_plus/share_plus.dart';

/// Chia sẻ tóm tắt ván dạng chữ.
Future<void> shareGameSummary(
  BuildContext context,
  String title,
  GameSummary summary,
) {
  final box = context.findRenderObject() as RenderBox?;
  final text = [
    title,
    if (summary.winnerLabel.isNotEmpty) '${summary.winnerLabel} thắng',
    for (final stat in summary.stats) '${stat.label}: ${stat.value}',
    'Chia sẻ từ 3i',
  ].join('\n');
  return SharePlus.instance.share(
    ShareParams(
      text: text,
      subject: title,
      sharePositionOrigin: box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size,
    ),
  );
}

/// Tab Tổng kết: số liệu cả ván và danh hiệu.
class GameEndedSummary extends StatelessWidget {
  const GameEndedSummary({super.key, required this.summary});

  final GameSummary summary;

  @override
  Widget build(BuildContext context) {
    final stats = summary.stats;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stats.isNotEmpty) _StatRows(stats: stats),
        if (summary.titles.isNotEmpty) ...[
          const SizedBox(height: 18),
          const _Head('DANH HIỆU'),
          const SizedBox(height: 8),
          _TitleCards(titles: summary.titles),
        ],
      ],
    );
  }
}

/// Mỗi hàng 4 ô số. Số dài tự thu nhỏ để không xuống dòng.
class _StatRows extends StatelessWidget {
  const _StatRows({required this.stats});

  final List<GameSummaryStat> stats;

  @override
  Widget build(BuildContext context) {
    return _Grid(
      count: stats.length,
      columns: 4,
      spacing: 6,
      itemBuilder: (i) => _StatTile(stat: stats[i]),
    );
  }
}

/// Lưới chia đều cột, các ô cùng hàng cao bằng nhau.
class _Grid extends StatelessWidget {
  const _Grid({
    required this.count,
    required this.columns,
    required this.spacing,
    required this.itemBuilder,
  });

  final int count;
  final int columns;
  final double spacing;
  final Widget Function(int index) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var row = 0; row * columns < count; row++) ...[
          if (row > 0) SizedBox(height: spacing),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var col = 0; col < columns; col++) ...[
                  if (col > 0) SizedBox(width: spacing),
                  Expanded(
                    child: row * columns + col < count
                        ? itemBuilder(row * columns + col)
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.stat});

  final GameSummaryStat stat;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
      decoration: BoxDecoration(
        color: context.moonlit.panel,
        borderRadius: context.runNowPalette.radius(12),
        border: Border.all(color: context.moonlit.border),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              stat.value,
              maxLines: 1,
              style: TextStyle(
                fontFamily: gameTitleFont,
                fontWeight: FontWeight.w800,
                fontSize: 26,
                height: 1,
                color: context.moonlit.amberLight,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            stat.label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: context.moonlit.muted),
          ),
        ],
      ),
    );
  }
}

IconData _titleIcon(String key) => switch (key) {
  'runner' => Icons.directions_run,
  'seer' => Icons.visibility_outlined,
  'guard' => Icons.shield_outlined,
  _ => Icons.emoji_events_outlined,
};

class _TitleCards extends StatelessWidget {
  const _TitleCards({required this.titles});

  final List<GameSummaryTitle> titles;

  @override
  Widget build(BuildContext context) {
    return _Grid(
      count: titles.length,
      columns: 3,
      spacing: 8,
      itemBuilder: (i) => _TitleCard(title: titles[i]),
    );
  }
}

class _TitleCard extends StatelessWidget {
  const _TitleCard({required this.title});

  final GameSummaryTitle title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.moonlit.list,
        borderRadius: context.runNowPalette.radius(14),
        border: Border.all(color: context.moonlit.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.moonlit.amberTint,
              borderRadius: context.runNowPalette.radius(10),
            ),
            child: Icon(
              _titleIcon(title.key),
              size: 20,
              color: context.moonlit.amberPale,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: context.moonlit.muted),
          ),
          const SizedBox(height: 2),
          Text(
            title.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: context.moonlit.ink,
            ),
          ),
          const Spacer(),
          Text(
            title.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: gameTitleFont,
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: context.moonlit.amberLight,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tab Lật bài: mỗi phe một khối, phe thắng đứng đầu (backend xếp).
class GameEndedReveal extends StatelessWidget {
  const GameEndedReveal({super.key, required this.teams});

  final List<GameSummaryTeam> teams;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final team in teams) ...[
          _TeamBlock(team: team),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _TeamBlock extends StatelessWidget {
  const _TeamBlock({required this.team});

  final GameSummaryTeam team;

  @override
  Widget build(BuildContext context) {
    final alive = team.players.where((p) => p.alive).length;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: context.moonlit.list,
        borderRadius: context.runNowPalette.radius(16),
        border: Border.all(
          color: team.won ? context.moonlit.amberLine : context.moonlit.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                team.label.toUpperCase(),
                style: TextStyle(
                  fontFamily: gameTitleFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  letterSpacing: 1,
                  color: team.won
                      ? context.moonlit.amberLight
                      : context.moonlit.ink,
                ),
              ),
              if (team.won) ...[
                const SizedBox(width: 8),
                const _Pill('THẮNG', strong: true),
              ],
              const Spacer(),
              Text(
                '$alive/${team.players.length} sống',
                style: TextStyle(fontSize: 12, color: context.moonlit.muted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _Grid(
            count: team.players.length,
            columns: 4,
            spacing: 6,
            itemBuilder: (i) => _RevealTile(player: team.players[i]),
          ),
        ],
      ),
    );
  }
}

class _RevealTile extends StatelessWidget {
  const _RevealTile({required this.player});

  final GameSummaryPlayer player;

  @override
  Widget build(BuildContext context) {
    final accent = player.role.isEmpty
        ? context.moonlit.amberStrong
        : gameRoleAccent(player.role);
    return Opacity(
      opacity: player.alive ? 1 : 0.75,
      child: Column(
        children: [
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: context.runNowPalette.round,
                    color: context.moonlit.raised,
                    border: Border.all(color: accent, width: 2),
                  ),
                  child: Text(
                    player.name.isEmpty ? '?' : player.name[0].toUpperCase(),
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: context.moonlit.ink,
                    ),
                  ),
                ),
                Positioned(
                  right: -6,
                  bottom: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: player.alive
                          ? context.moonlit.panel
                          : context.moonlit.lifted,
                      borderRadius: context.runNowPalette.radius(6),
                      border: Border.all(color: context.moonlit.list, width: 2),
                    ),
                    child: Text(
                      player.fate.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: player.alive
                            ? context.moonlit.amberPale
                            : context.moonlit.inkSoft,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            player.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: context.moonlit.ink,
            ),
          ),
          Text(
            player.roleLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: accent),
          ),
        ],
      ),
    );
  }
}

/// Các mục liền nhau cùng một vòng. Mục của backend cũ không có số vòng nên
/// đứng riêng với `round == 0`.
class GameReplayRound {
  const GameReplayRound(this.round, this.sections);

  final int round;
  final List<GameSummarySection> sections;

  int get deaths => [
    for (final section in sections) ...section.lines,
  ].where((line) => line.icon == 'death').length;

  /// `16/10`, hoặc `16–17/10` khi vòng đi qua hai ngày cùng tháng.
  String? get dateRange {
    final dates = [for (final section in sections) ?section.date];
    if (dates.isEmpty) return null;
    final first = dates.first;
    final last = dates.last;
    if (first == last) return first;
    final firstDay = first.split('/').first;
    if (first.endsWith(last.substring(last.indexOf('/')))) {
      return '$firstDay–$last';
    }
    return '$first–$last';
  }
}

/// Vòng có số thứ tự của mục diễn lại, giữ nguyên thứ tự backend gửi.
List<GameReplayRound> gameReplayRounds(List<GameSummarySection> sections) {
  final rounds = <GameReplayRound>[];
  for (final section in sections) {
    if (section.round <= 0) continue;
    if (rounds.lastOrNull case final last? when last.round == section.round) {
      last.sections.add(section);
    } else {
      rounds.add(GameReplayRound(section.round, [section]));
    }
  }
  return rounds;
}

/// Tab Diễn lại: gộp theo vòng; backend cũ không có vòng thì vẽ từng mục.
class GameReplay extends StatelessWidget {
  const GameReplay({super.key, required this.sections});

  final List<GameSummarySection> sections;

  @override
  Widget build(BuildContext context) {
    final rounds = gameReplayRounds(sections);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in sections.where((s) => s.round <= 0))
          _ReplayBlock(
            title: section.title.toUpperCase(),
            highlight: !section.night,
            children: [_SectionLines(section: section)],
          ),
        for (final round in rounds)
          _ReplayBlock(
            title: [
              'VÒNG ${round.round}',
              ?round.dateRange,
              if (round.deaths > 0) '${round.deaths} người ngã',
            ].join(' · '),
            highlight: true,
            children: [
              for (final section in round.sections) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    section.title.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: context.moonlit.muted,
                    ),
                  ),
                ),
                _SectionLines(section: section),
              ],
            ],
          ),
      ],
    );
  }
}

class _ReplayBlock extends StatelessWidget {
  const _ReplayBlock({
    required this.title,
    required this.highlight,
    required this.children,
  });

  final String title;
  final bool highlight;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      decoration: BoxDecoration(
        color: context.moonlit.list,
        borderRadius: context.runNowPalette.radius(16),
        border: Border.all(color: context.moonlit.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontFamily: gameTitleFont,
              fontWeight: FontWeight.w800,
              fontSize: 16,
              letterSpacing: 1,
              color: highlight
                  ? context.moonlit.amberLight
                  : context.moonlit.inkSoft,
            ),
          ),
          const SizedBox(height: 2),
          ...children,
        ],
      ),
    );
  }
}

class _SectionLines extends StatelessWidget {
  const _SectionLines({required this.section});

  final GameSummarySection section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final line in section.lines) ...[
          GameLineRow(line: line, night: section.night),
          if (line.hang + line.spare > 0)
            _VoteBar(hang: line.hang, spare: line.spare),
        ],
      ],
    );
  }
}

/// Thanh tỉ lệ phiếu Treo và Tha của một câu kết quả biểu quyết.
class _VoteBar extends StatelessWidget {
  const _VoteBar({required this.hang, required this.spare});

  final int hang;
  final int spare;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(42, 0, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: context.runNowPalette.radius(3),
            child: SizedBox(
              height: 6,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hang > 0)
                    Expanded(
                      flex: hang,
                      child: ColoredBox(color: context.moonlit.amber),
                    ),
                  if (spare > 0)
                    Expanded(
                      flex: spare,
                      child: ColoredBox(color: context.moonlit.track),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Treo $hang',
                style: TextStyle(
                  fontSize: 11,
                  color: context.moonlit.amberSoft,
                ),
              ),
              Text(
                'Tha $spare',
                style: TextStyle(fontSize: 11, color: context.moonlit.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
        color: context.moonlit.inkSoft,
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.text, {this.strong = false});

  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: strong ? context.moonlit.amberTint : context.moonlit.track,
        borderRadius: context.runNowPalette.radius(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: strong ? context.moonlit.amberPale : context.moonlit.inkSoft,
        ),
      ),
    );
  }
}
