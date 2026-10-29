import 'package:flutter/material.dart';
import 'package:myrun/src/runnow_api_client.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';

/// Km làm tròn xuống 0.1 như server làm khi so mốc: 0.96 km hiện 0.9 chứ
/// không 1.0, để không ai thấy "đủ 1 km" mà vẫn bị chặn.
String gameKmText(double km) {
  final meters = (km * 1000).round();
  return ((meters ~/ 100) / 10).toStringAsFixed(1);
}

/// Km còn thiếu tới mốc, làm tròn lên 0.1; null là đã đủ.
String? gameKmMissing(double km, double unitKm) {
  final missing = (unitKm * 1000).round() - (km * 1000).round();
  if (missing <= 0) return null;
  return (((missing + 99) ~/ 100) / 10).toStringAsFixed(1);
}

/// Mốc km viết gọn: 1 thay vì 1.0.
String gameKmUnitText(double km) {
  final text = gameKmText(km);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// Bảng hai cột km: chốt 22h gần nhất và đang gom tới giờ. Đầu cột lấy từ
/// server ([GameKmTable]); phần sau " · " xuống dòng.
class GameKmColumns extends StatelessWidget {
  const GameKmColumns({
    super.key,
    required this.lastLabel,
    required this.todayLabel,
    required this.rows,
  });

  final String lastLabel;
  final String todayLabel;
  final List<GameKmRow> rows;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final muted = palette.textMuted;
    final accent = palette.accent;
    final divider = palette.border;
    String header(String label) => label.replaceAll(' · ', '\n');
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(),
        1: FixedColumnWidth(96),
        2: FixedColumnWidth(96),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          children: [
            const SizedBox.shrink(),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                header(lastLabel),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                header(todayLabel),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ),
          ],
        ),
        for (final row in rows)
          TableRow(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: divider)),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(row.label, style: TextStyle(color: muted)),
              ),
              Align(alignment: Alignment.centerRight, child: row.last),
              Align(alignment: Alignment.centerRight, child: row.today),
            ],
          ),
      ],
    );
  }
}

class GameKmRow {
  const GameKmRow({
    required this.label,
    required this.last,
    required this.today,
  });

  final String label;
  final Widget last;
  final Widget today;
}

/// Số km to trong ô bảng; null là chưa có số ("Chưa chốt" hay "—").
class GameKmNumber extends StatelessWidget {
  const GameKmNumber({
    super.key,
    required this.km,
    this.empty = '—',
    this.highlight = false,
  });

  final double? km;
  final String empty;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final km = this.km;
    if (km == null) {
      return Text(empty, style: TextStyle(color: palette.textMuted));
    }
    return Text(
      gameKmText(km),
      style: TextStyle(
        fontSize: 18,
        fontWeight: highlight ? FontWeight.w800 : FontWeight.w700,
        color: highlight ? palette.accent : palette.ink,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// Nhãn Đủ / Thiếu x so với mốc; chữ khác nhau nên không chỉ dựa vào màu.
class GameKmStatusLabel extends StatelessWidget {
  const GameKmStatusLabel({super.key, required this.km, required this.unitKm});

  final double? km;
  final double unitKm;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final km = this.km;
    if (km == null) {
      return Text('—', style: TextStyle(color: palette.textMuted));
    }
    final missing = gameKmMissing(km, unitKm);
    if (missing == null) {
      return const Text(
        'Đủ',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: RunNowSemanticColors.success,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: RunNowSemanticColors.danger.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Thiếu $missing',
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: RunNowSemanticColors.danger,
        ),
      ),
    );
  }
}

/// Card "Km của bạn" trên màn ván: km chốt 22h gần nhất và km đang gom của
/// chính người xem.
class GameMyKmCard extends StatelessWidget {
  const GameMyKmCard({super.key, required this.table, required this.player});

  final GameKmTable table;
  final GamePlayer player;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final muted = TextStyle(
      fontSize: 13,
      height: 1.45,
      color: palette.textMuted,
    );
    final today = player.todayKm;
    final missing = today == null ? null : gameKmMissing(today, table.unitKm);
    return GlassPanel(
      padding: const EdgeInsets.all(16),
      border: Border.all(color: palette.border),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Km của bạn',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: palette.ink,
            ),
          ),
          const SizedBox(height: 12),
          if (!player.alive)
            Text(
              'Bạn đã chết nên km không còn tính trong ván.',
              style: TextStyle(color: palette.textMuted),
            )
          else ...[
            GameKmColumns(
              lastLabel: table.lastLabel,
              todayLabel: table.todayLabel,
              rows: [
                GameKmRow(
                  label: 'Km',
                  last: GameKmNumber(km: player.lastKm, empty: 'Chưa chốt'),
                  today: GameKmNumber(km: today, highlight: true),
                ),
                GameKmRow(
                  label: 'Mốc ${gameKmUnitText(table.unitKm)} km',
                  last: GameKmStatusLabel(
                    km: player.lastKm,
                    unitKm: table.unitKm,
                  ),
                  today: GameKmStatusLabel(km: today, unitKm: table.unitKm),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (missing != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Chạy thêm $missing km trước 22h để đủ mốc.',
                  style: TextStyle(fontSize: 13, color: palette.ink),
                ),
              ),
            Text(table.note, style: muted),
          ],
        ],
      ),
    );
  }
}
