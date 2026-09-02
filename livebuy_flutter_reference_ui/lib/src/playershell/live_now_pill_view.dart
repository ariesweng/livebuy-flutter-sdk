import 'package:flutter/widgets.dart';

import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';

// LiveNowPillView — 「現正直播」right-edge half-pill (rb-flutter-live-now-pill).
//
// Spec: `reference-ui-rendering/spec.md`
//   § "LivebuyReferenceUI 渲染現正直播中提示鈕（LiveNowPillView）" — Flutter section.
// Design: `design/contract/claude-design-sync.md` R28 / `components.md` `LBLiveNowPill` /
//   `sdk-components.jsx` `LBLiveNowPill` + `screens.jsx` `LBPPlayerScreen`.
// Flutter parity of iOS `LiveNowPillView.swift` / Android `LiveNowPill.kt` / RN
//   `LiveNowPillView.tsx`.
//
// PURE render: right-edge half-pill (only the left two corners rounded, `999px 0 0 999px`),
// fixed brand-red background, an 11px pulsing white dot + "LIVE" text + a hand-drawn right
// chevron. Does NOT call any API, does NOT poll itself — `onTap` only reports "tapped", the
// turnkey container (`LivebuyPlayer`) resolves what to switch to (see `LiveNowPollController`).
//
// SIZE (fix-flutter-live-now-pill-tap-and-size, 2026-09-02 R28 second sync): every constant below
// was rescaled from the ORIGINAL `rb-flutter-live-now-pill` design tokens to the new, smaller
// ones, preserving each constant's EXISTING mapping to its design-token counterpart (no new scale
// ratio invented). Two design tokens — the pulsing dot's stroked border ring (`dotBorderWidth`)
// and its separate stroked pulse ring (`pulseRingLineWidth` + `inset`) — have NEVER had a
// corresponding dart constant: this implementation's `_LiveDotFrame` is a simplified filled-
// circle-growing-and-fading animation, not the design's literal 3-layer stroked-ring technique.
// That simplification predates this change (from the original `rb-flutter-live-now-pill` build)
// and is left as-is — only the two dot-size numbers that DO have a design-token counterpart (the
// outer ring's max diameter and the solid core's diameter, in `_LiveDotFrame` / `_SolidDotCore`)
// are rescaled.
//
// TOUCH TARGET (fix-flutter-live-now-pill-tap-and-size): the visual pill is only ~26px tall at
// this new size (was ~34px before), sitting flush against the screen's right edge — well under
// the ~44px minimum comfortable touch target (iOS HIG / Material accessibility guidance). A real
// finger's tap landing even 15-20px off the visual center (easy for a short, edge-flush control)
// would otherwise fall through to the always-present full-bleed video-area `GestureDetector`
// underneath instead of registering on the pill. `_extraTapInsetVertical` pads the
// `GestureDetector`'s own hit-test box OUTSIDE the visual `DecoratedBox` — the rendered pixels do
// not move or resize, only the invisible hit region grows.
//
// SHAPE: `border-radius: 999px 0 0 999px` needs only the left two corners rounded — Flutter's
// `BorderRadius.only(topLeft:, bottomLeft:)` supports this natively (same conclusion as
// Android's `RoundedCornerShape` / RN's per-corner style props; unlike iOS, which had to hand-
// roll a `LeadingRoundedRectangle` `Shape` because `RoundedRectangle`/`Capsule` only round all
// four corners together).
//
// SHADOW: the design's directional `box-shadow: -1px 3px 10px rgba(0,0,0,0.25)` (rescaled from
// the original `-2px 4px 14px rgba(0,0,0,0.28)`) is reproduced EXACTLY via `BoxShadow(offset:
// Offset(-1, 3), blurRadius: 10, color: Color(0x40000000))` (`0.25 * 255 ≈ 64 = 0x40`) —
// Flutter's `BoxShadow` natively supports an arbitrary (including negative) offset, unlike
// Android's `Modifier.shadow(elevation:)` / RN's `elevation`, which have no directional control
// (both recorded a "approximation only, not pixel-exact" carve-out for this same shadow). This is
// the one platform of the four that needs no such carve-out.
//
// PULSE ANIMATION: mirrors this package's own established "no-animation-for-determinism"
// convention (`productsheets/product_row.dart`'s `_GridPlayButton`,
// `playershell/player_header_bar_view.dart`'s `_MarqueeTitleLoop`) rather than introducing a new
// cross-widget throttle layer (this package has no `continuousAnimationGate` /
// `LocalContinuousAnimationGate` equivalent, and does not need one — see design.md Decision 6).
// The `AnimationController` is constructed ONLY when [LiveNowPillView.live] is `true` (real
// runtime, the value the turnkey container always passes); the demo / golden / widget-test
// default (`live == false`) renders a STATIC frame — zero `Ticker`, so
// `WidgetTester.pumpAndSettle()` never hangs and goldens stay byte-stable.
//
// CHEVRON GLYPH: hand-drawn with `CustomPainter` (mirrors this package's existing "no icon
// font" convention — `ShareGlyph` / `PersonEditGlyph` / `ShopBagGlyph` / `EqualizerGlyph`), NOT
// a Material icon — tracing the design's own `M9 6l6 6-6 6` chevron path directly.

const Color _pillRed = Color(0xFFF03246);

/// Extra transparent padding added OUTSIDE the visual pill, INSIDE the `GestureDetector` — pads
/// the hit-test box without moving or resizing a single rendered pixel (see the file header's
/// "TOUCH TARGET" note). Chosen so the resulting hit box comfortably clears the ~44px minimum
/// touch-target guidance; not a design token (no visual manifestation), so a future design resync
/// MUST NOT treat this as a value to touch.
const double _extraTapInsetVertical = 10.0;

/// The「現正直播」right-edge half-pill. `onTap` only reports a tap — see the file header for
/// why this leaf never resolves or holds the target video itself.
class LiveNowPillView extends StatelessWidget {
  final ReferenceUITheme theme;

  /// Whether this is composed over a real, live player surface (gates the pulse animation —
  /// see the file header). Default `false` (demo / golden / widget test).
  final bool live;

  /// Tap callback. Default `null` → inert (demo / golden / widget test).
  final VoidCallback? onTap;

  const LiveNowPillView({
    super.key,
    required this.theme,
    this.live = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: LbTestKeys.liveNowPill,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // Touch-target padding (fix-flutter-live-now-pill-tap-and-size) — sits OUTSIDE the
      // DecoratedBox that paints the visual pill, so only the hit-test box grows (see the file
      // header's "TOUCH TARGET" note).
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: _extraTapInsetVertical),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            color: _pillRed,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(999),
              bottomLeft: Radius.circular(999),
            ),
            boxShadow: [
              BoxShadow(color: Color(0x40000000), offset: Offset(-1, 3), blurRadius: 10),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(7, 6, 9, 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _PulsingLiveDot(live: live),
                const SizedBox(width: 4),
                Text(
                  'LIVE',
                  style: TextStyle(
                    color: const Color(0xFFFFFFFF),
                    fontSize: 12 * theme.fontScale,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                  ),
                ),
                const SizedBox(width: 3),
                const _ChevronGlyph(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The 11px pulsing dot: a static 4px solid white core + an outer ring growing 4→11px while
/// fading opacity ~0.6→0 over a 1.6s cycle. See the file header for the `live` throttle gate.
class _PulsingLiveDot extends StatefulWidget {
  final bool live;
  const _PulsingLiveDot({required this.live});

  @override
  State<_PulsingLiveDot> createState() => _PulsingLiveDotState();
}

class _PulsingLiveDotState extends State<_PulsingLiveDot>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.live) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1600),
      )..repeat();
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
    if (controller == null) return const _LiveDotFrame(t: 0);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _LiveDotFrame(t: controller.value),
    );
  }
}

/// One frame of the pulse at progress [t] ∈ [0,1]: the outer ring's diameter interpolates
/// 4→11px while its opacity interpolates 0.6→0; the 4px solid core never changes.
class _LiveDotFrame extends StatelessWidget {
  final double t;
  const _LiveDotFrame({required this.t});

  @override
  Widget build(BuildContext context) {
    final ringDiameter = 4 + (11 - 4) * t;
    final ringOpacity = (0.6 * (1 - t)).clamp(0.0, 1.0);
    return SizedBox(
      width: 11,
      height: 11,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: ringDiameter,
            height: ringDiameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Color.fromRGBO(255, 255, 255, ringOpacity),
            ),
          ),
          const _SolidDotCore(),
        ],
      ),
    );
  }
}

class _SolidDotCore extends StatelessWidget {
  const _SolidDotCore();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 4,
      height: 4,
      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFFFFFFF)),
    );
  }
}

/// Hand-drawn right chevron (design `M9 6l6 6-6 6`), traced directly in a 24-unit space —
/// mirrors this package's existing `ShareGlyph` "no icon font" convention.
class _ChevronGlyph extends StatelessWidget {
  const _ChevronGlyph();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 13,
      height: 13,
      child: CustomPaint(painter: _ChevronGlyphPainter()),
    );
  }
}

class _ChevronGlyphPainter extends CustomPainter {
  const _ChevronGlyphPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide / 24.0;
    final stroke = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(9 * s, 6 * s)
      ..lineTo(15 * s, 12 * s)
      ..lineTo(9 * s, 18 * s);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _ChevronGlyphPainter oldDelegate) => false;
}
