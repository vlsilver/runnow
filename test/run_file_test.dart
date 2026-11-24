import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/run_file.dart';

// Bốn điểm theo kinh tuyến 106°E, mỗi bước 0,001° vĩ độ. Ở vĩ độ 10°, bán
// kính kinh tuyến WGS84 là 6 337 357 m nên mỗi bước dài 110,6 m (tính tay).
// Điểm cuối đứng yên 40 giây: thời gian chạy không tính đoạn đó.
const _garmin = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Garmin Connect"
  xmlns="http://www.topografix.com/GPX/1/1"
  xmlns:ns3="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
  <metadata><time>2026-11-23T22:40:00Z</time></metadata>
  <trk><name>Chạy sáng Hồ Tây</name><trkseg>
    <trkpt lat="10.0000" lon="106.0"><ele>5.0</ele><time>2026-11-23T22:42:00Z</time>
      <extensions><ns3:TrackPointExtension><ns3:hr>140</ns3:hr><ns3:cad>80</ns3:cad></ns3:TrackPointExtension></extensions></trkpt>
    <trkpt lat="10.0010" lon="106.0"><ele>7.0</ele><time>2026-11-23T22:42:40Z</time>
      <extensions><ns3:TrackPointExtension><ns3:hr>150</ns3:hr><ns3:cad>82</ns3:cad></ns3:TrackPointExtension></extensions></trkpt>
    <trkpt lat="10.0020" lon="106.0"><ele>6.0</ele><time>2026-11-23T22:43:20Z</time>
      <extensions><ns3:TrackPointExtension><ns3:hr>160</ns3:hr><ns3:cad>84</ns3:cad></ns3:TrackPointExtension></extensions></trkpt>
    <trkpt lat="10.0020" lon="106.0"><ele>6.0</ele><time>2026-11-23T22:44:00Z</time>
      <extensions><ns3:TrackPointExtension><ns3:hr>158</ns3:hr><ns3:cad>0</ns3:cad></ns3:TrackPointExtension></extensions></trkpt>
  </trkseg></trk>
</gpx>''';

// Cùng bốn điểm như trên nhưng ở dạng TCX Garmin; thêm một điểm không có
// Position (mất GPS) phải bị bỏ.
const _tcx = '''<?xml version="1.0" encoding="UTF-8"?>
<TrainingCenterDatabase
  xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"
  xmlns:ns3="http://www.garmin.com/xmlschemas/ActivityExtension/v2">
  <Activities><Activity Sport="Running"><Id>2026-11-23T22:42:00Z</Id>
    <Lap StartTime="2026-11-23T22:42:00Z"><Track>
      <Trackpoint><Time>2026-11-23T22:42:00Z</Time>
        <Position><LatitudeDegrees>10.0000</LatitudeDegrees><LongitudeDegrees>106.0</LongitudeDegrees></Position>
        <AltitudeMeters>5.0</AltitudeMeters><HeartRateBpm><Value>140</Value></HeartRateBpm>
        <Extensions><ns3:TPX><ns3:RunCadence>80</ns3:RunCadence></ns3:TPX></Extensions></Trackpoint>
      <Trackpoint><Time>2026-11-23T22:42:20Z</Time><HeartRateBpm><Value>145</Value></HeartRateBpm></Trackpoint>
      <Trackpoint><Time>2026-11-23T22:42:40Z</Time>
        <Position><LatitudeDegrees>10.0010</LatitudeDegrees><LongitudeDegrees>106.0</LongitudeDegrees></Position>
        <AltitudeMeters>7.0</AltitudeMeters><HeartRateBpm><Value>150</Value></HeartRateBpm>
        <Extensions><ns3:TPX><ns3:RunCadence>82</ns3:RunCadence></ns3:TPX></Extensions></Trackpoint>
      <Trackpoint><Time>2026-11-23T22:43:20Z</Time>
        <Position><LatitudeDegrees>10.0020</LatitudeDegrees><LongitudeDegrees>106.0</LongitudeDegrees></Position>
        <AltitudeMeters>6.0</AltitudeMeters><HeartRateBpm><Value>160</Value></HeartRateBpm>
        <Extensions><ns3:TPX><ns3:RunCadence>84</ns3:RunCadence></ns3:TPX></Extensions></Trackpoint>
      <Trackpoint><Time>2026-11-23T22:44:00Z</Time>
        <Position><LatitudeDegrees>10.0020</LatitudeDegrees><LongitudeDegrees>106.0</LongitudeDegrees></Position>
        <AltitudeMeters>6.0</AltitudeMeters><HeartRateBpm><Value>158</Value></HeartRateBpm>
        <Extensions><ns3:TPX><ns3:RunCadence>0</ns3:RunCadence></ns3:TPX></Extensions></Trackpoint>
    </Track></Lap>
  </Activity></Activities>
</TrainingCenterDatabase>''';

RunFile _parse(String xml) => parseRunFile(utf8.encode(xml));

// Giờ FIT là số giây kể từ 1989-12-31 00:00 UTC (FIT SDK, Protocol).
int _fitTime(DateTime time) =>
    time.difference(DateTime.utc(1989, 12, 31)).inSeconds;

// Toạ độ FIT: 2^31 semicircle là 180 độ.
int _semicircles(double degrees) => (degrees * 2147483648 / 180).round();

/// Dựng file FIT từng byte theo FIT SDK, Protocol: header 14 byte, các
/// message, rồi 2 byte CRC (để 0, app không kiểm).
class _Fit {
  final _body = BytesBuilder();

  /// [fields] là (số field, cỡ, kiểu gốc); [developerSizes] là cỡ các field
  /// developer.
  void define(
    int local,
    int global,
    List<(int, int, int)> fields, {
    bool bigEndian = false,
    List<int> developerSizes = const [],
  }) {
    final developer = developerSizes.isNotEmpty;
    _body.addByte(0x40 | (developer ? 0x20 : 0) | local);
    _body.add([0, bigEndian ? 1 : 0]);
    _body.add(_int(global, 2, bigEndian));
    _body.addByte(fields.length);
    for (final (number, size, type) in fields) {
      _body.add([number, size, type]);
    }
    if (developer) {
      _body.addByte(developerSizes.length);
      for (final (i, size) in developerSizes.indexed) {
        _body.add([i, size, 0]);
      }
    }
  }

  void data(int header, List<List<int>> values) {
    _body.addByte(header);
    for (final value in values) {
      _body.add(value);
    }
  }

  Uint8List build() {
    final body = _body.toBytes();
    return Uint8List.fromList([
      14, 0x20, 0x08, 0x08, // cỡ header, bản protocol, bản profile
      ..._int(body.length, 4, false),
      ...ascii.encode('.FIT'),
      0, 0,
      ...body,
      0, 0,
    ]);
  }
}

List<int> _int(int value, int size, bool bigEndian) {
  final bytes = [for (var i = 0; i < size; i++) (value >> (8 * i)) & 0xFF];
  return bigEndian ? bytes.reversed.toList() : bytes;
}

const _uint8 = 0x02;
const _uint16 = 0x84;
const _sint32 = 0x85;
const _uint32 = 0x86;

/// Bốn điểm như file GPX ở trên, ghi bằng FIT: trước đó có message file_id
/// (global 0) app phải bỏ qua.
Uint8List _garminFit() {
  final fit = _Fit()
    ..define(1, 0, [(0, 1, 0x00)])
    ..data(0x01, [
      [4], // file_id.type = activity
    ])
    ..define(0, 20, [
      (253, 4, _uint32),
      (0, 4, _sint32),
      (1, 4, _sint32),
      (2, 2, _uint16),
      (3, 1, _uint8),
      (4, 1, _uint8),
    ]);
  const rows = [
    (0, 10.0000, 5, 140, 80),
    (40, 10.0010, 7, 150, 82),
    (80, 10.0020, 6, 160, 84),
    (120, 10.0020, 6, 158, 0),
  ];
  final start = DateTime.utc(2026, 11, 23, 22, 42);
  for (final (seconds, lat, altitude, hr, cad) in rows) {
    fit.data(0x00, [
      _int(_fitTime(start.add(Duration(seconds: seconds))), 4, false),
      _int(_semicircles(lat), 4, false),
      _int(_semicircles(106.0), 4, false),
      // Độ cao FIT: (mét + 500) × 5.
      _int((altitude + 500) * 5, 2, false),
      [hr],
      [cad],
    ]);
  }
  return fit.build();
}

void main() {
  test('đọc tên, giờ bắt đầu, quãng đường và thời gian chạy', () {
    final run = _parse(_garmin);

    expect(run.name, 'Chạy sáng Hồ Tây');
    expect(run.startedAt, DateTime.utc(2026, 11, 23, 22, 42));
    expect(run.points, hasLength(4));
    expect(run.distanceMeters, closeTo(221.2, 0.5));
    // Hai đoạn 40 giây có chạy; đoạn đứng yên cuối không tính.
    expect(run.movingTimeSeconds, 80);
  });

  test('giữ giờ và độ cao từng điểm cho biểu đồ pace và độ cao', () {
    final run = _parse(_garmin);

    final timed = run.routePoints!;
    expect(timed[1].timestamp, DateTime.utc(2026, 11, 23, 22, 42, 40));
    expect([for (final p in timed) p.altitudeMeters], [5.0, 7.0, 6.0, 6.0]);
  });

  test(
    'nhịp tim và guồng chân từ phần mở rộng Garmin, theo mốc quãng đường',
    () {
      final run = _parse(_garmin);

      expect(run.streams['heartrate'], [140, 150, 160, 158]);
      expect(run.streams['cadence'], [80, 82, 84, 0]);
      final distance = run.streams['distance']!;
      expect(distance.first, 0);
      expect(distance[1], closeTo(110.6, 0.3));
      expect(distance.last, closeTo(221.2, 0.5));
    },
  );

  test('file không có giờ: vẫn có tuyến, không có pace và thời gian', () {
    const gpx = '''<gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
      <trk><trkseg>
        <trkpt lat="10.0000" lon="106.0"><ele>5</ele></trkpt>
        <trkpt lat="10.0010" lon="106.0"><ele>7</ele></trkpt>
      </trkseg></trk></gpx>''';

    final run = _parse(gpx);

    expect(run.points, hasLength(2));
    expect(run.routePoints, isNull);
    expect(run.movingTimeSeconds, isNull);
    expect(run.startedAt, isNull);
    expect(run.streams['altitude'], [5, 7]);
    expect(run.streams.containsKey('heartrate'), isFalse);
  });

  test('chỉ một vài điểm có nhịp tim thì bỏ biểu đồ nhịp tim', () {
    const gpx =
        '''<gpx xmlns:g="http://www.garmin.com/xmlschemas/TrackPointExtension/v1"><trk><trkseg>
      <trkpt lat="10.0000" lon="106.0"><extensions><g:hr>140</g:hr></extensions></trkpt>
      <trkpt lat="10.0010" lon="106.0"></trkpt>
      <trkpt lat="10.0020" lon="106.0"></trkpt>
    </trkseg></trk></gpx>''';

    expect(_parse(gpx).streams.containsKey('heartrate'), isFalse);
  });

  test('file không phải GPX có đường chạy thì báo lỗi', () {
    expect(() => _parse('không phải xml'), throwsFormatException);
    expect(
      () => _parse('<gpx><trk><trkseg></trkseg></trk></gpx>'),
      throwsFormatException,
    );
    expect(
      () => _parse(
        '<gpx><trk><trkseg><trkpt lat="10" lon="106"/></trkseg></trk></gpx>',
      ),
      throwsFormatException,
    );
  });

  test('TCX: bỏ điểm không có toạ độ, đọc nhịp tim và RunCadence', () {
    final run = _parse(_tcx);

    expect(run.name, isNull);
    expect(run.startedAt, DateTime.utc(2026, 11, 23, 22, 42));
    expect(run.points, hasLength(4));
    expect(run.distanceMeters, closeTo(221.2, 0.5));
    expect(run.movingTimeSeconds, 80);
    expect(run.streams['heartrate'], [140, 150, 160, 158]);
    expect(run.streams['cadence'], [80, 82, 84, 0]);
    expect(run.streams['altitude'], [5, 7, 6, 6]);
  });

  test('TCX máy chạy bộ, không có toạ độ, thì báo lỗi', () {
    const tcx = '''<TrainingCenterDatabase><Activities><Activity><Lap><Track>
      <Trackpoint><Time>2026-11-23T22:42:00Z</Time></Trackpoint>
      <Trackpoint><Time>2026-11-23T22:42:40Z</Time></Trackpoint>
    </Track></Lap></Activity></Activities></TrainingCenterDatabase>''';

    expect(() => _parse(tcx), throwsFormatException);
  });

  test('FIT: đọc record, bỏ message khác, đổi semicircle và độ cao', () {
    final run = parseRunFile(_garminFit());

    expect(run.name, isNull);
    expect(run.startedAt, DateTime.utc(2026, 11, 23, 22, 42));
    expect(run.points, hasLength(4));
    expect(run.points[1].latitude, closeTo(10.001, 1e-7));
    expect(run.points[1].longitude, closeTo(106.0, 1e-7));
    expect(run.distanceMeters, closeTo(221.2, 0.5));
    expect(run.movingTimeSeconds, 80);
    expect(run.streams['altitude'], [5, 7, 6, 6]);
    expect(run.streams['heartrate'], [140, 150, 160, 158]);
    expect(run.streams['cadence'], [80, 82, 84, 0]);
  });

  test(
    'FIT: big-endian, field developer, giờ nén qua vòng 32 giây, bỏ điểm không toạ độ',
    () {
      // 22:42:06 có 5 bit thấp của giờ FIT là 30 (tính tay: giờ FIT của
      // 22:42:00 chia 32 dư 24). Giờ nén +4 nhỏ hơn 30 nên sang vòng mới:
      // 30 → 36, tức 22:42:12.
      final start = _fitTime(DateTime.utc(2026, 11, 23, 22, 42, 6));
      expect(start % 32, 30);
      List<int> be(int value) => _int(value, 4, true);
      const developer = [0xAB, 0xCD];
      final fit = _Fit()
        ..define(
          0,
          20,
          [(253, 4, _uint32), (0, 4, _sint32), (1, 4, _sint32)],
          bigEndian: true,
          developerSizes: [2],
        )
        ..define(
          1,
          20,
          [(0, 4, _sint32), (1, 4, _sint32)],
          bigEndian: true,
          developerSizes: [2],
        )
        ..data(0x00, [
          be(start),
          be(_semicircles(10.0000)),
          be(_semicircles(106.0)),
          developer,
        ])
        // Header nén: bit 7, local type 1 ở bit 5-6, 5 bit thấp của giờ.
        ..data(0x80 | (1 << 5) | 4, [
          be(_semicircles(10.0010)),
          be(_semicircles(106.0)),
          developer,
        ])
        // 22:42:16, chưa bắt được GPS: toạ độ là giá trị "không có".
        ..data(0x80 | (1 << 5) | 8, [be(0x7FFFFFFF), be(0x7FFFFFFF), developer])
        ..data(0x80 | (1 << 5) | 10, [
          be(_semicircles(10.0020)),
          be(_semicircles(106.0)),
          developer,
        ]);

      final run = parseRunFile(fit.build());

      expect(
        [for (final p in run.routePoints!) p.timestamp],
        [
          DateTime.utc(2026, 11, 23, 22, 42, 6),
          DateTime.utc(2026, 11, 23, 22, 42, 12),
          DateTime.utc(2026, 11, 23, 22, 42, 18),
        ],
      );
      expect(run.distanceMeters, closeTo(221.2, 0.5));
    },
  );

  test('FIT bị cắt ngang thì lấy phần đọc được', () {
    final full = _garminFit();
    final cut = Uint8List.sublistView(full, 0, full.length - 5);

    expect(parseRunFile(cut).points, hasLength(3));
  });

  test('FIT có dữ liệu trước định nghĩa thì báo lỗi', () {
    final fit = _Fit()
      ..data(0x00, [
        [1, 2, 3, 4],
      ]);

    expect(() => parseRunFile(fit.build()), throwsFormatException);
  });

  test(
    'FIT: toạ độ âm, enhanced_altitude thắng altitude, nhịp tim không có',
    () {
      // Nam bán cầu, tây bán cầu: semicircle âm, đọc phải là sint32.
      final fit = _Fit()
        ..define(0, 20, [
          (253, 4, _uint32),
          (0, 4, _sint32),
          (1, 4, _sint32),
          (2, 2, _uint16),
          (78, 4, _uint32),
          (3, 1, _uint8),
        ]);
      final start = DateTime.utc(2026, 11, 23, 22, 42);
      for (final (seconds, lat) in [(0, -33.9000), (40, -33.9010)]) {
        fit.data(0x00, [
          _int(_fitTime(start.add(Duration(seconds: seconds))), 4, false),
          _int(_semicircles(lat), 4, false),
          _int(_semicircles(-70.6), 4, false),
          _int((1000 + 500) * 5, 2, false), // altitude: 1000 m, bị bỏ
          _int((1200 + 500) * 5, 4, false), // enhanced_altitude: 1200 m
          [0xFF], // nhịp tim: không có
        ]);
      }

      final run = parseRunFile(fit.build());

      expect(run.points.first.latitude, closeTo(-33.9, 1e-7));
      expect(run.points.first.longitude, closeTo(-70.6, 1e-7));
      expect(run.streams['altitude'], [1200, 1200]);
      expect(run.streams.containsKey('heartrate'), isFalse);
    },
  );

  test('FIT có data_size 0 (ghi dở) thì đọc tới trước CRC', () {
    final full = _garminFit();
    full.setRange(4, 8, [0, 0, 0, 0]);

    expect(parseRunFile(full).points, hasLength(4));
  });

  test('toạ độ ngoài khoảng hay NaN thì bỏ điểm đó', () {
    final run = _parse('''
<gpx><trk><trkseg>
  <trkpt lat="10.000" lon="106.0"/>
  <trkpt lat="135.0" lon="106.0"/>
  <trkpt lat="NaN" lon="106.0"/>
  <trkpt lat="10.001" lon="181.0"/>
  <trkpt lat="10.001" lon="106.0"/>
</trkseg></trk></gpx>''');

    expect(run.points, hasLength(2));
  });

  test('hai điểm gần đối xứng qua tâm Trái Đất thì báo lỗi đọc file', () {
    expect(
      () => _parse('''
<gpx><trk><trkseg>
  <trkpt lat="10" lon="106"/>
  <trkpt lat="-10" lon="-74"/>
</trkseg></trk></gpx>'''),
      throwsFormatException,
    );
  });

  test('FIT: toạ độ ngoài khoảng thì bỏ điểm đó', () {
    final fit = _Fit()
      ..define(0, 20, [(253, 4, _uint32), (0, 4, _sint32), (1, 4, _sint32)]);
    final start = DateTime.utc(2026, 11, 23, 6);
    for (final (seconds, lat) in [(0, 10.0), (10, 135.0), (20, 10.001)]) {
      fit.data(0x00, [
        _int(_fitTime(start.add(Duration(seconds: seconds))), 4, false),
        _int(_semicircles(lat), 4, false),
        _int(_semicircles(106.0), 4, false),
      ]);
    }

    expect(parseRunFile(fit.build()).points, hasLength(2));
  });

  test('file đúng 32 MB thì đọc, thêm một byte thì báo quá lớn', () {
    // GPX hợp lệ, đệm khoảng trắng sau thẻ đóng cho đủ cỡ.
    final gpx = utf8.encode('''
<gpx><trk><trkseg>
  <trkpt lat="10.000" lon="106.0"/>
  <trkpt lat="10.001" lon="106.0"/>
</trkseg></trk></gpx>''');
    Uint8List padded(int size) => Uint8List(size)
      ..fillRange(0, size, 0x20)
      ..setRange(0, gpx.length, gpx);

    expect(parseRunFile(padded(32 * 1024 * 1024)).points, hasLength(2));
    expect(
      () => parseRunFile(padded(32 * 1024 * 1024 + 1)),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          'File quá lớn.',
        ),
      ),
    );
  });

  test('mảng rỗng (native đọc hỏng hay file quá lớn) thì báo lỗi đọc file', () {
    expect(() => parseRunFile(Uint8List(0)), throwsFormatException);
  });
}
