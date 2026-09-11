import 'package:flutter/material.dart';

// CcUnavailableTooltip — small dark tooltip bubble shown after tapping the CC (字幕) icon while
// it is in its `unavailable` state.
//
// Spec: `reference-ui-rendering/spec.md` (`rb-flutter-cc-icon-availability-redesign`).
// Design: `design/templates/minimal/sdk-components.jsx` `LBPTooltip` (2026-09-10 R42 sync) —
// `{ show, text, icon, placement }`. A small dark-glass bubble + a triangle arrow pointing at the
// tapped button; design `animation: 'lbp-toast-in 0.16s ease both'` (fade/scale-in), non-hardcoded
// value — approximated here with a plain fade.
//
// PURE presentation — this widget owns NO timer / NO tap handling. The two call sites
// (`operation_rail.dart`'s `_CcPillButton`, `live_bottom_bar_view.dart`'s `_CcTrailingButton`)
// each own a local `show` bool + `Timer` (1.8s auto-hide, mirrors `product_sheets_view.dart`'s
// `_cartToastVisible`/`_cartToastTimer` convention) and drive this widget's [show] + [placement].
// `IgnorePointer`-wrapped so it never eats taps (parity `LBPTooltip`'s `pointerEvents: 'none'`).

/// Where the tooltip bubble sits relative to the tapped button (parity design `placement`).
enum CcTooltipPlacement {
  /// Above the button, arrow pointing down (design `placement="top"`) — the LIVE bottom-bar CC
  /// toggle's position (`live_bottom_bar_view.dart`).
  top,

  /// To the LEFT of the button, arrow pointing right (design `placement="left"`) — the VOD side
  /// rail's CC pill position (`operation_rail.dart`).
  left,
}

/// `rgba(0,0,0,0.9)` — the dark-glass bubble fill (design `LBPTooltip` `background`).
const Color _bubbleFill = Color(0xE6000000);

/// The default「未提供字幕/隱藏式輔助字幕」copy (design-literal, parity `ccTip` call sites).
const String _defaultText = '未提供字幕/隱藏式輔助字幕';

/// The small dark tooltip bubble + triangle arrow (design `LBPTooltip`). `show == false` renders
/// nothing (`SizedBox.shrink`) — same "absent, not just invisible" convention as `LBPTooltip`'s
/// own `if (!show) return null`.
class CcUnavailableTooltip extends StatelessWidget {
  final bool show;
  final String text;
  final CcTooltipPlacement placement;

  /// Extra horizontal offset (px) applied to the ARROW ONLY, independent of the bubble body
  /// (`rb-flutter-cc-tooltip-arrow-anchor-fix`). Consumed ONLY by [CcTooltipPlacement.top] — the
  /// caller (`live_bottom_bar_view.dart`'s `_CcTrailingButton`) computes this via
  /// `arrowCompensationOffset` (`cc_tooltip_layout.dart`) to counteract its OWN outer
  /// `Transform.translate` viewport-edge-clamp shift, so the arrow keeps pointing at the tapped
  /// button's true position even when the bubble itself has been nudged for the clamp.
  /// [CcTooltipPlacement.left] (the VOD side rail, `operation_rail.dart`) ignores this entirely —
  /// that placement never engages the clamp. Default `0` — a no-op — keeps every existing/future
  /// caller that omits this parameter byte-identical to before this field existed.
  final double arrowOffset;

  const CcUnavailableTooltip({
    super.key,
    required this.show,
    this.text = _defaultText,
    this.placement = CcTooltipPlacement.top,
    this.arrowOffset = 0,
  });

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();

    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: _bubbleFill,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    final arrow = CustomPaint(
      size: const Size(10, 5),
      painter: _TooltipArrowPainter(placement: placement),
    );

    final content = placement == CcTooltipPlacement.left
        ? Row(mainAxisSize: MainAxisSize.min, children: [
            bubble,
            SizedBox(
              width: 5,
              height: 10,
              child: CustomPaint(painter: _TooltipArrowPainter(placement: placement)),
            ),
          ])
        : Column(mainAxisSize: MainAxisSize.min, children: [
            bubble,
            // `arrowOffset` shifts only the arrow's PAINT position, not the layout slot Column
            // reserves for it (still centered under the bubble, same as before) — the caller's
            // own outer Transform.translate (the viewport-edge-clamp shift) and this inner one
            // cancel out in screen space when arrowOffset == -that shift (rb-flutter-cc-tooltip-
            // arrow-anchor-fix). `arrowOffset == 0` (the default / common case) makes this a
            // complete no-op, byte-identical to before this parameter existed.
            Transform.translate(offset: Offset(arrowOffset, 0), child: arrow),
          ]);

    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 160),
        builder: (context, opacity, child) => Opacity(opacity: opacity, child: child),
        child: content,
      ),
    );
  }
}

/// Returns the 3 triangle vertices (in path-draw order: first vertex is the `moveTo`, the rest
/// are `lineTo`s before `close()`) for [placement]'s arrow, given the paint [size]. Extracted as
/// a pure function (`unit-test-discipline.md`) so the geometry is directly unit-testable without
/// rasterizing a `CustomPainter`.
///
/// Both branches follow the same rule: the FLAT EDGE (the two vertices that share a coordinate)
/// touches the bubble, and the lone APEX vertex points away from the bubble, toward the tapped
/// button (`rb-flutter-cc-tooltip-left-arrow-direction-fix` — the `.left` branch previously had
/// these two roles swapped, so the arrow visually pointed INTO the bubble instead of at the
/// button; `.top` was already correct and is unchanged here beyond this extraction).
List<Offset> _arrowVertices(CcTooltipPlacement placement, Size size) {
  if (placement == CcTooltipPlacement.left) {
    // Flat edge along the left (x=0, touching the bubble which sits to the left in the
    // `Row(children: [bubble, arrow])` layout); apex on the right (x=size.width), pointing at
    // the button.
    return [
      Offset(0, 0),
      Offset(0, size.height),
      Offset(size.width, size.height / 2),
    ];
  }
  // Flat edge along the top (y=0, touching the bubble which sits above in the
  // `Column(children: [bubble, arrow])` layout); apex on the bottom (y=size.height), pointing at
  // the button.
  return [
    Offset(0, 0),
    Offset(size.width, 0),
    Offset(size.width / 2, size.height),
  ];
}

/// Test-only accessor for [_arrowVertices] (`unit-test-discipline.md` — private top-level pure
/// function, wrapped for direct assertion by `cc_unavailable_tooltip_test.dart` without needing
/// to rasterize a `CustomPainter`; same `*ForTesting` + `@visibleForTesting` pattern as
/// `LiveNowPollController.applyForTesting`).
@visibleForTesting
List<Offset> arrowVerticesForTesting(CcTooltipPlacement placement, Size size) =>
    _arrowVertices(placement, size);

/// A small filled triangle pointing AWAY from the bubble, toward the tapped button (design
/// `arrow` — a CSS border-triangle trick, reproduced here as a 3-point fill).
class _TooltipArrowPainter extends CustomPainter {
  final CcTooltipPlacement placement;

  const _TooltipArrowPainter({required this.placement});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _bubbleFill
      ..style = PaintingStyle.fill;
    final vertices = _arrowVertices(placement, size);
    final path = Path()
      ..moveTo(vertices[0].dx, vertices[0].dy)
      ..lineTo(vertices[1].dx, vertices[1].dy)
      ..lineTo(vertices[2].dx, vertices[2].dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _TooltipArrowPainter old) => old.placement != placement;
}
