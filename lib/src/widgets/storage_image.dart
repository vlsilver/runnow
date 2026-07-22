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
    super.key,
  });

  final String path;
  final BoxFit fit;

  /// Giới hạn kích thước giải mã (physical pixels) — truyền vào khi hiển thị
  /// ảnh ở khung nhỏ (vd marker trên bản đồ) để tránh giải mã ảnh gốc full
  /// độ phân giải chỉ để hiện thu nhỏ vài chục px.
  final int? cacheWidth;
  final int? cacheHeight;

  @override
  State<StorageImage> createState() => _StorageImageState();
}

class _StorageImageState extends State<StorageImage> {
  static final Map<String, Future<String>> _downloadUrlCache = {};

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
        return await FirebaseStorage.instance.ref(widget.path).getDownloadURL();
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
      builder: (context, snapshot) {
        final url = snapshot.data;
        if (url == null) {
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
          cacheWidth: widget.cacheWidth,
          cacheHeight: widget.cacheHeight,
          errorBuilder: (context, error, stack) => ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Center(child: Icon(Icons.broken_image_outlined)),
          ),
        );
      },
    );
  }
}
