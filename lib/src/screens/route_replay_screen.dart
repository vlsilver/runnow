import 'dart:async';
import 'dart:convert';
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
import 'package:myrun/src/widgets/photo_viewer.dart';
import 'package:myrun/src/widgets/run_now_avatar.dart';
import 'package:myrun/src/widgets/storage_image.dart';

const _zoomRange = (10.0, 18.0);
// MapLibre không nghiêng quá 60°.
const _maxTilt = 60.0;

/// Dải trời của tầm nhìn kiểu phim cao chừng này phần màn hình.
const _skyBand = 0.34;
const _avatarSize = 44.0;

/// Hình người chạy cao chừng này tính từ chỗ nó đứng lên.
const _runnerLift = 64.0;
const _distance = Distance(roundResult: false);

/// Kênh quay màn hình: ReplayKit trên iOS (ScreenClipRecorder trong
/// AppDelegate), MediaProjection trên Android (ScreenClipRecorder.kt).
const _screenClip = MethodChannel('runnow/screen_clip');

/// Quay màn hình app có trên iOS và Android 10 trở lên; Android cũ hơn thì
/// lệnh start báo lỗi.
bool get _canShareClip =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);

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

/// Các biểu đồ dựng được từ số liệu buổi chạy đang có, theo thứ tự lớp từ
/// trên xuống: pace, nhịp tim, guồng chân, độ cao. Loại nào thiếu số liệu thì
/// không có mặt.
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
  final cadences = streamProfile(streams['cadence'], distances);

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
    if (cadences != null)
      ReplaySeries(
        label: 'GUỒNG',
        values: cadences,
        format: (rpm) => '${rpm.round()} rpm',
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
       name = null,
       avatarUrl = null;

  const ReplayMoment.cheer({
    required this.distanceMeters,
    required String this.emoji,
    this.name,
    this.avatarUrl,
  }) : photoPath = null;

  /// Quãng đường người chạy đã đi lúc đó.
  final double distanceMeters;
  final String? photoPath;
  final String? emoji;

  /// Tên và ảnh của người cổ vũ.
  final String? name;
  final String? avatarUrl;

  @override
  bool operator ==(Object other) =>
      other is ReplayMoment &&
      other.distanceMeters == distanceMeters &&
      other.photoPath == photoPath &&
      other.emoji == emoji &&
      other.name == name &&
      other.avatarUrl == avatarUrl;

  @override
  int get hashCode =>
      Object.hash(distanceMeters, photoPath, emoji, name, avatarUrl);

  /// Vị trí trên buổi chạy dài [totalMeters], từ 0 tới 1. Cổ vũ lúc live có
  /// thể ghi quãng đường nhỉnh hơn số chốt của buổi chạy, nên kẹp về đích.
  double fraction(double totalMeters) =>
      totalMeters <= 0 ? 0 : (distanceMeters / totalMeters).clamp(0.0, 1.0);
}

/// Bỏ lần bấm lặp: một người bấm dồn cùng emoji quanh một chỗ (cùng quãng
/// 200 m) thì chỉ giữ lần đầu. Ảnh giữ hết.
List<ReplayMoment> replayDistinctMoments(List<ReplayMoment> moments) {
  final seen = <String>{};
  return [
    for (final moment in moments)
      if (moment.emoji == null ||
          seen.add(
            '${moment.avatarUrl}|${moment.emoji}|'
            '${(moment.distanceMeters / 200).floor()}',
          ))
        moment,
  ];
}

/// Chia buổi chạy dài [totalMeters] thành [limit] đoạn bằng nhau, mỗi đoạn giữ
/// khoảnh khắc đầu tiên trong [moments] rơi vào đó. Nhiều cái dồn một chỗ thì
/// chỗ đó vẫn chỉ có một, chỗ thưa không bị mất phần.
List<ReplayMoment> replayOnePerStretch(
  List<ReplayMoment> moments, {
  required double totalMeters,
  required int limit,
}) {
  final taken = <int>{};
  return [
    for (final moment in moments)
      if (taken.add(
        math.min((moment.fraction(totalMeters) * limit).floor(), limit - 1),
      ))
        moment,
  ];
}

/// Một đoạn tuyến được cổ vũ nhiều: [at] là giữa đoạn (0 tới 1), [emoji] là
/// emoji được bấm nhiều nhất ở đó, [count] là số lần cổ vũ của cả đoạn.
typedef ReplayCheerPeak = ({double at, String emoji, int count});

/// [limit] đoạn được cổ vũ nhiều nhất của buổi chạy dài [totalMeters], theo
/// thứ tự dọc đường. Tuyến chia [bins] đoạn bằng nhau; hai đỉnh phải cách nhau
/// ít nhất một đoạn để nhãn không đè nhau. Bằng số lần thì lấy đoạn tới trước.
List<ReplayCheerPeak> replayCheerPeaks(
  List<ReplayMoment> moments, {
  required double totalMeters,
  int bins = 10,
  int limit = 3,
}) {
  final emojis = List.generate(bins, (_) => <String, int>{});
  for (final moment in moments) {
    final emoji = moment.emoji;
    if (emoji == null) continue;
    final bin = math.min(
      (moment.fraction(totalMeters) * bins).floor(),
      bins - 1,
    );
    emojis[bin][emoji] = (emojis[bin][emoji] ?? 0) + 1;
  }
  int count(int bin) => emojis[bin].values.fold(0, (a, b) => a + b);
  final byCount = [
    for (var bin = 0; bin < bins; bin++)
      if (emojis[bin].isNotEmpty) bin,
  ]..sort((a, b) => count(b) != count(a) ? count(b) - count(a) : a - b);
  final taken = <int>[];
  for (final bin in byCount) {
    if (taken.length == limit) break;
    if (taken.every((other) => (other - bin).abs() > 1)) taken.add(bin);
  }
  return [
    for (final bin in taken..sort())
      (
        at: (bin + 0.5) / bins,
        // Map giữ thứ tự chèn, nên bằng nhau thì lấy emoji xuất hiện trước.
        emoji: emojis[bin].entries
            .reduce((a, b) => b.value > a.value ? b : a)
            .key,
        count: count(bin),
      ),
  ];
}

/// Đi dọc các khoảnh khắc theo người chạy, để khung tin biết cái nào vừa tới.
/// Sắp xếp một lần lúc tạo, mỗi khung hình chỉ dò tiếp từ chỗ đang đứng.
class ReplayFeedCursor {
  ReplayFeedCursor(List<ReplayMoment> moments, {required this.totalMeters})
    : _sorted = replayDistinctMoments(moments)
        ..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

  final double totalMeters;
  final List<ReplayMoment> _sorted;
  int _next = 0;
  double _reach = 0;

  /// Người chạy tới [reach] (0 tới 1): trả các khoảnh khắc đi qua kể từ lần
  /// gọi trước, theo thứ tự dọc đường. [reach] lùi lại (phát lại) thì bắt đầu
  /// lại từ đầu tuyến.
  List<ReplayMoment> advance(double reach) {
    if (reach < _reach) _next = 0;
    _reach = reach;
    final from = _next;
    while (_next < _sorted.length &&
        _sorted[_next].fraction(totalMeters) <= reach) {
      _next++;
    }
    return _sorted.sublist(from, _next);
  }
}

enum _PinKind { km, cheer, photo }

/// Một ghim trên map: hình thường [icon], hình nở to [bloom] (cột mốc km
/// không có). [point] là chỗ trên tuyến, tuyến ở đó đi theo hướng [bearing];
/// [moment] là khoảnh khắc ghim này chỉ.
typedef _Pin = ({
  double fraction,
  _PinKind kind,
  String icon,
  String? bloom,
  LatLng point,
  double bearing,
  ReplayMoment? moment,
});

/// Nhiều cổ vũ tới mấy cũng chỉ cắm chừng này hạt, mỗi đoạn tuyến một hạt:
/// mỗi hạt là một hình phải vẽ và một avatar phải tải.
const _maxCheerPins = 40;

/// Tâm ghim cách tim tuyến chừng này điểm ảnh, đủ để ghim không đè lên nét.
const _pinBeside = 22.0;

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

  /// Vị trí trên tuyến (0 tới 1) của các ảnh. Camera chỉ dừng ở ảnh; cổ vũ
  /// có thể rất nhiều nên chỉ trôi qua khung tin, không giữ camera lại.
  late final List<double> _momentFractions = [
    for (final moment in widget.moments)
      if (moment.photoPath != null) moment.fraction(_momentMeters),
  ];

  /// Các lần cổ vũ đã bỏ lần bấm lặp, theo thứ tự dọc đường.
  late final List<ReplayMoment> _cheers = [
    for (final moment in replayDistinctMoments(widget.moments))
      if (moment.emoji != null) moment,
  ]..sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

  late final _feed = ReplayFeedCursor(
    widget.moments,
    totalMeters: _momentMeters,
  );

  /// Những đoạn được cổ vũ nhiều nhất, hiện trên biểu đồ ở bảng số.
  late final List<ReplayCheerPeak> _cheerPeaks = replayCheerPeaks(
    _cheers,
    totalMeters: _momentMeters,
  );

  /// Những chỗ camera kiểu phim dừng lại, và các khoảnh khắc hiện ở mỗi chỗ.
  late final List<double> _stops = filmStops(_momentFractions);

  /// Khoảnh khắc xa nhất gộp vào mỗi chỗ dừng.
  late final List<double> _stopReach = [
    for (final (i, stop) in _stops.indexed)
      _momentFractions
          .where((at) => filmStopIndex(at, _stops) == i)
          .fold(stop, math.max),
  ];

  /// Camera dừng ở chỗ nào thì mọi khoảnh khắc gộp vào chỗ đó coi như đã qua,
  /// dù người chạy chưa tới hẳn. Về 0 khi phát lại.
  double _reachFloor = 0;

  /// Người chạy coi như đã đi qua tới đâu (0 tới 1): ghim và khung tin hiện
  /// tới đây.
  double get _reach => math.max(_progress.value, _reachFloor);

  /// Chỗ dừng đang diễn ra khi [_part] là [FilmPart.moment].
  int _stopNow = 0;

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

  /// Cột mốc km, cổ vũ và ảnh cắm trên tuyến, đã có hình trên map. Người
  /// chạy đi tới cái nào thì cái đó hiện ra và ở lại.
  final List<_Pin> _pins = [];

  /// Số ghim đang hiện trên map; null là layer ghim chưa dựng xong.
  int? _pinsShown;

  /// Mức zoom (làm tròn tới 1/4) đã dùng để đặt ghim cạnh tuyến; zoom đổi
  /// thì phải đặt lại, vì khoảng lệch tính theo điểm ảnh.
  int _pinZoomShown = 0;

  /// Các ghim đang nở to trên map, kèm layer đang vẽ nó.
  Map<int, String> _bloomShown = const {};

  /// Ghim người xem bấm cho nở to.
  int? _picked;

  /// Có thay đổi tới lúc [_sending] nên chưa sang được map.
  bool _stale = false;

  /// Xong khi map tải hết tile và đứng yên lần kế tiếp.
  Completer<void>? _idle;

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
      final reach = _reach;
      final reached = [
        for (final (i, pin) in _pins.indexed)
          if (pin.fraction <= reach) (i, pin),
      ];
      final blooming = _blooming();
      final camera = _camera(progress);
      final pinZoom = (camera.zoom * 4).round();
      await Future.wait([
        if (_pinsShown != null &&
            (_pinsShown != reached.length ||
                _pinZoomShown != pinZoom ||
                !mapEquals(blooming, _bloomShown)))
          map.setGeoJsonSource(
            _pinSource,
            _pinFeatures(reached, blooming, zoom: pinZoom / 4),
          ),
        map.moveCamera(ml.CameraUpdate.newCameraPosition(camera)),
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
      if (_pinsShown != null) {
        _pinsShown = reached.length;
        _pinZoomShown = pinZoom;
        _bloomShown = blooming;
      }
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
    _toStart();
    if (_view != ReplayView.film) {
      return _progress.forward(from: 0).orCancel;
    }
    await _intro.forward(from: 0).orCancel;
    for (final (i, stop) in _stops.indexed) {
      _part = FilmPart.run;
      await _progress.animateTo(stop).orCancel;
      _stopNow = i;
      _reachFloor = _stopReach[i];
      _part = FilmPart.moment;
      await _moment.forward(from: 0).orCancel;
    }
    _part = FilmPart.run;
    await _progress.forward().orCancel;
    _part = FilmPart.outro;
    await _outro.forward(from: 0).orCancel;
  }

  /// Dừng lượt đang phát và đặt cảnh về khung đầu của [_play].
  void _toStart() {
    _stopPlayback();
    _reachFloor = 0;
    _picked = null;
    _part = _view == ReplayView.film ? FilmPart.intro : FilmPart.run;
    _progress.value = 0;
    // Báo cho tem tổng kết và trời của đoạn kết lượt trước tắt đi.
    _outro.value = 0;
    _intro.value = 0;
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
  static const _kmLayer = 'replay-km-pins';
  static const _dotLayer = 'replay-dots';
  static const _bloomLayer = 'replay-blooms';
  static const _liftLayer = 'replay-lifted-blooms';

  /// [pins] là các ghim đang hiện kèm chỉ số trong [_pins]; chỉ số làm id của
  /// feature để biết người xem bấm vào ghim nào. Ghim trong [blooming] thì
  /// dùng hình nở to, vẽ ở layer ghi kèm. Ghim nằm cạnh tuyến, lệch theo
  /// [zoom]; riêng ghim nở trên đầu người chạy thì ở đúng chỗ trên tuyến.
  static Map<String, dynamic> _pinFeatures(
    List<(int, _Pin)> pins,
    Map<int, String> blooming, {
    required double zoom,
  }) => {
    'type': 'FeatureCollection',
    'features': [
      for (final (i, pin) in pins)
        {
          'type': 'Feature',
          'id': i,
          'properties': {
            'icon': blooming.containsKey(i) ? pin.bloom : pin.icon,
            'kind': blooming[i] ?? pin.kind.name,
            // Hai hạt chạm nhau thì giữ ảnh, ẩn cổ vũ.
            'rank': pin.kind == _PinKind.photo ? 0 : 1,
          },
          'geometry': {
            'type': 'Point',
            'coordinates': switch (blooming[i] == _liftLayer
                ? pin.point
                : replayPinBeside(
                    pin.point,
                    pin.bearing,
                    pixels: _pinBeside,
                    zoom: zoom,
                  )) {
              final at => [at.longitude, at.latitude],
            },
          },
        },
    ],
  };

  /// Ghim đang nở và layer vẽ nó: ghim người xem vừa bấm nở tại chỗ; một
  /// ghim ở chỗ camera đang dừng (ảnh trước, cổ vũ sau) nở trên đầu người
  /// chạy, vì người chạy đang đứng đúng chỗ đó.
  Map<int, String> _blooming() {
    final blooming = {?_picked: _bloomLayer};
    if (_view != ReplayView.film || _part != FilmPart.moment) return blooming;
    (int, _Pin)? best;
    for (final (i, pin) in _pins.indexed) {
      if (pin.bloom == null ||
          filmStopIndex(pin.fraction, _stops) != _stopNow) {
        continue;
      }
      if (best == null || pin.kind.index > best.$2.kind.index) best = (i, pin);
    }
    return {...blooming, ?best?.$1: _liftLayer};
  }

  /// Bấm vào hạt ảnh thì mở ảnh to. Bấm vào hạt cổ vũ thì hạt nở to, bấm lần
  /// nữa hoặc bấm ra ngoài thì thu lại.
  Future<void> _onTap(TapUpDetails details) async {
    final map = _map;
    if (map == null || _pinsShown == null) return;
    // Hạt nhỏ, nên tìm trong một ô quanh chỗ bấm cho dễ trúng.
    final hits = await map.queryRenderedFeaturesInRect(
      Rect.fromCenter(center: details.localPosition, width: 36, height: 36),
      [_liftLayer, _bloomLayer, _dotLayer],
      null,
    );
    if (!mounted) return;
    final picked = [for (final hit in hits) ?_featureId(hit)].firstOrNull;
    final moment = picked == null ? null : _pins[picked].moment;
    if (moment?.photoPath case final path?) {
      await showStoragePhotoViewer(
        context,
        path,
        caption: formatDistance(moment!.distanceMeters),
      );
      return;
    }
    _picked = picked == _picked ? null : picked;
    _syncMap();
  }

  /// Plugin trả feature dạng map hoặc chuỗi JSON tuỳ nền tảng.
  static int? _featureId(Object? hit) {
    final feature = hit is String ? jsonDecode(hit) : hit;
    return feature is Map ? int.tryParse('${feature['id']}') : null;
  }

  /// Dựng layer ghim rồi nạp hình từng cột mốc km, từng cổ vũ và từng ảnh. Ảnh
  /// tải chậm thì ghim của nó có mặt muộn hơn, replay không chờ.
  Future<void> _addPins() async {
    final map = _map!;
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    await map.addGeoJsonSource(
      _pinSource,
      _pinFeatures(const [], const {}, zoom: 0),
    );
    // Ghim nào đè ghim khác thì map tự ẩn bớt, lùi ra xa hay chạy nhiều vòng
    // quanh một chỗ thì chúng không dồn thành đống. Layer trên được giữ
    // trước: hạt nở to, rồi hạt ảnh và cổ vũ, cuối cùng cột mốc km.
    await map.addSymbolLayer(
      _pinSource,
      _kmLayer,
      const ml.SymbolLayerProperties(
        iconImage: ['get', 'icon'],
        iconAllowOverlap: false,
        iconIgnorePlacement: false,
      ),
      filter: [
        '==',
        ['get', 'kind'],
        'km',
      ],
      enableInteraction: false,
    );
    await map.addSymbolLayer(
      _pinSource,
      _dotLayer,
      const ml.SymbolLayerProperties(
        iconImage: ['get', 'icon'],
        iconAllowOverlap: false,
        iconIgnorePlacement: false,
        symbolSortKey: ['get', 'rank'],
      ),
      filter: [
        'any',
        [
          '==',
          ['get', 'kind'],
          'photo',
        ],
        [
          '==',
          ['get', 'kind'],
          'cheer',
        ],
      ],
      enableInteraction: false,
    );
    await map.addSymbolLayer(
      _pinSource,
      _bloomLayer,
      const ml.SymbolLayerProperties(
        iconImage: ['get', 'icon'],
        iconAnchor: 'bottom',
        iconOffset: [0, replayPinPad],
        // Luôn hiện, và chiếm chỗ để hạt bên dưới tránh ra.
        iconAllowOverlap: true,
        iconIgnorePlacement: false,
      ),
      filter: [
        '==',
        ['get', 'kind'],
        _bloomLayer,
      ],
      enableInteraction: false,
    );
    await map.addSymbolLayer(
      _pinSource,
      _liftLayer,
      const ml.SymbolLayerProperties(
        iconImage: ['get', 'icon'],
        iconAnchor: 'bottom',
        iconOffset: [0, replayPinPad - _runnerLift],
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
      filter: [
        '==',
        ['get', 'kind'],
        _liftLayer,
      ],
      enableInteraction: false,
    );
    if (!mounted) return;
    _pinsShown = 0;

    Future<void> add(
      double fraction,
      _PinKind kind,
      String icon,
      Uint8List png, {
      Uint8List? bloom,
      ReplayMoment? moment,
    }) async {
      await map.addImage(icon, png, false, pixelRatio);
      if (bloom != null) {
        await map.addImage('$icon-bloom', bloom, false, pixelRatio);
      }
      if (!mounted) return;
      final at = _path.at(fraction);
      _pins.add((
        fraction: fraction,
        kind: kind,
        icon: icon,
        bloom: bloom == null ? null : '$icon-bloom',
        point: at.point,
        bearing: at.bearing,
        moment: moment,
      ));
      _syncMap();
    }

    for (final km in replayKmMarks(_momentMeters)) {
      final png = await kmPinPng(km, pixelRatio, _colors);
      if (!mounted) return;
      await add(km * 1000 / _momentMeters, _PinKind.km, 'km-$km', png);
    }
    for (final (i, moment) in replayOnePerStretch(
      _cheers,
      totalMeters: _momentMeters,
      limit: _maxCheerPins,
    ).indexed) {
      final emoji = moment.emoji!;
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
      final dot = await cheerDotPng(emoji, pixelRatio);
      final bloom = await cheerBloomPng(avatar, emoji, pixelRatio, _colors);
      if (!mounted) return;
      await add(
        moment.fraction(_momentMeters),
        _PinKind.cheer,
        'cheer-$i',
        dot,
        bloom: bloom,
        moment: moment,
      );
    }
    for (final (i, moment) in widget.moments.indexed) {
      final path = moment.photoPath;
      if (path == null) continue;
      try {
        final photo = await loadReplayPhoto(path, pixelRatio);
        final dot = await photoDotPng(photo, pixelRatio, _colors);
        final bloom = await photoBloomPng(photo, pixelRatio, _colors);
        if (!mounted) return;
        await add(
          moment.fraction(_momentMeters),
          _PinKind.photo,
          'photo-$i',
          dot,
          bloom: bloom,
          moment: moment,
        );
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

  /// Thanh trạng thái (giờ, pin) không thuộc video nên ẩn trong lúc quay nếu
  /// nó nằm trong khung quay.
  static Future<void> _showStatusBar(bool shown) =>
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: shown ? SystemUiOverlay.values : const [],
      );

  /// Chờ map tải tile của khung đầu tối đa chừng này rồi quay luôn.
  static const _clipWarmup = Duration(seconds: 3);

  /// Dựng sẵn khung đầu trước khi quay. Quay ngay thì video mở bằng cảnh
  /// đang dừng, rồi giật sang khung đầu với nền trống chờ tile.
  Future<void> _showFirstFrame() async {
    // Tâm camera lúc quay tính theo bảng số đã dời vào khung quay.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    setState(_toStart);
    await _syncMap();
    final idle = _idle = Completer<void>();
    await idle.future.timeout(_clipWarmup, onTimeout: () => _idle = null);
  }

  /// Giữ khung cuối của video chừng này.
  static const _clipHold = Duration(milliseconds: 500);

  /// Đếm thời gian từ lúc bắt đầu quay, để hiện video đã dựng tới đâu.
  final _clipWatch = Stopwatch();
  Duration _clipLength = Duration.zero;

  /// Một lượt [_play] dài bao lâu.
  Duration get _playLength {
    final run = _progress.duration!;
    if (_view != ReplayView.film) return run;
    final stops = _stops.length;
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
    // Chỉ ẩn thanh trạng thái khi nó lấn vào khung quay. Ẩn nó là vào chế độ
    // toàn màn hình, và Android hiện bảng "Viewing full screen" đè lên video.
    final hideStatusBar = clip.top < MediaQuery.viewPaddingOf(context).top;
    final path = '${(await getTemporaryDirectory()).path}/replay-3d.mp4';
    try {
      if (hideStatusBar) await _showStatusBar(false);
      await _showFirstFrame();
      if (_clipCancelled || !mounted) throw const TickerCanceled();
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
              onMapIdle: () {
                _idle?.complete();
                _idle = null;
              },
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
              onTapUp: _onTap,
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.moments.isNotEmpty)
                  IgnorePointer(
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_progress, _moment]),
                      builder: (context, _) => _MomentFeed(
                        cursor: _feed,
                        reach: _reach,
                        movingTimeSeconds: widget.movingTimeSeconds,
                      ),
                    ),
                  ),
                IgnorePointer(
                  key: _hudKey,
                  child: AnimatedBuilder(
                    animation: _progress,
                    builder: (context, _) => _ReplayHud(
                      distanceMeters: widget.distanceMeters ?? _path.meters,
                      movingTimeSeconds: widget.movingTimeSeconds,
                      series: widget.series,
                      progress: _progress.value,
                      peaks: _cheerPeaks,
                      photos: _momentFractions,
                    ),
                  ),
                ),
              ],
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
      Paint()..color = Colors.black.withValues(alpha: 0.7),
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

/// Bảng ở đáy màn: số km tới lúc này thật to canh trái, giờ chạy bên phải,
/// dưới là các loại số liệu vẽ chồng lớp trong một vùng, rồi hàng số của
/// từng loại tại chỗ người chạy đang đứng.
class _ReplayHud extends StatelessWidget {
  const _ReplayHud({
    required this.distanceMeters,
    required this.movingTimeSeconds,
    required this.series,
    required this.progress,
    this.peaks = const [],
    this.photos = const [],
  });

  final double distanceMeters;
  final int? movingTimeSeconds;
  final List<ReplaySeries> series;
  final double progress;

  /// Những đoạn được cổ vũ nhiều nhất, theo thứ tự dọc đường.
  final List<ReplayCheerPeak> peaks;

  /// Vị trí (0 tới 1) của các ảnh dọc đường.
  final List<double> photos;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final seconds = movingTimeSeconds;
    final colors = ReplayColors.of(context.runNowPalette);
    const figures = [FontFeature.tabularFigures()];
    // Số liệu nhiều hơn số màu lớp thì bỏ bớt phần sau.
    final shown = series.take(colors.layers.length).toList();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.night.withValues(alpha: 0.9),
        boxShadow: kElevationToShadow[4],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  (distanceMeters * progress / 1000).toStringAsFixed(2),
                  style: text.headlineMedium?.copyWith(
                    color: colors.paper,
                    fontFeatures: figures,
                    height: 1,
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    'km',
                    style: text.titleSmall?.copyWith(color: colors.line),
                  ),
                ),
                const Spacer(),
                if (seconds != null)
                  Text(
                    formatDuration((seconds * progress).round()),
                    style: text.titleMedium?.copyWith(
                      color: colors.paper,
                      fontFeatures: figures,
                      height: 1,
                    ),
                  ),
              ],
            ),
            if (shown.isNotEmpty) ...[
              const SizedBox(height: 6),
              SizedBox(
                height: _LayersPainter.heightFor(
                  shown.length,
                  peaks: peaks.isNotEmpty,
                ),
                child: CustomPaint(
                  painter: _LayersPainter(
                    layers: [for (final one in shown) one.values],
                    progress: progress,
                    colors: colors,
                    peaks: peaks,
                    photos: photos,
                    peakStyle: text.labelSmall?.copyWith(
                      color: colors.paper,
                      fontFeatures: figures,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  for (final one in shown)
                    Expanded(
                      child: _HudFigure(
                        value: one.format(
                          one.values[(progress * (one.values.length - 1))
                              .round()],
                        ),
                        colors: colors,
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Một ô số dưới biểu đồ: số lớn kèm đơn vị nhỏ. Các ô xếp theo thứ tự lớp
/// từ trên xuống, đơn vị đủ cho biết ô nào là số gì.
class _HudFigure extends StatelessWidget {
  const _HudFigure({required this.value, required this.colors});

  /// Số kèm đơn vị, cách nhau một dấu cách, ví dụ "152 bpm".
  final String value;
  final ReplayColors colors;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cut = value.indexOf(' ');
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text.rich(
        TextSpan(
          text: cut < 0 ? value : value.substring(0, cut),
          children: [
            if (cut >= 0)
              TextSpan(
                text: value.substring(cut),
                style: text.labelSmall?.copyWith(color: colors.muted),
              ),
          ],
        ),
        maxLines: 1,
        style: text.labelLarge?.copyWith(
          color: colors.paper,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// Khung tin ở góc dưới: khoảnh khắc người chạy vừa đi qua bay từ dưới lên,
/// mờ dần rồi mất. Mỗi [_gap] chỉ thả một dòng; tới dồn dập thì dòng đó đứng
/// thay cả lượt và ghi còn bao nhiêu cái nữa.
class _MomentFeed extends StatefulWidget {
  const _MomentFeed({
    required this.cursor,
    required this.reach,
    required this.movingTimeSeconds,
  });

  final ReplayFeedCursor cursor;

  /// Người chạy đã tới đâu (0 tới 1).
  final double reach;
  final int? movingTimeSeconds;

  @override
  State<_MomentFeed> createState() => _MomentFeedState();
}

class _MomentFeedState extends State<_MomentFeed> {
  /// Đủ để dòng trước bay lên khỏi chỗ của dòng sau.
  static const _gap = Duration(milliseconds: 500);

  final _lines = <({int id, ReplayMoment moment, int more})>[];
  int _lineId = 0;

  /// Đang chờ tới lượt: một khoảnh khắc đứng thay và tổng số đang chờ.
  ReplayMoment? _waiting;
  int _waitingCount = 0;
  Timer? _cooldown;

  @override
  void initState() {
    super.initState();
    _take();
  }

  @override
  void didUpdateWidget(_MomentFeed old) {
    super.didUpdateWidget(old);
    if (widget.reach < old.reach) {
      // Phát lại từ đầu: bỏ những dòng của lượt trước.
      _cooldown?.cancel();
      _cooldown = null;
      _lines.clear();
      _waiting = null;
      _waitingCount = 0;
    }
    _take();
  }

  @override
  void dispose() {
    _cooldown?.cancel();
    super.dispose();
  }

  void _take() {
    final passed = widget.cursor.advance(widget.reach);
    if (passed.isEmpty) return;
    _waitingCount += passed.length;
    // Ảnh ít và là của chủ buổi chạy nên được đứng thay trước cổ vũ.
    final photo = passed.where((m) => m.photoPath != null).lastOrNull;
    _waiting = photo ?? (_waiting?.photoPath != null ? _waiting : passed.last);
    _release();
  }

  /// Thả dòng đang chờ nếu đã hết [_gap] từ dòng trước.
  void _release() {
    final moment = _waiting;
    if (moment == null || _cooldown != null) return;
    _lines.add((id: _lineId++, moment: moment, more: _waitingCount - 1));
    _waiting = null;
    _waitingCount = 0;
    _cooldown = Timer(_gap, () {
      _cooldown = null;
      if (mounted) setState(_release);
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.cursor.totalMeters;
    return SizedBox(
      height: _FeedLine.rise + 44,
      child: Stack(
        alignment: Alignment.bottomLeft,
        clipBehavior: Clip.none,
        children: [
          for (final line in _lines)
            _FeedLine(
              key: ValueKey(line.id),
              moment: line.moment,
              more: line.more,
              // Giờ chạy lúc đó, tính theo quãng đường đã đi.
              time: switch (widget.movingTimeSeconds) {
                final seconds? => formatDuration(
                  (seconds * line.moment.fraction(total)).round(),
                ),
                null => null,
              },
              onGone: () => setState(
                () => _lines.removeWhere((other) => other.id == line.id),
              ),
            ),
        ],
      ),
    );
  }
}

/// Một dòng của khung tin: bay lên [rise] điểm ảnh, hiện nhanh lúc đầu rồi
/// mờ dần từ nửa đường, hết thì gọi [onGone].
class _FeedLine extends StatefulWidget {
  const _FeedLine({
    super.key,
    required this.moment,
    required this.more,
    required this.time,
    required this.onGone,
  });

  static const rise = 160.0;

  final ReplayMoment moment;

  /// Còn bao nhiêu khoảnh khắc tới cùng lúc mà dòng này đứng thay.
  final int more;

  /// Giờ chạy lúc khoảnh khắc xảy ra; null là buổi chạy không có thời gian.
  final String? time;
  final VoidCallback onGone;

  @override
  State<_FeedLine> createState() => _FeedLineState();
}

class _FeedLineState extends State<_FeedLine>
    with SingleTickerProviderStateMixin {
  late final _life = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  late final _fade = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0, end: 1), weight: 10),
    TweenSequenceItem(tween: ConstantTween(1), weight: 40),
    TweenSequenceItem(tween: Tween(begin: 1, end: 0), weight: 50),
  ]).animate(_life);

  @override
  void initState() {
    super.initState();
    _life.forward().whenComplete(() {
      if (mounted) widget.onGone();
    });
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final colors = ReplayColors.of(palette);
    final moment = widget.moment;
    final text = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: colors.paper,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final Widget lead;
    final Widget label;
    if (moment.photoPath case final path?) {
      lead = ClipRRect(
        borderRadius: BorderRadius.all(palette.cornerRadius(8)),
        child: SizedBox.square(
          dimension: 34,
          child: StorageImage(
            path: path,
            cacheWidth: (34 * MediaQuery.devicePixelRatioOf(context)).round(),
            placeholder: ColoredBox(color: colors.muted),
          ),
        ),
      );
      label = Text(
        [formatDistance(moment.distanceMeters), ?widget.time].join(' · '),
        style: text,
      );
    } else {
      final url = moment.avatarUrl;
      lead = RunNowAvatar(
        radius: 13,
        backgroundColor: colors.line,
        backgroundImage: url == null
            ? null
            : cachedAvatarImage(context, url, 26),
        child: url == null
            ? Icon(Icons.person_rounded, size: 14, color: colors.onLine)
            : null,
      );
      label = Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          if (moment.name case final name?)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
          Text(moment.emoji!, style: const TextStyle(fontSize: 18)),
          if (widget.time case final time?)
            Text(time, style: text?.copyWith(color: colors.muted)),
        ],
      );
    }
    final pill = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.night.withValues(alpha: 0.72),
        borderRadius: BorderRadius.all(palette.cornerRadius(20)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            lead,
            label,
            if (widget.more > 0)
              Text(
                '+${widget.more}',
                style: text?.copyWith(color: colors.muted),
              ),
          ],
        ),
      ),
    );
    return AnimatedBuilder(
      animation: _life,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, -_FeedLine.rise * _life.value),
        child: child,
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: FadeTransition(opacity: _fade, child: pill),
      ),
    );
  }
}

/// Các loại số liệu vẽ chồng lớp trong một vùng: lớp đầu nằm trên cùng, mỗi
/// lớp sau lùi xuống [_step] và che phần chân của lớp trước. Phần đã chạy
/// qua lên màu, phần chưa tới thì chìm.
class _LayersPainter extends CustomPainter {
  _LayersPainter({
    required this.layers,
    required this.progress,
    required this.colors,
    this.peaks = const [],
    this.photos = const [],
    this.peakStyle,
  });

  /// Có đỉnh cổ vũ thì phần trên cùng cao chừng này để dành cho nhãn.
  static const _peakRoom = 20.0;

  /// Mép trên khi không có nhãn, đủ cho chấm của lớp đầu khỏi bị cắt.
  static const _headRoom = 6.0;

  /// Mỗi lớp dao động trong khoảng cao này.
  static const _amp = 18.0;

  /// Lớp sau lùi xuống so với lớp trước.
  static const _step = 9.0;

  /// Phần nền dưới lớp cuối.
  static const _foot = 6.0;

  static double heightFor(int layers, {required bool peaks}) =>
      (peaks ? _peakRoom : _headRoom) + _amp + _step * (layers - 1) + _foot;

  /// Mỗi phần tử là một loại số liệu rải đều theo quãng đường.
  final List<List<double>> layers;
  final double progress;
  final ReplayColors colors;

  /// Đỉnh cổ vũ: emoji và số lần đứng trên lớp đầu, nối xuống bằng nét đứt.
  /// Người chạy tới nơi thì mới hiện.
  final List<ReplayCheerPeak> peaks;

  /// Ảnh dọc đường (0 tới 1): ô sáng nằm trên lớp đầu, tới nơi mới hiện.
  final List<double> photos;
  final TextStyle? peakStyle;

  @override
  void paint(Canvas canvas, Size size) {
    final head = peaks.isEmpty ? _headRoom : _peakRoom;
    final doneX = size.width * progress;
    final done = Rect.fromLTRB(0, 0, doneX, size.height);

    // Giá trị thấp nhất và cao nhất của từng lớp, tính một lần cho cả lượt vẽ.
    final bounds = [
      for (final values in layers)
        (low: values.reduce(math.min), high: values.reduce(math.max)),
    ];

    // Điểm trên lớp [layer] ở vị trí [fraction] (0 tới 1) của buổi chạy.
    Offset on(int layer, double fraction) {
      final values = layers[layer];
      final low = bounds[layer].low;
      final range = bounds[layer].high - low;
      final at = fraction * (values.length - 1);
      final i = at.floor().clamp(0, values.length - 2);
      final value = values[i] + (values[i + 1] - values[i]) * (at - i);
      // Chừa 3 px trên dưới cho nét khỏi chạm lớp kế bên.
      return Offset(
        size.width * fraction,
        head +
            layer * _step +
            3 +
            (_amp - 6) * (1 - (range <= 0 ? 0.5 : (value - low) / range)),
      );
    }

    Paint stroke(Color color, double width) => Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeJoin = StrokeJoin.round;

    for (var layer = 0; layer < layers.length; layer++) {
      final count = layers[layer].length;
      Offset point(int i) => on(layer, i / (count - 1));
      // Nối qua trung điểm bằng đường cong bậc hai cho ra dáng sóng.
      final wave = Path()..moveTo(0, point(0).dy);
      for (var i = 1; i < count; i++) {
        final from = point(i - 1), to = point(i);
        wave.quadraticBezierTo(
          from.dx,
          from.dy,
          (from.dx + to.dx) / 2,
          (from.dy + to.dy) / 2,
        );
      }
      wave.lineTo(size.width, point(count - 1).dy);
      final area = Path.from(wave)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();

      final color = colors.layers[layer];
      // Nền lớp tô đặc để che chân lớp phía sau.
      final fill = Color.lerp(color, colors.night, 0.62)!;
      canvas
        ..drawPath(area, Paint()..color = Color.lerp(fill, colors.night, 0.6)!)
        ..drawPath(wave, stroke(colors.muted.withValues(alpha: 0.45), 1))
        ..save()
        ..clipRect(done)
        ..drawPath(area, Paint()..color = fill)
        ..drawPath(wave, stroke(color, layer == 0 ? 2.5 : 1.8))
        ..restore();
    }

    for (final photo in photos) {
      if (photo > progress) continue;
      canvas.drawRect(
        Rect.fromCenter(center: on(0, photo), width: 7, height: 7),
        Paint()..color = colors.paper,
      );
    }
    for (final peak in peaks) {
      if (peak.at > progress) continue;
      final label = TextPainter(
        text: TextSpan(text: '${peak.emoji} ${peak.count}', style: peakStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final foot = on(0, peak.at);
      // Nhãn sát mép thì dịch vào cho khỏi bị cắt.
      final left = (foot.dx - label.width / 2)
          .clamp(0.0, math.max(0.0, size.width - label.width))
          .toDouble();
      label.paint(canvas, Offset(left, (head - 4 - label.height) / 2));
      final stem = stroke(colors.line, 1);
      for (var dash = head - 4; dash < foot.dy - 4; dash += 4) {
        canvas.drawLine(
          Offset(foot.dx, dash),
          Offset(foot.dx, math.min(dash + 2, foot.dy - 4)),
          stem,
        );
      }
      label.dispose();
    }

    // Chấm vẽ sau cùng để lớp phía trước không che mất.
    for (var layer = 0; layer < layers.length; layer++) {
      final here = on(layer, progress);
      final radius = layer == 0 ? 4.5 : 3.0;
      canvas
        ..drawCircle(here, radius, Paint()..color = colors.layers[layer])
        ..drawCircle(here, radius, stroke(colors.paper, layer == 0 ? 2 : 1.2));
    }
  }

  @override
  bool shouldRepaint(_LayersPainter old) =>
      old.progress != progress ||
      old.layers != layers ||
      old.colors != colors ||
      old.peaks != peaks ||
      old.photos != photos ||
      old.peakStyle != peakStyle;
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
