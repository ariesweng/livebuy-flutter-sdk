import 'package:flutter/material.dart';

import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';

// PlaybackProgressBarView — VOD/回放播放進度條 (rb-flutter-vod-playback-progress-bar).
//
// Spec: `reference-ui-rendering/spec.md`
//   § "渲染 Flutter VOD/回放播放進度條（PlaybackProgressBarView），綁 DefaultPlaybackProgressState +
//      isFinishedLiveReplay"
// Flutter parity of iOS `PlaybackProgressBarView.swift`
// (rb-ios-restore-vod-playback-progress-bar, archived).
//   Design source: `design/templates/minimal/screens.jsx` `LBPPlayerScreen`
//   "Playback progress bar — VOD and replay only".
//
// IDLE state: a 3px thin line pinned to the bottom edge (translucent white track
// `Color(0x48FFFFFF)` + white fill by position/duration ratio), with an invisible ~20px drag
// hit-area above it so a touch does not need to land precisely on the 3px line. EXPANDED state
// (triggered by a touch-down, zero minimum distance — `onPanDown`, not `onPanStart`, which only
// fires after Flutter's own pan-slop threshold): a full transport bar — a 28×28 play/pause icon
// button (left) + a draggable 3px seek track (`Color(0x59FFFFFF)` background, white fill) with a
// 14px circular white handle + shadow (right). The parent (`PlayerShellView`) owns WHEN it stays
// expanded (2.8s after release) via [scrubBarExpanded]; this leaf only renders the two visual
// states and reports raw gesture edges upward.
//
// GESTURE CARRIER: ONE `GestureDetector` (explicit key, fixed Stack-child position) spans the
// FULL width in BOTH idle and expanded states — never itself swapped by the idle/expanded
// `if/else`, only its `child`'s VISUAL differs — so an in-flight drag survives the idle→expanded
// rebuild the very first `onScrubStart` call triggers in the parent (parity with iOS's documented
// "single structurally-stable gesture carrier" decision, translated to Flutter's element-
// reconciliation model: same type + same tree position ⇒ the same Element, so its underlying
// recognizer / tracked pointer is preserved across the rebuild). The play/pause button is
// deliberately a Stack SIBLING painted AFTER (on top of) this detector, NOT nested inside it:
// `onPanDown` fires on ANY pointer-down within a `GestureDetector`'s hit region regardless of
// gesture-arena resolution, so a nested button would ALSO fire scrub-start on every tap; as a
// Stack sibling, the button's own opaque hit-test occludes that region from ever reaching the
// drag detector underneath (Stack hit-testing stops at the first opaque hit). Local drag
// coordinates are translated into a track-relative ratio via [_transportBarInset]
// (`playButtonWidth + gap`) whenever [scrubBarExpanded] is true — correct precisely because the
// occluding button means the drag detector only ever RECEIVES offsets `>= inset` while expanded.
//
// While actively dragging ([isScrubbing], parent-owned — NOT the whole [scrubBarExpanded] hold
// window) a centered `HH:MM:SS / HH:MM:SS` timestamp readout floats 6px above the bar,
// non-interactive (`IgnorePointer`), disappearing the instant the finger lifts even though the
// transport bar itself stays expanded for the remaining hold window.
//
// STATE SPLIT (mirrors iOS `PlaybackProgressBarView` / `PlayerShellView`): this leaf owns ONLY
// its own transient `_dragRatio` (the live finger position, for zero-latency visual feedback
// without waiting on the async round trip back through `template.playbackProgress`). The coarser
// `isScrubbing` / `scrubBarExpanded` booleans + the 2.8s collapse timer are owned by the PARENT
// and passed down as plain snapshot props (SUB-VIEW INPUT PATTERN) — this leaf reports only the
// raw gesture edges ([onScrubStart] / [onScrubEnd]) and the live seek value ([onSeek]) upward.
//
// SUB-VIEW INPUT PATTERN: `theme` first, snapshot values, then callbacks defaulting to null so
// this renders correctly (inert) with every callback omitted (demo / golden / widget tests).
//
// DRAG-SEEK THROTTLE (rb-flutter-progress-bar-drag-seek-throttle): the live [_dragRatio] visual
// (thumb position / fill) updates on EVERY reported drag pixel via local `setState` — that stays
// unthrottled, it is cheap. What IS throttled is the [onSeek] callback itself: its default
// wiring (`live_buy_player.dart`'s `LivebuyPlayerConfig.onSeek` default) calls
// `LivebuyPlayerController.seek()`, a REAL `MethodChannel.invokeMethod` round trip to the native
// player, which then echoes an async `playbackProgress` event back into
// `LivebuyUI.playerTemplate` that can trigger a broader repaint — firing that on every dragged
// pixel (the previous, unthrottled behavior) was the actual source of the reported drag jank,
// not the local `setState`. [shouldEmitDragSeek] gates [onSeek] to at most once per
// [_dragSeekThrottleMs] during a drag; touch-down and release/cancel always emit immediately so
// the gesture still feels responsive and the final position is never dropped.

/// Total width of the transport bar's leading play/pause button + its gap to the track
/// (`28 (button) + 8 (gap)`), used to translate a drag's local x-offset into a track-relative
/// ratio once [PlaybackProgressBarView.scrubBarExpanded] is true (the idle state has no button,
/// so its inset is `0`). Deliberately NOT the same value as iOS/Android's
/// `transportHorizontalPadding` (`12`) — this is a distinct, meaningful "make room for the
/// button" offset, not a symmetric container margin (rb-flutter-progress-bar-expanded-ui-parity).
const double _transportBarInset = 36;

/// Expanded-state ONLY trailing (right) inset applied to the track, matching iOS
/// `PlaybackProgressBarView.transportHorizontalPadding` / Android
/// `transportHorizontalPadding` (both `12`, applied to BOTH sides of the transport row —
/// Flutter's leading side already gets its own asymmetric [_transportBarInset] for the
/// play/pause button, so only the trailing side needs this new, independent padding to reach
/// visual parity). Flutter logical pixels are device-independent, exactly like iOS points and
/// Android dp (see `player_header_bar_view.dart`'s marquee-constants doc comment), so this
/// ports across with no unit conversion. `0` in the idle state (no transport bar, no padding —
/// see [PlaybackProgressBarView._expandedTrackVisual], only ever composed while expanded).
/// (rb-flutter-progress-bar-expanded-ui-parity)
const double _expandedTrailingPadding = 12;

/// Play/pause glyph size while the transport bar is expanded, matching iOS
/// `PlaybackProgressBarView.playPauseIconSize` / Android `playPauseIconSize` (both `14`) — NOT
/// [_playPauseButtonSize] (`28`, the tappable button's own frame, unchanged and already at
/// parity). (rb-flutter-progress-bar-expanded-ui-parity)
const double _playPauseIconSize = 14;

/// The play/pause button's own tappable frame (unchanged — already at parity with iOS
/// `playPauseButtonSize` / Android `playPauseButtonSize`, both `28`). Named so the icon-vs-button
/// size distinction is explicit at every call site (rb-flutter-progress-bar-expanded-ui-parity).
const double _playPauseButtonSize = 28;

/// Minimum real-time gap (milliseconds) between two consecutive drag-triggered
/// [PlaybackProgressBarView.onSeek] emissions during an in-progress drag (touch-down and
/// release/cancel are exempt — see [shouldEmitDragSeek] / [_PlaybackProgressBarViewState._handleUp]).
/// `120` is comfortably below what reads as "instant" to a user (~8 emits/sec) while collapsing
/// what used to be one real native-seek round trip PER REPORTED PIXEL down to a small, bounded
/// rate (rb-flutter-progress-bar-drag-seek-throttle).
const int _dragSeekThrottleMs = 120;

/// PURE: throttle decision for [PlaybackProgressBarView]'s drag → [PlaybackProgressBarView.onSeek]
/// emission (rb-flutter-progress-bar-drag-seek-throttle; unit-testable without a widget/Timer —
/// takes plain millisecond ints, no `DateTime`/`Clock` dependency). [lastEmitMs] is the wall-clock
/// timestamp (`DateTime.now().millisecondsSinceEpoch`) of the last ACTUALLY-emitted `onSeek` call
/// this drag gesture, or `null` if none has fired yet. [nowMs] is the current timestamp for this
/// candidate emission. [force] (touch-down / release / cancel — the two gesture edges that MUST
/// NEVER be silently dropped) always returns `true` regardless of elapsed time. Otherwise this
/// permits an emission only once at least [minIntervalMs] (default [_dragSeekThrottleMs]) have
/// elapsed since [lastEmitMs] — including the very first non-forced call ever (`lastEmitMs ==
/// null`), which always emits (there is nothing to throttle against yet).
bool shouldEmitDragSeek(int? lastEmitMs, int nowMs,
    {required bool force, int minIntervalMs = _dragSeekThrottleMs}) {
  if (force) return true;
  if (lastEmitMs == null) return true;
  return (nowMs - lastEmitMs) >= minIntervalMs;
}

/// PURE: the expanded-state track's interactive/rendered width for a given full container
/// [containerWidth] — subtracts the leading [_transportBarInset] (button + gap, unchanged) and
/// the new symmetric trailing [_expandedTrailingPadding] (`12`, matches iOS/Android
/// `transportHorizontalPadding` on the far side of the track). Negative results clamp to `0`
/// (unit-testable without a widget; rb-flutter-progress-bar-expanded-ui-parity). Only used while
/// [PlaybackProgressBarView.scrubBarExpanded] is true — the idle state has neither inset.
double expandedTrackWidth(double containerWidth) =>
    (containerWidth - _transportBarInset - _expandedTrailingPadding)
        .clamp(0.0, double.infinity);

/// PURE: idle-state / non-dragging fill ratio (`position/duration`, clamp to `[0,1]`).
/// `duration <= 0` (including non-finite / negative) → `0` (unit-testable without a widget).
/// Parity iOS `progressRatio(position:duration:)`.
double playbackProgressRatio(double position, double duration) {
  if (!duration.isFinite || duration <= 0) return 0;
  final ratio = position / duration;
  if (!ratio.isFinite) return 0;
  return ratio.clamp(0.0, 1.0);
}

/// PURE: zero-padded `HH:MM:SS`, ALWAYS 3 segments (the hour segment is never omitted, even
/// under 1 hour — matches the design's literal `[hh,mm,ss].map(padStart(2,'0')).join(':')`, NOT
/// a typical player's "drop the hour when zero" convention). Non-finite / negative input → `0`.
/// Unit-testable without a widget. Parity iOS `formatTimestamp(_:)`.
String formatPlaybackTimestamp(double seconds) {
  final total = (!seconds.isFinite || seconds < 0) ? 0 : seconds.round();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(h)}:${two(m)}:${two(s)}';
}

class PlaybackProgressBarView extends StatefulWidget {
  final ReferenceUITheme theme;

  /// Non-dragging playback position in seconds (`PlayerShellModel.playbackPosition`). Used for
  /// the idle-state fill ratio and, while NOT dragging, the timestamp readout's numerator.
  final double position;

  /// Total duration in seconds (`PlayerShellModel.playbackDuration`).
  final double duration;

  /// Whether the video is currently playing (`PlayerShellModel.isPlaybackPlaying`) — drives the
  /// transport bar's play/pause glyph.
  final bool isPlaying;

  /// Parent-owned: true from touch-down until touch-up. Gates the timestamp readout.
  final bool isScrubbing;

  /// Parent-owned: true from touch-down until 2.8s after touch-up. Gates the idle-line-vs-
  /// transport-bar visual.
  final bool scrubBarExpanded;

  /// Tap the play/pause button (expanded state only). Default null → inert (demo / golden).
  final VoidCallback? onTogglePlayPause;

  /// Fired during a drag with the resolved absolute seconds (`ratio * duration`). Touch-down and
  /// release/cancel ALWAYS fire immediately; intermediate moves are throttled to at most once per
  /// [_dragSeekThrottleMs] (see [shouldEmitDragSeek] — rb-flutter-progress-bar-drag-seek-throttle;
  /// the live visual thumb position is NOT throttled, only this callback).
  final void Function(double seconds)? onSeek;

  /// Touch-down in the hit area / track (zero minimum distance — see [_transportBarInset]).
  final VoidCallback? onScrubStart;

  /// Touch-up (or cancel) — the parent starts its 2.8s collapse timer from here.
  final VoidCallback? onScrubEnd;

  const PlaybackProgressBarView({
    super.key,
    required this.theme,
    this.position = 0,
    this.duration = 0,
    this.isPlaying = false,
    this.isScrubbing = false,
    this.scrubBarExpanded = false,
    this.onTogglePlayPause,
    this.onSeek,
    this.onScrubStart,
    this.onScrubEnd,
  });

  @override
  State<PlaybackProgressBarView> createState() =>
      _PlaybackProgressBarViewState();
}

class _PlaybackProgressBarViewState extends State<PlaybackProgressBarView> {
  /// Live finger position while dragging, `null` when idle. Cleared on scrub end so the
  /// non-dragging ratio ([PlaybackProgressBarView.position] / [PlaybackProgressBarView.duration])
  /// takes back over.
  double? _dragRatio;

  double get _ratio =>
      _dragRatio ?? playbackProgressRatio(widget.position, widget.duration);

  /// Wall-clock timestamp (ms) of the last drag gesture's ACTUALLY-emitted [PlaybackProgressBarView.onSeek]
  /// call, or `null` before the first one this drag. Feeds [shouldEmitDragSeek] — see that
  /// function's doc comment for the throttle policy (rb-flutter-progress-bar-drag-seek-throttle).
  int? _lastSeekEmitMs;

  void _handleDrag(double localDx, double inset, double trackWidth,
      {required bool isStart}) {
    final ratio = trackWidth <= 0
        ? 0.0
        : ((localDx - inset) / trackWidth).clamp(0.0, 1.0);
    // Visual thumb / fill position updates on EVERY reported pixel, unthrottled — this is the
    // cheap local `setState` the throttle deliberately does NOT touch.
    setState(() => _dragRatio = ratio);
    if (isStart) widget.onScrubStart?.call();
    // Touch-down (isStart) always forces an immediate emission (parity with the pre-existing
    // "touch-down included" contract); intermediate moves go through the throttle.
    _emitSeek(ratio, force: isStart);
  }

  /// Gates the actual [PlaybackProgressBarView.onSeek] call through [shouldEmitDragSeek]. [force]
  /// bypasses the throttle entirely (touch-down / release / cancel).
  void _emitSeek(double ratio, {required bool force}) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!shouldEmitDragSeek(_lastSeekEmitMs, nowMs, force: force)) return;
    _lastSeekEmitMs = nowMs;
    widget.onSeek?.call(ratio * widget.duration);
  }

  void _handleUp() {
    // Capture the true final drag ratio BEFORE clearing it, and force-emit it even if the drag's
    // last intermediate move was throttled away — the released position MUST NOT be dropped
    // (rb-flutter-progress-bar-drag-seek-throttle).
    final finalRatio = _dragRatio;
    setState(() => _dragRatio = null);
    if (finalRatio != null) _emitSeek(finalRatio, force: true);
    widget.onScrubEnd?.call();
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: LbTestKeys.playbackProgressBar,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final inset = widget.scrubBarExpanded ? _transportBarInset : 0.0;
          final trackWidth = widget.scrubBarExpanded
              ? expandedTrackWidth(width)
              : width.clamp(0.0, double.infinity);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.isScrubbing) ...[
                KeyedSubtree(
                  key: LbTestKeys.playbackProgressTimestamp,
                  child: _TimestampReadout(
                    theme: widget.theme,
                    position: _ratio * widget.duration,
                    duration: widget.duration,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              SizedBox(
                height: widget.scrubBarExpanded ? 28 : 20,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // The PERSISTENT gesture carrier — the SAME `GestureDetector` Element (same
                    // type, same Stack-child position, explicit key) across BOTH idle and
                    // expanded, so an in-flight touch survives the idle→expanded rebuild the
                    // very first `onScrubStart` call triggers in the parent (see the file-header
                    // doc comment). Only its `child`'s VISUAL differs by state — it is never
                    // itself removed/replaced by an `if`/`else`. Spans the FULL width in both
                    // states (matching the idle state's invisible ~20px hit-area, which is
                    // deliberately larger than the visible 3px line); in the expanded state the
                    // play/pause button (below, painted AFTER = on top) occludes the region it
                    // covers from ever reaching this detector, so `inset`'s ratio math is exact
                    // regardless — a touch on the button never fires `onPanDown` here (Stack hit-
                    // testing stops at the first opaque hit; see the file-header doc comment).
                    Positioned.fill(
                      child: GestureDetector(
                        key: LbTestKeys.playbackProgressTrack,
                        behavior: HitTestBehavior.opaque,
                        onPanDown: (d) => _handleDrag(
                            d.localPosition.dx, inset, trackWidth,
                            isStart: true),
                        onPanUpdate: (d) => _handleDrag(
                            d.localPosition.dx, inset, trackWidth,
                            isStart: false),
                        onPanEnd: (_) => _handleUp(),
                        onPanCancel: _handleUp,
                        child: widget.scrubBarExpanded
                            ? _expandedTrackVisual(inset, trackWidth)
                            : _idleLineVisual(),
                      ),
                    ),
                    // Play/pause button — a Stack SIBLING of the drag detector (never its
                    // descendant), painted AFTER it (on top). Present + hit-testable ONLY while
                    // expanded. Deliberately NOT nested inside the drag detector: `onPanDown`
                    // fires on ANY pointer-down within a `GestureDetector`'s hit region
                    // regardless of gesture-arena resolution (it is not a "did this widget win
                    // the tap" callback), so a nested button would ALSO trigger scrub-start on
                    // every tap. Occluding it via Stack z-order instead means a tap here never
                    // reaches the drag detector underneath at all.
                    if (widget.scrubBarExpanded)
                      Positioned(
                        left: 0,
                        top: 0,
                        child: GestureDetector(
                          key: LbTestKeys.playbackProgressPlayPause,
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.onTogglePlayPause,
                          child: SizedBox(
                            width: _playPauseButtonSize,
                            height: _playPauseButtonSize,
                            child: Icon(
                              widget.isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                              size: _playPauseIconSize,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Idle-state visual: a 3px line anchored to the bottom of the 20px hit area (the
  /// `GestureDetector` ancestor supplies the actual hit region; this only paints).
  Widget _idleLineVisual() {
    return Align(
      alignment: Alignment.bottomCenter,
      child: _track(_ratio, background: const Color(0x48FFFFFF)),
    );
  }

  /// Expanded-state visual: the draggable track + handle, shifted right by [inset] to clear the
  /// play/pause button painted on top of this same region (see [build]'s doc comment), and
  /// inset from the trailing edge by [_expandedTrailingPadding] to match iOS/Android's symmetric
  /// `transportHorizontalPadding` on the far side of the track (rb-flutter-progress-bar-expanded-
  /// ui-parity — the leading side keeps its own distinct [inset], only the trailing side is new).
  Widget _expandedTrackVisual(double inset, double trackWidth) {
    return Padding(
      padding: EdgeInsets.only(left: inset, right: _expandedTrailingPadding),
      child: Center(
        child: SizedBox(
          height: 14,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Align(
                alignment: Alignment.center,
                child: _track(_ratio, background: const Color(0x59FFFFFF)),
              ),
              Positioned(
                left: (trackWidth * _ratio - 7)
                    .clamp(0.0, (trackWidth - 14).clamp(0.0, double.infinity)),
                top: 0,
                child: const _Handle(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 3px-tall track: [background] behind, opaque white fill left-aligned by [ratio].
  ///
  /// (rb-flutter-progress-bar-track-fill-width-guard) Two independent, STACKED bugs were found
  /// and fixed here, on real hardware (`flutter test`'s software renderer showed neither):
  ///
  /// 1. **Sizing**: both callers ([_idleLineVisual], [_expandedTrackVisual]) wrap this in an
  ///    `Align`, which — unlike a stretching parent (`CrossAxisAlignment.stretch` /
  ///    `Positioned.fill`) — sizes ITSELF to the incoming bounded max, but only STRETCHES ITS
  ///    CHILD to that size when the child asks for it. Without an explicit width, this outer
  ///    `SizedBox`'s width used to fall through to its (then-)child `Stack`'s intrinsic size,
  ///    which resolved to `ratio * availableWidth` — the WHOLE track (bg + fill together)
  ///    shrinking to `ratio`-of-full-width and then re-centering inside `Align`'s full-width box.
  ///    `width: double.infinity` forces this outer `SizedBox` to claim the full available width
  ///    regardless of `Align`'s non-stretching default — this alone fixed the reported "grows
  ///    from the middle outward" symptom ("細線進度條...從中間往左右兩邊跑出"), confirmed via
  ///    `adb shell screenrecord` pixel-scans (the track's OWN left/right edges no longer moved).
  /// 2. **Fill invisibility (the deeper bug)**: even after fix #1, the "played" fill was still
  ///    completely invisible on-device at every ratio strictly between 0 and 1 — confirmed with a
  ///    `Color(0xFFFF0000)` debug substitution: zero red pixels at ANY ratio (up to 0.976),
  ///    despite `flutter test` widget tests (software renderer, no `Impeller`) asserting the
  ///    correct rendered size/position for the identical widget tree. The original
  ///    `FractionallySizedBox(widthFactor: ratio, ...)` — a NON-positioned `Stack` child sized
  ///    from its own `widthFactor` — was the actual culprit: replaced with a `LayoutBuilder`
  ///    reading the resolved pixel `maxWidth` directly and an explicit
  ///    `Positioned(width: maxWidth * ratio)`, which renders correctly identically on both the
  ///    `flutter test` software renderer AND real-device `Impeller` (Vulkan/OpenGLES) rendering —
  ///    on-device re-verified via the same debug-color substitution at ratio ≈0.92: a correctly-
  ///    sized red segment appeared, sized to just the fill fraction, not the whole track.
  ///
  /// The one pre-existing test asserting fill width (`playback_progress_bar_view_test.dart`'s
  /// "expanded track leaves a symmetric 12px trailing gap" case) could not have caught either
  /// bug: it deliberately used `ratio == 1` (`position: duration: 100`), where bug #1's
  /// `ratio² == ratio` compounding is arithmetically invisible AND a fully-filled `ratio == 1`
  /// track has no unfilled remainder to reveal bug #2's total absence of any partial fill — see
  /// the new regression tests at `ratio == 0.5` for the case that actually discriminates both.
  Widget _track(double ratio, {required Color background}) {
    return SizedBox(
      width: double.infinity,
      height: 3,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fillWidth =
              constraints.maxWidth.isFinite ? constraints.maxWidth * ratio : 0.0;
          return Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: background)),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: fillWidth,
                child: const ColoredBox(color: Colors.white),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 14px circular white handle with a drop shadow, drawn at the current drag ratio's x-offset on
/// the expanded track.
class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Color(0x66000000), blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
    );
  }
}

/// Drag-time `HH:MM:SS / HH:MM:SS` readout — centered, non-interactive, 18pt bold white with a
/// drop shadow. Only ever composed while [PlaybackProgressBarView.isScrubbing] is true.
class _TimestampReadout extends StatelessWidget {
  final ReferenceUITheme theme;
  final double position;
  final double duration;

  const _TimestampReadout({
    required this.theme,
    required this.position,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    final text =
        '${formatPlaybackTimestamp(position)} / ${formatPlaybackTimestamp(duration)}';
    return IgnorePointer(
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            fontSize: 18 * theme.fontScale,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            shadows: const [
              Shadow(color: Color(0x99000000), blurRadius: 3, offset: Offset(0, 1)),
            ],
          ),
        ),
      ),
    );
  }
}
