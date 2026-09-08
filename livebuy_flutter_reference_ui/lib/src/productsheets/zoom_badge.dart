import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../testing/lb_test_keys.dart';

// ZoomBadge — decorative media-zoom affordance (family-3 product sheets, Flutter).
//
// Spec: `reference-ui-rendering/spec.md` (family-3 product + sheets — zoom badges).
// Parity of the iOS `ProductDetailSheetView` / `NotifyRestockSheetView` zoom disc
// (rb-ios-product-sheets follow-on `8f8fad0` #8) and Android `ZoomBadge.kt` / RN
// `ZoomBadge.tsx`. Design: `design/templates/minimal/screens.jsx` — ProductDetailSheet
// 4:3 media zoom disc (644-647: 32×32, rgba(255,255,255,0.85), Icons.zoom #15131a) and
// NotifyRestockSheet 96×96 thumb zoom disc (790-793: 24×24, rgba(0,0,0,0.55), white).
//
// TAPPABLE (rb-flutter-product-image-zoom-lightbox): the badge paints the design's
// media-zoom affordance AND, when [onTap] is non-null, opens the full-frame
// `ProductImageZoomOverlay`. The magnifier glyph is drawn with deterministic composed
// widgets (a bordered lens circle + a rotated handle) — NOT a Material `Icon` (which
// renders as tofu in golden) — so the golden shows a correct magnifier, consistent with
// the iOS / Android / RN self-drawn glyphs. `onTap == null` (demo / golden) → no
// `GestureDetector` → the golden is byte-identical to the prior decorative badge.
//
// GEOMETRY FIX (rb-flutter-product-detail-zoom-badge-glyph-alignment): the handle's
// position/rotation is derived from the lens circle's own center + radius (below),
// NOT independent magic numbers — a prior version positioned the handle via unrelated
// `right`/`bottom` offsets with the WRONG `Transform.rotate` sign, leaving the handle
// floating away from the lens along the wrong diagonal (a "/" shape instead of the
// correct outward "\" shape radiating from the lens toward the bottom-right corner).
// This mirrors Android `ZoomBadge.kt`'s `MagnifierGlyph`, which derives its handle's
// start point from `lensCenter + edge*(1,1)` — always connected, any `diameter`.

/// A circular zoom badge: a [diameter] disc filled [discColor] with a centered
/// self-drawn magnifier glyph in [glyphColor]. Tap ([onTap]) opens the lightbox.
class ZoomBadge extends StatelessWidget {
  const ZoomBadge({
    super.key,
    required this.diameter,
    required this.discColor,
    required this.glyphColor,
    this.onTap,
  });

  /// Disc diameter (32 on the detail 4:3 photo, 24 on the 96 thumb).
  final double diameter;

  /// Disc fill (white@0.85 on detail, black@0.55 on restock).
  final Color discColor;

  /// Magnifier glyph color (#15131A on detail, white on restock).
  final Color glyphColor;

  /// Tap handler → container opens the lightbox. `null` (demo / golden) → inert
  /// (no `GestureDetector`), golden byte-identical to the prior decorative badge.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final lens = diameter * 0.42;
    final stroke = math.max(1.0, diameter * 0.08);
    final handleLen = diameter * 0.26;
    // Lens circle geometry (centerline) — same box this build() positions the lens
    // Container at (`left`/`top`: diameter*0.22, `width`/`height`: lens), so its center
    // is at `diameter*0.22 + lensRadius` on both axes (the lens box is square).
    final lensRadius = lens / 2;
    final lensCenter = diameter * 0.22 + lensRadius;
    // k = cos(45°) == sin(45°) — the (+1,+1) unit diagonal the handle radiates along.
    const k = 0.7071067811865476; // sqrt(2) / 2
    // p1 — the point ON the lens circle's edge, along the (+1,+1) diagonal: the
    // handle's near endpoint. handleCenter — the midpoint of the handle segment
    // running from p1 outward by handleLen along the same diagonal.
    final p1 = lensCenter + lensRadius * k;
    final handleCenter = p1 + (handleLen * k) / 2;
    final Widget disc = Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(color: discColor, shape: BoxShape.circle),
      child: Stack(
        children: [
          // Lens — a bordered circle in the upper-left.
          Positioned(
            left: diameter * 0.22,
            top: diameter * 0.22,
            child: Container(
              width: lens,
              height: lens,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: glyphColor, width: stroke),
              ),
            ),
          ),
          // Handle — a short rotated bar running to the lower-right, anchored to the
          // lens circle's edge (see lensRadius/lensCenter/p1/handleCenter above).
          Positioned(
            left: handleCenter - stroke / 2,
            top: handleCenter - handleLen / 2,
            child: Transform.rotate(
              angle: -math.pi / 4, // -45° — the (+1,+1) outward diagonal
              child: Container(
                width: stroke,
                height: handleLen,
                decoration: BoxDecoration(
                  color: glyphColor,
                  borderRadius: BorderRadius.circular(stroke / 2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    // onTap == null (demo / golden) → return the disc as-is (no GestureDetector) so the
    // golden is byte-identical to the prior decorative badge. Non-null → tappable.
    // E2E key (INERT — KeyedSubtree paints nothing) on the badge root.
    if (onTap == null) return KeyedSubtree(key: LbTestKeys.zoomBadge, child: disc);
    return KeyedSubtree(
      key: LbTestKeys.zoomBadge,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: disc,
      ),
    );
  }
}
