import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/widgets/map_vector.dart';

void main() {
  test('dấu folder cache khớp test vector FNV-1a 32 bit', () {
    // Giá trị chuẩn của FNV-1a 32 bit (isthe.com/chongo/tech/comp/fnv).
    expect(fnv1a32(''), '811c9dc5');
    expect(fnv1a32('a'), 'e40c292c');
    expect(fnv1a32('foobar'), 'bf9cf968');
  });
}
