import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

/// Hiển thị ảnh lưu trên Firebase Storage qua `getDownloadURL()` +
/// `Image.network` — không dùng `Reference.getData()` vì phương thức đó
/// không được hỗ trợ trên Flutter Web.
class StorageImage extends StatefulWidget {
  const StorageImage({
    required this.path,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.cacheHeight,
    this.placeholder,
    super.key,
  });

  final String path;
  final BoxFit fit;

  /// Giới hạn kích thước giải mã (physical pixels) — truyền vào khi hiển thị
  /// ảnh ở khung nhỏ (vd marker trên bản đồ) để tránh giải mã ảnh gốc full
  /// độ phân giải chỉ để hiện thu nhỏ vài chục px.
  ///
  /// LƯU Ý: chỉ 1 trong 2 chiều được dùng lúc decode (ưu tiên cacheWidth) để
  /// GIỮ ĐÚNG TỈ LỆ. Truyền cả 2 vào Image sẽ ép decode đúng WxH → bóp méo ảnh.
  final int? cacheWidth;
  final int? cacheHeight;

  /// Thay ô xám có vòng quay hay icon ảnh hỏng, lúc đang lấy link hoặc lỗi.
  final Widget? placeholder;

  /// Cho test đặt sẵn link tải của [path] như đã lấy xong trong phiên.
  @visibleForTesting
  static void debugPutDownloadUrl(String path, String url) {
    _StorageImageState._downloadUrlCache[path] = Future.value(url);
    _StorageImageState._resolvedUrls[path] = url;
  }

  @override
  State<StorageImage> createState() => _StorageImageState();
}

class _StorageImageState extends State<StorageImage> {
  static final Map<String, Future<String>> _downloadUrlCache = {};

  /// Link đã lấy xong, đọc được ngay: FutureBuilder luôn dựng một khung chưa
  /// có data dù future đã xong, nên thiếu cái này thì mở lại màn nào cũng
  /// thấy placeholder chớp lên trước khi ảnh hiện.
  static final Map<String, String> _resolvedUrls = {};

  late Future<String> _downloadUrl;

  @override
  void initState() {
    super.initState();
    _downloadUrl = _loadDownloadUrl();
  }

  @override
  void didUpdateWidget(covariant StorageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _downloadUrl = _loadDownloadUrl();
  }

  Future<String> _loadDownloadUrl() async {
    return _downloadUrlCache.putIfAbsent(widget.path, () async {
      try {
        final url = await FirebaseStorage.instance
            .ref(widget.path)
            .getDownloadURL();
        _resolvedUrls[widget.path] = url;
        return url;
      } catch (error) {
        _downloadUrlCache.remove(widget.path);
        rethrow;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _downloadUrl,
      initialData: _resolvedUrls[widget.path],
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null) {
          if (widget.placeholder case final placeholder?) return placeholder;
          return ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Center(
              child: snapshot.hasError
                  ? const Icon(Icons.broken_image_outlined)
                  : const CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return Image.network(
          url,
          fit: widget.fit,
          width: double.infinity,
          height: double.infinity,
          // Chỉ dùng 1 chiều để decode giữ đúng tỉ lệ (không bóp méo).
          cacheWidth: widget.cacheWidth,
          cacheHeight: widget.cacheWidth == null ? widget.cacheHeight : null,
          errorBuilder: (context, error, stack) =>
              widget.placeholder ??
              ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Center(child: Icon(Icons.broken_image_outlined)),
              ),
        );
      },
    );
  }
}
