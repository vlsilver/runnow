import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:myrun/src/games/game_create_tabs.dart';
import 'package:myrun/src/games/game_models.dart';
import 'package:myrun/src/theme_tokens.dart';

typedef _M = RunNowMoonlitTokens;

/// Giới hạn của độ dài pha, khớp backend (werewolf.MinPhaseMinutes,
/// PhaseStepMinutes): pha nào cũng ít nhất 1 tiếng, dời theo bước 30 phút.
const gameMinPhase = 60;
const gamePhaseStep = 30;

/// Co giãn [phases] cho tổng bằng [total] phút (độ dài vòng khi đổi số vòng
/// mỗi ngày), giữ tỉ lệ giữa các pha. Pha làm tròn về bước 30 phút, ít nhất 1
/// tiếng; phần lệch do làm tròn trừ vào hoặc cộng vào pha dài nhất.
List<int> gameFitPhases(List<int> phases, int total) {
  final sum = phases.fold<int>(0, (a, p) => a + p);
  final out = [
    for (final p in phases)
      ((p * total / sum / gamePhaseStep).round() * gamePhaseStep).clamp(
        gameMinPhase,
        total,
      ),
  ];
  int longest({bool shrinkable = false}) {
    var at = -1;
    for (var i = 0; i < out.length; i++) {
      if (shrinkable && out[i] <= gameMinPhase) continue;
      if (at < 0 || out[i] > out[at]) at = i;
    }
    return at;
  }

  var diff = out.fold<int>(0, (a, p) => a + p) - total;
  while (diff > 0) {
    final i = longest(shrinkable: true);
    if (i < 0) break;
    out[i] -= gamePhaseStep;
    diff -= gamePhaseStep;
  }
  while (diff < 0) {
    out[longest()] += gamePhaseStep;
    diff += gamePhaseStep;
  }
  return out;
}

/// Phút (tính từ lúc mở đêm) của mốc [hour] trên lịch gốc 24 tiếng, khi các pha
/// dài [phases] phút: mốc giữ đúng tỉ lệ trong pha chứa nó, như
/// werewolf.Config.At. [base] là (từ, tới) giờ của từng pha trên lịch gốc.
double gameMarkAt(List<(double, double)> base, List<int> phases, double hour) {
  var start = 0.0;
  for (var i = 0; i < base.length; i++) {
    final (from, to) = base[i];
    if (hour <= to || i == base.length - 1) {
      return start + (hour - from) / (to - from) * phases[i];
    }
    start += phases[i];
  }
  return start;
}

/// Nút −/+ ([dir] là -1 hoặc 1) của pha thứ [i]: dời mốc cuối pha nửa tiếng,
/// lấy hoặc trả phút cho pha sau. Pha cuối thì đổi độ dài vòng theo giờ tròn;
/// vòng bị khoá ([lockEnd]) thì dời mốc đầu pha, lấy hoặc trả cho pha trước.
List<int>? gameStepPhase(
  List<int> phases,
  int i,
  int dir, {
  required bool lockEnd,
  required int maxTotal,
}) {
  var end = 0;
  for (var k = 0; k <= i; k++) {
    end += phases[k];
  }
  final last = i == phases.length - 1;
  if (!last) {
    return gameMoveMark(
      phases,
      i + 1,
      end + dir * gamePhaseStep,
      lockEnd: lockEnd,
      maxTotal: maxTotal,
    );
  }
  if (!lockEnd) {
    return gameMoveMark(
      phases,
      i + 1,
      end + dir * 60,
      lockEnd: false,
      maxTotal: maxTotal,
    );
  }
  return gameMoveMark(
    phases,
    i,
    end - phases[i] - dir * gamePhaseStep,
    lockEnd: true,
    maxTotal: maxTotal,
  );
}

/// Dời mốc [mark] (1 là cuối Đêm, … 4 là cuối Biểu quyết) tới phút [offset]
/// tính từ lúc mở đêm. Mốc giữa đổi phút giữa hai pha kề nhau; mốc cuối đổi độ
/// dài vòng, theo bước 60 phút vì vòng phải tròn giờ, không quá [maxTotal].
/// Trả null khi mốc bị khoá hoặc không đổi gì.
List<int>? gameMoveMark(
  List<int> phases,
  int mark,
  int offset, {
  required bool lockEnd,
  required int maxTotal,
}) {
  if (mark == phases.length && lockEnd) return null;
  final bounds = [0];
  for (final p in phases) {
    bounds.add(bounds.last + p);
  }
  final last = mark == phases.length;
  final step = last ? 60 : gamePhaseStep;
  final lo = bounds[mark - 1] + gameMinPhase;
  final hi = last ? maxTotal : bounds[mark + 1] - gameMinPhase;
  final at = ((offset / step).round() * step).clamp(lo, hi);
  if (at == bounds[mark]) return null;
  final out = [...phases];
  out[mark - 1] = at - bounds[mark - 1];
  if (!last) out[mark] = bounds[mark + 1] - at;
  return out;
}

/// Độ dài theo giờ: 120 → "2h", 90 → "1h30".
String gameHours(int minutes) {
  final h = minutes ~/ 60, m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
}

IconData gamePhaseIcon(String key) => switch (key) {
  'night' => Icons.nightlight_round,
  'dawn' => Icons.wb_twilight_rounded,
  'day' => Icons.wb_sunny_rounded,
  'trial' => Icons.gavel_rounded,
  _ => Icons.schedule_rounded,
};

/// Dời giờ mở vòng [dir] tiếng ([dir] là -1 hoặc 1), giữ mốc cuối Đêm: mở muộn
/// thì Đêm ngắn đi, mở sớm thì Đêm dài ra nhưng vòng không quá [maxTotal]. Trả
/// (giờ mở mới tính bằng phút trong ngày, các pha), null khi không dời được.
({int start, List<int> phases})? gameMoveStart(
  int start,
  List<int> phases,
  int dir, {
  required int maxTotal,
}) {
  final night = phases.first - dir * 60;
  final total = phases.fold<int>(0, (a, p) => a + p) - dir * 60;
  if (night < gameMinPhase || total > maxTotal) return null;
  return (start: (start + dir * 60) % 1440, phases: [night, ...phases.skip(1)]);
}

/// Một vòng trên mặt đồng hồ 24 tiếng: bốn cung pha bắt đầu ở giờ mở đêm, kéo
/// mốc giữa các pha để đổi độ dài. Dưới là dòng Mở vòng, từng pha với giờ và
/// nút −/+, rồi dòng Chốt vòng. Ván km khoá mốc cuối ([lockEnd]) vì vòng phải
/// chia đều 24 tiếng.
class GameRoundDial extends StatefulWidget {
  const GameRoundDial({
    super.key,
    required this.plan,
    required this.phases,
    required this.startMinute,
    required this.lockEnd,
    required this.maxTotal,
    required this.onChanged,
    this.onStart,
  });

  /// Tên, khoá, mốc gốc của pha và các mốc nhắc.
  final GameRoundPlan plan;

  /// Độ dài từng pha (phút), cùng thứ tự với `plan.phases`.
  final List<int> phases;

  /// Giờ mở đêm, phút trong ngày.
  final int startMinute;
  final bool lockEnd;

  /// Độ dài vòng tối đa (phút) khi kéo mốc cuối.
  final int maxTotal;

  /// null thì không chỉnh được.
  final ValueChanged<List<int>>? onChanged;

  /// Dời giờ mở vòng (phút trong ngày) cùng các pha; null thì giờ mở khoá.
  final void Function(int start, List<int> phases)? onStart;

  @override
  State<GameRoundDial> createState() => _GameRoundDialState();
}

class _GameRoundDialState extends State<GameRoundDial> {
  /// Mốc đang kéo (1 là cuối pha đầu); null khi không kéo.
  int? _dragging;

  List<int> get _bounds {
    final out = [0];
    for (final p in widget.phases) {
      out.add(out.last + p);
    }
    return out;
  }

  /// Phút trong ngày ở điểm chạm, 0h ở đỉnh, theo chiều kim đồng hồ.
  static double _minuteAt(Offset p, Size size) {
    final c = size.center(Offset.zero);
    final a = math.atan2(p.dy - c.dy, p.dx - c.dx) + math.pi / 2;
    return (a / (2 * math.pi) * 1440) % 1440;
  }

  /// Phút tính từ lúc mở đêm ở điểm chạm, chọn vòng quay gần mốc [mark] nhất
  /// để mốc cuối kéo được tới đủ 24 tiếng.
  int _offsetAt(Offset p, Size size, int mark) {
    final raw = (_minuteAt(p, size) - widget.startMinute) % 1440;
    final at = _bounds[mark];
    return ((raw - at).abs() <= (raw + 1440 - at).abs() ? raw : raw + 1440)
        .round();
  }

  /// Mốc kéo được có tay nắm gần điểm chạm nhất, trong tầm một ngón tay.
  int? _markAt(Offset p, Size size) {
    final n = widget.phases.length;
    final last = widget.lockEnd ? n - 1 : n;
    final bounds = _bounds;
    int? best;
    var bestGap = 28.0;
    for (var m = 1; m <= last; m++) {
      final gap =
          (_DialPainter.handle(size, widget.startMinute + bounds[m]) - p)
              .distance;
      if (gap < bestGap) {
        bestGap = gap;
        best = m;
      }
    }
    return best;
  }

  void _move(Offset p, Size size) {
    final mark = _dragging;
    final change = widget.onChanged;
    if (mark == null || change == null) return;
    final out = gameMoveMark(
      widget.phases,
      mark,
      _offsetAt(p, size, mark),
      lockEnd: widget.lockEnd,
      maxTotal: widget.maxTotal,
    );
    if (out != null) change(out);
  }

  @override
  Widget build(BuildContext context) {
    final plan = widget.plan;
    final phases = widget.phases;
    final bounds = _bounds;
    final total = bounds.last;
    final start = widget.startMinute;
    final change = widget.onChanged;
    final keys = [for (final p in plan.phases) p.key];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: AspectRatio(
              aspectRatio: 1,
              child: LayoutBuilder(
                builder: (context, box) {
                  final size = box.biggest;
                  // Chạm trúng tay nắm thì giành cử chỉ ngay, để kéo dọc ở
                  // cạnh mặt đồng hồ không thành cuộn trang.
                  return RawGestureDetector(
                    gestures: {
                      if (change != null)
                        _HandlePan:
                            GestureRecognizerFactoryWithHandlers<_HandlePan>(
                              () => _HandlePan((p) => _markAt(p, size) != null),
                              (r) {
                                r.onStart = (d) {
                                  setState(
                                    () => _dragging = _markAt(
                                      d.localPosition,
                                      size,
                                    ),
                                  );
                                };
                                r.onUpdate = (d) =>
                                    _move(d.localPosition, size);
                                r.onEnd = (_) =>
                                    setState(() => _dragging = null);
                                r.onCancel = () =>
                                    setState(() => _dragging = null);
                              },
                            ),
                    },
                    child: CustomPaint(
                      painter: _DialPainter(
                        keys: keys,
                        phases: phases,
                        start: start,
                        lockEnd: widget.lockEnd,
                        active: _dragging,
                      ),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'MỘT VÒNG',
                              style: TextStyle(
                                fontSize: 10.5,
                                letterSpacing: 1.4,
                                fontWeight: FontWeight.w800,
                                color: _M.faint,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  total % 60 == 0
                                      ? '${total ~/ 60}'
                                      : gameHours(total),
                                  style: const TextStyle(
                                    fontFamily: 'Barlow Condensed',
                                    fontSize: 38,
                                    height: 1.1,
                                    fontWeight: FontWeight.w800,
                                    color: _M.ink,
                                  ),
                                ),
                                if (total % 60 == 0)
                                  const Text(
                                    ' tiếng',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: _M.muted,
                                    ),
                                  ),
                              ],
                            ),
                            Text(
                              '${gameClock(start.toDouble())} → '
                              '${gameClock((start + total).toDouble())}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: _M.faint,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 4,
          children: [
            for (final p in plan.phases)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: gamePhaseColor(p.key),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    p.label,
                    style: const TextStyle(fontSize: 11.5, color: _M.muted),
                  ),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),
        _EdgeRow(
          label: 'Mở vòng',
          value: gameClock(start.toDouble()),
          locked: widget.onStart == null,
          onStep: _startStep,
        ),
        const Divider(height: 14, color: _M.border),
        for (var i = 0; i < phases.length; i++)
          _PhaseRow(
            phase: plan.phases[i],
            from: gameClock((start + bounds[i]).toDouble()),
            to: gameClock((start + bounds[i + 1]).toDouble()),
            length: phases[i],
            lockedEnd: widget.lockEnd && i == phases.length - 1,
            onStep: change == null
                ? null
                : (dir) {
                    final out = gameStepPhase(
                      phases,
                      i,
                      dir,
                      lockEnd: widget.lockEnd,
                      maxTotal: widget.maxTotal,
                    );
                    if (out == null) return false;
                    change(out);
                    return true;
                  },
          ),
        const Divider(height: 14, color: _M.border),
        _EdgeRow(
          label: 'Chốt vòng',
          value: gameClock((start + total).toDouble()),
          locked: widget.lockEnd || change == null,
          onStep: _endStep,
        ),
      ],
    );
  }

  /// Nút −/+ của dòng Mở vòng; trả false khi bước đó không làm được, để nút mờ.
  bool _startStep(int dir, {bool dryRun = false}) {
    final onStart = widget.onStart;
    if (onStart == null) return false;
    final out = gameMoveStart(
      widget.startMinute,
      widget.phases,
      dir,
      maxTotal: widget.maxTotal,
    );
    if (out == null) return false;
    if (!dryRun) onStart(out.start, out.phases);
    return true;
  }

  /// Nút −/+ của dòng Chốt vòng: dời mốc cuối một tiếng.
  bool _endStep(int dir, {bool dryRun = false}) {
    final change = widget.onChanged;
    if (change == null || widget.lockEnd) return false;
    final out = gameMoveMark(
      widget.phases,
      widget.phases.length,
      _bounds.last + dir * 60,
      lockEnd: false,
      maxTotal: widget.maxTotal,
    );
    if (out == null) return false;
    if (!dryRun) change(out);
    return true;
  }
}

/// Dòng Mở vòng / Chốt vòng: giờ và nút −/+ dời một tiếng.
class _EdgeRow extends StatelessWidget {
  const _EdgeRow({
    required this.label,
    required this.value,
    required this.locked,
    required this.onStep,
  });

  final String label;
  final String value;
  final bool locked;
  final bool Function(int dir, {bool dryRun}) onStep;

  @override
  Widget build(BuildContext context) {
    bool can(int dir) => !locked && onStep(dir, dryRun: true);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              border: Border.all(color: _M.border),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              Icons.schedule_rounded,
              size: 16,
              color: _M.amberBright,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _M.ink,
              ),
            ),
          ),
          if (locked)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Icon(Icons.lock_rounded, size: 14, color: _M.faint),
            ),
          GameStepBox(
            label: label,
            value: value,
            onDec: can(-1) ? () => onStep(-1) : null,
            onInc: can(1) ? () => onStep(1) : null,
          ),
        ],
      ),
    );
  }
}

/// Ô −/+ có viền, giá trị ở giữa; nút null thì mờ.
class GameStepBox extends StatelessWidget {
  const GameStepBox({
    super.key,
    required this.label,
    required this.value,
    required this.onDec,
    required this.onInc,
  });

  /// Tên cho tooltip "Bớt …" / "Thêm …".
  final String label;
  final String value;
  final VoidCallback? onDec;
  final VoidCallback? onInc;

  @override
  Widget build(BuildContext context) {
    Widget button(String tip, IconData icon, VoidCallback? onTap) => IconButton(
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 34, height: 34),
      padding: EdgeInsets.zero,
      icon: Icon(icon, size: 16),
      color: _M.amberBright,
      onPressed: onTap,
    );
    return Container(
      decoration: BoxDecoration(
        color: _M.raised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _M.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button('Bớt $label', Icons.remove_rounded, onDec),
          SizedBox(
            width: 44,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Barlow Condensed',
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: _M.amberBright,
              ),
            ),
          ),
          button('Thêm $label', Icons.add_rounded, onInc),
        ],
      ),
    );
  }
}

/// Kéo trên mặt đồng hồ; chạm trúng tay nắm thì thắng ngay, không chờ
/// vượt ngưỡng kéo như ScrollView.
class _HandlePan extends PanGestureRecognizer {
  _HandlePan(this.hitsHandle);

  final bool Function(Offset local) hitsHandle;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    if (hitsHandle(event.localPosition)) resolve(GestureDisposition.accepted);
  }
}

class _PhaseRow extends StatelessWidget {
  const _PhaseRow({
    required this.phase,
    required this.from,
    required this.to,
    required this.length,
    required this.lockedEnd,
    required this.onStep,
  });

  final GameRoundPhase phase;
  final String from;
  final String to;
  final int length;
  final bool lockedEnd;

  /// Bấm −/+; trả false khi không dời được.
  final bool Function(int dir)? onStep;

  @override
  Widget build(BuildContext context) {
    final step = onStep;
    final color = gamePhaseColor(phase.key);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(gamePhaseIcon(phase.key), size: 16, color: _M.onMoon),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  phase.label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _M.ink,
                  ),
                ),
                Text(
                  '$from – $to',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _M.amberBright,
                  ),
                ),
              ],
            ),
          ),
          if (lockedEnd)
            const Tooltip(
              message: 'Ván km chốt lúc 22h',
              child: Icon(Icons.lock_rounded, size: 14, color: _M.faint),
            ),
          const SizedBox(width: 6),
          GameStepBox(
            label: phase.label,
            value: gameHours(length),
            onDec: step == null || length <= gameMinPhase
                ? null
                : () => step(-1),
            onInc: step == null ? null : () => step(1),
          ),
        ],
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.keys,
    required this.phases,
    required this.start,
    required this.lockEnd,
    required this.active,
  });

  final List<String> keys;
  final List<int> phases;
  final int start;
  final bool lockEnd;
  final int? active;

  static const _ring = 18.0;

  static double _radius(Size size) => size.shortestSide / 2 - _ring / 2 - 22;

  /// Tâm tay nắm của mốc ở phút [minute] trong ngày.
  static Offset handle(Size size, num minute) {
    final a = _angle(minute);
    return size.center(Offset.zero) +
        Offset(math.cos(a), math.sin(a)) * _radius(size);
  }

  /// Góc của phút trong ngày, 0h ở đỉnh.
  static double _angle(num minute) => minute / 1440 * 2 * math.pi - math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = _radius(size);
    final rect = Rect.fromCircle(center: c, radius: r);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _ring;
    canvas.drawCircle(c, r, stroke..color = _M.track);

    var at = 0;
    for (var i = 0; i < phases.length; i++) {
      canvas.drawArc(
        rect,
        _angle(start + at) + 0.012,
        phases[i] / 1440 * 2 * math.pi - 0.024,
        false,
        stroke..color = gamePhaseColor(keys[i]),
      );
      at += phases[i];
    }
    // Phần còn lại của ngày khi vòng ngắn hơn 24 tiếng: nét đứt.
    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = _M.faint;
    for (var m = at + 15; m < 1440 - 10; m += 30) {
      canvas.drawArc(
        rect,
        _angle(start + m),
        15 / 1440 * 2 * math.pi,
        false,
        dash,
      );
    }

    // Vạch giờ và nhãn 0h, 6h, 12h, 18h.
    final tick = Paint()
      ..strokeWidth = 1.5
      ..color = _M.faint;
    final inner = r - _ring / 2 - 4;
    for (var h = 0; h < 24; h++) {
      final a = _angle(h * 60);
      final len = h % 6 == 0 ? 7.0 : 3.0;
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * inner, c + dir * (inner - len), tick);
      if (h % 6 == 0) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${h}h',
            style: const TextStyle(fontSize: 10, color: _M.faint),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          c + dir * (r + _ring / 2 + 12) - Offset(tp.width / 2, tp.height / 2),
        );
      }
    }

    // Mốc: mốc đầu khoá, các mốc giữa kéo được, mốc cuối kéo được khi không khoá.
    var bound = 0;
    for (var m = 0; m <= phases.length; m++) {
      if (m > 0) bound += phases[m - 1];
      if (m == phases.length && bound == 1440) break; // trùng mốc đầu
      final p = handle(size, start + bound);
      final locked = m == 0 || (m == phases.length && lockEnd);
      final color = gamePhaseColor(keys[math.max(0, m - 1)]);
      canvas.drawCircle(
        p,
        m == active ? 13 : 11,
        Paint()..color = locked ? _M.lifted : _M.ink,
      );
      canvas.drawCircle(
        p,
        m == active ? 13 : 11,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = locked ? _M.borderStrong : color,
      );
      if (locked) {
        final icon = Icons.lock_rounded;
        final tp = TextPainter(
          text: TextSpan(
            text: String.fromCharCode(icon.codePoint),
            style: TextStyle(
              fontSize: 12,
              fontFamily: icon.fontFamily,
              package: icon.fontPackage,
              color: _M.faint,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.start != start ||
      old.lockEnd != lockEnd ||
      old.active != active ||
      !_same(old.phases, phases) ||
      !_same(old.keys, keys);

  static bool _same<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
