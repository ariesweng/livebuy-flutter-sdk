import 'package:flutter/material.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart' show LBProduct;
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show LBProductRecommendation;

import '../playershell/detail_glyph.dart';
import '../reference_ui_theme.dart';
import '../share_glyph.dart';
import '../testing/lb_test_keys.dart';
import 'equalizer_glyph.dart';
import 'hot_glyph.dart';
import 'product_row_overlay.dart' show ProductRowMode;
import 'product_status_badge.dart';
import 'sheet_scaffold.dart';

// ProductRow — reusable product-card component (row / grid two states, Flutter).
//
// Spec: `reference-ui-rendering/spec.md` §"LivebuyReferenceUI 商品卡元件（row / grid
//        兩態）供商品列表與商品明細更多商品推薦格共用" (rb-flutter-product-detail-recommendations).
// Design: `design/templates/minimal/sdk-components.jsx` `LBPProductRow` (design R21).
// Parity: iOS `ProductRowView.swift` (rb-ios-product-detail-recommendations §1) /
//   Android `ProductRow.kt` / RN `ProductRow.tsx`.
//
// Extracted from `ProductListSheet`'s former private `_ProductRow` (§1 of this
// change). `ProductListSheet` now constructs THIS widget for its EXISTING `.row`
// call site — behavior / pixels UNCHANGED (see the `.row` DELIBERATE DEVIATION note
// below). The new `.grid` layout is used ONLY by the「更多商品」推薦格
// (`ProductDetailSheet`'s recommendations section).

/// Which card geometry [ProductRow] renders (design R21).
enum ProductRowLayout {
  /// The existing horizontal list row (縮圖 · name/price · action-icon group) —
  /// `ProductListSheet`'s product list drawer. Default.
  row,

  /// The new vertical card (縮圖 on top, info below) — used ONLY by the「更多商品」
  /// 推薦格 (2×2, always `hideSub: true`).
  grid,
}

/// A single product card, in either the existing `.row` layout or the new `.grid`
/// layout (rb-flutter-product-detail-recommendations §1). All action callbacks stay
/// the pre-existing `void Function(LBProduct product)?` shape (the row calls back
/// with the [product] it renders) — the SAME idiom `ProductListSheet` already used,
/// so `.row` call sites are unaffected.
class ProductRow extends StatelessWidget {
  /// 0-based position — feeds the index-addressable per-row E2E keys.
  final int rowIndex;
  final ReferenceUITheme theme;
  final LBProduct product;
  final bool live;

  /// 縮圖疊層的播放 affordance（`.row` only — see `product_row_overlay.dart`).
  final bool showPlay;

  /// This row is the currently-introducing product (`.row` only).
  final bool isIntroducing;

  /// 縮圖疊層的播放模式（product-row-status-overlay，`.row` only）。`mode ==
  /// ProductRowMode.vod` 時，[showPlay] / [isIntroducing] 繪成 VOD 專屬的新視覺——置中黑色圓形
  /// 播放鈕（[_VodPlayOverlay]）/ 滿版半透明黑底遮罩＋等化器圖示（[_VodIntroducingMask]），
  /// design R36（rb-flutter-product-row-vod-intro-mask）——取代 `mode` 為 `null` 或 `live` /
  /// `replay` 時沿用的既有底部「看講解」文字膠囊 / 「介紹中」珊瑚色橫幅視覺。`null`（預設，既有
  /// 呼叫點 / `.grid`）→ 走既有視覺，byte-identical。Orthogonal to [showPlay] / [isIntroducing]
  /// themselves (those still decide WHETHER an overlay shows; [mode] only decides WHICH visual).
  final ProductRowMode? mode;

  /// 縮圖左上角編號徽章的內容（design R35，rb-flutter-product-row-number-badge，`.row` only —
  /// mirrors the `showPlay` / `isIntroducing` `.row`-only convention). `null` → no badge drawn
  /// at all (VOD, or a call site that never wires this — e.g. `.grid`'s「更多商品」推薦格, which
  /// has no live/replay/introducing semantics and never passes this). Non-null → the product's
  /// 1-based position in the BACKEND-ORDER snapshot (`ProductSheetsModel.productsBackendOrder`);
  /// [isIntroducing] then decides whether this number or a「🔥 HOT」swap renders (see
  /// `_NumberBadge`). Orthogonal to [showPlay] / [showShare].
  final int? index;

  /// 列分享 icon 可見性（`.row` only — orthogonal to [showPlay] / [isIntroducing]).
  final bool showShare;

  /// `.row`（預設）或 `.grid`（design R21）.
  final ProductRowLayout layout;

  /// `.row`: hides the ENTIRE secondary text line under the product name (struck-
  /// through original price / 已售完 sub-line, whichever applies). Default `false`
  /// (existing `.row` behavior unchanged).
  ///
  /// `.grid`: currently a NO-OP — design R21 (`sdk-components.jsx:1108-1123`) only
  /// gates a separate `p.sub` caption line with `hideSub`, which this widget does not
  /// implement yet. The `.grid` price cell's struck-through original price (see
  /// `_gridPriceText`) is UNCONDITIONAL on this flag — it is NOT the same "hides
  /// original price" semantics as `.row` (`add-recommendation-original-price-
  /// reference-ui-flutter` design.md D2). The「更多商品」推薦格 call site's existing
  /// `hideSub: true` predates `LBProductRecommendation` carrying original-price data
  /// and is kept for historical reasons — it does NOT suppress the `.grid` price
  /// cell's strike-through.
  final bool hideSub;

  final void Function(LBProduct product)? onOpenProduct;
  final void Function(LBProduct product)? onQuickAdd;
  final void Function(LBProduct product)? onNotifyRestock;
  final void Function(LBProduct product)? onSeekToIntro;
  final void Function(LBProduct product)? onShareProduct;

  /// Independent tap handler for the play / 看講解 affordance
  /// (rb-flutter-product-detail-recommendations §1.3). `null`（預設）→ `.row` falls
  /// back to the existing 縮圖 seek forwarding ([onSeekToIntro]) — byte-identical to
  /// the pre-extraction behavior. `.grid`'s dedicated play button has NO fallback
  /// (the call site hides the button entirely instead when there is nothing to play —
  /// see `ProductDetailSheet`'s recommendation card, gated on `videoId != null`).
  final VoidCallback? onPlayClick;

  const ProductRow({
    super.key,
    required this.rowIndex,
    required this.theme,
    required this.product,
    required this.live,
    this.showPlay = false,
    this.isIntroducing = false,
    this.mode,
    this.index,
    this.showShare = false,
    this.layout = ProductRowLayout.row,
    this.hideSub = false,
    this.onOpenProduct,
    this.onQuickAdd,
    this.onNotifyRestock,
    this.onSeekToIntro,
    this.onShareProduct,
    this.onPlayClick,
  });

  /// 明細鈕 / 商品名 / 卡片本體 → full browse sheet.
  void _open() => onOpenProduct?.call(product);

  /// 加購鈕 (in-stock cart glyph) → compact AddToCart sheet. `onQuickAdd` falls back
  /// to `onOpenProduct` so a quick-add reads as a plain open when unwired.
  void _quickAdd() => (onQuickAdd ?? onOpenProduct)?.call(product);

  /// 售完列補貨鈴鐺 → restock sheet. Falls back to `onOpenProduct` when unwired.
  void _notifyRestock() => (onNotifyRestock ?? onOpenProduct)?.call(product);

  /// 縮圖 / 播放 tap. `onPlayClick` set → independent handler (design R21 issue 1.3);
  /// unset → the existing seek-to-intro forwarding (byte-identical pre-extraction
  /// behavior for every existing `.row` call site).
  void _playTap() {
    final onPlay = onPlayClick;
    if (onPlay != null) {
      onPlay();
    } else {
      onSeekToIntro?.call(product);
    }
  }

  /// 列分享鈕 → 系統分享，連結帶該商品介紹時間 ?t=beginTime（`.row` only）.
  void _share() => onShareProduct?.call(product);

  @override
  Widget build(BuildContext context) {
    switch (layout) {
      case ProductRowLayout.row:
        return _buildRow(context);
      case ProductRowLayout.grid:
        return _buildGrid(context);
    }
  }

  // ── `.row` layout (`LBPProductRow` layout:'row') ──────────────────────────────
  //
  // Mirrors `LBPProductRow` `layout:'row'` verbatim — moved from `ProductListSheet`'s
  // former private `_ProductRow` with NO pixel change (§1.1 byte-identical baseline
  // requirement), EXCEPT for the play affordance below.
  //
  // Play affordance NOW MATCHES design R21 (`rb-flutter-product-row-play-hint-pill`):
  // a bottom-centered, translucent-white rounded pill「看講解」(play icon + label),
  // replacing the former centered black-dot play icon. The prior DELIBERATE
  // DEVIATION carve-out (which kept the black-dot icon to protect
  // `test/goldens/product-list-drawer-populated.png` and its 4 siblings) is now
  // resolved — the user explicitly authorized regenerating those baselines for this
  // change. No CSS `backdrop-filter: blur` equivalent is attempted (Flutter has no
  // native lightweight blur widget here); a translucent solid background approximates
  // the design's `rgba(255,255,255,0.75)` well enough. `.grid` (below, brand new — no
  // baseline to protect) already draws R21's dedicated grid visual (§1.4).

  Widget _buildRow(BuildContext context) {
    final soldOut =
        ProductStatusBadge.resolve(product) == ProductStatusBadge.soldOut;
    final explicitBadge = ProductStatusBadge.fromLabel(product.label);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                key: LbTestKeys.productRowThumb(rowIndex),
                behavior: HitTestBehavior.opaque,
                onTap: _playTap,
                child: Builder(builder: (context) {
                  final Widget thumb = SizedBox(
                    width: 64,
                    height: 64,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Positioned.fill(
                          child: liveProductImage(
                            live: live,
                            url: product.photos.isEmpty
                                ? null
                                : product.photos.first,
                            // 4 (was 12, R34 `design/contract/claude-design-sync.md`) — see
                            // this thumb's outer bordered `Container` below for the matching
                            // clip radius + the new 1px `#D2D2D2` border.
                            borderRadius: BorderRadius.circular(4),
                            placeholder: DecoratedBox(
                              decoration: BoxDecoration(
                                color: _bgSunken,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                        // VOD (mode == ProductRowMode.vod, design R36,
                        // rb-flutter-product-row-vod-intro-mask): showPlay draws the NEW
                        // centered black circle instead of the existing bottom 看講解 pill.
                        // mode != vod (live / replay / omitted) keeps the existing pill
                        // byte-identical.
                        if (showPlay)
                          mode == ProductRowMode.vod
                              ? _VodPlayOverlay(theme: theme)
                              : Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 4,
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 3),
                                      decoration: const BoxDecoration(
                                        color: Color(0xBFFFFFFF),
                                        borderRadius: BorderRadius.all(
                                            Radius.circular(999)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.play_arrow,
                                            size: 9 * theme.fontScale,
                                            color: const Color(0xFF111111),
                                          ),
                                          const SizedBox(width: 3),
                                          Text(
                                            _playHintLabel,
                                            style: TextStyle(
                                              color: const Color(0xFF111111),
                                              fontSize: 9.5 * theme.fontScale,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                        // VOD "now" (mode == ProductRowMode.vod, design R36): full-bleed mask +
                        // centered equalizer, no text — replaces the existing bottom coral
                        // 介紹中 banner for VOD only. mode != vod keeps the existing banner
                        // byte-identical. Same isIntroducing && !soldOut sold-out precedence
                        // gate as the existing banner.
                        if (isIntroducing && !soldOut)
                          mode == ProductRowMode.vod
                              ? const _VodIntroducingMask()
                              : Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 0,
                                  child: Container(
                                    // Fixed coral fill (rb-flutter-vod-live-product-card-restyle,
                                    // 2026-09-03) — was `theme.accent` (varied with the merchant
                                    // theme). Unifies the「介紹中」vocabulary with
                                    // `LiveOverlayChromeView._pinnedCard`'s narrate banner and
                                    // the design's `LBPProductRow` introBadge.
                                    color: _introducingBadgeFill,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 3, horizontal: 4),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.max,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        const EqualizerGlyph(
                                            size: 9, color: Color(0xFFFFFFFF)),
                                        const SizedBox(width: 3),
                                        Text(
                                          _introducingLabel,
                                          maxLines: 1,
                                          overflow: TextOverflow.clip,
                                          style: TextStyle(
                                            color: const Color(0xFFFFFFFF),
                                            // 10 → 12 (rb-flutter-vod-live-product-card-restyle),
                                            // parity with the design's introBadge
                                            // (`fontSize: 12`).
                                            fontSize: 12 * theme.fontScale,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                        // 縮圖左上角編號徽章（design R35，rb-flutter-product-row-number-badge）—
                        // orthogonal to the play affordance / bottom introducing banner above.
                        // `index == null` → no badge node at all (VOD, or an unwired call site).
                        if (index != null)
                          Positioned(
                            top: 0,
                            left: 0,
                            child: _NumberBadge(
                              theme: theme,
                              index: index!,
                              introducing: isIntroducing,
                            ),
                          ),
                      ],
                    ),
                  );
                  // R34 (`design/contract/claude-design-sync.md`): the `.row` thumbnail now
                  // ALWAYS carries a 1px `#D2D2D2` border + a 4px clip (was: only clipped when
                  // `isIntroducing` needed its bottom-edge banner corners rounded, and had no
                  // border at all) — matches the design's outer `div` (`borderRadius:
                  // '0.25rem', border: '1px solid #D2D2D2', overflow: 'hidden'`), so an
                  // unconditional bordered + clipped `Container` replaces the prior
                  // introducing-only `ClipRRect`.
                  return Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFD2D2D2), width: 1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: thumb,
                  );
                }),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  key: LbTestKeys.productRowDetail(rowIndex),
                  behavior: HitTestBehavior.opaque,
                  onTap: _open,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.text,
                          fontSize: 14 * theme.fontScale,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (!hideSub)
                        if (soldOut)
                          Text(
                            _soldOutLabel,
                            style: TextStyle(
                              color: _soldOutColor,
                              fontSize: 12 * theme.fontScale,
                            ),
                          )
                        else
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (product.originalPriceShow.isNotEmpty &&
                                  product.originalPriceShow !=
                                      product.priceShow)
                                Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: Text(
                                    product.originalPriceShow,
                                    style: TextStyle(
                                      color: _textDim,
                                      fontSize: 12 * theme.fontScale,
                                      decoration: TextDecoration.lineThrough,
                                      decorationColor: _textDim,
                                    ),
                                  ),
                                ),
                              Text(
                                product.priceShow,
                                style: TextStyle(
                                  color: _saleColor,
                                  fontSize: 14 * theme.fontScale,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              if (explicitBadge == ProductStatusBadge.outSoon)
                                _StatusPill(
                                    theme: theme,
                                    text: _outSoonLabel,
                                    color: _outSoonColor)
                              else if (explicitBadge == ProductStatusBadge.hot)
                                _StatusPill(
                                    theme: theme,
                                    text: _hotLabel,
                                    color: theme.accent),
                            ],
                          ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 明細鈕 icon — self-drawn `DetailGlyph` (design `Icons.detail`, size 16),
              // replacing the prior text-character '≣' glyph (rb-flutter-icon-parity-
              // product-detail-button). `DetailGlyph` is reused verbatim from
              // `../playershell/detail_glyph.dart` (already migrated for the clean-mode
              // exit button by `rb-flutter-clean-mode-exit-icon-fix`) — same design source
              // glyph, no duplicate CustomPainter needed.
              _RowOutlineIcon(
                theme: theme,
                onTap: _open,
                child: DetailGlyph(color: theme.accent, size: 16),
              ),
              const SizedBox(width: 8),
              if (showShare) ...[
                _RowOutlineIcon(
                  buttonKey: LbTestKeys.productRowShare(rowIndex),
                  theme: theme,
                  onTap: _share,
                  child: ShareGlyph(color: theme.accent, size: 14),
                ),
                const SizedBox(width: 8),
              ],
              _RowCartButton(
                buttonKey: LbTestKeys.productRowCart(rowIndex),
                theme: theme,
                soldOut: soldOut,
                onTap: soldOut ? _notifyRestock : _quickAdd,
              ),
            ],
          ),
        ),
        Container(height: 1, color: _stroke),
      ],
    );
  }

  // ── `.grid` layout (`LBPProductRow` layout:'grid', design R21) ────────────────
  //
  // Brand new — no existing baseline to protect. A vertical card: a 1:1 縮圖 with a
  // top-right accent play button (breathing-pulse ONLY while [live] — golden / demo
  // instances render it as a static full-opacity circle, keeping the golden
  // byte-stable per this codebase's "no animation for determinism" convention) +
  // (when sold out) a translucent 已售完 overlay; below it, the name (2-line clamp),
  // price row (accent sale price, stacked with a struck-through original price when
  // [LBProduct.originalPriceShow] is non-empty and differs from priceShow — design R21
  // `sdk-components.jsx:1108-1123`; this is UNCONDITIONAL on [hideSub], see that
  // field's doc comment — `add-recommendation-original-price-reference-ui-flutter`)
  // with an independent accent cart button.

  Widget _buildGrid(BuildContext context) {
    final soldOut =
        ProductStatusBadge.resolve(product) == ProductStatusBadge.soldOut;
    final hasOriginalPrice = product.originalPriceShow.isNotEmpty &&
        product.originalPriceShow != product.priceShow;
    return GestureDetector(
      key: LbTestKeys.recommendationCard(rowIndex),
      behavior: HitTestBehavior.opaque,
      onTap: _open,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: theme.background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  liveProductImage(
                    live: live,
                    url: product.photos.isEmpty ? null : product.photos.first,
                    placeholder: DecoratedBox(
                      decoration: BoxDecoration(color: _bgSunken),
                    ),
                  ),
                  if (soldOut)
                    Container(
                      color: const Color(0xB3FFFFFF), // white @ 0.7
                      alignment: Alignment.center,
                      child: Text(
                        _soldOutLabel,
                        style: TextStyle(
                          color: const Color(0xFF666666),
                          fontSize: 13 * theme.fontScale,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  if (onPlayClick != null)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _GridPlayButton(
                        theme: theme,
                        live: live,
                        buttonKey: LbTestKeys.recommendationPlay(rowIndex),
                        onTap: onPlayClick,
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 12 * theme.fontScale,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: soldOut
                            ? Text(
                                _soldOutLabel,
                                style: TextStyle(
                                  color: _soldOutColor,
                                  fontSize: 11 * theme.fontScale,
                                ),
                              )
                            : _gridPriceText(theme, hasOriginalPrice),
                      ),
                      if (!soldOut)
                        _GridCartButton(
                          theme: theme,
                          buttonKey: LbTestKeys.recommendationCart(rowIndex),
                          onTap: _quickAdd,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// `.grid` price cell (未售完 only). Design R21 `sdk-components.jsx:1108-1123`: when
  /// there's a strikeable original price, the sale price stacks ABOVE a struck-through
  /// original price (`Column`, left-aligned, no gap) — a DIFFERENT arrangement from
  /// `.row`'s horizontal side-by-side layout (`.row`'s condition/logic is the ONLY thing
  /// mirrored here, not its visual arrangement — design.md D1). UNCONDITIONAL on
  /// [hideSub] (design.md D2 — `.grid`'s `hideSub` only ever gated the not-yet-implemented
  /// `p.sub` caption line, never this price cell).
  Widget _gridPriceText(ReferenceUITheme theme, bool hasOriginalPrice) {
    final priceText = Text(
      product.priceShow,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: _saleColor,
        fontSize: 14 * theme.fontScale,
        fontWeight: FontWeight.w800,
      ),
    );
    if (!hasOriginalPrice) return priceText;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        priceText,
        Text(
          product.originalPriceShow,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _textDim,
            fontSize: 11 * theme.fontScale,
            decoration: TextDecoration.lineThrough,
            decorationColor: _textDim,
          ),
        ),
      ],
    );
  }
}

// MARK: - `.row`-only sub-widgets (moved verbatim from `ProductListSheet`)

/// out_soon / hot 小徽章.
class _StatusPill extends StatelessWidget {
  final ReferenceUITheme theme;
  final String text;
  final Color color;

  const _StatusPill({
    required this.theme,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: const Color(0xFFFFFFFF),
            fontSize: 10 * theme.fontScale,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}

// MARK: - VOD overlays (design R36, rb-flutter-product-row-vod-intro-mask)
//
// `.row` layout, `mode == ProductRowMode.vod` only. Parity iOS `VodPlayOverlay` /
// `VodIntroducingMask` (Swift) / Android `VodPlayOverlay` / `VodIntroducingMask` (Compose) / RN
// `VodPlayOverlay` / `VodIntroducingMask` (`.tsx`). Design `sdk-components.jsx` `LBPProductRow`'s
// `playOverlay` / `introBadge` (VOD branch).

/// VOD `upcoming`（含缺 `beginTime`/`endTime` 時的既有 fallback）覆蓋層：縮圖置中一顆 32px 黑色
/// 圓形播放鈕（`rgba(0,0,0,0.5)` 底 + 白色播放三角），取代 `mode != ProductRowMode.vod` 沿用的
/// 底部「看講解」文字膠囊。純視覺——縮圖本身既有的 `GestureDetector`（`_playTap`）已覆蓋整個縮圖
/// 範圍，這裡不重複掛 tap handler。
class _VodPlayOverlay extends StatelessWidget {
  final ReferenceUITheme theme;

  const _VodPlayOverlay({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Center(
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0x80000000), // rgba(0,0,0,0.5)
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.play_arrow,
            size: 15 * theme.fontScale,
            color: const Color(0xFFFFFFFF),
          ),
        ),
      ),
    );
  }
}

/// VOD `now`（播放進度落在該商品 `[beginTime, endTime)` 介紹時間窗內）覆蓋層：縮圖滿版
/// `rgba(0,0,0,0.5)` 遮罩 + 置中白色等化器圖示，無文字——語意等同 `mode != ProductRowMode.vod`
/// 底部珊瑚色「介紹中」橫幅（同一個 [EqualizerGlyph]），但視覺不同（滿版、無底部貼齊、無文字）。
class _VodIntroducingMask extends StatelessWidget {
  const _VodIntroducingMask();

  @override
  Widget build(BuildContext context) {
    return const Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(color: Color(0x80000000)), // rgba(0,0,0,0.5)
        child: Center(
          child: EqualizerGlyph(size: 18, color: Color(0xFFFFFFFF)),
        ),
      ),
    );
  }
}

/// 縮圖左上角編號徽章（design R35，rb-flutter-product-row-number-badge，`.row` only）：平常顯示
/// 商品在**後端原始清單**（backend order，非介紹中優先重排）中的 1-based 序號；[introducing] 為
/// `true` 時整個內容換成火焰 icon（[HotGlyph]）+「HOT」文字，取代數字，兩者互斥。設計稿
/// `sdk-components.jsx:LBPProductRow` 的 `numberBadge`（`layout:'row'` 分支：`minWidth:18,
/// height:18, fontSize:11`；黑底 70% 透明、外側兩角圓角 `0.25rem 0 0.25rem 0`）。呼叫端
/// （`_buildRow`）只在 [ProductRow.index] 非 `null` 時才建構這個 widget——VOD（`index` 恆 `null`）
/// 完全不會出現這顆徽章的任何節點。
class _NumberBadge extends StatelessWidget {
  final ReferenceUITheme theme;
  final int index;
  final bool introducing;

  const _NumberBadge({
    required this.theme,
    required this.index,
    required this.introducing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 18,
      constraints: const BoxConstraints(minWidth: 18),
      padding: EdgeInsets.symmetric(horizontal: introducing ? 6 : 5),
      decoration: const BoxDecoration(
        color: Color(0xB3000000), // rgba(0,0,0,0.7)
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(4),
          bottomRight: Radius.circular(4),
        ),
      ),
      alignment: Alignment.center,
      child: introducing
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HotGlyph(size: 10 * theme.fontScale, color: const Color(0xFFFFFFFF)),
                const SizedBox(width: 3),
                Text(
                  _numberBadgeHotLabel,
                  style: TextStyle(
                    color: const Color(0xFFFFFFFF),
                    fontSize: 11 * theme.fontScale,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            )
          : Text(
              '$index',
              style: TextStyle(
                color: const Color(0xFFFFFFFF),
                fontSize: 11 * theme.fontScale,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }
}

/// An outline-accent 30-wide circular icon button (detail affordance).
///
/// [glyph] (text-character fallback rendering) has no remaining call site as of
/// `rb-flutter-icon-parity-product-detail-button` — the last user (明細鈕) now passes
/// [child] (`DetailGlyph`), matching the sibling 分享 icon's existing `child:
/// ShareGlyph(...)` call. Kept on the constructor (not removed) as source-compat for
/// any future text-glyph call site; MUST NOT be re-adopted for a new icon position
/// without first checking whether a self-drawn glyph already exists (see
/// `docs/reference-ui/drop-in-roadmap.md` / prior `rb-flutter-icon-parity-*` batches).
class _RowOutlineIcon extends StatelessWidget {
  final ReferenceUITheme theme;
  final String? glyph;
  final void Function()? onTap;
  final Widget? child;
  final Key? buttonKey;

  const _RowOutlineIcon({
    required this.theme,
    this.glyph,
    required this.onTap,
    this.child,
    this.buttonKey,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: buttonKey,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: theme.accent, width: 1),
        ),
        alignment: Alignment.center,
        child: child ??
            Text(
              glyph!,
              style: TextStyle(
                color: theme.accent,
                fontSize: 14 * theme.fontScale,
              ),
            ),
      ),
    );
  }
}

/// The filled-accent cart button — bell glyph (補貨通知) when sold out, cart glyph
/// (加購) otherwise.
class _RowCartButton extends StatelessWidget {
  final ReferenceUITheme theme;
  final bool soldOut;
  final void Function()? onTap;
  final Key? buttonKey;

  const _RowCartButton({
    required this.theme,
    required this.soldOut,
    required this.onTap,
    this.buttonKey,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: buttonKey,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.accent,
        ),
        alignment: Alignment.center,
        child: Icon(
          soldOut ? Icons.notifications_none : Icons.shopping_cart_outlined,
          size: 16 * theme.fontScale,
          color: const Color(0xFFFFFFFF),
        ),
      ),
    );
  }
}

// MARK: - `.grid`-only sub-widgets (design R21, brand new)

/// The top-right accent play button (design R21「呼吸動畫 accent 圓鈕」). Pulses
/// (opacity breathing) ONLY while [live] is true (real runtime); a golden / demo
/// instance (`live == false`) renders a STATIC full-opacity circle — no
/// `AnimationController` ticks, so the golden stays byte-stable (this codebase's
/// established no-animation-for-determinism convention, e.g. `EqualizerGlyph`).
class _GridPlayButton extends StatefulWidget {
  final ReferenceUITheme theme;
  final bool live;
  final Key? buttonKey;
  final VoidCallback? onTap;

  const _GridPlayButton({
    required this.theme,
    required this.live,
    this.buttonKey,
    required this.onTap,
  });

  @override
  State<_GridPlayButton> createState() => _GridPlayButtonState();
}

class _GridPlayButtonState extends State<_GridPlayButton>
    with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.live) {
      _controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 900),
      )..repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final glyph = Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(color: theme.accent, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: const Icon(Icons.play_arrow, size: 14, color: Color(0xFFFFFFFF)),
    );
    final controller = _controller;
    final button = controller == null
        ? glyph
        : FadeTransition(
            opacity: controller.drive(Tween(begin: 1.0, end: 0.55)),
            child: glyph,
          );
    return GestureDetector(
      key: widget.buttonKey,
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: button,
    );
  }
}

/// The independent accent cart button beside the grid price row (design R21).
class _GridCartButton extends StatelessWidget {
  final ReferenceUITheme theme;
  final Key? buttonKey;
  final void Function()? onTap;

  const _GridCartButton({
    required this.theme,
    this.buttonKey,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: buttonKey,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(color: theme.accent, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: const Icon(Icons.shopping_cart_outlined,
            size: 13, color: Color(0xFFFFFFFF)),
      ),
    );
  }
}

// MARK: - Decorative design tokens (literal minimal hex, mirrors `product_list_sheet.dart`)

final Color _textDim = colorFromHex('#6B6775') ?? const Color(0xFF6B6775);
final Color _stroke = colorFromHex('#ECEAF0') ?? const Color(0xFFECEAF0);
final Color _bgSunken = colorFromHex('#F4F4F6') ?? const Color(0xFFF4F4F6);
final Color _saleColor = colorFromHex('#E0334B') ?? const Color(0xFFE0334B);
final Color _soldOutColor = colorFromHex('#9A96A3') ?? const Color(0xFF9A96A3);
final Color _outSoonColor = colorFromHex('#F5A623') ?? const Color(0xFFF5A623);

/// The「介紹中」badge fill — fixed coral `rgba(240,50,70,.7)` = `#F03246` @ alpha 0.7
/// (rb-flutter-vod-live-product-card-restyle, 2026-09-03 — was `theme.accent`). Kept as
/// its own file-local constant (not shared with `live_overlay_chrome_view.dart`'s
/// equivalent) per `design.md` Decisions — same value, independent per-file token.
final Color _introducingBadgeFill =
    (colorFromHex('#F03246') ?? const Color(0xFFF03246)).withValues(alpha: 0.7);

const String _soldOutLabel = '已售完';
const String _introducingLabel = '介紹中';
const String _outSoonLabel = '即將售完';
const String _hotLabel = '熱賣中';
const String _playHintLabel = '看講解';

/// 縮圖左上角編號徽章（design R35）介紹中內容的文字——「熱賣中」（[_hotLabel]，`is_hot` 商品狀態
/// 標籤）是一個完全不同的概念，兩者刻意使用不同常數，不共用。
const String _numberBadgeHotLabel = 'HOT';

// MARK: - LBProductRecommendation → LBProduct (PRESENTATION-ONLY conversion)
//
// `LBProductDetailState.recommendations` (`[LBProductRecommendation]`, from
// `expose-other-goods-recommendations-template`) is a DELIBERATELY minimal shape
// (`productId` / `name` / `priceShow` / `originalPriceShow` / `pic` / `videoId?` /
// `soldOut`) — it carries no `specifications` / `specOptions` / `stock`
// (`originalPriceShow` was ADDED by `add-recommendation-original-price-template-
// flutter`, no longer part of the gap — see the KNOWN GAP note below, which is now
// narrower). [ProductRow] renders `LBProduct`, so this extension (mirrors iOS
// `LBProductRecommendation.asDisplayProduct`, `ProductRowView.swift`) builds a
// PRESENTATION-ONLY `LBProduct` carrying just enough to paint the `.grid` card
// correctly.
//
// ⚠️ Flutter-specific widening of the iOS/Android caveat (RN hit the identical
// constraint and converged on the same mitigation — see below): on iOS / Android, the
// container resolves the REAL `LBProduct` for a tapped recommendation from a
// synchronously-held `channel.otherGoods` (keyed by `productId`) before forwarding it
// to `onProductTap` — so [asDisplayProduct] there is used ONLY to paint the card,
// never as the tap payload. Flutter's (and RN's) core exposes NO such synchronous
// channel/otherGoods accessor at the reference-ui layer (Flutter's platform-view
// bridge keeps channel state native-side; `DefaultPlayerTemplate` only exposes it
// privately via `setOtherGoods`, and adding a public getter would be a `flutter-ui`
// TEMPLATE-layer change, out of scope for this `## Layer: reference-ui` change — I7).
// So on Flutter, [asDisplayProduct] IS the drill-in tap payload for the TAPPED
// recommendation (`ProductSheetsOverlayView._handleOpenRecommendation` /
// `_handleQuickAddRecommendation`) — that nested detail therefore has NO variant
// chips (`specifications`/`specOptions` empty) and a derived (not real) stock number
// (but DOES now carry a real `originalPriceShow`, so its price/strike-through display
// is accurate). This is a documented, accepted KNOWN GAP (see
// `reference-ui-rendering/spec.md`'s Requirement for this change), not an oversight.
//
// The OTHER side of a drill-in — pushing "what's currently open" onto the breadcrumb
// so「返回」can restore it — does NOT use this conversion and is NOT degraded: it
// synthesizes from the currently-open `LBProductDetailState` instead
// (`detail_breadcrumb.dart`'s `detailAsDisplayProduct`), which already carries full
// `specifications`/`specOptions`/`stock` — lossless. Mirrors RN's identical two-sided
// split (`recommendationAsDisplayProduct` vs `detailAsDisplayProduct`,
// `rb-rn-product-detail-recommendations`).
extension ProductRecommendationDisplay on LBProductRecommendation {
  LBProduct get asDisplayProduct => LBProduct(
        id: productId,
        name: name,
        priceShow: priceShow,
        originalPriceShow: originalPriceShow,
        stock: soldOut == 1 ? 0 : 1,
        pic: pic,
        photos: pic.isEmpty ? const [] : [pic],
        goodsGpn: '',
        // brief / description (rb-flutter-recommendation-product-intro-carry-through):
        // pass through the real values already carried by `LBProductRecommendation`
        // (add-recommendation-brief-description-template-flutter). This alone does NOT
        // close the product-intro carry-through gap — the tap payload built from this
        // extension is never merged into `productOverlay.products`, so
        // `ProductSheetsModel.briefFor`/`descriptionFor`'s PRIMARY snapshot lookup still
        // misses for a recommendation resolved from `recommendations` (not the current
        // video's own goods). The actual fix is the container-side fallback cache (see
        // `ProductSheetsOverlayView._handleOpenRecommendation` /
        // `_handleQuickAddRecommendation` and `ProductSheetsModel.briefFor`/
        // `descriptionFor`). This transfer is kept anyway so `asDisplayProduct` itself
        // stays a faithful, non-lossy conversion of its source fields.
        brief: brief,
        description: description,
        soldOut: soldOut,
        isHot: 0,
        diversionUrl: '',
        videoId: videoId,
      );
}
