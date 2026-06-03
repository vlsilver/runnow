# RunNow

RunNow is an iOS-first Flutter journal for Strava runs and walks. The repository
uses Firebase Authentication and Firestore for direct Strava sync with a local
Firestore cache. Activity detail can export a PNG recap through the native share
sheet or publish metrics to an in-app feed. Feed publishing is explicit and
keeps route location data private. Sample data exists only as a test fixture.

## Prerequisites

- Flutter stable and full Xcode installation
- A Firebase project with anonymous Authentication and Firestore enabled
- A Strava API application

After installing Xcode, activate it and install CocoaPods:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
brew install cocoapods
```

## Native Platforms

The repository includes standard iOS and Android platform folders. iOS is the
first configured target. Android remains available for the next platform phase;
its valid generated application ID is `com.u3ae.myrun` because Android package
segments cannot start with a digit.

Use `scripts/bootstrap_flutter.sh` only when regenerating missing platform
folders.

## Configure Firebase

Create a Firebase project, open Authentication, click **Get started**, enable the
Anonymous sign-in provider, and create Firestore before configuring the iOS app.
This demo connects to Strava directly from the Flutter app. The
hardcoded Strava secret in `lib/src/config.dart` must be moved to a dedicated
backend service before distributing the app.

Deploy the Firestore rules before running against Firebase:

```sh
cp .firebaserc.example .firebaserc
# Replace the placeholder project ID in .firebaserc.
firebase login
firebase deploy --only firestore
```

The iOS URL scheme `com.runnow.3aeidiot` is already registered. The Strava
development callback is `com.runnow.3aeidiot://localhost/oauth`; Strava
whitelists the `localhost` callback host. Install the ignored Firebase plist
with:

```sh
scripts/configure_ios_secrets.sh /path/to/GoogleService-Info.plist
```

Keep downloaded Firebase plist files outside source control. The local workspace
installs the Firebase plist from `.secret/`.

Activity routes use MapLibre with OpenFreeMap vector tiles and visible
OpenStreetMap attribution. This map stack does not require an API key or billing
account.

Check the machine before iOS acceptance testing:

```sh
scripts/check_ios_readiness.sh
```

Run the app. Firebase is always enabled; no Dart define or wrapper script is
required:

```sh
flutter run -d "iPhone 17 Pro"
```

## Verification

```sh
flutter test
flutter analyze
```

OAuth tokens stay in the platform secure store. Synced activities and feed posts
are normalized in the app and cached in Firestore. The app reads Firestore's
local cache when offline.
