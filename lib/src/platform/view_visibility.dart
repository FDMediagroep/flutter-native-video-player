import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Answers the native side's question whether a platform view is fully
/// visible (iOS: a closing PiP window only flies back into a player that is).
///
/// AVKit animates the window to the native view's whole frame, above
/// everything Flutter draws, so a tile half under the app bar got the video
/// drawn over the app bar until the animation ended. Only Flutter knows the
/// clips (scroll viewports, clip widgets) a platform view is painted under.
class ViewVisibility {
  ViewVisibility._();

  static const MethodChannel _channel = MethodChannel(
    'native_video_player/visibility',
  );

  static final Map<int, BuildContext> _views = <int, BuildContext>{};
  static bool _handlerInstalled = false;

  /// Lets the native side ask about platform view [viewId], drawn by the
  /// widget at [context].
  static void register(int viewId, BuildContext context) {
    _views[viewId] = context;
    if (!_handlerInstalled) {
      _handlerInstalled = true;
      _channel.setMethodCallHandler(_handle);
    }
  }

  /// Stops answering for [viewId] (when [context] still owns it).
  static void unregister(int viewId, BuildContext context) {
    if (identical(_views[viewId], context)) {
      _views.remove(viewId);
    }
  }

  static Future<Object?> _handle(MethodCall call) async {
    if (call.method != 'isViewFullyVisible') {
      throw MissingPluginException();
    }
    final int? viewId = (call.arguments as Map<Object?, Object?>?)?['viewId']
        as int?;
    final BuildContext? context = viewId == null ? null : _views[viewId];
    if (context == null || !context.mounted) {
      return false;
    }
    return isFullyVisible(context);
  }

  /// Whether the widget at [context] is painted whole: not cut by an
  /// ancestor's clip (a scrolled list, a clip widget) nor by the screen
  /// edge. [tolerance] (logical pixels) absorbs rounding.
  static bool isFullyVisible(BuildContext context, {double tolerance = 2}) {
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
}
