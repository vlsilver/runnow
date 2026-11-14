import 'package:flutter/material.dart';
import 'package:myrun/src/games/game_create_tabs.dart';
import 'package:myrun/src/games/game_models.dart';
import 'package:myrun/src/games/game_night_theme.dart';
import 'package:myrun/src/games/game_round_dial.dart';
import 'package:myrun/src/games/game_skill_cards.dart';
import 'package:myrun/src/theme.dart';

/// Một trang cho cả luật chơi lẫn thiết lập của ván, mở được ở mọi trạng thái
/// của ván. Luật không đổi giữa ván nên trang đọc [detail] lúc mở.
class GameRulesPage extends StatelessWidget {
  const GameRulesPage({super.key, required this.detail});

  final GameDetail detail;

  /// Có gì để hiện không; backend cũ có thể không gửi phần nào.
  static bool hasContent(GameDetail detail) =>
      detail.rulesText.isNotEmpty ||
      detail.rulesCard.isNotEmpty ||
      detail.setup.isNotEmpty;

  /// Mở trang với theme của màn gọi, vì route mới nằm ngoài Theme của màn đó.
  static Future<void> open(BuildContext context, GameDetail detail) {
    final theme = Theme.of(context);
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Theme(
          data: theme,
          child: GameRulesPage(detail: detail),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = detail.rulesCard;
    final text = detail.rulesText;
    final setup = detail.setup.where((s) => !s.inRulesCard).toList();
    return GameMoonlitBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Luật chơi')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            if (card.isEmpty && text.isNotEmpty) SelectableText(text),
            for (final (i, section) in card.indexed) ...[
              if (i > 0) const SizedBox(height: 18),
              Text(section.title.toUpperCase(), style: _sectionStyle(context)),
              const SizedBox(height: 8),
              switch (section.layout) {
                'timeline' => _RuleTimeline(section.items),
                'tiles' => _RuleTiles(section.items),
                _ => _RuleRows(section.items),
              },
            ],
            if (setup.isNotEmpty) ...[
              const SizedBox(height: 28),
              Text(
                'Thiết lập ván',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: context.moonlit.ink,
                ),
              ),
              GameSetupSections(setup),
            ],
          ],
        ),
      ),
    );
  }
}

TextStyle _sectionStyle(BuildContext context) => TextStyle(
  fontSize: 11,
  letterSpacing: 1.4,
  fontWeight: FontWeight.w800,
  color: context.moonlit.faint,
);

BoxDecoration _panel(BuildContext context) => BoxDecoration(
  color: context.moonlit.raised,
  borderRadius: context.runNowPalette.radius(14),
  border: Border.all(color: context.moonlit.border),
);

Color _ruleColor(RunNowMoonlit m, String key) => switch (key) {
  'night' => m.phaseNight,
  'trial' || 'teamWolf' => m.phaseTrial,
  'lovers' => m.danger,
  _ => m.amber,
};

Widget _ruleIcon(RunNowMoonlit m, String key, {required double size}) {
  final color = _ruleColor(m, key);
  if (key == 'teamWolf') return gameKeyIcon('wolf', color: color, size: size);
  final icon = switch (key) {
    'km' => Icons.directions_run_rounded,
    'skill' => Icons.auto_awesome_rounded,
    'vote' => Icons.how_to_vote_rounded,
    'shared' => Icons.sync_rounded,
    'tie' => Icons.balance_rounded,
    'hang' => Icons.gavel_rounded,
    'reveal' => Icons.style_rounded,
    'village' => Icons.groups_rounded,
    'lovers' => Icons.favorite_rounded,
    _ => gamePhaseIcon(key),
  };
  return Icon(icon, size: size, color: color);
}

/// Vòng tròn icon nền nhạt theo màu của icon.
class _RuleBadge extends StatelessWidget {
  const _RuleBadge(this.icon);

  final String icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: context.runNowPalette.round,
        color: _ruleColor(context.moonlit, icon).withValues(alpha: 0.16),
      ),
      child: _ruleIcon(context.moonlit, icon, size: 16),
    );
  }
}

/// Các mốc của một vòng nối bằng đường dọc. Dòng không có icon là ghi chú.
class _RuleTimeline extends StatelessWidget {
  const _RuleTimeline(this.items);

  final List<GameSetupItem> items;

  @override
  Widget build(BuildContext context) {
    final notes = items.where((it) => it.icon.isEmpty);
    final steps = items.where((it) => it.icon.isNotEmpty).toList();
    return Container(
      decoration: _panel(context),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final note in notes)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                note.value,
                style: TextStyle(fontSize: 13, color: context.moonlit.muted),
              ),
            ),
          for (final (i, step) in steps.indexed)
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    children: [
                      _RuleBadge(step.icon),
                      if (i < steps.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            color: context.moonlit.border,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: 6,
                        bottom: i < steps.length - 1 ? 18 : 6,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              step.value,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: context.moonlit.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          // Ván nhiều vòng: mỗi vòng một dòng giờ.
                          Text(
                            step.label,
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: context.moonlit.amberBright,
                            ),
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
    );
  }
}

/// Các ô bằng nhau xếp ngang, mỗi ô một ý.
class _RuleTiles extends StatelessWidget {
  const _RuleTiles(this.items);

  final List<GameSetupItem> items;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, item) in items.indexed) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Container(
                decoration: _panel(context),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.icon.isNotEmpty) ...[
                      _ruleIcon(context.moonlit, item.icon, size: 22),
                      const SizedBox(height: 8),
                    ],
                    Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: context.moonlit.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.value,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: context.moonlit.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Danh sách từng dòng: nhãn nhỏ trên, nội dung dưới.
class _RuleRows extends StatelessWidget {
  const _RuleRows(this.items);

  final List<GameSetupItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _panel(context),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          for (final (i, item) in items.indexed) ...[
            if (i > 0) Divider(height: 1, color: context.moonlit.divider),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  if (item.icon.isNotEmpty) ...[
                    _RuleBadge(item.icon),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (item.label.isNotEmpty)
                          Text(
                            item.label,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.moonlit.faint,
                            ),
                          ),
                        Text(
                          item.value,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: context.moonlit.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
