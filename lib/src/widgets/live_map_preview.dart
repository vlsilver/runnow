import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/live_bits.dart';
import 'package:myrun/src/widgets/map_vector.dart';
import 'package:myrun/src/widgets/route_map.dart' show routeBounds;

/// Bản đồ thật của một phiên live trong ô nhỏ: đường đã chạy và chấm nhấp
/// nháy ở chỗ mới nhất. Không kéo được, chạm vào là chạm ô bên ngoài. Khung
/// ôm cả đường, chừa [padding] cho các lớp phủ của ô, và ôm lại mỗi lần phiên
/// cập nhật. Chưa có điểm GPS nào thì không vẽ gì. Widget không ghi nguồn bản
/// đồ: ô chứa nó phải ghi (bắt buộc theo ODbL), đặt cạnh các lớp phủ của ô để
/// không đè lên nhau.
class LiveMapPreview extends StatefulWidget {
  const LiveMapPreview({
    required this.session,
    required this.padding,
    super.key,
  });

  final LiveTrackingSession session;
  final EdgeInsets padding;

  @override
  State<LiveMapPreview> createState() => _LiveMapPreviewState();
}

class _LiveMapPreviewState extends State<LiveMapPreview> {
  final _map = MapController();
  bool _ready = false;

  @override
  void didUpdateWidget(covariant LiveMapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // So cả id: danh sách đổi thứ tự thì ô dùng lại state này cho người khác,
    // mà hai phiên có thể cùng updatedAt.
    if (oldWidget.session.id != widget.session.id ||
        oldWidget.session.updatedAt != widget.session.updatedAt) {
      _fit();
    }
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _fit() {
    final points = liveRoutePoints(widget.session);
    if (!_ready || points.isEmpty) return;
    if (points.length == 1) {
      _map.move(points.single, 16);
      return;
    }
    _map.fitCamera(
      CameraFit.bounds(
        bounds: routeBounds(points),
        padding: widget.padding,
        maxZoom: 17,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final points = liveRoutePoints(widget.session);
    if (points.isEmpty) return const SizedBox.shrink();
    final palette = context.runNowPalette;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IgnorePointer(
      child: FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: points.last,
          initialZoom: 15,
          backgroundColor: palette.tint,
          onMapReady: () {
            _ready = true;
            _fit();
          },
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.none,
          ),
        ),
        children: [
          mapBaseLayer(context, dark: dark, around: points),
          PolylineLayer(
            polylines: [
              Polyline(
                points: points,
                color: palette.wash(palette.accent, 0.28),
                strokeWidth: 12,
              ),
              Polyline(
                points: points,
                color: palette.accent,
                strokeWidth: 4,
                borderColor: dark ? palette.backgroundDeep : Colors.white,
                borderStrokeWidth: 1.5,
              ),
            ],
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: points.last,
                width: 64,
                height: 64,
                child: PulsingDot(color: palette.accent),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
