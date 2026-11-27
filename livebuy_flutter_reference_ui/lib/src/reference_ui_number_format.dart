// Safe double → int conversion for reference-ui price / discount display
// (rb-flutter-price-int-conversion-guard, parity iOS
// `ReferenceUINumberFormat.safeInt(_:)` from rb-ios-price-int-conversion-guard).
//
// Why: `LBProduct.price` / `originalPrice` are unbounded `double?` values from the
// API. Dart `double.toInt()` / `floor()` throw `UnsupportedError` on NaN / ±infinity
// (finite values outside int64 saturate instead), and the throw happens inside
// `build`, so the subtree renders an error widget. This helper returns `null` for
// anything that cannot be represented, so callers decide to show nothing.
//
// Pure (no Flutter deps) so it is unit-testable. Not exported from the package.

/// 2^63 as a double — the first value above the int64 range. `-2^63` itself is the
/// smallest int64 and is exactly representable as a double.
const double _twoPow63 = 9223372036854775808.0;

/// Converts [value] to an `int` by truncating toward zero.
///
/// Returns `null` when [value] is NaN or ±infinity, or when the truncated value is
/// outside the signed 64-bit range (`-2^63 <= t < 2^63`). Same semantics as iOS
/// `Int(exactly: value.rounded(.towardZero))`: no clamping / saturation. Every value
/// that converts returns the same result as `value.toInt()`.
int? referenceUiSafeInt(double value) {
  if (!value.isFinite) return null;
  final t = value.truncateToDouble();
  if (t < -_twoPow63 || t >= _twoPow63) return null;
  return t.toInt();
}
