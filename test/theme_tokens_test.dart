import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('element palette hex values live only in theme_tokens.dart', () {
    const elementalHexValues = <String>{
      '0d1115',
      '090c10',
      '050709',
      '171c21',
      '11151a',
      '0a1522',
      '07101a',
      '040912',
      '101d2a',
      '0b151f',
      '0b1610',
      '07100b',
      '040905',
      '111e16',
      '0b150f',
      '180d0d',
      '100809',
      '090405',
      '211414',
      '160d0e',
      '17140c',
      '0f0d08',
      '080704',
      '201c12',
      '15120c',
      '8fa3b7',
      '465563',
      '8f7645',
      'b3a071',
      '2f8dff',
      '244e77',
      '8798a8',
      'aeb8c2',
      '429867',
      '24583a',
      '4d779f',
      '718eaa',
      'c96157',
      '6b302c',
      '4f8762',
      '78a184',
      'ad8844',
      '5f4b26',
      '9d554d',
      'b8786f',
    };
    final dartFiles = Directory('lib/src')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'));

    for (final file in dartFiles) {
      if (file.path.endsWith('theme_tokens.dart')) continue;
      final source = file.readAsStringSync().toLowerCase();
      for (final hex in elementalHexValues) {
        expect(
          source.contains(hex),
          isFalse,
          reason: 'Move elemental color $hex from ${file.path} to tokens.',
        );
      }
    }
  });

  test('ThemeData builder contains no raw hex colors', () {
    final source = File('lib/src/theme.dart').readAsStringSync();
    expect(source, isNot(contains(RegExp(r'Color\(0x[0-9a-fA-F]+\)'))));
  });

  test('runtime UI contains no raw hex colors or legacy AppColors', () {
    final dartFiles = Directory('lib/src')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) => !file.path.endsWith('theme_tokens.dart'));

    for (final file in dartFiles) {
      final source = file.readAsStringSync();
      expect(
        source,
        isNot(contains(RegExp(r'Color\(0x[0-9a-fA-F]+\)'))),
        reason: 'Move raw colors from ${file.path} to theme_tokens.dart.',
      );
      expect(
        source,
        isNot(contains('AppColors.')),
        reason: 'Use RunNowPalette or semantic/data tokens in ${file.path}.',
      );
    }
  });

  test('power radar uses one theme accent instead of per-metric colors', () {
    final radar = File(
      'lib/src/widgets/power_radar_card.dart',
    ).readAsStringSync();
    final personalPower = File(
      'lib/src/widgets/personal_power_card.dart',
    ).readAsStringSync();
    final trainingPower = File(
      'lib/src/training_power.dart',
    ).readAsStringSync();

    expect(radar, isNot(contains('metric.color')));
    expect(radar, isNot(contains('SweepGradient')));
    expect(personalPower, isNot(contains('RunNowDataColors')));
    expect(trainingPower, isNot(contains('RunNowDataColors')));
  });

  test('discipline owns the embedded consistency section', () {
    final discipline = File(
      'lib/src/widgets/discipline_card.dart',
    ).readAsStringSync();
    final dashboard = File(
      'lib/src/screens/dashboard_screen.dart',
    ).readAsStringSync();
    final member = File(
      'lib/src/screens/member_profile_screen.dart',
    ).readAsStringSync();

    expect(discipline, contains('embedded: true'));
    expect(dashboard, isNot(contains('ConsistencyHeatmap(')));
    expect(member, isNot(contains('ConsistencyHeatmap(')));
  });

  test('journal activity cards use the themed surface and one accent', () {
    final activityTile = File(
      'lib/src/widgets/activity_tile.dart',
    ).readAsStringSync();

    expect(activityTile, contains('palette.glassStart'));
    expect(activityTile, contains('palette.glassEnd'));
    expect(activityTile, isNot(contains('RunNowDataColors')));
  });

  test('global backdrop contains no fog or image blur layer', () {
    final backdrop = File('lib/src/widgets/glass.dart').readAsStringSync();

    expect(backdrop, isNot(contains('ImageFiltered')));
    expect(backdrop, isNot(contains('BackdropFilter')));
    expect(backdrop, isNot(contains('ImageFilter.blur')));
  });
}
