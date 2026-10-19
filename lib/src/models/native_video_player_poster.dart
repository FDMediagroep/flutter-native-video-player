import 'package:flutter/widgets.dart';

import '../enums/native_video_player_event.dart';

/// What a [NativeVideoPlayerPoster] shows right now.
enum NativeVideoPlayerPosterPhase {
  /// The still [NativeVideoPlayerPoster.image].
  still,

  /// The [NativeVideoPlayerPoster.animation] on top of the still.
  animation,

  /// Gone: the video shows.
  hidden,
}

/// When a [NativeVideoPlayerPoster] gives way to the video.
enum NativeVideoPlayerPosterHide {
  /// When playback starts (default). The poster covers loading and a loaded
  /// video that was never played, which is when the preview animation runs.
  onPlay,

  /// As soon as the video is loaded, so its first frame shows before it
  /// plays. The preview animation only runs while the video loads.
  onLoaded,
}

/// What [NativeVideoPlayerPoster.overlayBuilder] gets to draw custom poster
/// chrome (a title, a play button, a progress hint, ...).
@immutable
class NativeVideoPlayerPosterState {
  const NativeVideoPlayerPosterState({
    required this.phase,
    required this.activityState,
    required this.duration,
    required this.isLive,
  });

  /// What the poster shows right now.
  final NativeVideoPlayerPosterPhase phase;

  /// The player's activity state, e.g. to show a spinner while loading.
  final PlayerActivityState activityState;

  /// [NativeVideoPlayerPoster.duration], or the player's own duration once
  /// it is known. Null while neither is known.
  final Duration? duration;

  /// [NativeVideoPlayerPoster.isLive], or what the player reports.
  final bool isLive;

  /// Whether the player is still getting the video ready.
  bool get isLoading =>
      activityState.isIdle ||
      activityState.isInitializing ||
      activityState.isInitialized ||
      activityState.isLoading;
}

/// A custom thumbnail over the player until the video plays, with an
/// optional preview animation (highlights) that fades in after the viewer
/// has looked at the unplayed video for a while.
///
/// ```dart
/// NativeVideoPlayer(
///   controller: controller,
///   poster: NativeVideoPlayerPoster(
///     image: NetworkImage('https://cdn.example.com/video/thumbnail.jpg'),
///     animation: NetworkImage('https://cdn.example.com/video/preview.webp'),
///     animationDelay: Duration(seconds: 2),
///     duration: Duration(minutes: 9, seconds: 56),
///   ),
/// )
/// ```
///
/// The poster is drawn by Flutter between the video and the controls
/// overlay, so the controls keep working on top of it. [animation] can be
/// any [ImageProvider]; animated GIF and animated WebP play as they are
/// (Bunny Stream serves both, see [NativeVideoPlayerPoster.bunny]). Use
/// [overlayBuilder] for anything else on top.
@immutable
class NativeVideoPlayerPoster {
  const NativeVideoPlayerPoster({
    this.image,
    this.animation,
    this.animationDelay = const Duration(seconds: 3),
    this.animationDuration,
    this.repeatAnimation = true,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.backgroundColor = const Color(0xFF000000),
    this.fadeDuration = const Duration(milliseconds: 350),
    this.hideWhen = NativeVideoPlayerPosterHide.onPlay,
    this.showOnCompleted = false,
    this.duration,
    this.isLive = false,
    this.showDurationBadge = true,
    this.badgeAlignment = Alignment.bottomRight,
    this.badgeBuilder,
    this.showPlayButton = true,
    this.overlayBuilder,
  });

  /// A poster for a Bunny Stream video: its `thumbnail.jpg` (or
  /// [thumbnailFileName], for a custom thumbnail) and its animated
  /// `preview.webp` (`preview.gif` with [gifPreview]).
  ///
  /// [videoBaseUrl] is the video's folder on the pull zone:
  /// `https://{pull_zone}.b-cdn.net/{video_id}`. Bunny only creates the
  /// preview when "Enable preview animation" is on for the library; pass
  /// `preview: false` otherwise. [headers] go with both image requests
  /// (a pull zone with token authentication or a referrer check). Change
  /// anything else with [copyWith].
  factory NativeVideoPlayerPoster.bunny(
    String videoBaseUrl, {
    Map<String, String>? headers,
    String thumbnailFileName = 'thumbnail.jpg',
    bool preview = true,
    bool gifPreview = false,
    Duration animationDelay = const Duration(seconds: 3),
    Duration? animationDuration,
    Duration? duration,
  }) {
    final base = videoBaseUrl.endsWith('/')
        ? videoBaseUrl.substring(0, videoBaseUrl.length - 1)
        : videoBaseUrl;
    return NativeVideoPlayerPoster(
      image: NetworkImage('$base/$thumbnailFileName', headers: headers),
      animation: preview
          ? NetworkImage(
              '$base/${gifPreview ? 'preview.gif' : 'preview.webp'}',
              headers: headers,
            )
          : null,
      animationDelay: animationDelay,
      animationDuration: animationDuration,
      duration: duration,
    );
  }

  /// The still thumbnail. Null shows [backgroundColor] until the video is
  /// ready, which still hides the black box of a loading player.
  final ImageProvider? image;

  /// A preview animation (GIF / animated WebP) faded in over the still
  /// after [animationDelay]. Null for a still-only poster.
  final ImageProvider? animation;

  /// How long the still shows before the animation fades in, counted from
  /// when the poster appears (and again after each [animationDuration] with
  /// [repeatAnimation]). [Duration.zero] starts it right away.
  final Duration animationDelay;

  /// How long the animation plays before fading back to the still. Null
  /// keeps it running until the video plays.
  final Duration? animationDuration;

  /// With an [animationDuration]: wait [animationDelay] on the still again
  /// and replay the animation, for as long as the poster shows.
  final bool repeatAnimation;

  /// How [image] and [animation] fill the player.
  final BoxFit fit;

  /// Where [image] and [animation] sit when [fit] crops or letterboxes.
  final AlignmentGeometry alignment;

  /// Shown behind the images, and while they load.
  final Color backgroundColor;

  /// Cross-fade between still, animation and video.
  final Duration fadeDuration;

  /// When the poster gives way to the video.
  final NativeVideoPlayerPosterHide hideWhen;

  /// Show the poster again when the video plays to its end.
  final bool showOnCompleted;

  /// The duration shown in the badge before the player knows it (e.g. from
  /// your CMS). Once the player reports one, the badge uses that.
  final Duration? duration;

  /// Show "LIVE" in the badge instead of a duration. The badge also turns
  /// to "LIVE" by itself once the player reports a live stream.
  final bool isLive;

  /// Show the duration / LIVE badge.
  final bool showDurationBadge;

  /// Where the badge sits.
  final AlignmentGeometry badgeAlignment;

  /// Replaces the default badge. Gets the duration text ("9:56", "1:02:03")
  /// or "LIVE", and the poster state.
  final Widget Function(
    BuildContext context,
    String label,
    NativeVideoPlayerPosterState state,
  )?
  badgeBuilder;

  /// Without custom controls (`NativeVideoPlayer.overlayBuilder`), the
  /// poster covers the native controls, so it shows a play button of its
  /// own and a tap anywhere on it starts the video. Set false to draw your
  /// own in [overlayBuilder]. With custom controls those take the taps and
  /// this is ignored.
  final bool showPlayButton;

  /// Draws anything on top of the poster: a title, a play button, a loading
  /// hint. Interactive when the player has no custom controls overlay; with
  /// one, taps go to the controls.
  final Widget Function(
    BuildContext context,
    NativeVideoPlayerPosterState state,
  )?
  overlayBuilder;

  /// A copy with the given fields replaced.
  NativeVideoPlayerPoster copyWith({
    ImageProvider? image,
    ImageProvider? animation,
    Duration? animationDelay,
    Duration? animationDuration,
    bool? repeatAnimation,
    BoxFit? fit,
    AlignmentGeometry? alignment,
    Color? backgroundColor,
    Duration? fadeDuration,
    NativeVideoPlayerPosterHide? hideWhen,
    bool? showOnCompleted,
    Duration? duration,
    bool? isLive,
    bool? showDurationBadge,
    AlignmentGeometry? badgeAlignment,
    Widget Function(BuildContext, String, NativeVideoPlayerPosterState)?
    badgeBuilder,
    bool? showPlayButton,
    Widget Function(BuildContext, NativeVideoPlayerPosterState)? overlayBuilder,
  }) {
    return NativeVideoPlayerPoster(
      image: image ?? this.image,
      animation: animation ?? this.animation,
      animationDelay: animationDelay ?? this.animationDelay,
      animationDuration: animationDuration ?? this.animationDuration,
      repeatAnimation: repeatAnimation ?? this.repeatAnimation,
      fit: fit ?? this.fit,
      alignment: alignment ?? this.alignment,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      fadeDuration: fadeDuration ?? this.fadeDuration,
      hideWhen: hideWhen ?? this.hideWhen,
      showOnCompleted: showOnCompleted ?? this.showOnCompleted,
      duration: duration ?? this.duration,
      isLive: isLive ?? this.isLive,
      showDurationBadge: showDurationBadge ?? this.showDurationBadge,
      badgeAlignment: badgeAlignment ?? this.badgeAlignment,
      badgeBuilder: badgeBuilder ?? this.badgeBuilder,
      showPlayButton: showPlayButton ?? this.showPlayButton,
      overlayBuilder: overlayBuilder ?? this.overlayBuilder,
    );
  }
}
