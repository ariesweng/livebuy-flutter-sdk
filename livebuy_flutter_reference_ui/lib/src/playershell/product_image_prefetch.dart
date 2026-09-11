import 'package:flutter/widgets.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart' show LBProduct;

import '../reference_ui_image_url.dart';

// product_image_prefetch.dart — rb-flutter-product-image-loading-polish.
//
// Spec: `reference-ui-rendering/spec.md` § "Flutter 商品照片載入優化" (ADDED).
//
// The FULL (unfiltered) product list arrives at video-load time — well before any
// individual product's `[beginTime,endTime)` (VOD) or `narrate_status==2` (LIVE)
// introducing window opens and its card actually gets built. `PlayerShellView` (see
// `_maybePrefetchProductImages`) uses the pure function below to resolve WHICH image
// URLs are worth warming into Flutter's own `ImageCache` via `precacheImage`, well
// ahead of the moment `liveProductImage` (`sheet_scaffold.dart`) would otherwise start
// loading them for the first time.

/// Resolve the de-duplicated, valid http(s) image URL for every product in
/// [products] — `photos.first ?? pic` (mirrors the SAME source resolution
/// `_buildNowIntroducing` already uses to build an `LBMiniCartPeek.pic`), upgraded
/// http → https (`referenceUiHttpsUpgraded`, the same upgrade `liveProductImage`'s own
/// gate applies) and filtered to a parseable `http`/`https` scheme. Preserves
/// [products]' own order; a later duplicate URL is dropped (first occurrence wins).
/// Pure — no Flutter runtime / IO — independently unit-testable.
List<String> productImageUrlsToPrefetch(List<LBProduct> products) {
  final seen = <String>{};
  final result = <String>[];
  for (final p in products) {
    final raw = p.photos.isNotEmpty ? p.photos.first : p.pic;
    final url = _validHttpUrl(raw);
    if (url == null || !seen.add(url)) continue;
    result.add(url);
  }
  return result;
}

/// Pure: upgrades a cleartext `http://` [raw] URL to `https://`, then returns it only
/// if it parses as a non-empty `http`/`https` [Uri] — else `null`. Deliberately a
/// SEPARATE small check from `sheet_scaffold.dart`'s private `_httpUri` (same shape,
/// built on the same PUBLIC `referenceUiHttpsUpgraded`) rather than exporting that
/// file's private helper for one extra caller — see design.md Decision 3.
String? _validHttpUrl(String raw) {
  final upgraded = referenceUiHttpsUpgraded(raw.trim());
  if (upgraded.isEmpty) return null;
  final uri = Uri.tryParse(upgraded);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return upgraded;
}

/// Optional override hook for testing (`docs/unit-test-discipline.md` §3 "Dual-use
/// 例外" — read by PRODUCTION code too, at `player_shell_view.dart`'s own
/// `_precacheProductImage` call site, so this deliberately carries no
/// `@visibleForTesting` annotation; that annotation would flag the cross-file
/// production read as `invalid_use_of_visible_for_testing_member`). `null` (production
/// default) → [defaultProductImagePrecache] (the real
/// `precacheImage(NetworkImage(url), context)`). A widget test overrides this to
/// capture WHICH urls were requested without a real network fetch / image decode, then
/// MUST reset it to `null` afterward.
Future<void> Function(String url, BuildContext context)?
    productImagePrecacheForTesting;

/// Production default for the prefetch side effect — Flutter's own `ImageCache` via
/// `precacheImage`, no custom cache (design.md Goals). Swallows any load/decode error
/// (a failed prefetch just means `liveProductImage` falls back to its normal
/// load-on-build path later — never a crash / unhandled rejection).
Future<void> defaultProductImagePrecache(String url, BuildContext context) =>
    precacheImage(NetworkImage(url), context).catchError((_) {});
