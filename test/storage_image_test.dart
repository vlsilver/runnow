import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/widgets/storage_image.dart';

void main() {
  testWidgets(
    'an image whose link was fetched earlier shows on the first frame',
    (tester) async {
      StorageImage.debugPutDownloadUrl(
        'artStyles/examples/oil.jpg',
        'https://storage.example.test/oil.jpg',
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: StorageImage(
            path: 'artStyles/examples/oil.jpg',
            placeholder: Text('placeholder'),
          ),
        ),
      );

      expect(find.text('placeholder'), findsNothing);
      // Qua cache đĩa: tắt app mở lại thì ảnh đọc từ máy, không tải lại.
      expect(
        tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage)),
        isA<CachedNetworkImage>().having(
          (w) => w.imageUrl,
          'imageUrl',
          'https://storage.example.test/oil.jpg',
        ),
      );
    },
  );
}
