import 'package:myrun/src/territory/territory_grid.dart';

/// Một ô trong doc `territoryChunks/{x_y}`: chủ ô và số mét backend đã tính.
/// App chỉ hiện, không tự xét ai giữ ô.
class TerritoryCell {
  const TerritoryCell({
    required this.tile,
    required this.ownerUid,
    required this.meters,
    this.secondMeters = 0,
  });

  /// Ô z18.
  final TileXY tile;
  final String ownerUid;

  /// Số mét chủ ô đã chạy trong ô, trong cửa sổ giữ ô (`m`).
  final int meters;

  /// Số mét của người nhiều thứ hai trong ô (`m2`); 0 khi chỉ một người qua.
  /// Backend không lưu người đó là ai.
  final int secondMeters;

  /// Người thứ hai có từ 80% km của chủ trở lên: ô dễ mất.
  bool get contested => secondMeters > 0 && secondMeters * 5 >= meters * 4;
}

/// Đọc field `cells` của doc chunk. Doc không còn (chunk hết ô) cho danh sách
/// rỗng. Mục sai dạng thì bỏ qua để một ô hỏng không làm mất cả chunk.
List<TerritoryCell> parseTerritoryCells(Map<String, dynamic>? chunk) {
  final cells = chunk?['cells'];
  if (cells is! Map) return const [];
  return [
    for (final MapEntry(:key, :value) in cells.entries)
      if (TileXY.parse(key as String?) case final tile?)
        if (value case {'u': final String uid} when uid.isNotEmpty)
          TerritoryCell(
            tile: tile,
            ownerUid: uid,
            meters: (value['m'] as num?)?.toInt() ?? 0,
            secondMeters: (value['m2'] as num?)?.toInt() ?? 0,
          ),
  ];
}

/// Doc `territoryOwners/{uid}`: số ô người đó giữ ở từng chunk.
class TerritoryOwner {
  const TerritoryOwner(this.byChunk);

  /// Doc không tồn tại là chưa giữ ô nào.
  factory TerritoryOwner.fromMap(Map<String, dynamic>? data) {
    final raw = data?['byChunk'];
    if (raw is! Map) return const TerritoryOwner({});
    return TerritoryOwner({
      for (final MapEntry(:key, :value) in raw.entries)
        if (TileXY.parse(key as String?) case final chunk?)
          if (value is num && value > 0) chunk: value.toInt(),
    });
  }

  final Map<TileXY, int> byChunk;

  /// Tổng số ô đang giữ. Backend chỉ ghi số theo chunk, app tự cộng.
  int get cellCount => byChunk.values.fold(0, (sum, n) => sum + n);

  /// Diện tích đang giữ (m²): số ô từng chunk nhân diện tích một ô ở vĩ độ
  /// của chunk đó, vì ô nhỏ dần khi lên phía bắc.
  double get areaM2 => byChunk.entries.fold(
    0,
    (sum, e) => sum + e.value * territoryCellAreaM2(e.key),
  );

  /// Chunk giữ nhiều ô nhất, để mở màn Lãnh địa đúng chỗ hay chạy. Bằng nhau
  /// thì lấy id nhỏ hơn cho mỗi lần mở ra cùng một chỗ.
  TileXY? get topChunk {
    TileXY? best;
    var bestCount = 0;
    for (final MapEntry(:key, :value) in byChunk.entries) {
      if (value > bestCount ||
          (value == bestCount &&
              best != null &&
              key.id.compareTo(best.id) < 0)) {
        best = key;
        bestCount = value;
      }
    }
    return best;
  }
}

/// Kết quả lãnh địa của một buổi chạy, đọc từ doc nhỏ
/// `territoryResults/{uid}_{activityId}` backend ghi kèm `territory.result`.
class TerritoryResult {
  const TerritoryResult({
    required this.gained,
    this.taken = const {},
    this.chunk,
  });

  /// Null khi backend chưa ghi kết quả (vài giây sau khi lưu buổi).
  static TerritoryResult? fromMap(Map<String, dynamic>? data) {
    if (data == null) return null;
    final taken = data['taken'];
    return TerritoryResult(
      gained: (data['gained'] as num?)?.toInt() ?? 0,
      taken: {
        if (taken is Map)
          for (final MapEntry(:key, :value) in taken.entries)
            if (key is String && value is num && value > 0) key: value.toInt(),
      },
      chunk: TileXY.parse(data['chunk'] as String?),
    );
  }

  final int gained;

  /// uid người bị chiếm → số ô.
  final Map<String, int> taken;

  /// Chunk z13 đầu tiên buổi chạy qua, để mở màn Lãnh địa đúng vùng của buổi.
  /// Null khi buổi không có ô nào.
  final TileXY? chunk;

  /// Số ô buổi này có thêm: ô mới cộng ô chiếm được.
  int get total => taken.values.fold(gained, (sum, n) => sum + n);
}

/// Số liệu lãnh địa của một người, tính từ các ô người đó đang giữ.
class TerritoryStats {
  TerritoryStats(Iterable<TerritoryCell> cells)
    : cellCount = cells.length,
      meters = cells.fold(0, (sum, c) => sum + c.meters),
      strongestMeters = cells.fold(
        0,
        (best, c) => c.meters > best ? c.meters : best,
      ),
      contested = cells.where((c) => c.contested).length;

  final int cellCount;

  /// Tổng km trong lãnh địa (mét), 30 ngày.
  final int meters;

  /// Km của ô chắc nhất (mét).
  final int strongestMeters;

  /// Số ô bị bám sát.
  final int contested;
}
