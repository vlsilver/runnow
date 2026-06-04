import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:myrun/src/app.dart';
import 'package:myrun/src/config.dart';
import 'package:myrun/src/strava_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await GoogleSignIn.instance.initialize(
    serverClientId: AppConfig.googleServerClientId,
  );
  // Initialize Strava client (loads tokens from secure storage)
  await StravaClient.instance.initialize();
  runApp(const ProviderScope(child: RunNowApp()));
}
