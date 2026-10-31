import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:myrun/src/widgets/glass.dart';
import 'package:myrun/src/widgets/map_tiles.dart';
import 'package:url_launcher/url_launcher.dart';

/// Ghi công nguồn bản đồ — bắt buộc, không phải trang trí.
///
/// Dữ liệu bản đồ là OpenStreetMap, phát hành theo giấy phép ODbL nên **buộc
/// phải** ghi "© OpenStreetMap contributors" ở nơi người dùng thấy được. Nguồn
/// tile khác (CARTO…) thì ghi thêm theo [mapTileCredits].
///
/// Đặt widget này vào `children` của mọi `FlutterMap` trong app.
///
/// [top] = true: neo ở GÓC TRÊN PHẢI (dùng cho map tràn viền lúc chạy, nơi đáy
/// bị panel số liệu che). `RichAttributionWidget` chỉ neo được ở đáy nên bản
/// top là 1 nút ℹ️ nhỏ, chạm mở link nguồn.
class MapAttribution extends StatelessWidget {
  const MapAttribution({this.top = false, super.key});

  final bool top;

  @override
  Widget build(BuildContext context) {
    if (!top) {
      return RichAttributionWidget(
        alignment: AttributionAlignment.bottomRight,
        showFlutterMapAttribution: false,
        attributions: [
          for (final credit in mapTileCredits(currentMapTileTemplate()))
            TextSourceAttribution(credit.label, onTap: () => _open(credit.url)),
        ],
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topRight,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 8, right: 12),
          child: Material(
            color: scheme.surface.withValues(alpha: 0.92),
            elevation: 3,
            shadowColor: Colors.black.withValues(alpha: 0.3),
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _showSources(context),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(
                  Icons.info_outline,
                  size: 18,
                  color: scheme.onSurface.withValues(alpha: 0.75),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showSources(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: GlassPanel(
          borderRadius: 22,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
                child: Text(
                  'NGUỒN BẢN ĐỒ',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
              for (final credit in mapTileCredits(currentMapTileTemplate()))
                ListTile(
                  title: Text('© ${credit.label}'),
                  onTap: () => _open(credit.url),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
