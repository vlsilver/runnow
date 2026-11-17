import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:maplibre_gl/maplibre_gl.dart' as ml;
import 'package:path_provider/path_provider.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/screens/route_replay_film.dart';
import 'package:myrun/src/screens/route_replay_pins.dart';
import 'package:myrun/src/screens/route_replay_sky.dart';
import 'package:myrun/src/share.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/cached_avatar.dart';
import 'package:myrun/src/widgets/map_vector.dart';
import 'package:myrun/src/widgets/run_now_avatar.dart';

const _zoomRange = (10.0, 18.0);
// MapLibre không nghiêng quá 60°.
const _maxTilt = 60.0;

/// Dải trời của tầm nhìn kiểu phim cao chừng này phần màn hình.
const _skyBand = 0.34;
const _avatarSize = 44.0;

/// Hình người chạy cao chừng này tính từ chân cọc lên.
const _pinLift = 76.0;
const _distance = Distance(roundResult: false);

/// Kênh quay màn hình bằng ReplayKit (ScreenClipRecorder trong AppDelegate).
const _screenClip = MethodChannel('runnow/screen_clip');

/// Quay cửa sổ app mới chỉ có trên iOS.
bool get _canShareClip =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Replay dài bao lâu: 2,5 giây cho mỗi km, kẹp trong 12 đến 20 giây. Buổi
/// chạy trên 8 km thì phát nhanh dần lên để video không dài quá 20 giây.
Duration replayDuration(double meters) =>
    Duration(milliseconds: (meters * 2.5).clamp(12000, 20000).round());

/// Tốc độ (m/s) dọc quãng đường, chia [bins] đoạn dài bằng nhau rồi trung
/// bình trượt ±[smooth] đoạn cho đường cong không răng cưa. Đoạn đứng nghỉ ra
/// tốc độ thấp đúng như thật. Trả null khi mốc giờ của [points] không đủ để
/// tính.
List<double>? speedProfile(
  List<RoutePoint> points, {
  int bins = 96,
  int smooth = 2,
}) {
  if (points.length < 2) return null;
  final meters = <double>[0];
  final seconds = <double>[0];
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1], b = points[i];
    meters.add(
      meters.last +
          _distance(
            LatLng(a.latitude, a.longitude),
            LatLng(b.latitude, b.longitude),
          ),
    );
    final gap = b.timestamp.difference(a.timestamp).inMilliseconds / 1000;
    seconds.add(seconds.last + math.max(0, gap));
  }
  if (meters.last <= 0 || seconds.last <= 0) return null;
  final step = meters.last / bins;
  // Mốc giờ tại ranh của từng đoạn, nội suy giữa hai điểm GPS kề nhau.
  final marks = <double>[0];
  var at = 1;
  for (var k = 1; k <= bins; k++) {
    final target = math.min(step * k, meters.last);
    while (at < meters.length - 1 && meters[at] < target) {
      at++;
    }
    final span = meters[at] - meters[at - 1];
    final t = span <= 0 ? 1.0 : (target - meters[at - 1]) / span;
    marks.add(seconds[at - 1] + (seconds[at] - seconds[at - 1]) * t);
  }
  final raw = [
    for (var k = 0; k < bins; k++)
      marks[k + 1] > marks[k] ? step / (marks[k + 1] - marks[k]) : 0.0,
  ];
  return _smoothed(raw, smooth);
}

/// Trung bình trượt ±[reach] phần tử.
List<double> _smoothed(List<double> raw, int reach) => [
  for (var k = 0; k < raw.length; k++)
    () {
      final from = math.max(0, k - reach);
      final to = math.min(raw.length - 1, k + reach);
      var sum = 0.0;
      for (var j = from; j <= to; j++) {
        sum += raw[j];
      }
      return sum / (to - from + 1);
    }(),
];

/// Lấy [values] đo tại các mốc [distances] (mét, tăng dần) về [bins] điểm cách
/// đều theo quãng đường rồi làm mượt. Trả null khi hai chuỗi không khớp nhau.
List<double>? streamProfile(
  List<double>? values,
  List<double>? distances, {
  int bins = 96,
  int smooth = 2,
}) {
  if (values == null || distances == null) return null;
  if (values.length < 2 || values.length != distances.length) return null;
  final start = distances.first;
  final total = distances.last - start;
  if (total <= 0) return null;
  final raw = <double>[];
  var at = 1;
  for (var k = 0; k < bins; k++) {
    final target = start + total * (k + 0.5) / bins;
    while (at < distances.length - 1 && distances[at] < target) {
      at++;
    }
    final span = distances[at] - distances[at - 1];
    final t = span <= 0 ? 1.0 : (target - distances[at - 1]) / span;
    raw.add(values[at - 1] + (values[at] - values[at - 1]) * t);
  }
  return _smoothed(raw, smooth);
}

/// Một đường biểu đồ chạy cùng replay; [values] rải đều theo quãng đường.
class ReplaySeries {
  const ReplaySeries({
    required this.label,
    required this.values,
    required this.format,
  });

  final String label;
  final List<double> values;
  final String Function(double value) format;
}

/// Nhãn của biểu đồ pace; [ReplaySeries.values] của nó là tốc độ (m/s).
const replayPaceLabel = 'PACE';

/// Các biểu đồ dựng được từ số liệu buổi chạy đang có: pace, nhịp tim, độ
/// cao. Loại nào thiếu số liệu thì không có mặt.
List<ReplaySeries> replaySeries({
  List<RoutePoint>? routePoints,
  Map<String, List<double>> streams = const {},
}) {
  final distances = streams['distance'];
  final timed = routePoints ?? const <RoutePoint>[];
  final speeds =
      speedProfile(timed) ??
      streamProfile(streams['velocity_smooth'], distances);
  final heartRates = streamProfile(streams['heartrate'], distances);

  final high = [
    for (final point in timed)
      if (point.altitudeMeters != null) point,
  ];
  final highMeters = <double>[0];
  for (var i = 1; i < high.length; i++) {
    highMeters.add(
      highMeters.last +
          _distance(
            LatLng(high[i - 1].latitude, high[i - 1].longitude),
            LatLng(high[i].latitude, high[i].longitude),
          ),
    );
  }
  final altitudes =
      streamProfile(
        [for (final point in high) point.altitudeMeters!],
        [if (high.isNotEmpty) ...highMeters],
      ) ??
      streamProfile(streams['altitude'], distances);

  return [
    if (speeds != null)
      ReplaySeries(
        label: replayPaceLabel,
        values: speeds,
        format: (speed) => formatPace(speed <= 0 ? null : 1000 / speed),
      ),
    if (heartRates != null)
      ReplaySeries(
        label: 'NHỊP TIM',
        values: heartRates,
        format: (bpm) => '${bpm.round()} bpm',
      ),
    if (altitudes != null)
      ReplaySeries(
        label: 'ĐỘ CAO',
        values: altitudes,
        format: (meters) => '${meters.round()} m',
      ),
  ];
}

/// Tuyến đã làm mượt để camera bay theo: GPS thô rung vài mét mỗi điểm, bám
/// đúng từng điểm thì đường gãy và camera lắc.
class ReplayPath {
  ReplayPath._(this.points, this._cumulative, this._bearings);

  /// Lấy mẫu lại [raw] mỗi 5 m, rồi trung bình trượt ±25 m.
  factory ReplayPath(List<LatLng> raw) {
    final even = _resample(raw, 5);
    final points = [for (var i = 0; i < even.length; i++) _mean(even, i, 5)];
    final cumulative = <double>[0];
    for (var i = 1; i < points.length; i++) {
      cumulative.add(cumulative.last + _distance(points[i - 1], points[i]));
    }
    return ReplayPath._(points, cumulative, _smoothBearings(points));
  }

  final List<LatLng> points;
  final List<double> _cumulative;

  /// Hướng camera ở từng điểm, đã bỏ bước nhảy 360° nên nội suy thẳng được.
  final List<double> _bearings;

  double get meters => _cumulative.last;

  static List<LatLng> _resample(List<LatLng> raw, double step) {
    final out = [raw.first];
    var carried = 0.0;
    for (var i = 1; i < raw.length; i++) {
      final a = raw[i - 1], b = raw[i];
      final span = _distance(a, b);
      if (span <= 0) continue;
      for (var at = step - carried; at <= span; at += step) {
        final t = at / span;
        out.add(
          LatLng(
            a.latitude + (b.latitude - a.latitude) * t,
            a.longitude + (b.longitude - a.longitude) * t,
          ),
        );
      }
      carried = (carried + span) % step;
    }
    if (out.length < 2 || out.last != raw.last) out.add(raw.last);
    return out;
  }

  /// Trung bình các điểm cách [i] không quá [reach] mẫu; gần hai đầu thì thu
  /// cửa sổ lại để điểm đầu, điểm cuối giữ nguyên chỗ.
  static LatLng _mean(List<LatLng> points, int i, int reach) {
    final r = math.min(reach, math.min(i, points.length - 1 - i));
    var lat = 0.0, lng = 0.0;
    for (var j = i - r; j <= i + r; j++) {
      lat += points[j].latitude;
      lng += points[j].longitude;
    }
    return LatLng(lat / (2 * r + 1), lng / (2 * r + 1));
  }

  /// Hướng nhìn tới điểm cách 80 m phía trước, rồi trung bình trượt ±60 m.
  static List<double> _smoothBearings(List<LatLng> points) {
    final last = points.length - 1;
    // Nhìn trước và lấy trung bình trên 6% tuyến mỗi phía. Replay tua cả buổi
    // chạy trong 12 đến 20 giây, nên cửa sổ cố định theo mét sẽ làm camera
    // giật theo từng khúc cua trên tuyến dài.
    final ahead = math.max(16, (last * 0.06).round());
    final reach = math.max(12, (last * 0.06).round());
    final raw = <double>[];
    for (var i = 0; i <= last; i++) {
      final from = math.min(i, math.max(0, last - ahead));
      final to = math.min(last, from + ahead);
      var bearing = from == to
          ? 0.0
          : _distance.bearing(points[from], points[to]);
      if (raw.isNotEmpty) {
        // Giữ liên tục với điểm trước, không quay vòng qua ±180°.
        bearing = raw.last + ((bearing - raw.last + 540) % 360 - 180);
      }
      raw.add(bearing);
    }
    return [
      for (var i = 0; i <= last; i++)
        () {
          final lo = math.max(0, i - reach), hi = math.min(last, i + reach);
          var sum = 0.0;
          for (var j = lo; j <= hi; j++) {
            sum += raw[j];
          }
          return sum / (hi - lo + 1);
        }(),
    ];
  }

  /// Vị trí và hướng camera khi đã đi [progress] (0..1) chiều dài tuyến.
  ({LatLng point, double bearing}) at(double progress) {
    final target = meters * progress.clamp(0.0, 1.0);
    var low = 1, high = _cumulative.length - 1;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (_cumulative[mid] < target) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    final a = points[low - 1], b = points[low];
    final span = _cumulative[low] - _cumulative[low - 1];
    final t = span <= 0 ? 0.0 : (target - _cumulative[low - 1]) / span;
    return (
      point: LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      ),
      bearing:
          (_bearings[low - 1] + (_bearings[low] - _bearings[low - 1]) * t) %
          360,
    );
  }
}

/// Một thứ xảy ra dọc đường: ảnh chụp hoặc một lần được cổ vũ.
class ReplayMoment {
  const ReplayMoment.photo({
    required this.distanceMeters,
    required String this.photoPath,
  }) : emoji = null,
       avatarUrl = null;

  const ReplayMoment.cheer({
    required this.distanceMeters,
    required String this.emoji,
    this.avatarUrl,
  }) : photoPath = null;

  /// Quãng đường người chạy đã đi lúc đó.
  final double distanceMeters;
  final String? photoPath;
  final String? emoji;

  /// Ảnh của người cổ vũ.
  final String? avatarUrl;

  @override
  bool operator ==(Object other) =>
      other is ReplayMoment &&
      other.distanceMeters == distanceMeters &&
      other.photoPath == photoPath &&
      other.emoji == emoji &&
      other.avatarUrl == avatarUrl;

  @override
  int get hashCode => Object.hash(distanceMeters, photoPath, emoji, avatarUrl);

  /// Vị trí trên buổi chạy dài [totalMeters], từ 0 tới 1. Cổ vũ lúc live có
  /// thể ghi quãng đường nhỉnh hơn số chốt của buổi chạy, nên kẹp về đích.
  double fraction(double totalMeters) =>
      totalMeters <= 0 ? 0 : (distanceMeters / totalMeters).clamp(0.0, 1.0);
}

/// Những [moments] đang hiện khi replay ở [progress]: người chạy vừa đi qua
/// và chưa đi quá [linger] (cùng thang 0 tới 1), theo thứ tự dọc đường.
List<ReplayMoment> replayMomentsAt(
  List<ReplayMoment> moments,
  double progress, {
  required double totalMeters,
  double linger = 0.07,
}) {
  final shown = [
    for (final moment in moments)
      if (moment.fraction(totalMeters) <= progress &&
          progress - moment.fraction(totalMeters) < linger)
        moment,
  ];
  return shown..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));
}

/// BẢN THỬ: xem lại buổi chạy với camera nghiêng bay theo tuyến, nhà dựng khối.
class RouteReplayScreen extends StatefulWidget {
  const RouteReplayScreen({
    super.key,
    required this.points,
    this.distanceMeters,
    this.movingTimeSeconds,
    this.startedAt,
    this.avatarUrl,
    this.series = const [],
    this.moments = const [],
  });

  final List<LatLng> points;
  final double? distanceMeters;
  final int? movingTimeSeconds;

  /// Lúc bắt đầu buổi chạy; map tô theo giờ trong ngày. Thiếu thì theo theme.
  final DateTime? startedAt;
  final String? avatarUrl;

  /// Kết quả của [replaySeries]; rỗng thì không vẽ biểu đồ.
  final List<ReplaySeries> series;

  /// Ảnh chụp và cổ vũ dọc đường, hiện khi người chạy tới đúng chỗ.
  final List<ReplayMoment> moments;

  @override
  State<RouteReplayScreen> createState() => _RouteReplayScreenState();
}

class _RouteReplayScreenState extends State<RouteReplayScreen>
    with TickerProviderStateMixin {
  late final ReplayPath _path = ReplayPath(widget.points);
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: replayDuration(_path.meters),
  )..addListener(_syncMap);
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: _daylight == null ? filmIntro : filmIntroSky,
  )..addListener(_syncMap);
  late final AnimationController _outro = AnimationController(
    vsync: this,
    duration: _daylight == null ? filmOutro : filmOutroSky,
  )..addListener(_syncMap);
  late final AnimationController _moment = AnimationController(
    vsync: this,
    duration: filmMoment,
  )..addListener(_syncMap);

  /// Đoạn đang phát của tầm nhìn kiểu phim. Bắt đầu ở đầu đoạn bay vào để
  /// khung đầu tiên của map đã là góc cao, không chớp góc gần.
  FilmPart _part = FilmPart.intro;

  /// Thang quãng đường của [RouteReplayScreen.moments]: số chốt của buổi
  /// chạy, thiếu thì lấy độ dài tuyến.
  late final double _momentMeters = widget.distanceMeters ?? _path.meters;

  /// Vị trí trên tuyến (0 tới 1) của các khoảnh khắc có ghim: ảnh, cổ vũ.
  late final List<double> _momentFractions = [
    for (final moment in widget.moments)
      if (moment.photoPath != null || moment.emoji != null)
        moment.fraction(_momentMeters),
  ];

  /// Buổi trong ngày của buổi chạy; null là không biết giờ chạy, map theo
  /// theme và không có trời.
  late final ReplayDaylight? _daylight = switch (widget.startedAt) {
    final at? => replayDaylightAt(at.toLocal()),
    null => null,
  };

  /// Màu theo theme, giữ lại để dùng được ở chỗ không có lượt build (đồng bộ
  /// map, vẽ ghim).
  late ReplayColors _colors;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _colors = ReplayColors.of(context.runNowPalette);
  }

  ml.MapLibreMapController? _map;
  bool _styleReady = false;
  bool _sending = false;

  /// Cột mốc km và ảnh cắm trên tuyến, đã có hình trên map. Người chạy đi tới
  /// cái nào thì cái đó hiện ra và ở lại.
  final List<({double fraction, String icon, LatLng point, int layer})> _pins =
      [];

  /// Số ghim đang hiện trên map; null là layer ghim chưa dựng xong.
  int? _pinsShown;

  /// Có thay đổi tới lúc [_sending] nên chưa sang được map.
  bool _stale = false;

  // Góc nhìn người xem tự chỉnh: chụm để zoom, vuốt ngang để xoay quanh
  // người chạy, vuốt dọc để nghiêng.
  // Mặc định lùi ra đủ xa để thấy cả tuyến cùng các ghim trên đó.
  late final double _fitZoom = replayFitZoom(
    _path.points,
    span: MediaQuery.sizeOf(context).width * 0.8,
  );
  late final LatLng _center = replayCenter(_path.points);

  /// Người chạy lệch khỏi tâm màn hình bao nhiêu. Camera bám người chạy thì
  /// bằng 0; camera đứng yên thì hỏi map vị trí người chạy sau mỗi nhịp.
  final _runnerShift = ValueNotifier(Offset.zero);
  late double _zoom = _view.zoom(_fitZoom)!;
  ReplayView _view = ReplayView.film;

  void _nextView() {
    setState(() {
      _view = _view.next;
      _zoom = _view.zoom(_fitZoom)!;
    });
    _syncMap();
  }

  double _tilt = _maxTilt;
  double _spin = 0;
  late double _zoomAtPinchStart = _zoom;

  void _onViewGesture(ScaleUpdateDetails details) {
    if (details.pointerCount > 1) {
      if (_view != ReplayView.custom) {
        setState(() => _view = ReplayView.custom);
      }
      _zoom = (_zoomAtPinchStart + math.log(details.scale) / math.ln2).clamp(
        _zoomRange.$1,
        _zoomRange.$2,
      );
    } else {
      _spin = (_spin + details.focalPointDelta.dx * 0.4) % 360;
      _tilt = (_tilt - details.focalPointDelta.dy * 0.3).clamp(0, _maxTilt);
    }
    _syncMap();
  }

  /// Đang quay video để share: ẩn các nút cho khỏi lọt vào hình.
  bool _recording = false;

  /// Người dùng bấm huỷ giữa lúc quay.
  bool _clipCancelled = false;

  /// Khổ của video đang quay; vùng quay và chỗ đặt nhãn cùng theo khổ này.
  ShareFormat _clipFormat = ShareFormat.story;

  final _hudKey = GlobalKey();

  /// Khoảng từ tâm màn hình lên tâm phần map còn thấy (từ mép trên tới bảng
  /// số): đẩy tâm toàn cảnh lên chừng này thì tuyến nằm giữa phần đó. Lúc quay
  /// video thì mép trên là mép khung quay. [sky]: tính cả dải trời của tầm
  /// nhìn kiểu phim là phần bị che. Chưa dựng xong thì 0.
  double _hudLift({bool sky = false}) {
    final hud = _hudKey.currentContext?.findRenderObject() as RenderBox?;
    if (hud == null || !hud.hasSize) return 0;
    final screen = MediaQuery.sizeOf(context);
    var top = _recording
        ? replayClipRect(screen, aspect: _clipFormat.aspect).top
        : 0.0;
    // Có dải trời thì tuyến nằm dưới dải trời.
    if (sky && _daylight != null) {
      top = math.max(top, _skyRect(screen).bottom);
    }
    final bottom = hud.localToGlobal(Offset.zero).dy;
    return math.max(0, screen.height / 2 - (top + bottom) / 2);
  }

  /// Chỗ của dải trời: mép trên màn hình, lúc quay thì mép trên khung quay để
  /// mặt trời, trăng không bị cắt khỏi video.
  Rect _skyRect(Size screen) {
    final frame = _recording
        ? replayClipRect(screen, aspect: _clipFormat.aspect)
        : Offset.zero & screen;
    return Rect.fromLTWH(
      frame.left,
      frame.top,
      frame.width,
      frame.height * _skyBand,
    );
  }

  ml.CameraPosition _camera(double progress) {
    if (_view == ReplayView.film) {
      final at = switch (_part) {
        FilmPart.intro => 0.0,
        FilmPart.run || FilmPart.moment => progress,
        FilmPart.outro => 1.0,
      };
      final now = _path.at(at);
      final shot = filmCamera(
        part: _part,
        t: switch (_part) {
          FilmPart.intro => _intro.value,
          FilmPart.moment => _moment.value,
          FilmPart.outro => _outro.value,
          FilmPart.run => 0,
        },
        chase: (
          target: now.point,
          zoom: _zoom,
          tilt: _tilt,
          bearing: now.bearing + _spin,
        ),
        wide: (target: _center, zoom: _fitZoom, tilt: 45, bearing: 0),
        lift: _hudLift(sky: true),
        chaseLift: _hudLift(),
        lookAt: switch (_daylight) {
          final daylight? => filmSkyAzimuth(daylight),
          null => null,
        },
      );
      return ml.CameraPosition(
        target: ml.LatLng(shot.target.latitude, shot.target.longitude),
        zoom: shot.zoom,
        tilt: shot.tilt,
        bearing: shot.bearing,
      );
    }
    if (_view.overview) {
      return ml.CameraPosition(
        target: ml.LatLng(_center.latitude, _center.longitude),
        zoom: _zoom,
        tilt: _tilt,
        bearing: _spin,
      );
    }
    final now = _path.at(progress);
    // Người chạy nằm giữa phần map trên bảng số, không bị bảng số che.
    final shot = liftCamera((
      target: now.point,
      zoom: _zoom,
      tilt: _tilt,
      bearing: now.bearing + _spin,
    ), _hudLift());
    return ml.CameraPosition(
      target: ml.LatLng(shot.target.latitude, shot.target.longitude),
      zoom: shot.zoom,
      tilt: shot.tilt,
      bearing: shot.bearing,
    );
  }

  /// Đẩy tiến độ hiện tại sang map. Lệnh trước chưa xong thì bỏ nhịp này, nhịp
  /// sau sẽ mang tiến độ mới hơn.
  Future<void> _syncMap() async {
    final map = _map;
    if (map == null || !_styleReady) return;
    if (_sending) {
      _stale = true;
      return;
    }
    _sending = true;
    _stale = false;
    try {
      final progress = _progress.value;
      final sweep = _view == ReplayView.film && _part == FilmPart.outro
          ? filmSweep(_outro.value)
          : null;
      final gradients = sweep == null
          ? replayDoneGradients(
              progress,
              line: _colors.line,
              outline: _colors.night,
            )
          : replaySweepGradients(
              sweep,
              line: _colors.line,
              outline: _colors.night,
              glow: _colors.paper,
            );
      final reached = [
        for (final pin in _pins)
          if (pin.fraction <= progress) pin,
      ];
      await Future.wait([
        if (_pinsShown != null && _pinsShown != reached.length)
          map.setGeoJsonSource(_pinSource, _pinFeatures(reached)),
        map.moveCamera(ml.CameraUpdate.newCameraPosition(_camera(progress))),
        for (var i = 0; i < replayDoneLayers.length; i++)
          map.setLayerProperties(
            replayDoneLayers[i],
            // Plugin ghi đè cả bộ thuộc tính, cái nào bỏ trống thì về mặc định.
            ml.LineLayerProperties(
              lineGradient: gradients[i],
              lineWidth: replayDoneWidths[i],
              lineCap: 'round',
              lineJoin: 'round',
            ),
          ),
      ]);
      if (_pinsShown != null) _pinsShown = reached.length;
      // Hỏi map người chạy đang ở đâu trên màn, kể cả lúc camera bám theo:
      // camera bám thì người chạy được đẩy lên trên bảng số, không nằm đúng
      // tâm.
      final runner = _path.at(progress).point;
      final at = await map.toScreenLocation(
        ml.LatLng(runner.latitude, runner.longitude),
      );
      if (!mounted) return;
      final size = context.size;
      if (size == null) return;
      _runnerShift.value =
          Offset(at.x.toDouble(), at.y.toDouble()) - size.center(Offset.zero);
    } finally {
      _sending = false;
    }
    // Lúc replay đứng yên không có nhịp sau nào mang thay đổi bị bỏ lỡ sang.
    if (_stale && mounted) return _syncMap();
  }

  void _onStyleLoaded() {
    _styleReady = true;
    _replay();
    _addPins();
  }

  /// Phát lại từ đầu. Tầm nhìn kiểu phim có thêm đoạn bay vào và đoạn kết.
  /// Gọi lần nữa giữa chừng thì lượt cũ ném [TickerCanceled] và dừng.
  Future<void> _play() async {
    _stopPlayback();
    if (_view != ReplayView.film) {
      _part = FilmPart.run;
      return _progress.forward(from: 0).orCancel;
    }
    _part = FilmPart.intro;
    _progress.value = 0;
    // Báo cho tem tổng kết và trời của đoạn kết lượt trước tắt đi.
    _outro.value = 0;
    await _intro.forward(from: 0).orCancel;
    for (final stop in filmStops(_momentFractions)) {
      _part = FilmPart.run;
      await _progress.animateTo(stop).orCancel;
      _part = FilmPart.moment;
      await _moment.forward(from: 0).orCancel;
    }
    _part = FilmPart.run;
    await _progress.forward().orCancel;
    _part = FilmPart.outro;
    await _outro.forward(from: 0).orCancel;
  }

  void _replay() => _play().catchError(
    (Object _) {},
    test: (error) => error is TickerCanceled,
  );

  void _stopPlayback() {
    _intro.stop();
    _progress.stop();
    _moment.stop();
    _outro.stop();
  }

  static const _pinSource = 'replay-pins';

  static Map<String, dynamic> _pinFeatures(
    List<({double fraction, String icon, LatLng point, int layer})> pins,
  ) => {
    'type': 'FeatureCollection',
    'features': [
      for (final pin in pins)
        {
          'type': 'Feature',
          'properties': {'icon': pin.icon, 'layer': pin.layer},
          'geometry': {
            'type': 'Point',
            'coordinates': [pin.point.longitude, pin.point.latitude],
          },
        },
    ],
  };

  /// Dựng layer ghim rồi nạp hình từng cột mốc km và từng ảnh. Ảnh tải chậm
  /// thì ghim của nó có mặt muộn hơn, replay không chờ.
  Future<void> _addPins() async {
    final map = _map!;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    await map.addGeoJsonSource(_pinSource, _pinFeatures(const []));
    // Cột mốc km nằm layer riêng, đè nhau thì map tự ẩn bớt: lùi ra xa hay
    // chạy nhiều vòng quanh một chỗ thì chúng không dồn thành đống.
    await map.addSymbolLayer(
      _pinSource,
      'replay-km-pins',
      const ml.SymbolLayerProperties(
        iconImage: ['get', 'icon'],
        iconAnchor: 'bottom',
        iconOffset: [0, replayPinPad],
        iconAllowOverlap: false,
        iconIgnorePlacement: false,
      ),
      filter: [
        '==',
        ['get', 'layer'],
        0,
      ],
    );
    await map.addSymbolLayer(
      _pinSource,
      'replay-pins',
      const ml.SymbolLayerProperties(
        iconImage: ['get', 'icon'],
        iconAnchor: 'bottom',
        iconOffset: [0, replayPinPad],
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        // Ảnh đè lên người cổ vũ.
        symbolSortKey: ['get', 'layer'],
      ),
      filter: [
        '!=',
        ['get', 'layer'],
        0,
      ],
    );
    if (!mounted) return;
    _pinsShown = 0;

    Future<void> add(
      double fraction,
      String icon,
      Uint8List png,
      int layer,
    ) async {
      await map.addImage(icon, png, false, pixelRatio);
      if (!mounted) return;
      _pins.add((
        fraction: fraction,
        icon: icon,
        point: _path.at(fraction).point,
        layer: layer,
      ));
      _syncMap();
    }

    for (final km in replayKmMarks(_momentMeters)) {
      final png = await kmPinPng(km, pixelRatio, _colors);
      if (!mounted) return;
      await add(km * 1000 / _momentMeters, 'km-$km', png, 0);
    }
    // Một người bấm dồn nhiều lần quanh một chỗ thì cắm một ghim thôi.
    final cheered = <String>{};
    for (final (i, moment) in widget.moments.indexed) {
      final emoji = moment.emoji;
      if (emoji == null) continue;
      final spot = (moment.distanceMeters / 200).floor();
      if (!cheered.add('${moment.avatarUrl}|$emoji|$spot')) continue;
      ui.Image? avatar;
      if (moment.avatarUrl case final url?) {
        try {
          avatar = await loadReplayAvatar(url, pixelRatio);
        } catch (error, stack) {
          // Thiếu avatar thì ghim vẫn cắm với hình người; báo ra để điều tra.
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: error,
              stack: stack,
              library: 'route replay',
              context: ErrorDescription('nạp avatar người cổ vũ'),
            ),
          );
        }
      }
      final png = await cheerPinPng(avatar, emoji, pixelRatio, _colors);
      if (!mounted) return;
      await add(moment.fraction(_momentMeters), 'cheer-$i', png, 1);
    }
    for (final (i, moment) in widget.moments.indexed) {
      final path = moment.photoPath;
      if (path == null) continue;
      try {
        final photo = await loadReplayPhoto(path, pixelRatio);
        final png = await photoPinPng(photo, pixelRatio, _colors);
        if (!mounted) return;
        await add(moment.fraction(_momentMeters), 'photo-$i', png, 2);
      } catch (error, stack) {
        // Một ảnh hỏng không được làm mất cả replay; báo ra để điều tra.
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'route replay',
            context: ErrorDescription('nạp ảnh dọc đường $path'),
          ),
        );
      }
    }
  }

  /// Thanh trạng thái (giờ, pin) không thuộc video nên ẩn trong lúc quay.
  static Future<void> _showStatusBar(bool shown) =>
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: shown ? SystemUiOverlay.values : const [],
      );

  /// Giữ khung cuối của video chừng này.
  static const _clipHold = Duration(milliseconds: 500);

  /// Đếm thời gian từ lúc bắt đầu quay, để hiện video đã dựng tới đâu.
  final _clipWatch = Stopwatch();
  Duration _clipLength = Duration.zero;

  /// Một lượt [_play] dài bao lâu.
  Duration get _playLength {
    final run = _progress.duration!;
    if (_view != ReplayView.film) return run;
    final stops = filmStops(_momentFractions).length;
    return _intro.duration! +
        run +
        _moment.duration! * stops +
        _outro.duration!;
  }

  /// Quay lại cả lượt replay từ đầu rồi mở bảng share với file MP4. Video chỉ
  /// lấy vùng [replayClipRect]; lúc quay nhãn và bảng số dời vào trong vùng đó.
  Future<void> _shareClip() async {
    if (_recording) return;
    final format = shareFormatOf(context);
    final clip = replayClipRect(
      MediaQuery.sizeOf(context),
      aspect: format.aspect,
    );
    _stopPlayback();
    setState(() {
      _clipFormat = format;
      _recording = true;
      _clipCancelled = false;
    });
    final path = '${(await getTemporaryDirectory()).path}/replay-3d.mp4';
    try {
      await _showStatusBar(false);
      await _screenClip.invokeMethod<void>('start', {
        'path': path,
        'left': clip.left,
        'top': clip.top,
        'width': clip.width,
        'height': clip.height,
      });
      if (_clipCancelled) throw const TickerCanceled();
      _clipLength = _playLength + _clipHold;
      _clipWatch
        ..reset()
        ..start();
      await _play();
      // Giữ khung cuối một nhịp cho video không cụt.
      await Future<void>.delayed(_clipHold);
      if (_clipCancelled) throw const TickerCanceled();
      await _screenClip.invokeMethod<void>('stop');
    } on TickerCanceled {
      // Rời màn giữa chừng thì dispose đã huỷ lượt quay.
      if (!mounted) return;
      // Bấm huỷ: bỏ file đang quay, trả màn về như trước.
      await _screenClip.invokeMethod<void>('cancel');
      await _showStatusBar(true);
      if (!mounted) return;
      setState(() => _recording = false);
      return;
    } on PlatformException catch (error) {
      await _screenClip.invokeMethod<void>('cancel');
      await _showStatusBar(true);
      if (!mounted) return;
      setState(() => _recording = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không quay được video: ${error.message}')),
      );
      return;
    }
    await _showStatusBar(true);
    if (!mounted) return;
    setState(() => _recording = false);
    final file = File(path);
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    await shareCardFile(
      bytes: bytes,
      mimeType: 'video/mp4',
      fileName: '3i-replay.mp4',
      shareOriginContext: context,
      text: 'Buổi chạy của tôi trên 3i',
    );
    await file.delete();
  }

  /// Dừng lượt quay đang chạy; [_shareClip] dọn phần còn lại.
  void _cancelClip() {
    _clipCancelled = true;
    _stopPlayback();
  }

  @override
  void dispose() {
    if (_recording) {
      _screenClip.invokeMethod<void>('cancel');
      _showStatusBar(true);
    }
    _progress.dispose();
    _intro.dispose();
    _outro.dispose();
    _moment.dispose();
    _runnerShift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final screen = MediaQuery.sizeOf(context);
    // Lúc quay, tem và bảng số nằm trong vùng an toàn của khổ chia sẻ: Story
    // bị app đè tên tài khoản ở trên và ô trả lời ở dưới.
    final safe = replayClipSafeRect(
      replayClipRect(screen, aspect: _clipFormat.aspect),
      _clipFormat,
    );
    final inset = _recording
        ? EdgeInsets.fromLTRB(
            safe.left,
            safe.top,
            screen.width - safe.right,
            screen.height - safe.bottom,
          )
        : MediaQuery.paddingOf(context);
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: ml.MapLibreMap(
              styleString: replayMapStyle(
                dark: dark,
                daylight: _daylight,
                route: [
                  for (final p in _path.points) [p.longitude, p.latitude],
                ],
                line: _colors.line,
                outline: _colors.night,
              ),
              initialCameraPosition: _camera(0),
              onMapCreated: (controller) => _map = controller,
              onStyleLoadedCallback: _onStyleLoaded,
              compassEnabled: false,
              rotateGesturesEnabled: false,
              scrollGesturesEnabled: false,
              zoomGesturesEnabled: false,
              tiltGesturesEnabled: false,
              dragEnabled: false,
            ),
          ),
          if (_daylight case final daylight? when _view == ReplayView.film)
            Positioned.fromRect(
              rect: _skyRect(MediaQuery.sizeOf(context)),
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_intro, _outro]),
                  builder: (context, _) {
                    final sky = filmSky(
                      daylight,
                      _part,
                      _part == FilmPart.intro ? _intro.value : _outro.value,
                    );
                    if (sky == null) return const SizedBox.shrink();
                    return ReplaySky(
                      daylight: daylight,
                      sky: sky,
                      bearing: _camera(_progress.value).bearing,
                    );
                  },
                ),
              ),
            ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (_) => _zoomAtPinchStart = _zoom,
              onScaleUpdate: _onViewGesture,
            ),
          ),
          // Hình người chạy đi theo [_runnerShift]: chân cọc chạm đúng chỗ
          // người chạy trên map.
          Center(
            child: ValueListenableBuilder(
              valueListenable: _runnerShift,
              builder: (context, shift, child) =>
                  Transform.translate(offset: shift, child: child),
              child: FractionalTranslation(
                translation: const Offset(0, -0.5),
                child: _RunnerPin(avatarUrl: widget.avatarUrl),
              ),
            ),
          ),
          if (widget.moments.isNotEmpty)
            // Đáy hàng này nằm ngay trên hình người chạy.
            Center(
              child: ValueListenableBuilder(
                valueListenable: _runnerShift,
                builder: (context, shift, child) => Transform.translate(
                  offset: shift + const Offset(0, -_pinLift),
                  child: child,
                ),
                child: FractionalTranslation(
                  translation: const Offset(0, -0.5),
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _progress,
                      builder: (context, _) => _MomentRow(
                        shown: replayMomentsAt(
                          widget.moments,
                          _progress.value,
                          totalMeters: _momentMeters,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_view == ReplayView.film)
            Positioned(
              left: 0,
              right: 0,
              top: inset.top + 120,
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _outro,
                  builder: (context, child) {
                    final shown = _part == FilmPart.outro
                        ? filmStamp(_outro.value)
                        : 0.0;
                    if (shown == 0) return const SizedBox.shrink();
                    // Đóng tem: từ to rơi xuống đúng cỡ.
                    final scale =
                        1 + 0.6 * (1 - Curves.easeOutBack.transform(shown));
                    return Opacity(
                      opacity: shown,
                      child: Transform.scale(scale: scale, child: child),
                    );
                  },
                  child: Center(
                    child: _FinishStamp(
                      distanceMeters: widget.distanceMeters ?? _path.meters,
                      movingTimeSeconds: widget.movingTimeSeconds,
                      startedAt: widget.startedAt,
                    ),
                  ),
                ),
              ),
            ),
          Positioned(
            left: inset.left + (_recording ? 0 : 12),
            right: inset.right + (_recording ? 0 : 12),
            bottom: inset.bottom + (_recording ? 0 : 12),
            child: IgnorePointer(
              key: _hudKey,
              child: AnimatedBuilder(
                animation: _progress,
                builder: (context, _) => _ReplayHud(
                  distanceMeters: widget.distanceMeters ?? _path.meters,
                  movingTimeSeconds: widget.movingTimeSeconds,
                  series: widget.series,
                  progress: _progress.value,
                  marks: [
                    for (final moment in widget.moments)
                      (
                        moment.fraction(_momentMeters),
                        moment.photoPath != null,
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (_recording)
            Positioned(
              top: inset.top,
              left: inset.left,
              child: const ReplayStamp(),
            ),
          // Ngoài vùng quay thì làm tối và hiện video dựng tới đâu. Phần này
          // nằm ngoài vùng cắt nên không vào video.
          if (_recording)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _intro,
                  _progress,
                  _moment,
                  _outro,
                ]),
                builder: (context, _) => _ClipFrame(
                  clip: replayClipRect(screen, aspect: _clipFormat.aspect),
                  onCancel: _cancelClip,
                  done: _clipLength == Duration.zero
                      ? 0
                      : _clipWatch.elapsedMilliseconds /
                            _clipLength.inMilliseconds,
                ),
              ),
            ),
          if (!_recording) ...[
            Positioned(
              top: 12,
              left: 12,
              child: SafeArea(
                child: _RailButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Đóng',
                  icon: Icons.close_rounded,
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 6,
                  children: [
                    if (_canShareClip)
                      _RailButton(
                        onPressed: _shareClip,
                        tooltip: 'Quay video để chia sẻ',
                        icon: Icons.ios_share_rounded,
                        primary: true,
                      ),
                    _RailButton(
                      onPressed: _nextView,
                      tooltip: switch (_view) {
                        ReplayView.film => 'Tầm nhìn: kiểu phim',
                        ReplayView.fit => 'Tầm nhìn: vừa cả tuyến',
                        ReplayView.near => 'Tầm nhìn: gần 2 lần',
                        ReplayView.nearer => 'Tầm nhìn: gần 3 lần',
                        ReplayView.nearest => 'Tầm nhìn: gần 5 lần',
                        ReplayView.custom => 'Tầm nhìn: tự chỉnh',
                      },
                      icon: switch (_view) {
                        ReplayView.film => Icons.movie_rounded,
                        ReplayView.fit => Icons.fit_screen_rounded,
                        ReplayView.near => Icons.zoom_in_rounded,
                        ReplayView.nearer => Icons.center_focus_strong_rounded,
                        ReplayView.nearest => Icons.my_location_rounded,
                        ReplayView.custom => Icons.tune_rounded,
                      },
                    ),
                    _RailButton(
                      onPressed: _replay,
                      tooltip: 'Chạy lại',
                      icon: Icons.replay_rounded,
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

/// Làm tối phần màn hình ngoài [clip] và hiện thanh video đã dựng được [done]
/// (0 tới 1) ở dải tối rộng hơn.
class _ClipFrame extends StatelessWidget {
  const _ClipFrame({
    required this.clip,
    required this.done,
    required this.onCancel,
  });

  final Rect clip;
  final double done;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final shown = done.clamp(0.0, 0.99);
    final colors = ReplayColors.of(context.runNowPalette);
    // Thanh trạng thái tắt lúc quay nhưng tai thỏ và thanh home vẫn còn.
    final notch = MediaQuery.viewPaddingOf(context);
    final label = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Đang tạo video ${(shown * 100).round()}%',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: colors.paper),
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: shown,
            minHeight: 3,
            color: colors.line,
            backgroundColor: colors.paper.withValues(alpha: 0.25),
          ),
        ],
      ),
    );
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _OutsidePainter(clip)),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: clip.bottom,
          bottom: notch.bottom,
          child: IgnorePointer(child: Center(child: label)),
        ),
        // Nút huỷ ở góc trên bên trái, cạnh tai thỏ, trong dải tối trên
        // khung quay.
        Positioned(
          left: 12,
          top: math.max(4, (clip.top - 48) / 2),
          child: IconButton(
            onPressed: onCancel,
            tooltip: 'Huỷ quay',
            color: colors.paper,
            icon: const Icon(Icons.close_rounded),
          ),
        ),
      ],
    );
  }
}

class _OutsidePainter extends CustomPainter {
  _OutsidePainter(this.clip);

  final Rect clip;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRect(clip),
      ),
      Paint()..color = const Color(0xB3000000),
    );
  }

  @override
  bool shouldRepaint(_OutsidePainter old) => old.clip != clip;
}

/// Tem tên app trên video chia sẻ: khối màu nhấn của giao diện đang chọn,
/// đặt nghiêng trên một bóng cứng cho nổi khỏi nền map.
class ReplayStamp extends StatelessWidget {
  const ReplayStamp({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    return Transform.rotate(
      angle: -0.07,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.accent,
          boxShadow: [
            BoxShadow(color: palette.accentNight, offset: const Offset(5, 5)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            '3I RUN',
            style: palette.heading(
              TextStyle(
                color: palette.onAccent,
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Nút vuông phẳng nằm trên map. Nền than cho map vẫn là thứ nổi nhất; chỉ
/// nút chính ([primary]) mới đỏ.
class _RailButton extends StatelessWidget {
  const _RailButton({
    required this.onPressed,
    required this.tooltip,
    required this.icon,
    this.primary = false,
  });

  final VoidCallback onPressed;
  final String tooltip;
  final IconData icon;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = ReplayColors.of(context.runNowPalette);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: primary ? colors.line : colors.night.withValues(alpha: 0.88),
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 44,
            child: Icon(
              icon,
              size: 22,
              color: primary ? colors.onLine : colors.paper,
            ),
          ),
        ),
      ),
    );
  }
}

/// Ảnh người chạy có viền sáng, dưới là cọc đỏ cắm xuống tuyến.
class _RunnerPin extends StatelessWidget {
  const _RunnerPin({required this.avatarUrl});

  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final url = avatarUrl;
    final colors = ReplayColors.of(context.runNowPalette);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.paper,
            shape: context.runNowPalette.round,
            boxShadow: kElevationToShadow[4],
          ),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: RunNowAvatar(
              radius: _avatarSize / 2,
              backgroundColor: colors.line,
              backgroundImage: url == null
                  ? null
                  : cachedAvatarImage(context, url, _avatarSize),
              child: url == null
                  ? Icon(Icons.directions_run_rounded, color: colors.onLine)
                  : null,
            ),
          ),
        ),
        // Đuôi nhọn chỉ xuống chấm đánh dấu chỗ đang đứng trên tuyến.
        CustomPaint(
          size: const Size(14, 9),
          painter: _PinTailPainter(colors.paper),
        ),
        const SizedBox(height: 3),
        // Tâm chấm nằm đúng tâm map, nơi camera đang nhìn.
        Transform.translate(
          offset: const Offset(0, 6),
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: colors.line,
              shape: BoxShape.circle,
              border: Border.all(color: colors.paper, width: 2.5),
              boxShadow: kElevationToShadow[2],
            ),
          ),
        ),
      ],
    );
  }
}

/// Bảng ở đáy màn: số km tới lúc này thật to canh trái, giờ chạy và pace
/// trung bình bên phải, dưới là các biểu đồ dọc buổi chạy, mỗi loại số liệu
/// một hàng, phần đã qua tô đỏ.
class _ReplayHud extends StatelessWidget {
  const _ReplayHud({
    required this.distanceMeters,
    required this.movingTimeSeconds,
    required this.series,
    required this.progress,
    this.marks = const [],
  });

  final double distanceMeters;
  final int? movingTimeSeconds;
  final List<ReplaySeries> series;
  final double progress;

  /// Vị trí (0 tới 1) của ảnh và cổ vũ dọc đường; true là ảnh.
  final List<(double, bool)> marks;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final seconds = movingTimeSeconds;
    final colors = ReplayColors.of(context.runNowPalette);
    const figures = [FontFeature.tabularFigures()];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.night.withValues(alpha: 0.9),
        boxShadow: kElevationToShadow[4],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  (distanceMeters * progress / 1000).toStringAsFixed(2),
                  style: text.displaySmall?.copyWith(
                    color: colors.paper,
                    fontFeatures: figures,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    'km',
                    style: text.titleMedium?.copyWith(color: colors.line),
                  ),
                ),
                const Spacer(),
                if (seconds != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatDuration((seconds * progress).round()),
                        style: text.titleLarge?.copyWith(
                          color: colors.paper,
                          fontFeatures: figures,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatPace(
                          distanceMeters <= 0
                              ? null
                              : seconds / (distanceMeters / 1000),
                        ),
                        style: text.labelMedium?.copyWith(
                          color: colors.muted,
                          fontFeatures: figures,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            if (marks.isNotEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 6,
                child: CustomPaint(painter: _MarkPainter(marks, colors)),
              ),
            ],
            for (final shown in series) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    shown.label,
                    style: text.labelSmall?.copyWith(
                      color: colors.muted,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    shown.format(
                      shown.values[(progress * (shown.values.length - 1))
                          .round()],
                    ),
                    style: text.labelLarge?.copyWith(
                      color: colors.paper,
                      fontFeatures: figures,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              SizedBox(
                height: series.length > 1 ? 18 : 30,
                child: CustomPaint(
                  painter: _WavePainter(
                    values: shown.values,
                    progress: progress,
                    colors: colors,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Vạch đánh dấu ảnh (trắng) và cổ vũ (đỏ) dọc buổi chạy, cùng thang ngang
/// với các biểu đồ bên dưới.
class _MarkPainter extends CustomPainter {
  _MarkPainter(this.marks, this.colors);

  final List<(double, bool)> marks;
  final ReplayColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (at, isPhoto) in marks) {
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(at * size.width, size.height / 2),
          width: isPhoto ? 6 : 3,
          height: size.height,
        ),
        Paint()..color = isPhoto ? colors.paper : colors.line,
      );
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) =>
      old.marks != marks || old.colors != colors;
}

/// Emoji cổ vũ bung ra khi người chạy tới đúng chỗ. Ảnh thì cắm thẳng trên
/// tuyến, xem `_addPins`.
class _MomentRow extends StatelessWidget {
  const _MomentRow({required this.shown});

  final List<ReplayMoment> shown;

  @override
  Widget build(BuildContext context) {
    // Nhiều người bấm dồn một chỗ thì chỉ giữ mấy lần mới nhất.
    final cheers = [
      for (final moment in shown)
        if (moment.emoji != null) moment,
    ];
    final recent = cheers.length > 6
        ? cheers.sublist(cheers.length - 6)
        : cheers;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [for (final cheer in recent) _CheerChip(cheer)],
        ),
      ],
    );
  }
}

/// Ảnh người cổ vũ kèm emoji họ bấm.
class _CheerChip extends StatelessWidget {
  const _CheerChip(this.cheer);

  final ReplayMoment cheer;

  @override
  Widget build(BuildContext context) {
    final url = cheer.avatarUrl;
    final colors = ReplayColors.of(context.runNowPalette);
    return SizedBox(
      width: 62,
      height: 58,
      child: Stack(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.line,
              shape: context.runNowPalette.round,
              boxShadow: kElevationToShadow[4],
            ),
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: RunNowAvatar(
                radius: 24,
                backgroundColor: colors.line,
                backgroundImage: url == null
                    ? null
                    : cachedAvatarImage(context, url, 48),
                child: url == null
                    ? Icon(Icons.person_rounded, size: 20, color: colors.onLine)
                    : null,
              ),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Text(cheer.emoji!, style: const TextStyle(fontSize: 26)),
          ),
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.values,
    required this.progress,
    required this.colors,
  });

  final List<double> values;
  final double progress;
  final ReplayColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final low = values.reduce(math.min), high = values.reduce(math.max);
    final range = high - low;
    // Chừa mép trên dưới cho nét và chấm không bị cắt.
    double y(double value) =>
        size.height * (0.9 - 0.8 * (range <= 0 ? 0.5 : (value - low) / range));
    double x(int i) => size.width * i / (values.length - 1);

    // Nối qua trung điểm bằng đường cong bậc hai cho ra dáng sóng.
    final wave = Path()..moveTo(0, y(values.first));
    for (var i = 1; i < values.length; i++) {
      final midX = (x(i - 1) + x(i)) / 2;
      final midY = (y(values[i - 1]) + y(values[i])) / 2;
      wave.quadraticBezierTo(x(i - 1), y(values[i - 1]), midX, midY);
    }
    wave.lineTo(size.width, y(values.last));
    final area = Path.from(wave)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    Paint line(Color color, double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(wave, line(colors.muted, 1.5));
    final doneX = size.width * progress;
    canvas
      ..save()
      ..clipRect(Rect.fromLTRB(0, 0, doneX, size.height))
      ..drawPath(area, Paint()..color = colors.line.withValues(alpha: 0.3))
      ..drawPath(wave, line(colors.line, 2.5))
      ..restore();

    final at = progress * (values.length - 1);
    final i = at.floor().clamp(0, values.length - 2);
    final here = Offset(
      doneX,
      y(values[i] + (values[i + 1] - values[i]) * (at - i)),
    );
    canvas
      ..drawCircle(here, 5, Paint()..color = colors.paper)
      ..drawCircle(here, 3, Paint()..color = colors.line);
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.progress != progress || old.values != values || old.colors != colors;
}

class _PinTailPainter extends CustomPainter {
  const _PinTailPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) => canvas.drawPath(
    Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close(),
    Paint()..color = color,
  );

  @override
  bool shouldRepaint(_PinTailPainter old) => old.color != color;
}

/// Tem tổng kết hiện ở cuối đoạn kết của tầm nhìn kiểu phim.
class _FinishStamp extends StatelessWidget {
  const _FinishStamp({
    required this.distanceMeters,
    required this.movingTimeSeconds,
    required this.startedAt,
  });

  final double distanceMeters;
  final int? movingTimeSeconds;
  final DateTime? startedAt;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = ReplayColors.of(context.runNowPalette);
    const figures = [FontFeature.tabularFigures()];
    final seconds = movingTimeSeconds;
    final at = startedAt?.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return Transform.rotate(
      angle: -0.08,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.paper,
          border: Border.all(color: colors.line, width: 3),
          boxShadow: kElevationToShadow[6],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(distanceMeters / 1000).toStringAsFixed(2)} KM',
                style: text.displaySmall?.copyWith(
                  color: colors.line,
                  fontFeatures: figures,
                  height: 1,
                ),
              ),
              if (seconds != null) ...[
                const SizedBox(height: 6),
                Text(
                  '${formatDuration(seconds)} · ${formatPace(distanceMeters <= 0 ? null : seconds / (distanceMeters / 1000))}',
                  style: text.titleSmall?.copyWith(
                    color: colors.night,
                    fontFeatures: figures,
                  ),
                ),
              ],
              if (at != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${two(at.day)}/${two(at.month)} · ${two(at.hour)}:${two(at.minute)} · 3i',
                  style: text.labelSmall?.copyWith(color: colors.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
