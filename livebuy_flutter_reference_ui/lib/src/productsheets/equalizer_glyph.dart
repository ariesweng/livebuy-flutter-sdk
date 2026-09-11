import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

// MARK: - EqualizerGlyph — hand-drawn 3-bar equalizer (design「介紹中」mark)
//
// Spec: `reference-ui-rendering/spec.md` (rb-flutter-product-list-introducing-banner,
// rb-flutter-live-equalizer-motion). Flutter parity of iOS `Glyphs/EqualizerGlyph.swift` /
// Android `IconGlyphs.kt` `EqualizerGlyph` / RN `productsheets/EqualizerGlyph.tsx`. Design
// `design/templates/minimal/live-chrome.jsx` `LBLivePinnedCard` + `sdk-components.jsx`
// `LBPProductRow` introBadge — now `Icons.equalizerLive` (design R40,
// `design/contract/claude-design-sync.md`), and the cross-platform motion contract
// `design/contract/equalizer-motion.json`:
//   <rect x3   y14 w3 h7  rx0.5/>
//   <rect x10.5 y9 w3 h12 rx0.5/>
//   <rect x18  y4  w3 h17 rx0.5/>   (24-unit viewBox, fill, bottom-anchored at y21)
//
// Three bottom-aligned, ascending-height filled bars — the「介紹中」(now-introducing)
// vocabulary shared by the LIVE pinned card tag and the product-list banner. Drawn
// with `CustomPaint` (as with `ShareGlyph`) so it does not depend on any icon font
// for a stable golden, scaled by `size / 24`. Identical geometry to iOS / Android / RN.
//
// Motion (design R40 — `equalizer-motion.json` `platformPrimitives.flutter`): a single
// `AnimationController(duration: 900ms)..repeat()` drives all 3 bars via
// [equalizerHeightUnitsAt], each offset by its own [equalizerBarPhases] entry — NOT
// three independent controllers. Height (not `scaleY`) is animated, bottom-anchored,
// matching the contract's `motion.anchor == "bottom"` note (`scaleY` transform-origin
// is inconsistent across SVG / RN / Android).
//
// This codebase's established「no-animation-for-determinism」convention gates the
// motion behind [EqualizerGlyph.animate] (default `false`) — golden / demo call sites
// never pass it, so every EXISTING call site and baseline stays byte-identical. All 3
// real-runtime call sites (`ProductRow`'s LIVE/replay「介紹中」banner, `ProductRow`'s
// VOD `_VodIntroducingMask`, `LiveOverlayChromeView`'s LIVE pinned-card tag) pass a
// hardcoded `animate: true` — unconditional, matching iOS / Android / RN, which never
// gated this on any live/replay flag to begin with (rb-flutter-equalizer-live-gate-
// removal; an earlier revision of this file/change mistakenly threaded `live: bool` /
// `isLive: bool` into `animate:`, which froze the glyph static during a replay — see
// that change's proposal.md for the correction). When
// `MediaQuery.of(context).disableAnimations` (reduced motion) is true, the glyph stays
// on [equalizerRestingHeightUnits] regardless of `animate` — contract `lifecycle
// .onStop`: "停在 restingHeights（等同靜態 Icons.equalizer），不要歸零".

/// One entry per bar — evenly spaced across the animation cycle (design contract
/// `motion.phases`: `[0, 1/3, 2/3]`).
const List<double> equalizerBarPhases = <double>[0.0, 1 / 3, 2 / 3];

/// Bottom-anchored resting bar heights, 24-unit viewBox space — the pre-motion static
/// glyph's exact `[7, 12, 17]` (design contract `restingHeights` `[0.2917, 0.5, 0.7083]`
/// × 24 ≈ `[7, 12, 17]`; kept as the original integers here, not the rounded ratios, so
/// the non-animating render path stays byte-identical to every existing golden).
const List<double> equalizerRestingHeightUnits = <double>[7.0, 12.0, 17.0];

/// Animated min/max bar height, 24-unit viewBox space (design contract `motion
/// .minHeight`/`maxHeight` `0.2917`/`0.7083` × 24 ≈ `7`/`17` — the same two extremes as
/// [equalizerRestingHeightUnits]'s shortest/tallest bar).
const double equalizerMinHeightUnits = 7.0;
const double equalizerMaxHeightUnits = 17.0;

/// One full breathe cycle (design contract `motion.periodMs`).
const Duration equalizerAnimationPeriod = Duration(milliseconds: 900);

/// Pure function — design contract `motion.formula`:
/// `h = minHeight + (maxHeight - minHeight) * (0.5 - 0.5 * cos(2*PI*(t/periodMs + phase)))`.
///
/// [progress] is `t / periodMs`, i.e. an `AnimationController(duration:
/// equalizerAnimationPeriod)..repeat()`'s `.value` (expected in `[0, 1)` per cycle, but
/// any real number works — the cosine wraps). [phase] is one of [equalizerBarPhases].
/// The raised-cosine shape IS the contract's `easing: "easeInOut"` — no additional
/// `Curves` wrapping is applied on top of it.
double equalizerHeightUnitsAt({
  required double progress,
  required double phase,
  double minHeightUnits = equalizerMinHeightUnits,
  double maxHeightUnits = equalizerMaxHeightUnits,
}) {
  final wave = 0.5 - 0.5 * math.cos(2 * math.pi * (progress + phase));
  return minHeightUnits + (maxHeightUnits - minHeightUnits) * wave;
}

/// The design's 3-bar equalizer mark, hand-drawn to match the「介紹中」badge. [size] is
/// the square edge; the design proportions scale by `size / 24`. Used by the
/// product-list introducing banner (white) and the VOD full-bleed introducing mask
/// (white, larger).
///
/// [animate] (default `false`) turns on the design R40 breathing motion — see the
/// file-level doc comment above for the golden-safety contract. When `true` but the
/// platform reports `MediaQuery.of(context).disableAnimations`, the glyph still renders
/// the static [equalizerRestingHeightUnits] (never ticks a controller).
class EqualizerGlyph extends StatefulWidget {
  /// The glyph box size.
  final double size;

  /// The fill color.
  final Color color;

  /// Real-runtime motion gate. `false` (DEFAULT — golden / demo) → static resting bars,
  /// byte-identical to the pre-motion glyph. `true` (real runtime) → the breathing loop,
  /// unless `MediaQuery.of(context).disableAnimations` is true.
  final bool animate;

  const EqualizerGlyph({
    super.key,
    required this.size,
    required this.color,
    this.animate = false,
  });

  @override
  State<EqualizerGlyph> createState() => _EqualizerGlyphState();
}

class _EqualizerGlyphState extends State<EqualizerGlyph>
    with TickerProviderStateMixin {
  // `TickerProviderStateMixin` (not `Single...`) — this State disposes and re-creates
  // its `AnimationController` over its lifetime (every `animate` / `disableAnimations`
  // transition, not just once), which `SingleTickerProviderStateMixin` explicitly
  // forbids ("can only be used as a TickerProvider once" — its `_ticker` field is
  // never cleared just because the ticker itself was disposed).
  AnimationController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncController();
  }

  @override
  void didUpdateWidget(covariant EqualizerGlyph oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncController();
  }

  /// Starts / stops the ticking controller so it exists if and only if
  /// `widget.animate && !MediaQuery.of(context).disableAnimations` — called from
  /// [didChangeDependencies] (so a live `MediaQuery` flip, e.g. the system reduced-
  /// motion setting toggling mid-session, is honored) and [didUpdateWidget] (so a call
  /// site flipping `animate` at runtime is honored). No-op renders (`animate == false`)
  /// never create a controller, so they never register a `Ticker` — no per-frame cost.
  void _syncController() {
    final shouldAnimate =
        widget.animate && !MediaQuery.of(context).disableAnimations;
    if (shouldAnimate && _controller == null) {
      _controller =
          AnimationController(vsync: this, duration: equalizerAnimationPeriod)
            ..repeat();
    } else if (!shouldAnimate && _controller != null) {
      _controller!.dispose();
      _controller = null;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _EqualizerGlyphPainter(
            widget.color,
            equalizerRestingHeightUnits,
          ),
        ),
      );
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final heights = <double>[
          for (final phase in equalizerBarPhases)
            equalizerHeightUnitsAt(progress: controller.value, phase: phase),
        ];
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: CustomPaint(painter: _EqualizerGlyphPainter(widget.color, heights)),
        );
      },
    );
  }
}

class _EqualizerGlyphPainter extends CustomPainter {
  final Color color;

  /// One height per bar, 24-unit viewBox space, bottom-anchored at [_bottomUnits].
  final List<double> heightUnits;

  _EqualizerGlyphPainter(this.color, this.heightUnits);

  // x / width per the design svg — all bars bottom at y21 (24-unit viewBox).
  static const List<double> _xUnits = [3, 10.5, 18];
  static const double _widthUnits = 3;
  static const double _bottomUnits = 21;
  static const double _radiusUnits = 0.5;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final radius = Radius.circular(_radiusUnits * s);
    for (var i = 0; i < heightUnits.length; i++) {
      final h = heightUnits[i];
      final rect = Rect.fromLTWH(
        _xUnits[i] * s,
        (_bottomUnits - h) * s,
        _widthUnits * s,
        h * s,
      );
      canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), fill);
    }
  }

  @override
  bool shouldRepaint(covariant _EqualizerGlyphPainter old) =>
      old.color != color || !listEquals(old.heightUnits, heightUnits);
}
