pro# native_video_player_example

Demonstrates how to use the native_video_player plugin.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Android engine regression tests

Start an Android emulator, then run from `example`:

```sh
flutter pub get
flutter build apk --debug --target lib/engine_test.dart
cd android
./gradlew :better_native_video_player:testDebugUnitTest :app:connectedDebugAndroidTest -Ptarget=lib/engine_test.dart
```

On Windows, use `gradlew.bat`. The instrumentation tests start two real Flutter
engines with separate Dart isolates, reuse controller and texture view IDs, and
check event routing and playback after engine detach. Audio is generated locally;
Firebase and network media are not required. Build the normal example again with
`flutter build apk --debug --target lib/main.dart` before using its demo screens.
