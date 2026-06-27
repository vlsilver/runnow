import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:myrun/src/app.dart';
import 'package:myrun/src/config.dart';
import 'package:myrun/src/strava_client.dart';

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
  await Firebase.initializeApp(
    options: kIsWeb ? _webFirebaseOptions : null,
  );
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
  try {
    // Initialize Strava client (loads tokens from secure storage)
    await StravaClient.instance.initialize();
  } catch (error, stack) {
    debugPrint('Strava init failed: $error\n$stack');
  }
  runApp(const ProviderScope(child: RunNowApp()));
}
