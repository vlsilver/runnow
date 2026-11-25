import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:myrun/src/territory/territory_grid.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/map_vector.dart';

/// Bản đồ nhỏ các ô lãnh địa (Trang chủ, màn số liệu): nền bản đồ, [polygons],
/// khung vừa các ô [fit]. Ô về sau khi bản đồ đã dựng thì dời camera bằng
/// controller, không dựng lại bản đồ: dựng lại giữa lúc lớp tile vector đang
/// tải làm rơi mất tile, nền bị thủng từng mảng.
class TerritoryMiniMap extends StatefulWidget {
  const TerritoryMiniMap({
    required this.center,
    required this.polygons,
    required this.fit,
    this.interactive = false,
    this.onTap,
    super.key,
  });

  /// Tâm khi chưa có ô để fit.
  final LatLng center;
  final List<Polygon> polygons;

  /// Các ô để khung camera vừa; rỗng thì giữ [center].
  final List<TileXY> fit;

  /// Kéo, phóng to được (không xoay).
  final bool interactive;

  /// Chạm bản đồ, nhận điểm chạm.
  final void Function(LatLng point)? onTap;

  @override
  State<TerritoryMiniMap> createState() => _TerritoryMiniMapState();
}

class _TerritoryMiniMapState extends State<TerritoryMiniMap> {
  final _map = MapController();
  bool _ready = false;

  /// Các ô đã fit lần gần nhất; danh sách đổi (kể cả cùng số ô) thì fit lại.
  List<TileXY> _fitted = const [];

  CameraFit get _cameraFit => CameraFit.coordinates(
    coordinates: [for (final c in widget.fit) ...cellCorners(c)],
    padding: const EdgeInsets.all(20),
    maxZoom: 16,
  );

  @override
  void initState() {
    super.initState();
    _fitted = widget.fit;
  }

  @override
  void didUpdateWidget(TerritoryMiniMap old) {
    super.didUpdateWidget(old);
    if (_ready && widget.fit.isNotEmpty && !listEquals(widget.fit, _fitted)) {
      _fitted = widget.fit;
      _map.fitCamera(_cameraFit);
    }
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.runNowPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final onTap = widget.onTap;
    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: widget.center,
        initialZoom: 14,
        initialCameraFit: widget.fit.isEmpty ? null : _cameraFit,
        backgroundColor: palette.tint,
        onMapReady: () {
          _ready = true;
          // Ô về trước lúc bản đồ sẵn sàng mà chưa fit.
          if (widget.fit.isNotEmpty && !listEquals(widget.fit, _fitted)) {
            _fitted = widget.fit;
            _map.fitCamera(_cameraFit);
          }
        },
        interactionOptions: InteractionOptions(
          flags: widget.interactive
              ? InteractiveFlag.all & ~InteractiveFlag.rotate
              : InteractiveFlag.none,
        ),
        onTap: onTap == null ? null : (_, point) => onTap(point),
      ),
      children: [
        mapBaseLayer(context, dark: dark, around: [widget.center]),
        PolygonLayer(polygons: widget.polygons),
      ],
    );
  }
}
