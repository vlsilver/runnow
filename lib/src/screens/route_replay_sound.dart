import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Nhịp bước (bước/phút) của người chạy ở tốc độ [metersPerSecond]. Mốc: pace
/// 6:00/km (2,78 m/s) khoảng 160 bước/phút, 4:00/km (4,17 m/s) khoảng 180.
/// Nhanh mấy cũng không quá 195. Gần như đứng yên thì trả null, tức không có
/// tiếng bước.
double? replayCadence(double metersPerSecond) {
  if (metersPerSecond < 0.5) return null;
  return math.min(160 + 14.4 * (metersPerSecond - 2.78), 195);
}

/// Một bước chân vừa tới giờ phát.
typedef ReplayBeat = ({bool leftFoot});

/// Đếm giờ cho tiếng bước chân theo đồng hồ thật, không theo tiến độ replay:
/// replay tua nhanh cả buổi chạy, còn tiếng thì vẫn là nhịp chân thật ở tốc
/// độ đoạn đang chiếu.
class ReplayStepClock {
  Duration? _next;
  int _steps = 0;

  /// Gọi mỗi khung hình. Tới giờ thì trả bước cần phát, chưa tới thì null.
  ReplayBeat? tick(Duration now, double metersPerSecond) {
    final cadence = replayCadence(metersPerSecond);
    if (cadence == null) {
      _next = null;
      return null;
    }
    final next = _next;
    if (next != null && now < next) return null;
    final gap = Duration(microseconds: (60e6 / cadence).round());
    // Khung hình tới trễ quá một bước thì đếm lại từ bây giờ, không phát dồn.
    _next = next == null || now - next > gap ? now + gap : next + gap;
    return (leftFoot: (_steps++).isEven);
  }

  void reset() {
    _next = null;
    _steps = 0;
  }
}

/// Phát tiếng bước chân của replay.
class ReplaySound {
  static const _stepVolume = 0.8;

  final _clock = ReplayStepClock();
  _Pools? _pools;
  int _played = 0;
  bool _disposed = false;
  bool _failed = false;

  Future<void> load() async {
    // Theo công tắc im lặng của máy và không ngắt nhạc người dùng đang nghe.
    final context = AudioContextConfig(respectSilence: true).build();
    Future<AudioPool> pool(String name) => AudioPool.create(
      source: AssetSource('replay/$name.wav'),
      maxPlayers: 2,
      audioContext: context,
    );
    // Mỗi chân ba tiếng thu khác nhau, phát xoay vòng cho khỏi đều như máy.
    final pools = (
      left: [for (var i = 1; i <= 3; i++) await pool('step_l$i')],
      right: [for (var i = 1; i <= 3; i++) await pool('step_r$i')],
    );
    if (_disposed) {
      await _release(pools);
    } else {
      _pools = pools;
    }
  }

  /// Gọi mỗi khung hình khi replay đang chạy và chưa tắt tiếng.
  void tick(Duration now, double metersPerSecond) {
    final beat = _clock.tick(now, metersPerSecond);
    final pools = _pools;
    if (beat == null || pools == null) return;
    final foot = beat.leftFoot ? pools.left : pools.right;
    _play(foot[(_played++ ~/ 2) % foot.length], _stepVolume);
  }

  void reset() => _clock.reset();

  Future<void> _play(AudioPool pool, double volume) async {
    try {
      await pool.start(volume: volume);
    } catch (error, stack) {
      // Báo một lần; lỗi phát tiếng lặp lại ở mọi bước chân sau đó.
      if (_failed) return;
      _failed = true;
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          context: ErrorDescription('phát tiếng replay'),
        ),
      );
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    final pools = _pools;
    _pools = null;
    if (pools != null) await _release(pools);
  }

  static Future<void> _release(_Pools pools) => Future.wait([
    for (final pool in [...pools.left, ...pools.right]) pool.dispose(),
  ]);
}

typedef _Pools = ({List<AudioPool> left, List<AudioPool> right});
