import 'package:flutter/widgets.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart' show LBSpec;
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show LBProductDetailState;

import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';
import 'resolved_product_photo.dart';
import 'sheet_scaffold.dart' show liveProductImage;

// ProductImageZoomOverlay — family-3 product-image lightbox (rb-flutter-product-image-zoom-lightbox).
//
// Spec: `reference-ui-rendering/spec.md` (family-3 product + sheets — 商品圖放大檢視燈箱).
// Design: `design/templates/minimal/screens.jsx` `ProductZoomOverlay` (31-95). Parity of iOS
// `ProductZoomOverlayView.swift` + Android `ProductImageZoomOverlay.kt` + RN `ProductZoomOverlay.tsx`.
//
// The full-frame product-image zoom viewer, mounted as the LAST child of the container's `Stack`
// (ABOVE the `BottomSheetPresenter` → covers the open sheet) when a sheet's zoom badge is tapped.
// Reads ONE `LBProductDetailState` (`photos` + `name`) — purely a pixel-layer affordance, no
// view-model / template / core state. Behaviour mirrors the design's `ProductZoomOverlay`:
//
//   • dark backdrop (0.92); tap the backdrop to close.
//   • centered square product image (84% width, aspect 1:1, radius 16, shadow); tap-to-zoom
//     (1 ⇄ 2.4×); drag-to-pan when zoomed (clamped to ±110*(z-1)); a second tap resets.
//   • top-right circular close button (self-drawn ✕).
//   • bottom gradient caption: product name + hint (changes when zoomed).
//
// Photo rendering reuses `liveProductImage` + the same gradient + monogram placeholder:
// `live == false` (golden / demo) draws the deterministic gradient + monogram only; `live == true`
// overlays the real photo. No scrollable container / no `NetworkImage` outside `liveProductImage`.
//
// PHOTO SOURCE (flutter-product-sheet-spec-photo-reference-ui, parity iOS
// `ProductZoomOverlayView`): the zoomed photo is resolved by the SHARED `resolveProductPhoto`
// from `detail` + [ProductImageZoomOverlay.selectedSpec] — NOT by a local
// `detail.photos.first`. The lightbox is opened FROM a sheet, so the container already holds
// the selected variant; re-deriving the ladder here is precisely how "sheet shows the spec
// photo, lightbox shows the product photo" happens.

final Color _zoomPhotoStart = colorFromHex('#FFD7A8') ?? const Color(0xFFFFD7A8);
final Color _zoomPhotoEnd = colorFromHex('#E27D5A') ?? const Color(0xFFE27D5A);

const double _zoomed = 2.4;
const String _hintIdle = '點圖片放大';
const String _hintZoomed = '拖曳檢視細節 · 點一下還原';

/// Up-to-2-char monogram (deterministic, pure). Mirrors `product_detail_sheet._monogram`.
String _monogram(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'LB';
  return trimmed.substring(0, trimmed.length < 2 ? trimmed.length : 2).toUpperCase();
}

/// The family-3 full-frame product-image zoom viewer for one [detail].
class ProductImageZoomOverlay extends StatefulWidget {
  const ProductImageZoomOverlay({
    super.key,
    required this.theme,
    required this.detail,
    this.selectedSpec,
    this.overridePhotoURL,
    this.live = false,
    this.onClose,
  });

  /// The resolved reference-ui theme (FIRST, always).
  final ReferenceUITheme theme;

  /// The product whose image is zoomed (reads `photos` + `name`).
  final LBProductDetailState detail;

  /// The RESOLVED variant spec for the current selection
  /// (`DefaultVariantPicker.selectedSpec`, threaded in by the container as
  /// `ProductSheetsModel.selectedSpec`). Read-only BY-VALUE snapshot — this widget MUST NOT
  /// reach back into `ProductSheetsModel` / `DefaultPlayerTemplate` to fetch it.
  ///
  /// Drives the zoomed photo's SOURCE through the shared [resolveProductPhoto], so the
  /// lightbox shows the SAME photo the sheet that opened it is showing
  /// (flutter-product-sheet-spec-photo-reference-ui, parity iOS `ProductZoomOverlayView`).
  ///
  /// `null` (the DEFAULT) → the product-level photos, so every existing call site / demo /
  /// golden stays byte-identical.
  final LBSpec? selectedSpec;

  /// The photo to show, OVERRIDING [selectedSpec] / [resolveProductPhoto] when non-null and
  /// non-blank (rb-flutter-product-detail-image-gallery). Threaded in by the container when the
  /// lightbox is opened from `ProductDetailSheet`'s multi-image gallery — the container forwards
  /// the gallery's CURRENTLY SELECTED photo URL here, so the lightbox shows the same page the
  /// gallery was on instead of unconditionally re-deriving `primaryPhoto`.
  ///
  /// Semantics deliberately mirror the design's `imgKind || product.img` (`||` falls through on
  /// an empty string too): a value that is `null` OR blank after trim is treated as "no
  /// override" and this widget falls back to the existing [resolveProductPhoto] resolution —
  /// NOT a plain `!= null` check. `null` (the DEFAULT) → every existing call site (the
  /// `NotifyRestockSheet` badge, `.addToCart`'s compact-card badge, every test / golden) is
  /// byte-identical to before this field existed.
  final String? overridePhotoURL;

  /// `false` (golden / demo) → gradient + monogram placeholder; `true` → real photo.
  final bool live;

  /// Backdrop / close-button tap → container clears `_zoomedDetail`.
  final VoidCallback? onClose;

  @override
  State<ProductImageZoomOverlay> createState() => _ProductImageZoomOverlayState();
}

class _ProductImageZoomOverlayState extends State<ProductImageZoomOverlay> {
  double _z = 1.0;
  Offset _pan = Offset.zero;

  void _toggleZoom() {
    setState(() {
      if (_z > 1.0) {
        _z = 1.0;
        _pan = Offset.zero;
      } else {
        _z = _zoomed;
      }
    });
  }

  void _onPan(DragUpdateDetails d) {
    if (_z <= 1.0) return;
    final lim = 110.0 * (_z - 1.0);
    setState(() {
      _pan = Offset(
        (_pan.dx + d.delta.dx).clamp(-lim, lim),
        (_pan.dy + d.delta.dy).clamp(-lim, lim),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final detail = widget.detail;
    // The photo this overlay draws (rb-flutter-product-detail-image-gallery): a non-null,
    // trim-non-blank `overridePhotoURL` WINS (the gallery's currently-selected page, threaded
    // in by the container) — mirrors the design's `imgKind || product.img` (`||` falls through
    // on an empty string too, so a blank override is treated the same as no override). Every
    // pre-existing call site leaves `overridePhotoURL` at its default `null`, so this is a
    // strict superset of the prior behavior: it falls through to the SAME photo-source
    // resolution shared verbatim with the sheet (flutter-product-sheet-spec-photo-reference-ui)
    // — `primaryPhoto` is the first NON-BLANK entry of the winning source; `null` → the
    // gradient + monogram placeholder below.
    final override = widget.overridePhotoURL;
    final photoUrl = (override != null && override.trim().isNotEmpty)
        ? override
        : resolveProductPhoto(detail: detail, selectedSpec: widget.selectedSpec).primaryPhoto;
    // E2E key (INERT — KeyedSubtree paints nothing) on the overlay backdrop/root.
    return KeyedSubtree(
      key: LbTestKeys.zoomOverlay,
      child: Stack(
      fit: StackFit.expand,
      children: [
        // Full-bleed dark backdrop — tap to close.
        GestureDetector(
          onTap: widget.onClose,
          child: const ColoredBox(color: Color(0xEB000000)), // black @ 0.92
        ),

        // Centered square image card — tap to zoom, drag to pan (when zoomed).
        Center(
          child: FractionallySizedBox(
            widthFactor: 0.84,
            child: AspectRatio(
              aspectRatio: 1,
              child: GestureDetector(
                key: LbTestKeys.imageZoomImage,
                onTap: _toggleZoom,
                onPanUpdate: _onPan,
                child: Transform.translate(
                  offset: _pan,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x80000000), // black @ 0.5
                          blurRadius: 60,
                          offset: Offset(0, 24),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Transform.scale(
                        scale: _z,
                        child: liveProductImage(
                          live: widget.live,
                          url: photoUrl,
                          placeholder: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [_zoomPhotoStart, _zoomPhotoEnd],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                _monogram(detail.name),
                                style: TextStyle(
                                  color: const Color(0xFFFFFFFF).withValues(alpha: 0.92),
                                  fontSize: 64 * theme.fontScale,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),

        // Top-right circular close button (self-drawn ✕).
        Positioned(
          top: 14,
          right: 14,
          child: GestureDetector(
            key: LbTestKeys.zoomClose,
            onTap: widget.onClose,
            child: Container(
              width: 36,
              height: 36,
              decoration: const BoxDecoration(
                color: Color(0x24FFFFFF), // white @ 0.14
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '✕',
                style: TextStyle(
                  color: const Color(0xFFFFFFFF),
                  fontSize: 16 * theme.fontScale,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),

        // Bottom gradient caption: product name + hint (changes when zoomed).
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0x00000000), Color(0x99000000)], // transparent → black @ 0.6
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detail.name,
                    style: TextStyle(
                      color: const Color(0xFFFFFFFF),
                      fontSize: 15 * theme.fontScale,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _z > 1.0 ? _hintZoomed : _hintIdle,
                    style: TextStyle(
                      color: const Color(0xFFFFFFFF).withValues(alpha: 0.6),
                      fontSize: 12 * theme.fontScale,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
      ),
    );
  }
}
