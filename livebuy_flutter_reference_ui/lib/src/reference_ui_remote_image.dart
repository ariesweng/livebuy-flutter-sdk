import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

// reference_ui_remote_image.dart — rb-flutter-remote-image-downsampling.
//
// Spec: `reference-ui-rendering/spec.md` § "Flutter 遠端靜態圖依顯示尺寸分層降採樣解碼".
//
// The single place this package turns a remote image URL into an [ImageProvider]. Every
// remote still image (product photo / video cover / shop logo / upcoming cover / zoom
// lightbox) and the background prefetch go through [referenceUiRemoteImageProvider].
//
// Flutter has no image disk cache, and `ImageCache` keys include the decode size — every
// distinct decode size of one URL is a separate download. So instead of decoding each box
// at its own size, a URL is decoded at one of only TWO sizes ("tiers"):
//   • thumbnail — every small box (list rows, thumbnail strips, now-introducing / pinned /
//     compact cards, chips, logos) and the background prefetch;
//   • large — everything else (product-detail main image, zoom lightbox, covers).
// Every surface of a tier resolves an EQUAL provider (one cache entry, one download), so a
// URL is downloaded at most twice, and the main image and the lightbox share one decode.
//
// Not exported from the package barrel — internal to `livebuy_flutter_reference_ui`.

/// Decode-size ladder (physical px): powers of two and their 1.5× — the same ladder as
/// Android `stillImageBucketPx`. Rounding a tier's size up to a step keeps the cache key
/// stable across devices whose pixel density differs only slightly.
const List<int> kReferenceUiImageBucketsPx = <int>[
  64, 96, 128, 192, 256, 384, 512, 768, 1024, 1536, 2048, 3072, 4096, //
];

/// A box whose longer side is at most this many logical px is a thumbnail-tier box. Covers
/// every fixed-size small box in the package (36 – 100).
const double kThumbnailTierMaxLogicalSide = 128;

/// The zoom lightbox's maximum paint-time magnification; the large tier is sized so an
/// image filling the screen's shorter side stays sharp at this factor.
const double kLargeTierMaxZoom = 2.4;

/// Screen size assumed when no `MediaQuery` is in scope.
const Size kReferenceUiFallbackScreenSize = Size(390, 844);

/// The two decode sizes a remote image URL can be requested at — see the file header.
enum ReferenceUiImageTier { thumbnail, large }

/// Rounds [neededPx] UP to the next step of [kReferenceUiImageBucketsPx]. Anything above
/// the last step (including `+infinity`) clamps to it; non-positive / NaN → the first step.
/// Pure.
int referenceUiImageBucketPx(double neededPx) {
  if (neededPx.isNaN || neededPx <= 0) return kReferenceUiImageBucketsPx.first;
  for (final int step in kReferenceUiImageBucketsPx) {
    if (step >= neededPx) return step;
  }
  return kReferenceUiImageBucketsPx.last;
}

/// The tier of a box of [logicalSize]: thumbnail when BOTH sides are bounded and at most
/// [kThumbnailTierMaxLogicalSide]; large otherwise (incl. an unbounded side). Pure.
ReferenceUiImageTier referenceUiImageTierForBox(Size logicalSize) {
  final double longer = math.max(logicalSize.width, logicalSize.height);
  return longer.isFinite && longer <= kThumbnailTierMaxLogicalSide
      ? ReferenceUiImageTier.thumbnail
      : ReferenceUiImageTier.large;
}

/// The decode size of [tier] — the physical-px length the decoded image's SHORTER side is
/// at least (source permitting), bucketed and capped at the ladder's last step.
///
/// - thumbnail: [kThumbnailTierMaxLogicalSide] × [devicePixelRatio] — covers the largest
///   thumbnail-tier box whatever the image's aspect ratio.
/// - large: `max(longer screen side, shorter screen side × kLargeTierMaxZoom)` ×
///   [devicePixelRatio] — covers a full-screen box, and the lightbox at max zoom.
///
/// Depends only on the tier, the screen and the pixel density — never on the individual
/// box — which is what makes every surface of a tier share one cache entry. Pure.
int referenceUiImageTierSidePx(
  ReferenceUiImageTier tier, {
  required Size screenLogicalSize,
  required double devicePixelRatio,
}) {
  final double dpr = devicePixelRatio.isFinite && devicePixelRatio > 0 ? devicePixelRatio : 1.0;
  switch (tier) {
    case ReferenceUiImageTier.thumbnail:
      return referenceUiImageBucketPx(kThumbnailTierMaxLogicalSide * dpr);
    case ReferenceUiImageTier.large:
      final double logical = math.max(
        screenLogicalSize.longestSide,
        screenLogicalSize.shortestSide * kLargeTierMaxZoom,
      );
      return referenceUiImageBucketPx(logical * dpr);
  }
}

/// The size to decode a source of [intrinsicWidth]×[intrinsicHeight] at so that its
/// SHORTER side is [minSidePx] (aspect ratio preserved — the decoded image then covers any
/// box whose sides are both at most [minSidePx], however it is fitted at paint time), or
/// `null` = decode at the source's own size. Never upscales: a source whose shorter side
/// is already at most [minSidePx] → `null`. Pure.
({int width, int height})? referenceUiDecodeTargetSize({
  required int intrinsicWidth,
  required int intrinsicHeight,
  required int minSidePx,
}) {
  if (intrinsicWidth <= 0 || intrinsicHeight <= 0 || minSidePx <= 0) return null;
  final double scale = minSidePx / math.min(intrinsicWidth, intrinsicHeight);
  if (scale >= 1.0) return null;
  return (
    width: math.max(1, (intrinsicWidth * scale).ceil()),
    height: math.max(1, (intrinsicHeight * scale).ceil()),
  );
}

/// Cache key of [ReferenceUiSizedImage]: the wrapped provider's own key plus the size.
@immutable
class ReferenceUiSizedImageKey {
  const ReferenceUiSizedImageKey(this.providerKey, this.minSidePx);

  final Object providerKey;
  final int minSidePx;

  @override
  bool operator ==(Object other) =>
      other is ReferenceUiSizedImageKey &&
      other.providerKey == providerKey &&
      other.minSidePx == minSidePx;

  @override
  int get hashCode => Object.hash(providerKey, minSidePx);
}

/// Decodes [imageProvider]'s bytes downsampled so the shorter side is [minSidePx] (see
/// [referenceUiDecodeTargetSize]) — never upscaled, aspect ratio preserved. Flutter's own
/// `ResizeImage` offers "exact" and "fit inside" only; a box drawn with `BoxFit.cover`
/// needs "at least the box on both sides", hence this thin provider over the same
/// framework decode hook (`ImageDecoderCallback.getTargetSize`) `ResizeImage` uses. It
/// downloads nothing itself and holds no cache of its own — the wrapped provider fetches
/// the bytes and Flutter's `ImageCache` stores the result under [ReferenceUiSizedImageKey].
@immutable
class ReferenceUiSizedImage extends ImageProvider<ReferenceUiSizedImageKey> {
  const ReferenceUiSizedImage(this.imageProvider, {required this.minSidePx});

  final ImageProvider imageProvider;
  final int minSidePx;

  @override
  Future<ReferenceUiSizedImageKey> obtainKey(ImageConfiguration configuration) {
    // Same shape as `ResizeImage.obtainKey`: stay synchronous when the wrapped provider is
    // (e.g. `NetworkImage`), so a cache hit still paints in the very first frame.
    Completer<ReferenceUiSizedImageKey>? completer;
    SynchronousFuture<ReferenceUiSizedImageKey>? result;
    imageProvider.obtainKey(configuration).then((Object key) {
      final ReferenceUiSizedImageKey sized = ReferenceUiSizedImageKey(key, minSidePx);
      if (completer == null) {
        result = SynchronousFuture<ReferenceUiSizedImageKey>(sized);
      } else {
        completer.complete(sized);
      }
    });
    if (result != null) return result!;
    completer = Completer<ReferenceUiSizedImageKey>();
    return completer.future;
  }

  @override
  ImageStreamCompleter loadImage(ReferenceUiSizedImageKey key, ImageDecoderCallback decode) {
    Future<ui.Codec> decodeSized(
      ui.ImmutableBuffer buffer, {
      ui.TargetImageSizeCallback? getTargetSize,
    }) {
      assert(getTargetSize == null, 'ReferenceUiSizedImage cannot wrap another resizing provider.');
      return decode(buffer, getTargetSize: _targetSize);
    }

    final ImageStreamCompleter completer = imageProvider.loadImage(key.providerKey, decodeSized);
    // Same as `ResizeImage`: a failed load must not stay in the cache under this key.
    completer.addEphemeralErrorListener((Object exception, StackTrace? stackTrace) {
      scheduleMicrotask(() => PaintingBinding.instance.imageCache.evict(key));
    });
    return completer;
  }

  ui.TargetImageSize _targetSize(int intrinsicWidth, int intrinsicHeight) {
    final target = referenceUiDecodeTargetSize(
      intrinsicWidth: intrinsicWidth,
      intrinsicHeight: intrinsicHeight,
      minSidePx: minSidePx,
    );
    return ui.TargetImageSize(width: target?.width, height: target?.height);
  }

  @override
  bool operator ==(Object other) =>
      other is ReferenceUiSizedImage &&
      other.imageProvider == imageProvider &&
      other.minSidePx == minSidePx;

  @override
  int get hashCode => Object.hash(imageProvider, minSidePx);

  @override
  String toString() => 'ReferenceUiSizedImage($imageProvider, minSide: $minSidePx)';
}

/// Test-only. Production code never sets this. Replaces the provider that FETCHES the
/// bytes of a remote image (production: `NetworkImage(url)`) with a zero-network one, so a
/// widget test can exercise the real downsampled decode. Reset to `null` after the test.
@visibleForTesting
ImageProvider Function(String url)? referenceUiRemoteBaseImageProviderForTesting;

/// The provider for remote image [url] decoded at [minSidePx] — the ONLY place in this
/// package that creates a network image provider.
ImageProvider referenceUiRemoteImageProvider(String url, int minSidePx) {
  final ImageProvider base =
      referenceUiRemoteBaseImageProviderForTesting?.call(url) ?? NetworkImage(url);
  return ReferenceUiSizedImage(base, minSidePx: minSidePx);
}

/// The provider for remote image [url] at [tier], for the screen [context] is on. Every
/// caller of one tier under the same `MediaQuery` gets an EQUAL provider.
ImageProvider referenceUiRemoteImageProviderForTier(
  BuildContext context,
  String url,
  ReferenceUiImageTier tier,
) {
  return referenceUiRemoteImageProvider(
    url,
    referenceUiImageTierSidePx(
      tier,
      screenLogicalSize: MediaQuery.maybeSizeOf(context) ?? kReferenceUiFallbackScreenSize,
      devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0,
    ),
  );
}
