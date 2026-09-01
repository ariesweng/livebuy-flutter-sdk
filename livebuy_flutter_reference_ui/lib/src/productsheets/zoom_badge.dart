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
          // Handle — a short rotated bar running to the lower-right.
          Positioned(
            right: diameter * 0.2,
            bottom: diameter * 0.18,
            child: Transform.rotate(
              angle: math.pi / 4, // 45°
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
