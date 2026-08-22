import 'package:flutter/material.dart';
import 'package:myrun/src/health_sync.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/steps_format.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/glass.dart';

/// Trang CHI TIẾT số bước một ngày (Apple Health): tổng + tiến độ mục tiêu, các
/// chỉ số suy ra (quãng đường thật, giờ hoạt động, cao điểm, so 7 ngày) và biểu
/// đồ phân bố theo giờ (bước hoặc km) — ưu tiên bản ĐÃ LƯU (Firestore) để xem
/// được cả simulator/offline/user khác; ngày cũ chưa lưu thì fallback đọc live.
class StepDayDetailScreen extends StatefulWidget {
  const StepDayDetailScreen({
    required this.day,
    required this.recentDays,
    this.controller,
    super.key,
  });

  /// null khi xem detail của USER KHÁC (không có quyền đọc Health máy này) —
  /// khi đó chỉ dùng dữ liệu theo giờ ĐÃ LƯU, không fallback đọc live.
  final HealthSyncController? controller;
  final StepDay day;

  /// Các ngày gần đây (đã tải ở Nhật ký) để tính trung bình 7 ngày mà so sánh.
  final List<StepDay> recentDays;

  @override
  State<StepDayDetailScreen> createState() => _StepDayDetailScreenState();
}

class _StepDayDetailScreenState extends State<StepDayDetailScreen> {
  // CHỈ bước theo giờ — nhanh, cho biểu đồ hiện ngay. Km theo giờ lazy-load riêng
  // trong _ChartCard khi user bấm tab Km, để km (mới) KHÔNG chặn biểu đồ bước.
  late final Future<List<int>> _future;

  @override
  void initState() {
    super.initState();
    final parsed = DateTime.tryParse(widget.day.date) ?? DateTime.now();
    // ƯU TIÊN chi tiết theo giờ ĐÃ LƯU (Firestore) → hiện được cả simulator/offline/
    // user khác, khỏi get live. Ngày cũ CHƯA lưu → fallback đọc live từ Health.
    // KHÔNG nuốt lỗi ở nhánh live: thiếu quyền thì phải thấy, không giả vờ "rỗng".
    final stored = widget.day.hourlySteps;
    final controller = widget.controller;
    _future = stored != null
        ? Future.value(stored)
        : controller == null
        ? Future.value(const <int>[]) // user khác + chưa lưu → không có gì để đọc
        : controller.hourlySteps(parsed).timeout(const Duration(seconds: 15));
  }

  /// Trung bình bước của tối đa 7 ngày GẦN ĐÂY khác (không tính ngày đang xem).
  int? get _sevenDayAvg {
    final others = widget.recentDays
        .where((d) => d.date != widget.day.date)
        .take(7)
        .toList();
    if (others.isEmpty) return null;
    final sum = others.fold<int>(0, (a, b) => a + b.steps);
    return (sum / others.length).round();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Bước chân')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: FutureBuilder<List<int>>(
            future: _future,
            builder: (context, snap) {
              final done = snap.connectionState == ConnectionState.done;
              final stepsHours = snap.data ?? const <int>[];
              final hasHourly = stepsHours.any((h) => h > 0);
              // Tổng lấy từ số đã dedup (Firestore) cho chính xác; hourly chỉ dùng
              // vẽ HÌNH DẠNG phân bố (mẫu thô có thể phồng với Apple Watch).
              final total = widget.day.steps;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  _Hero(day: widget.day, total: total),
                  const SizedBox(height: 12),
                  _StatsGrid(
                    total: total,
                    day: widget.day,
                    hours: hasHourly ? stepsHours : null,
                    sevenDayAvg: _sevenDayAvg,
                  ),
                  const SizedBox(height: 12),
                  _ChartCard(
                    controller: widget.controller,
                    day: widget.day,
                    done: done,
                    stepsHours: stepsHours,
                    error: snap.error,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Số liệu theo giờ từ Health (đã lưu để xem lại). Km là quãng '
                    'đường đi bộ + chạy — không tính vào km chạy.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: context.runNowPalette.textMuted,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Thẻ đầu: ngày + tổng bước lớn + thanh tiến độ mục tiêu.
class _Hero extends StatelessWidget {
  const _Hero({required this.day, required this.total});

  final StepDay day;
  final int total;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final pct = ((total / stepDailyGoal) * 100).round();
    final reached = total >= stepDailyGoal;
    return GlassPanel(
      borderRadius: 18,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            stepRelativeDate(day.date),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: palette.textMuted,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                stepThousands(total),
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  color: palette.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  'bước',
                  style: TextStyle(fontSize: 15, color: palette.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (total / stepDailyGoal).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: palette.accent.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(palette.accent),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (reached) ...[
                Icon(
                  Icons.check_circle_rounded,
                  size: 16,
                  color: palette.accent,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                reached
                    ? 'Đã đạt mục tiêu ${stepThousands(stepDailyGoal)} bước'
                    : '$pct% mục tiêu ${stepThousands(stepDailyGoal)} bước',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: reached ? palette.accent : palette.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Lưới 2×2 các chỉ số suy ra từ tổng + phân bố theo giờ.
class _StatsGrid extends StatelessWidget {
  const _StatsGrid({
    required this.total,
    required this.day,
    required this.hours,
    required this.sevenDayAvg,
  });

  final int total;
  final StepDay day;
  final List<int>? hours; // null = chưa có phân bố theo giờ
  final int? sevenDayAvg;

  @override
  Widget build(BuildContext context) {
    // Quãng đường: dùng km THẬT từ Health nếu có, không thì ước lượng từ bước.
    final distValue = day.distanceMeters > 0
        ? stepKmFromMeters(day.distanceMeters)
        : '≈ ${stepDistanceKm(total)}';

    // Giờ hoạt động + cao điểm suy từ phân bố theo giờ (nếu có).
    String activeHours = '—';
    String peak = '—';
    if (hours != null) {
      final active = hours!.where((h) => h > 0).length;
      var peakIdx = 0;
      for (var i = 0; i < hours!.length; i++) {
        if (hours![i] > hours![peakIdx]) peakIdx = i;
      }
      activeHours = '$active giờ';
      peak = '${peakIdx}h';
    }

    // So 7 ngày dùng số ĐÃ LƯU (day.steps) vs trung bình đã lưu — nhất quán nguồn.
    String compare = '—';
    Color? compareColor;
    final avg = sevenDayAvg;
    if (avg != null && avg > 0) {
      final delta = ((day.steps - avg) / avg * 100).round();
      compare = '${delta >= 0 ? '+' : ''}$delta%';
      compareColor = delta >= 0
          ? context.runNowPalette.accent
          : context.runNowPalette.textMuted;
    }

    return Row(
      children: [
        Expanded(
          child: Column(
            children: [
              _StatTile(
                icon: Icons.straighten_rounded,
                label: 'Quãng đường',
                value: distValue,
              ),
              const SizedBox(height: 12),
              _StatTile(
                icon: Icons.bolt_rounded,
                label: 'Cao điểm',
                value: peak,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            children: [
              _StatTile(
                icon: Icons.schedule_rounded,
                label: 'Giờ hoạt động',
                value: activeHours,
              ),
              const SizedBox(height: 12),
              _StatTile(
                icon: Icons.insights_rounded,
                label: 'So 7 ngày',
                value: compare,
                valueColor: compareColor,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return GlassPanel(
      borderRadius: 14,
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: palette.textMuted),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: valueColor ?? palette.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Thẻ biểu đồ phân bố theo giờ — mặc định BƯỚC (nhanh); tab KM lazy-load quãng
/// đường theo giờ khi bấm, để km KHÔNG chặn biểu đồ bước.
class _ChartCard extends StatefulWidget {
  const _ChartCard({
    required this.day,
    required this.done,
    required this.stepsHours,
    required this.error,
    this.controller,
  });

  final HealthSyncController? controller;
  final StepDay day;
  final bool done;
  final List<int> stepsHours;
  final Object? error;

  @override
  State<_ChartCard> createState() => _ChartCardState();
}

class _ChartCardState extends State<_ChartCard> {
  bool _showKm = false;
  Future<List<double>>? _distFuture; // lazy: chỉ tạo khi lần đầu bấm tab Km

  void _selectKm(bool km) {
    setState(() {
      _showKm = km;
      if (km && _distFuture == null) {
        // Ưu tiên km/giờ ĐÃ LƯU (Firestore) → hiện được simulator/offline/user khác.
        // Ngày cũ chưa lưu → fallback đọc live từ Health.
        final storedDist = widget.day.hourlyDistance;
        final controller = widget.controller;
        if (storedDist != null) {
          _distFuture = Future.value(storedDist);
        } else if (controller == null) {
          _distFuture = Future.value(const <double>[]); // user khác + chưa lưu
        } else {
          final parsed = DateTime.tryParse(widget.day.date) ?? DateTime.now();
          _distFuture = controller
              .hourlyDistance(parsed)
              .timeout(
                const Duration(seconds: 10),
                onTimeout: () => const <double>[],
              )
              .catchError((_) => const <double>[]);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return GlassPanel(
      borderRadius: 18,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Theo giờ',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: palette.ink,
                ),
              ),
              const Spacer(),
              _MetricToggle(showKm: _showKm, onChanged: _selectKm),
            ],
          ),
          const SizedBox(height: 16),
          _showKm ? _kmChart(palette) : _stepsChart(palette),
        ],
      ),
    );
  }

  Widget _stepsChart(RunNowPalette palette) {
    if (!widget.done) return const _ChartLoading();
    // Lỗi thật từ Health (vd "Authorization not determined") → HIỆN, đừng giấu.
    if (widget.error != null) {
      return _ChartEmpty(
        text:
            'Không đọc được số bước theo giờ từ Apple Health:\n'
            '${widget.error}\n\n'
            'Thường do quyền "Bước" chưa bật. Vào Cài đặt iOS › Sức khoẻ › '
            '3i Run để bật, rồi mở lại.',
      );
    }
    if (!widget.stepsHours.any((h) => h > 0)) {
      // Rỗng nhưng Firestore đã có số bước ngày này → gần như chắc là quyền live
      // (getTotalStepsInInterval trả 0/null khi chưa cấp), không phải "không có".
      final hint = widget.day.steps > 0
          ? 'Không đọc được số bước theo giờ từ Health (dù đã lưu '
                '${stepThousands(widget.day.steps)} bước). Kiểm tra quyền "Bước" '
                'trong Cài đặt iOS › Sức khoẻ › 3i Run.'
          : 'Không có dữ liệu bước theo giờ cho ngày này.';
      return _ChartEmpty(text: hint);
    }
    return _HourBars(
      values: widget.stepsHours,
      peakLabel: (v) => '(${stepThousands(v.round())} bước)',
    );
  }

  Widget _kmChart(RunNowPalette palette) {
    return FutureBuilder<List<double>>(
      future: _distFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const _ChartLoading();
        }
        final dist = snap.data ?? const <double>[];
        if (!dist.any((d) => d > 0)) {
          return _ChartEmpty(
            text:
                'Chưa có quãng đường theo giờ.\n'
                'Cần cấp quyền "Khoảng cách đi bộ + chạy" trong Sức khoẻ.',
          );
        }
        return _HourBars(
          values: dist,
          peakLabel: (v) => '(${stepKmFromMeters(v.toDouble())})',
        );
      },
    );
  }
}

class _ChartLoading extends StatelessWidget {
  const _ChartLoading();
  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 168,
    child: Center(child: CircularProgressIndicator()),
  );
}

class _ChartEmpty extends StatelessWidget {
  const _ChartEmpty({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 120),
    alignment: Alignment.center,
    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 6),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(color: context.runNowPalette.textMuted, height: 1.4),
    ),
  );
}

/// Toggle nhỏ Bước ↔ Km cho biểu đồ theo giờ.
class _MetricToggle extends StatelessWidget {
  const _MetricToggle({required this.showKm, required this.onChanged});

  final bool showKm;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final onAccent = dark ? RunNowDataColors.coachOnAccentDark : Colors.white;
    Widget seg(bool km, String label) {
      final selected = showKm == km;
      return GestureDetector(
        onTap: selected ? null : () => onChanged(km),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? palette.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? onAccent : palette.textMuted,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: palette.glassStart,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [seg(false, 'Bước'), seg(true, 'Km')],
      ),
    );
  }
}

/// Biểu đồ cột 24 giờ (0h→23h) cho một chỉ số bất kỳ; cột cao điểm tô đậm.
class _HourBars extends StatelessWidget {
  const _HourBars({required this.values, required this.peakLabel});

  final List<num> values;
  final String Function(num peakValue) peakLabel;

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final maxH = values.fold<double>(
      0,
      (m, v) => v.toDouble() > m ? v.toDouble() : m,
    );
    var peak = 0;
    for (var i = 0; i < values.length; i++) {
      if (values[i] > values[peak]) peak = i;
    }
    const chartHeight = 150.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: chartHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var h = 0; h < values.length; h++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Container(
                      height: maxH <= 0
                          ? 0.0
                          : (values[h].toDouble() / maxH * chartHeight).clamp(
                              values[h] > 0 ? 3.0 : 0.0,
                              chartHeight,
                            ),
                      decoration: BoxDecoration(
                        color: h == peak
                            ? palette.accent
                            : palette.accent.withValues(alpha: 0.28),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _axis('0h', palette),
            const Spacer(),
            _axis('6h', palette),
            const Spacer(),
            _axis('12h', palette),
            const Spacer(),
            _axis('18h', palette),
            const Spacer(),
            _axis('23h', palette),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Icon(Icons.bolt_rounded, size: 17, color: palette.accent),
            const SizedBox(width: 6),
            Text(
              'Cao điểm: ${peak}h',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: palette.ink,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              peakLabel(values[peak]),
              style: TextStyle(fontSize: 13, color: palette.textMuted),
            ),
          ],
        ),
      ],
    );
  }

  Widget _axis(String label, RunNowPalette palette) => Text(
    label,
    style: TextStyle(fontSize: 10.5, color: palette.textMuted),
  );
}
