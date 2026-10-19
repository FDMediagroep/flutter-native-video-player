import 'package:better_native_video_player/src/platform/pip_restore.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Android reports neither the PiP window's expand button nor its X: the
/// lifecycle after the PiP flag went off tells them apart. An expand calls
/// `onPictureInPictureRestore`, a close pauses.
void main() {
  /// Runs the classifier against [states], one per 100 ms poll (the last
  /// one repeats), on the test's fake clock, and returns its answer.
  Future<AndroidPipExit> classify(
    WidgetTester tester,
    List<AppLifecycleState?> states, {
    bool Function()? isStillOutOfPip,
  }) async {
    var poll = 0;
    AndroidPipExit? result;
    PipRestore.classifyAndroidPipExit(
      lifecycle: () =>
          states[poll < states.length ? poll++ : states.length - 1],
      isStillOutOfPip: isStillOutOfPip ?? () => true,
    ).then((AndroidPipExit value) => result = value);
    for (var i = 0; i < 40 && result == null; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return result!;
  }

  testWidgets('resumed is an expand', (tester) async {
    expect(
      await classify(tester, <AppLifecycleState?>[
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]),
      AndroidPipExit.expanded,
    );
  });

  testWidgets('hidden or paused is a close with the X', (tester) async {
    expect(
      await classify(tester, <AppLifecycleState?>[
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
      ]),
      AndroidPipExit.dismissed,
    );
    expect(
      await classify(tester, <AppLifecycleState?>[AppLifecycleState.paused]),
      AndroidPipExit.dismissed,
    );
  });

  testWidgets('inactive until the next touch is an expand', (tester) async {
    expect(
      await classify(tester, <AppLifecycleState?>[AppLifecycleState.inactive]),
      AndroidPipExit.expanded,
    );
  });

  testWidgets('back in PiP, or disposed, before it is clear', (tester) async {
    var polls = 0;
    expect(
      await classify(tester, <AppLifecycleState?>[
        AppLifecycleState.inactive,
      ], isStillOutOfPip: () => ++polls < 3),
      AndroidPipExit.undecided,
    );
  });

  testWidgets('an expand calls the handler set for the controller', (
    tester,
  ) async {
    var calls = 0;
    PipRestore.setHandler(7, () => calls++);
    await PipRestore.callHandler(7);
    await PipRestore.callHandler(8);
    expect(calls, 1);
    PipRestore.setHandler(7, null);
  });
}
