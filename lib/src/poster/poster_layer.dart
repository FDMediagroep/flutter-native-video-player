import 'dart:async';

import 'package:flutter/widgets.dart';

import '../controllers/native_video_player_controller.dart';
import '../enums/native_video_player_event.dart';
import '../models/native_video_player_poster.dart';

/// Draws a [NativeVideoPlayerPoster] over the video until it plays: the
/// still, the preview animation on its timer, the duration badge and the
/// app's own poster overlay.
class PosterLayer extends StatefulWidget {
  const PosterLayer({
    required this.poster,
    required this.controller,
    super.key,
  });

  final NativeVideoPlayerPoster poster;
  final NativeVideoPlayerController controller;

  @override
  State<PosterLayer> createState() => _PosterLayerState();
}

class _PosterLayerState extends State<PosterLayer> {
  late NativeVideoPlayerPosterPhase _phase;

  /// Out of the tree once the fade-out ends, so an animated image stops
  /// decoding frames under the video.
  bool _removed = false;

  Timer? _timer;
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];

  NativeVideoPlayerController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    // A view joining a controller that already played (a detail screen
    // reusing the feed's player) starts without its poster.
    final state = _controller.activityState;
    final alreadyStarted =
        state.isPlaying ||
        ((state.isPaused || state.isBuffering) &&
            _controller.currentPosition > Duration.zero);
    _phase = alreadyStarted || _hides(state)
        ? NativeVideoPlayerPosterPhase.hidden
        : NativeVideoPlayerPosterPhase.still;
    _removed = _phase == NativeVideoPlayerPosterPhase.hidden;

    _subscriptions
      ..add(_controller.playerStateStream.listen(_onActivity))
      // The badge follows the player's duration and live flag.
      ..add(_controller.durationStream.listen((_) => _rebuild()))
      ..add(_controller.isLiveStream.listen((_) => _rebuild()));

    _scheduleAnimation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decode the preview up front so it fades in with its first frame.
    final animation = widget.poster.animation;
    if (animation != null) {
      unawaited(precacheImage(animation, context, onError: (_, _) {}));
    }
  }

  @override
  void didUpdateWidget(PosterLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.poster.animationDelay != widget.poster.animationDelay ||
        oldWidget.poster.animation != widget.poster.animation) {
      _scheduleAnimation();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }

  bool _hides(PlayerActivityState state) {
    if (state.isPlaying) return true;
    return widget.poster.hideWhen == NativeVideoPlayerPosterHide.onLoaded &&
        (state.isLoaded || state.isPaused || state.isBuffering);
  }

  void _onActivity(PlayerActivityState state) {
    if (!mounted) return;
    if (_phase != NativeVideoPlayerPosterPhase.hidden && _hides(state)) {
      _timer?.cancel();
      setState(() => _phase = NativeVideoPlayerPosterPhase.hidden);
    } else if (_phase == NativeVideoPlayerPosterPhase.hidden &&
        state.isCompleted &&
        widget.poster.showOnCompleted) {
      setState(() {
        _removed = false;
        _phase = NativeVideoPlayerPosterPhase.still;
      });
      _scheduleAnimation();
    } else {
      // The overlay builder shows the activity state (e.g. a spinner).
      _rebuild();
    }
  }

  void _rebuild() {
    if (mounted && !_removed) setState(() {});
  }

  /// Still for [NativeVideoPlayerPoster.animationDelay], then the
  /// animation, for [NativeVideoPlayerPoster.animationDuration] (and
  /// around again with [NativeVideoPlayerPoster.repeatAnimation]).
  void _scheduleAnimation() {
    _timer?.cancel();
    final poster = widget.poster;
    if (poster.animation == null ||
        _phase == NativeVideoPlayerPosterPhase.hidden) {
      return;
    }
    _timer = Timer(poster.animationDelay, () {
      if (!mounted || _phase == NativeVideoPlayerPosterPhase.hidden) return;
      setState(() => _phase = NativeVideoPlayerPosterPhase.animation);
      final playFor = poster.animationDuration;
      if (playFor == null) return;
      _timer = Timer(playFor, () {
        if (!mounted || _phase != NativeVideoPlayerPosterPhase.animation) {
          return;
        }
        setState(() => _phase = NativeVideoPlayerPosterPhase.still);
        if (poster.repeatAnimation) _scheduleAnimation();
      });
    });
  }

  NativeVideoPlayerPosterState get _posterState {
    final playerDuration = _controller.duration;
    return NativeVideoPlayerPosterState(
      phase: _phase,
      activityState: _controller.activityState,
      duration: playerDuration > Duration.zero
          ? playerDuration
          : widget.poster.duration,
      isLive: widget.poster.isLive || _controller.isLive,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_removed) return const SizedBox.shrink();

    final poster = widget.poster;
    final state = _posterState;
    final hidden = _phase == NativeVideoPlayerPosterPhase.hidden;

    Widget picture(ImageProvider provider, Key key) => Image(
      key: key,
      image: provider,
      fit: poster.fit,
      alignment: poster.alignment,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );

    final String? badgeLabel = state.isLive
        ? 'LIVE'
        : state.duration == null
        ? null
        : formatPosterDuration(state.duration!);

    return AnimatedOpacity(
      opacity: hidden ? 0 : 1,
      duration: poster.fadeDuration,
      // Can end during this build (a zero fade), so drop it after the frame.
      onEnd: () => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _phase == NativeVideoPlayerPosterPhase.hidden) {
          setState(() => _removed = true);
        }
      }),
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: poster.backgroundColor),
                if (poster.image != null)
                  picture(poster.image!, const ValueKey('still')),
                if (poster.animation != null)
                  AnimatedSwitcher(
                    duration: poster.fadeDuration,
                    child: _phase == NativeVideoPlayerPosterPhase.animation
                        ? picture(poster.animation!, const ValueKey('preview'))
                        : const SizedBox.expand(key: ValueKey('none')),
                  ),
                if (poster.showDurationBadge && badgeLabel != null)
                  Align(
                    alignment: poster.badgeAlignment,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child:
                          poster.badgeBuilder?.call(
                            context,
                            badgeLabel,
                            state,
                          ) ??
                          _DefaultBadge(label: badgeLabel, live: state.isLive),
                    ),
                  ),
              ],
            ),
          ),
          if (poster.overlayBuilder != null)
            poster.overlayBuilder!(context, state),
        ],
      ),
    );
  }
}

/// "9:56", "1:02:03".
String formatPosterDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes % 60;
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return hours > 0
      ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds'
      : '$minutes:$seconds';
}

class _DefaultBadge extends StatelessWidget {
  const _DefaultBadge({required this.label, required this.live});

  final String label;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: live ? const Color(0xFFE53935) : const Color(0xCC000000),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFFFFFFFF),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFeatures: [FontFeature.tabularFigures()],
            letterSpacing: 0.2,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}
