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
      final image = tester.widget<Image>(find.byType(Image));
      expect(
        image.image,
        isA<NetworkImage>().having(
          (p) => p.url,
          'url',
          'https://storage.example.test/oil.jpg',
        ),
      );
    },
  );
}
