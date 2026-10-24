/// Mẫu URL tile nền cho mọi `FlutterMap` trong app. Đổi nguồn tile thì chỉ
/// sửa ở đây (kèm [MapAttribution] nếu đổi nhà cung cấp).
const _lightTileTemplate =
    'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}{r}.png';
const _darkTileTemplate =
    'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';

String mapTileTemplate({required bool dark}) =>
    dark ? _darkTileTemplate : _lightTileTemplate;
