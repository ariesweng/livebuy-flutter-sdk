import 'package:flutter/material.dart';
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart' show LBMiniCartPeek;

import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';
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
// Android #9): aligned to the design's `LBPMiniCart`, the peek LEADS with a 60-wide
// product thumbnail (rb-flutter-vod-live-product-card-restyle, 2026-09-03: 52→60,
// square→left-corners-only, fixed→stretch height). `photos` are remote URLs and
// reference-ui keeps goldens deterministic (NO network image), so — like
// `ProductDetailSheet`'s media — it draws a rounded gradient placeholder with a
// monogram (host can swap in a real image). The rest mirrors `LBPMiniCart`: the WHITE
// card surface (rb-flutter-vod-live-product-card-restyle: was dark glass), the single-
// line name, the price line (`已售完` when `soldOut == 1`, else `priceShow`), and the
// top-right absolute close button (was trailing circular). NO「已加入購物車」confirmation
// line (the design's `LBPMiniCart` has none — the peek's mere appearance is the
// "added" signal).
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

/// Card padding (`padding: '0 8px 0 0'` — content padding is right-only now that the
/// thumbnail is flush against the card's left/top/bottom edges, rb-flutter-vod-live-
/// product-card-restyle). Corner radius (`borderRadius: '0.25rem'` ≈ 4 logical px —
/// this file keeps the existing px-literal convention rather than introducing a rem
/// unit).
const double _cardRadius = 4;

/// Gap between the chip / info / close (`gap: 10`).
const double _hGap = 10;

/// Product thumbnail box — a fixed SQUARE, width AND height (design `width: '3.5rem',
/// height: '3.5rem'` = 56px, R34, `design/contract/claude-design-sync.md`). Was `60` (no
/// explicit height, implicitly stretched to the info column's height via the enclosing
/// `Row`'s `CrossAxisAlignment.stretch` — see `build()`'s doc comment for the R34 change to
/// that).
const double _chipWidth = 56;

/// Trailing close-circle diameter (`width/height: 22`).
const double _closeSize = 22;

/// Close button inset from the card's top-right corner (`top:3, right:3`).
const double _closeInset = 3;

// MARK: - Decorative design tokens (literal hex from sdk-components.jsx LBPMiniCart)
//
// rb-flutter-vod-live-product-card-restyle (2026-09-03): the card surface flipped
// from a dark glass pill to a white card — `_glassFill` / `_glassStroke` / `_closeFill`
// are RETIRED (no longer referenced); text/price colors now resolve from [theme]
// (`theme.text`) or the merchant `accent` rather than fixed on-glass literals.

/// The white card fill (`background:#fff`).
const Color _cardFill = Color(0xFFFFFFFF);

/// The card's drop shadow (`boxShadow: 0 6px 18px rgba(0,0,0,0.15)`).
const List<BoxShadow> _cardShadow = [
  BoxShadow(
    color: Color(0x26000000),
    blurRadius: 18,
    offset: Offset(0, 6),
  ),
];

/// Sold-out copy color `#9A96A3` (the design's muted sold-out tint — unchanged by
/// this restyle; `theme.surface.textDim` has no Flutter `ReferenceUITheme` field, so
/// this literal is kept as-is, mirroring `product_row.dart`'s own `_soldOutColor`).
final Color _soldOutColor = colorFromHex('#9A96A3') ?? const Color(0xFF9A96A3);

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
/// PHOTO-LED white card — a product thumbnail + the product name + a price / sold-out
/// line — with a tap-to-open-detail body and a top-right absolute close button
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

  /// VOD 介紹輪播兩參數（rb-flutter-now-introducing，問題 9/10；皆預設保 peek 不變）：
  ///  • live    — `live && peek.pic` 非空時於漸層 placeholder 上疊真實商品圖（liveProductImage）。
  ///  • fullWidth — body 由固定 260 改為填滿（輪播卡用滿寬）。
  ///
  /// （rb-flutter-minicart-remove-introducing-tag，2026-09-04）先前的第三個參數 `tag`
  /// （info 欄名稱上方的「介紹中」accent 小標）已整段移除——`design/templates/minimal/
  /// sdk-components.jsx` 的 `LBPMiniCart` 沒有任何 tag / 介紹中 / 描述文案節點，只有縮圖 +
  /// 名稱 + 價格行 + 關閉鈕。
  final bool live;
  final bool fullWidth;

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
          decoration: const BoxDecoration(
            color: _cardFill,
            borderRadius: BorderRadius.all(Radius.circular(_cardRadius)),
            boxShadow: _cardShadow,
          ),
          // Close button is `position: absolute` in the design (positioned against the
          // card's own border box, NOT the content row's padded box) — a `Stack` sibling
          // to the content row, not a trailing Row child.
          child: Stack(
            children: [
              // Content row — thumbnail flush at the card's left/top/bottom edges, right-
              // padded 8 (design `padding: '0 8px 0 0'`). R34 (`design/contract/
              // claude-design-sync.md`): the thumbnail is now a fixed 56×56 SQUARE (see
              // `_chipWidth`'s doc comment) instead of stretching to match the info column's
              // height, so the `IntrinsicHeight` + `CrossAxisAlignment.stretch` this row used
              // to need are GONE — `CrossAxisAlignment.center` (Row's default) is enough: the
              // row's own cross-axis extent is simply the taller of the two children's natural
              // heights, and each child is vertically centered within it.
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _productThumb(p),
                    const SizedBox(width: _hGap),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: _infoColumn(p),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: _closeInset,
                right: _closeInset,
                child: _closeButton(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // MARK: - Product thumbnail (LBPMiniCart 60-wide photo — deterministic placeholder)
  //
  // Photo-led peek: a rounded gradient placeholder with a monogram (NO network image),
  // mirroring `ProductDetailSheet`'s photo placeholder. Host can swap in a real image.
  // Only the LEFT two corners are rounded (design `borderRadius: '0.25rem 0 0
  // 0.25rem'`) — the thumbnail sits flush against the card's left/top/bottom edges, so
  // its outer corners match the card's own radius while the inner (right) edge stays
  // square.

  Widget _productThumb(LBMiniCartPeek p) {
    final placeholder = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_photoStart, _photoEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
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
    // Height is EXPLICIT (R34) — a fixed 56×56 square (`_chipWidth` both ways), no longer
    // implicitly stretched to match the info column's height via the enclosing Row.
    return Container(
      width: _chipWidth,
      height: _chipWidth,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(_cardRadius),
          bottomLeft: Radius.circular(_cardRadius),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: liveProductImage(
        live: live,
        url: p.pic,
        placeholder: placeholder,
      ),
    );
  }

  // MARK: - Info column (name + price line)

  Widget _infoColumn(LBMiniCartPeek p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // （rb-flutter-minicart-remove-introducing-tag，2026-09-04）先前這裡有一個「介紹中」
        // accent 標籤 Row（carousel 呼叫端傳入 `tag: '介紹中'` 時畫出，`EqualizerGlyph` + 文字）
        // ——已整段移除：`LBPMiniCart` 沒有任何 tag / 介紹中 / 描述文案節點，只有名稱 + 價格行。
        // Product name — single-line, ellipsis-truncated (design 13/600). `theme.text`
        // (was fixed white on the retired dark-glass fill). `paddingRight: 26` (design
        // literal) reserves clearance under the absolutely-positioned close button —
        // combined with the card's own `right: 8` content padding, this totals the
        // design's 34px clearance (button spans `right: 3..25`).
        Padding(
          padding: const EdgeInsets.only(right: 26),
          child: Text(
            p.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: theme.text,
              fontSize: 13 * theme.fontScale,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ),
        const SizedBox(height: 2),

        // Price line — sold-out → 已售完 (unchanged `_soldOutColor` literal; Flutter's
        // `ReferenceUITheme` has no `surface.textDim` field to source it from); else the
        // priceShow, now colored with the merchant `accent` (was the fixed on-glass pink
        // `#FF7B8A`).
        Text(
          _isSoldOut ? miniCartSoldOutLabel : p.priceShow,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _isSoldOut ? _soldOutColor : theme.accent,
            fontSize: 12 * theme.fontScale,
            fontWeight: _isSoldOut ? FontWeight.w600 : FontWeight.w700,
          ),
        ),
      ],
    );
  }

  // MARK: - Close button (LBPMiniCart top-right absolute close, design `top:3,right:3`)
  //
  // Tapping it dismisses WITHOUT opening the detail: its own GestureDetector
  // intercepts the tap so the outer open-detail action does not also fire (design
  // `e.stopPropagation()` on `onClose`). A no-op when `onDismiss` is null. Transparent
  // background (was a translucent white circle on the retired dark-glass fill); icon
  // color now `theme.text` (was fixed white).

  Widget _closeButton() {
    return GestureDetector(
      key: LbTestKeys.minicartPeekClose,
      behavior: HitTestBehavior.opaque,
      onTap: () => onDismiss?.call(),
      child: SizedBox(
        width: _closeSize,
        height: _closeSize,
        child: Center(
          child: Icon(
            Icons.close,
            color: theme.text,
            size: 14 * theme.fontScale,
          ),
        ),
      ),
    );
  }
}
