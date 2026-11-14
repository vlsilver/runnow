import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:myrun/src/achievements/run_faces/run_face_kit.dart';
import 'package:myrun/src/widgets/map_tiles.dart';
import 'package:myrun/src/widgets/route_map.dart' show routeBounds;
import '../../theme_tokens.dart';

/// Ghi công in thẳng lên thẻ vì ảnh khoe không bấm được.
String mapCreditLine() =>
    '© ${mapTileCredits(currentMapTileTemplate()).map((c) => c.label).join(' · ')}';

/// Bản đồ đứng yên, khung vừa đường chạy.
class StillRouteMap extends StatelessWidget {
  const StillRouteMap({
    super.key,
    required this.points,
    required this.dark,
    required this.background,
    required this.route,
    this.stroke = 3,
    this.padding = const EdgeInsets.all(20),
    this.maxZoom = 16,
    this.markers = const [],
    this.tileFilter,
  });

  final List<LatLng> points;
  final bool dark;
  final Color background;

  /// Null thì không vẽ đường, để mặt thẻ tự vẽ theo nét riêng.
  final Color? route;
  final double stroke;

  /// Khoảng chừa quanh đường chạy; chữ đè lên phần nào của bản đồ thì chừa
  /// phần đó.
  final EdgeInsets padding;
  final double maxZoom;
  final List<Marker> markers;

  /// Chỉ lọc tile, đường chạy giữ nguyên màu.
  final ColorFilter? tileFilter;

  @override
  Widget build(BuildContext context) {
    final tiles = mapTileLayer(context, dark: dark);
    final filter = tileFilter;
    final route = this.route;
    return IgnorePointer(
      child: FlutterMap(
        options: MapOptions(
          initialCameraFit: CameraFit.bounds(
            bounds: routeBounds(points),
            padding: padding,
            maxZoom: maxZoom,
          ),
          backgroundColor: background,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.none,
          ),
        ),
        children: [
          if (filter == null)
            tiles
          else
            ColorFiltered(colorFilter: filter, child: tiles),
          if (route != null)
            PolylineLayer(
              polylines: [
                Polyline(points: points, color: route, strokeWidth: stroke),
              ],
            ),
          if (markers.isNotEmpty) MarkerLayer(markers: markers),
        ],
      ),
    );
  }
}

/// Lọc tile về đơn sắc kiểu in nhiệt.
const faceMapMono = ColorFilter.matrix([
  0.30, 0.59, 0.11, 0, 12, //
  0.30, 0.59, 0.11, 0, 12,
  0.30, 0.59, 0.11, 0, 12,
  0, 0, 0, 1, 0,
]);

/// Biến tile thành lớp mực mờ để tờ giấy của mặt thẻ vẫn lộ ra. Tile tối thì
/// phần sáng ăn mực, tile sáng thì phần tối ăn mực. Alpha tính từ alpha gốc
/// nên chỗ tile chưa tải vẫn trong suốt.
ColorFilter faceMapWash(
  Color ink, {
  required bool dark,
  required double strength,
}) {
  final s = dark ? strength : -strength;
  return ColorFilter.matrix([
    0, 0, 0, 0, ink.r * 255, //
    0, 0, 0, 0, ink.g * 255,
    0, 0, 0, 0, ink.b * 255,
    0.30 * s, 0.59 * s, 0.11 * s, dark ? 0 : strength, 0,
  ]);
}

/// Bản đồ thật trên mặt sau: cỡ theo chỗ cha cho, luôn kèm dòng ghi công.
class FaceMap extends StatelessWidget {
  const FaceMap(
    this.f, {
    super.key,
    required this.dark,
    required this.route,
    this.stroke = 3,
    this.padding = const EdgeInsets.all(18),
    this.maxZoom = 16,
    this.radius = 0,
    this.circle = false,
    this.tileFilter,
    this.creditAt = Alignment.bottomRight,
    this.creditPadding = const EdgeInsets.fromLTRB(5, 3, 5, 3),
    this.overlay,
    this.showCredit = true,
  });

  final RunFace f;
  final bool dark;

  /// Null là nền mờ dưới nét vẽ riêng của mặt thẻ: không đường, không chấm
  /// xuất phát, không nền đặc.
  final Color? route;
  final double stroke;
  final EdgeInsets padding;

  /// Nền mờ phải khớp nét vẽ của mặt thẻ, nên buổi ngắn cũng được zoom sát.
  final double maxZoom;
  final double radius;
  final bool circle;
  final ColorFilter? tileFilter;
  final Alignment creditAt;

  /// Khung tròn thì chừa ngang cho chữ nằm trong dây cung.
  final EdgeInsets creditPadding;

  /// Nét vẽ riêng của mặt thẻ, nằm trên bản đồ và dưới ghi công để không che
  /// mất dòng ghi công.
  final Widget? overlay;

  /// Tắt chỉ khi mặt thẻ đã có bản đồ khác in dòng ghi công.
  final bool showCredit;

  @override
  Widget build(BuildContext context) {
    final points = f.route;
    final route = this.route;
    final land = dark ? RunFaceTokens.mapLandDark : RunFaceTokens.mapLandLight;
    final map = Stack(
      fit: StackFit.expand,
      children: [
        StillRouteMap(
          points: points,
          dark: dark,
          background: route == null ? Colors.transparent : land,
          route: route,
          stroke: stroke,
          padding: padding,
          maxZoom: maxZoom,
          tileFilter: tileFilter,
          markers: [
            if (route != null)
              Marker(
                point: points.first,
                width: 9,
                height: 9,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: RunFaceTokens.white,
                    border: Border.all(color: route, width: 2),
                  ),
                ),
              ),
          ],
        ),
        ?overlay,
        if (showCredit)
          Padding(
            padding: creditPadding,
            child: Align(
              alignment: creditAt,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                // Nền mờ giữ ghi công đọc được khi đè lên tên địa danh của tile.
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: land.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      mapCreditLine(),
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w500,
                        color: dark
                            ? RunFaceTokens.paper76
                            : RunFaceTokens.mapCreditOnLight,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    return circle
        ? ClipOval(child: map)
        : ClipRRect(borderRadius: BorderRadius.circular(radius), child: map);
  }
}
