import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_map_tiles/vector_map_tiles.dart';
import 'package:vector_tile_renderer/vector_tile_renderer.dart' as vtr;

import '../theme_tokens.dart';
import 'map_tiles.dart';

/// Chạy thử với server tile trên máy:
/// `--dart-define=MAP_VECTOR_URL=http://localhost:8080/vn/{z}/{x}/{y}.mvt`.
const _buildVectorUrl = String.fromEnvironment('MAP_VECTOR_URL');

/// Nguồn tile vector (schema Protomaps) cho bản đồ nền, lấy từ Remote Config
/// `map_vector_url` để bật, tắt hay đổi host mà không cần ra bản app mới.
/// Trống thì app vẽ tile ảnh như cũ.
String get _vectorUrl => _buildVectorUrl.isNotEmpty
    ? _buildVectorUrl
    : _remoteString('map_vector_url');

/// Chạy thử với glyph trên máy:
/// `--dart-define=MAP_GLYPH_URL=http://localhost:8090/{fontstack}/{range}.pbf`.
const _buildGlyphUrl = String.fromEnvironment('MAP_GLYPH_URL');

/// Nguồn glyph của chữ trên màn replay 3D, mẫu `.../{fontstack}/{range}.pbf`,
/// lấy từ Remote Config `map_glyph_url`. Trống thì màn 3D không vẽ chữ. Bộ
/// glyph sinh bằng `tool/build_map_glyphs.dart`.
String get _glyphUrl =>
    _buildGlyphUrl.isNotEmpty ? _buildGlyphUrl : _remoteString('map_glyph_url');

String _remoteString(String key) {
  try {
    return FirebaseRemoteConfig.instance.getString(key);
  } on FirebaseException {
    // Firebase chưa khởi tạo (widget test): coi như chưa đặt giá trị.
    return '';
  }
}

const _source = 'protomaps';

/// Tên do Trung Quốc đặt cho đơn vị hành chính trên Hoàng Sa, Trường Sa.
const _hiddenNames = ['Sansha', 'Tam Sa', '三沙市', '西沙区', '南沙区'];

/// Nhãn chủ quyền app tự vẽ, không lấy từ dữ liệu.
const _sovereignLabels = [
  (name: 'QUẦN ĐẢO HOÀNG SA\n(VIỆT NAM)', point: LatLng(16.5, 112.0)),
  (name: 'QUẦN ĐẢO TRƯỜNG SA\n(VIỆT NAM)', point: LatLng(10.0, 114.3)),
];
const _font = ['Barlow Condensed'];

/// Tên bộ glyph mà `tool/build_map_glyphs.dart` sinh ra cho MapLibre.
const _glyphFont = ['BarlowCondensed-SemiBold'];

/// Bảng màu một kiểu bản đồ, viết dạng chuỗi hex của style JSON.
typedef _MapColors = ({
  String land,
  String water,
  String green,
  String building,
  String roadMinor,
  String roadMajor,
  String roadHighway,
  String ink,
  String muted,
});

const _MapColors _light = (
  land: '#F2F1ED',
  water: '#9CC4DD',
  green: '#C9DFB6',
  building: '#E3DED3',
  roadMinor: '#FFFFFF',
  roadMajor: '#F6D98A',
  roadHighway: '#F0A94E',
  ink: '#151515',
  muted: '#6F6B65',
);

const _MapColors _dark = (
  land: '#1D1E20',
  water: '#12304A',
  green: '#1F3527',
  building: '#27282B',
  roadMinor: '#303236',
  roadMajor: '#6E5B2C',
  roadHighway: '#A06E2A',
  ink: '#F2F1ED',
  muted: '#9A968F',
);

Map<String, dynamic> _line(
  String id,
  List<Object> filter,
  String color,
  List<List<num>> width, {
  int minzoom = 0,
}) => {
  'id': id,
  'type': 'line',
  'source': _source,
  'source-layer': 'roads',
  'minzoom': minzoom,
  'filter': filter,
  'layout': {'line-cap': 'butt', 'line-join': 'miter'},
  'paint': {
    'line-color': color,
    'line-width': {'base': 1.4, 'stops': width},
  },
};

Map<String, dynamic> _label(
  String id,
  String layer,
  List<Object> filter,
  String color,
  List<List<num>> size, {
  required String halo,
  int minzoom = 0,
  bool upper = false,
  bool alongLine = false,
}) => {
  'id': id,
  'type': 'symbol',
  'source': _source,
  'source-layer': layer,
  'minzoom': minzoom,
  'filter': filter,
  'layout': {
    'text-field': '{name}',
    'text-font': _font,
    'text-size': {'stops': size},
    if (upper) 'text-transform': 'uppercase',
    if (alongLine) 'symbol-placement': 'line',
    'text-letter-spacing': upper ? 0.12 : 0.02,
  },
  'paint': {
    'text-color': color,
    'text-halo-color': halo,
    'text-halo-width': 1.4,
  },
};

/// Style màu thật: nền giấy, sông xanh, công viên xanh lá, đường trắng rồi vàng
/// rồi cam theo cấp. Màu đỏ để dành cho tuyến chạy vẽ đè lên trên.
Map<String, dynamic> _mapStyle(String id, _MapColors c) => {
  'version': 8,
  'id': id,
  'sources': {
    _source: {'type': 'vector'},
  },
  'layers': [
    {
      'id': 'background',
      'type': 'background',
      'paint': {'background-color': c.water},
    },
    {
      'id': 'earth',
      'type': 'fill',
      'source': _source,
      'source-layer': 'earth',
      'paint': {'fill-color': c.land},
    },
    {
      'id': 'green',
      'type': 'fill',
      'source': _source,
      'source-layer': 'landuse',
      'filter': [
        'in',
        'kind',
        'park',
        'forest',
        'wood',
        'grass',
        'garden',
        'cemetery',
        'pitch',
        'golf_course',
        'national_park',
        'nature_reserve',
      ],
      'paint': {'fill-color': c.green},
    },
    {
      'id': 'water',
      'type': 'fill',
      'source': _source,
      'source-layer': 'water',
      'filter': ['==', r'$type', 'Polygon'],
      'paint': {'fill-color': c.water},
    },
    {
      'id': 'buildings',
      'type': 'fill',
      'source': _source,
      'source-layer': 'buildings',
      'minzoom': 14,
      'paint': {'fill-color': c.building},
    },
    _line(
      'roads-path',
      ['==', 'kind', 'path'],
      c.roadMinor,
      [
        [14, 0.6],
        [18, 2],
      ],
      minzoom: 14,
    ),
    _line(
      'roads-minor',
      ['==', 'kind', 'minor_road'],
      c.roadMinor,
      [
        [12, 0.5],
        [15, 3],
        [18, 12],
      ],
      minzoom: 12,
    ),
    _line(
      'roads-major',
      ['==', 'kind', 'major_road'],
      c.roadMajor,
      [
        [8, 0.5],
        [13, 2.5],
        [18, 18],
      ],
      minzoom: 8,
    ),
    _line(
      'roads-highway',
      ['==', 'kind', 'highway'],
      c.roadHighway,
      [
        [5, 0.6],
        [12, 3],
        [18, 22],
      ],
    ),
    {
      'id': 'boundaries',
      'type': 'line',
      'source': _source,
      'source-layer': 'boundaries',
      'filter': ['<=', 'kind_detail', 4],
      'paint': {
        'line-color': c.muted,
        'line-width': 1,
        'line-dasharray': [3, 2],
      },
    },
    _label(
      'roads-label',
      'roads',
      ['in', 'kind', 'major_road', 'highway', 'minor_road'],
      c.muted,
      [
        [13, 10],
        [17, 13],
      ],
      halo: c.land,
      minzoom: 14,
      alongLine: true,
    ),
    _label(
      'places-neighbourhood',
      'places',
      ['==', 'kind', 'neighbourhood'],
      c.muted,
      [
        [12, 10],
        [16, 13],
      ],
      halo: c.land,
      minzoom: 12,
      upper: true,
    ),
    _label(
      'places-locality',
      'places',
      [
        'all',
        ['==', 'kind', 'locality'],
        // Dữ liệu OSM ghi "thành phố Tam Sa" trên Hoàng Sa: không vẽ nhãn này.
        ['!in', 'name', ..._hiddenNames],
      ],
      c.ink,
      [
        [4, 11],
        [10, 16],
        [14, 22],
      ],
      halo: c.land,
      upper: true,
    ),
    _label(
      'places-region',
      'places',
      ['==', 'kind', 'region'],
      c.muted,
      [
        [4, 10],
        [8, 14],
      ],
      halo: c.land,
      upper: true,
    ),
    _label(
      'places-country',
      'places',
      ['==', 'kind', 'country'],
      c.ink,
      [
        [2, 12],
        [6, 20],
      ],
      halo: c.land,
      upper: true,
    ),
  ],
};

final vtr.Theme _lightTheme = vtr.ThemeReader().read(
  _mapStyle('natural-light', _light),
);
final vtr.Theme _darkTheme = vtr.ThemeReader().read(
  _mapStyle('natural-dark', _dark),
);
final vtr.Theme _nightTheme = vtr.ThemeReader().read(
  _mapStyle('natural-night', _night),
);

/// Bộ tile vector đang host chỉ có Việt Nam; khung này bao đất liền và các
/// đảo gần bờ (Phú Quốc, Côn Đảo).
const _vectorSouth = 8.2, _vectorNorth = 23.5;
const _vectorWest = 102.1, _vectorEast = 109.6;

/// [points] có nằm trọn trong vùng bộ tile vector phủ không. Chưa có điểm nào
/// thì coi như có.
bool vectorMapCovers(Iterable<LatLng> points) => points.every(
  (point) =>
      point.latitude >= _vectorSouth &&
      point.latitude <= _vectorNorth &&
      point.longitude >= _vectorWest &&
      point.longitude <= _vectorEast,
);

/// Lớp bản đồ nền: tile vector khi có nguồn tile vector và [around] (tuyến
/// hay vị trí bản đồ sẽ hiện) nằm trong vùng nó phủ, còn lại là tile ảnh của
/// [mapTileLayer]. Có [daylight] thì màu theo giờ chạy, cùng bảng màu với màn
/// replay.
Widget mapBaseLayer(
  BuildContext context, {
  required bool dark,
  required Iterable<LatLng> around,
  ReplayDaylight? daylight,
}) {
  if (_vectorUrl.isEmpty || !vectorMapCovers(around)) {
    return mapTileLayer(context, dark: dark);
  }
  return Stack(
    children: [
      VectorTileLayer(
        theme: switch (daylight) {
          ReplayDaylight.night => _nightTheme,
          ReplayDaylight.morning || ReplayDaylight.afternoon => _lightTheme,
          null => dark ? _darkTheme : _lightTheme,
        },
        tileProviders: TileProviders({
          _source: NetworkVectorTileProvider(
            urlTemplate: _vectorUrl,
            maximumZoom: 14,
          ),
        }),
      ),
      MarkerLayer(
        markers: [
          for (final label in _sovereignLabels)
            Marker(
              point: label.point,
              width: 180,
              height: 40,
              child: Text(
                label.name,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Barlow Condensed',
                  fontSize: 13,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: dark
                      ? RunFaceTokens.ironPaper
                      : RunFaceTokens.ironCoal,
                ),
              ),
            ),
        ],
      ),
    ],
  );
}

/// Có nguồn tile vector thì mới mở được màn replay 3D.
bool get hasVectorMap => _vectorUrl.isNotEmpty;

/// Layer tuyến đã chạy ở màn replay; màn replay đổi `line-gradient` của hai
/// layer này theo tiến độ.
const replayDoneLayers = ['replay-done-outline', 'replay-done'];

/// Bề rộng từng layer trong [replayDoneLayers].
const replayDoneWidths = [6.0, 4.0];

String _hex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// `line-gradient` tô [color] từ đầu tuyến tới [progress] (0..1), phần sau để
/// trong suốt.
List<Object> _doneGradient(String color, double progress) => [
  'step',
  ['line-progress'],
  color,
  progress.clamp(0.0001, 1.0),
  'rgba(0,0,0,0)',
];

/// Giá trị `line-gradient` của từng layer trong [replayDoneLayers] ở
/// [progress]: viền màu [outline], ruột màu [line].
List<List<Object>> replayDoneGradients(
  double progress, {
  required Color line,
  required Color outline,
}) => [
  _doneGradient(_hex(outline), progress),
  _doneGradient(_hex(line), progress),
];

/// Buổi trong ngày của lúc buổi chạy bắt đầu: quyết định màu map, hướng nắng
/// và trời ở đoạn mở, đoạn kết của màn replay.
enum ReplayDaylight { morning, afternoon, night }

/// [at] thuộc buổi nào. Mốc theo trời Việt Nam: sáng từ 5 giờ, tối từ 18 giờ.
ReplayDaylight replayDaylightAt(DateTime at) => switch (at.hour) {
  >= 5 && < 12 => ReplayDaylight.morning,
  >= 12 && < 18 => ReplayDaylight.afternoon,
  _ => ReplayDaylight.night,
};

const _MapColors _night = (
  land: '#131A2B',
  water: '#0A1A33',
  green: '#152A2A',
  building: '#222C44',
  roadMinor: '#2A3352',
  roadMajor: '#9A7430',
  roadHighway: '#D1953A',
  ink: '#E8ECF7',
  muted: '#8C95AD',
);

/// Đèn chiếu lên khối nhà (thuộc tính `light` của style MapLibre): sáng nắng
/// từ phía đông, chiều nắng xiên vàng từ phía tây, tối ánh trăng.
Map<String, Object>? _replayLight(ReplayDaylight? daylight) =>
    switch (daylight) {
      ReplayDaylight.morning => {
        'anchor': 'map',
        'position': [1.5, 90, 50],
        'color': '#FFFFFF',
        'intensity': 0.4,
      },
      ReplayDaylight.afternoon => {
        'anchor': 'map',
        'position': [1.5, 270, 65],
        'color': '#FFE2A8',
        'intensity': 0.5,
      },
      ReplayDaylight.night => {
        'anchor': 'map',
        'position': [1.5, 120, 40],
        'color': '#8EA0FF',
        'intensity': 0.35,
      },
      null => null,
    };

/// Giá trị `line-gradient` của [replayDoneLayers] khi cả tuyến đã vẽ xong và
/// một vệt sáng màu [glow] chạy dọc tuyến, đầu vệt ở [sweep] (0..1).
List<List<Object>> replaySweepGradients(
  double sweep, {
  required Color line,
  required Color outline,
  required Color glow,
}) {
  const tail = 0.12;
  final head = sweep.clamp(0.0, 1.0);
  final stops = <(double, String)>[
    (0, _hex(line)),
    if (head - tail > 0) (head - tail, _hex(line)),
    if (head > 0) (head, _hex(glow)),
    if (head + 0.01 < 1) (head + 0.01, _hex(line)),
    (1, head + 0.01 < 1 ? _hex(line) : _hex(glow)),
  ];
  return [
    _doneGradient(_hex(outline), 1),
    [
      'interpolate',
      ['linear'],
      ['line-progress'],
      for (final (at, color) in stops) ...[at, color],
    ],
  ];
}

/// Style JSON cho MapLibre ở màn replay 3D: cùng bảng màu với bản đồ nền, nhà
/// dựng khối theo `height` của tile, tuyến [route] (mỗi điểm là [lng, lat]) nằm
/// sẵn trong style. Chữ chỉ có tên đường, và chỉ khi có [glyphUrl] (mặc định
/// lấy từ Remote Config `map_glyph_url`) vì MapLibre không dùng được font của
/// Flutter.
String replayMapStyle({
  required bool dark,
  ReplayDaylight? daylight,
  required List<List<double>> route,
  required Color line,
  required Color outline,
  String? glyphUrl,
}) {
  final c = switch (daylight) {
    ReplayDaylight.morning || ReplayDaylight.afternoon => _light,
    ReplayDaylight.night => _night,
    null => dark ? _dark : _light,
  };
  final light = _replayLight(daylight);
  final glyphs = glyphUrl ?? _glyphUrl;
  const routeSource = 'replay-route';
  final gradients = replayDoneGradients(0, line: line, outline: outline);
  Map<String, dynamic> routeLine(
    String id,
    double width,
    Map<String, Object> paint,
  ) => {
    'id': id,
    'type': 'line',
    'source': routeSource,
    'layout': {'line-join': 'round', 'line-cap': 'round'},
    'paint': {'line-width': width, ...paint},
  };
  return jsonEncode({
    'version': 8,
    if (glyphs.isNotEmpty) 'glyphs': glyphs,
    'light': ?light,
    'sources': {
      _source: {
        'type': 'vector',
        'tiles': [_vectorUrl],
        'maxzoom': 14,
        'attribution': '© OpenStreetMap',
      },
      routeSource: {
        'type': 'geojson',
        // line-gradient cần lineMetrics.
        'lineMetrics': true,
        'data': {
          'type': 'Feature',
          'properties': <String, Object>{},
          'geometry': {'type': 'LineString', 'coordinates': route},
        },
      },
    },
    'layers': [
      for (final layer in _mapStyle('replay', c)['layers'] as List)
        if (layer['type'] != 'symbol' && layer['id'] != 'buildings') layer,
      routeLine('replay-route', 3, {
        'line-color': c.muted,
        'line-opacity': 0.6,
      }),
      routeLine(replayDoneLayers[0], replayDoneWidths[0], {
        'line-gradient': gradients[0],
      }),
      routeLine(replayDoneLayers[1], replayDoneWidths[1], {
        'line-gradient': gradients[1],
      }),
      {
        'id': 'buildings-3d',
        'type': 'fill-extrusion',
        'source': _source,
        'source-layer': 'buildings',
        'minzoom': 14,
        'paint': {
          'fill-extrusion-color': c.building,
          'fill-extrusion-height': [
            'coalesce',
            ['get', 'height'],
            8,
          ],
          'fill-extrusion-opacity': 0.92,
        },
      },
      // Chỉ vẽ tên đường: tên phường, khu phố làm màn 3D rối.
      if (glyphs.isNotEmpty)
        for (final layer in _mapStyle('replay', c)['layers'] as List)
          if (layer['id'] == 'roads-label')
            {
              ...layer as Map<String, dynamic>,
              'layout': {...layer['layout'] as Map, 'text-font': _glyphFont},
            },
    ],
  });
}
