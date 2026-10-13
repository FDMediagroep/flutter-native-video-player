import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fullscreen change the native player made itself (its own fullscreen
/// button, or Done on iOS) must only be mirrored in Dart: sending
/// enterFullScreen/exitFullScreen back ran the native transition twice, and
/// listeners must hear about it once.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methodChannel = MethodChannel('native_video_player');

  final List<String> methodCalls = <String>[];
  MockStreamHandlerEventSink? viewSink;

  setUp(() {
    methodCalls.clear();
    viewSink = null;
    NativeVideoPlayerController.controllerChannelRetryDelays = const [
      Duration.zero,
      Duration.zero,
      Duration.zero,
    ];
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  testWidgets('a native fullscreen change is mirrored once, not sent back', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());

    await tester.runAsync(() async {
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        methodCalls.add(call.method);
        if (call.method == 'getAvailableQualities') return <Object?>[];
        return null;
      });
      messenger.setMockStreamHandler(
        const EventChannel('native_video_player_controller_81'),
        MockStreamHandler.inline(onListen: (arguments, events) {}),
      );
      messenger.setMockStreamHandler(
        const EventChannel('native_video_player_810'),
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            viewSink = events;
          },
        ),
      );

      final controller = NativeVideoPlayerController(id: 81);
      await controller.debugControllerChannelSetup;
      await controller.onPlatformViewCreated(
        810,
        tester.element(find.byType(SizedBox)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));

      final List<PlayerControlState> fullscreenEvents = <PlayerControlState>[];
      controller.addControlListener((event) {
        if (event.state == PlayerControlState.fullscreenEntered ||
            event.state == PlayerControlState.fullscreenExited) {
          fullscreenEvents.add(event.state);
        }
      });

      viewSink!.success(<String, Object?>{
        'event': 'fullscreenChange',
        'isFullscreen': true,
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.isFullScreen, isTrue);
      expect(fullscreenEvents, [PlayerControlState.fullscreenEntered]);

      viewSink!.success(<String, Object?>{
        'event': 'fullscreenChange',
        'isFullscreen': false,
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(controller.isFullScreen, isFalse);
      expect(fullscreenEvents, [
        PlayerControlState.fullscreenEntered,
        PlayerControlState.fullscreenExited,
      ]);
      expect(methodCalls, isNot(contains('enterFullScreen')));
      expect(methodCalls, isNot(contains('exitFullScreen')));

      await controller.dispose();
    });
  });
}
