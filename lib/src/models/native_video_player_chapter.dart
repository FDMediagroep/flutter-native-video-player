import 'package:flutter/painting.dart' show ImageProvider;
import 'package:flutter/foundation.dart';

/// One chapter of a video: where it starts and what it is called.
///
/// A chapter runs until the next chapter starts (the last one until the end
/// of the video). Set them with [NativeVideoPlayerController.setChapters]
/// or `load(chapters: ...)`; parse them from a description with
/// [NativeVideoPlayerChapters.parseText] or from a WebVTT chapters track
/// with [NativeVideoPlayerChapters.parseVtt].
@immutable
class NativeVideoPlayerChapter {
  const NativeVideoPlayerChapter({
    required this.start,
    required this.title,
    this.thumbnail,
  });

  /// Where the chapter starts, from the beginning of the video.
  final Duration start;

  /// The chapter title, shown in the scrub preview while dragging.
  final String title;

  /// Optional image for the chapter, shown in the scrub preview when there
  /// is no storyboard thumbnail for the position.
  final ImageProvider? thumbnail;

  @override
  bool operator ==(Object other) =>
      other is NativeVideoPlayerChapter &&
      other.start == start &&
      other.title == title &&
      other.thumbnail == thumbnail;

  @override
  int get hashCode => Object.hash(start, title, thumbnail);

  @override
  String toString() =>
      'NativeVideoPlayerChapter(${start.inMilliseconds}ms, $title)';
}
