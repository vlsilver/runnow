import 'dart:math' as math;

import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:latlong2/latlong.dart';

/// Lưới ô của lãnh địa: tile slippy map z18, gom theo chunk z13. Backend giữ
/// cùng hai zoom này (territory_grid.go); app chỉ dùng để vẽ và tìm chunk cần
/// tải, không tính ô hay chủ ô.
const territoryCellZoom = 18;
const territoryChunkZoom = 13;

/// Số chunk tối đa app nghe cùng lúc. Khung nhìn chứa nhiều chunk hơn (zoom
/// quá xa) thì không tải ô.
const territoryMaxChunks = 16;

/// Toạ độ một tile ở zoom ngầm định theo ngữ cảnh (ô hay chunk). [id] là khoá
/// "x_y" backend dùng cho doc chunk và cho key ô trong `cells`.
class TileXY {
  const TileXY(this.x, this.y);

  final int x;
  final int y;

  String get id => '${x}_$y';

  /// Đọc khoá "x_y"; null khi sai dạng hay có số âm.
  static TileXY? parse(String? id) {
    if (id == null) return null;
    final parts = id.split('_');
    if (parts.length != 2) return null;
    final x = int.tryParse(parts[0]);
    final y = int.tryParse(parts[1]);
    if (x == null || y == null || x < 0 || y < 0) return null;
    return TileXY(x, y);
  }

  @override
  bool operator ==(Object other) =>
      other is TileXY && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => id;
}

/// Góc tây bắc của tile (x, y) ở [zoom], theo công thức "Slippy map
/// tilenames" của OSM. Dùng (x + 1, y + 1) để lấy góc đông nam.
LatLng tileCorner(num x, num y, int zoom) {
  final n = math.pow(2, zoom);
  final lng = x / n * 360 - 180;
  final mercator = math.pi * (1 - 2 * y / n);
  final lat = math.atan(_sinh(mercator)) * 180 / math.pi;
  return LatLng(lat, lng);
}

double _sinh(double v) => (math.exp(v) - math.exp(-v)) / 2;

/// Bốn góc của ô z18 theo chiều kim đồng hồ từ góc tây bắc.
List<LatLng> cellCorners(TileXY cell) => [
  tileCorner(cell.x, cell.y, territoryCellZoom),
  tileCorner(cell.x + 1, cell.y, territoryCellZoom),
  tileCorner(cell.x + 1, cell.y + 1, territoryCellZoom),
  tileCorner(cell.x, cell.y + 1, territoryCellZoom),
];

/// Tile chứa [point] ở [zoom]. Điểm ngoài biên Mercator (±85,05°) hay đúng
/// kinh độ 180 được kẹp về hàng, cột biên, giống backend.
TileXY tileAt(LatLng point, int zoom) {
  final n = 1 << zoom;
  final x = ((point.longitude + 180) / 360 * n).floor();
  final rad = point.latitude * math.pi / 180;
  final y =
      ((1 - math.log(math.tan(rad) + 1 / math.cos(rad)) / math.pi) / 2 * n)
          .floor();
  return TileXY(x.clamp(0, n - 1), y.clamp(0, n - 1));
}

/// Chunk z13 chứa ô z18: mỗi chunk gom 32×32 ô.
TileXY chunkOfCell(TileXY cell) {
  const shift = territoryCellZoom - territoryChunkZoom;
  return TileXY(cell.x >> shift, cell.y >> shift);
}

/// Tâm chunk, tính trên lưới Mercator để rơi đúng giữa ô trên bản đồ.
LatLng chunkCenter(TileXY chunk) =>
    tileCorner(chunk.x + 0.5, chunk.y + 0.5, territoryChunkZoom);

/// Các chunk z13 giao với [bounds]. Null khi khung nhìn chứa quá [max] chunk,
/// tức đang zoom quá xa để tải ô.
List<TileXY>? chunksInView(
  LatLngBounds bounds, {
  int max = territoryMaxChunks,
}) {
  final northWest = tileAt(bounds.northWest, territoryChunkZoom);
  final southEast = tileAt(bounds.southEast, territoryChunkZoom);
  final columns = southEast.x - northWest.x + 1;
  final rows = southEast.y - northWest.y + 1;
  // Khung vắt qua kinh tuyến 180 cho cột âm; vùng có ô là Việt Nam nên coi như
  // quá xa.
  if (columns <= 0 || rows <= 0 || columns * rows > max) return null;
  return [
    for (var y = northWest.y; y <= southEast.y; y++)
      for (var x = northWest.x; x <= southEast.x; x++) TileXY(x, y),
  ];
}

/// Chu vi xích đạo trong Web Mercator (EPSG:3857), mét.
const _earthCircumference = 40075016.686;

/// Diện tích một ô z18 (m²) ở vĩ độ của [chunk]. Ô vuông trên Mercator, cạnh
/// bằng chu vi xích đạo chia 2^18 nhân cos(vĩ độ): khoảng 150 m ở TP.HCM.
/// Lấy vĩ độ tâm chunk; trong một chunk (khoảng 5 km) sai lệch dưới 0,2%.
double territoryCellAreaM2(TileXY chunk) {
  final lat = chunkCenter(chunk).latitude * math.pi / 180;
  final side = _earthCircumference / (1 << territoryCellZoom) * math.cos(lat);
  return side * side;
}
