import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:myrun/src/theme.dart';
import 'package:share_plus/share_plus.dart';

/// Khổ ảnh, video đem chia sẻ, khớp chỗ đăng trên Instagram và Facebook.
enum ShareFormat {
  /// Story, Reels: 9:16.
  story('Story', '9:16', Size(1080, 1920)),

  /// Bài đăng trên feed: 4:5, khổ dọc cao nhất feed còn hiện đủ.
  feed('Feed', '4:5', Size(1080, 1350));

  const ShareFormat(this.label, this.ratio, this.pixels);

  final String label;
  final String ratio;

  /// Cỡ file ảnh.
  final Size pixels;

  double get aspect => pixels.width / pixels.height;

  /// Vùng đặt nội dung. Story chừa trên dưới 250 px vì app đè tên tài khoản
  /// và ô trả lời lên đó.
  Rect get safe => switch (this) {
    story => const Rect.fromLTRB(64, 250, 1016, 1670),
    feed => const Rect.fromLTRB(64, 64, 1016, 1286),
  };
}

/// Chỗ [content] nằm trong khung [format]: thu phóng vừa vùng an toàn, giữ
/// tỉ lệ. Còn dư ít nhất [stampBand] px chiều dọc thì nội dung dịch lên, nhường
/// dải dưới cho tem 3I RUN; không thì nằm giữa và không có tem.
///
/// [bleed] là viền trống quanh [content] (px của content, mỗi cạnh) cùng màu
/// nền khung: phần đó được tràn ra ngoài vùng an toàn, để hình bên trong mới
/// là thứ lấp vùng an toàn.
({Rect content, Rect? stamp}) shareFrameLayout(
  Size content,
  ShareFormat format, {
  double stampBand = 150,
  double bleed = 0,
}) {
  final safe = format.safe;
  final inner = Size(content.width - bleed * 2, content.height - bleed * 2);
  final scale = math.min(safe.width / inner.width, safe.height / inner.height);
  final size = inner * scale;
  final free = safe.height - size.height;
  if (free < stampBand) {
    return (
      content: Rect.fromCenter(
        center: safe.center,
        width: size.width,
        height: size.height,
      ).inflate(bleed * scale),
      stamp: null,
    );
  }
  final top = safe.top + (free - stampBand) / 2;
  final placed = Rect.fromLTWH(
    safe.center.dx - size.width / 2,
    top,
    size.width,
    size.height,
  );
  return (
    content: placed.inflate(bleed * scale),
    stamp: Rect.fromLTWH(safe.left, placed.bottom, safe.width, stampBand),
  );
}

/// Đặt [content] lên nền [background] trong khung [format] rồi xuất PNG. Có
/// [stamp] và còn chỗ thì in tem 3I RUN theo bảng màu đó dưới nội dung.
/// [bleed] như ở [shareFrameLayout].
Future<Uint8List> frameShareImage(
  ui.Image content,
  ShareFormat format, {
  required Color background,
  RunNowPalette? stamp,
  double bleed = 0,
}) async {
  final layout = shareFrameLayout(
    Size(content.width.toDouble(), content.height.toDouble()),
    format,
    stampBand: stamp == null ? double.infinity : 150,
    bleed: bleed,
  );
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)
    ..drawRect(Offset.zero & format.pixels, Paint()..color = background)
    ..drawImageRect(
      content,
      Offset.zero & Size(content.width.toDouble(), content.height.toDouble()),
      layout.content,
      Paint()..filterQuality = FilterQuality.high,
    );
  if (layout.stamp case final band?) _paintStamp(canvas, band.center, stamp!);
  final picture = recorder.endRecording();
  final image = await picture.toImage(
    format.pixels.width.round(),
    format.pixels.height.round(),
  );
  picture.dispose();
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Không thể tạo ảnh chia sẻ.');
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// Tem 3I RUN nghiêng, nền màu nhấn, bóng cứng; cùng dáng với tem trên video
/// replay.
void _paintStamp(Canvas canvas, Offset center, RunNowPalette palette) {
  final label = TextPainter(
    text: TextSpan(
      text: '3I RUN',
      style: palette.heading(
        TextStyle(
          color: palette.onAccent,
          fontSize: 56,
          fontWeight: FontWeight.w900,
          letterSpacing: 3,
          height: 1,
        ),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final plate = Rect.fromCenter(
    center: Offset.zero,
    width: label.width + 56,
    height: label.height + 32,
  );
  canvas
    ..save()
    ..translate(center.dx, center.dy)
    ..rotate(-0.07)
    ..drawRect(
      plate.shift(const Offset(10, 10)),
      Paint()..color = palette.accentNight,
    )
    ..drawRect(plate, Paint()..color = palette.accent);
  label.paint(canvas, Offset(-label.width / 2, -label.height / 2));
  canvas.restore();
  label.dispose();
}

/// Giữ khổ chia sẻ máy này chọn trong Cài đặt. Chưa chọn thì là Story.
class ShareFormatController extends ChangeNotifier {
  ShareFormatController({
    FlutterSecureStorage? storage,
    bool loadFromStorage = true,
  }) : _storage = storage ?? const FlutterSecureStorage() {
    if (loadFromStorage) _load();
  }

  static const _key = 'runnow_share_format';

  final FlutterSecureStorage _storage;

  ShareFormat _format = ShareFormat.story;

  /// Người dùng đã chọn trong phiên này thì giá trị đọc muộn từ máy không
  /// được đè lên.
  bool _chosen = false;

  ShareFormat get format => _format;

  Future<void> setFormat(ShareFormat format) async {
    _chosen = true;
    if (_format == format) return;
    _format = format;
    notifyListeners();
    await _storage.write(key: _key, value: format.name);
  }

  Future<void> _load() async {
    final loaded = ShareFormat.values
        .asNameMap()[await _storage.read(key: _key)];
    if (_chosen || loaded == null || loaded == _format) return;
    _format = loaded;
    notifyListeners();
  }
}

/// Khổ chia sẻ của máy này.
final shareFormatControllerProvider =
    ChangeNotifierProvider<ShareFormatController>(
      (ref) => ShareFormatController(),
    );

/// Khổ chia sẻ đang chọn, cho những hàm share chỉ có [context].
ShareFormat shareFormatOf(BuildContext context) => ProviderScope.containerOf(
  context,
  listen: false,
).read(shareFormatControllerProvider).format;

/// Mở bảng chọn khổ chia sẻ từ Cài đặt.
Future<void> showShareFormatSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Consumer(
            builder: (context, ref, _) {
              final controller = ref.watch(shareFormatControllerProvider);
              return Row(
                spacing: 12,
                children: [
                  for (final format in ShareFormat.values)
                    Expanded(
                      child: ShareFormatTile(
                        format: format,
                        selected: format == controller.format,
                        onTap: () {
                          controller.setFormat(format);
                          Navigator.of(sheet).pop();
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );

/// Ô chọn một khổ chia sẻ: hình khung đúng tỉ lệ, tên và tỉ lệ.
class ShareFormatTile extends StatelessWidget {
  const ShareFormatTile({
    super.key,
    required this.format,
    required this.onTap,
    this.selected = false,
  });

  final ShareFormat format;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.runNowPalette;
    final ink = selected ? palette.accent : theme.colorScheme.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        key: ValueKey('share-format-${format.name}'),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? palette.accent : theme.dividerColor,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              SizedBox(
                height: 44,
                child: AspectRatio(
                  aspectRatio: format.aspect,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: ink, width: 2),
                    ),
                  ),
                ),
              ),
              Text(
                format.label,
                style: theme.textTheme.titleMedium?.copyWith(color: ink),
              ),
              Text(format.ratio, style: theme.textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// Chụp [boundary] và đặt vào khung khổ chia sẻ đang chọn trên nền theme, kèm
/// tem 3I RUN.
Future<Uint8List> captureShareFrame(
  BuildContext context,
  RenderRepaintBoundary? boundary, {
  Color? background,
}) async {
  final palette = context.runNowPalette;
  final format = shareFormatOf(context);
  if (boundary == null) throw StateError('Recap card chưa sẵn sàng.');
  final image = await boundary.toImage(pixelRatio: 3);
  try {
    return await frameShareImage(
      image,
      format,
      background: background ?? palette.background,
      stamp: palette,
    );
  } finally {
    image.dispose();
  }
}

Future<ShareResult> shareDashboardCard({
  required GlobalKey cardKey,
  required BuildContext shareOriginContext,
  required String title,
}) async {
  final boundary =
      cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  final renderBox = shareOriginContext.findRenderObject() as RenderBox?;
  final sharePositionOrigin = renderBox == null
      ? null
      : renderBox.localToGlobal(Offset.zero) & renderBox.size;
  final png = await captureShareFrame(shareOriginContext, boundary);
  return SharePlus.instance.share(
    ShareParams(
      text: '$title\nChia sẻ từ 3i',
      files: [XFile.fromData(png, mimeType: 'image/png')],
      fileNameOverrides: ['3i-${_shareFileName(title)}.png'],
      sharePositionOrigin: sharePositionOrigin,
    ),
  );
}

Future<ShareResult> shareJourneyCompletion({
  required GlobalKey cardKey,
  required BuildContext shareOriginContext,
  required String campaignName,
  required String routeName,
}) async {
  final boundary =
      cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  final renderBox = shareOriginContext.findRenderObject() as RenderBox?;
  final sharePositionOrigin = renderBox == null
      ? null
      : renderBox.localToGlobal(Offset.zero) & renderBox.size;
  final png = await captureShareFrame(shareOriginContext, boundary);
  return SharePlus.instance.share(
    ShareParams(
      text:
          'Tôi vừa hoàn thành $campaignName ($routeName) trên 3i — cộng dồn '
          'từng buổi chạy thật, không hệ số!',
      files: [XFile.fromData(png, mimeType: 'image/png')],
      fileNameOverrides: ['3i-${_shareFileName(campaignName)}.png'],
      sharePositionOrigin: sharePositionOrigin,
    ),
  );
}

/// Gửi một file khoe thẻ đã tạo sẵn (ảnh mặt trước, mặt sau hay lá xoay 3D).
Future<ShareResult> shareCardFile({
  required Uint8List bytes,
  required String mimeType,
  required String fileName,
  required BuildContext shareOriginContext,
  required String text,
}) {
  final renderBox = shareOriginContext.findRenderObject() as RenderBox?;
  final sharePositionOrigin = renderBox == null
      ? null
      : renderBox.localToGlobal(Offset.zero) & renderBox.size;
  return SharePlus.instance.share(
    ShareParams(
      text: text,
      files: [XFile.fromData(bytes, mimeType: mimeType)],
      fileNameOverrides: [fileName],
      sharePositionOrigin: sharePositionOrigin,
    ),
  );
}

/// Mở sheet xem trước [card] rồi mới khoe: ảnh chụp đúng cái đang thấy, và
/// avatar trong thẻ có thời gian tải xong. Ảnh gửi đi kèm [caption].
Future<void> showShareCardSheet(
  BuildContext context, {
  required Widget card,
  required String caption,
  required String fileName,
  required String label,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _ShareCardSheet(
    card: card,
    caption: caption,
    fileName: fileName,
    label: label,
  ),
);

class _ShareCardSheet extends StatefulWidget {
  const _ShareCardSheet({
    required this.card,
    required this.caption,
    required this.fileName,
    required this.label,
  });

  final Widget card;
  final String caption;
  final String fileName;
  final String label;

  @override
  State<_ShareCardSheet> createState() => _ShareCardSheetState();
}

class _ShareCardSheetState extends State<_ShareCardSheet> {
  final _cardKey = GlobalKey();
  var _sending = false;

  Future<void> _send(BuildContext buttonContext) async {
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final png = await captureShareFrame(
        buttonContext,
        _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?,
      );
      if (!buttonContext.mounted) return;
      await shareCardFile(
        bytes: png,
        mimeType: 'image/png',
        fileName: widget.fileName,
        shareOriginContext: buttonContext,
        text: widget.caption,
      );
      navigator.pop();
    } catch (error) {
      debugPrint('${widget.label} lỗi: $error');
      if (!mounted) return;
      setState(() => _sending = false);
      messenger.showSnackBar(
        SnackBar(content: Text('Không thể chia sẻ: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Bỏ phóng chữ để ảnh giống nhau trên mọi máy.
            SizedBox(
              height: 400,
              child: FittedBox(
                child: RepaintBoundary(
                  key: _cardKey,
                  child: MediaQuery.withNoTextScaling(child: widget.card),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Builder(
              builder: (buttonContext) => FilledButton.icon(
                onPressed: _sending ? null : () => _send(buttonContext),
                icon: const Icon(Icons.ios_share_rounded),
                label: Text(widget.label),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ảnh bot vẽ: gửi đúng file PNG gốc trên Storage, không chụp lại màn xem
/// (màn xem có viền đen và đang phóng to tuỳ tay người xem).
Future<ShareResult> shareAgentImage({
  required Uint8List png,
  required BuildContext shareOriginContext,
}) {
  final renderBox = shareOriginContext.findRenderObject() as RenderBox?;
  final sharePositionOrigin = renderBox == null
      ? null
      : renderBox.localToGlobal(Offset.zero) & renderBox.size;
  return SharePlus.instance.share(
    ShareParams(
      text: 'MyBot vẽ cho mình trên 3i',
      files: [XFile.fromData(png, mimeType: 'image/png')],
      fileNameOverrides: ['3i-mybot-anh.png'],
      sharePositionOrigin: sharePositionOrigin,
    ),
  );
}

Future<Uint8List> captureRecapPng(RenderRepaintBoundary? boundary) async {
  if (boundary == null) {
    throw StateError('Recap card chưa sẵn sàng.');
  }
  final image = await boundary.toImage(pixelRatio: 3);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) {
    throw StateError('Không thể tạo ảnh recap.');
  }
  return data.buffer.asUint8List();
}

String _shareFileName(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}
