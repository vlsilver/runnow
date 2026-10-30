import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/widgets/rank_road.dart';

void main() {
  group('roadLanes', () {
    test('cách nhau đủ xa thì cùng nằm làn dưới', () {
      expect(roadLanes([0, 40, 80], minGap: 36, maxLanes: 3), [0, 0, 0]);
    });

    test('sát nhau thì lên làn trên, làn dưới trống lại thì về làn dưới', () {
      // 10 và 20 còn quá gần 0 nên lên làn 1, làn 2; 100 đã xa 0 đủ 36.
      expect(roadLanes([0, 10, 20, 100], minGap: 36, maxLanes: 3), [
        0,
        1,
        2,
        0,
      ]);
    });

    test('hết làn thì vào làn có người trước nằm xa nhất về bên trái', () {
      // Làn 0, 1, 2 đang có 0, 10, 20; 30 không vừa làn nào, làn 0 đè ít nhất.
      // Rồi 35: làn 1 (10) giờ xa nhất về bên trái.
      expect(roadLanes([0, 10, 20, 30, 35], minGap: 36, maxLanes: 3), [
        0,
        1,
        2,
        0,
        1,
      ]);
    });

    test('rỗng thì rỗng', () {
      expect(roadLanes([], minGap: 36, maxLanes: 3), isEmpty);
    });
  });
}
