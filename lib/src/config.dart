class AppConfig {
  static const runNowApiBaseUrl = String.fromEnvironment(
    'RUNNOW_API_URL',
    defaultValue: 'https://runnow-api-oq4o7wa4iq-as.a.run.app',
  );

  /// Domain của trang web 3i Run — nơi đặt các trang tĩnh như hỗ trợ và
  /// chính sách bảo mật. App di động mở bằng đường dẫn tuyệt đối này; bản
  /// web thì tự suy ra từ địa chỉ đang chạy nên không dùng tới.
  static const webBaseUrl = 'https://threei.run';

  static const stravaRedirectScheme = 'com.threei.run';
  static const stravaRedirectHost = 'localhost';
  static const stravaRedirectPath = '/oauth';

  static const googleServerClientId =
      '267607013114-qud9nba6kopvqfut8umgtor2cqp846u0.apps.googleusercontent.com';
}
