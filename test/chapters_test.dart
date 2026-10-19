import 'dart:async';

import 'package:better_native_video_player/better_native_video_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _intro = NativeVideoPlayerChapter(start: Duration.zero, title: 'Intro');
const _partTwo = NativeVideoPlayerChapter(
  start: Duration(seconds: 30),
  title: 'Part two',
);
const _outro = NativeVideoPlayerChapter(
  start: Duration(seconds: 45),
  title: 'Outro',
);
const _chapters = [_intro, _partTwo, _outro];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseText', () {
    test('reads timestamp-first lines and skips the rest', () {
      final chapters = NativeVideoPlayerChapters.parseText('''
In this video we build a player.

0:00 Intro
1:23 - Setting up
(12:05) Outro: thanks!
1:02:03 | Bonus
Not a chapter at 2:30 in the middle
''');
      expect(chapters.map((c) => (c.start, c.title)), [
        (Duration.zero, 'Intro'),
        (const Duration(minutes: 1, seconds: 23), 'Setting up'),
        (const Duration(minutes: 12, seconds: 5), 'Outro: thanks!'),
        (const Duration(hours: 1, minutes: 2, seconds: 3), 'Bonus'),
      ]);
    });

    test('reads timestamp-last lines, bullets and brackets', () {
      final chapters = NativeVideoPlayerChapters.parseText(
        '• Intro - 0:00\n- Part two (1:23)\n[2:00] Outro',
      );
      expect(chapters.map((c) => (c.start, c.title)), [
        (Duration.zero, 'Intro'),
        (const Duration(minutes: 1, seconds: 23), 'Part two'),
        (const Duration(minutes: 2), 'Outro'),
      ]);
    });

    test('sorts, keeps the first of a shared start, skips bad times', () {
      final chapters = NativeVideoPlayerChapters.parseText(
        '2:00 Later\n0:00 First\n0:00 Duplicate\n1:75 Bad seconds\n3:00',
      );
      expect(chapters.map((c) => c.title), ['First', 'Later']);
    });

    test('handles Windows line endings and empty input', () {
      expect(NativeVideoPlayerChapters.parseText(''), isEmpty);
      expect(
        NativeVideoPlayerChapters.parseText(
          '0:00 A\r\n0:10 B\r\n',
        ).map((c) => c.title),
        ['A', 'B'],
      );
    });
  });

  group('parseVtt', () {
    test('takes cue starts and text, ignores cue ends', () {
      final chapters = NativeVideoPlayerChapters.parseVtt('''WEBVTT

chapter-1
00:00:00.000 --> 00:00:30.000
Intro

chapter-2
00:00:30.000 --> 00:00:40.000
Part <b>two</b>

00:00:45.500 --> 00:01:00.000
Outro
''');
      expect(chapters.map((c) => (c.start, c.title)), [
        (Duration.zero, 'Intro'),
        (const Duration(seconds: 30), 'Part two'),
        (const Duration(seconds: 45, milliseconds: 500), 'Outro'),
      ]);
    });
  });

  group('chapter math', () {
    test('indexAt / chapterAt find the chapter playing at a position', () {
      expect(NativeVideoPlayerChapters.indexAt(_chapters, Duration.zero), 0);
      expect(
        NativeVideoPlayerChapters.chapterAt(
          _chapters,
          const Duration(seconds: 30),
        ),
        _partTwo,
      );
      expect(
        NativeVideoPlayerChapters.chapterAt(
          _chapters,
          const Duration(minutes: 5),
        ),
        _outro,
      );
      expect(
        NativeVideoPlayerChapters.indexAt(const [
          _partTwo,
        ], const Duration(seconds: 10)),
        -1,
      );
      expect(NativeVideoPlayerChapters.indexAt(const [], Duration.zero), -1);
    });

    test('segments cover the bar, one per chapter', () {
      final segments = NativeVideoPlayerChapters.segments(
        _chapters,
        const Duration(seconds: 60),
      );
      expect(segments.map((s) => (s.startFraction, s.endFraction)), [
        (0.0, 0.5),
        (0.5, 0.75),
        (0.75, 1.0),
      ]);
      expect(segments.map((s) => s.chapter), _chapters);
      expect(segments.last.end, const Duration(seconds: 60));
      expect(segments[1].contains(const Duration(seconds: 44)), isTrue);
      expect(segments[1].contains(const Duration(seconds: 45)), isFalse);
    });

    test('segments add an untitled lead-in and drop chapters past the end', () {
      final segments = NativeVideoPlayerChapters.segments(const [
        _partTwo,
        _outro,
      ], const Duration(seconds: 40));
      expect(segments.map((s) => (s.index, s.chapter?.title)), [
        (-1, null),
        (0, 'Part two'),
      ]);
      expect(segments.last.endFraction, 1.0);
    });

    test('segments without chapters or duration', () {
      expect(
        NativeVideoPlayerChapters.segments(
          const [],
          const Duration(seconds: 9),
        ),
        hasLength(1),
      );
      expect(
        NativeVideoPlayerChapters.segments(_chapters, Duration.zero),
        isEmpty,
      );
    });

    test('snapTarget snaps within the threshold, to the nearest start', () {
      const threshold = Duration(seconds: 1);
      Duration? snap(int ms) => NativeVideoPlayerChapters.snapTarget(
        _chapters,
        Duration(milliseconds: ms),
        threshold: threshold,
      );
      expect(snap(29200), const Duration(seconds: 30)); // just before
      expect(snap(30900), const Duration(seconds: 30)); // just after
      expect(snap(28500), isNull); // too far
      expect(snap(44500), const Duration(seconds: 45));
      expect(snap(300), isNull, reason: 'zero is not a snap point');
      expect(
        NativeVideoPlayerChapters.snap(
          _chapters,
          const Duration(seconds: 20),
          threshold: threshold,
        ),
        const Duration(seconds: 20),
      );
    });

    test('snapTarget picks the closer of two nearby starts', () {
      const close = [
        NativeVideoPlayerChapter(start: Duration(seconds: 10), title: 'a'),
        NativeVideoPlayerChapter(start: Duration(seconds: 11), title: 'b'),
      ];
      expect(
        NativeVideoPlayerChapters.snapTarget(
          close,
          const Duration(milliseconds: 10600),
          threshold: const Duration(seconds: 2),
        ),
        const Duration(seconds: 11),
      );
    });
  });

  group('storyboard precache order', () {
    test('imageUrlsAround: the sheet at the position first, then outward', () {
      final storyboard = StoryboardThumbnails.fromUniformGrid(
        spriteUrls: const ['s0', 's1', 's2', 's3', 's4'],
        frameInterval: const Duration(seconds: 1),
        columns: 2,
        frameWidth: 10,
        frameHeight: 10,
        framesPerSprite: 4,
      );
      expect(storyboard.imageUrlsAround(const Duration(seconds: 9), limit: 3), [
        's2',
        's1', // frame 7 is nearer to frame 9 than frame 12
        's3',
      ]);
      expect(storyboard.imageUrlsAround(Duration.zero, limit: 2), ['s0', 's1']);
      expect(storyboard.imageUrlsAround(Duration.zero, limit: 0), isEmpty);
    });
  });

  group('Bunny storyboard from the playlist URL', () {
    test('keeps a query token', () {
      final storyboard = StoryboardThumbnails.bunnyFromPlaylistUrl(
        'https://vz-abc.b-cdn.net/guid/playlist.m3u8?token=t&expires=1',
        duration: const Duration(minutes: 3),
      )!;
      expect(
        storyboard.entries.first.url,
        'https://vz-abc.b-cdn.net/guid/seek/_0.jpg?token=t&expires=1',
      );
      // 90 frames every 2 s, 36 per sheet: 3 sheets.
      expect(storyboard.entries.map((e) => e.url).toSet(), hasLength(3));
    });

    test('keeps a path token', () {
      final storyboard = StoryboardThumbnails.bunnyFromPlaylistUrl(
        'https://vz-abc.b-cdn.net/bcdn_token=t&expires=1&token_path=%2Fguid%2F'
        '/guid/playlist.m3u8',
        duration: const Duration(seconds: 30),
      )!;
      expect(
        storyboard.entries.first.url,
        'https://vz-abc.b-cdn.net/bcdn_token=t&expires=1&token_path=%2Fguid%2F'
        '/guid/seek/_0.jpg',
      );
    });

    test('null without a path', () {
      expect(
        StoryboardThumbnails.bunnyFromPlaylistUrl(
          'https://vz-abc.b-cdn.net',
          duration: const Duration(seconds: 30),
        ),
        isNull,
      );
    });
  });

  group('NativeVideoPlayerProgressBar without a controller', () {
    Widget host(Widget bar) => MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(top: 300),
          child: SizedBox(width: 400, child: bar),
        ),
      ),
    );

    Offset at(WidgetTester tester, double x) =>
        tester.getTopLeft(find.byType(NativeVideoPlayerProgressBar)) +
        Offset(x, 16);

    Future<void> drag(WidgetTester tester, double from, double to) async {
      final gesture = await tester.startGesture(at(tester, from));
      await gesture.moveTo(at(tester, (from + to) / 2));
      await gesture.moveTo(at(tester, to));
      await tester.pump();
      await gesture.up();
      await tester.pump();
    }

    testWidgets('uses the values and onSeek it is given, with callbacks', (
      tester,
    ) async {
      final seeks = <Duration>[];
      final events = <String>[];
      await tester.pumpWidget(
        host(
          NativeVideoPlayerProgressBar(
            position: const Duration(seconds: 10),
            duration: const Duration(seconds: 60),
            chapters: _chapters,
            onSeek: seeks.add,
            hapticFeedback: false,
            onScrubStart: (_) => events.add('start'),
            onScrubEnd: (p) => events.add('end ${p.inSeconds}'),
          ),
        ),
      );
      await drag(tester, 100, 205);
      expect(seeks, [const Duration(seconds: 30)], reason: 'snapped');
      expect(events, ['start', 'end 30']);
    });

    testWidgets('preview, chapter and snap callbacks', (tester) async {
      final previews = <NativeVideoPlayerScrubDetails?>[];
      final chapters = <String?>[];
      final snaps = <String>[];
      await tester.pumpWidget(
        host(
          NativeVideoPlayerProgressBar(
            duration: const Duration(seconds: 60),
            chapters: _chapters,
            onSeek: _ignoreSeek,
            hapticFeedback: false,
            // Drawn elsewhere by the app: no bubble, callbacks still fire.
            showPreview: false,
            onPreviewChanged: previews.add,
            onScrubChapterChanged: (c) => chapters.add(c?.title),
            onSnap: (c) => snaps.add(c.title),
          ),
        ),
      );
      final gesture = await tester.startGesture(at(tester, 100));
      await gesture.moveTo(at(tester, 150));
      await tester.pump();
      await gesture.moveTo(at(tester, 205));
      await tester.pump();
      expect(find.text('Part two'), findsNothing, reason: 'no bubble');
      expect(previews.last?.chapter, _partTwo);
      expect(previews.last?.snapped, isTrue);
      expect(previews.last?.position, const Duration(seconds: 30));
      await gesture.up();
      await tester.pump();
      await tester.pump();
      expect(previews.last, isNull, reason: 'gone after release');
      expect(chapters, ['Intro', 'Part two', null]);
      expect(snaps, ['Part two']);
    });

    testWidgets('showPreview: false shows no bubble', (tester) async {
      await tester.pumpWidget(
        host(
          const NativeVideoPlayerProgressBar(
            duration: Duration(seconds: 60),
            chapters: _chapters,
            showPreview: false,
            onSeek: _ignoreSeek,
          ),
        ),
      );
      final gesture = await tester.startGesture(at(tester, 100));
      await gesture.moveTo(at(tester, 150));
      await gesture.moveTo(at(tester, 205));
      await tester.pump();
      expect(find.text('Part two'), findsNothing);
      expect(find.text('0:30'), findsNothing);
      await gesture.up();
      await tester.pump();
    });

    testWidgets('preview parts can be switched off; a custom builder', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          NativeVideoPlayerProgressBar(
            duration: const Duration(seconds: 60),
            chapters: _chapters,
            onSeek: _ignoreSeek,
            previewStyle: const NativeVideoPlayerScrubPreviewStyle(
              showChapterTitle: false,
              backgroundColor: Colors.black,
              padding: EdgeInsets.all(8),
              arrowSize: Size(8, 6),
            ),
          ),
        ),
      );
      final gesture = await tester.startGesture(at(tester, 100));
      await gesture.moveTo(at(tester, 150));
      await gesture.moveTo(at(tester, 205));
      await tester.pump();
      expect(find.text('Part two'), findsNothing);
      expect(find.text('0:30'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        host(
          NativeVideoPlayerProgressBar(
            duration: const Duration(seconds: 60),
            chapters: _chapters,
            onSeek: _ignoreSeek,
            previewBuilder: (context, details) =>
                Text('custom ${details.chapter?.title} ${details.snapped}'),
          ),
        ),
      );
      final second = await tester.startGesture(at(tester, 100));
      await second.moveTo(at(tester, 150));
      await second.moveTo(at(tester, 205));
      await tester.pump();
      expect(find.text('custom Part two true'), findsOneWidget);
      await second.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a storyboard image that fails to load does not throw', (
      tester,
    ) async {
      final storyboard = StoryboardThumbnails.fromUniformGrid(
        spriteUrls: const ['assets/does-not-exist.jpg'],
        frameInterval: const Duration(seconds: 10),
        columns: 10,
        frameWidth: 160,
        frameHeight: 90,
        framesPerSprite: 60,
      );
      await tester.pumpWidget(
        host(
          NativeVideoPlayerProgressBar(
            duration: const Duration(seconds: 60),
            chapters: _chapters,
            storyboard: storyboard,
            storyboardHeaders: const {'Referer': 'https://example.com'},
            onSeek: _ignoreSeek,
          ),
        ),
      );
      final gesture = await tester.startGesture(at(tester, 100));
      await gesture.moveTo(at(tester, 150));
      await gesture.moveTo(at(tester, 205));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // The frame is gone; title and time still show.
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Part two'), findsOneWidget);
      expect(find.text('0:30'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('a custom image provider builder receives the headers', (
      tester,
    ) async {
      final requested = <(String, Map<String, String>?)>[];
      final storyboard = StoryboardThumbnails.fromUniformGrid(
        spriteUrls: const ['https://cdn.example.com/seek/_0.jpg'],
        frameInterval: const Duration(seconds: 10),
        columns: 10,
        frameWidth: 160,
        frameHeight: 90,
        framesPerSprite: 60,
      );
      await tester.pumpWidget(
        host(
          NativeVideoPlayerProgressBar(
            duration: const Duration(seconds: 60),
            storyboard: storyboard,
            storyboardHeaders: const {'Referer': 'https://huddle.example'},
            storyboardImageProvider: (url, headers) {
              requested.add((url, headers));
              return const AssetImage('assets/does-not-exist.jpg');
            },
            onSeek: _ignoreSeek,
          ),
        ),
      );
      // Precached around the start before any drag.
      await tester.pumpAndSettle();
      expect(requested, isNotEmpty);
      expect(requested.first.$1, 'https://cdn.example.com/seek/_0.jpg');
      expect(requested.first.$2, {'Referer': 'https://huddle.example'});
      expect(tester.takeException(), isNull);
    });
  });

  group('controller', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const methodChannel = MethodChannel('native_video_player');

    late List<MethodCall> calls;
    late NativeVideoPlayerController controller;
    MockStreamHandlerEventSink? viewSink;
    var seq = 0;
    late int controllerId;
    late int viewId;

    setUp(() {
      seq++;
      controllerId = 8800 + seq;
      viewId = 9800 + seq;
      calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        calls.add(call);
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

    Future<void> attach(WidgetTester tester, {Widget? child}) async {
      messenger.setMockStreamHandler(
        EventChannel('native_video_player_controller_$controllerId'),
        MockStreamHandler.inline(onListen: (arguments, events) {}),
      );
      messenger.setMockStreamHandler(
        EventChannel('native_video_player_$viewId'),
        MockStreamHandler.inline(
          onListen: (_, events) {
            viewSink = events;
          },
        ),
      );
      controller = NativeVideoPlayerController(id: controllerId);
      await tester.pumpWidget(child ?? const SizedBox());
      final context = tester.element(find.byType(Directionality).first);
      await controller.onPlatformViewCreated(viewId, context);
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> sendPosition(
      WidgetTester tester,
      int ms, {
      bool isLive = false,
    }) async {
      viewSink!.success({
        'event': 'timeUpdate',
        'position': ms,
        'duration': 60000,
        'bufferedPosition': ms,
        'isBuffering': false,
        'isLive': isLive,
      });
      await tester.pump();
    }

    List<int> seeks() => [
      for (final c in calls.where((c) => c.method == 'seekTo'))
        (c.arguments as Map)['milliseconds'] as int,
    ];

    testWidgets('tracks the current chapter and emits on crossings', (
      tester,
    ) async {
      await attach(
        tester,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(),
        ),
      );
      final emitted = <String?>[];
      final sub = controller.currentChapterStream.listen(
        (c) => emitted.add(c?.title),
      );

      controller.setChapters(const [_outro, _intro, _partTwo]);
      expect(controller.chapters, _chapters, reason: 'sorted');
      expect(controller.currentChapter, _intro);

      await sendPosition(tester, 10000);
      await sendPosition(tester, 31000);
      await sendPosition(tester, 32000);
      await sendPosition(tester, 50000);
      expect(controller.currentChapter, _outro);
      expect(emitted, ['Intro', 'Part two', 'Outro']);

      controller.setChapters(const []);
      expect(controller.currentChapter, isNull);
      await tester.pump();
      expect(emitted.last, isNull);
      // Not awaited: the cancel future never completes in the fake-async
      // zone, which would hang the test.
      unawaited(sub.cancel());
    });

    testWidgets('chapter changes reach control listeners', (tester) async {
      await attach(
        tester,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(),
        ),
      );
      final events = <PlayerControlEvent>[];
      controller.addControlListener((e) {
        if (e.state == PlayerControlState.chapterChanged ||
            e.state == PlayerControlState.chaptersChanged) {
          events.add(e);
        }
      });
      controller.setChapters(_chapters);
      await sendPosition(tester, 31000);
      await sendPosition(tester, 32000); // same chapter: no event
      expect(events.map((e) => e.state), [
        PlayerControlState.chaptersChanged,
        PlayerControlState.chapterChanged,
        PlayerControlState.chapterChanged,
      ]);
      expect(events.map((e) => e.data).toList(), [
        {'count': 3},
        {'index': 0, 'title': 'Intro', 'startMs': 0},
        {'index': 1, 'title': 'Part two', 'startMs': 30000},
      ]);
      expect(controller.currentChapterIndex, 1);
    });

    testWidgets('next / previous chapter', (tester) async {
      await attach(
        tester,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(),
        ),
      );
      controller.setChapters(_chapters);

      // The native player confirms each seek before reporting positions far
      // from its target (the controller drops stale ones until then).
      Future<void> seekDone(int ms) async {
        viewSink!.success({'event': 'seek', 'position': ms});
        await tester.pump();
      }

      await sendPosition(tester, 10000);
      await controller.seekToNextChapter();
      // Reported a hair before the start after the seek: still "next" is 45s.
      await sendPosition(tester, 29900);
      await controller.seekToNextChapter();
      await seekDone(45000);
      await sendPosition(tester, 50000);
      await controller.seekToNextChapter(); // last chapter: nothing
      expect(seeks(), [30000, 45000]);

      // 5 s into Outro: back to its start; within 3 s: to the previous one.
      await controller.seekToPreviousChapter();
      await sendPosition(tester, 46000);
      await controller.seekToPreviousChapter();
      await seekDone(30000);
      await sendPosition(tester, 1000);
      await controller.seekToPreviousChapter();
      expect(seeks(), [30000, 45000, 45000, 30000, 0]);
    });

    testWidgets('load(chapters:) sets them; a different URL clears them', (
      tester,
    ) async {
      await attach(
        tester,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(),
        ),
      );
      // Set before the first load: kept.
      controller.setChapters(_chapters);
      await controller.load(url: 'https://example.com/a.m3u8');
      expect(controller.chapters, _chapters);

      // Same URL again (eviction re-load path): kept.
      await controller.load(url: 'https://example.com/a.m3u8', force: true);
      expect(controller.chapters, _chapters);

      await controller.load(url: 'https://example.com/b.m3u8', force: true);
      expect(controller.chapters, isEmpty);

      await controller.load(
        url: 'https://example.com/c.m3u8',
        chapters: const [_partTwo],
        force: true,
      );
      expect(controller.chapters, const [_partTwo]);

      // A guarded (no-op) load still applies the chapters passed.
      await controller.load(
        url: 'https://example.com/c.m3u8',
        chapters: _chapters,
      );
      expect(controller.chapters, _chapters);
    });

    testWidgets('chapters are hidden while live', (tester) async {
      await attach(
        tester,
        child: const Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(),
        ),
      );
      controller.setChapters(_chapters);
      await sendPosition(tester, 31000);
      expect(controller.currentChapter, _partTwo);

      await sendPosition(tester, 32000, isLive: true);
      expect(controller.chapters, isEmpty);
      expect(controller.currentChapter, isNull);
      await controller.seekToNextChapter();
      expect(seeks(), isEmpty);
    });

    group('NativeVideoPlayerProgressBar', () {
      late List<String> haptics;

      Widget app() => MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(top: 300),
            child: SizedBox(
              width: 400,
              child: Builder(
                builder: (context) =>
                    NativeVideoPlayerProgressBar(controller: controller),
              ),
            ),
          ),
        ),
      );

      Future<void> pumpBar(WidgetTester tester) async {
        haptics = [];
        messenger.setMockMethodCallHandler(SystemChannels.platform, (
          call,
        ) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments as String);
          }
          return null;
        });
        addTearDown(
          () =>
              messenger.setMockMethodCallHandler(SystemChannels.platform, null),
        );
        // The widget tree goes in before the controller attaches, so the
        // bar is built with this test's controller.
        messenger.setMockStreamHandler(
          EventChannel('native_video_player_controller_$controllerId'),
          MockStreamHandler.inline(onListen: (arguments, events) {}),
        );
        messenger.setMockStreamHandler(
          EventChannel('native_video_player_$viewId'),
          MockStreamHandler.inline(
            onListen: (_, events) {
              viewSink = events;
            },
          ),
        );
        controller = NativeVideoPlayerController(id: controllerId);
        await tester.pumpWidget(app());
        final context = tester.element(find.byType(SizedBox).first);
        await controller.onPlatformViewCreated(viewId, context);
        await tester.pump(const Duration(milliseconds: 100));
        controller.setChapters(_chapters);
        await sendPosition(tester, 0);
      }

      Offset at(WidgetTester tester, double x) =>
          tester.getTopLeft(find.byType(NativeVideoPlayerProgressBar)) +
          Offset(x, 16);

      testWidgets('drag near a chapter start snaps, ticks and seeks there', (
        tester,
      ) async {
        await pumpBar(tester);
        // 400 px for 60 s: 30 s (Part two) is at x = 200; 8 px = 1.2 s.
        final gesture = await tester.startGesture(at(tester, 100));
        await gesture.moveTo(at(tester, 150));
        await tester.pump();
        expect(find.text('Intro'), findsOneWidget, reason: 'preview title');
        expect(haptics, isEmpty);

        await gesture.moveTo(at(tester, 205)); // 30.75 s, within 8 px
        await tester.pump();
        expect(find.text('Part two'), findsOneWidget);
        expect(find.text('0:30'), findsOneWidget);
        expect(haptics, ['HapticFeedbackType.selectionClick']);

        await gesture.moveTo(at(tester, 203)); // still snapped: no new tick
        await tester.pump();
        expect(haptics, hasLength(1));

        await gesture.up();
        await tester.pump();
        expect(seeks(), [30000]);
        await tester.pump(const Duration(milliseconds: 200));
        expect(find.text('Part two'), findsNothing, reason: 'preview hides');
      });

      testWidgets('a drag away from chapter starts seeks to the finger', (
        tester,
      ) async {
        await pumpBar(tester);
        final gesture = await tester.startGesture(at(tester, 100));
        await gesture.moveTo(at(tester, 220)); // 33 s, 20 px from 30 s
        await tester.pump();
        await gesture.up();
        await tester.pump();
        expect(seeks(), [33000]);
        expect(haptics, isEmpty);
      });

      testWidgets('keeps the overlay up while scrubbing, then lets go', (
        tester,
      ) async {
        await pumpBar(tester);
        final locks = <bool>[];
        final sub = controller.isOverlayLockedStream.listen(locks.add);
        final gesture = await tester.startGesture(at(tester, 100));
        await gesture.moveTo(at(tester, 150));
        await tester.pump();
        expect(controller.isOverlayLocked, isTrue);
        await gesture.up();
        await tester.pump();
        expect(controller.isOverlayLocked, isFalse);
        expect(locks, [true, false]);

        // The app's own lock survives a scrub.
        controller.lockOverlay();
        final again = await tester.startGesture(at(tester, 100));
        await again.moveTo(at(tester, 150));
        await again.up();
        await tester.pump();
        expect(controller.isOverlayLocked, isTrue);
        controller.unlockOverlay();
        expect(controller.isOverlayLocked, isFalse);
        unawaited(sub.cancel());
        await tester.pump(const Duration(seconds: 2));
      });

      testWidgets('tap seeks', (tester) async {
        await pumpBar(tester);
        await tester.tapAt(at(tester, 100));
        await tester.pump();
        expect(seeks(), [15000]);
      });

      testWidgets('no snapping for live', (tester) async {
        await pumpBar(tester);
        await sendPosition(tester, 0, isLive: true);
        final gesture = await tester.startGesture(at(tester, 100));
        await gesture.moveTo(at(tester, 205));
        await tester.pump();
        await gesture.up();
        await tester.pump();
        expect(seeks(), [30750]);
        expect(haptics, isEmpty);
      });
    });
  });
}

void _ignoreSeek(Duration _) {}
