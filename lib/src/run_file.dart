import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:latlong2/latlong.dart';
import 'package:myrun/src/models.dart';
import 'package:xml/xml.dart';

/// Đuôi file buổi chạy app đọc được: GPX (Strava, Garmin Connect web, Coros
/// xuất ra), TCX (Garmin Connect, Polar, Suunto xuất ra) và FIT (file gốc của
/// đồng hồ Garmin, Coros, Wahoo).
const runFileExtensions = ['gpx', 'tcx', 'fit'];

/// File lớn hơn mức này thì không đọc, cho khỏi hết bộ nhớ. File thật nhỏ hơn
/// nhiều: FIT ghi mỗi giây suốt 24 giờ chừng 3 MB, GPX cùng buổi chừng 20 MB.
/// Native (RunFileInbox) gặp file quá mức này hay đọc hỏng thì giao mảng rỗng,
/// và Dart từ chối mảng rỗng như file hỏng.
const runFileMaxBytes = 32 * 1024 * 1024;

/// Một buổi chạy đọc từ file GPX, TCX hoặc FIT, chỉ để xem lại 3D. Không lưu đi
/// đâu và không tính vào BXH hay kèo.
class RunFile {
  const RunFile({
    required this.points,
    required this.distanceMeters,
    required this.streams,
    this.name,
    this.startedAt,
    this.movingTimeSeconds,
    this.routePoints,
  });

  final String? name;

  /// Giờ của điểm đầu tiên; null khi file không ghi giờ.
  final DateTime? startedAt;
  final List<LatLng> points;
  final double distanceMeters;

  /// Tổng các đoạn có di chuyển; đoạn đứng yên (bấm dừng, đợi đèn) không
  /// tính. Null khi file không ghi giờ.
  final int? movingTimeSeconds;

  /// Điểm có giờ để vẽ pace; null khi có điểm thiếu giờ.
  final List<RoutePoint>? routePoints;

  /// Cùng dạng streams Strava mà `replaySeries` đọc: `distance` (mét cộng
  /// dồn) và `altitude`, `heartrate`, `cadence` khi file có.
  final Map<String, List<double>> streams;
}

/// Điểm có di chuyển khi nhanh hơn mức này (m/s); chậm hơn là đứng yên.
const _movingSpeed = 0.5;

/// Một loại số liệu (nhịp tim, guồng...) phải có ở ít nhất chừng này phần
/// điểm mới vẽ; chỗ hụt lấy giá trị điểm trước đó.
const _streamCoverage = 0.9;

const _distance = Distance(roundResult: false);

/// Đọc file FIT (nhận theo chữ `.FIT` trong header), hoặc GPX 1.0/1.1, TCX v2.
/// Thẻ XML đọc theo tên, bỏ qua namespace vì mỗi hãng đặt tiền tố khác nhau.
/// Ném [FormatException] khi file quá [runFileMaxBytes], không đọc được, hoặc
/// có dưới hai điểm có toạ độ.
RunFile parseRunFile(Uint8List bytes) {
  if (bytes.length > runFileMaxBytes) {
    throw const FormatException('File quá lớn.');
  }
  final List<_Sample> samples;
  String? name;
  if (_isFit(bytes)) {
    samples = _fitSamples(bytes);
  } else {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
    } on XmlException catch (error) {
      throw FormatException(
        'File không phải GPX, TCX hay FIT: ${error.message}',
      );
    }
    final tcx = document.rootElement.localName == 'TrainingCenterDatabase';
    samples = tcx ? _tcxSamples(document) : _gpxSamples(document);
    if (!tcx) name = _gpxTrackName(document);
  }
  if (samples.length < 2) {
    throw const FormatException('File không có đường chạy.');
  }

  final points = [for (final s in samples) s.point];
  final times = [for (final s in samples) s.time];
  final meters = <double>[0];
  for (var i = 1; i < points.length; i++) {
    final double step;
    try {
      step = _distance(points[i - 1], points[i]);
    } on StateError {
      // Vincenty không hội tụ với hai điểm gần đối xứng qua tâm Trái Đất:
      // chỉ có ở file dựng tay, chạy thật không nhảy nửa vòng địa cầu.
      throw const FormatException('File có hai điểm liền nhau quá xa.');
    }
    meters.add(meters.last + step);
  }

  final timed = times.every((time) => time != null);
  int? moving;
  if (timed) {
    var seconds = 0.0;
    for (var i = 1; i < points.length; i++) {
      final gap = times[i]!.difference(times[i - 1]!).inMilliseconds / 1000;
      if (gap > 0 && (meters[i] - meters[i - 1]) / gap >= _movingSpeed) {
        seconds += gap;
      }
    }
    moving = seconds.round();
  }

  return RunFile(
    name: name,
    startedAt: times.first,
    points: points,
    distanceMeters: meters.last,
    movingTimeSeconds: moving,
    routePoints: timed
        ? [
            for (final s in samples)
              RoutePoint(
                latitude: s.point.latitude,
                longitude: s.point.longitude,
                timestamp: s.time!,
                altitudeMeters: s.altitude,
              ),
          ]
        : null,
    streams: {
      'distance': meters,
      'altitude': ?_filled([for (final s in samples) s.altitude]),
      'heartrate': ?_filled([for (final s in samples) s.heartRate]),
      'cadence': ?_filled([for (final s in samples) s.cadence]),
    },
  );
}

/// Một điểm có toạ độ, cùng số liệu ghi kèm nếu có.
class _Sample {
  const _Sample(
    this.point, {
    this.time,
    this.altitude,
    this.heartRate,
    this.cadence,
  });

  final LatLng point;
  final DateTime? time;
  final double? altitude;
  final double? heartRate;
  final double? cadence;
}

/// `<trkpt lat lon>` cùng giờ, độ cao, và nhịp tim, guồng chân trong
/// TrackPointExtension.
List<_Sample> _gpxSamples(XmlDocument document) => [
  for (final element in _elements(document, 'trkpt'))
    if (_latLng(element.getAttribute('lat'), element.getAttribute('lon'))
        case final point?)
      _Sample(
        point,
        time: _time(element, const {'time'}),
        altitude: _number(element, const {'ele'}),
        heartRate: _number(element, const {'hr', 'heartrate'}),
        cadence: _number(element, const {'cad', 'cadence'}),
      ),
];

/// `<Trackpoint>` có `<Position>`; điểm không có toạ độ (máy chạy bộ, mất
/// GPS) thì bỏ. Guồng chân chạy bộ nằm ở `RunCadence` trong phần mở rộng,
/// `Cadence` là của xe đạp.
List<_Sample> _tcxSamples(XmlDocument document) => [
  for (final element in _elements(document, 'Trackpoint'))
    if (_latLng(
          _text(element, const {'LatitudeDegrees'}),
          _text(element, const {'LongitudeDegrees'}),
        )
        case final point?)
      _Sample(
        point,
        time: _time(element, const {'Time'}),
        altitude: _number(element, const {'AltitudeMeters'}),
        heartRate: _number(element, const {'HeartRateBpm'}),
        cadence:
            _number(element, const {'RunCadence'}) ??
            _number(element, const {'Cadence'}),
      ),
];

// FIT: định dạng nhị phân của Garmin (FIT SDK, Protocol). Sau header là chuỗi
// message; mỗi message định nghĩa (definition) nói các message dữ liệu cùng
// "local type" phía sau có những field nào, cỡ bao nhiêu, byte thứ tự gì. Chỉ
// đọc message `record` (global 20), mỗi cái là một điểm của buổi chạy.

const _fitRecord = 20;
const _fitTimestamp = 253;
const _fitLatitude = 0;
const _fitLongitude = 1;
const _fitAltitude = 2;
const _fitHeartRate = 3;
const _fitCadence = 4;
const _fitEnhancedAltitude = 78;

/// Giây Unix của 1989-12-31 00:00 UTC, mốc giờ của FIT.
const _fitEpoch = 631065600;

/// Toạ độ FIT tính bằng semicircle: 2^31 semicircle là 180 độ.
const _semicircleDegrees = 180 / 2147483648;

bool _isFit(Uint8List bytes) =>
    bytes.length >= 12 &&
    bytes[8] == 0x2E && // .
    bytes[9] == 0x46 && // F
    bytes[10] == 0x49 && // I
    bytes[11] == 0x54; // T

class _FitField {
  const _FitField(this.number, this.offset, this.size, this.baseType);

  final int number;

  /// Vị trí field tính từ đầu phần dữ liệu của message.
  final int offset;
  final int size;
  final int baseType;
}

class _FitDefinition {
  const _FitDefinition(this.global, this.endian, this.fields, this.size);

  final int global;
  final Endian endian;
  final Map<int, _FitField> fields;

  /// Tổng số byte một message dữ liệu, kể cả field của developer.
  final int size;
}

/// Đọc các `record` có toạ độ. File bị cắt ngang (đồng bộ dở) thì lấy phần
/// đọc được; chỉ ném lỗi khi gặp message dữ liệu không có định nghĩa, tức là
/// file không đúng FIT. Không kiểm CRC: file sai CRC mà vẫn ra tuyến hợp lý
/// thì vẫn cho xem.
List<_Sample> _fitSamples(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  final headerSize = bytes[0];
  if (headerSize < 12) throw const FormatException('Header FIT hỏng.');
  final dataSize = data.getUint32(4, Endian.little);
  // data_size 0: thiết bị chưa kịp ghi lại header khi file bị ngắt, thì đọc
  // tới trước 2 byte CRC cuối.
  final end = dataSize == 0
      ? bytes.length - 2
      : math.min(headerSize + dataSize, bytes.length);
  final definitions = <int, _FitDefinition>{};
  final samples = <_Sample>[];
  int? lastTime;
  var at = headerSize;
  while (at < end) {
    final header = bytes[at++];
    if (header & 0x80 == 0 && header & 0x40 != 0) {
      final definition = _fitDefinition(
        bytes,
        data,
        at,
        end,
        header & 0x20 != 0,
      );
      if (definition == null) break;
      definitions[header & 0x0F] = definition.$1;
      at = definition.$2;
      continue;
    }

    // Header nén (bit 7) mang 5 bit thấp của giờ, cộng vào giờ đầy đủ gần
    // nhất; nhỏ hơn 5 bit thấp cũ nghĩa là đã qua vòng 32 giây.
    final compressed = header & 0x80 != 0;
    final local = compressed ? (header >> 5) & 0x03 : header & 0x0F;
    final definition = definitions[local];
    if (definition == null) {
      throw const FormatException('File FIT có dữ liệu trước định nghĩa.');
    }
    if (at + definition.size > end) break;
    if (compressed && lastTime != null) {
      final offset = header & 0x1F;
      var time = (lastTime & ~0x1F) + offset;
      if (offset < lastTime & 0x1F) time += 0x20;
      lastTime = time;
    }

    int? field(int number) {
      final field = definition.fields[number];
      if (field == null) return null;
      return _fitInt(data, at + field.offset, field, definition.endian);
    }

    lastTime = field(_fitTimestamp) ?? lastTime;
    if (definition.global == _fitRecord) {
      final latitude = field(_fitLatitude);
      final longitude = field(_fitLongitude);
      final point = latitude == null || longitude == null
          ? null
          : _point(
              latitude * _semicircleDegrees,
              longitude * _semicircleDegrees,
            );
      if (point != null) {
        final altitude = field(_fitEnhancedAltitude) ?? field(_fitAltitude);
        samples.add(
          _Sample(
            point,
            time: lastTime == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(
                    (lastTime + _fitEpoch) * 1000,
                    isUtc: true,
                  ),
            // Độ cao FIT: (mét + 500) × 5.
            altitude: altitude == null ? null : altitude / 5 - 500,
            heartRate: field(_fitHeartRate)?.toDouble(),
            cadence: field(_fitCadence)?.toDouble(),
          ),
        );
      }
    }
    at += definition.size;
  }
  return samples;
}

/// Đọc message định nghĩa bắt đầu ở [at] (sau byte header). Trả định nghĩa
/// cùng vị trí message kế tiếp; null khi file hết giữa chừng.
(_FitDefinition, int)? _fitDefinition(
  Uint8List bytes,
  ByteData data,
  int at,
  int end,
  bool developer,
) {
  if (at + 5 > end) return null;
  final endian = bytes[at + 1] == 1 ? Endian.big : Endian.little;
  final global = data.getUint16(at + 2, endian);
  final count = bytes[at + 4];
  at += 5;
  if (at + count * 3 > end) return null;
  final fields = <int, _FitField>{};
  var size = 0;
  for (var i = 0; i < count; i++, at += 3) {
    final field = _FitField(bytes[at], size, bytes[at + 1], bytes[at + 2]);
    fields[field.number] = field;
    size += field.size;
  }
  if (developer) {
    if (at + 1 > end) return null;
    final developerCount = bytes[at++];
    if (at + developerCount * 3 > end) return null;
    for (var i = 0; i < developerCount; i++, at += 3) {
      size += bytes[at + 1];
    }
  }
  return (_FitDefinition(global, endian, fields, size), at);
}

/// Số nguyên của một field theo kiểu gốc FIT; null khi là giá trị "không có"
/// của kiểu đó, hoặc field không phải số nguyên 1, 2, 4 byte (mảng, chuỗi,
/// số thực).
int? _fitInt(ByteData data, int at, _FitField field, Endian endian) {
  final (size, signed, zeroInvalid) = switch (field.baseType & 0x1F) {
    0 || 2 || 13 => (1, false, false), // enum, uint8, byte
    1 => (1, true, false), // sint8
    3 => (2, true, false), // sint16
    4 => (2, false, false), // uint16
    5 => (4, true, false), // sint32
    6 => (4, false, false), // uint32
    10 => (1, false, true), // uint8z
    11 => (2, false, true), // uint16z
    12 => (4, false, true), // uint32z
    _ => (0, false, false),
  };
  if (size == 0 || field.size != size) return null;
  final value = switch ((size, signed)) {
    (1, false) => data.getUint8(at),
    (1, true) => data.getInt8(at),
    (2, false) => data.getUint16(at, endian),
    (2, true) => data.getInt16(at, endian),
    (4, false) => data.getUint32(at, endian),
    _ => data.getInt32(at, endian),
  };
  final invalid = zeroInvalid
      ? 0
      : signed
      ? (1 << (size * 8 - 1)) - 1
      : (1 << (size * 8)) - 1;
  return value == invalid ? null : value;
}

Iterable<XmlElement> _elements(XmlDocument document, String name) => document
    .descendants
    .whereType<XmlElement>()
    .where((element) => element.localName == name);

LatLng? _latLng(String? lat, String? lon) {
  final latitude = double.tryParse(lat ?? '');
  final longitude = double.tryParse(lon ?? '');
  if (latitude == null || longitude == null) return null;
  return _point(latitude, longitude);
}

/// Toạ độ trong khoảng hợp lệ; ngoài khoảng (file hỏng hay dựng tay) thì bỏ
/// điểm như điểm không có toạ độ.
LatLng? _point(double latitude, double longitude) {
  // Viết dạng `!(<=)` để NaN (GPX ghi lat="NaN") cũng bị bỏ.
  if (!(latitude.abs() <= 90 && longitude.abs() <= 180)) return null;
  return LatLng(latitude, longitude);
}

/// Chữ của thẻ con đầu tiên (ở bất kỳ tầng nào) có tên trong [names].
String? _text(XmlElement element, Set<String> names) {
  for (final child in element.descendants.whereType<XmlElement>()) {
    if (names.contains(child.localName)) return child.innerText.trim();
  }
  return null;
}

double? _number(XmlElement element, Set<String> names) =>
    double.tryParse(_text(element, names) ?? '');

DateTime? _time(XmlElement element, Set<String> names) =>
    DateTime.tryParse(_text(element, names) ?? '');

String? _gpxTrackName(XmlDocument document) {
  for (final track in _elements(document, 'trk')) {
    for (final child in track.childElements) {
      if (child.localName == 'name') {
        final name = child.innerText.trim();
        return name.isEmpty ? null : name;
      }
    }
  }
  return null;
}

/// Chuỗi đủ dài để vẽ, chỗ hụt lấy giá trị gần nhất phía trước (đầu chuỗi hụt
/// thì lấy giá trị đầu tiên có). Null khi có quá ít điểm có số liệu.
List<double>? _filled(List<double?> values) {
  final present = values.whereType<double>();
  if (present.length < values.length * _streamCoverage) return null;
  var last = present.first;
  return [for (final value in values) last = value ?? last];
}
