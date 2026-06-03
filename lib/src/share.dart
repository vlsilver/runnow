import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:myrun/src/formatters.dart';
import 'package:myrun/src/models.dart';
import 'package:share_plus/share_plus.dart';

String buildShareCaption(ActivitySummary activity) {
  return [
    activity.name,
    '${formatDistance(activity.distanceMeters)} • ${formatDuration(activity.movingTimeSeconds)} • ${formatPace(activity.paceSecondsPerKm)}',
    'Chia sẻ từ RunNow',
  ].join('\n');
}

Future<ShareResult> shareActivityRecap({
  required GlobalKey recapKey,
  required BuildContext shareButtonContext,
  required ActivitySummary activity,
}) async {
  final boundary =
      recapKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  final renderBox = shareButtonContext.findRenderObject() as RenderBox?;
  final sharePositionOrigin = renderBox == null
      ? null
      : renderBox.localToGlobal(Offset.zero) & renderBox.size;
  final png = await captureRecapPng(boundary);
  return SharePlus.instance.share(
    ShareParams(
      text: buildShareCaption(activity),
      files: [XFile.fromData(png, mimeType: 'image/png')],
      fileNameOverrides: ['runnow-${activity.id}.png'],
      sharePositionOrigin: sharePositionOrigin,
    ),
  );
}

Future<ShareResult> shareDashboardCard({
  required GlobalKey cardKey,
  required BuildContext shareButtonContext,
  required String title,
}) async {
  final boundary =
      cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  final renderBox = shareButtonContext.findRenderObject() as RenderBox?;
  final sharePositionOrigin = renderBox == null
      ? null
      : renderBox.localToGlobal(Offset.zero) & renderBox.size;
  final png = await captureRecapPng(boundary);
  return SharePlus.instance.share(
    ShareParams(
      text: '$title\nChia sẻ từ RunNow',
      files: [XFile.fromData(png, mimeType: 'image/png')],
      fileNameOverrides: ['runnow-${_shareFileName(title)}.png'],
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
