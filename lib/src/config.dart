class AppConfig {
  static const runNowApiBaseUrl = String.fromEnvironment(
    'RUNNOW_API_URL',
    defaultValue: 'https://runnow-api-oq4o7wa4iq-as.a.run.app',
  );

  static const stravaRedirectScheme = 'com.threei.run';
  static const stravaRedirectHost = 'localhost';
  static const stravaRedirectPath = '/oauth';

  static const googleServerClientId =
      '267607013114-qud9nba6kopvqfut8umgtor2cqp846u0.apps.googleusercontent.com';
}
