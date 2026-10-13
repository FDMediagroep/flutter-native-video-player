import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The activity state `load()` leaves behind.
///
/// With autoplay, native reports `play` before `load()` resolves. Android
/// sends no further play event while it keeps playing, so `load()` must not
/// overwrite that `playing` with `loaded`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methodChannel = MethodChannel('native_video_player');

  MockStreamHandlerEventSink? viewSink;

  /// Events native pushes on the view channel while handling `load`.
  List<String> eventsDuringLoad = <String>[];

  setUp(() {
    viewSink = null;
    eventsDuringLoad = <String>[];
    NativeVideoPlayerController.controllerChannelRetryDelays = const [
      Duration.zero,
      Duration.zero,
      Duration.zero,
    ];
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  Future<NativeVideoPlayerController> pumpControllerWithView(
    WidgetTester tester, {
    required int controllerId,
    required int viewId,
  }) async {
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      if (call.method == 'load') {
        for (final String event in eventsDuringLoad) {
          viewSink!.success(<String, Object?>{'event': event});
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      if (call.method == 'getAvailableQualities') return <Object?>[];
      return null;
    });
    messenger.setMockStreamHandler(
      EventChannel('native_video_player_controller_$controllerId'),
      MockStreamHandler.inline(onListen: (arguments, events) {}),
    );
    messenger.setMockStreamHandler(
      EventChannel('native_video_player_$viewId'),
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          viewSink = events;
        },
      ),
    );

    final controller = NativeVideoPlayerController(id: controllerId);
    await controller.debugControllerChannelSetup;
    await controller.onPlatformViewCreated(
      viewId,
      tester.element(find.byType(SizedBox)),
    );
    await controller.initialize();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(viewSink, isNotNull);
    return controller;
  }

  testWidgets('autoplay that reports play during load stays playing', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());

    await tester.runAsync(() async {
      final controller = await pumpControllerWithView(
        tester,
        controllerId: 71,
        viewId: 710,
      );
      eventsDuringLoad = <String>['loaded', 'play'];

      await controller.load(url: 'https://example.com/video.m3u8');

      expect(controller.activityState, PlayerActivityState.playing);
      await controller.dispose();
    });
  });

  testWidgets('load without a play event ends in loaded', (tester) async {
    await tester.pumpWidget(const SizedBox());

    await tester.runAsync(() async {
      final controller = await pumpControllerWithView(
        tester,
        controllerId: 72,
        viewId: 720,
      );
      eventsDuringLoad = <String>['loaded'];

      await controller.load(url: 'https://example.com/video.m3u8');

      expect(controller.activityState, PlayerActivityState.loaded);
      await controller.dispose();
    });
  });

  testWidgets('play from the previous video does not survive a new load', (
    tester,
  ) async {
    await tester.pumpWidget(const SizedBox());

    await tester.runAsync(() async {
      final controller = await pumpControllerWithView(
        tester,
        controllerId: 73,
        viewId: 730,
      );
      viewSink!.success(<String, Object?>{'event': 'play'});
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.activityState, PlayerActivityState.playing);

      await controller.load(url: 'https://example.com/next.m3u8');

      expect(controller.activityState, PlayerActivityState.loaded);
      await controller.dispose();
    });
  });
}
