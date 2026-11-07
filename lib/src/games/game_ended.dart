import 'package:flutter/material.dart';
import 'package:myrun/src/games/game_hero.dart';
import 'package:myrun/src/games/game_journal.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

typedef _M = RunNowMoonlitTokens;

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
        if (stats.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final stat in stats)
                    SizedBox(
                      width: width,
                      child: _StatTile(stat: stat),
                    ),
                ],
              );
            },
          ),
        if (summary.titles.isNotEmpty) ...[
          const SizedBox(height: 18),
          const _Head('DANH HIỆU'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _M.list,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _M.border),
            ),
            child: Column(
              children: [
                for (final title in summary.titles) _TitleRow(title: title),
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
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: _M.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _M.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stat.value,
            style: const TextStyle(
              fontFamily: gameTitleFont,
              fontWeight: FontWeight.w800,
              fontSize: 30,
              height: 1,
              color: _M.amberLight,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            stat.label,
            style: const TextStyle(fontSize: 12, color: _M.muted),
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

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.title});

  final GameSummaryTitle title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: _M.amberTint,
            ),
            child: Icon(_titleIcon(title.key), size: 19, color: _M.amberPale),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.label.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: _M.muted,
                  ),
                ),
                Text(
                  title.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _M.ink,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title.value,
            style: const TextStyle(
              fontFamily: gameTitleFont,
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: _M.amberLight,
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
        color: _M.list,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: team.won ? _M.amberLine : _M.border),
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
                  color: team.won ? _M.amberLight : _M.ink,
                ),
              ),
              if (team.won) ...[
                const SizedBox(width: 8),
                const _Pill('THẮNG', strong: true),
              ],
              const Spacer(),
              Text(
                '$alive/${team.players.length} sống',
                style: const TextStyle(fontSize: 12, color: _M.muted),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final player in team.players) _RevealRow(player: player),
        ],
      ),
    );
  }
}

class _RevealRow extends StatelessWidget {
  const _RevealRow({required this.player});

  final GameSummaryPlayer player;

  @override
  Widget build(BuildContext context) {
    final cause = player.causeLabel;
    final km = player.km;
    return Opacity(
      opacity: player.alive ? 1 : 0.75,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _M.raised,
                border: Border.all(
                  color: player.alive ? _M.amberStrong : _M.divider,
                  width: 2,
                ),
              ),
              child: Text(
                player.name.isEmpty ? '?' : player.name[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: _M.ink,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    player.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _M.ink,
                    ),
                  ),
                  Text(
                    [player.roleLabel, ?cause, ?km].join(' · '),
                    style: const TextStyle(fontSize: 12, color: _M.amberSoft),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _Pill(player.fate.toUpperCase(), strong: player.alive),
          ],
        ),
      ),
    );
  }
}

/// Tab Diễn lại: từng đêm, từng ngày, cả việc làm trong đêm.
class GameReplay extends StatelessWidget {
  const GameReplay({super.key, required this.sections});

  final List<GameSummarySection> sections;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final section in sections)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            decoration: BoxDecoration(
              color: _M.list,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _M.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  section.title.toUpperCase(),
                  style: TextStyle(
                    fontFamily: gameTitleFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: 1,
                    color: section.night ? _M.inkSoft : _M.amberLight,
                  ),
                ),
                const SizedBox(height: 2),
                for (final line in section.lines)
                  GameLineRow(line: line, night: section.night),
              ],
            ),
          ),
      ],
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
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.4,
        color: _M.inkSoft,
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
        color: strong ? _M.amberTint : _M.track,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: strong ? _M.amberPale : _M.inkSoft,
        ),
      ),
    );
  }
}
