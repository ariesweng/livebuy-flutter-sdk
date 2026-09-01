import 'package:livebuy_flutter/livebuy_flutter.dart' show LBSpec;
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show LBProductDetailState;

// MARK: - ResolvedProductPhoto — spec-aware product photo SOURCE for the product sheets
//
// Spec: `reference-ui-rendering/spec.md`
//   § "Flutter reference-ui 商品明細 / 加入購物車 sheet 與 zoom 燈箱的商品主圖跟隨 selectedSpec，
//      來源有效性與所繪項目同述詞解析（Flutter）"
// Change: flutter-product-sheet-spec-photo-reference-ui.
// Sibling: `resolved_price_display.dart` (flutter-product-sheet-spec-price-reference-ui) — same
// skeleton, same degradation-ladder shape, same "single shared fallback target" structure.
//
// ⚠️ FOUR-PLATFORM PARITY — THIS FILE MIRRORS THE iOS LEAD VERBATIM ⚠️
// iOS is the LEAD platform for this rule:
// `ios/Sources/LivebuyReferenceUI/ProductSheets/ResolvedProductPhoto.swift`
// (change `ios-product-sheet-spec-photo-reference-ui`). Same type name, same function name,
// same field names, same degradation ladder, same `primaryPhoto` predicate, same test matrix.
// Android (`ResolvedProductPhoto.kt`) and React Native (`resolvedProductPhoto.ts`) mirror it too.
// Do NOT "improve" the shape here without re-deriving all four platforms.
// The ONE thing that is deliberately NOT mirrored is iOS's `primaryPhotoURL` — see the
// "NO URL ADAPTER" note below.
//
// ── WHY THE RESULT IS THE WHOLE ARRAY (and not a single resolved URL) ──
//
// What this resolution decides is the SOURCE (the selected spec, or the product level).
// "Which one of its photos do we draw" is a DERIVED question, asked after the source is
// settled. If the function returned a single value, the source decision would be buried
// inside that value and lost: every additional consumer (the zoom lightbox today, a
// multi-image gallery tomorrow) would have to RE-DERIVE the degradation ladder for itself
// — and the moment two derivations disagree, the screen shows the spec's photo in the
// sheet and the product's photo in the lightbox.
//
// That is the same failure mode `ResolvedPriceDisplay` exists to make unrepresentable
// (two independent `??` fallbacks silently disagreeing), transposed onto photos. Returning
// the array makes the source decision happen EXACTLY ONCE; every consumer reads the same
// resolved source, and [ResolvedProductPhoto.primaryPhoto] is the single place that
// answers "which one".
//
// ── DEGRADATION LADDER ──
//
//   1. `selectedSpec == null` (selection incomplete / unresolvable)
//        → the product level. Mirrors the view-model's existing stock fallback shape
//        (`final spec = variantPicker.selectedSpec; final stock = spec?.stock ?? detail.stock;`,
//        `flutter-ui/lib/src/default_template.dart:1170-1174` — NOT modified by this change)
//        and the sibling price resolver's rung 1.
//   2. `selectedSpec != null` but its `photos` is empty, OR contains no entry that is
//      non-blank after trimming
//        → the product level (that source cannot draw anything, so it does not stand up
//        as a source at all).
//   3. otherwise
//        → the spec's photos.
//
// ── THE MOST MIRROR-FRAGILE CLAUSE: `primaryPhoto` IS *NOT* `photos.first` ──
//
// [ResolvedProductPhoto.primaryPhoto] is the FIRST NON-BLANK entry, not the first entry.
// This is load-bearing, and an implementation using `photos.first` will still pass the two
// obvious tests ("spec has no photos" / "spec's first photo is valid") while being wrong:
//
//     spec.photos == ['', 'https://cdn/spec-rose.jpg']
//
//   • rung 2 asks "does this source have anything drawable?" → YES → the source is
//     LOCKED to the spec, no fallback to the product level.
//   • a `photos.first` display predicate then reads `''` → null → the sheet draws the
//     gradient + monogram PLACEHOLDER.
//
// So the user picks a variant that demonstrably HAS a photo and sees a monogram, with no
// product photo to fall back to either — strictly WORSE than before this change. The fix
// is not a bigger comment: "is this source valid" and "what do we draw" MUST BE THE SAME
// PREDICATE. [resolveProductPhoto] therefore spells rung 2 as `primaryPhoto == null` on a
// candidate value, so the two are coupled STRUCTURALLY and cannot drift apart. Writing the
// guard as `spec.photos.isNotEmpty` — or as a SECOND copy of the predicate such as
// `photos.any((s) => s.trim().isNotEmpty)` — is exactly the drift this shape forbids.
//
// Side effect, deliberate and accepted: the PRODUCT level gets the same predicate, so
// `detail.photos == ['', 'https://…']` now loads that photo instead of drawing a
// placeholder. A strict improvement, observable only on the host-runtime path that loads
// real images (`live == true`); the golden path never loads images, so baselines are
// untouched.
//
// ── ⚠️ DART DIFFERENCE FROM THE iOS LEAD: `List.first` THROWS ON AN EMPTY LIST ──
//
// Swift's `Array.first` returns `nil` for an empty array; Dart's `List.first` throws a
// `StateError`. Transcribing the Swift verbatim would therefore CRASH on the single most
// common rung-2 input (`spec.photos == []`). [ResolvedProductPhoto.primaryPhoto] is
// consequently written with a `firstWhere(..., orElse: () => null)` over a `String?` view;
// the SEMANTICS stay identical to the lead, only the safe-access form differs. This is the
// only shape adjustment Flutter makes when mirroring this contract.
//
// ── BLANK CHECKS TRIM; RETURNED STRINGS ARE NEVER TRIMMED ──
//
// Per the SDK's JSON-decoder tolerance rules a free-text field may arrive as `''` or
// whitespace-only, so emptiness is judged AFTER trimming. Trimming is for JUDGEMENT ONLY:
// [ResolvedProductPhoto.photos] and [ResolvedProductPhoto.primaryPhoto] hand back the
// ORIGINAL strings, character for character, and `photos` is a VERBATIM copy of the
// winning source — never filtered, reordered, or cleaned up. (Filtering out the blanks
// here would quietly change indices, which a future gallery would then disagree with.)
//
// ── NO URL ADAPTER (unlike iOS) ──
//
// iOS carries a `primaryPhotoURL` returning `Foundation.URL?`, because `URL(string:)` fails
// on a padded string. That property is explicitly iOS-LOCAL and NOT part of the
// four-platform contract. Flutter needs no equivalent: the existing `liveProductImage`
// helper takes a plain `String?` url, so call sites consume [primaryPhoto] directly.

/// The resolved product-photo SOURCE for the product sheets: whichever array of photo
/// strings won — the selected spec's, or the product's — together with the single answer
/// to "which one do we draw".
///
/// Produced ONLY by [resolveProductPhoto] — do not pick a photo out of `detail.photos` /
/// `selectedSpec.photos` at a call site (that is precisely what this type exists to prevent).
class ResolvedProductPhoto {
  /// The winning source's photo strings, VERBATIM — same order, same elements, blanks
  /// included. Never a mix of the two sources, never filtered or reordered.
  final List<String> photos;

  const ResolvedProductPhoto({required this.photos});

  /// The photo to draw: the FIRST entry that is non-blank after trimming, returned
  /// VERBATIM (untrimmed). `null` when this source has nothing drawable.
  ///
  /// NOT `photos.first` — see the file header. This predicate is also what
  /// [resolveProductPhoto] uses to decide whether a source is valid at all, so "the ladder
  /// picked this source" and "this source can be drawn" are the same statement by
  /// construction.
  ///
  /// SAFE ON AN EMPTY LIST: Dart's `List.first` throws `StateError` where Swift's
  /// `Array.first` returns `nil`, so this uses `firstWhere(..., orElse: () => null)` over a
  /// `String?` view. `photos == []` yields `null`, never an exception.
  String? get primaryPhoto => photos
      .cast<String?>()
      .firstWhere((photo) => !_isBlank(photo!), orElse: () => null);

  /// Whether there is a photo worth drawing — i.e. whether the caller should load an
  /// image instead of the deterministic gradient + monogram placeholder.
  ///
  /// The sheets MUST read this (or [primaryPhoto]) instead of re-deriving "are there
  /// photos?" from `detail` / `selectedSpec`, so that WHETHER an image is drawn and WHICH
  /// image is drawn always agree.
  bool get hasPhoto => primaryPhoto != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResolvedProductPhoto && _photosEqual(other.photos, photos);

  @override
  int get hashCode => Object.hashAll(photos);

  @override
  String toString() => 'ResolvedProductPhoto(photos: $photos)';
}

/// Resolves the sheet's product-photo SOURCE from the product detail and the currently
/// selected spec.
///
/// - [detail]: the product-level detail (`DefaultProductSheet.detail`).
/// - [selectedSpec]: the resolved variant spec (`DefaultVariantPicker.selectedSpec`), or
///   `null` when the selection is incomplete / unresolvable.
///
/// Returns a [ResolvedProductPhoto] whose `photos` is a verbatim copy of either
/// `selectedSpec.photos` or `detail.photos` — never a mix, never filtered.
///
/// Pure: no I/O, no global state, no mutation. Safe to call per-build.
ResolvedProductPhoto resolveProductPhoto({
  required LBProductDetailState detail,
  required LBSpec? selectedSpec,
}) {
  // The product-level source — the single shared fallback target for BOTH degradation
  // rungs, so a fallback can never assemble a result out of two sources.
  final productLevel = ResolvedProductPhoto(photos: detail.photos);

  // Rung 1 — selection incomplete / unresolvable → product level.
  final spec = selectedSpec;
  if (spec == null) return productLevel;

  // Rung 2 — the spec source cannot draw anything → product level.
  //
  // The validity test is deliberately expressed as `primaryPhoto == null` ON THE CANDIDATE
  // ITSELF rather than as a separate `isNotEmpty` / `any(...)` scan. That is what makes
  // "this source is valid" and "this source has something to draw" ONE predicate instead of
  // two that can drift — see the file header's `['', 'url']` walkthrough for what drift costs.
  final specLevel = ResolvedProductPhoto(photos: spec.photos);
  if (specLevel.primaryPhoto == null) return productLevel;

  // Rung 3 — the spec source wins, verbatim (blanks and ordering preserved).
  return specLevel;
}

/// Blank (empty or whitespace-only) — the emptiness test used by
/// [ResolvedProductPhoto.primaryPhoto] and, through it, by the ladder's rung 2.
/// Judgement only; never applied to a returned value.
bool _isBlank(String value) => value.trim().isEmpty;

/// Element-wise list equality (kept local so this file stays free of `flutter/` imports,
/// matching the sibling `resolved_price_display.dart`).
bool _photosEqual(List<String> a, List<String> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
