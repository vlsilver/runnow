import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:myrun/src/screens/route_replay_film.dart';
import 'package:myrun/src/widgets/map_vector.dart';

/// Dải trời ở mép trên màn replay kiểu phim, có mặt trời hoặc trăng.
///
/// Map chỉ nghiêng tới 60° nên không thấy chân trời thật; dải này vẽ đè lên
/// phần map xa nhất và mờ dần xuống dưới.
class ReplaySky extends StatelessWidget {
  const ReplaySky({
    super.key,
    required this.daylight,
    required this.sky,
    required this.bearing,
  });

  final ReplayDaylight daylight;
  final FilmSky sky;

  /// Hướng camera đang nhìn (độ): thiên thể trượt ngang theo khi camera xoay.
  final double bearing;

  @override
  Widget build(BuildContext context) {
    if (sky.shown <= 0) return const SizedBox.shrink();
    return Opacity(
      opacity: sky.shown,
      child: CustomPaint(
        size: Size.infinite,
        painter: _SkyPainter(daylight: daylight, sky: sky, bearing: bearing),
      ),
    );
  }
}

class _SkyPainter extends CustomPainter {
  _SkyPainter({
    required this.daylight,
    required this.sky,
    required this.bearing,
  });

  final ReplayDaylight daylight;
  final FilmSky sky;
  final double bearing;

  /// Nửa góc nhìn ngang của camera, để đổi hướng thành vị trí trên màn.
  static const _halfView = 35.0;

  /// Chân trời nằm ở chừng này phần chiều cao dải trời.
  static const _horizonAt = 0.8;

  @override
  void paint(Canvas canvas, Size size) {
    final horizon = size.height * _horizonAt;
    final (top, low) = _colors();
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [top, low, low.withValues(alpha: 0)],
          stops: const [0, _horizonAt, 1],
        ).createShader(Offset.zero & size),
    );
    if (sky.body == FilmBody.moon) _stars(canvas, size, horizon);

    final turn = ((sky.azimuth - bearing + 540) % 360) - 180;
    if (turn.abs() > _halfView + 15) return;
    final center = Offset(
      size.width / 2 + turn / _halfView * size.width / 2,
      horizon - sky.rise * horizon * 0.8,
    );
    // Khuất dưới chân trời thì cắt đi.
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, size.width, horizon + 2));
    if (sky.body == FilmBody.sun) {
      _sun(canvas, center);
    } else {
      _moon(canvas, center, top);
    }
    canvas.restore();
  }

  /// Màu đỉnh trời và màu sát chân trời. Chiều thì chuyển dần sang hoàng hôn
  /// khi mặt trời xuống thấp.
  (Color, Color) _colors() {
    switch (daylight) {
      case ReplayDaylight.morning:
        return (const Color(0xFF8CC2EE), const Color(0xFFFDE6C8));
      case ReplayDaylight.afternoon:
        final dusk = (1 - sky.rise / 0.6).clamp(0.0, 1.0);
        return (
          Color.lerp(const Color(0xFF7DB4E6), const Color(0xFF4A3F7A), dusk)!,
          Color.lerp(const Color(0xFFFFF2DA), const Color(0xFFFF8A4C), dusk)!,
        );
      case ReplayDaylight.night:
        return (const Color(0xFF070C22), const Color(0xFF26315C));
    }
  }

  void _sun(Canvas canvas, Offset center) {
    final low = (1 - sky.rise / 0.5).clamp(0.0, 1.0);
    final core = Color.lerp(
      const Color(0xFFFFF4C2),
      const Color(0xFFFF7A30),
      low,
    )!;
    canvas.drawCircle(
      center,
      90,
      Paint()
        ..shader = RadialGradient(
          colors: [core.withValues(alpha: 0.55), core.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: 90)),
    );
    canvas.drawCircle(center, 24, Paint()..color = core);
  }

  void _moon(Canvas canvas, Offset center, Color skyTop) {
    canvas.drawCircle(
      center,
      60,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFDDE4FF).withValues(alpha: 0.35),
            const Color(0x00DDE4FF),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: 60)),
    );
    canvas.drawCircle(center, 18, Paint()..color = const Color(0xFFF4F1E1));
    // Trăng khuyết: một vòng màu trời che lệch một bên.
    canvas.drawCircle(
      center + const Offset(8, -5),
      16,
      Paint()..color = skyTop,
    );
  }

  void _stars(Canvas canvas, Size size, double horizon) {
    final random = math.Random(7);
    final paint = Paint()..color = const Color(0xCCFFFFFF);
    for (var i = 0; i < 40; i++) {
      final at = Offset(
        random.nextDouble() * size.width,
        random.nextDouble() * horizon * 0.85,
      );
      canvas.drawCircle(at, random.nextDouble() * 1.2 + 0.4, paint);
    }
  }

  @override
  bool shouldRepaint(_SkyPainter old) =>
      old.sky != sky || old.bearing != bearing || old.daylight != daylight;
}
