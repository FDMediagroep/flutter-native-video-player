import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A subscription to a native EventChannel that handles its own
/// `listen`/`cancel` handshake.
///
/// [EventChannel.receiveBroadcastStream] reports a failed handshake straight
/// to [FlutterError.onError], where callers cannot catch it. With platform
/// views such failures are routine: Android removes a view's stream handler
/// when the engine disposes the view, before the widget's dispose cancels; a
/// view can be disposed before its subscription attaches. Each of those
/// surfaced as a MissingPluginException or a "No active stream to cancel"
/// PlatformException report.
///
/// This speaks the same protocol (a message handler on the channel name plus
/// `listen` and `cancel` method calls) and treats a failed handshake as "the
/// native stream is gone": [listen] reports it, [cancel] swallows it.
class NativeEventSubscription {
  NativeEventSubscription(
    this.channelName, {
    required this.onEvent,
    this.onError,
  });

  /// The EventChannel name, e.g. `native_video_player_<viewId>`.
  final String channelName;

  /// Called for every event the native side sends.
  final void Function(dynamic event) onEvent;

  /// Called for every error the native side sends through its sink.
  final void Function(Object error)? onError;

  static const MethodCodec _codec = StandardMethodCodec();

  /// The subscription that owns each channel name's message handler. A
  /// [BinaryMessenger] keeps one handler per name, so a subscription that was
  /// superseded on its name must leave the newer one's handler (and native
  /// sink) alone when it is cancelled.
  static final Map<String, NativeEventSubscription> _handlerOwners =
      <String, NativeEventSubscription>{};

  bool _isListening = false;
  bool _isCancelled = false;
  bool _ownedHandlerWhenCancelled = false;

  /// Whether the native side accepted the listen and it was not cancelled.
  bool get isListening => _isListening && !_isCancelled;

  /// Whether [cancel] was called.
  bool get isCancelled => _isCancelled;

  BinaryMessenger get _messenger =>
      ServicesBinding.instance.defaultBinaryMessenger;

  MethodChannel get _methodChannel => MethodChannel(channelName, _codec);

  /// Starts the native stream.
  ///
  /// Returns false when the native side has no handler for [channelName],
  /// rejected the listen, or [cancel] was called while it was in flight.
  Future<bool> listen() async {
    if (_isCancelled || _isListening) {
      return isListening;
    }

    _handlerOwners[channelName] = this;
    _messenger.setMessageHandler(channelName, _handleMessage);

    try {
      await _methodChannel.invokeMethod<void>('listen');
    } on MissingPluginException {
      _releaseHandler();
      return false;
    } catch (e) {
      // A PlatformException from the native onListen, or a channel failure.
      if (kDebugMode) {
        debugPrint('Listening on $channelName failed: $e');
      }
      _releaseHandler();
      return false;
    }

    if (_isCancelled) {
      // Cancelled while the listen was in flight: the native side has a sink
      // now, so stop it — unless a newer subscription took the channel over.
      if (_ownedHandlerWhenCancelled) {
        await _sendCancel();
      }
      return false;
    }

    _isListening = true;
    return true;
  }

  /// Stops the native stream. Idempotent, and never throws: a native side
  /// that is already gone has nothing left to stop.
  Future<void> cancel() async {
    if (_isCancelled) {
      return;
    }
    _isCancelled = true;
    _ownedHandlerWhenCancelled = _releaseHandler();

    if (_isListening && _ownedHandlerWhenCancelled) {
      await _sendCancel();
    }
  }

  Future<ByteData?> _handleMessage(ByteData? message) async {
    // A null message is the native end-of-stream marker.
    if (message == null || _isCancelled) {
      return null;
    }

    try {
      onEvent(_codec.decodeEnvelope(message));
    } on PlatformException catch (e) {
      onError?.call(e);
    }
    return null;
  }

  /// Removes this subscription's message handler if it still owns the
  /// channel name. Returns whether it did.
  bool _releaseHandler() {
    if (!identical(_handlerOwners[channelName], this)) {
      return false;
    }
    _handlerOwners.remove(channelName);
    _messenger.setMessageHandler(channelName, null);
    return true;
  }

  Future<void> _sendCancel() async {
    try {
      await _methodChannel.invokeMethod<void>('cancel');
    } on MissingPluginException {
      // The native handler is already gone, e.g. Android disposed the
      // platform view together with its stream.
    } catch (e) {
      // e.g. "No active stream to cancel": nothing left to stop natively.
      if (kDebugMode) {
        debugPrint('Cancelling $channelName: $e');
      }
    }
  }
}
