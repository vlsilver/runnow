import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/models.dart';
import 'package:latlong2/latlong.dart';
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

  group('replayMomentsAt', () {
    // Buổi 10 km: ảnh ở km 2, cổ vũ ở km 5 và ở 10,4 km (số live nhỉnh hơn
    // số chốt, phải rơi về đích).
    const photo = ReplayMoment.photo(distanceMeters: 2000, photoPath: 'p');
    const mid = ReplayMoment.cheer(distanceMeters: 5000, emoji: '🔥');
    const late = ReplayMoment.cheer(distanceMeters: 10400, emoji: '🏁');
    const all = [late, mid, photo];

    List<ReplayMoment> at(double progress) =>
        replayMomentsAt(all, progress, totalMeters: 10000, linger: 0.1);

    test('chưa tới chỗ thì chưa hiện, tới rồi thì hiện, đi quá thì tắt', () {
      expect(at(0.19), isEmpty);
      expect(at(0.2), [photo]);
      expect(at(0.29), [photo]);
      expect(at(0.31), isEmpty);
      expect(at(0.5), [mid]);
    });

    test('quãng đường vượt số chốt thì hiện ở đích', () {
      expect(late.fraction(10000), 1.0);
      expect(at(0.99), isEmpty);
      expect(at(1), [late]);
    });

    test('nhiều thứ cùng lúc xếp theo thứ tự dọc đường', () {
      const near = ReplayMoment.cheer(distanceMeters: 2300, emoji: '👏');
      expect(
        replayMomentsAt([near, photo], 0.25, totalMeters: 10000, linger: 0.1),
        [photo, near],
      );
    });
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

    test('bấm nút đi vòng vừa, gần 2, 3, 5; đang tự chỉnh thì về vừa', () {
      expect(ReplayView.fit.next, ReplayView.near);
      expect(ReplayView.near.next, ReplayView.nearer);
      expect(ReplayView.nearer.next, ReplayView.nearest);
      expect(ReplayView.nearest.next, ReplayView.fit);
      expect(ReplayView.custom.next, ReplayView.fit);
    });

    test('chỉ mức vừa thì camera đứng yên, còn lại bám người', () {
      expect(ReplayView.fit.overview, isTrue);
      expect(ReplayView.near.overview, isFalse);
      expect(ReplayView.nearer.overview, isFalse);
      expect(ReplayView.nearest.overview, isFalse);
      expect(ReplayView.custom.overview, isFalse);
    });
  });
}
