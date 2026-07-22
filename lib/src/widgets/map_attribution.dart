import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';

/// Ghi công nguồn bản đồ — bắt buộc, không phải trang trí.
///
/// App dùng tile của CARTO dựng trên dữ liệu OpenStreetMap. OSM phát hành
/// theo giấy phép ODbL nên **buộc phải** ghi "© OpenStreetMap contributors"
/// ở nơi người dùng thấy được, và CARTO cũng yêu cầu ghi công tương tự.
///
/// Đặt widget này vào `children` của mọi `FlutterMap` trong app.
class MapAttribution extends StatelessWidget {
  const MapAttribution({super.key});

  @override
  Widget build(BuildContext context) {
    return RichAttributionWidget(
      alignment: AttributionAlignment.bottomRight,
      showFlutterMapAttribution: false,
      attributions: [
        TextSourceAttribution(
          'OpenStreetMap contributors',
          onTap: () => _open('https://www.openstreetmap.org/copyright'),
        ),
        TextSourceAttribution(
          'CARTO',
          onTap: () => _open('https://carto.com/attributions'),
        ),
      ],
    );
  }

  static Future<void> _open(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
