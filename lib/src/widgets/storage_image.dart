import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Hiển thị ảnh lưu trên Firebase Storage qua `getDownloadURL()` +
/// `Image.network` — không dùng `Reference.getData()` vì phương thức đó
/// không được hỗ trợ trên Flutter Web.
class StorageImage extends StatefulWidget {
  const StorageImage({required this.path, this.fit = BoxFit.cover, super.key});

  final String path;
  final BoxFit fit;

  @override
  State<StorageImage> createState() => _StorageImageState();
}

class _StorageImageState extends State<StorageImage> {
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
    _debugLog('Đang lấy download URL cho path=${widget.path}...');
    try {
      final url = await FirebaseStorage.instance
          .ref(widget.path)
          .getDownloadURL();
      _debugLog('getDownloadURL thành công cho ${widget.path}: $url');
      return url;
    } catch (error, stack) {
      _debugLog('getDownloadURL LỖI cho ${widget.path}: $error\n$stack');
      rethrow;
    }
  }

  void _debugLog(String message) {
    if (kDebugMode) debugPrint('[StorageImage] $message');
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
          errorBuilder: (context, error, stack) {
            _debugLog(
              'Image.network LỖI khi tải url cho ${widget.path}: $error',
            );
            return ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Center(child: Icon(Icons.broken_image_outlined)),
            );
          },
        );
      },
    );
  }
}
