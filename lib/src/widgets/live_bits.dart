import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:myrun/src/models.dart';
import 'package:myrun/src/theme.dart';

/// Thời gian chạy của một phiên live tại [now]. App người chạy ghi
/// `movingTimeSeconds` mỗi ~5 giây, nên giữa hai lần ghi người xem tự cộng
/// thêm khoảng từ `updatedAt` tới giờ. Khoảng cộng thêm kẹp trong 0–180 giây:
/// đồng hồ máy người xem lệch giờ server thì không chạy lùi hay vọt lên, và
/// quá 3 phút không ai ghi thì phiên coi như mất tín hiệu.
int liveElapsedSeconds(LiveTrackingSession session, DateTime now) {
  if (session.status != LiveTrackingStatus.running) {
    return session.movingTimeSeconds;
  }
  final sinceWrite = now.difference(session.updatedAt).inSeconds.clamp(0, 180);
  return session.movingTimeSeconds + sinceWrite;
}

/// Đường đã chạy của một phiên live: `routePreview` (đã thưa bớt) nối thêm
/// `lastLocation` nếu điểm cuối chưa có trong đó, để chấm đang chạy luôn ở
/// chỗ mới nhất.
List<LatLng> liveRoutePoints(LiveTrackingSession session) {
  final points = [
    for (final p in session.routePreview) LatLng(p.latitude, p.longitude),
  ];
  final last = session.lastLocation;
  if (last != null) {
    final here = LatLng(last.latitude, last.longitude);
    if (points.isEmpty || points.last != here) points.add(here);
  }
  return points;
}

/// Đọc lại [builder] mỗi giây, cho đồng hồ live.
class EverySecond extends StatefulWidget {
  const EverySecond({required this.builder, super.key});

  final Widget Function(BuildContext context, DateTime now) builder;

  @override
  State<EverySecond> createState() => _EverySecondState();
}

class _EverySecondState extends State<EverySecond> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, DateTime.now());
}

class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: RunNowSemanticColors.danger,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LiveDot(color: Colors.white, size: 7),
            SizedBox(width: 6),
            Text(
              'LIVE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chấm nhấp nháy báo đang live.
class LiveDot extends StatefulWidget {
  const LiveDot({required this.color, this.size = 8, super.key});

  final Color color;
  final double size;

  @override
  State<LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<LiveDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.25, end: 1.0).animate(_controller),
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      ),
    );
  }
}

/// Chấm vị trí hiện tại với hai vòng sóng lan ra.
class PulsingDot extends StatefulWidget {
  const PulsingDot({required this.color, this.size = 16, super.key});

  final Color color;
  final double size;

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final extent = widget.size * 4;
    return SizedBox.square(
      dimension: extent,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _PulsePainter(
            color: widget.color,
            core: widget.size,
            phase: _controller.isAnimating ? _controller.value : null,
          ),
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({required this.color, required this.core, this.phase});

  final Color color;
  final double core;
  final double? phase;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.shortestSide / 2;
    if (phase != null) {
      for (final offset in [0.0, 0.5]) {
        final t = (phase! + offset) % 1;
        canvas.drawCircle(
          center,
          core / 2 + (maxRadius - core / 2) * t,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = color.withValues(alpha: (1 - t) * 0.7),
        );
      }
    }
    canvas.drawCircle(center, core / 2 + 2.5, Paint()..color = Colors.white);
    canvas.drawCircle(center, core / 2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_PulsePainter old) =>
      old.phase != phase || old.color != color;
}

/// Đường chạy vẽ thẳng lên nền (không tile bản đồ), có một lớp sáng mờ bên
/// dưới. Dùng ở ô live nhỏ trên trang Kèo, nơi tải tile cho từng ô thì tốn.
class LiveRouteSketch extends StatelessWidget {
  const LiveRouteSketch({
    required this.points,
    required this.color,
    this.padding = const EdgeInsets.fromLTRB(28, 46, 28, 70),
    super.key,
  });

  final List<RoutePoint> points;
  final Color color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        final projected = projectRoute(points, padding.deflateSize(size));
        final shifted = [
          for (final p in projected) p + Offset(padding.left, padding.top),
        ];
        return Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(painter: _RouteSketchPainter(shifted, color)),
            ),
            if (shifted.isNotEmpty)
              Positioned(
                left: shifted.last.dx - 32,
                top: shifted.last.dy - 32,
                child: PulsingDot(color: color),
              ),
          ],
        );
      },
    );
  }
}

/// Chiếu các điểm GPS vào khung [box], giữ tỉ lệ (kinh độ co theo vĩ độ) và
/// canh giữa. Ít hơn hai điểm thì trả nguyên một điểm giữa khung hoặc rỗng.
List<Offset> projectRoute(List<RoutePoint> points, Size box) {
  if (points.isEmpty || box.isEmpty) return const [];
  final latScale = math.cos(points.first.latitude * math.pi / 180);
  final xs = [for (final p in points) p.longitude * latScale];
  final ys = [for (final p in points) -p.latitude];
  final minX = xs.reduce(math.min), maxX = xs.reduce(math.max);
  final minY = ys.reduce(math.min), maxY = ys.reduce(math.max);
  final spanX = maxX - minX, spanY = maxY - minY;
  if (spanX == 0 && spanY == 0) return [box.center(Offset.zero)];
  final scale = math.min(
    spanX == 0 ? double.infinity : box.width / spanX,
    spanY == 0 ? double.infinity : box.height / spanY,
  );
  final dx = (box.width - spanX * scale) / 2;
  final dy = (box.height - spanY * scale) / 2;
  return [
    for (var i = 0; i < points.length; i++)
      Offset(dx + (xs[i] - minX) * scale, dy + (ys[i] - minY) * scale),
  ];
}

class _RouteSketchPainter extends CustomPainter {
  _RouteSketchPainter(this.points, this.color);

  final List<Offset> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final p in points.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RouteSketchPainter old) =>
      old.points != points || old.color != color;
}
