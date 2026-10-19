import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'view_visibility.dart';

/// Runs the app's `onPictureInPictureRestore` handler when the user taps the
/// button in the PiP window that returns to the app (iOS).
///
/// AVKit asks the native side to restore the app's UI and waits for its
/// answer before the window animates. The native side asks here; the reply
/// comes once the handler has opened the screen and a player of the
/// controller is fully visible, so the window flies into that player.
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
