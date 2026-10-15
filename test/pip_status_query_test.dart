import 'package:better_native_video_player/src/platform/video_player_method_channel.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// iOS: the PiP status is asked by controller ID, because the window can
/// outlive the view that opened it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methodChannel = MethodChannel('native_video_player');

  final List<MethodCall> calls = <MethodCall>[];

  tearDown(() {
    calls.clear();
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  test('asks by controller ID and returns the native answer', () async {
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      return false;
    });

    final channel = VideoPlayerMethodChannel(
      primaryPlatformViewId: 1,
      controllerId: 7,
    );

    expect(await channel.isPictureInPictureActive(), isFalse);
    expect(calls.single.method, 'isPictureInPictureActive');
    expect(calls.single.arguments, <String, Object>{'controllerId': 7});
  });

  test('returns null without a controller ID', () async {
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      calls.add(call);
      return true;
    });

    final channel = VideoPlayerMethodChannel(primaryPlatformViewId: 1);

    expect(await channel.isPictureInPictureActive(), isNull);
    expect(calls, isEmpty);
  });

  test('returns null when the call fails', () async {
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      throw PlatformException(code: 'NO_VIEW');
    });

    final channel = VideoPlayerMethodChannel(
      primaryPlatformViewId: 1,
      controllerId: 7,
    );

    expect(await channel.isPictureInPictureActive(), isNull);
  });
}
