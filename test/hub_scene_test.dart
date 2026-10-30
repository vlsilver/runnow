import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/widgets/hub_scene.dart';

void main() {
  test('trời của buổi chạy đổi theo giờ bắt đầu', () {
    HubScene at(int hour, int minute) =>
        HubScene.forRunAt(DateTime(2026, 10, 31, hour, minute));

    expect(at(4, 59), HubScene.night);
    expect(at(5, 0), HubScene.dawn);
    expect(at(8, 59), HubScene.dawn);
    expect(at(9, 0), HubScene.day);
    expect(at(15, 59), HubScene.day);
    expect(at(16, 0), HubScene.dusk);
    expect(at(18, 59), HubScene.dusk);
    expect(at(19, 0), HubScene.night);
    expect(at(0, 0), HubScene.night);
  });
}
