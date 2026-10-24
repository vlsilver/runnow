import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

/// Tile nền cho mọi `FlutterMap` trong app: mặc định OpenStreetMap, không cần
/// key. OSM chỉ có một style sáng, nên dark mode đảo màu chính tile đó.
///
/// Remote Config `map_tile_url_light` / `map_tile_url_dark` đổi được nguồn
/// tile mà không cần phát hành app. Đặt hai URL khác nhau là nhà cung cấp có
/// style tối riêng thì dùng thẳng; đặt giống nhau hoặc bỏ trống dark thì vẫn
/// đảo màu. Key (nếu nguồn cần) nằm trong giá trị RC chứ không nằm trong code
/// do repo public.
const _osmTemplate = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

TileLayer mapTileLayer(BuildContext context, {required bool dark}) {
  final tiles = resolveMapTiles(
    light: _remoteString('map_tile_url_light'),
    dark: _remoteString('map_tile_url_dark'),
    darkMode: dark,
  );
  return TileLayer(
    key: ValueKey(tiles),
    urlTemplate: tiles.template,
    userAgentPackageName: 'com.threei.run',
    // Không có {r} mà bật retina thì flutter_map giả lập bằng 4 tile ở zoom
    // cao hơn: gấp 4 lượt gọi (OSM cấm tải nặng) và chữ trên bản đồ nhỏ đi.
    retinaMode:
        tiles.template.contains('{r}') && RetinaMode.isHighDensity(context),
    tileBuilder: tiles.invert ? darkModeTileBuilder : null,
  );
}

({String template, bool invert}) resolveMapTiles({
  String? light,
  String? dark,
  required bool darkMode,
}) {
  final lightTemplate = _usable(light) ?? _osmTemplate;
  final darkTemplate = _usable(dark);
  if (!darkMode) return (template: lightTemplate, invert: false);
  if (darkTemplate == null || darkTemplate == lightTemplate) {
    return (template: lightTemplate, invert: true);
  }
  return (template: darkTemplate, invert: false);
}

/// Nguồn phải ghi công cho [template]. Dữ liệu luôn là OSM (giấy phép ODbL);
/// CARTO chỉ ghi khi đang dùng tile của họ.
List<({String label, String url})> mapTileCredits(String template) => [
  (
    label: 'OpenStreetMap contributors',
    url: 'https://www.openstreetmap.org/copyright',
  ),
  if (template.contains('cartocdn.com'))
    (label: 'CARTO', url: 'https://carto.com/attributions'),
];

/// Mẫu tile sáng đang dùng, để [MapAttribution] ghi công đúng nguồn.
String currentMapTileTemplate() => resolveMapTiles(
  light: _remoteString('map_tile_url_light'),
  darkMode: false,
).template;

/// Giá trị RC gõ sai trên console thì mọi bản đồ trắng trơn, nên chỉ nhận
/// URL https có đủ {z} {x} {y}.
String? _usable(String? remote) {
  final value = remote?.trim() ?? '';
  final ok =
      value.startsWith('https://') &&
      value.contains('{z}') &&
      value.contains('{x}') &&
      value.contains('{y}');
  return ok ? value : null;
}

String? _remoteString(String key) {
  try {
    final v = FirebaseRemoteConfig.instance.getValue(key);
    return v.source == ValueSource.valueStatic ? null : v.asString();
  } catch (_) {
    // Web, test hay RC chưa khởi tạo: dùng mặc định.
    return null;
  }
}
