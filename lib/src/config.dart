class AppConfig {
  // Demo-only credentials. Keeping the Strava app secret in a mobile build is
  // acceptable only while this app is used locally by its developer. Move the
  // OAuth exchange and token refresh to a backend before distributing the app.
  static const stravaClientId = '253789';
  static const stravaClientSecret = 'fc1c5c4b4e68c421038476c62fd7485f979cd76a';
  static const stravaRedirectScheme = 'com.runnow.3aeidiot';
  // Strava explicitly whitelists localhost callback hosts. Keep the custom
  // scheme so iOS returns to RunNow after the browser authorization flow.
  static const stravaRedirectHost = 'localhost';
  static const stravaRedirectPath = '/oauth';
  static const stravaRedirectUri =
      '$stravaRedirectScheme://$stravaRedirectHost$stravaRedirectPath';
  static const stravaScope = 'activity:read_all';

  static const googleServerClientId =
      '267607013114-qud9nba6kopvqfut8umgtor2cqp846u0.apps.googleusercontent.com';
}
