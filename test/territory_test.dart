import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show LatLngBounds;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:myrun/src/territory/territory_grid.dart';
import 'package:myrun/src/territory/territory_models.dart';
import 'package:myrun/src/territory/territory_widgets.dart';
import 'package:myrun/src/theme.dart';

void main() {
  // Chợ Bến Thành. Giá trị tính tay theo công thức slippy map của OSM, khớp ca
  // TestCellAt bên backend: x = floor((lng+180)/360·2^z),
  // y = floor((1 − ln(tan φ + sec φ)/π)/2·2^z).
  const benThanh = LatLng(10.772, 106.698);

  group('lưới ô', () {
    test('điểm ra ô z18 và chunk z13', () {
      expect(tileAt(benThanh, territoryCellZoom), const TileXY(208767, 123181));
      expect(tileAt(benThanh, territoryChunkZoom), const TileXY(6523, 3849));
      // 208767 / 32 = 6523,97; 123181 / 32 = 3849,4.
      expect(
        chunkOfCell(const TileXY(208767, 123181)),
        const TileXY(6523, 3849),
      );
    });

    test('ô của tuyến lấy theo điểm giữa, tuyến rỗng thì null', () {
      // Hồ Gươm: x = (105,85+180)/360·2^18 = 208149,6; y tính tay ra 115402,5.
      expect(
        territoryCellOfRoute([benThanh, const LatLng(21.03, 105.85), benThanh]),
        const TileXY(208149, 115402),
      );
      expect(territoryCellOfRoute(const []), isNull);
    });

    test(
      'góc tile theo lon = x/2^z·360−180, lat = atan(sinh(π(1−2y/2^z)))',
      () {
        final nw = tileCorner(208767, 123181, 18);
        expect(nw.longitude, closeTo(106.697845459, 1e-9));
        expect(nw.latitude, closeTo(10.772603102, 1e-9));
        final corners = cellCorners(const TileXY(208767, 123181));
        expect(corners, hasLength(4));
        expect(corners[0], nw);
        expect(corners[2].longitude, closeTo(106.69921875, 1e-9));
        expect(corners[2].latitude, closeTo(10.771254010, 1e-9));
        // Tile z0 phủ cả biên Mercator.
        expect(tileCorner(0, 0, 0).latitude, closeTo(85.0511287798, 1e-9));
        expect(tileCorner(0, 0, 0).longitude, -180);
        expect(tileCorner(1, 1, 0).latitude, closeTo(-85.0511287798, 1e-9));
      },
    );

    test('tâm chunk nằm giữa tile trên lưới Mercator', () {
      final center = chunkCenter(const TileXY(6523, 3849));
      expect(center.longitude, closeTo(106.677246094, 1e-9));
      expect(center.latitude, closeTo(10.768555808, 1e-9));
    });

    test('đọc id "x_y"', () {
      expect(TileXY.parse('6523_3849'), const TileXY(6523, 3849));
      expect(const TileXY(6523, 3849).id, '6523_3849');
      for (final bad in [null, '', '6523', '6523_', 'a_1', '1_2_3', '-1_2']) {
        expect(TileXY.parse(bad), isNull, reason: '$bad');
      }
    });
  });

  group('chunk trong khung nhìn', () {
    LatLngBounds box(double north, double west, double south, double east) =>
        LatLngBounds(LatLng(north, west), LatLng(south, east));

    test('khung trong một chunk', () {
      expect(chunksInView(box(10.78, 106.66, 10.77, 106.67)), [
        const TileXY(6523, 3849),
      ]);
    });

    test('khung vắt qua 2×2 chunk, theo hàng', () {
      // 106.70 đã qua mép 106.69921875 của cột 6524; 10.74 dưới mép
      // 10.74697 của hàng 3850.
      expect(chunksInView(box(10.78, 106.66, 10.74, 106.70)), const [
        TileXY(6523, 3849),
        TileXY(6524, 3849),
        TileXY(6523, 3850),
        TileXY(6524, 3850),
      ]);
    });

    test('4×4 chunk vẫn tải, 5×4 là zoom quá xa', () {
      expect(chunksInView(box(10.78, 106.66, 10.65, 106.80)), hasLength(16));
      expect(chunksInView(box(10.78, 106.66, 10.65, 106.84)), isNull);
    });
  });

  group('owners', () {
    test('cộng byChunk, bỏ mục hỏng', () {
      final owner = TerritoryOwner.fromMap({
        'byChunk': {'6523_3849': 3, '6524_3849': 5, '6525_3849': 0, 'x': 4},
      });
      expect(owner.cellCount, 8);
      expect(owner.topChunk, const TileXY(6524, 3849));
    });

    test('chưa có doc là 0 ô', () {
      expect(TerritoryOwner.fromMap(null).cellCount, 0);
      expect(TerritoryOwner.fromMap(null).topChunk, isNull);
      expect(TerritoryOwner.fromMap({'updatedAt': 1}).cellCount, 0);
    });

    test('bằng ô thì chunk id nhỏ hơn', () {
      final owner = TerritoryOwner.fromMap({
        'byChunk': {'6524_3849': 2, '6523_3849': 2},
      });
      expect(owner.topChunk, const TileXY(6523, 3849));
    });
  });

  test('đọc cells của chunk, bỏ ô sai dạng', () {
    final cells = parseTerritoryCells({
      'cells': {
        '208767_123181': {'u': 'an', 'm': 420, 'm2': 100},
        '208768_123181': {'u': 'binh', 'm': 1200.0},
        'hỏng': {'u': 'an', 'm': 1},
        '208769_123181': {'m': 5},
        '208770_123181': 'x',
      },
    });
    expect(
      [for (final c in cells) (c.tile.id, c.ownerUid, c.meters)],
      [('208767_123181', 'an', 420), ('208768_123181', 'binh', 1200)],
    );
    expect(parseTerritoryCells(null), isEmpty);
  });

  group('kết quả buổi', () {
    test('+N ô = gained + tổng taken, kèm chunk của buổi', () {
      final result = TerritoryResult.fromMap({
        'uid': 'an',
        'activityId': 'a1',
        'gained': 3,
        'taken': {'binh': 2, 'chi': 1},
        'chunk': '6523_3849',
      })!;
      expect(result.total, 6);
      expect(result.taken, {'binh': 2, 'chi': 1});
      expect(result.chunk, const TileXY(6523, 3849));
    });

    test('chưa có doc là null, doc rỗng là 0 ô và không có chunk', () {
      expect(TerritoryResult.fromMap(null), isNull);
      final empty = TerritoryResult.fromMap({
        'uid': 'an',
        'activityId': 'a1',
        'gained': 0,
        'taken': {},
      })!;
      expect(empty.total, 0);
      expect(empty.chunk, isNull);
    });
  });

  test('km chủ ô viết dấu phẩy, một số lẻ', () {
    expect(territoryKm(1234), '1,2 km');
    expect(territoryKm(980), '1,0 km');
    expect(territoryKm(60), '0,1 km');
  });

  test('màu trên bản đồ: của mình màu chính, mọi người khác một màu xanh', () {
    const mine = Color(0xFF00FF00);
    expect(territoryMapColor('an', myUid: 'an', mine: mine), mine);
    expect(
      territoryMapColor('binh', myUid: 'an', mine: mine),
      const Color(0xFF2F6FDB),
    );
    expect(
      territoryMapColor('chi', myUid: 'an', mine: mine),
      const Color(0xFF2F6FDB),
    );
  });

  test('màu người khác đổi sang tím khi màu chính gần xanh', () {
    // Theme Nước #0E96A8 (sắc ~187°) gần xanh #2F6FDB (~219°).
    expect(
      territoryOthersColor(const Color(0xFF0E96A8)),
      RunNowTerritoryTokens.othersAlt,
    );
    // Theme Lửa #E63B1F (sắc ~8°) xa xanh.
    expect(
      territoryOthersColor(const Color(0xFFE63B1F)),
      RunNowTerritoryTokens.others,
    );
  });

  test('màu riêng từng người: cố định theo uid, của mình là màu chính', () {
    const mine = Color(0xFF00FF00);
    expect(territoryOwnerColor('an', myUid: 'an', mine: mine), mine);
    final binh = territoryOwnerColor('binh', myUid: 'an', mine: mine);
    expect(RunNowTerritoryTokens.people, contains(binh));
    expect(territoryOwnerColor('binh', myUid: 'an', mine: mine), binh);
    final colors = {
      for (final uid in ['u1', 'u2', 'u3', 'u4', 'u5', 'u6', 'u7', 'u8'])
        territoryOwnerColor(uid, myUid: 'an', mine: mine),
    };
    expect(colors.length, greaterThan(1));
  });

  test('diện tích một ô theo vĩ độ chunk', () {
    // Tính tay: cạnh = 40 075 016,686 / 2^18 × cos(vĩ độ tâm chunk).
    // Chunk y=3849 (TP.HCM, 10,7686°): 22 554,6 m². y=3700 (17,1198°):
    // 21 345,3 m².
    expect(
      territoryCellAreaM2(const TileXY(6523, 3849)),
      closeTo(22554.6, 0.5),
    );
    expect(
      territoryCellAreaM2(const TileXY(6600, 3700)),
      closeTo(21345.3, 0.5),
    );
  });

  test('diện tích đang giữ cộng theo từng chunk', () {
    final owner = TerritoryOwner.fromMap({
      'byChunk': {'6523_3849': 2, '6600_3700': 1},
    });
    // 2 × 22 554,6 + 21 345,3.
    expect(owner.areaM2, closeTo(66454.6, 1));
  });

  test('viết diện tích: km² từ 1 km², ha dưới đó', () {
    expect(territoryArea(2600000), '2,6 km²');
    expect(territoryArea(1000000), '1,0 km²');
    expect(territoryArea(999999), '1,0 km²');
    expect(territoryArea(99600), '10 ha');
    expect(territoryArea(99400), '9,9 ha');
    expect(territoryArea(609000), '61 ha');
    expect(territoryArea(100000), '10 ha');
    expect(territoryArea(66454.6), '6,6 ha');
    expect(territoryArea(0), '0,0 ha');
  });

  test('số liệu một người: tổng km, ô chắc nhất, ô bị bám sát', () {
    const cells = [
      TerritoryCell(
        tile: TileXY(1, 1),
        ownerUid: 'an',
        meters: 1000,
        secondMeters: 800,
      ),
      TerritoryCell(
        tile: TileXY(1, 2),
        ownerUid: 'an',
        meters: 1000,
        secondMeters: 799,
      ),
      TerritoryCell(tile: TileXY(1, 3), ownerUid: 'an', meters: 2500),
    ];
    final stats = TerritoryStats(cells);
    expect(stats.cellCount, 3);
    expect(stats.meters, 4500);
    expect(stats.strongestMeters, 2500);
    // Ngưỡng 80%: 800/1000 là bám sát, 799 thì chưa, không có người thứ hai
    // thì không.
    expect(stats.contested, 1);
  });

  test('đọc m2 của ô', () {
    final cells = parseTerritoryCells({
      'cells': {
        '1_1': {'u': 'an', 'm': 900, 'm2': 300},
        '1_2': {'u': 'an', 'm': 900},
      },
    });
    expect(
      {for (final c in cells) c.tile.id: c.secondMeters},
      {'1_1': 300, '1_2': 0},
    );
  });

  test('đọc lần bị chiếm từ push: thiếu người chiếm hay số ô thì bỏ', () {
    final taken = parseTerritoryTaken('binh', '2', '1_1,hỏng,2_1')!;
    expect(taken.uid, 'binh');
    expect(taken.count, 2);
    expect(taken.cells, [const TileXY(1, 1), const TileXY(2, 1)]);
    expect(parseTerritoryTaken('binh', null, '1_1'), isNull);
    expect(parseTerritoryTaken('binh', '0', '1_1'), isNull);
    expect(parseTerritoryTaken('', '2', '1_1'), isNull);
    // Link tự gõ: số ô quá một buổi thì bỏ, danh sách ô cắt ở 40.
    expect(parseTerritoryTaken('binh', '5000', '1_1'), isNull);
    final many = List.generate(60, (i) => '${i}_1').join(',');
    expect(parseTerritoryTaken('binh', '60', many)!.cells, hasLength(40));
    expect(parseTerritoryTaken('binh', '2', '1_1', to: 'an')!.to, 'an');
    // Thiếu danh sách ô vẫn có thẻ, chỉ không có viền.
    expect(parseTerritoryTaken('binh', '2', null)!.cells, isEmpty);
  });

  test('route màn Lãnh địa', () {
    expect(territoryLocation(), '/lanh-dia');
    expect(territoryLocation(chunk: '6523_3849'), '/lanh-dia?chunk=6523_3849');
    expect(
      territoryLocation(cell: '208149_115402'),
      '/lanh-dia?cell=208149_115402',
    );
  });
}
