# better_native_video_player example

`lib/main.dart` is the showcase: one file with every feature of the
plugin, in four tabs (Watch, Live, Feed, Binge).

```sh
flutter run
```

`lib/dev_main.dart` is the test harness the plugin is developed against:
perf screens, stress feeds, PiP and AirPlay repro screens, with
[Marionette](https://github.com/leancodepl/marionette_mcp) for driving it.

```sh
flutter run -t lib/dev_main.dart
```

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
`flutter build apk --debug --target lib/dev_main.dart` before using its demo screens.
