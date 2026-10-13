import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// EventChannel `listen`/`cancel` handshakes against native handlers that are
/// gone or not there yet.
///
/// The stock EventChannel stream reports a failed handshake to
/// [FlutterError.onError]. In the field that surfaced as a
/// MissingPluginException for `cancel` on `native_video_player_<viewId>`
/// (Android removes the handler when the engine disposes the platform view,
/// before the widget's dispose cancels), the same for `listen`, and as
/// "No active stream to cancel". None of these may reach
/// FlutterError.onError.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methodChannel = MethodChannel('native_video_player');

  late List<String> log;
  late List<FlutterErrorDetails> flutterErrors;
  late Map<int, MockStreamHandlerEventSink> controllerSinks;
  FlutterExceptionHandler? originalOnError;

  setUp(() {
    log = <String>[];
    flutterErrors = <FlutterErrorDetails>[];
    controllerSinks = <int, MockStreamHandlerEventSink>{};
    originalOnError = FlutterError.onError;
    FlutterError.onError = flutterErrors.add;
    NativeVideoPlayerController.controllerChannelRetryDelays = const [
      Duration.zero,
      Duration.zero,
      Duration.zero,
    ];
  });

  tearDown(() {
    FlutterError.onError = originalOnError;
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  /// Registers (or removes) the native stream handler for the controller
  /// channel of [id], like the plugin's setup/teardown methods do.
  void setControllerStreamRegistered(int id, {required bool registered}) {
    final channel = EventChannel('native_video_player_controller_$id');
    if (!registered) {
      messenger.setMockStreamHandler(channel, null);
      return;
    }
    messenger.setMockStreamHandler(
      channel,
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          log.add('controller:onListen');
          controllerSinks[id] = events;
        },
        onCancel: (arguments) => log.add('controller:onCancel'),
      ),
    );
  }

  /// Mocks the shared method channel; controller-channel setup and teardown
  /// register and remove the native stream handler as the plugin does.
  void mockPlugin() {
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      log.add('method:${call.method}');
      final id = (call.arguments as Map?)?['controllerId'] as int?;
      if (call.method == 'setupControllerEventChannel' && id != null) {
        setControllerStreamRegistered(id, registered: true);
      }
      if (call.method == 'teardownControllerEventChannel' && id != null) {
        setControllerStreamRegistered(id, registered: false);
      }
      if (call.method == 'getAvailableQualities') return <Object?>[];
      return null;
    });
  }

  /// Mocks the per-view stream `native_video_player_[viewId]`.
  void mockViewStream(int viewId) {
    messenger.setMockStreamHandler(
      EventChannel('native_video_player_$viewId'),
      MockStreamHandler.inline(
        onListen: (arguments, events) => log.add('view$viewId:onListen'),
        onCancel: (arguments) => log.add('view$viewId:onCancel'),
      ),
    );
  }

  /// Removes the per-view stream handler, like Android does when the engine
  /// disposes the platform view.
  void removeViewStream(int viewId) {
    messenger.setMockStreamHandler(
      EventChannel('native_video_player_$viewId'),
      null,
    );
  }

  Future<void> settle([int milliseconds = 100]) =>
      Future<void>.delayed(Duration(milliseconds: milliseconds));

  group('per-view event channel', () {
    testWidgets('cancel after the native handler is gone is silent', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      final context = tester.element(find.byType(SizedBox));

      await tester.runAsync(() async {
        mockPlugin();
        mockViewStream(601);

        final controller = NativeVideoPlayerController(id: 31);
        await controller.debugControllerChannelSetup;
        await controller.onPlatformViewCreated(601, context);
        await settle();
        expect(log, contains('view601:onListen'));

        // The engine disposed the platform view (and with it the handler)
        // before the widget's dispose reaches the controller.
        removeViewStream(601);
        controller.onPlatformViewDisposed(601);
        await settle();

        expect(log, contains('method:viewDisposed'));
        expect(flutterErrors, isEmpty);

        await controller.dispose();
        expect(flutterErrors, isEmpty);
      });
    });

    testWidgets('a view disposed before its subscription attaches is never '
        'listened to', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final context = tester.element(find.byType(SizedBox));

      await tester.runAsync(() async {
        mockPlugin();
        mockViewStream(602);

        final controller = NativeVideoPlayerController(id: 32);
        await controller.debugControllerChannelSetup;
        await controller.onPlatformViewCreated(602, context);
        // Disposed before the subscription's initial delay elapsed.
        controller.onPlatformViewDisposed(602);
        await settle();

        expect(log, isNot(contains('view602:onListen')));
        expect(log, contains('method:viewDisposed'));
        expect(flutterErrors, isEmpty);

        await controller.dispose();
        expect(log, isNot(contains('view602:onCancel')));
        expect(flutterErrors, isEmpty);
      });
    });

    testWidgets('a listen without a native handler is silent and never '
        'cancelled', (tester) async {
      await tester.pumpWidget(const SizedBox());
      final context = tester.element(find.byType(SizedBox));

      await tester.runAsync(() async {
        mockPlugin();
        final viewMethods = <String>[];
        messenger.setMockMessageHandler('native_video_player_603', (
          message,
        ) async {
          viewMethods.add(
            const StandardMethodCodec().decodeMethodCall(message).method,
          );
          return null; // no handler: MissingPluginException on the caller
        });

        final controller = NativeVideoPlayerController(id: 33);
        await controller.debugControllerChannelSetup;
        await controller.onPlatformViewCreated(603, context);
        await settle(200);

        expect(viewMethods, contains('listen'));
        expect(flutterErrors, isEmpty);

        await controller.dispose();
        await settle(200);

        expect(viewMethods, isNot(contains('cancel')));
        expect(flutterErrors, isEmpty);
        messenger.setMockMessageHandler('native_video_player_603', null);
      });
    });
  });

  group('controller event channel shared by one ID', () {
    test(
      'both controllers receive events; only the last one tears down',
      () async {
        mockPlugin();

        final first = NativeVideoPlayerController(id: 41);
        await first.debugControllerChannelSetup;
        final second = NativeVideoPlayerController(id: 41);
        await second.debugControllerChannelSetup;
        await Future<void>.delayed(Duration.zero);

        expect(log.where((e) => e == 'controller:onListen').length, 1);

        controllerSinks[41]!.success(<String, Object?>{'event': 'pipStart'});
        await Future<void>.delayed(Duration.zero);
        expect(first.isPipEnabled, isTrue);
        expect(second.isPipEnabled, isTrue);

        await first.dispose();
        expect(log, isNot(contains('controller:onCancel')));
        expect(log, isNot(contains('method:teardownControllerEventChannel')));

        controllerSinks[41]!.success(<String, Object?>{'event': 'pipStop'});
        await Future<void>.delayed(Duration.zero);
        expect(second.isPipEnabled, isFalse);

        await second.dispose();
        final relevant = log
            .where(
              (e) =>
                  e == 'controller:onCancel' ||
                  e == 'method:teardownControllerEventChannel',
            )
            .toList();
        expect(relevant, [
          'controller:onCancel',
          'method:teardownControllerEventChannel',
        ]);
        expect(flutterErrors, isEmpty);
      },
    );

    test('a controller created while another with its ID is being disposed '
        'keeps receiving events', () async {
      mockPlugin();

      final leaving = NativeVideoPlayerController(id: 42);
      await leaving.debugControllerChannelSetup;
      await Future<void>.delayed(Duration.zero);

      // The next screen's controller for the same video is created while the
      // previous screen's controller is still being disposed.
      final disposing = leaving.dispose();
      final arriving = NativeVideoPlayerController(id: 42);
      await disposing;
      await arriving.debugControllerChannelSetup;
      await Future<void>.delayed(Duration.zero);

      controllerSinks[42]!.success(<String, Object?>{'event': 'pipStart'});
      await Future<void>.delayed(Duration.zero);
      expect(arriving.isPipEnabled, isTrue);
      expect(flutterErrors, isEmpty);

      await arriving.dispose();
      expect(
        log.where((e) => e == 'method:teardownControllerEventChannel').length,
        1,
      );
      expect(flutterErrors, isEmpty);
    });

    test('a controller created after another with its ID left re-registers '
        'only after the teardown', () async {
      mockPlugin();

      final leaving = NativeVideoPlayerController(id: 43);
      await leaving.debugControllerChannelSetup;
      await Future<void>.delayed(Duration.zero);

      // Let the dispose reach its teardown before the next controller exists.
      final disposing = leaving.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 1));
      final arriving = NativeVideoPlayerController(id: 43);
      await disposing;
      await arriving.debugControllerChannelSetup;
      await Future<void>.delayed(Duration.zero);

      final teardownIndex = log.indexOf(
        'method:teardownControllerEventChannel',
      );
      final lastSetupIndex = log.lastIndexOf(
        'method:setupControllerEventChannel',
      );
      if (teardownIndex >= 0) {
        expect(lastSetupIndex, greaterThan(teardownIndex));
      }

      controllerSinks[43]!.success(<String, Object?>{'event': 'pipStart'});
      await Future<void>.delayed(Duration.zero);
      expect(arriving.isPipEnabled, isTrue);
      expect(flutterErrors, isEmpty);

      await arriving.dispose();
      expect(flutterErrors, isEmpty);
    });
  });
}
