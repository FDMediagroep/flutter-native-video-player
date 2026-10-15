import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// iOS: a PiP request right after leaving Dart fullscreen must reach the
/// inline view. Until the fullscreen route's fade-out ends, its platform view
/// is still the primary view, and PiP started there ends when that view is
/// disposed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methodChannel = MethodChannel('native_video_player');

  const int inlineViewId = 820, fullscreenViewId = 821;
  final List<MethodCall> pipCalls = <MethodCall>[];

  setUp(() {
    pipCalls.clear();
    NativeVideoPlayerController.controllerChannelRetryDelays = const [
      Duration.zero,
      Duration.zero,
      Duration.zero,
    ];
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  Future<NativeVideoPlayerController> attachInlineAndFullscreenViews(
    WidgetTester tester,
  ) async {
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      if (call.method == 'enterPictureInPicture') pipCalls.add(call);
      if (call.method == 'getAvailableQualities') return <Object?>[];
      return null;
    });
    for (final String name in <String>[
      'native_video_player_controller_82',
      'native_video_player_$inlineViewId',
      'native_video_player_$fullscreenViewId',
    ]) {
      messenger.setMockStreamHandler(
        EventChannel(name),
        MockStreamHandler.inline(onListen: (arguments, events) {}),
      );
    }

    final controller = NativeVideoPlayerController(id: 82);
    await controller.debugControllerChannelSetup;
    final BuildContext context = tester.element(find.byType(SizedBox));
    await controller.onPlatformViewCreated(inlineViewId, context);
    controller.registerFullscreenView(fullscreenViewId);
    await controller.onPlatformViewCreated(fullscreenViewId, context);
    return controller;
  }

  testWidgets('waits for the closing fullscreen view, then uses the inline '
      'view', (tester) async {
    await tester.pumpWidget(const SizedBox());

    await tester.runAsync(() async {
      final controller = await attachInlineAndFullscreenViews(tester);

      // Not fullscreen any more, but the fullscreen view is still attached:
      // the state right after exitFullScreen().
      final Future<bool> entering = controller.enterPictureInPicture();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(pipCalls, isEmpty);

      controller.onPlatformViewDisposed(fullscreenViewId);
      await entering;

      expect(pipCalls, hasLength(1));
      expect(pipCalls.single.arguments, containsPair('viewId', inlineViewId));

      await controller.dispose();
    });
  });

  testWidgets('gives up waiting after a second', (tester) async {
    await tester.pumpWidget(const SizedBox());

    await tester.runAsync(() async {
      final controller = await attachInlineAndFullscreenViews(tester);

      final Stopwatch stopwatch = Stopwatch()..start();
      await controller.enterPictureInPicture();

      expect(
        stopwatch.elapsed,
        greaterThanOrEqualTo(const Duration(seconds: 1)),
      );
      expect(pipCalls, hasLength(1));

      await controller.dispose();
    });
  });
}
