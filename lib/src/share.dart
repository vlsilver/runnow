import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

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
  final png = await captureRecapPng(boundary);
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
  final png = await captureRecapPng(boundary);
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

Future<ShareResult> shareAgentCard({
  required GlobalKey cardKey,
  required BuildContext shareOriginContext,
  required String botName,
}) => _shareCard(
  cardKey: cardKey,
  shareOriginContext: shareOriginContext,
  text: 'Thẻ MyBot $botName của mình trên 3i',
  fileName: '3i-mybot.png',
);

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

Future<ShareResult> _shareCard({
  required GlobalKey cardKey,
  required BuildContext shareOriginContext,
  required String text,
  required String fileName,
}) async {
  final boundary =
      cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  final renderBox = shareOriginContext.findRenderObject() as RenderBox?;
  final sharePositionOrigin = renderBox == null
      ? null
      : renderBox.localToGlobal(Offset.zero) & renderBox.size;
  final png = await captureRecapPng(boundary);
  return SharePlus.instance.share(
    ShareParams(
      text: text,
      files: [XFile.fromData(png, mimeType: 'image/png')],
      fileNameOverrides: [fileName],
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
