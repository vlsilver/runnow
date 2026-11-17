import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:myrun/src/share.dart';
import 'package:myrun/src/theme.dart';
import 'package:myrun/src/widgets/storage_image.dart';

/// Các cột mốc km nguyên của buổi chạy dài [totalMeters]: 1, 2, 3...
List<int> replayKmMarks(double totalMeters) => [
  for (var km = 1; km * 1000 <= totalMeters; km++) km,
];

({double south, double north, double west, double east}) _bounds(
  List<LatLng> route,
) {
  var south = 90.0, north = -90.0, west = 180.0, east = -180.0;
  for (final point in route) {
    south = math.min(south, point.latitude);
    north = math.max(north, point.latitude);
    west = math.min(west, point.longitude);
    east = math.max(east, point.longitude);
  }
  return (south: south, north: north, west: west, east: east);
}

/// Tâm khung bao của [route]: chỗ camera đứng khi nhìn cả tuyến.
LatLng replayCenter(List<LatLng> route) {
  final box = _bounds(route);
  return LatLng((box.south + box.north) / 2, (box.west + box.east) / 2);
}

/// Mức zoom để đường chéo khung bao của [route] dài đúng [span] điểm ảnh
/// logic trên màn hình, tức camera đứng ở [replayCenter] thì thấy cả tuyến.
/// Kẹp trong [min]..[max] để tuyến ngắn không dí sát mặt đất, tuyến dài không
/// vượt mức tile có.
double replayFitZoom(
  List<LatLng> route, {
  required double span,
  double min = 11,
  double max = 16,
}) {
  final box = _bounds(route);
  final diagonal = const Distance(roundResult: false)(
    LatLng(box.south, box.west),
    LatLng(box.north, box.east),
  );
  if (diagonal <= 0) return max;
  // MapLibre: zoom 0 ở xích đạo là 78271,517 m mỗi điểm ảnh logic.
  final metersPerPointAtZoom0 =
      78271.517 * math.cos((box.south + box.north) / 2 * math.pi / 180);
  final zoom = math.log(metersPerPointAtZoom0 * span / diagonal) / math.ln2;
  return zoom.clamp(min, max);
}

/// Vùng màn hình mà video chia sẻ quay: khung tỉ lệ rộng/cao [aspect] (mặc
/// định 9:16, khổ Reels và Story) lớn nhất nằm giữa màn cỡ [screen]. Người
/// chạy đứng giữa màn nên cũng đứng giữa video.
Rect replayClipRect(Size screen, {double aspect = 9 / 16}) {
  final width = math.min(screen.width, screen.height * aspect);
  return Rect.fromCenter(
    center: screen.center(Offset.zero),
    width: width,
    height: width / aspect,
  );
}

/// Phần của khung quay [clip] mà Instagram, Facebook không đè giao diện lên:
/// vùng an toàn của [format] thu theo cỡ khung quay. Tem và bảng số của video
/// nằm trong vùng này.
Rect replayClipSafeRect(Rect clip, ShareFormat format) {
  final scale = clip.width / format.pixels.width;
  final safe = format.safe;
  return Rect.fromLTRB(
    clip.left + safe.left * scale,
    clip.top + safe.top * scale,
    clip.left + safe.right * scale,
    clip.top + safe.bottom * scale,
  );
}

/// Tầm nhìn của replay. Video chia sẻ quay đúng tầm đang chọn.
enum ReplayView {
  /// Kiểu phim: bay vào từ trên cao, bám sau lưng người chạy, lùi ra xoay một
  /// vòng ở cuối.
  film,

  /// Vừa thấy cả tuyến.
  fit,

  /// Lại gần gấp đôi so với [fit].
  near,

  /// Lại gần gấp ba so với [fit].
  nearer,

  /// Lại gần gấp năm so với [fit].
  nearest,

  /// Người xem tự chụm ngón để chỉnh.
  custom;

  /// Camera đứng yên giữa tuyến, người chạy tự đi trên màn hình. Các tầm
  /// còn lại thì camera bám theo người chạy.
  bool get overview => this == fit;

  /// Bấm nút đổi tầm nhìn thì sang mức nào. Đang tự chỉnh thì về [fit].
  ReplayView get next => switch (this) {
    film => fit,
    fit => near,
    near => nearer,
    nearer => nearest,
    nearest => film,
    custom => fit,
  };

  /// Mức zoom của tầm nhìn này khi [fitZoom] là mức vừa cả tuyến; [custom]
  /// không có mức cố định nên trả null.
  double? zoom(double fitZoom) => switch (this) {
    // Bám người chạy ở khoảng giữa gần 2 lần và gần 3 lần.
    film => fitZoom + 3,
    fit => fitZoom,
    near => fitZoom + 1,
    // Mỗi mức zoom là gấp đôi, nên gần gấp ba là tiến log2(3) mức.
    nearer => fitZoom + math.log(3) / math.ln2,
    nearest => fitZoom + math.log(5) / math.ln2,
    custom => null,
  };
}

/// Lề quanh mỗi ghim để chứa bóng đổ. Layer phải đẩy icon xuống đúng chừng
/// này thì chân ghim mới chạm chỗ nó chỉ.
const replayPinPad = 8.0;

const _stem = 10.0;
const _photoSide = 32.0;
const _cheerSide = 46.0;
const _cheerRing = 3.0;

/// Màu của màn replay lấy theo theme đang chọn: tuyến, bảng số, nút và ghim
/// dùng chung bộ này cho cả màn một tông.
class ReplayColors {
  const ReplayColors({
    required this.line,
    required this.onLine,
    required this.night,
    required this.paper,
    required this.muted,
  });

  factory ReplayColors.of(RunNowPalette palette) {
    final iron = palette.style == RunNowStyle.iron;
    final night = palette.accentNight;
    final paper = iron
        ? RunFaceTokens.ironPaper
        : Color.lerp(palette.accent, Colors.white, 0.9)!;
    return ReplayColors(
      line: palette.accent,
      onLine: palette.onAccent,
      night: night,
      paper: paper,
      muted: iron ? RunFaceTokens.ironMuted : Color.lerp(paper, night, 0.4)!,
    );
  }

  /// Tuyến đã chạy, phần biểu đồ đã qua, nút chính.
  final Color line;

  /// Chữ và icon trên nền [line].
  final Color onLine;

  /// Nền tối: bảng số, viền tuyến, bảng cột mốc.
  final Color night;

  /// Chữ và viền sáng trên nền [night].
  final Color paper;

  /// Nhãn phụ trên nền [night].
  final Color muted;
}

final _shadow = Paint()
  ..color = Colors.black.withValues(alpha: 0.45)
  ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

/// Vẽ ghim cỡ [size] (chưa kể lề bóng) thành PNG.
Future<Uint8List> _png(
  Size size,
  double pixelRatio,
  void Function(Canvas canvas) paint,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..scale(pixelRatio)
    ..translate(replayPinPad, replayPinPad);
  paint(canvas);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    ((size.width + replayPinPad * 2) * pixelRatio).ceil(),
    ((size.height + replayPinPad * 2) * pixelRatio).ceil(),
  );
  picture.dispose();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// Cột mốc [km] cắm trên tuyến: bảng số trên một cọc, chân cọc là đúng chỗ.
Future<Uint8List> kmPinPng(int km, double pixelRatio, ReplayColors colors) {
  final label = TextPainter(
    text: TextSpan(
      text: '$km',
      style: TextStyle(
        color: colors.paper,
        fontSize: 13,
        fontWeight: FontWeight.w900,
        height: 1,
      ),
      children: const [
        TextSpan(
          text: ' km',
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
        ),
      ],
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final plate = Size(label.width + 12, label.height + 10);
  return _png(Size(plate.width, plate.height + _stem), pixelRatio, (canvas) {
    final coal = Paint()..color = colors.night;
    canvas
      ..drawRect(Offset.zero & plate, Paint()..color = colors.paper)
      ..drawRect((Offset.zero & plate).deflate(1.5), coal)
      ..drawRect(
        Rect.fromLTWH(plate.width / 2 - 1.5, plate.height, 3, _stem),
        coal,
      );
    label.paint(canvas, const Offset(6, 5));
    label.dispose();
  });
}

/// Ảnh chụp dọc đường thành ô ảnh nhỏ không viền trên một cọc như cột mốc
/// km, chân cọc là đúng chỗ chụp.
Future<Uint8List> photoPinPng(
  ui.Image photo,
  double pixelRatio,
  ReplayColors colors,
) {
  const size = Size(_photoSide, _photoSide + _stem);
  return _png(size, pixelRatio, (canvas) {
    const frame = Rect.fromLTWH(0, 0, _photoSide, _photoSide);
    canvas.drawRect(
      const Rect.fromLTWH(_photoSide / 2 - 1.5, _photoSide, 3, _stem),
      Paint()..color = colors.night,
    );
    // Cắt giữa ảnh thành ô vuông.
    final side = math.min(photo.width, photo.height).toDouble();
    canvas.drawImageRect(
      photo,
      Rect.fromCenter(
        center: Offset(photo.width / 2, photo.height / 2),
        width: side,
        height: side,
      ),
      frame,
      Paint()..filterQuality = FilterQuality.medium,
    );
  });
}

/// Người cổ vũ cắm tại chỗ họ bấm: avatar tròn viền đỏ trên cọc, emoji to ở
/// góc. Không có [avatar] thì vẽ hình người.
Future<Uint8List> cheerPinPng(
  ui.Image? avatar,
  String emoji,
  double pixelRatio,
  ReplayColors colors,
) {
  final badge = TextPainter(
    text: TextSpan(text: emoji, style: const TextStyle(fontSize: 24)),
    textDirection: TextDirection.ltr,
  )..layout();
  // Emoji lấn ra ngoài vòng avatar về bên phải.
  const overhang = 14.0;
  const size = Size(_cheerSide + overhang, _cheerSide + _stem);
  return _png(size, pixelRatio, (canvas) {
    const center = Offset(_cheerSide / 2, _cheerSide / 2);
    final red = Paint()..color = colors.line;
    canvas
      ..drawCircle(center + const Offset(0, 2), _cheerSide / 2, _shadow)
      ..drawRect(
        Rect.fromLTWH(_cheerSide / 2 - 1.5, _cheerSide - 2, 3, _stem + 2),
        red,
      )
      ..drawCircle(center, _cheerSide / 2, red);
    final face = Rect.fromCircle(
      center: center,
      radius: _cheerSide / 2 - _cheerRing,
    );
    canvas
      ..save()
      ..clipPath(Path()..addOval(face));
    if (avatar == null) {
      canvas.drawRect(face, Paint()..color = colors.night);
      final icon = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(Icons.person_rounded.codePoint),
          style: TextStyle(
            fontFamily: Icons.person_rounded.fontFamily,
            fontSize: 28,
            color: colors.paper,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      icon.paint(canvas, center - Offset(icon.width / 2, icon.height / 2));
      icon.dispose();
    } else {
      final side = math.min(avatar.width, avatar.height).toDouble();
      canvas.drawImageRect(
        avatar,
        Rect.fromCenter(
          center: Offset(avatar.width / 2, avatar.height / 2),
          width: side,
          height: side,
        ),
        face,
        Paint()..filterQuality = FilterQuality.medium,
      );
    }
    canvas.restore();
    badge.paint(
      canvas,
      Offset(size.width - badge.width, _cheerSide - badge.height + 4),
    );
    badge.dispose();
  });
}

/// Tải ảnh ở [url] về, giải mã nhỏ còn [side] điểm ảnh logic.
Future<ui.Image> loadReplayImage(String url, double side, double pixelRatio) {
  final loaded = Completer<ui.Image>();
  final stream = ResizeImage(
    CachedNetworkImageProvider(url),
    width: (side * pixelRatio).ceil(),
  ).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      stream.removeListener(listener);
      if (!loaded.isCompleted) loaded.complete(info.image);
    },
    onError: (error, stack) {
      stream.removeListener(listener);
      if (!loaded.isCompleted) loaded.completeError(error, stack);
    },
  );
  stream.addListener(listener);
  return loaded.future;
}

/// Ảnh chụp dọc đường ở [storagePath], nhỏ vừa đủ cho ô ảnh trên map.
Future<ui.Image> loadReplayPhoto(String storagePath, double pixelRatio) async {
  final url = await StorageImage.downloadUrl(storagePath);
  return loadReplayImage(url, _photoSide, pixelRatio);
}

/// Avatar người cổ vũ ở [url], nhỏ vừa đủ cho ghim trên map.
Future<ui.Image> loadReplayAvatar(String url, double pixelRatio) =>
    loadReplayImage(url, _cheerSide, pixelRatio);
