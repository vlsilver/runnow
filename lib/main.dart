import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:myrun/src/app.dart';
import 'package:myrun/src/config.dart';
import 'package:myrun/src/legacy_strava_credentials.dart';

/// Firebase web app config (run-now-79767). Mobile dùng google-services.json /
/// GoogleService-Info.plist nên không cần options. apiKey web không phải secret.
const _webFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyBwtxn2yGTxCqbvW1wf4d4Ge0lbAUDnosw',
  appId: '1:267607013114:web:c61da65f65ee7744dc7b43',
  messagingSenderId: '267607013114',
  projectId: 'run-now-79767',
  authDomain: 'run-now-79767.firebaseapp.com',
  storageBucket: 'run-now-79767.firebasestorage.app',
  measurementId: 'G-XK586P6778',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // URL dạng path (threei.run/s/...) thay vì hash (threei.run/#/...). Không có
  // dòng này Flutter web mặc định dùng hash, nên deep-link dạng path bị bỏ qua
  // (go_router đọc fragment rỗng → về '/'), khiến link chia sẻ activity không
  // vào đúng trang. Path strategy cũng khớp WEB_RETURN_URI (.../oauth) sẵn có.
  if (kIsWeb) usePathUrlStrategy();
  await Firebase.initializeApp(options: kIsWeb ? _webFirebaseOptions : null);
  await _initRemoteConfig();
  // Best-effort: trên web các init này có thể chưa cấu hình (web client id),
  // nhưng không nên làm trắng màn cả app — login sẽ báo lỗi khi bấm thay vì crash.
  try {
    await GoogleSignIn.instance.initialize(
      // Web cần clientId (Web OAuth client); mobile dùng config native nên chỉ
      // truyền serverClientId như cũ.
      clientId: kIsWeb ? AppConfig.googleServerClientId : null,
      serverClientId: kIsWeb ? null : AppConfig.googleServerClientId,
    );
  } catch (error, stack) {
    debugPrint('GoogleSignIn init failed: $error\n$stack');
  }
  runApp(const ProviderScope(child: RunNowApp()));
  unawaited(LegacyStravaCredentials.clear());
}

/// Khởi tạo Firebase Remote Config cho tham số GPS tracking (đổi từ console,
/// không cần build lại). ĐIỀU KIỆN theo platform (device.os) xử lý ở server RC
/// nên app chỉ đọc getDouble. setDefaults theo platform để lần đầu / offline vẫn
/// đúng (Android giãn mẫu 15s, iOS 0). fetchAndActivate chạy NỀN — không chặn
/// khởi động app; giá trị server áp khi fetch xong (hoặc realtime onConfigUpdated).
Future<void> _initRemoteConfig() async {
  if (kIsWeb) return; // RC realtime/native chủ yếu cho mobile — web bỏ qua an toàn.
  try {
    final rc = FirebaseRemoteConfig.instance;
    await rc.setConfigSettings(
      RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: const Duration(minutes: 30),
      ),
    );
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    await rc.setDefaults(<String, dynamic>{
      'tracking_min_sample_interval_seconds': isAndroid ? 15 : 0,
      'tracking_max_accuracy_meters': 25,
      'tracking_max_running_speed_mps': 10,
      'tracking_min_segment_distance_meters': 2,
      // Ẩn Strava ở Settings khi app Strava đang Inactive. false = ẩn; bật true
      // trên console khi kết nối lại được (áp realtime, không cần build lại).
      'strava_enabled': false,
    });
    unawaited(rc.fetchAndActivate());
  } catch (error, stack) {
    debugPrint('RemoteConfig init failed: $error\n$stack');
  }
}
