import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../reference_ui_theme.dart';

// MARK: - HeartBurst — shared floating-burst-glyph widget (`LBPHeartBurst`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-flutter-live-bottom-heart-burst, 問題 5;
//   restyled by rb-flutter-live-like-burst-restyle, design R37;
//   glyph rendering switched to bundled PNGs by rb-flutter-live-like-burst-png-glyphs).
// Design: `design/templates/minimal/sdk-components.jsx` `LBPHeartBurst` (rewritten R37) +
//          `live-chrome.jsx` `LBLiveBottomBar onLike` + `screens.jsx` `likeAnimation`/`doAnimation`.
// Flutter parity of iOS `HeartBurstView.swift` / Android `HeartBurstView.kt`
// (rb-ios-live-bottom-heart-burst / 1733176) — those two changes are tracked separately
// (this repo's R37 batch is per-platform, I7 single-layer/single-change discipline).
//
// A `tick`-driven burst: each time `tick` INCREASES, one glyph spawns at the origin and flies,
// self-removing when its flight completes so repeated ticks never accumulate. Pure presentation —
// never calls core / template.
//
// R37 REWRITE: previously every heart was the SAME accent-colored `Icons.favorite` flying along a
// SINGLE path (fixed upward translate + `dx`/`rot` jitter, 2.4s). Now each spawn independently
// picks ONE of 4 glyph shapes (heart / star / arrow / cross, `pickRandomBurstVariant`) × 3 rise
// trajectories (scale/rotation curves, `BurstTrajectory`) × 3 horizontal swing paths (`BurstSwing`)
// × 2 speeds (800ms / 1000ms) — 4×3×3×2 = 72 possible combinations per spawn, mirroring design's
// `doAnimation()` (`LIKE_ICONS[random]`, `y=random(1..3)`, `swing=random(1..3)`,
// `speed=random(1..2)`). The container's own anchor position is UNCHANGED (still governed by the
// call site — VOD side rail vs. LIVE bottom bar — per existing spec, not touched here).
//
// Golden-neutral: at rest (no in-flight glyph) NOTHING is drawn. `tick` does NOT change during a
// static golden capture, so nothing spawns → baseline carries no burst (matches iOS/Android).
//
// rb-flutter-live-like-burst-png-glyphs: R37's launch approximated the 4 glyph shapes with
// Material `Icons` / a self-drawn badge (heart alone tinted `theme.accent`) because the design's
// reference PNGs were briefly blocked on a DesignSync binary-transfer limitation. That gap is now
// closed — all 4 shapes render their bundled `assets/like_burst/like_*.png` verbatim (see
// `burstGlyphFor`), and NONE of them tint from `theme.accent` any more.

const double _flyDistance = -90; // upward travel (unchanged by R37)
const Duration _burstDurationFast = Duration(milliseconds: 800); // design `speed=1` → 0.8s
const Duration _burstDurationSlow = Duration(milliseconds: 1000); // design `speed=2` → 1.0s

// MARK: - Burst variant (pure, unit-testable — no rendering)

/// Which glyph a spawned burst draws (design `LIKE_ICONS`: heart / star / arrow / cross).
enum BurstShape { heart, star, arrow, cross }

/// Which upward rise/scale/rotation curve a spawned burst follows (design `lbp-like-y-{1,2,3}`).
enum BurstTrajectory { rise1, rise2, rise3 }

/// Which horizontal wobble path a spawned burst follows (design `lbp-like-swing-{1,2,3}`).
enum BurstSwing { swing1, swing2, swing3 }

/// One resolved combination for a single flying burst glyph.
class BurstVariant {
  final BurstShape shape;
  final BurstTrajectory trajectory;
  final BurstSwing swing;
  final Duration duration;

  const BurstVariant({
    required this.shape,
    required this.trajectory,
    required this.swing,
    required this.duration,
  });
}

/// Pick one random shape × rise-trajectory × swing-path × speed combination for a single flying
/// burst glyph (design `doAnimation()`'s `icon`/`y`/`swing`/`speed` random picks). Pure aside from
/// the injected [random] source (default `math.Random()`) — inject a seeded `math.Random(seed)`
/// in tests for determinism.
BurstVariant pickRandomBurstVariant([math.Random? random]) {
  final rng = random ?? math.Random();
  return BurstVariant(
    shape: BurstShape.values[rng.nextInt(BurstShape.values.length)],
    trajectory: BurstTrajectory.values[rng.nextInt(BurstTrajectory.values.length)],
    swing: BurstSwing.values[rng.nextInt(BurstSwing.values.length)],
    duration: rng.nextBool() ? _burstDurationFast : _burstDurationSlow,
  );
}

// MARK: - Keyframe evaluation (pure, unit-testable — piecewise-linear through design's CSS
// `@keyframes` percentage stops)

/// Piecewise-linear interpolation through `(stops[i], values[i])` keyframe pairs at progress [p]
/// (0..1, clamped). [stops] MUST be ascending and the same length as [values].
double _evalKeyframes(List<double> stops, List<double> values, double p) {
  final clamped = p.clamp(0.0, 1.0);
  for (var i = 0; i < stops.length - 1; i++) {
    if (clamped <= stops[i + 1]) {
      final span = stops[i + 1] - stops[i];
      final t = span == 0 ? 0.0 : (clamped - stops[i]) / span;
      return values[i] + (values[i + 1] - values[i]) * t;
    }
  }
  return values.last;
}

const List<double> _riseStops = [0.0, 0.35, 0.8, 1.0];
const Map<BurstTrajectory, List<double>> _riseScaleValues = {
  BurstTrajectory.rise1: [0.2, 1.2, 0.9, 0.6],
  BurstTrajectory.rise2: [0.4, 1.5, 1.0, 0.4],
  BurstTrajectory.rise3: [0.6, 1.7, 1.1, 0.7],
};
const Map<BurstTrajectory, double> _riseRotationDeg = {
  BurstTrajectory.rise1: 0,
  BurstTrajectory.rise2: 20,
  BurstTrajectory.rise3: -30,
};
const List<double> _opacityStops = [0.0, 0.35, 0.8, 1.0];
const List<double> _opacityValues = [0.0, 1.0, 1.0, 0.0];

const List<double> _swing1Stops = [0.0, 0.25, 0.75, 1.0];
const List<double> _swing1Values = [0.0, -16.0, 16.0, 0.0];
const List<double> _swing2Stops = [0.0, 0.33, 1.0];
const List<double> _swing2Values = [0.0, -16.0, 8.0];
const List<double> _swing3Stops = [0.0, 0.25, 0.75, 1.0];
const List<double> _swing3Values = [0.0, 16.0, -16.0, 0.0];

/// Scale multiplier at animation progress [p] (0..1) for [trajectory] — piecewise-linear through
/// design's `lbp-like-y-{1,2,3}` keyframe stops (`0%, 35%, 80%, 100%`).
double burstScaleAt(BurstTrajectory trajectory, double p) =>
    _evalKeyframes(_riseStops, _riseScaleValues[trajectory]!, p);

/// Opacity at animation progress [p] (0..1) — shared by all three rise trajectories
/// (`0%→0, 35%→1, 80%→1, 100%→0`).
double burstOpacityAt(double p) => _evalKeyframes(_opacityStops, _opacityValues, p);

/// Constant rotation (radians) overlaid on the whole flight for [trajectory] — NOT animated over
/// [p] (design applies it as a fixed wrapper transform alongside the keyframed scale, not itself
/// keyframed).
double burstRotationRadiansFor(BurstTrajectory trajectory) =>
    _riseRotationDeg[trajectory]! * math.pi / 180;

/// Horizontal wobble (px) at animation progress [p] (0..1) for [swing] — piecewise-linear through
/// design's `lbp-like-swing-{1,2,3}` keyframe stops.
double burstSwingDxAt(BurstSwing swing, double p) {
  switch (swing) {
    case BurstSwing.swing1:
      return _evalKeyframes(_swing1Stops, _swing1Values, p);
    case BurstSwing.swing2:
      return _evalKeyframes(_swing2Stops, _swing2Values, p);
    case BurstSwing.swing3:
      return _evalKeyframes(_swing3Stops, _swing3Values, p);
  }
}

// MARK: - Glyph widgets (design `assets/like-{heart,star,arrow,cross}.png`, bundled verbatim as
// package assets and rendered via `Image.asset` — rb-flutter-live-like-burst-png-glyphs. Replaces
// the R37 launch's Material `Icons` / self-drawn-badge approximation, which was a stopgap while
// the 4 reference PNGs were blocked on a DesignSync binary-transfer limitation; see that change's
// proposal.md for the timeline.)

/// The bundled asset package name — this package's own `pubspec.yaml` `name:` — required for
/// `Image.asset` to resolve a path bundled INSIDE this package (not the consuming app's own
/// assets). Same convention as `LoadingMarkAnimationView`'s `_framePaths` loading.
const String _assetPackage = 'livebuy_flutter_reference_ui';

/// Build the glyph widget for one burst [shape]. All 4 shapes render their own bundled PNG
/// (`assets/like_burst/like_{heart,star,arrow,cross}.png`) at its baked-in color — NONE of them
/// read [theme] any more (kept as a parameter only so call sites don't need to change).
Widget burstGlyphFor(BurstShape shape, ReferenceUITheme theme, double size) {
  final String assetName;
  switch (shape) {
    case BurstShape.heart:
      assetName = 'assets/like_burst/like_heart.png';
    case BurstShape.star:
      assetName = 'assets/like_burst/like_star.png';
    case BurstShape.arrow:
      assetName = 'assets/like_burst/like_arrow.png';
    case BurstShape.cross:
      // A "+" crosshair mark, deliberately NOT an "x"/close glyph (the source PNG is a
      // 4-segment crosshair, not a dismiss X).
      assetName = 'assets/like_burst/like_cross.png';
  }
  return Image.asset(
    assetName,
    package: _assetPackage,
    width: size,
    height: size,
    fit: BoxFit.contain,
  );
}

/// The shared floating-burst-glyph widget. Spawns one glyph each time [tick] increases.
class HeartBurst extends StatefulWidget {
  final ReferenceUITheme theme;

  /// Monotonic trigger — each increase spawns one burst.
  final int tick;

  /// Glyph size (design `<img width={28} height={28}>` — 26-28 range).
  final double glyphSize;

  const HeartBurst({
    super.key,
    required this.theme,
    required this.tick,
    this.glyphSize = 26,
  });

  @override
  State<HeartBurst> createState() => _HeartBurstState();
}

class _Heart {
  final AnimationController controller;
  final BurstVariant variant;
  _Heart(this.controller, this.variant);
}

class _HeartBurstState extends State<HeartBurst> with TickerProviderStateMixin {
  final List<_Heart> _hearts = [];
  final math.Random _rng = math.Random();

  @override
  void didUpdateWidget(covariant HeartBurst oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only spawn on a CHANGE (mirrors iOS `onChange(of: tick)`), never on the first build.
    if (widget.tick != oldWidget.tick) _spawn();
  }

  void _spawn() {
    final variant = pickRandomBurstVariant(_rng);
    final controller = AnimationController(vsync: this, duration: variant.duration);
    final heart = _Heart(controller, variant);
    setState(() => _hearts.add(heart));
    controller.forward().whenComplete(() {
      if (mounted) setState(() => _hearts.remove(heart));
      controller.dispose();
    });
  }

  @override
  void dispose() {
    for (final h in _hearts) {
      h.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: widget.glyphSize,
        height: widget.glyphSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            for (final h in _hearts)
              AnimatedBuilder(
                animation: h.controller,
                builder: (context, child) {
                  final p = h.controller.value;
                  return Transform.translate(
                    offset: Offset(burstSwingDxAt(h.variant.swing, p), _flyDistance * p),
                    child: Transform.rotate(
                      angle: burstRotationRadiansFor(h.variant.trajectory),
                      child: Transform.scale(
                        scale: burstScaleAt(h.variant.trajectory, p),
                        child: Opacity(opacity: burstOpacityAt(p), child: child),
                      ),
                    ),
                  );
                },
                child: burstGlyphFor(
                  h.variant.shape,
                  widget.theme,
                  widget.glyphSize * widget.theme.fontScale,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
