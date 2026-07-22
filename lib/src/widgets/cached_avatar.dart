import 'package:flutter/widgets.dart';

/// Wraps [url] in a [ResizeImage] sized near [diameter] logical pixels at the
/// device pixel ratio. Only width is constrained so the image keeps its
/// original aspect ratio; the circular widget can then crop with cover instead
/// of receiving a pre-squashed bitmap.
ImageProvider cachedAvatarImage(
  BuildContext context,
  String url,
  double diameter,
) {
  final pixelSize = (diameter * MediaQuery.of(context).devicePixelRatio)
      .round()
      .clamp(1, 1 << 20);
  return ResizeImage(NetworkImage(url), width: pixelSize);
}
