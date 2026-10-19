import 'package:flutter/foundation.dart';

import '../models/native_video_player_chapter.dart';
import '../subtitles/subtitle_loader.dart';
import '../subtitles/subtitle_parser.dart';

/// One stretch of a chapter seek bar: a chapter, or the untitled stretch
/// before the first chapter when that does not start at zero.
@immutable
class NativeVideoPlayerChapterSegment {
  const NativeVideoPlayerChapterSegment({
    required this.index,
    required this.chapter,
    required this.start,
    required this.end,
    required this.startFraction,
    required this.endFraction,
  });

  /// Index of [chapter] in the chapter list, or -1 for the untitled stretch
  /// before the first chapter.
  final int index;

  /// The chapter this segment shows, or null for the untitled stretch
  /// before the first chapter (and for a bar without chapters).
  final NativeVideoPlayerChapter? chapter;

  final Duration start;
  final Duration end;

  /// [start] and [end] as fractions (0..1) of the video's duration, ready
  /// to multiply with the bar's width.
  final double startFraction;
  final double endFraction;

  /// Whether [position] falls in this segment (start inclusive).
  bool contains(Duration position) => position >= start && position < end;

  @override
  bool operator ==(Object other) =>
      other is NativeVideoPlayerChapterSegment &&
      other.index == index &&
      other.chapter == chapter &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(index, chapter, start, end);

  @override
  String toString() =>
      'NativeVideoPlayerChapterSegment($index, '
      '${start.inMilliseconds}-${end.inMilliseconds}ms, ${chapter?.title})';
}

/// Parsing and seek-bar math for [NativeVideoPlayerChapter]s.
///
/// Everything [NativeVideoPlayerProgressBar] does with chapters is here as
/// plain functions, so custom controls can draw their own segmented bar and
/// snap to chapter starts the same way.
abstract final class NativeVideoPlayerChapters {
  /// `1:23`, `01:23`, `1:02:03`; seconds always have two digits.
  static final RegExp _timestamp = RegExp(r'(?:(\d{1,2}):)?(\d{1,3}):(\d{2})');

  /// A timestamp at the start of a line, optionally after a bullet and in
  /// brackets, then a separator and the title: `0:00 Intro`,
  /// `- (1:23) - Part two`, `[1:02:03] | Outro`.
  static final RegExp _leading = RegExp(
    r'^[\s\-–—•*·▶►]*[\[(]?(' +
        _timestamp.pattern +
        r')[\])]?\s*[-–—:|.)•]*\s*(.*)$',
  );

  /// A title followed by the timestamp at the end of a line:
  /// `Intro - 0:00`, `Part two (1:23)`.
  static final RegExp _trailing = RegExp(
    r'^[\s\-–—•*·▶►]*(.*?)[\s\-–—:|•]*[\[(]?(' +
        _timestamp.pattern +
        r')[\])]?\s*$',
  );

  /// Parses the chapter list most videos put in their description, one
  /// chapter per line with the timestamp first or last:
  ///
  /// ```text
  /// 0:00 Intro
  /// 1:23 - Setting up
  /// 12:05 Outro
  /// ```
  ///
  /// Lines without a timestamp at their start or end are skipped, so a whole
  /// description can go in. The result is sorted by start; when two lines
  /// share a start, the first one wins.
  static List<NativeVideoPlayerChapter> parseText(String text) {
    final chapters = <NativeVideoPlayerChapter>[];
    for (final rawLine in text.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      Duration? start;
      String? title;
      final leading = _leading.firstMatch(line);
      if (leading != null) {
        start = _parseTimestamp(leading.group(1)!);
        title = leading.group(5);
      }
      if (start == null || title == null || title.trim().isEmpty) {
        final trailing = _trailing.firstMatch(line);
        if (trailing != null) {
          start = _parseTimestamp(trailing.group(2)!);
          title = trailing.group(1);
        }
      }
      title = title?.trim();
      if (start == null || title == null || title.isEmpty) continue;
      chapters.add(NativeVideoPlayerChapter(start: start, title: title));
    }
    return normalize(chapters);
  }

  /// Parses a WebVTT chapters track (`<track kind="chapters">`): each cue's
  /// start is a chapter start and its text the title. Cue ends are ignored;
  /// a chapter runs until the next one starts.
  static List<NativeVideoPlayerChapter> parseVtt(String content) {
    final cues = SubtitleParser.parse(content, format: SubtitleFormat.vtt);
    return normalize([
      for (final cue in cues)
        NativeVideoPlayerChapter(start: cue.start, title: cue.lines.join(' ')),
    ]);
  }

  /// Downloads and parses a WebVTT chapters track from [url], sending
  /// [headers]. Throws when the download fails (and on the web, where URL
  /// loading is unsupported).
  static Future<List<NativeVideoPlayerChapter>> fromVttUrl(
    String url, {
    Map<String, String>? headers,
  }) async {
    return parseVtt(await SubtitleLoader.loadUrl(url, headers: headers));
  }

  /// Sorts [chapters] by start, drops negative starts and keeps the first
  /// chapter of any that share a start. Every function here expects a list
  /// in this shape; the controller normalizes what it is given.
  static List<NativeVideoPlayerChapter> normalize(
    Iterable<NativeVideoPlayerChapter> chapters,
  ) {
    final sorted = chapters.where((c) => !c.start.isNegative).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    final result = <NativeVideoPlayerChapter>[];
    for (final chapter in sorted) {
      if (result.isNotEmpty && result.last.start == chapter.start) continue;
      result.add(chapter);
    }
    return List.unmodifiable(result);
  }

  /// Index of the chapter playing at [position]: the last one that starts
  /// at or before it. -1 before the first chapter or without chapters.
  static int indexAt(
    List<NativeVideoPlayerChapter> chapters,
    Duration position,
  ) {
    var low = 0;
    var high = chapters.length - 1;
    var match = -1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (chapters[mid].start <= position) {
        match = mid;
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return match;
  }

  /// The chapter playing at [position], or null (see [indexAt]).
  static NativeVideoPlayerChapter? chapterAt(
    List<NativeVideoPlayerChapter> chapters,
    Duration position,
  ) {
    final index = indexAt(chapters, position);
    return index == -1 ? null : chapters[index];
  }

  /// Splits a bar for a video of [duration] into one segment per chapter.
  ///
  /// Chapters starting at or after [duration] are left out. When the first
  /// chapter starts after zero, an untitled segment (index -1) covers the
  /// stretch before it. Without chapters this is one untitled segment for
  /// the whole bar; with an unknown (zero) duration it is empty.
  static List<NativeVideoPlayerChapterSegment> segments(
    List<NativeVideoPlayerChapter> chapters,
    Duration duration,
  ) {
    if (duration <= Duration.zero) return const [];
    final total = duration.inMicroseconds;
    double fraction(Duration d) => d.inMicroseconds / total;

    final starts = <(int, NativeVideoPlayerChapter?, Duration)>[];
    if (chapters.isEmpty || chapters.first.start > Duration.zero) {
      starts.add((-1, null, Duration.zero));
    }
    for (var i = 0; i < chapters.length; i++) {
      if (chapters[i].start >= duration) break;
      starts.add((i, chapters[i], chapters[i].start));
    }

    return [
      for (var i = 0; i < starts.length; i++)
        NativeVideoPlayerChapterSegment(
          index: starts[i].$1,
          chapter: starts[i].$2,
          start: starts[i].$3,
          end: i + 1 < starts.length ? starts[i + 1].$3 : duration,
          startFraction: fraction(starts[i].$3),
          endFraction: i + 1 < starts.length ? fraction(starts[i + 1].$3) : 1,
        ),
    ];
  }

  /// The chapter start a drag at [position] should snap to: the nearest
  /// chapter start within [threshold] of it, or null when none is that
  /// close. A start at zero is not a snap point (there is no gap to land
  /// on there).
  ///
  /// A seek bar usually derives [threshold] from a distance in pixels,
  /// `duration * snapDistance / barWidth`, so snapping feels the same on any
  /// bar width.
  static Duration? snapTarget(
    List<NativeVideoPlayerChapter> chapters,
    Duration position, {
    required Duration threshold,
  }) {
    if (chapters.isEmpty || threshold <= Duration.zero) return null;
    // Only the chapters on either side of the position can be nearest.
    final index = indexAt(chapters, position);
    Duration? best;
    for (final i in [index, index + 1]) {
      if (i < 0 || i >= chapters.length) continue;
      final start = chapters[i].start;
      if (start <= Duration.zero) continue;
      final distance = (start - position).abs();
      if (distance > threshold) continue;
      if (best == null || distance < (best - position).abs()) best = start;
    }
    return best;
  }

  /// [position], moved to the nearest chapter start when it is within
  /// [threshold] of one (see [snapTarget]).
  static Duration snap(
    List<NativeVideoPlayerChapter> chapters,
    Duration position, {
    required Duration threshold,
  }) => snapTarget(chapters, position, threshold: threshold) ?? position;

  static Duration? _parseTimestamp(String raw) {
    final match = _timestamp.matchAsPrefix(raw);
    if (match == null || match.end != raw.length) return null;
    final hours = match.group(1) == null ? null : int.parse(match.group(1)!);
    final minutes = int.parse(match.group(2)!);
    final seconds = int.parse(match.group(3)!);
    if (seconds >= 60 || (hours != null && minutes >= 60)) return null;
    return Duration(hours: hours ?? 0, minutes: minutes, seconds: seconds);
  }
}
