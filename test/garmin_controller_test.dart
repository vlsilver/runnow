import 'package:flutter_test/flutter_test.dart';
import 'package:myrun/src/garmin_controller.dart';
import 'package:myrun/src/runnow_api_client.dart';

void main() {
  test(
    'backend redirects to the shared OAuth deep link with garmin result',
    () {
      expect(
        isGarminCallback(
          Uri.parse('com.threei.run://localhost/oauth?garmin=connected'),
        ),
        isTrue,
      );
      expect(
        isGarminCallback(
          Uri.parse(
            'com.threei.run://localhost/oauth?garminError=garmin_token_failed',
          ),
        ),
        isTrue,
      );
      // Kết quả của Strava đi cùng deep link nhưng không phải việc của Garmin.
      expect(
        isGarminCallback(
          Uri.parse('com.threei.run://localhost/oauth?strava=connected'),
        ),
        isFalse,
      );
      expect(
        isGarminCallback(
          Uri.parse('com.threei.run://localhost/oauth?error=access_denied'),
        ),
        isFalse,
      );
      expect(
        isGarminCallback(
          Uri.parse('https://evil.example/oauth?garmin=connected'),
        ),
        isFalse,
      );
    },
  );

  test('web callback must come back to the page that opened it', () {
    final base = Uri.parse('https://threei.run/app');
    expect(
      isGarminCallback(
        Uri.parse('https://threei.run/oauth?garmin=connected'),
        webBase: base,
      ),
      isTrue,
    );
    expect(
      isGarminCallback(
        Uri.parse('https://other.example/oauth?garmin=connected'),
        webBase: base,
      ),
      isFalse,
    );
  });

  test('user cancelling on Garmin is not shown as an error', () {
    expect(garminErrorMessage('garmin_authorization_denied'), isNull);
    expect(
      garminErrorMessage('garmin_user_already_linked'),
      contains('tài khoản 3i khác'),
    );
    expect(garminErrorMessage('garmin_token_failed'), isNotNull);
  });

  test('status reads last push time from backend JSON', () {
    final status = GarminConnectionStatus.fromJson({
      'available': true,
      'connected': true,
      'status': 'active',
      'lastPushAt': '2026-10-21T06:30:00Z',
    });
    expect(status.connected, isTrue);
    expect(status.lastPushAt, DateTime.utc(2026, 10, 21, 6, 30));
    final empty = GarminConnectionStatus.fromJson({});
    expect(empty.connected, isFalse);
    expect(empty.available, isFalse);
    expect(empty.status, 'disconnected');
  });
}
