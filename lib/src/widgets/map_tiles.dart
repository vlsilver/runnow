import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';

/// Mẫu URL tile nền cho mọi `FlutterMap` trong app. Đổi nguồn tile thì chỉ
/// sửa ở đây (kèm [MapAttribution] nếu đổi nhà cung cấp).
///
/// Remote Config `map_tile_url_light` / `map_tile_url_dark` ghi đè mẫu mặc
/// định, nên đổi nguồn hay gắn key (CARTO bắt `?key=` từ 29/9/2026) không cần
/// phát hành app mới. Key nằm trong giá trị RC chứ không nằm trong code do repo
/// public.
const _lightTileTemplate =
    'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';
const _darkTileTemplate =
    'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';

/// Lớp tile nền dùng chung cho mọi bản đồ trong app.
TileLayer mapTileLayer(BuildContext context, {required bool dark}) {
  final template = mapTileTemplate(dark: dark);
  return TileLayer(
    key: ValueKey(template),
    urlTemplate: template,
    userAgentPackageName: 'com.threei.run',
    retinaMode: RetinaMode.isHighDensity(context),
  );
}

String mapTileTemplate({required bool dark}) => resolveMapTileTemplate(
  _remoteString(dark ? 'map_tile_url_dark' : 'map_tile_url_light'),
  dark: dark,
);

/// Giá trị RC gõ sai trên console thì mọi bản đồ trắng trơn, nên chỉ nhận
/// URL https có đủ {z} {x} {y}; còn lại dùng mẫu mặc định.
String resolveMapTileTemplate(String? remote, {required bool dark}) {
  final value = remote?.trim() ?? '';
  final usable =
      value.startsWith('https://') &&
      value.contains('{z}') &&
      value.contains('{x}') &&
      value.contains('{y}');
  if (usable) return value;
  return dark ? _darkTileTemplate : _lightTileTemplate;
}

String? _remoteString(String key) {
  try {
    final v = FirebaseRemoteConfig.instance.getValue(key);
    return v.source == ValueSource.valueStatic ? null : v.asString();
  } catch (_) {
    // Web, test hay RC chưa khởi tạo: dùng mẫu mặc định.
    return null;
  }
}
