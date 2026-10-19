import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'view_visibility.dart';

/// How an Android Picture-in-Picture window ended (see
/// [PipRestore.classifyAndroidPipExit]).
enum AndroidPipExit {
  /// Expanded back into the app.
  expanded,

  /// Closed with its X: the app went to the background.
  dismissed,

  /// PiP came back, or the controller went, before it was clear.
  undecided,
}

/// Runs the app's `onPictureInPictureRestore` handler when the user takes
/// the PiP window back into the app.
///
/// iOS: AVKit asks the native side to restore the app's UI and waits for its
/// answer before the window animates. The native side asks here; the reply
/// comes once the handler has opened the screen and a player of the
/// controller is fully visible, so the window flies into that player.
/// Android: the controller calls [callHandler] when the window was expanded
/// (see [classifyAndroidPipExit]); nothing waits.
class PipRestore {
  PipRestore._();

  static const MethodChannel _channel = MethodChannel(
    'native_video_player/pip',
  );

  /// How long the app's handler may take to start its navigation.
  static const Duration handlerTimeout = Duration(milliseconds: 1500);

  /// How long to wait after the handler for a fully visible player (the
  /// opened route's transition). With [handlerTimeout] below the native
  /// side's 3 s backstop.
  static const Duration visibleTimeout = Duration(milliseconds: 1000);

  static final Map<int, FutureOr<void> Function()> _handlers =
      <int, FutureOr<void> Function()>{};
  static bool _handlerInstalled = false;

  /// Sets (or with null clears) the handler for the controller with ID
  /// [controllerId]. Controllers sharing an ID share one native player and
  /// one PiP window: the last handler set wins.
  static void setHandler(int controllerId, FutureOr<void> Function()? handler) {
    if (handler == null) {
      _handlers.remove(controllerId);
      return;
    }
    _handlers[controllerId] = handler;
    if (!_handlerInstalled) {
      _handlerInstalled = true;
      _channel.setMethodCallHandler(_handle);
    }
  }

  /// Clears [handler] for [controllerId] if it is still the one set.
  static void clearHandler(
    int controllerId,
    FutureOr<void> Function()? handler,
  ) {
    if (handler != null && identical(_handlers[controllerId], handler)) {
      _handlers.remove(controllerId);
    }
  }

  /// Calls the handler for [controllerId], if any, without waiting for a
  /// player (Android: the window was expanded and the app is already back).
  static Future<void> callHandler(int controllerId) async {
    final FutureOr<void> Function()? handler = _handlers[controllerId];
    if (handler == null) {
      return;
    }
    try {
      await Future<void>.sync(handler);
    } catch (e) {
      debugPrint('NativeVideoPlayer: onPictureInPictureRestore failed: $e');
    }
  }

  /// Tells how an Android PiP window ended, once the PiP flag went off.
  ///
  /// Android reports neither a tap on the window's expand button nor its X.
  /// Expanding brings the app back: `resumed`, or `inactive` until its window
  /// regains focus, which on some devices only happens on the next touch.
  /// Closing stops the activity: a lifecycle that reports the app hidden
  /// (`hidden`/`paused`). Still `inactive` after [timeout] counts as
  /// expanded. [isStillOutOfPip] going false (PiP again, or the controller
  /// disposed) ends the wait with [AndroidPipExit.undecided].
  static Future<AndroidPipExit> classifyAndroidPipExit({
    required AppLifecycleState? Function() lifecycle,
    required bool Function() isStillOutOfPip,
    Duration timeout = const Duration(seconds: 3),
    Duration pollInterval = const Duration(milliseconds: 100),
  }) async {
    Duration waited = Duration.zero;
    while (waited < timeout) {
      if (!isStillOutOfPip()) {
        return AndroidPipExit.undecided;
      }
      switch (lifecycle()) {
        case AppLifecycleState.resumed:
          return AndroidPipExit.expanded;
        case AppLifecycleState.hidden:
        case AppLifecycleState.paused:
        case AppLifecycleState.detached:
          return AndroidPipExit.dismissed;
        case AppLifecycleState.inactive:
        case null:
          break;
      }
      await Future<void>.delayed(pollInterval);
      waited += pollInterval;
    }
    return isStillOutOfPip()
        ? AndroidPipExit.expanded
        : AndroidPipExit.undecided;
  }

  static Future<Object?> _handle(MethodCall call) async {
    if (call.method != 'restoreUserInterface') {
      throw MissingPluginException();
    }
    final int? controllerId =
        (call.arguments as Map<Object?, Object?>?)?['controllerId'] as int?;
    final FutureOr<void> Function()? handler = controllerId == null
        ? null
        : _handlers[controllerId];
    if (controllerId == null || handler == null) {
      return false;
    }

    try {
      await Future<void>.sync(handler).timeout(handlerTimeout);
    } on TimeoutException {
      debugPrint(
        'NativeVideoPlayer: onPictureInPictureRestore took longer than '
        '${handlerTimeout.inMilliseconds} ms',
      );
    } catch (e) {
      debugPrint('NativeVideoPlayer: onPictureInPictureRestore failed: $e');
    }

    return ViewVisibility.waitUntilControllerFullyVisible(
      controllerId,
      timeout: visibleTimeout,
    );
  }
}
