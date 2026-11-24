import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/models.dart';
import 'package:latlong2/latlong.dart';
import 'package:myrun/src/screens/route_replay_film.dart';
import 'package:myrun/src/screens/route_replay_pins.dart';
import 'package:myrun/src/screens/route_replay_screen.dart';
import 'package:myrun/src/screens/route_replay_sound.dart';
import 'package:myrun/src/share.dart';

void main() {
  // 0,0009° vĩ độ gần xích đạo dài khoảng 99,5 m.
  RoutePoint at(int step, int second) => RoutePoint(
    latitude: 0.0009 * step,
    longitude: 106,
    timestamp: DateTime.utc(2026, 1, 1, 6, 0, second),
  );

  test('speedProfile chia theo quãng đường, đoạn nào chạy nhanh ra số lớn', () {
    // 100 m đầu hết 20 giây (5 m/s), 100 m sau hết 50 giây (2 m/s).
    final speeds = speedProfile(
      [at(0, 0), at(1, 20), at(2, 70)],
      bins: 2,
      smooth: 0,
    )!;
    expect(speeds[0], closeTo(5, 0.05));
    expect(speeds[1], closeTo(2, 0.02));
  });

  test('speedProfile trả null khi các điểm cùng một mốc giờ', () {
    expect(speedProfile([at(0, 0), at(1, 0), at(2, 0)]), isNull);
  });

  test('streamProfile nội suy số đo về các điểm cách đều theo quãng đường', () {
    // 100 bpm ở mét 0, 200 bpm ở mét 1000; hai điểm lấy mẫu nằm ở mét 250 và 750.
    final rates = streamProfile([100, 200], [0, 1000], bins: 2, smooth: 0)!;
    expect(rates, [125, 175]);
  });

  test('streamProfile trả null khi số đo và mốc quãng đường lệch độ dài', () {
    expect(streamProfile([100, 120, 140], [0, 1000]), isNull);
  });

  test('replaySeries có guồng chân, nằm giữa nhịp tim và độ cao', () {
    final series = replaySeries(
      streams: {
        'distance': [0, 1000],
        'heartrate': [100, 200],
        'cadence': [80, 90],
        'altitude': [5, 15],
      },
    );
    expect(
      [for (final one in series) one.label],
      ['NHỊP TIM', 'GUỒNG', 'ĐỘ CAO'],
    );
    // Guồng chân 80 ở mét 0 và 90 ở mét 1000; chưa làm mượt thì điểm lấy mẫu
    // cuối cùng (mét 750) là 87,5, in tròn thành 88.
    final cadence = streamProfile([80, 90], [0, 1000], bins: 2, smooth: 0)!;
    expect(series[1].format(cadence.last), '88 rpm');
  });

  test('replaySeries: điểm có độ cao cách xa nhau vẫn ra biểu đồ độ cao', () {
    // Hai điểm có độ cao gần đối xứng qua tâm Trái Đất, nối bằng một điểm không
    // có độ cao. Đo thẳng giữa hai điểm có độ cao thì Vincenty không hội tụ.
    final series = replaySeries(
      routePoints: [
        RoutePoint(
          latitude: 10,
          longitude: 106,
          timestamp: DateTime.utc(2026, 1, 1, 6),
          altitudeMeters: 10,
        ),
        RoutePoint(
          latitude: 0,
          longitude: 16,
          timestamp: DateTime.utc(2026, 1, 1, 7),
        ),
        RoutePoint(
          latitude: -10,
          longitude: -74,
          timestamp: DateTime.utc(2026, 1, 1, 8),
          altitudeMeters: 20,
        ),
      ],
    );
    final altitude = series.singleWhere((one) => one.label == 'ĐỘ CAO');
    expect(altitude.values.first, closeTo(10, 1));
    expect(altitude.values.last, closeTo(20, 1));
  });

  test('ReplayPath tuyến dài 200 km giữ tối đa khoảng 20 nghìn mẫu', () {
    // 1,8° kinh độ ở xích đạo dài khoảng 200 km: bước 5 m sẽ ra 40 nghìn mẫu.
    final path = ReplayPath([const LatLng(0, 106), const LatLng(0, 107.8)]);
    expect(path.points.length, lessThanOrEqualTo(20002));
    expect(path.meters, closeTo(200375, 1000));
  });

  group('replayPinBeside', () {
    // Ở zoom 0 cả vòng xích đạo (360°) dài 512 điểm ảnh, nên 1 điểm ảnh là
    // 360 / 512 = 0,703125°; zoom 1 thì bằng nửa.
    test('tuyến chạy lên bắc thì ghim lệch sang đông đúng số điểm ảnh', () {
      final at = replayPinBeside(const LatLng(0, 0), 0, pixels: 1, zoom: 0);
      expect(at.longitude, closeTo(0.703125, 0.003));
      expect(at.latitude, closeTo(0, 1e-6));
    });

    test('zoom gần hơn thì cùng số điểm ảnh ứng với quãng ngắn hơn', () {
      final at = replayPinBeside(const LatLng(0, 0), 90, pixels: 2, zoom: 1);
      // Tuyến chạy sang đông thì bên phải là phía nam.
      expect(at.latitude, closeTo(-0.703125, 0.006));
      expect(at.longitude, closeTo(0, 1e-6));
    });
  });

  group('ReplayFeedCursor', () {
    // Buổi 10 km: ảnh ở km 2, cổ vũ ở km 5, 6, 7 và ở 10,4 km (số live nhỉnh
    // hơn số chốt, phải rơi về đích).
    const photo = ReplayMoment.photo(distanceMeters: 2000, photoPath: 'p');
    const km5 = ReplayMoment.cheer(distanceMeters: 5000, emoji: '🔥');
    const km6 = ReplayMoment.cheer(distanceMeters: 6000, emoji: '👏');
    const km7 = ReplayMoment.cheer(distanceMeters: 7000, emoji: '💪');
    const late = ReplayMoment.cheer(distanceMeters: 10400, emoji: '🏁');
    const all = [late, km7, km6, km5, photo];

    test('mỗi khoảnh khắc ra đúng một lần, lúc người chạy vừa tới', () {
      final cursor = ReplayFeedCursor(all, totalMeters: 10000);
      expect(cursor.advance(0.19), isEmpty);
      expect(cursor.advance(0.2), [photo]);
      expect(cursor.advance(0.45), isEmpty);
      expect(cursor.advance(0.7), [km5, km6, km7]);
      expect(cursor.advance(0.99), isEmpty);
      expect(cursor.advance(1), [late]);
    });

    test('phát lại từ đầu thì ra lại từ đầu', () {
      final cursor = ReplayFeedCursor(all, totalMeters: 10000);
      cursor.advance(1);
      expect(cursor.advance(0), isEmpty);
      expect(cursor.advance(0.5), [photo, km5]);
    });

    test('một người bấm dồn cùng emoji quanh một chỗ chỉ ra một lần', () {
      const a1 = ReplayMoment.cheer(
        distanceMeters: 3010,
        emoji: '🔥',
        avatarUrl: 'a',
      );
      const a2 = ReplayMoment.cheer(
        distanceMeters: 3150,
        emoji: '🔥',
        avatarUrl: 'a',
      );
      const b = ReplayMoment.cheer(
        distanceMeters: 3100,
        emoji: '🔥',
        avatarUrl: 'b',
      );
      final cursor = ReplayFeedCursor([a1, a2, b], totalMeters: 10000);
      expect(cursor.advance(1), [a1, b]);
    });
  });

  test('cổ vũ dồn một chỗ thì mỗi đoạn tuyến chỉ giữ cái đầu tiên', () {
    // Buổi 10 km chia 4 đoạn 2,5 km: ba cái dồn ở km 1 chỉ giữ cái đầu, cái
    // ở km 6 và cái ở đích (10,4 km kẹp về đoạn cuối) vẫn còn.
    const a = ReplayMoment.cheer(distanceMeters: 1000, emoji: '🔥');
    const b = ReplayMoment.cheer(distanceMeters: 1010, emoji: '👏');
    const c = ReplayMoment.cheer(distanceMeters: 1020, emoji: '💪');
    const d = ReplayMoment.cheer(distanceMeters: 6000, emoji: '🎉');
    const e = ReplayMoment.cheer(distanceMeters: 10400, emoji: '🏁');
    expect(replayOnePerStretch([a, b, c, d, e], totalMeters: 10000, limit: 4), [
      a,
      d,
      e,
    ]);
  });

  group('replayCheerPeaks', () {
    ReplayMoment cheer(double meters, String emoji) =>
        ReplayMoment.cheer(distanceMeters: meters, emoji: emoji);

    test('lấy đoạn được cổ vũ nhiều nhất, kèm emoji nhiều nhất ở đó', () {
      // Buổi 10 km chia 4 đoạn 2,5 km. Đoạn đầu: 🔥 hai lần, 👏 một lần.
      // Đoạn thứ ba: một lần. Ảnh không tính. Hai đoạn cách nhau một đoạn
      // nên cùng được giữ; giữa đoạn là 1/8 và 5/8.
      final peaks = replayCheerPeaks(
        [
          cheer(1000, '👏'),
          cheer(1100, '🔥'),
          cheer(1200, '🔥'),
          const ReplayMoment.photo(distanceMeters: 4000, photoPath: 'p'),
          cheer(6000, '🎉'),
        ],
        totalMeters: 10000,
        bins: 4,
      );
      expect(peaks, [
        (at: 0.125, emoji: '🔥', count: 3),
        (at: 0.625, emoji: '🎉', count: 1),
      ]);
    });

    test('hai đoạn sát nhau chỉ giữ đoạn nhiều hơn', () {
      // Đoạn 0 có 1 lần, đoạn 1 có 2 lần, đoạn 3 có 1 lần (10,4 km kẹp về
      // đoạn cuối): bỏ đoạn 0 vì sát đoạn 1.
      final peaks = replayCheerPeaks(
        [
          cheer(1000, '👏'),
          cheer(3000, '🔥'),
          cheer(3100, '🔥'),
          cheer(10400, '🏁'),
        ],
        totalMeters: 10000,
        bins: 4,
      );
      expect(peaks, [
        (at: 0.375, emoji: '🔥', count: 2),
        (at: 0.875, emoji: '🏁', count: 1),
      ]);
    });

    test('không quá 3 đỉnh', () {
      // 12 đoạn, mỗi đoạn chẵn một lần: giữ ba đoạn tới trước là 0, 2, 4.
      final peaks = replayCheerPeaks(
        [for (var bin = 0; bin < 12; bin += 2) cheer(bin * 1000 + 500, '🔥')],
        totalMeters: 12000,
        bins: 12,
      );
      expect(
        [for (final peak in peaks) peak.at],
        [0.5 / 12, 2.5 / 12, 4.5 / 12],
      );
    });

    test('không ai cổ vũ thì không có đỉnh', () {
      expect(replayCheerPeaks(const [], totalMeters: 10000), isEmpty);
    });
  });

  group('spreadEvenly', () {
    test('không quá trần thì giữ nguyên', () {
      expect(spreadEvenly([1, 2, 3], 3), [1, 2, 3]);
      expect(spreadEvenly(<int>[], 3), isEmpty);
    });

    test('quá trần thì lấy rải đều, giữ thứ tự', () {
      expect(spreadEvenly([0, 1, 2, 3, 4, 5, 6, 7, 8, 9], 5), [0, 2, 4, 6, 8]);
      expect(spreadEvenly([0, 1, 2, 3, 4, 5, 6], 3), [0, 2, 4]);
    });
  });

  test('camera dừng nhiều nhất 5 chỗ dù có bao nhiêu khoảnh khắc', () {
    // 9 chỗ cách nhau 0,1: giữ chỗ thứ 0, 1, 3, 5, 7 (9·i/5 làm tròn xuống).
    final stops = filmStops([for (var i = 1; i <= 9; i++) i / 10]);
    expect(stops, [0.1, 0.2, 0.4, 0.6, 0.8]);
  });

  test('replay 2,5 giây mỗi km, ngắn nhất 12 giây, dài nhất 20 giây', () {
    expect(replayDuration(1000), const Duration(seconds: 12));
    expect(replayDuration(6000), const Duration(seconds: 15));
    expect(replayDuration(8000), const Duration(seconds: 20));
    expect(replayDuration(42195), const Duration(seconds: 20));
  });

  group('tiếng bước chân', () {
    test('pace 6:00/km ra 160 bước/phút, 4:00/km ra 180, đứng yên thì im', () {
      expect(replayCadence(2.78), closeTo(160, 0.1));
      expect(replayCadence(4.17), closeTo(180, 0.1));
      expect(replayCadence(0.3), isNull);
      // 160 - 14,4 × 1,78 = 134,4.
      expect(replayCadence(1), closeTo(134.4, 0.1));
      expect(replayCadence(10), 195);
    });

    test('160 bước/phút thì 3 giây có 9 bước, đổi chân liên tục', () {
      final clock = ReplayStepClock();
      final beats = <ReplayBeat>[
        // 160 bước/phút là 375 ms một bước: 0, 375, ... 3000 ms.
        for (var ms = 0; ms <= 3000; ms += 5)
          ?clock.tick(Duration(milliseconds: ms), 2.78),
      ];
      expect(
        [for (final beat in beats) beat.leftFoot],
        [
          true, false, true, false, true, false, true, false, true, //
        ],
      );
    });

    test('khung hình đứng 2 giây thì không phát dồn các bước đã lỡ', () {
      final clock = ReplayStepClock();
      expect(clock.tick(Duration.zero, 2.78), isNotNull);
      expect(clock.tick(const Duration(seconds: 2), 2.78), isNotNull);
      expect(clock.tick(const Duration(milliseconds: 2005), 2.78), isNull);
    });

    test('đứng lại thì im, chạy tiếp thì bước ngay', () {
      final clock = ReplayStepClock();
      expect(clock.tick(Duration.zero, 2.78), isNotNull);
      expect(clock.tick(const Duration(milliseconds: 400), 0), isNull);
      expect(clock.tick(const Duration(milliseconds: 405), 2.78), isNotNull);
    });
  });

  test('rẽ vuông góc trên tuyến 5 km thì camera xoay dưới 2° mỗi 5 m', () {
    // 2,5 km về đông rồi 2,5 km lên bắc, gần xích đạo: 0,0225° mỗi cạnh.
    final path = ReplayPath([
      for (var i = 0; i <= 50; i++) LatLng(0, 106 + 0.00045 * i),
      for (var i = 1; i <= 50; i++) LatLng(0.00045 * i, 106.0225),
    ]);
    final bearings = [
      for (var i = 0; i <= 1000; i++) path.at(i / 1000).bearing,
    ];
    expect(bearings.first, closeTo(90, 1));
    expect((bearings.last + 180) % 360 - 180, closeTo(0, 1));
    for (var i = 1; i < bearings.length; i++) {
      final turn = ((bearings[i] - bearings[i - 1] + 540) % 360 - 180).abs();
      expect(turn, lessThan(2), reason: 'điểm $i');
    }
  });

  group('replayKmMarks', () {
    test('mỗi km nguyên một cột mốc, phần lẻ cuối không có', () {
      expect(replayKmMarks(5570), [1, 2, 3, 4, 5]);
    });

    test('chạy tròn km thì km cuối vẫn có cột mốc', () {
      expect(replayKmMarks(5000), [1, 2, 3, 4, 5]);
    });

    test('chưa đủ 1 km thì không có cột mốc nào', () {
      expect(replayKmMarks(999), isEmpty);
      expect(replayKmMarks(0), isEmpty);
    });
  });

  group('replayFitZoom', () {
    test('tuyến chéo 1113 m ở xích đạo dài 190 điểm trên màn ở zoom 13,7', () {
      // 0,01° kinh độ ở xích đạo = 1113,2 m; 78271,517 × 190 / 1113,2 = 13359
      // = 2^13,705.
      final zoom = replayFitZoom(const [
        LatLng(0, 0),
        LatLng(0, 0.01),
      ], span: 190);
      expect(zoom, closeTo(13.7, 0.02));
    });

    test('tuyến dài gấp đôi thì lùi ra đúng một mức zoom', () {
      final near = replayFitZoom(const [
        LatLng(0, 0),
        LatLng(0, 0.01),
      ], span: 190);
      final far = replayFitZoom(const [
        LatLng(0, 0),
        LatLng(0, 0.02),
      ], span: 190);
      expect(near - far, closeTo(1, 0.01));
    });

    test('tuyến rất ngắn hay rất dài thì dừng ở hai đầu kẹp', () {
      expect(
        replayFitZoom(const [LatLng(0, 0), LatLng(0, 0.0001)], span: 190),
        16,
      );
      expect(replayFitZoom(const [LatLng(0, 0), LatLng(0, 1)], span: 190), 11);
      expect(replayFitZoom(const [LatLng(10, 106)], span: 190), 16);
    });
  });

  group('replayClipRect', () {
    test('màn dọc 390×844 thì khung video rộng hết màn, cao 693, nằm giữa', () {
      // 390 × 16 / 9 = 693,33; lề trên (844 - 693,33) / 2 = 75,33.
      final clip = replayClipRect(const Size(390, 844));
      expect(clip.left, 0);
      expect(clip.width, 390);
      expect(clip.top, closeTo(75.33, 0.01));
      expect(clip.height, closeTo(693.33, 0.01));
    });

    test('khổ Feed 4:5 trên màn 390×844 thì khung cao 487,5, nằm giữa', () {
      // 390 × 5 / 4 = 487,5; lề trên (844 - 487,5) / 2 = 178,25.
      final clip = replayClipRect(const Size(390, 844), aspect: 4 / 5);
      expect(clip.left, 0);
      expect(clip.width, 390);
      expect(clip.top, 178.25);
      expect(clip.height, 487.5);
    });

    test(
      'màn ngang hơn 9:16 thì khung video cao hết màn, hẹp lại, nằm giữa',
      () {
        // 1000 × 9 / 16 = 562,5; lề trái (800 - 562,5) / 2 = 118,75.
        final clip = replayClipRect(const Size(800, 1000));
        expect(clip.top, 0);
        expect(clip.height, 1000);
        expect(clip.left, 118.75);
        expect(clip.width, 562.5);
      },
    );
  });

  group('replayClipSafeRect', () {
    test('khổ Story: tem và bảng số né dải tên tài khoản và ô trả lời', () {
      // Khung quay 390×693,33 ứng với 1080×1920, tức 1 px = 0,3611 điểm.
      // Vùng an toàn Story là (64, 250)–(1016, 1670) px:
      // trái 64 × 0,3611 = 23,11; trên 75,33 + 250 × 0,3611 = 165,61;
      // phải 1016 × 0,3611 = 366,89; dưới 75,33 + 1670 × 0,3611 = 678,39.
      final safe = replayClipSafeRect(
        const Rect.fromLTWH(0, 75.33, 390, 693.33),
        ShareFormat.story,
      );
      expect(safe.left, closeTo(23.11, 0.01));
      expect(safe.top, closeTo(165.61, 0.01));
      expect(safe.right, closeTo(366.89, 0.01));
      expect(safe.bottom, closeTo(678.39, 0.01));
    });

    test('khổ Feed: chỉ chừa lề 64 px mỗi cạnh', () {
      // Khung quay 390×487,5 ứng với 1080×1350; 64 px = 23,11 điểm.
      final safe = replayClipSafeRect(
        const Rect.fromLTWH(0, 178.25, 390, 487.5),
        ShareFormat.feed,
      );
      expect(safe.left, closeTo(23.11, 0.01));
      expect(safe.top, closeTo(201.36, 0.01));
      expect(safe.right, closeTo(366.89, 0.01));
      expect(safe.bottom, closeTo(642.64, 0.01));
    });
  });

  test('replayCenter là tâm khung bao của tuyến', () {
    expect(
      replayCenter(const [LatLng(0, 0), LatLng(2, 4), LatLng(1, 1)]),
      const LatLng(1, 2),
    );
  });

  group('ReplayView', () {
    test('gần 2, 3, 5 lần tiến 1, 1,585, 2,322 mức so với mức vừa', () {
      expect(ReplayView.fit.zoom(13), 13);
      expect(ReplayView.near.zoom(13), 14);
      expect(ReplayView.nearer.zoom(13), closeTo(14.585, 0.001));
      expect(ReplayView.nearest.zoom(13), closeTo(15.322, 0.001));
      expect(ReplayView.custom.zoom(13), isNull);
    });

    test(
      'bấm nút đi vòng vừa, gần 2, 3, 5, kiểu phim; đang tự chỉnh thì về vừa',
      () {
        expect(ReplayView.fit.next, ReplayView.near);
        expect(ReplayView.near.next, ReplayView.nearer);
        expect(ReplayView.nearer.next, ReplayView.nearest);
        expect(ReplayView.nearest.next, ReplayView.film);
        expect(ReplayView.film.next, ReplayView.fit);
        expect(ReplayView.custom.next, ReplayView.fit);
      },
    );

    test('chỉ mức vừa thì camera đứng yên, còn lại bám người', () {
      expect(ReplayView.fit.overview, isTrue);
      expect(ReplayView.near.overview, isFalse);
      expect(ReplayView.nearer.overview, isFalse);
      expect(ReplayView.nearest.overview, isFalse);
      expect(ReplayView.custom.overview, isFalse);
    });
  });

  group('khoảnh khắc ở chỗ dừng', () {
    // Ảnh ở 20%, cổ vũ ở 21% (gộp vào chỗ dừng 20%), ảnh ở 50%, cổ vũ sát
    // vạch xuất phát ở 2% (không dừng).
    const fractions = [0.2, 0.21, 0.5, 0.02];

    test('mỗi khoảnh khắc thuộc chỗ dừng đã gộp nó', () {
      final stops = filmStops(fractions);
      expect(stops, [0.2, 0.5]);
      expect(filmStopIndex(0.2, stops), 0);
      expect(filmStopIndex(0.21, stops), 0);
      expect(filmStopIndex(0.5, stops), 1);
    });

    test('khoảnh khắc không được dừng thì không thuộc chỗ nào', () {
      final stops = filmStops(fractions);
      expect(filmStopIndex(0.02, stops), isNull);
      expect(filmStopIndex(0.35, stops), isNull);
    });
  });
}
