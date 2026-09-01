import 'package:flutter/widgets.dart';

import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';

// MARK: - SheetHeaderCloseButton — shared transparent sheet-header close affordance
//
// Spec: `reference-ui-rendering/spec.md` (family-3 product sheets / family-1 VideoInfoPanel
//        header close). Flutter parity of iOS `SheetKit/SheetHeaderCloseButton.swift` /
//        Android `SheetHeaderCloseButton.kt` (rb-flutter-sheet-header-close-unify).
//
// One shared close glyph for EVERY bottom-sheet header (ProductListSheet / ProductDetailSheet /
// AddToCartSheet / NotifyRestockSheet / VideoInfoPanel), replacing the prior divergence (deep
// `Container(bgSunken) + Icon(Icons.close)` on the detail/restock sheets vs the bare decorative
// `Text('✕')` on the list). Mirrors the design `Icons.close`: a TRANSPARENT 32×32 tap target
// (NO fill) + `✕` in `theme.text` (16). The tap forwards `onTap`.
//
// `isBack` (rb-flutter-product-detail-recommendations §5.4, parity iOS `SheetHeaderCloseButton`
// `isBack`): `ProductDetailSheet`'s nested-recommendation drill-in swaps the glyph to a
// back-chevron `‹` while its container's `detailBreadcrumb` is non-empty — the wired callback
// stays `onTap` either way; only the GLYPH + its dedicated a11y key change. Default `false`
// (every other existing call site — the plain ✕ close, byte-identical).

/// The shared transparent sheet-header close button. 32×32 tap target, no background fill,
/// `✕` in `theme.text` (16) — or `‹` (back-chevron) + a distinct [LbTestKeys.sheetHeaderBack]
/// key when [isBack] is `true`. When [onTap] is null (demo / golden, no host wiring) it stays
/// inert (no gesture) so the golden baseline carries no hit-test artifact.
class SheetHeaderCloseButton extends StatelessWidget {
  final ReferenceUITheme theme;
  final VoidCallback? onTap;
  final bool isBack;

  const SheetHeaderCloseButton({
    super.key,
    required this.theme,
    this.onTap,
    this.isBack = false,
  });

  @override
  Widget build(BuildContext context) {
    final glyph = SizedBox(
      width: 32,
      height: 32,
      child: Center(
        child: Text(
          isBack ? '‹' : '✕',
          style: TextStyle(color: theme.text, fontSize: 16 * theme.fontScale),
        ),
      ),
    );
    final key = isBack ? LbTestKeys.sheetHeaderBack : LbTestKeys.sheetHeaderClose;
    // E2E key (INERT — KeyedSubtree paints nothing) on the shared close button root.
    if (onTap == null) {
      return KeyedSubtree(key: key, child: glyph);
    }
    return KeyedSubtree(
      key: key,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: glyph,
      ),
    );
  }
}
