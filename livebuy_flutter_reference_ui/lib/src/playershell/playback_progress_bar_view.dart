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

/// Total width of the transport bar's leading play/pause button + its gap to the track
/// (`28 (button) + 8 (gap)`), used to translate a drag's local x-offset into a track-relative
/// ratio once [PlaybackProgressBarView.scrubBarExpanded] is true (the idle state has no button,
/// so its inset is `0`).
const double _transportBarInset = 36;

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

  /// Fired on every drag position change (touch-down included) with the resolved absolute
  /// seconds (`ratio * duration`). No debounce — every move reports.
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

  void _handleDrag(double localDx, double inset, double trackWidth,
      {required bool isStart}) {
    final ratio = trackWidth <= 0
        ? 0.0
        : ((localDx - inset) / trackWidth).clamp(0.0, 1.0);
    setState(() => _dragRatio = ratio);
    if (isStart) widget.onScrubStart?.call();
    widget.onSeek?.call(ratio * widget.duration);
  }

  void _handleUp() {
    setState(() => _dragRatio = null);
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
          final trackWidth = (width - inset).clamp(0.0, double.infinity);
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
                            width: 28,
                            height: 28,
                            child: Icon(
                              widget.isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                              size: 20,
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
  /// play/pause button painted on top of this same region (see [build]'s doc comment).
  Widget _expandedTrackVisual(double inset, double trackWidth) {
    return Padding(
      padding: EdgeInsets.only(left: inset),
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
  Widget _track(double ratio, {required Color background}) {
    return SizedBox(
      height: 3,
      child: Stack(
        children: [
          Positioned.fill(child: ColoredBox(color: background)),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: ratio,
            child: const ColoredBox(color: Colors.white),
          ),
        ],
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
