import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methodChannel = MethodChannel('native_video_player');

  setUp(() {
    messenger.setMockMethodCallHandler(methodChannel, (call) async => null);
    messenger.setMockStreamHandler(
      const EventChannel('native_video_player_controller_91'),
      MockStreamHandler.inline(onListen: (arguments, events) {}),
    );
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  test('PiP skip buttons are shown by default and plumbed into creationParams',
      () async {
    final byDefault = NativeVideoPlayerController(id: 91);
    expect(byDefault.creationParams['showPictureInPictureSkipButtons'], isTrue);
    await byDefault.dispose();

    final hidden = NativeVideoPlayerController(
      id: 91,
      showPictureInPictureSkipButtons: false,
    );
    expect(hidden.creationParams['showPictureInPictureSkipButtons'], isFalse);
    await hidden.dispose();
  });
}
