import 'package:flutter/material.dart';

import '../models/native_video_player_chapter.dart';
import '../subtitles/storyboard_thumbnails.dart';

/// Turns a storyboard image URL into an [ImageProvider]. Swap it to load
/// sprites through your own cache (e.g. `CachedNetworkImageProvider`) or
/// with signed URLs.
typedef StoryboardImageProviderBuilder =
    ImageProvider Function(String url, Map<String, String>? headers);

/// What the seek bar is pointing at while the viewer drags (or hovers),
/// handed to a custom [NativeVideoPlayerProgressBar.previewBuilder].
@immutable
class NativeVideoPlayerScrubDetails {
  const NativeVideoPlayerScrubDetails({
    required this.position,
    required this.duration,
    this.chapter,
    this.chapterIndex = -1,
    this.thumbnail,
    this.snapped = false,
  });

  /// The position under the finger, after snapping.
  final Duration position;

  /// The video's duration.
  final Duration duration;

  /// The chapter at [position], if the video has chapters.
  final NativeVideoPlayerChapter? chapter;

  /// Index of [chapter] in the chapter list, -1 without one.
  final int chapterIndex;

  /// The storyboard frame for [position], if a storyboard was given.
  final StoryboardThumbnail? thumbnail;

  /// Whether [position] snapped to the start of [chapter].
  final bool snapped;
}

/// How the scrub preview bubble looks. The defaults are YouTube's: a white
/// bordered frame with the chapter title and time below it, straight on
/// the video. Give it a [backgroundColor], [padding] and [arrowSize] for a
/// tooltip-style bubble instead.
@immutable
class NativeVideoPlayerScrubPreviewStyle {
  const NativeVideoPlayerScrubPreviewStyle({
    this.showThumbnail = true,
    this.showChapterTitle = true,
    this.showTime = true,
    this.thumbnailWidth = 160,
    this.thumbnailAspectRatio = 16 / 9,
    this.thumbnailBorder = const Border.fromBorderSide(
      BorderSide(color: Colors.white, width: 2),
    ),
    this.thumbnailBorderRadius = const BorderRadius.all(Radius.circular(10)),
    this.thumbnailPlaceholderColor = const Color(0x66000000),
    this.titleStyle,
    this.timeStyle,
    this.maxTitleLines = 2,
    this.spacing = 4,
    this.backgroundColor,
    this.padding = EdgeInsets.zero,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
    this.shadows = const [],
    this.arrowSize,
    this.gapToBar = 8,
    this.timeFormatter,
    this.animationDuration = const Duration(milliseconds: 180),
    this.animationCurve = Curves.fastOutSlowIn,
  });

  /// Which parts to show. A preview with nothing to show stays hidden.
  final bool showThumbnail;
  final bool showChapterTitle;
  final bool showTime;

  /// Width of the frame; the title wraps within it.
  final double thumbnailWidth;

  /// Aspect ratio of frames that are whole images (no sprite region) and
  /// of chapter thumbnails.
  final double thumbnailAspectRatio;

  final BoxBorder? thumbnailBorder;
  final BorderRadius thumbnailBorderRadius;

  /// Fill of the frame while its image is still loading.
  final Color thumbnailPlaceholderColor;

  /// Text styles; null is white with a soft shadow (title semi-bold, time
  /// bold with tabular figures).
  final TextStyle? titleStyle;
  final TextStyle? timeStyle;
  final int maxTitleLines;

  /// Space between frame, title and time.
  final double spacing;

  /// Bubble fill behind everything; null draws no bubble.
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;
  final BorderRadius borderRadius;
  final List<BoxShadow> shadows;

  /// Size of the arrow under the bubble pointing at the finger (width,
  /// height), in [backgroundColor]. Null draws none.
  final Size? arrowSize;

  /// Distance between the bubble (or its arrow) and the bar.
  final double gapToBar;

  /// Formats the time; null is `m:ss`, or `h:mm:ss` from an hour on.
  final String Function(Duration)? timeFormatter;

  /// The bubble scales and fades in and out with these, and the chapter
  /// title cross-fades when the finger moves to another chapter.
  final Duration animationDuration;
  final Curve animationCurve;

  NativeVideoPlayerScrubPreviewStyle copyWith({
    bool? showThumbnail,
    bool? showChapterTitle,
    bool? showTime,
    double? thumbnailWidth,
    double? thumbnailAspectRatio,
    BoxBorder? thumbnailBorder,
    BorderRadius? thumbnailBorderRadius,
    Color? thumbnailPlaceholderColor,
    TextStyle? titleStyle,
    TextStyle? timeStyle,
    int? maxTitleLines,
    double? spacing,
    Color? backgroundColor,
    EdgeInsetsGeometry? padding,
    BorderRadius? borderRadius,
    List<BoxShadow>? shadows,
    Size? arrowSize,
    double? gapToBar,
    String Function(Duration)? timeFormatter,
    Duration? animationDuration,
    Curve? animationCurve,
  }) => NativeVideoPlayerScrubPreviewStyle(
    showThumbnail: showThumbnail ?? this.showThumbnail,
    showChapterTitle: showChapterTitle ?? this.showChapterTitle,
    showTime: showTime ?? this.showTime,
    thumbnailWidth: thumbnailWidth ?? this.thumbnailWidth,
    thumbnailAspectRatio: thumbnailAspectRatio ?? this.thumbnailAspectRatio,
    thumbnailBorder: thumbnailBorder ?? this.thumbnailBorder,
    thumbnailBorderRadius: thumbnailBorderRadius ?? this.thumbnailBorderRadius,
    thumbnailPlaceholderColor:
        thumbnailPlaceholderColor ?? this.thumbnailPlaceholderColor,
    titleStyle: titleStyle ?? this.titleStyle,
    timeStyle: timeStyle ?? this.timeStyle,
    maxTitleLines: maxTitleLines ?? this.maxTitleLines,
    spacing: spacing ?? this.spacing,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    padding: padding ?? this.padding,
    borderRadius: borderRadius ?? this.borderRadius,
    shadows: shadows ?? this.shadows,
    arrowSize: arrowSize ?? this.arrowSize,
    gapToBar: gapToBar ?? this.gapToBar,
    timeFormatter: timeFormatter ?? this.timeFormatter,
    animationDuration: animationDuration ?? this.animationDuration,
    animationCurve: animationCurve ?? this.animationCurve,
  );
}

/// The bubble above a seek bar while scrubbing: a storyboard frame (or the
/// chapter's own thumbnail), the chapter title and the time.
///
/// [NativeVideoPlayerProgressBar] shows it by default; use it directly in
/// custom controls that draw their own bar. An image that fails to load
/// (bad URL, 403, offline) is left out; it never throws.
class NativeVideoPlayerScrubPreview extends StatelessWidget {
  const NativeVideoPlayerScrubPreview({
    super.key,
    required this.details,
    this.style = const NativeVideoPlayerScrubPreviewStyle(),
    this.imageHeaders,
    this.imageProviderBuilder,
  });

  final NativeVideoPlayerScrubDetails details;
  final NativeVideoPlayerScrubPreviewStyle style;

  /// HTTP headers for storyboard images (e.g. a `Referer` for a CDN with
  /// hotlink protection).
  final Map<String, String>? imageHeaders;

  /// Builds the provider for storyboard images; null uses
  /// [defaultImageProvider].
  final StoryboardImageProviderBuilder? imageProviderBuilder;

  /// `NetworkImage` (with [headers]) for http(s) URLs, `AssetImage`
  /// otherwise.
  static ImageProvider defaultImageProvider(
    String url,
    Map<String, String>? headers,
  ) => url.startsWith('http://') || url.startsWith('https://')
      ? NetworkImage(url, headers: headers)
      : AssetImage(url);

  /// `m:ss`, or `h:mm:ss` from an hour on.
  static String formatDuration(Duration d) {
    if (d.isNegative) return '-${formatDuration(-d)}';
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0
        ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds'
        : '$minutes:$seconds';
  }

  /// Whether [style] leaves anything to show for [details].
  static bool hasContent(
    NativeVideoPlayerScrubDetails details,
    NativeVideoPlayerScrubPreviewStyle style,
  ) =>
      style.showTime ||
      (style.showChapterTitle && details.chapter != null) ||
      (style.showThumbnail &&
          (details.thumbnail != null || details.chapter?.thumbnail != null));

  @override
  Widget build(BuildContext context) {
    const shadow = [Shadow(blurRadius: 6)];
    final titleStyle =
        style.titleStyle ??
        const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          shadows: shadow,
        );
    final timeStyle =
        style.timeStyle ??
        const TextStyle(
          color: Colors.white,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
          shadows: shadow,
        );
    final duration = style.animationDuration;
    final chapter = style.showChapterTitle ? details.chapter : null;

    final children = <Widget>[
      if (style.showThumbnail) ?_frame(),
      if (chapter != null)
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: style.thumbnailWidth),
          child: AnimatedSwitcher(
            duration: duration,
            switchInCurve: style.animationCurve,
            switchOutCurve: style.animationCurve,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.bottomCenter,
              children: [...previous, ?current],
            ),
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: const Offset(0, 0.35),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: Text(
              chapter.title,
              key: ValueKey((details.chapterIndex, chapter.title)),
              maxLines: style.maxTitleLines,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: titleStyle,
            ),
          ),
        ),
      if (style.showTime)
        Text(
          (style.timeFormatter ?? formatDuration)(details.position),
          style: timeStyle,
        ),
    ];

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      spacing: style.spacing,
      children: children,
    );
    content = AnimatedSize(
      duration: duration,
      curve: style.animationCurve,
      alignment: Alignment.bottomCenter,
      child: content,
    );
    if (style.backgroundColor != null || style.padding != EdgeInsets.zero) {
      content = DecoratedBox(
        decoration: BoxDecoration(
          color: style.backgroundColor,
          borderRadius: style.borderRadius,
          boxShadow: style.shadows,
        ),
        child: Padding(padding: style.padding, child: content),
      );
    }
    return content;
  }

  Widget? _frame() {
    final thumbnail = details.thumbnail;
    if (thumbnail != null) {
      final provider = (imageProviderBuilder ?? defaultImageProvider)(
        thumbnail.url,
        imageHeaders,
      );
      return _PreviewFrame(
        key: const ValueKey('storyboard'),
        image: provider,
        region: thumbnail.region,
        style: style,
      );
    }
    final chapterImage = details.chapter?.thumbnail;
    if (chapterImage != null) {
      return _PreviewFrame(
        key: const ValueKey('chapter'),
        image: chapterImage,
        style: style,
      );
    }
    return null;
  }
}

/// One frame: a whole image, or a [region] cut out of a sprite sheet.
/// Shows a placeholder while loading and disappears when loading fails.
class _PreviewFrame extends StatelessWidget {
  const _PreviewFrame({
    super.key,
    required this.image,
    required this.style,
    this.region,
  });

  final ImageProvider image;
  final Rect? region;
  final NativeVideoPlayerScrubPreviewStyle style;

  @override
  Widget build(BuildContext context) {
    final width = style.thumbnailWidth;
    final region = this.region;
    final scale = region == null ? 1.0 : width / region.width;
    final height = region == null
        ? width / style.thumbnailAspectRatio
        : region.height * scale;

    Widget box({required Widget? child, Color? color}) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        border: style.thumbnailBorder,
        borderRadius: style.thumbnailBorderRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );

    return Image(
      image: image,
      // Keep the last frame while the next sprite sheet loads.
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      fit: region == null ? BoxFit.cover : null,
      errorBuilder: (context, error, stackTrace) {
        // Forget the failure, so the next scrub asks again: a 403 or a
        // dropped connection must not lose the previews for the whole
        // video. This one leaves the frame out.
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => PaintingBinding.instance.imageCache.evict(image),
        );
        return const SizedBox.shrink();
      },
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (frame == null) {
          return box(child: null, color: style.thumbnailPlaceholderColor);
        }
        if (region == null) {
          return box(child: SizedBox.expand(child: child));
        }
        return box(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: Transform.translate(
              offset: Offset(-region.left * scale, -region.top * scale),
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.topLeft,
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
