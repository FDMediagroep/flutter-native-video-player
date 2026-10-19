import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/native_video_player_controller.dart';
import '../models/native_video_player_chapter.dart';
import '../subtitles/storyboard_thumbnails.dart';
import 'native_video_player_chapters.dart';
import 'native_video_player_scrub_preview.dart';

/// How a [NativeVideoPlayerProgressBar] looks.
///
/// The defaults are YouTube's: a thin bar where only the chapter under the
/// finger grows. For a bar that thickens as a whole while you touch it and
/// a thumb that only shows then, set [expandedBarHeight], [thumbRadius] 0
/// and [expandedThumbRadius].
@immutable
class NativeVideoPlayerProgressBarStyle {
  const NativeVideoPlayerProgressBarStyle({
    this.height = 32,
    this.barHeight = 3,
    this.expandedBarHeight,
    this.activeSegmentHeight = 6,
    this.chapterGap = 2,
    this.roundedCaps = true,
    this.thumbRadius = 6,
    this.expandedThumbRadius = 8,
    this.playedColor,
    this.bufferedColor,
    this.backgroundColor,
    this.thumbColor,
    this.expandDuration = const Duration(milliseconds: 150),
    this.collapseDelay = Duration.zero,
    this.snapPulse = true,
  });

  /// Height of the touch area; the bar is centered in it.
  final double height;

  /// Thickness of the bar at rest.
  final double barHeight;

  /// Thickness of the whole bar while touched or hovered; null keeps it at
  /// [barHeight] (only the active segment grows).
  final double? expandedBarHeight;

  /// Thickness of the segment under the finger or mouse.
  final double activeSegmentHeight;

  /// Gap between chapter segments, in logical pixels.
  final double chapterGap;

  /// Whether segment ends are rounded.
  final bool roundedCaps;

  /// Thumb radius at rest (0 hides it) and while touched.
  final double thumbRadius;
  final double expandedThumbRadius;

  /// Colors; null takes them from the [SliderTheme] (active, secondary
  /// active and inactive track, thumb), then the color scheme.
  final Color? playedColor;
  final Color? bufferedColor;
  final Color? backgroundColor;
  final Color? thumbColor;

  /// How long growing and shrinking takes.
  final Duration expandDuration;

  /// How long the bar stays expanded after the finger lifts.
  final Duration collapseDelay;

  /// Whether the thumb pulses when the drag snaps to a chapter start.
  final bool snapPulse;

  NativeVideoPlayerProgressBarStyle copyWith({
    double? height,
    double? barHeight,
    double? expandedBarHeight,
    double? activeSegmentHeight,
    double? chapterGap,
    bool? roundedCaps,
    double? thumbRadius,
    double? expandedThumbRadius,
    Color? playedColor,
    Color? bufferedColor,
    Color? backgroundColor,
    Color? thumbColor,
    Duration? expandDuration,
    Duration? collapseDelay,
    bool? snapPulse,
  }) => NativeVideoPlayerProgressBarStyle(
    height: height ?? this.height,
    barHeight: barHeight ?? this.barHeight,
    expandedBarHeight: expandedBarHeight ?? this.expandedBarHeight,
    activeSegmentHeight: activeSegmentHeight ?? this.activeSegmentHeight,
    chapterGap: chapterGap ?? this.chapterGap,
    roundedCaps: roundedCaps ?? this.roundedCaps,
    thumbRadius: thumbRadius ?? this.thumbRadius,
    expandedThumbRadius: expandedThumbRadius ?? this.expandedThumbRadius,
    playedColor: playedColor ?? this.playedColor,
    bufferedColor: bufferedColor ?? this.bufferedColor,
    backgroundColor: backgroundColor ?? this.backgroundColor,
    thumbColor: thumbColor ?? this.thumbColor,
    expandDuration: expandDuration ?? this.expandDuration,
    collapseDelay: collapseDelay ?? this.collapseDelay,
    snapPulse: snapPulse ?? this.snapPulse,
  );
}

/// A seek bar for custom controls, with chapters like YouTube's.
///
/// - The track splits into one segment per chapter, with a small gap at
///   each chapter start. The segment under the finger (or mouse) grows.
/// - While dragging, a preview bubble above the bar shows the storyboard
///   frame (when [storyboard] is given), the chapter title and the time.
/// - A drag that comes within [snapDistance] pixels of a chapter start
///   snaps to it, with a light haptic tick. Releasing seeks there.
///
/// Without chapters it is a plain seek bar with buffered range and scrub
/// preview. It reads position, duration, buffered range, live state and
/// chapters from [controller]; pass [position], [duration],
/// [bufferedPosition], [isLive] or [chapters] to override them (for
/// example while casting, or for an audio player without a controller),
/// and [onSeek] to seek some other way. Live streams show no chapters and
/// no preview.
///
/// ```dart
/// NativeVideoPlayerProgressBar(
///   controller: controller,
///   storyboard: storyboard, // optional scrub thumbnails
///   showPreview: controller.isFullScreen,
/// )
/// ```
class NativeVideoPlayerProgressBar extends StatefulWidget {
  const NativeVideoPlayerProgressBar({
    super.key,
    this.controller,
    this.position,
    this.duration,
    this.bufferedPosition,
    this.isLive,
    this.chapters,
    this.onSeek,
    this.storyboard,
    this.storyboardHeaders,
    this.storyboardImageProvider,
    this.storyboardPrecacheLimit = 4,
    this.snapToChapters = true,
    this.snapDistance = 8,
    this.hapticFeedback = true,
    this.showPreview = true,
    this.showBuffered = true,
    this.holdOverlayWhileScrubbing = true,
    this.style = const NativeVideoPlayerProgressBarStyle(),
    this.previewStyle = const NativeVideoPlayerScrubPreviewStyle(),
    this.previewBuilder,
    this.onScrubStart,
    this.onScrubUpdate,
    this.onScrubEnd,
    this.onScrubChapterChanged,
    this.onSnap,
    this.onPreviewChanged,
    this.semanticsLabel,
  }) : assert(
         controller != null || duration != null,
         'Pass a controller, or at least a duration (and a position)',
       );

  /// Where the values come from and what seeks; optional when they are
  /// all passed in (see below) together with [onSeek].
  final NativeVideoPlayerController? controller;

  /// Overrides for the controller's values.
  final Duration? position;
  final Duration? duration;
  final Duration? bufferedPosition;
  final bool? isLive;

  /// Chapters to show instead of the controller's
  /// [NativeVideoPlayerController.chapters]. Sorted for you.
  final List<NativeVideoPlayerChapter>? chapters;

  /// Seeks on release (and tap) instead of `controller.seekTo`.
  final FutureOr<void> Function(Duration position)? onSeek;

  /// Scrub-preview frames shown in the bubble.
  final StoryboardThumbnails? storyboard;

  /// HTTP headers for storyboard images (e.g. a `Referer`).
  final Map<String, String>? storyboardHeaders;

  /// Builds the provider for storyboard images, e.g. to go through your
  /// own image cache; null uses
  /// [NativeVideoPlayerScrubPreview.defaultImageProvider].
  final StoryboardImageProviderBuilder? storyboardImageProvider;

  /// How many storyboard images around the playing position (and, while
  /// scrubbing, around the finger) are loaded ahead, so the frame is there
  /// when the bubble shows. Flutter's image cache bounds the memory; 0
  /// turns precaching off. Load failures are ignored.
  final int storyboardPrecacheLimit;

  /// Whether a drag near a chapter start snaps to it.
  final bool snapToChapters;

  /// How close, in logical pixels, a drag must come to a chapter start to
  /// snap to it.
  final double snapDistance;

  /// Whether snapping gives a light haptic tick
  /// ([HapticFeedback.selectionClick]).
  final bool hapticFeedback;

  /// Whether to show the preview bubble while scrubbing; turn it off for a
  /// small inline player, for example. Never shown for live.
  final bool showPreview;

  /// Whether to draw the buffered range (never for live).
  final bool showBuffered;

  /// Whether the player's overlay stays up while the viewer scrubs (see
  /// [NativeVideoPlayerController.holdOverlay]); its hide timer starts
  /// over after the release. Needs [controller].
  final bool holdOverlayWhileScrubbing;

  final NativeVideoPlayerProgressBarStyle style;
  final NativeVideoPlayerScrubPreviewStyle previewStyle;

  /// Builds the bubble instead of [NativeVideoPlayerScrubPreview]. It is
  /// centered over the finger and kept inside the bar's ends; the bar
  /// animates it in and out.
  final Widget Function(BuildContext, NativeVideoPlayerScrubDetails)?
  previewBuilder;

  /// Called when a drag (or tap) starts, with the position under the
  /// finger. Keep the controls visible from here to [onScrubEnd].
  final ValueChanged<Duration>? onScrubStart;

  /// Called as the drag moves, with the (snapped) position.
  final ValueChanged<Duration>? onScrubUpdate;

  /// Called on release, with the position the bar seeks to.
  final ValueChanged<Duration>? onScrubEnd;

  /// Called when the finger (or mouse) moves into another chapter, and
  /// with null when scrubbing ends, e.g. to show the chapter title
  /// somewhere else in the overlay while dragging.
  final ValueChanged<NativeVideoPlayerChapter?>? onScrubChapterChanged;

  /// Called each time the drag snaps to a chapter start.
  final ValueChanged<NativeVideoPlayerChapter>? onSnap;

  /// Called whenever what the preview shows changes (position, chapter,
  /// storyboard frame, snapped), and with null when it goes away. Fires
  /// with [showPreview] off too, so you can draw the preview elsewhere.
  final ValueChanged<NativeVideoPlayerScrubDetails?>? onPreviewChanged;

  /// Accessibility label; the value is the position.
  final String? semanticsLabel;

  @override
  State<NativeVideoPlayerProgressBar> createState() =>
      _NativeVideoPlayerProgressBarState();
}

class _NativeVideoPlayerProgressBarState
    extends State<NativeVideoPlayerProgressBar>
    with TickerProviderStateMixin {
  final List<StreamSubscription<Object?>> _subscriptions = [];

  /// Bar (and thumb) expansion while touched or hovered.
  late final AnimationController _grow = AnimationController(
    vsync: this,
    duration: widget.style.expandDuration,
  );

  /// Hand-over between the previously and newly active segment.
  late final AnimationController _segmentSwitch = AnimationController(
    vsync: this,
    duration: widget.style.expandDuration,
    value: 1,
  );

  /// Thumb pulse on a snap.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  /// Preview bubble in/out.
  late final AnimationController _preview = AnimationController(
    vsync: this,
    duration: widget.previewStyle.animationDuration,
  );

  /// The position the drag points at (snapped), while dragging and until
  /// the release's seek lands.
  Duration? _scrub;
  bool _dragging = false;
  Timer? _settleTimer;
  Timer? _collapseTimer;

  /// The chapter start the drag is snapped to, for the haptic tick.
  Duration? _snappedTo;

  /// Releases the controller's overlay hold taken while scrubbing.
  VoidCallback? _releaseOverlay;

  void _holdOverlay() {
    if (!widget.holdOverlayWhileScrubbing) return;
    _releaseOverlay ??= _c?.holdOverlay();
  }

  void _releaseOverlayHold() {
    _releaseOverlay?.call();
    _releaseOverlay = null;
  }

  /// Mouse x while hovering (desktop/web).
  double? _hoverX;

  int _activeSegment = -1;
  int _previousSegment = -1;

  /// The last preview shown, kept while it animates out.
  NativeVideoPlayerScrubDetails? _lastPreview;

  /// What the scrub callbacks last reported, to call them on changes only.
  NativeVideoPlayerScrubDetails? _reportedDetails;
  int _reportedChapter = -1;

  /// Storyboard URLs already handed to [precacheImage], newest last.
  final List<String> _precached = [];
  String? _precacheCenter;

  NativeVideoPlayerController? get _c => widget.controller;

  Duration get _duration => widget.duration ?? _c?.duration ?? Duration.zero;
  Duration get _position =>
      widget.position ?? _c?.currentPosition ?? Duration.zero;
  Duration get _buffered =>
      widget.bufferedPosition ?? _c?.bufferedPosition ?? Duration.zero;
  bool get _isLive => widget.isLive ?? _c?.isLive ?? false;

  List<NativeVideoPlayerChapter> get _chapters {
    if (_isLive) return const [];
    final own = widget.chapters;
    return own == null
        ? (_c?.chapters ?? const [])
        : NativeVideoPlayerChapters.normalize(own);
  }

  @override
  void initState() {
    super.initState();
    _listen();
    // Drop the bubble once it has faded out.
    _preview.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && mounted) {
        setState(() => _lastPreview = null);
      }
    });
  }

  @override
  void didUpdateWidget(NativeVideoPlayerProgressBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _releaseOverlayHold();
      _unlisten();
      _listen();
    }
    _grow.duration = widget.style.expandDuration;
    _segmentSwitch.duration = widget.style.expandDuration;
    _preview.duration = widget.previewStyle.animationDuration;
    if (oldWidget.storyboard != widget.storyboard) {
      _precached.clear();
      _precacheCenter = null;
    }
  }

  @override
  void dispose() {
    _releaseOverlayHold();
    _unlisten();
    _settleTimer?.cancel();
    _collapseTimer?.cancel();
    _grow.dispose();
    _segmentSwitch.dispose();
    _pulse.dispose();
    _preview.dispose();
    super.dispose();
  }

  void _listen() {
    final c = _c;
    if (c == null) return;
    void refresh(Object? _) {
      if (mounted) setState(() {});
    }

    _subscriptions.addAll([
      c.positionStream.listen(refresh),
      c.durationStream.listen(refresh),
      c.bufferedPositionStream.listen(refresh),
      c.chaptersStream.listen(refresh),
      c.isLiveStream.listen(refresh),
    ]);
  }

  void _unlisten() {
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    _subscriptions.clear();
  }

  // ─── Gestures ───────────────────────────────────────────────────────

  /// Converts a local x to a position, snapped to a nearby chapter start.
  (Duration, Duration?) _positionAt(double x, double width) {
    final duration = _duration;
    if (width <= 0 || duration <= Duration.zero) return (Duration.zero, null);
    final fraction = (x / width).clamp(0.0, 1.0);
    final raw = duration * fraction;
    if (!widget.snapToChapters) return (raw, null);
    final target = NativeVideoPlayerChapters.snapTarget(
      _chapters,
      raw,
      threshold: duration * (widget.snapDistance / width),
    );
    return (target ?? raw, target);
  }

  void _expand() {
    _collapseTimer?.cancel();
    unawaited(_grow.forward());
  }

  void _collapse() {
    if (_dragging || _hoverX != null) return;
    _collapseTimer?.cancel();
    final delay = widget.style.collapseDelay;
    if (delay <= Duration.zero) {
      unawaited(_grow.reverse());
    } else {
      _collapseTimer = Timer(delay, () {
        if (mounted && !_dragging && _hoverX == null) {
          unawaited(_grow.reverse());
        }
      });
    }
  }

  void _start(double x, double width) {
    if (_duration <= Duration.zero) return;
    final (position, snapped) = _positionAt(x, width);
    _settleTimer?.cancel();
    _snappedTo = snapped;
    setState(() {
      _dragging = true;
      _scrub = position;
    });
    _holdOverlay();
    _expand();
    widget.onScrubStart?.call(position);
  }

  void _update(double x, double width) {
    if (!_dragging) return;
    final (position, snapped) = _positionAt(x, width);
    if (snapped != null && snapped != _snappedTo) {
      if (widget.hapticFeedback) unawaited(HapticFeedback.selectionClick());
      if (widget.style.snapPulse) unawaited(_pulse.forward(from: 0));
      final chapter = NativeVideoPlayerChapters.chapterAt(_chapters, snapped);
      if (chapter != null) widget.onSnap?.call(chapter);
    }
    _snappedTo = snapped;
    if (position == _scrub) return;
    setState(() => _scrub = position);
    widget.onScrubUpdate?.call(position);
  }

  Future<void> _end() async {
    if (!_dragging) return;
    final target = _scrub!;
    setState(() => _dragging = false);
    _snappedTo = null;
    _releaseOverlayHold();
    _collapse();
    widget.onScrubEnd?.call(target);
    final seek = widget.onSeek ?? _c?.seekTo;
    try {
      await seek?.call(target);
    } finally {
      // Keep the thumb at the target until the player reports a position
      // near it (see build), or for a moment at most.
      if (mounted && !_dragging) {
        _settleTimer?.cancel();
        _settleTimer = Timer(const Duration(milliseconds: 1500), () {
          if (mounted && !_dragging) setState(() => _scrub = null);
        });
      }
    }
  }

  void _cancel() {
    if (!_dragging) return;
    setState(() {
      _dragging = false;
      _scrub = null;
    });
    _snappedTo = null;
    _releaseOverlayHold();
    _collapse();
  }

  void _tap(double x, double width) {
    _start(x, width);
    unawaited(_end());
  }

  void _hover(double? x) {
    setState(() => _hoverX = x);
    if (x != null) {
      _expand();
    } else {
      _collapse();
    }
  }

  // ─── Precaching ─────────────────────────────────────────────────────

  void _precacheAround(Duration position) {
    final storyboard = widget.storyboard;
    final limit = widget.storyboardPrecacheLimit;
    if (storyboard == null || limit <= 0) return;
    final center = storyboard.thumbnailAt(position)?.url;
    if (center == null || center == _precacheCenter) return;
    _precacheCenter = center;
    final urls = storyboard.imageUrlsAround(position, limit: limit);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final build =
          widget.storyboardImageProvider ??
          NativeVideoPlayerScrubPreview.defaultImageProvider;
      for (final url in urls) {
        if (_precached.contains(url)) continue;
        _precached.add(url);
        unawaited(
          precacheImage(
            build(url, widget.storyboardHeaders),
            context,
            onError: (error, stackTrace) => _precached.remove(url),
          ),
        );
      }
      // Remember only the recent ones; older images may already have been
      // evicted from the image cache and are loaded again when needed.
      while (_precached.length > limit * 3) {
        _precached.removeAt(0);
      }
    });
  }

  /// Calls the preview/chapter callbacks after this frame when what they
  /// report changed.
  void _report(NativeVideoPlayerScrubDetails? details) {
    final changed =
        details?.position != _reportedDetails?.position ||
        details?.chapterIndex != _reportedDetails?.chapterIndex ||
        details?.thumbnail != _reportedDetails?.thumbnail ||
        details?.snapped != _reportedDetails?.snapped ||
        (details == null) != (_reportedDetails == null);
    if (!changed) return;
    _reportedDetails = details;
    final chapterIndex = details?.chapterIndex ?? -1;
    final chapterChanged = chapterIndex != _reportedChapter;
    _reportedChapter = chapterIndex;
    if (widget.onPreviewChanged == null &&
        (widget.onScrubChapterChanged == null || !chapterChanged)) {
      return;
    }
    // Callbacks usually call setState on a parent: not during this build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onPreviewChanged?.call(details);
      if (chapterChanged) widget.onScrubChapterChanged?.call(details?.chapter);
    });
  }

  // ─── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final style = widget.style;
    final sliderTheme = SliderTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final played =
        style.playedColor ?? sliderTheme.activeTrackColor ?? scheme.primary;
    final buffered =
        style.bufferedColor ??
        sliderTheme.secondaryActiveTrackColor ??
        Colors.white.withValues(alpha: 0.5);
    final background =
        style.backgroundColor ??
        sliderTheme.inactiveTrackColor ??
        Colors.white.withValues(alpha: 0.24);
    final thumb = style.thumbColor ?? sliderTheme.thumbColor ?? played;

    // The seek landed: follow the player again.
    if (!_dragging &&
        _scrub != null &&
        (_position - _scrub!).abs() < const Duration(milliseconds: 1200)) {
      _scrub = null;
      _settleTimer?.cancel();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final duration = _duration;
        final chapters = _chapters;
        final segments = NativeVideoPlayerChapters.segments(chapters, duration);
        double fractionOf(Duration d) => duration <= Duration.zero
            ? 0
            : (d.inMicroseconds / duration.inMicroseconds).clamp(0.0, 1.0);

        final position = _scrub ?? _position;
        final hoverPosition = _hoverX == null
            ? null
            : _positionAt(_hoverX!, width).$1;
        final focus = _dragging ? _scrub : hoverPosition;

        // The segment that grows: under the finger, else under the mouse.
        if (focus != null) {
          final active = segments.lastIndexWhere((s) => s.start <= focus);
          if (active != _activeSegment) {
            _previousSegment = _activeSegment;
            _activeSegment = active;
            unawaited(_segmentSwitch.forward(from: 0));
          }
        }

        if (!_isLive) {
          _precacheAround(focus ?? _position);
        }

        // Preview bubble.
        NativeVideoPlayerScrubDetails? details;
        if (focus != null && !_isLive && duration > Duration.zero) {
          final index = NativeVideoPlayerChapters.indexAt(chapters, focus);
          details = NativeVideoPlayerScrubDetails(
            position: focus,
            duration: duration,
            chapter: index == -1 ? null : chapters[index],
            chapterIndex: index,
            thumbnail: widget.storyboard?.thumbnailAt(focus),
            snapped: _dragging && _snappedTo != null,
          );
        }
        _report(details);
        if (details != null &&
            (!widget.showPreview ||
                (widget.previewBuilder == null &&
                    !NativeVideoPlayerScrubPreview.hasContent(
                      details,
                      widget.previewStyle,
                    )))) {
          details = null;
        }
        if (details != null) {
          _lastPreview = details;
          if (!_preview.isForwardOrCompleted) unawaited(_preview.forward());
        } else if (_preview.value == 0) {
          // Nothing to fade out (reversing now would notify mid-build).
          _preview.stop();
          _lastPreview = null;
        } else if (_preview.status != AnimationStatus.reverse) {
          unawaited(_preview.reverse());
        }

        final bar = AnimatedBuilder(
          animation: Listenable.merge([_grow, _segmentSwitch, _pulse]),
          builder: (context, _) {
            final grow = Curves.easeOut.transform(_grow.value);
            final pulse = math.sin(_pulse.value * math.pi) * 0.3;
            return CustomPaint(
              size: Size(width, style.height),
              painter: _ChapterBarPainter(
                segments: segments,
                playedFraction: fractionOf(position),
                bufferedFraction: widget.showBuffered && !_isLive
                    ? fractionOf(_buffered)
                    : 0,
                activeSegment: _activeSegment,
                previousSegment: _previousSegment,
                switchProgress: Curves.easeOut.transform(_segmentSwitch.value),
                grow: grow,
                barHeight: style.barHeight,
                expandedBarHeight: style.expandedBarHeight ?? style.barHeight,
                activeSegmentHeight: style.activeSegmentHeight,
                gap: style.chapterGap,
                roundedCaps: style.roundedCaps,
                thumbRadius:
                    lerpDouble(
                      style.thumbRadius,
                      style.expandedThumbRadius,
                      grow,
                    )! *
                    (1 + pulse),
                playedColor: played,
                bufferedColor: buffered,
                backgroundColor: background,
                thumbColor: thumb,
              ),
            );
          },
        );

        final format =
            widget.previewStyle.timeFormatter ??
            NativeVideoPlayerScrubPreview.formatDuration;
        const step = Duration(seconds: 10);
        Future<void> seekBy(Duration delta) async {
          final target = _position + delta;
          final clamped = target < Duration.zero
              ? Duration.zero
              : (target > duration ? duration : target);
          await (widget.onSeek ?? _c?.seekTo)?.call(clamped);
        }

        return Semantics(
          slider: true,
          label: widget.semanticsLabel,
          value: format(position),
          increasedValue: format(position + step),
          decreasedValue: format(
            position > step ? position - step : Duration.zero,
          ),
          onIncrease: () => unawaited(seekBy(step)),
          onDecrease: () => unawaited(seekBy(-step)),
          child: MouseRegion(
            onHover: (e) => _hover(e.localPosition.dx),
            onExit: (_) => _hover(null),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragDown: (d) => _start(d.localPosition.dx, width),
              // The move that wins the drag arrives as its start.
              onHorizontalDragStart: (d) => _update(d.localPosition.dx, width),
              onHorizontalDragUpdate: (d) => _update(d.localPosition.dx, width),
              onHorizontalDragEnd: (_) => _end(),
              onHorizontalDragCancel: _cancel,
              onTapUp: (d) => _tap(d.localPosition.dx, width),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  SizedBox(width: width, height: style.height, child: bar),
                  ..._previewLayer(context, width, fractionOf),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _previewLayer(
    BuildContext context,
    double width,
    double Function(Duration) fractionOf,
  ) {
    final details = _lastPreview;
    if (details == null) return const [];
    final style = widget.style;
    final previewStyle = widget.previewStyle;
    final x = fractionOf(details.position) * width;
    final animation = CurvedAnimation(
      parent: _preview,
      curve: previewStyle.animationCurve,
    );
    // Above the thickest the bar (or its thumb) gets.
    final tallest = [
      style.activeSegmentHeight,
      style.expandedBarHeight ?? 0,
      style.expandedThumbRadius * 2,
    ].reduce(math.max);
    final barTop = style.height / 2 + tallest / 2;
    final arrow = previewStyle.backgroundColor == null
        ? null
        : previewStyle.arrowSize;
    final bubbleBottom = barTop + previewStyle.gapToBar + (arrow?.height ?? 0);

    final bubble =
        widget.previewBuilder?.call(context, details) ??
        NativeVideoPlayerScrubPreview(
          details: details,
          style: previewStyle,
          imageHeaders: widget.storyboardHeaders,
          imageProviderBuilder: widget.storyboardImageProvider,
        );

    Widget appear(Widget child, Alignment alignment) => IgnorePointer(
      child: FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween(begin: 0.85, end: 1.0).animate(animation),
          alignment: alignment,
          child: child,
        ),
      ),
    );

    return [
      Positioned(
        left: 0,
        right: 0,
        bottom: bubbleBottom,
        // Room for the tallest bubble; the bubble sits at its bottom.
        height: 600,
        child: appear(
          CustomSingleChildLayout(delegate: _BubbleLayout(x), child: bubble),
          Alignment((x / math.max(width, 1) * 2 - 1).clamp(-1.0, 1.0), 1),
        ),
      ),
      if (arrow != null)
        Positioned(
          left:
              x.clamp(
                arrow.width / 2,
                math.max(arrow.width / 2, width - arrow.width / 2),
              ) -
              arrow.width / 2,
          bottom: barTop + previewStyle.gapToBar,
          child: appear(
            CustomPaint(
              size: arrow,
              painter: _ArrowPainter(previewStyle.backgroundColor!),
            ),
            Alignment.bottomCenter,
          ),
        ),
    ];
  }
}

/// Centers the bubble on the finger, kept inside the bar's ends, at the
/// bottom of its (tall) slot.
class _BubbleLayout extends SingleChildLayoutDelegate {
  _BubbleLayout(this.x);

  final double x;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxLeft = size.width - childSize.width;
    final left = maxLeft <= 0
        ? maxLeft / 2
        : (x - childSize.width / 2).clamp(0.0, maxLeft);
    return Offset(left, size.height - childSize.height);
  }

  @override
  bool shouldRelayout(_BubbleLayout oldDelegate) => oldDelegate.x != x;
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(size.width, 0)
        ..lineTo(size.width / 2, size.height)
        ..close(),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter old) => old.color != color;
}

class _ChapterBarPainter extends CustomPainter {
  _ChapterBarPainter({
    required this.segments,
    required this.playedFraction,
    required this.bufferedFraction,
    required this.activeSegment,
    required this.previousSegment,
    required this.switchProgress,
    required this.grow,
    required this.barHeight,
    required this.expandedBarHeight,
    required this.activeSegmentHeight,
    required this.gap,
    required this.roundedCaps,
    required this.thumbRadius,
    required this.playedColor,
    required this.bufferedColor,
    required this.backgroundColor,
    required this.thumbColor,
  });

  final List<NativeVideoPlayerChapterSegment> segments;
  final double playedFraction;
  final double bufferedFraction;
  final int activeSegment;
  final int previousSegment;
  final double switchProgress;
  final double grow;
  final double barHeight;
  final double expandedBarHeight;
  final double activeSegmentHeight;
  final double gap;
  final bool roundedCaps;
  final double thumbRadius;
  final Color playedColor;
  final Color bufferedColor;
  final Color backgroundColor;
  final Color thumbColor;

  double _heightOf(int i) {
    final base = lerpDouble(barHeight, expandedBarHeight, grow)!;
    final active = math.max(
      base,
      lerpDouble(barHeight, activeSegmentHeight, grow)!,
    );
    if (i == activeSegment) return lerpDouble(base, active, switchProgress)!;
    if (i == previousSegment) return lerpDouble(active, base, switchProgress)!;
    return base;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final width = size.width;
    final playedX = playedFraction * width;
    final bufferedX = bufferedFraction * width;
    // An unknown duration still draws an empty track.
    final drawn = segments.isEmpty
        ? const [
            NativeVideoPlayerChapterSegment(
              index: -1,
              chapter: null,
              start: Duration.zero,
              end: Duration.zero,
              startFraction: 0,
              endFraction: 1,
            ),
          ]
        : segments;

    for (var i = 0; i < drawn.length; i++) {
      final segment = drawn[i];
      final left = segment.startFraction * width + (i > 0 ? gap / 2 : 0);
      final right =
          segment.endFraction * width - (i < drawn.length - 1 ? gap / 2 : 0);
      if (right <= left) continue;
      final height = _heightOf(i);
      final rect = RRect.fromLTRBR(
        left,
        centerY - height / 2,
        right,
        centerY + height / 2,
        roundedCaps ? Radius.circular(height / 2) : Radius.zero,
      );
      canvas
        ..save()
        ..clipRRect(rect)
        ..drawRect(rect.outerRect, Paint()..color = backgroundColor);
      if (bufferedX > left) {
        canvas.drawRect(
          Rect.fromLTRB(left, rect.top, bufferedX, rect.bottom),
          Paint()..color = bufferedColor,
        );
      }
      if (playedX > left) {
        canvas.drawRect(
          Rect.fromLTRB(left, rect.top, playedX, rect.bottom),
          Paint()..color = playedColor,
        );
      }
      canvas.restore();
    }

    if (thumbRadius > 0) {
      canvas.drawCircle(
        Offset(playedX.clamp(0.0, width), centerY),
        thumbRadius,
        Paint()..color = thumbColor,
      );
    }
  }

  @override
  bool shouldRepaint(_ChapterBarPainter old) =>
      !listEquals(old.segments, segments) ||
      old.playedFraction != playedFraction ||
      old.bufferedFraction != bufferedFraction ||
      old.activeSegment != activeSegment ||
      old.previousSegment != previousSegment ||
      old.switchProgress != switchProgress ||
      old.grow != grow ||
      old.barHeight != barHeight ||
      old.expandedBarHeight != expandedBarHeight ||
      old.activeSegmentHeight != activeSegmentHeight ||
      old.gap != gap ||
      old.roundedCaps != roundedCaps ||
      old.thumbRadius != thumbRadius ||
      old.playedColor != playedColor ||
      old.bufferedColor != bufferedColor ||
      old.backgroundColor != backgroundColor ||
      old.thumbColor != thumbColor;
}
