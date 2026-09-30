import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// initialize() must wait for a live platform view again after the last view
/// was disposed or releaseResources() was called, instead of returning early
/// and letting commands hit a gone view (NO_VIEW).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methodChannel = MethodChannel('native_video_player');
  const controllerId = 7;

  late NativeVideoPlayerController controller;

  setUp(() {
    messenger.setMockMethodCallHandler(methodChannel, (call) async => null);
    messenger.setMockStreamHandler(
      const EventChannel('native_video_player_controller_$controllerId'),
      MockStreamHandler.inline(onListen: (arguments, events) {}),
    );
    for (final viewId in [1, 2]) {
      messenger.setMockStreamHandler(
        EventChannel('native_video_player_$viewId'),
        MockStreamHandler.inline(onListen: (arguments, events) {}),
      );
    }
    controller = NativeVideoPlayerController(id: controllerId);
  });

  tearDown(() async {
    await controller.dispose();
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  Future<BuildContext> contextFor(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    return tester.element(find.byType(SizedBox));
  }

  testWidgets('initialize waits for a new view after the last one is disposed', (
    tester,
  ) async {
    final context = await contextFor(tester);
    await controller.onPlatformViewCreated(1, context);
    await controller.initialize();
    await controller.load(url: 'https://example.com/a.m3u8');

    controller.onPlatformViewDisposed(1);
    expect(controller.isInitialized, isFalse);
    expect(
      () => controller.load(url: 'https://example.com/b.m3u8', force: true),
      throwsException,
    );

    var initialized = false;
    final pending = controller.initialize().then((_) => initialized = true);
    await tester.pump();
    expect(initialized, isFalse);

    await controller.onPlatformViewCreated(2, context);
    await pending;
    expect(controller.isInitialized, isTrue);
    // Re-attaching to the shared player keeps its media state.
    expect(controller.activityState, PlayerActivityState.loaded);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('pending initialize survives releaseResources', (tester) async {
    final context = await contextFor(tester);

    var initialized = false;
    final pending = controller.initialize().then((_) => initialized = true);
    await controller.releaseResources();
    await tester.pump();
    expect(initialized, isFalse);

    await controller.onPlatformViewCreated(1, context);
    await pending;
    expect(controller.isInitialized, isTrue);
    expect(controller.activityState, PlayerActivityState.initialized);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('initialize waits again after releaseResources', (tester) async {
    final context = await contextFor(tester);
    await controller.onPlatformViewCreated(1, context);
    await controller.initialize();

    controller.onPlatformViewDisposed(1);
    await controller.releaseResources();
    expect(controller.isInitialized, isFalse);

    var initialized = false;
    final pending = controller.initialize().then((_) => initialized = true);
    await tester.pump();
    expect(initialized, isFalse);

    await controller.onPlatformViewCreated(2, context);
    await pending;
    expect(initialized, isTrue);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('a failed surface reconnect keeps initialize pending', (
    tester,
  ) async {
    final context = await contextFor(tester);
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      final args = call.arguments;
      if (call.method == 'ensureSurfaceConnected' &&
          args is Map &&
          args['viewId'] == 1) {
        throw PlatformException(code: 'NO_VIEW');
      }
      return null;
    });

    var initialized = false;
    final pending = controller.initialize().then((_) => initialized = true);

    await controller.onPlatformViewCreated(1, context);
    await tester.pump();
    expect(initialized, isFalse);
    expect(controller.isInitialized, isFalse);

    // The next attach retries the reconnect even though view 1 is still
    // registered.
    await controller.onPlatformViewCreated(2, context);
    await pending;
    expect(controller.isInitialized, isTrue);
    await tester.pump(const Duration(milliseconds: 100));
  });

  testWidgets('activity events from a failed attach keep initialize pending', (
    tester,
  ) async {
    final context = await contextFor(tester);
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      if (call.method == 'ensureSurfaceConnected') {
        throw PlatformException(code: 'NO_VIEW');
      }
      return null;
    });
    messenger.setMockStreamHandler(
      const EventChannel('native_video_player_1'),
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          events.success({'event': 'isInitialized'});
          events.success({'event': 'play'});
        },
      ),
    );

    var initialized = false;
    final pending = controller.initialize().then((_) => initialized = true);

    await controller.onPlatformViewCreated(1, context);
    await tester.pump(const Duration(milliseconds: 100));
    expect(initialized, isFalse);
    expect(controller.isInitialized, isFalse);

    messenger.setMockMethodCallHandler(methodChannel, (call) async => null);
    await controller.onPlatformViewCreated(2, context);
    await pending;
    expect(controller.isInitialized, isTrue);
    await tester.pump(const Duration(milliseconds: 100));
  });

  test('dispose releases a pending initialize', () async {
    var initialized = false;
    final pending = controller.initialize().then((_) => initialized = true);

    await controller.dispose();
    await pending;

    expect(initialized, isTrue);
    expect(controller.isInitialized, isFalse);
  });
}
