import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:myrun/src/models.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/live_bits.dart';
import 'package:myrun/src/widgets/map_tiles.dart';
import 'package:myrun/src/widgets/route_map.dart' show routeBounds;

/// Bản đồ thật của một phiên live trong ô nhỏ: đường đã chạy và chấm nhấp
/// nháy ở chỗ mới nhất. Không kéo được, chạm vào là chạm ô bên ngoài. Khung
/// ôm cả đường, chừa [padding] cho các lớp phủ của ô, và ôm lại mỗi lần phiên
/// cập nhật. Chưa có điểm GPS nào thì không vẽ gì.
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
    if (oldWidget.session.updatedAt != widget.session.updatedAt) _fit();
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
    final credit = mapTileCredits(
      currentMapTileTemplate(),
    ).map((c) => c.label).join(' · ');
    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
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
                mapTileLayer(context, dark: dark),
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: points,
                      color: palette.accent.withValues(alpha: 0.28),
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
          ),
        ),
        // Ghi nguồn bản đồ là bắt buộc (ODbL); đặt ngay trên lớp phủ ở đáy.
        Positioned(
          right: 16,
          bottom: widget.padding.bottom - 10,
          child: Text(
            '© $credit',
            style: TextStyle(
              fontSize: 8,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      ],
    );
  }
}
