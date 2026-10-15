import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// AirPlay actions (picker, disconnect) are routed to the view of the channel
/// they are sent through. A controller that outlives its views (kept alive by
/// PiP, AirPlay or the app) must not be that channel: its calls end in
/// "no view" and the AirPlay button does nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methodChannel = MethodChannel('native_video_player');

  setUp(() {
    NativeVideoPlayerController.controllerChannelRetryDelays = const [
      Duration.zero,
      Duration.zero,
      Duration.zero,
    ];
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      if (call.method == 'getAvailableQualities') return <Object?>[];
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  void mockEventChannels(List<String> names) {
    for (final String name in names) {
      messenger.setMockStreamHandler(
        EventChannel(name),
        MockStreamHandler.inline(onListen: (arguments, events) {}),
      );
    }
  }

  testWidgets('a controller whose views are gone no longer serves AirPlay '
      'actions', (tester) async {
    await tester.pumpWidget(const SizedBox());

    await tester.runAsync(() async {
      mockEventChannels(<String>[
        'native_video_player_controller_91',
        'native_video_player_controller_92',
        'native_video_player_910',
        'native_video_player_911',
        'native_video_player_920',
      ]);
      final BuildContext context = tester.element(find.byType(SizedBox));

      final lessonA = NativeVideoPlayerController(id: 91);
      await lessonA.debugControllerChannelSetup;
      await lessonA.onPlatformViewCreated(910, context);

      final lessonB = NativeVideoPlayerController(id: 92);
      await lessonB.debugControllerChannelSetup;
      await lessonB.onPlatformViewCreated(920, context);

      // Back to lesson A: B's controller outlives its view, A gets a new one.
      lessonA.onPlatformViewDisposed(910);
      lessonB.onPlatformViewDisposed(920);
      await lessonA.onPlatformViewCreated(911, context);

      expect(
        AirPlayStateManager.instance.debugActionChannel?.primaryPlatformViewId,
        911,
      );

      await lessonA.dispose();
      await lessonB.dispose();
    });
  });

  testWidgets('a controller serves AirPlay actions again once a view '
      'attaches', (tester) async {
    await tester.pumpWidget(const SizedBox());

    await tester.runAsync(() async {
      mockEventChannels(<String>[
        'native_video_player_controller_93',
        'native_video_player_930',
        'native_video_player_931',
      ]);
      final BuildContext context = tester.element(find.byType(SizedBox));

      final controller = NativeVideoPlayerController(id: 93);
      await controller.debugControllerChannelSetup;
      await controller.onPlatformViewCreated(930, context);
      controller.onPlatformViewDisposed(930);

      expect(AirPlayStateManager.instance.debugActionChannel, isNull);

      await controller.onPlatformViewCreated(931, context);

      expect(
        AirPlayStateManager.instance.debugActionChannel?.primaryPlatformViewId,
        931,
      );

      await controller.dispose();
    });
  });
}
