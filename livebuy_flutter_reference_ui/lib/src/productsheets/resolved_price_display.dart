import 'package:livebuy_flutter/livebuy_flutter.dart' show LBSpec;
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show LBProductDetailState;

// MARK: - ResolvedPriceDisplay — spec-aware, SAME-SOURCE price pair for the product sheets
//
// Spec: `reference-ui-rendering/spec.md`
//   § "Flutter reference-ui 商品明細 / 加入購物車 sheet 價格線跟隨 selectedSpec，售價與原價同源原子解析（Flutter）"
// Change: flutter-product-sheet-spec-price-reference-ui.
//
// ⚠️ FOUR-PLATFORM PARITY — THIS FILE MIRRORS THE iOS LEAD VERBATIM ⚠️
// iOS is the LEAD platform for this rule:
// `ios/Sources/LivebuyReferenceUI/ProductSheets/ResolvedPriceDisplay.swift`
// (change `ios-product-sheet-spec-price-reference-ui`). Same type name, same function
// name, same field names, same degradation ladder, same test matrix. Android
// (`ResolvedPriceDisplay.kt`) and React Native (`resolvedPriceDisplay.ts`) mirror it too.
// Do NOT "improve" the shape here without re-deriving all four platforms.
//
// ── WHY A SINGLE FUNCTION RETURNING A PAIR (and not two independent resolvers) ──
//
// The sale price and the struck-through original price MUST come from the SAME
// SOURCE. If they are resolved by two independent `??` fallbacks, the two can
// silently disagree the moment their degradation conditions differ — producing a
// FAKE DISCOUNT RATE on screen, e.g.:
//
//     spec sale NT$ 290  ×  product original NT$ 590   → claims 51% off
//     (reality: the product level is NT$ 390 / NT$ 590)
//
// Returning ONE value object makes the mismatch UNREPRESENTABLE rather than merely
// discouraged-by-comment. Each independent resolver would also unit-test "correct"
// in isolation while the composed screen is wrong — the exact failure mode that is
// most likely to be re-introduced when this rule is mirrored across platforms.
//
// ── DEGRADATION LADDER ──
//
//   1. `selectedSpec == null` (selection incomplete / unresolvable)
//        → the WHOLE PAIR falls back to the product level.
//        Mirrors the view-model's existing stock fallback shape
//        (`final spec = variantPicker.selectedSpec; final stock = spec?.stock ?? detail.stock;`,
//        `flutter-ui/lib/src/default_template.dart:1170-1174` — NOT modified by this change).
//   2. `selectedSpec != null` but its `priceShow` is blank (empty / whitespace-only)
//        → the WHOLE PAIR falls back to the product level.
//   3. otherwise
//        → the WHOLE PAIR is taken from the spec — INCLUDING a blank original price.
//
// ── WHY A BLANK `originalPriceShow` DOES *NOT* TRIGGER FALLBACK ──
//
// This is the single most mirror-fragile clause in the contract, so the reasoning is
// spelled out. The two fields are NOT symmetric:
//
//   • `priceShow` (sale price) is a MANDATORY-TO-DRAW field. A blank sale price
//     cannot be rendered, so a spec carrying one does not stand up as a source at
//     all → the whole pair falls back.
//   • `originalPriceShow` (was-price / strike-through) is an OPTIONAL-TO-DRAW field.
//     "This variant has no was-price" is a LEGITIMATE *no-discount* state, not a
//     data gap — the product level has always treated a blank original the same way.
//
// So a blank original MUST keep the spec source and simply not draw the strike-through.
// The two rejected alternatives, for the record:
//
//   • blank original → fall back the whole pair  ⇒ the screen would show the PRODUCT'S
//     SALE PRICE while the user has a NT$ 290 variant selected. Displayed price ≠ price
//     actually added to cart — far worse than a missing strike-through.
//   • blank original → borrow the product's original, keep the spec's sale price
//     ⇒ violates same-source atomicity outright, i.e. the fake discount above.
//
// ── BLANK CHECKS TRIM; RETURNED STRINGS ARE NEVER TRIMMED ──
//
// Per the SDK's JSON-decoder tolerance rules a free-text field may arrive as `''` or
// whitespace-only, so emptiness is judged AFTER trimming. But trimming is used for
// JUDGEMENT ONLY: the returned strings are the ORIGINALS, character for character.
// Returning a trimmed string would change rendered pixels (a merchant may pad
// `priceShow` deliberately) and would let per-platform trimming differences
// (Dart `String.trim()` vs Swift `trimmingCharacters(in:.whitespacesAndNewlines)` vs
// Kotlin `isBlank()`) grow into cross-platform visual drift.
//
// ── FLUTTER-SPECIFIC NULLABILITY CONVERGENCE ──
//
// `LBSpec.priceShow` / `LBSpec.originalPriceShow` are NON-NULLABLE `String` (default `''`),
// but `LBProductDetailState.originalPriceShow` is a NULLABLE `String?`. This file is the
// SINGLE convergence point: the product-level pair normalizes it with `?? ''`, so both
// fields of [ResolvedPriceDisplay] are ALWAYS non-null `String` (`''` = that source
// genuinely has no was-price). Downstream rendering therefore needs NO `!` null
// assertion — the previous `detail.originalPriceShow!` in the price row is gone, and a
// null-assertion crash is structurally impossible.
//
// `LBSpec.price` / `LBSpec.originalPrice` (the `double?` NUMERIC fields) are deliberately
// NOT read here — this rule is about the display strings only.

/// A same-source price pair for the product sheets' price row: the sale price plus its
/// optional struck-through original, resolved together so they can never disagree.
///
/// Produced ONLY by [resolvePriceDisplay] — do not construct the two fields from
/// different sources at a call site (that is precisely what this type exists to prevent).
class ResolvedPriceDisplay {
  /// The sale price to draw, verbatim from whichever source won (spec or product).
  final String priceShow;

  /// The original ("was") price to strike through, verbatim from the SAME source as
  /// [priceShow]. May be `''` — meaning that source genuinely has no was-price.
  final String originalPriceShow;

  const ResolvedPriceDisplay({
    required this.priceShow,
    required this.originalPriceShow,
  });

  /// Whether a struck-through original price worth drawing exists.
  ///
  /// True only when [originalPriceShow] is non-blank AND differs from [priceShow]
  /// (an original equal to the sale price is not a discount). Both sides are trimmed
  /// for the comparison only — see the file header note on trimming.
  ///
  /// The sheet MUST read this instead of re-deriving "is there an original?" from
  /// `detail` / `selectedSpec`, so that WHETHER a strike-through is drawn and WHICH
  /// string is drawn always agree.
  bool get hasOriginalPrice {
    final original = originalPriceShow.trim();
    if (original.isEmpty) return false;
    return original != priceShow.trim();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResolvedPriceDisplay &&
          other.priceShow == priceShow &&
          other.originalPriceShow == originalPriceShow;

  @override
  int get hashCode => Object.hash(priceShow, originalPriceShow);

  @override
  String toString() =>
      'ResolvedPriceDisplay(priceShow: $priceShow, originalPriceShow: $originalPriceShow)';
}

/// Resolves the sheet's price pair from the product detail and the currently selected
/// spec, ATOMICALLY: both returned fields always come from the same source.
///
/// - [detail]: the product-level detail (`DefaultProductSheet.detail`).
/// - [selectedSpec]: the resolved variant spec (`DefaultVariantPicker.selectedSpec`), or
///   `null` when the selection is incomplete / unresolvable.
///
/// Returns a [ResolvedPriceDisplay] whose two fields are both from [selectedSpec] or
/// both from [detail] — never mixed.
///
/// Pure: no I/O, no global state, no mutation. Safe to call per-build.
ResolvedPriceDisplay resolvePriceDisplay({
  required LBProductDetailState detail,
  required LBSpec? selectedSpec,
}) {
  // The product-level pair — the SINGLE fallback target for BOTH degradation rungs,
  // so a fallback can never take one field from the spec and the other from here.
  // This is also where the nullable `String?` converges to a non-null `String`.
  final productLevel = ResolvedPriceDisplay(
    priceShow: detail.priceShow,
    originalPriceShow: detail.originalPriceShow ?? '',
  );

  // Rung 1 — selection incomplete / unresolvable → whole pair from the product.
  final spec = selectedSpec;
  if (spec == null) return productLevel;

  // Rung 2 — the spec cannot supply a drawable sale price → whole pair from the
  // product. NOTE this deliberately discards a non-blank `spec.originalPriceShow`
  // too: keeping it would be exactly the mixed-source fake discount this type bans.
  if (_isBlank(spec.priceShow)) return productLevel;

  // Rung 3 — whole pair from the spec, INCLUDING a blank original price (a genuine
  // "this variant has no was-price" → strike-through simply isn't drawn).
  return ResolvedPriceDisplay(
    priceShow: spec.priceShow,
    originalPriceShow: spec.originalPriceShow,
  );
}

/// Blank (empty or whitespace-only) — the emptiness test used by every rung above.
/// Judgement only; never applied to a returned string.
bool _isBlank(String value) => value.trim().isEmpty;
