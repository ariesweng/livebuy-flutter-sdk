import 'package:flutter/material.dart';
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart' show LBMiniCartPeek;

import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';
import 'equalizer_glyph.dart';
import 'sheet_scaffold.dart' show liveProductImage;

// MiniCartPeek — family-3 product sheet-stack surface 3 (mini-cart peek).
//
// Spec: `reference-ui-rendering/spec.md` (family-3 product + sheets, surface 3).
// Flutter sibling of iOS `MiniCartView.swift` (rb-ios-product-sheets, D-4) and
// Android `MiniCartPeek.kt` (rb-android-product-sheets, golden
// `mini-cart-peek-in-stock`).
//   Design source: `design/templates/minimal/sdk-components.jsx` `LBPMiniCart`
//     (lines 675-713) + `design/templates/minimal/screens.jsx` `LBPMiniCart`
//     call-site.
//
// The floating mini-cart peek for the most-recent successful add. It is the third
// of the four family-3 surface sub-views composed by `ProductSheetsOverlayView`,
// and it implements the agreed SUB-VIEW INPUT PATTERN documented in that
// container (mirrors family-1 `OperationRailView` / family-2 surfaces EXACTLY):
//
//   1. `theme:` (ReferenceUITheme, required)  — FIRST named argument, always.
//   2. the bound SNAPSHOT VALUE              — `peek: LBMiniCartPeek` — passed BY
//      VALUE from `ProductSheetsModel.miniCartPeek` (never the model, never the
//      template). The container renders this sub-view ONLY when its `miniCartPeek`
//      snapshot is non-null (an absent peek → no floating card), so the sub-view
//      itself binds a NON-OPTIONAL peek and additionally self-guards (renders
//      nothing) on the rare null pass so it is always safe to compose.
//   3. action callbacks (LAST, each defaulting to a no-op):
//        • `onDismiss`    → `DefaultMiniCart.dismissMiniCart()` (the close button).
//        • `onOpenDetail` → the host-wired「開明細」re-open (the Flutter template
//          exposes no public `openDetail()` exit — see `ProductSheetsModel
//          .openDetailFromMiniCart`; the host re-feeds the full `LBProduct`).
//
// One-way data flow (D-1 / D-4): this surface reads ONLY its passed-in `peek`; it
// never reaches back into `ProductSheetsModel` / `DefaultPlayerTemplate`, and it
// NEVER calls core `addToCart` (the detail sheet forwards that). It NEVER records /
// clears the peek itself — that is the template's `DefaultMiniCart`; this layer
// only forwards the close / open intents. It renders correctly with all callbacks
// null / omitted (so demo / golden / preview construct it action-free).
//
// PHOTO-LED (rb-align-flutter-product-sheets — four-platform parity with iOS #8 /
// Android #9): aligned to the design's `LBPMiniCart`, the peek LEADS with a 52×52
// product thumbnail. `photos` are remote URLs and reference-ui keeps goldens
// deterministic (NO network image), so — like `ProductDetailSheet`'s media — it draws
// a 52×52 rounded gradient placeholder with a monogram (host can swap in a real
// image). The rest mirrors `LBPMiniCart`: the dark glass card surface, the single-
// line name, the price line (`已售完` when `soldOut == 1`, else `priceShow`), and the
// trailing circular close button. NO「已加入購物車」confirmation line (the design's
// `LBPMiniCart` has none — the peek's mere appearance is the "added" signal).
//
// SNAPSHOT-DETERMINISM (iOS / Android lessons baked in): plain Row / Column /
// Container only — NO scrollable container (`ListView` / `GridView` /
// `SingleChildScrollView`), NO network image, NO Material `Switch`, NO animation /
// randomness. Tapping the card body opens the detail; tapping the close button
// dismisses WITHOUT opening (the design's `onClose` calls `e.stopPropagation()`).

// MARK: - Layout tokens (lifted from sdk-components.jsx · LBPMiniCart)

/// Bounded card width — keeps the single-line name truncating rather than
/// stretching (parity with iOS 260pt / Android 260dp).
const double _cardWidth = 260;

/// Card padding (`padding: 8`) + corner radius (`borderRadius: 16`).
const double _cardPadding = 8;
const double _cardRadius = 16;

/// Gap between the chip / info / close (`gap: 10`).
const double _hGap = 10;

/// Product thumbnail box (design's 52×52 photo — deterministic placeholder).
const double _chipSize = 52;
const double _chipRadius = 10;

/// Trailing close-circle diameter (`width/height: 22`).
const double _closeSize = 22;

// MARK: - Decorative design tokens (literal hex from sdk-components.jsx LBPMiniCart)
//
// FIXED decorative colors lifted verbatim from the design's dark-glass overlay —
// these are NOT the theme accent / text / background (parity with iOS
// `MiniCartView` statics + Android `MiniCartPeek` private vals). Parsed via
// `colorFromHex` (falls back only if a literal is ever malformed — constants).

/// `rgba(20,20,24,0.78)` — the dark glass card fill (`LBPMiniCart`).
final Color _glassFill =
    (colorFromHex('#141418') ?? const Color(0xFF000000)).withValues(alpha: 0.78);

/// `rgba(255,255,255,0.10)` — the 0.5px hairline border on the glass.
const Color _glassStroke = Color(0x1AFFFFFF);

/// On-glass primary text — white (`#fff` in the design).
const Color _onGlassText = Color(0xFFFFFFFF);

/// In-stock price accent `#FF7B8A` (the design's price-pink on the glass).
final Color _priceColor = colorFromHex('#FF7B8A') ?? const Color(0xFFFF7B8A);

/// Sold-out copy color `#9A96A3` (the design's muted sold-out tint).
final Color _soldOutColor = colorFromHex('#9A96A3') ?? const Color(0xFF9A96A3);

/// The trailing close-circle fill `rgba(255,255,255,0.18)`.
const Color _closeFill = Color(0x2EFFFFFF);

/// Product-photo placeholder gradient stops (mirrors `ProductDetailSheet` — the
/// design's warm media chip; deterministic, NO network image).
final Color _photoStart = colorFromHex('#FFD7A8') ?? const Color(0xFFFFD7A8);
final Color _photoEnd = colorFromHex('#E27D5A') ?? const Color(0xFFE27D5A);

// MARK: - Static copy (LBPMiniCart labels)

/// Sold-out price-line label (design `已售完`).
const String miniCartSoldOutLabel = '已售完';

/// Up-to-2-char monogram from the product name (deterministic, pure) — for the photo
/// placeholder. Mirrors `ProductDetailSheet._monogram`.
String _monogram(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'LB';
  return trimmed.substring(0, trimmed.length < 2 ? trimmed.length : 2).toUpperCase();
}

/// The family-3 floating mini-cart peek for one [LBMiniCartPeek]. Paints a compact
/// PHOTO-LED dark-glass card — a 52×52 product thumbnail + the product name + a price
/// / sold-out line — with a tap-to-open-detail body and a trailing close button
/// (aligned to the design's `LBPMiniCart`). The container draws it only when a peek
/// exists.
///
/// Renders correctly with the default no-op [onDismiss] / [onOpenDetail] (golden /
/// preview safe).
class MiniCartPeek extends StatelessWidget {
  /// The resolved reference-ui theme (FIRST named argument, always).
  final ReferenceUITheme theme;

  /// The mini-cart peek SNAPSHOT VALUE (`DefaultMiniCart.peek`) — the most-recent
  /// successful add. Read BY VALUE. The container passes it only when non-null; a
  /// `null` here self-guards to `SizedBox.shrink()` (no floating card).
  final LBMiniCartPeek? peek;

  /// Host-wired close (the ✕). Forwarded to the template's `dismissMiniCart()`.
  /// Default no-op so demo / golden / preview instances construct action-free.
  final void Function()? onDismiss;

  /// Host-wired body tap. Forwarded to the host's「開明細」re-open (the Flutter
  /// template exposes no public `openDetail()` — the host re-feeds the full
  /// `LBProduct`). Default no-op so demo / golden / preview construct action-free.
  final void Function()? onOpenDetail;

  /// VOD 介紹輪播三參數（rb-flutter-now-introducing，問題 9/10；皆預設保 peek 不變）：
  ///  • live    — `live && peek.pic` 非空時於漸層 placeholder 上疊真實商品圖（liveProductImage）。
  ///  • fullWidth — body 由固定 260 改為填滿（輪播卡用滿寬）。
  ///  • tag     — 非 null 時 info 欄名稱上方畫小 accent 標籤（「介紹中」）。
  final bool live;
  final bool fullWidth;
  final String? tag;

  /// E2E key on the card root (INERT — wrapped in a `KeyedSubtree`, paints nothing).
  /// Defaults to [LbTestKeys.minicartPeek]; the now-introducing carousel call site
  /// (which reuses this widget) passes [LbTestKeys.nowIntroducingCard] instead.
  final Key rootKey;

  const MiniCartPeek({
    super.key,
    required this.theme,
    required this.peek,
    this.onDismiss,
    this.onOpenDetail,
    this.live = false,
    this.fullWidth = false,
    this.tag,
    this.rootKey = LbTestKeys.minicartPeek,
  });

  /// Whether the peeked product is sold out (`soldOut == 1`). Drives the price
  /// line: sold-out shows `已售完`, in-stock shows `priceShow`.
  bool get _isSoldOut => peek?.soldOut == 1;

  @override
  Widget build(BuildContext context) {
    final p = peek;
    // Self-guard (D-4): an absent peek → no floating card (the container also
    // gates, mirroring iOS / Android, so this is safe to compose unconditionally).
    if (p == null) return const SizedBox.shrink();

    // The whole card body is the open-detail affordance (design `onTap`); the
    // trailing close button is a separate gesture that dismisses WITHOUT opening
    // (design `onClose` calls `e.stopPropagation()`). A bounded width keeps the
    // single-line name truncating rather than stretching (parity to iOS 260 /
    // Android 260dp).
    // E2E key (INERT — KeyedSubtree paints nothing) on the card root.
    return KeyedSubtree(
      key: rootKey,
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onOpenDetail?.call(),
      child: Container(
        // 輪播卡滿寬（fullWidth）；浮動 mini-cart peek 維持固定 260。
        width: fullWidth ? double.infinity : _cardWidth,
        padding: const EdgeInsets.all(_cardPadding),
        decoration: BoxDecoration(
          color: _glassFill,
          borderRadius: BorderRadius.circular(_cardRadius),
          border: Border.all(color: _glassStroke, width: 0.5),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _productThumb(p),
            const SizedBox(width: _hGap),
            Expanded(child: _infoColumn(p)),
            const SizedBox(width: _hGap),
            _closeButton(),
          ],
        ),
      ),
      ),
    );
  }

  // MARK: - Product thumbnail (LBPMiniCart 52×52 photo — deterministic placeholder)
  //
  // Photo-led peek: a 52×52 rounded gradient placeholder with a monogram (NO network
  // image), mirroring `ProductDetailSheet`'s photo placeholder. Host can swap in a
  // real image.

  Widget _productThumb(LBMiniCartPeek p) {
    final placeholder = Container(
      width: _chipSize,
      height: _chipSize,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_photoStart, _photoEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(_chipRadius),
      ),
      alignment: Alignment.center,
      child: Text(
        _monogram(p.name),
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.92),
          fontSize: 16 * theme.fontScale,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
    // Real product image OVER the gradient placeholder at host runtime (`live` + non-blank pic);
    // `live == false` / blank → placeholder only (golden byte-stable). rb-flutter-now-introducing 真實圖.
    return SizedBox(
      width: _chipSize,
      height: _chipSize,
      child: liveProductImage(
        live: live,
        url: p.pic,
        placeholder: placeholder,
        borderRadius: BorderRadius.circular(_chipRadius),
      ),
    );
  }

  // MARK: - Info column (name + price line)

  Widget _infoColumn(LBMiniCartPeek p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Optional accent tag above the name (carousel「介紹中」). null → not drawn (peek unchanged).
        // The tag leads with an accent equalizer glyph (size 11, gap 3) — parity iOS/Android/RN,
        // 共用 `EqualizerGlyph`（與商品列底部橫幅同一 vocabulary）.
        if (tag != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              EqualizerGlyph(size: 11, color: theme.accent),
              const SizedBox(width: 3),
              Text(
                tag!,
                style: TextStyle(
                  color: theme.accent,
                  fontSize: 11 * theme.fontScale,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        // Product name — single-line, ellipsis-truncated (design 13/600).
        Text(
          p.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _onGlassText,
            fontSize: 13 * theme.fontScale,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 2),

        // Price line — sold-out → 已售完; else the priceShow (design dim).
        Text(
          _isSoldOut ? miniCartSoldOutLabel : p.priceShow,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _isSoldOut ? _soldOutColor : _priceColor,
            fontSize: 12 * theme.fontScale,
            fontWeight: _isSoldOut ? FontWeight.w600 : FontWeight.w700,
          ),
        ),
      ],
    );
  }

  // MARK: - Close button (LBPMiniCart trailing close — 22×22 glass circle)
  //
  // Tapping it dismisses WITHOUT opening the detail: its own GestureDetector
  // intercepts the tap so the outer open-detail action does not also fire (design
  // `e.stopPropagation()` on `onClose`). A no-op when `onDismiss` is null.

  Widget _closeButton() {
    return GestureDetector(
      key: LbTestKeys.minicartPeekClose,
      behavior: HitTestBehavior.opaque,
      onTap: () => onDismiss?.call(),
      child: Container(
        width: _closeSize,
        height: _closeSize,
        decoration: BoxDecoration(
          color: _closeFill,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          Icons.close,
          color: _onGlassText,
          size: 12 * theme.fontScale,
        ),
      ),
    );
  }
}
