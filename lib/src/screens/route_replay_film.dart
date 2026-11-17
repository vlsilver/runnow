import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:latlong2/latlong.dart';
import 'package:myrun/src/widgets/map_vector.dart';

/// Một khung camera của màn replay 3D.
typedef FilmCamera = ({
  LatLng target,
  double zoom,
  double tilt,
  double bearing,
});

/// Các đoạn của tầm nhìn kiểu phim: bay vào, bám người chạy, dừng ở một
/// khoảnh khắc (ảnh, cổ vũ) dọc đường, lùi ra xoay một vòng.
enum FilmPart { intro, run, moment, outro }

/// Đoạn bay vào và đoạn kết dài bao lâu.
const filmIntro = Duration(milliseconds: 2400);
const filmOutro = Duration(milliseconds: 3600);

/// Có trời (biết giờ chạy) thì đoạn mở và đoạn kết dài hơn để kịp thấy mặt
/// trời, trăng mọc lặn.
const filmIntroSky = Duration(milliseconds: 3600);
const filmOutroSky = Duration(milliseconds: 4800);

/// Phần đầu đoạn mở camera đứng ngắm trời trước khi sà xuống.
const _skyHold = 0.35;

/// Lúc ngắm trời camera nghiêng chừng này độ, mức cao nhất MapLibre cho.
const _skyTilt = 60.0;

/// Mỗi lần dừng ở một khoảnh khắc dài bao lâu.
const filmMoment = Duration(milliseconds: 2000);

/// Lúc dừng ở khoảnh khắc, camera lùi ra chừng này mức zoom, ngẩng lên chừng
/// này độ và xoay lệch chừng này độ rồi quay về sau lưng người chạy.
const _momentZoomOut = 1.0;
const _momentTiltUp = 15.0;
const _momentSwing = 60.0;

/// Lúc bắt đầu bay vào, camera xoay lệch hướng chạy chừng này độ rồi xoay dần
/// về sau lưng người chạy.
const _introTurn = 90.0;

/// Đoạn kết dùng chừng này phần đầu để lùi ra, phần còn lại chỉ xoay.
const _outroPullBack = 0.4;

/// Có trời thì đoạn kết xoay xong ở chừng này phần, phần sau để ngắm trời.
const _skyTurnEnd = 0.5;

/// Camera ở thời điểm [t] (0 tới 1) của đoạn [part].
///
/// [chase] là camera bám sau lưng người chạy ở điểm đầu (với [FilmPart.intro])
/// hoặc điểm cuối tuyến (với [FilmPart.outro]); [wide] là camera nhìn cả tuyến.
/// Đoạn [FilmPart.run] trả nguyên [chase]; đoạn [FilmPart.moment] lượn quanh
/// [chase] rồi về lại.
///
/// [lift] là số điểm ảnh logic mà tâm [wide] được đẩy lên trên tâm màn hình,
/// để tuyến nằm giữa phần map không bị bảng số che. Camera càng gần [chase]
/// thì càng đẩy ít, tới [chase] thì còn [chaseLift].
///
/// [chaseLift] là số điểm ảnh logic mà người chạy được đẩy lên lúc bám theo,
/// để đoạn vừa chạy phía sau không nằm dưới bảng số.
///
/// Có [lookAt] (hướng của mặt trời hoặc trăng, độ) thì đoạn mở bắt đầu nghiêng
/// nhìn về hướng đó, đứng ngắm một lúc rồi mới sà xuống; đoạn kết xoay về
/// đúng hướng đó.
FilmCamera filmCamera({
  required FilmPart part,
  required double t,
  required FilmCamera chase,
  required FilmCamera wide,
  double lift = 0,
  double chaseLift = 0,
  double? lookAt,
}) {
  final x = t.clamp(0.0, 1.0);
  switch (part) {
    case FilmPart.run:
      return liftCamera(chase, chaseLift);
    case FilmPart.moment:
      // Đi ra rồi về đúng [chase] nên nối với đoạn chạy không giật.
      final out = math.sin(math.pi * x);
      return liftCamera((
        target: chase.target,
        zoom: chase.zoom - _momentZoomOut * out,
        tilt: math.max(0, chase.tilt - _momentTiltUp * out),
        bearing: (chase.bearing + _momentSwing * out) % 360,
      ), chaseLift);
    case FilmPart.intro:
      final start = (
        target: wide.target,
        zoom: wide.zoom,
        tilt: lookAt == null ? 0.0 : _skyTilt,
        bearing: lookAt ?? chase.bearing - _introTurn,
      );
      final near = Curves.easeInOutCubic.transform(
        lookAt == null ? x : ((x - _skyHold) / (1 - _skyHold)).clamp(0.0, 1.0),
      );
      return liftCamera(
        _between(start, chase, near),
        lift * (1 - near) + chaseLift * near,
      );
    case FilmPart.outro:
      final back = Curves.easeInOutCubic.transform(
        (x / _outroPullBack).clamp(0.0, 1.0),
      );
      final moved = _between(chase, (
        target: wide.target,
        zoom: wide.zoom,
        tilt: wide.tilt,
        bearing: chase.bearing,
      ), back);
      // Không có trời thì xoay đủ một vòng, chậm dần ở cuối. Có trời thì
      // xoay xong sớm, dừng đúng hướng mặt trời, trăng để kịp thấy nó mọc
      // hay lặn ở giữa khung; xoay ít nhất 120° cho thấy chuyển động.
      final double turn;
      if (lookAt == null) {
        turn = 360 * Curves.easeOutCubic.transform(x);
      } else {
        final toward = (lookAt - chase.bearing) % 360;
        final total = toward < 120 ? toward + 360 : toward;
        turn =
            total *
            Curves.easeInOutCubic.transform((x / _skyTurnEnd).clamp(0.0, 1.0));
      }
      return liftCamera((
        target: moved.target,
        zoom: moved.zoom,
        tilt: moved.tilt,
        bearing: (chase.bearing + turn) % 360,
      ), lift * back + chaseLift * (1 - back));
  }
}

/// Dời tâm camera về phía người xem để chỗ đang ở tâm hiện cao hơn [points]
/// điểm ảnh logic. Ước lượng bậc nhất quanh tâm màn hình: mặt đất nghiêng
/// [FilmCamera.tilt] độ thì co theo chiều dọc cos(tilt) lần.
FilmCamera liftCamera(FilmCamera camera, double points) {
  if (points == 0) return camera;
  final lat = camera.target.latitude;
  // MapLibre: zoom 0 ở xích đạo là 78271,517 m mỗi điểm ảnh logic.
  final metersPerPoint =
      78271.517 * math.cos(lat * math.pi / 180) / math.pow(2, camera.zoom);
  final meters =
      points * metersPerPoint / math.cos(camera.tilt * math.pi / 180);
  return (
    target: const Distance(
      roundResult: false,
    ).offset(camera.target, meters, (camera.bearing + 180) % 360),
    zoom: camera.zoom,
    tilt: camera.tilt,
    bearing: camera.bearing,
  );
}

FilmCamera _between(FilmCamera a, FilmCamera b, double t) {
  double lerp(double from, double to) => from + (to - from) * t;
  // Đi đường xoay ngắn nhất giữa hai hướng.
  final turn = ((b.bearing - a.bearing + 540) % 360) - 180;
  return (
    target: LatLng(
      lerp(a.target.latitude, b.target.latitude),
      lerp(a.target.longitude, b.target.longitude),
    ),
    zoom: lerp(a.zoom, b.zoom),
    tilt: lerp(a.tilt, b.tilt),
    bearing: (a.bearing + turn * t) % 360,
  );
}

/// Những chỗ camera dừng lại, lấy từ vị trí các khoảnh khắc [fractions] (0 tới
/// 1 trên tuyến): theo thứ tự trên tuyến, bỏ chỗ sát đầu hay sát cuối, và gần
/// chỗ trước dưới [minGap] thì gộp làm một.
List<double> filmStops(Iterable<double> fractions, {double minGap = 0.03}) {
  final stops = <double>[];
  for (final at in fractions.toList()..sort()) {
    if (at < minGap || at > 1 - minGap) continue;
    if (stops.isNotEmpty && at - stops.last < minGap) continue;
    stops.add(at);
  }
  return stops;
}

/// Ở thời điểm [t] của đoạn kết, vệt sáng chạy dọc tuyến tới đâu (0 tới 1).
/// Vệt chạy sau khi camera lùi ra xong; ngoài lúc đó thì null.
double? filmSweep(double t) {
  const from = _outroPullBack;
  const to = 0.85;
  if (t < from || t > to) return null;
  return Curves.easeInOutCubic.transform((t - from) / (to - from));
}

/// Ở thời điểm [t] của đoạn kết, tem tổng kết hiện rõ tới đâu (0 tới 1).
/// Tem hiện sau khi mặt trời đã lặn để không che nó.
double filmStamp(double t) => ((t - 0.85) / 0.1).clamp(0.0, 1.0);

/// Mặt trời hay trăng.
enum FilmBody { sun, moon }

/// Trời ở một thời điểm của đoạn mở hoặc đoạn kết: [shown] trời hiện rõ tới
/// đâu (0 tới 1), [rise] thiên thể cao tới đâu (0 là chân trời, 1 là đỉnh
/// dải trời, âm là đã khuất).
typedef FilmSky = ({FilmBody body, double azimuth, double shown, double rise});

/// Hướng (độ, tính từ bắc) của thiên thể buổi [daylight]: mặt trời buổi sáng
/// ở phía đông, buổi chiều ở phía tây; trăng ở phía đông nam.
double filmSkyAzimuth(ReplayDaylight daylight) => switch (daylight) {
  ReplayDaylight.morning => 100,
  ReplayDaylight.afternoon => 260,
  ReplayDaylight.night => 130,
};

/// Trời kiểu dựng phim: sáng thì mặt trời mọc lúc mở và lên cao lúc kết;
/// chiều thì mặt trời đứng cao lúc mở và lặn lúc kết; tối thì trăng lên dần.
FilmSky? filmSky(ReplayDaylight daylight, FilmPart part, double t) {
  final x = t.clamp(0.0, 1.0);
  double ease(double from, double to) =>
      Curves.easeInOut.transform(((x - from) / (to - from)).clamp(0.0, 1.0));
  double lerp(double a, double b, double k) => a + (b - a) * k;
  final body = daylight == ReplayDaylight.night ? FilmBody.moon : FilmBody.sun;
  final azimuth = filmSkyAzimuth(daylight);
  switch (part) {
    case FilmPart.run || FilmPart.moment:
      return null;
    case FilmPart.intro:
      final rising = ease(0, 0.6);
      return (
        body: body,
        azimuth: azimuth,
        shown: 1 - ease(_skyHold, 0.65),
        rise: switch (daylight) {
          ReplayDaylight.morning => lerp(-0.25, 0.45, rising),
          ReplayDaylight.afternoon => lerp(0.75, 0.65, rising),
          ReplayDaylight.night => lerp(0.2, 0.55, rising),
        },
      );
    case FilmPart.outro:
      final moving = ease(_skyTurnEnd, 0.95);
      return (
        body: body,
        azimuth: azimuth,
        shown: ease(_outroPullBack, 0.6),
        rise: switch (daylight) {
          ReplayDaylight.morning => lerp(0.4, 0.8, moving),
          ReplayDaylight.afternoon => lerp(0.6, -0.3, moving),
          ReplayDaylight.night => lerp(0.35, 0.8, moving),
        },
      );
  }
}
