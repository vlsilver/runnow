import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:myrun/src/games/game_hero.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';

typedef _M = RunNowMoonlitTokens;

/// Icon của một câu nhật ký hay diễn lại theo khoá backend gửi
/// (`GameSummaryLine.Icon`); khoá lạ thì chấm.
IconData gameLineIcon(String key) => switch (key) {
  'bite' => Icons.dark_mode_outlined,
  'guard' => Icons.shield_outlined,
  'seer' => Icons.visibility_outlined,
  'witch' => Icons.science_outlined,
  'lovers' => Icons.favorite_border,
  'survive' => Icons.favorite,
  'death' => Icons.close,
  'void' => Icons.remove_circle_outline,
  'nominee' => Icons.campaign_outlined,
  'vote' => Icons.gavel,
  'hunter' => Icons.gps_fixed,
  'reveal' => Icons.style_outlined,
  'winner' => Icons.emoji_events_outlined,
  'pick' => Icons.touch_app_outlined,
  'peace' => Icons.nights_stay_outlined,
  _ => Icons.circle,
};

/// Một câu có icon tròn, chữ và tag; đêm tông xám bạc, ngày tông hổ phách.
class GameLineRow extends StatelessWidget {
  const GameLineRow({super.key, required this.line, required this.night});

  final GameLine line;
  final bool night;

  @override
  Widget build(BuildContext context) {
    final icon = gameLineIcon(line.icon);
    final tag = line.tag;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: night ? _M.track : _M.amberTint,
            ),
            child: Icon(
              icon,
              size: icon == Icons.circle ? 6 : 17,
              color: night ? _M.amberStrong : _M.amberPale,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              line.text,
              style: const TextStyle(fontSize: 14, height: 1.35, color: _M.ink),
            ),
          ),
          if (tag != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _M.amberTint,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                tag,
                style: const TextStyle(
                  fontFamily: gameTitleFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  letterSpacing: 0.8,
                  color: _M.amberPale,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

final _timeFormat = DateFormat('HH:mm dd/MM');

/// Nhật ký ván, mới trước. Mục nhiều dòng (cả chục lượt bấm một ngày) thì
/// gọn còn mấy dòng cuối, vì backend để kết quả ở cuối mục.
class GameJournal extends StatefulWidget {
  const GameJournal({
    super.key,
    required this.items,
    required this.hasOlder,
    required this.loadingOlder,
    required this.onLoadOlder,
  });

  final List<GameFeedItem> items;
  final bool hasOlder;
  final bool loadingOlder;
  final VoidCallback onLoadOlder;

  @override
  State<GameJournal> createState() => _GameJournalState();
}

class _GameJournalState extends State<GameJournal> {
  static const _foldAbove = 4;
  static const _shownWhenFolded = 3;

  final _expanded = <int>{};

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Chưa có gì.', style: TextStyle(color: _M.muted)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in items) _item(item),
        if (widget.hasOlder)
          Center(
            child: TextButton(
              onPressed: widget.loadingOlder ? null : widget.onLoadOlder,
              child: Text(widget.loadingOlder ? 'Đang tải…' : 'Xem cũ hơn'),
            ),
          ),
      ],
    );
  }

  Widget _item(GameFeedItem item) {
    // Backend cũ chỉ gửi lines: mỗi câu một dòng không icon, không tag.
    final lines = item.entries.isNotEmpty
        ? item.entries
        : [for (final text in item.lines) GameLine(icon: '', text: text)];
    final foldable = lines.length > _foldAbove;
    final open = !foldable || _expanded.contains(item.seq);
    final shown = open ? lines : lines.sublist(lines.length - _shownWhenFolded);
    return Container(
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _M.ink,
                  ),
                ),
              ),
              if (item.at != null)
                Text(
                  _timeFormat.format(item.at!.toLocal()),
                  style: const TextStyle(fontSize: 11, color: _M.muted),
                ),
            ],
          ),
          const SizedBox(height: 2),
          for (final line in shown) GameLineRow(line: line, night: item.night),
          if (foldable)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.only(top: 2, bottom: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => setState(() {
                  if (!_expanded.remove(item.seq)) _expanded.add(item.seq);
                }),
                child: Text(open ? 'Thu gọn' : 'Xem đủ ${lines.length} dòng'),
              ),
            ),
        ],
      ),
    );
  }
}
