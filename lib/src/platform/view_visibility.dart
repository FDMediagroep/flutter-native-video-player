import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Answers the native side's question whether a platform view is fully
/// visible (iOS: a closing PiP window only flies back into a player that is).
///
/// AVKit animates the window to the native view's whole frame, above
/// everything Flutter draws, so a tile half under the app bar got the video
/// drawn over the app bar until the animation ended. Only Flutter knows the
/// clips (scroll viewports, clip widgets) and routes a platform view is
/// painted under.
class ViewVisibility {
  ViewVisibility._();

  static const MethodChannel _channel = MethodChannel(
    'native_video_player/visibility',
  );

  static final Map<int, _RegisteredView> _views = <int, _RegisteredView>{};
  static bool _handlerInstalled = false;

  /// Lets the native side ask about platform view [viewId], drawn by the
  /// widget at [context] for the controller with ID [controllerId].
  static void register(
    int viewId,
    BuildContext context, {
    required int controllerId,
  }) {
    _views[viewId] = _RegisteredView(context, controllerId);
    if (!_handlerInstalled) {
      _handlerInstalled = true;
      _channel.setMethodCallHandler(_handle);
    }
  }

  /// Stops answering for [viewId] (when [context] still owns it).
  static void unregister(int viewId, BuildContext context) {
    if (identical(_views[viewId]?.context, context)) {
      _views.remove(viewId);
    }
  }

  static Future<Object?> _handle(MethodCall call) async {
    if (call.method != 'isViewFullyVisible') {
      throw MissingPluginException();
    }
    final int? viewId = (call.arguments as Map<Object?, Object?>?)?['viewId']
        as int?;
    final BuildContext? context = viewId == null ? null : _views[viewId]?.context;
    if (context == null || !context.mounted) {
      return false;
    }
    return isFullyVisible(context);
  }

  /// Whether a player of the controller with ID [controllerId] is fully
  /// visible (see [isFullyVisible]).
  static bool isControllerFullyVisible(int controllerId) {
    for (final _RegisteredView view in _views.values) {
      if (view.controllerId == controllerId &&
          view.context.mounted &&
          isFullyVisible(view.context)) {
        return true;
      }
    }
    return false;
  }

  /// Waits, frame by frame and at most [timeout], until a player of the
  /// controller with ID [controllerId] is fully visible: a screen just
  /// opened for it first has to build and finish its route transition.
  static Future<bool> waitUntilControllerFullyVisible(
    int controllerId, {
    required Duration timeout,
  }) async {
    final Completer<void> deadline = Completer<void>();
    final Timer timer = Timer(timeout, deadline.complete);
    try {
      while (!isControllerFullyVisible(controllerId)) {
        if (deadline.isCompleted) {
          return false;
        }
        // No frame comes while the app is not drawing (still in the
        // background): the deadline then ends the wait.
        await Future.any<void>(<Future<void>>[
          SchedulerBinding.instance.endOfFrame,
          deadline.future,
        ]);
      }
      return true;
    } finally {
      timer.cancel();
    }
  }

  /// Whether the widget at [context] is painted whole: its route (and every
  /// enclosing route) is on top and done animating, and it is not cut by an
  /// ancestor's clip (a scrolled list, a clip widget) nor by the screen
  /// edge. [tolerance] (logical pixels) absorbs rounding.
  static bool isFullyVisible(BuildContext context, {double tolerance = 2}) {
    if (!_isOnTopRoute(context)) {
      return false;
    }

    final RenderObject? object = context.findRenderObject();
    if (object is! RenderBox || !object.attached || !object.hasSize) {
      return false;
    }

    final Rect full = MatrixUtils.transformRect(
      object.getTransformTo(null),
      Offset.zero & object.size,
    );
    Rect visible = full;

    RenderObject child = object;
    RenderObject? parent = object.parent;
    while (parent != null) {
      final Rect? clip = parent.describeApproximatePaintClip(child);
      if (clip != null) {
        visible = visible.intersect(
          MatrixUtils.transformRect(parent.getTransformTo(null), clip),
        );
      }
      child = parent;
      parent = parent.parent;
    }

    final view = View.of(context);
    visible = visible.intersect(
      Offset.zero & (view.physicalSize / view.devicePixelRatio),
    );

    return visible.width >= full.width - tolerance &&
        visible.height >= full.height - tolerance;
  }

  /// A page or dialog pushed over the player covers it without clipping it,
  /// and a route still sliding in moves it: walks out through nested
  /// navigators (a tab shell's) up to the root.
  static bool _isOnTopRoute(BuildContext context) {
    BuildContext? current = context;
    while (current != null) {
      final ModalRoute<Object?>? route = ModalRoute.of(current);
      if (route == null) {
        return true;
      }
      if (!route.isCurrent ||
          route.animation?.status != AnimationStatus.completed ||
          (route.secondaryAnimation?.status ?? AnimationStatus.dismissed) !=
              AnimationStatus.dismissed) {
        return false;
      }
      final NavigatorState? navigator = route.navigator;
      if (navigator == null || !navigator.mounted) {
        return true;
      }
      current = navigator.context;
    }
    return true;
  }
}

class _RegisteredView {
  _RegisteredView(this.context, this.controllerId);

  final BuildContext context;
  final int controllerId;
}
