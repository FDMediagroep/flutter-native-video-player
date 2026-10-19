import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:better_native_video_player/src/poster/poster_layer.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Poster layer: the still until the video plays, the preview animation on
/// its timer, the duration / LIVE badge — events injected through the
/// per-view EventChannel like the native side sends them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const methodChannel = MethodChannel('native_video_player');

  // 1×1 transparent PNG.
  final pixel = MemoryImage(
    Uint8List.fromList(const <int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, //
      0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00,
      0x00, 0x01, 0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89,
      0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63,
      0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4,
      0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60,
      0x82,
    ]),
  );

  late NativeVideoPlayerController controller;
  MockStreamHandlerEventSink? viewSink;

  // Fresh ids per test, so a previous test's channel teardown can never
  // clear the handler the current test registered.
  var testSeq = 0;
  late int controllerId;
  late int viewId;

  setUp(() {
    testSeq++;
    controllerId = 8800 + testSeq;
    viewId = 9800 + testSeq;
    viewSink = null;
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      return call.method == 'getAvailableQualities' ? <Object?>[] : null;
    });
  });

  tearDown(() async {
    await controller.dispose().timeout(
      const Duration(seconds: 1),
      onTimeout: () {},
    );
    messenger.setMockMethodCallHandler(methodChannel, null);
  });

  Future<void> pumpPoster(
    WidgetTester tester,
    NativeVideoPlayerPoster poster,
  ) async {
    messenger.setMockStreamHandler(
      EventChannel('native_video_player_controller_$controllerId'),
      MockStreamHandler.inline(onListen: (arguments, events) {}),
    );
    messenger.setMockStreamHandler(
      EventChannel('native_video_player_$viewId'),
      MockStreamHandler.inline(
        onListen: (arguments, events) {
          viewSink = events;
        },
      ),
    );
    controller = NativeVideoPlayerController(id: controllerId);
    await tester.pumpWidget(const SizedBox());
    await controller.onPlatformViewCreated(
      viewId,
      tester.element(find.byType(SizedBox)),
    );
    // Lets the per-view EventChannel subscribe.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: PosterLayer(poster: poster, controller: controller),
      ),
    );
  }

  Future<void> send(WidgetTester tester, Map<String, dynamic> event) async {
    viewSink!.success(event);
    await tester.pump();
  }

  // The fade, then the frame that drops the faded-out poster.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  Finder preview() => find.byKey(const ValueKey('preview'));
  Finder still() => find.byKey(const ValueKey('still'));

  testWidgets('still, then the animation after its delay, gone on play', (
    tester,
  ) async {
    await pumpPoster(
      tester,
      NativeVideoPlayerPoster(
        image: pixel,
        animation: pixel,
        animationDelay: const Duration(seconds: 2),
        fadeDuration: const Duration(milliseconds: 100),
      ),
    );
    expect(still(), findsOneWidget);
    expect(preview(), findsNothing);

    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 100));
    expect(preview(), findsOneWidget);

    await send(tester, {'event': 'play'});
    await settle(tester);
    expect(still(), findsNothing);
    expect(preview(), findsNothing);
  });

  testWidgets('animationDuration fades back to the still and repeats', (
    tester,
  ) async {
    await pumpPoster(
      tester,
      NativeVideoPlayerPoster(
        image: pixel,
        animation: pixel,
        animationDelay: const Duration(seconds: 1),
        animationDuration: const Duration(seconds: 3),
        fadeDuration: Duration.zero,
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(preview(), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    expect(preview(), findsNothing);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(preview(), findsOneWidget, reason: 'repeatAnimation defaults on');
  });

  testWidgets('a loaded video that never played keeps its poster', (
    tester,
  ) async {
    await pumpPoster(tester, NativeVideoPlayerPoster(image: pixel));
    await send(tester, {'event': 'loaded', 'duration': 60000});
    await tester.pump(const Duration(seconds: 1));
    expect(still(), findsOneWidget);
  });

  testWidgets('hideWhen onLoaded hides it once loaded', (tester) async {
    await pumpPoster(
      tester,
      NativeVideoPlayerPoster(
        image: pixel,
        hideWhen: NativeVideoPlayerPosterHide.onLoaded,
        fadeDuration: Duration.zero,
      ),
    );
    await send(tester, {'event': 'loaded', 'duration': 60000});
    await settle(tester);
    expect(still(), findsNothing);
  });

  testWidgets('showOnCompleted brings the poster back at the end', (
    tester,
  ) async {
    await pumpPoster(
      tester,
      NativeVideoPlayerPoster(
        image: pixel,
        showOnCompleted: true,
        fadeDuration: Duration.zero,
      ),
    );
    await send(tester, {'event': 'play'});
    await settle(tester);
    expect(still(), findsNothing);

    await send(tester, {'event': 'completed'});
    await tester.pump();
    expect(still(), findsOneWidget);
  });

  testWidgets('badge: the given duration, then the player\'s, LIVE for live', (
    tester,
  ) async {
    await pumpPoster(
      tester,
      NativeVideoPlayerPoster(
        image: pixel,
        duration: const Duration(minutes: 9, seconds: 56),
      ),
    );
    expect(find.text('9:56'), findsOneWidget);

    await send(tester, {
      'event': 'timeUpdate',
      'position': 0,
      'duration': 3723000,
      'bufferedPosition': 0,
      'isBuffering': false,
    });
    await tester.pump();
    expect(find.text('1:02:03'), findsOneWidget);

    await send(tester, {
      'event': 'timeUpdate',
      'position': 0,
      'duration': 60000,
      'bufferedPosition': 0,
      'isBuffering': false,
      'isLive': true,
    });
    await tester.pump();
    expect(find.text('LIVE'), findsOneWidget);
  });

  testWidgets('badgeBuilder and overlayBuilder draw custom chrome', (
    tester,
  ) async {
    await pumpPoster(
      tester,
      NativeVideoPlayerPoster(
        image: pixel,
        duration: const Duration(seconds: 75),
        badgeBuilder: (context, label, state) => Text('⏱ $label'),
        overlayBuilder: (context, state) =>
            Text(state.isLoading ? 'loading' : 'ready'),
      ),
    );
    expect(find.text('⏱ 1:15'), findsOneWidget);
    expect(find.text('loading'), findsOneWidget);

    await send(tester, {'event': 'loaded', 'duration': 75000});
    await tester.pump();
    expect(find.text('ready'), findsOneWidget);
  });

  group('Bunny Stream', () {
    test('poster uses thumbnail.jpg and preview.webp', () {
      final poster = NativeVideoPlayerPoster.bunny(
        'https://vz-abc.b-cdn.net/video-id/',
      );
      expect(
        (poster.image! as NetworkImage).url,
        'https://vz-abc.b-cdn.net/video-id/thumbnail.jpg',
      );
      expect(
        (poster.animation! as NetworkImage).url,
        'https://vz-abc.b-cdn.net/video-id/preview.webp',
      );

      final gif = NativeVideoPlayerPoster.bunny(
        'https://vz-abc.b-cdn.net/video-id',
        thumbnailFileName: 'custom.jpg',
        gifPreview: true,
      );
      expect(
        (gif.image! as NetworkImage).url,
        endsWith('/video-id/custom.jpg'),
      );
      expect((gif.animation! as NetworkImage).url, endsWith('/preview.gif'));
      expect(
        NativeVideoPlayerPoster.bunny('https://x', preview: false).animation,
        isNull,
      );
    });

    test('seek sprites: 6×6 grids of 300×168 frames, 2 s apart', () {
      final board = StoryboardThumbnails.bunny(
        videoBaseUrl: 'https://vz-abc.b-cdn.net/video-id',
        duration: const Duration(seconds: 100),
      );
      // 50 frames: 36 on the first sheet, 14 on the second.
      expect(board.entries, hasLength(50));
      expect(board.entries.first.url, endsWith('/video-id/seek/_0.jpg'));
      expect(board.entries.last.url, endsWith('/video-id/seek/_1.jpg'));

      final at = board.thumbnailAt(const Duration(seconds: 15))!;
      // Frame 7: row 1, column 1.
      expect(at.region, const Rect.fromLTWH(300, 168, 300, 168));
      expect(at.start, const Duration(seconds: 14));
    });

    test('videos under 10 s get a frame every second', () {
      final board = StoryboardThumbnails.bunny(
        videoBaseUrl: 'https://vz-abc.b-cdn.net/short',
        duration: const Duration(seconds: 8),
      );
      expect(board.entries, hasLength(8));
      expect(board.entries[1].start, const Duration(seconds: 1));
    });
  });
}
