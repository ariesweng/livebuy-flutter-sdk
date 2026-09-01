// Single http→https upgrade point for remote product images
// (rb-flutter-product-image-https-upgrade, parity with iOS ReferenceUIImageURL /
// Android & RN referenceUiHttpsUpgraded).
//
// Why: some backend product `pic` URLs are cleartext `http://` (e.g. shop P1MUv99J's
// 測試零食). On Flutter iOS, App Transport Security blocks cleartext, so Image.network
// never loads the image → the placeholder stays. The Livebuy image host serves the same
// path over TLS (it even 301-redirects http→https), so upgrading the scheme client-side
// makes the image load.
//
// Pure (no Flutter deps) so it is unit-testable. Only the `http` scheme is rewritten;
// `https`, other schemes, relative paths, null and empty are returned unchanged
// (null / empty → "").

/// If [url] starts with a cleartext `http://` scheme (case-insensitive), return it with an
/// `https://` scheme (host / path / query preserved); otherwise return [url] unchanged
/// (null / empty → empty string).
String referenceUiHttpsUpgraded(String? url) {
  final s = url ?? '';
  if (s.toLowerCase().startsWith('http://')) {
    return 'https://${s.substring('http://'.length)}';
  }
  return s;
}
