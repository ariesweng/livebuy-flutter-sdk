import 'package:flutter/material.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart' show LBProduct;

import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';
import 'shop_bag_glyph.dart';
import 'product_row.dart';
import 'product_row_overlay.dart';
import 'sheet_header_close_button.dart';
import 'sheet_scaffold.dart';

// ProductListSheet — family-3 product sheet-stack surface 1 (product list drawer).
//
// Spec: `reference-ui-rendering/spec.md` (family-3 product + sheets, surface 1).
// Flutter sibling of iOS `ProductListView.swift` (rb-ios-product-sheets, D-2) and
// Android `ProductListSheet.kt` (rb-android-product-sheets, golden
// `product-list-drawer-populated`).
//   Design source: `design/templates/minimal/screens.jsx` `ProductListSheet`
//     (lines 505-595) + `design/templates/minimal/sdk-components.jsx`
//     `LBPBottomSheet` (751) / `LBPSheetHeader` (787) / `LBPProductRow`
//     `layout:'row'` (816-912) / `LBPCartCTA` (993-1006).
//
// The bag-opened product LIST drawer: a top-rounded bottom-sheet shell (grab handle
// + centered 「銷售商品」header + decorative close) listing the core-fed products in
// a plain Column (thumb placeholder + name + sale/strike price, or 已售完 line when
// sold out), plus a bottom-pinned cart CTA showing the cart count when `> 0`.
//
// SUB-VIEW INPUT PATTERN (mirrors family-1 `OperationRailView` / family-2
// `ChatFeedView` and the iOS / Android surfaces EXACTLY — see the contract in
// `ProductSheetsOverlayView`):
//   1. `theme:` (ReferenceUITheme, required)  — FIRST named argument, always.
//   2. bound SNAPSHOT VALUES, BY VALUE        — `products: List<LBProduct>` (the
//      core-fed, already-merged / ordered list — this layer MUST NOT slice / merge
//      / re-sort) + `cartCount: int` (per-session successful-add count for the CTA
//      badge). Read-only; never the model / template.
//   3. action callbacks (LAST, each defaulting to a no-op):
//      • `onOpenProduct: (LBProduct) -> void` — a product-row tap funnels HERE, NOT
//        to a template intent. The container forwards it to the host-wired
//        `onProductTap`, which the host wires to core
//        `LivebuyPlayer.simulateProductTap(product)`. reference-ui NEVER opens the
//        detail itself (D-2 — mirrors family-2 ChatFeedView's eventJoin forwarder).
//      • `onOpenCart: () -> void` — the bottom-pinned cart CTA tap forwards to
//        `model.openCart()` → `DefaultCartCTA.openCart()` (host passthrough; the
//        template owns no checkout page).
//
// One-way data flow (D-1): this surface reads ONLY its passed-in values; it never
// reaches back into `ProductSheetsModel` / `DefaultPlayerTemplate`, and it does NOT
// call any core `simulate*` / `addToCart`. It renders correctly with all callbacks
// null / omitted (so demo / preview / golden instances construct action-free).
//
// FAMILY BOUNDARY: the RECONCILED 收藏鈕 (favorite affordance) lives ONLY in the
// product-DETAIL sheet (`ProductDetailSheet`), NOT here. This list surface MUST NOT
// render a favorite control and MUST NOT read goods-tracking state.
//
// LAYOUT (rb-sheet-pinned-header-footer, iOS parity): the grab handle + header PIN at
// top, the 查看購物車 CTA PINS at bottom, and only the product rows BODY scrolls — within a
// ½-screen height cap (via `LBSheetScaffold`). Unlike the iOS `ImageRenderer` snapshot
// path (which renders `ScrollView` blank), the Flutter golden path renders the scaffold's
// `SingleChildScrollView` correctly, so the golden reflects the pinned layout.
//
// SNAPSHOT-DETERMINISM (iOS / Android lessons baked in): plain Column / Row inside the
// scaffold's single scroll body — NO ListView / GridView / nested scroll. NO Material
// Switch. The 縮圖 is the gated live image over a placeholder fill (`live == false` →
// placeholder only, byte-stable; `live == true` → real `Image.network`). Deterministic
// (no animation / randomness).

// MARK: - Decorative design tokens (literal minimal hex via colorFromHex)
//
// `theme.accent` / `theme.text` / `theme.background` come from the resolved theme.
// These are FIXED decorative colors lifted verbatim from the design's
// `theme.surface.*` / `theme.sale` / `theme.soldOut` (light mode,
// `design/brands/livebuy/tokens.jsx`) — design-literal, NOT theme-resolved. Kept
// consistent with iOS `ProductListView` / Android `ProductListSheet` so the family-3
// sheets read as one family.

/// `theme.surface.textDim` (secondary / caption / strike text).
final Color _textDim = colorFromHex('#6B6775') ?? const Color(0xFF6B6775);

/// `theme.surface.stroke` (hairline row / footer border).
final Color _stroke = colorFromHex('#ECEAF0') ?? const Color(0xFFECEAF0);

/// `theme.surface.strokeStrong` (grab handle).
final Color _strokeStrong = colorFromHex('#D8D5DE') ?? const Color(0xFFD8D5DE);

/// `theme.surface.bgSunken` (thumbnail placeholder fill — light mode).
final Color _bgSunken = colorFromHex('#F4F4F6') ?? const Color(0xFFF4F4F6);

// `_saleColor` / `_soldOutColor` / `_outSoonColor` (row price / badge colors) moved to
// `product_row.dart` with the extracted `ProductRow` widget (rb-flutter-product-detail-
// recommendations §1) — this file no longer draws a row itself.

// MARK: - Static copy (LBPSheetHeader / LBPCartCTA labels)

/// Sheet header title.
const String _titleLabel = '銷售商品';

/// Bottom cart CTA label.
const String _cartLabel = '查看購物車';

/// Empty-state line (no products).
const String _emptyLabel = '目前沒有商品';

// `_soldOutLabel` / `_introducingLabel` / `_outSoonLabel` / `_hotLabel` (row copy) moved
// to `product_row.dart` alongside the extracted `ProductRow` widget.

/// Search field placeholder (rb-flutter-product-list-search，問題 2).
const String _searchPlaceholder = '搜尋商品名稱';

/// Search cancel button label.
const String _searchCancel = '取消';

/// No-search-hit empty line for [query].
String _noResultsLabel(String query) => '找不到符合「$query」的商品';

/// The family-3 product LIST drawer. Renders the core-fed [products] as a plain
/// non-scrolling Column of product rows (縮圖 placeholder + name + sale/strike
/// price, or 已售完 when sold out) inside a top-rounded bottom-sheet shell with the
/// 「銷售商品」header, plus a bottom-pinned cart CTA badged with [cartCount]. A row
/// tap forwards to [onOpenProduct] (→ host → core `simulateProductTap`); the CTA
/// forwards to [onOpenCart]. This layer NEVER opens the detail itself and NEVER
/// renders the 收藏鈕 (that is the detail sheet's affordance).
///
/// Renders correctly with both callbacks omitted (golden / preview safe).
class ProductListSheet extends StatefulWidget {
  /// The resolved reference-ui theme (FIRST named argument, always).
  final ReferenceUITheme theme;

  /// The core-fed products snapshot (`DefaultProductOverlayState.products`),
  /// BY VALUE. Already merged / ordered by the data layer — this layer MUST NOT
  /// slice / merge / re-sort. Read-only.
  final List<LBProduct> products;

  /// Per-session successful-add count (`DefaultCartCTA.count`) — the cart CTA
  /// shows the count badge when `> 0`. Read-only.
  final int cartCount;

  /// `false` (snapshot / demo) → row thumbnails draw the deterministic placeholder
  /// only (goldens unchanged). `true` (host runtime) → load each `product.photos[0]`
  /// over the placeholder via a gated `Image.network` (rb-product-real-images).
  final bool live;

  /// The FULL set of currently-introducing product ids (`ProductSheetsModel.liveActiveProducts`
  /// mapped to `.id` — every LIVE `narrate_status == 2` product, not just the first). Every row
  /// whose `product.id` is a member (`ProductBagNarratingBadge.isNarrating`, see
  /// `product_row_overlay.dart`) draws the「介紹中」bottom banner; in LIVE the play/seek
  /// affordance is hidden (live has no timeline to scrub). The data layer surfaces this list
  /// introducing-FIRST (`productsIntroducingFirst`) — this layer MUST NOT re-sort. Empty set
  /// (default; VOD / demo / nothing introducing) → no banner, play shown.
  /// Parity iOS / Android / RN `introducingProductIds` (flutter-product-bag-multi-narrating,
  /// replaces the former single-value `introducingProductId: String?`).
  final Set<String> introducingProductIds;

  /// 縮圖疊層的播放模式（product-row-status-overlay）：`vod` → 播放 icon；`live` → 介紹中
  /// 落在 narrating row；`replay` → 介紹中 落在 `playbackPosition ∈ [beginTime, endTime]` 的商品，
  /// 否則播放 icon。`null` / 省略（既有呼叫點 / golden）→ 回退由真實影格 `live` 派生
  /// （`live ? live : vod`）保 golden byte-identical；production 容器由 `model.rowMode` 供應。
  /// 與 `live`（圖片載入）正交。Parity iOS / Android / RN.
  final ProductRowMode? mode;

  /// 當下播放秒數（replay 用）——對照每個商品的 `[beginTime, endTime]` 判「介紹中」。Default 0。
  final int playbackPosition;

  /// Host-wired 明細鈕 / 商品名 tap → FULL browse sheet. The container forwards this to its
  /// host-wired `onProductTap`, which the host wires to core
  /// `LivebuyPlayer.simulateProductTap(product)`. Default no-op so demo / golden
  /// instances render correctly action-free (D-2).
  final void Function(LBProduct product)? onOpenProduct;

  /// Host-wired 加購鈕 (in-stock cart glyph) tap → COMPACT AddToCart sheet
  /// (rb-align-flutter-product-action-sheet). Distinct from [onOpenProduct] (明細鈕 / 商品名
  /// → full browse) so the container picks the compact purchase sheet vs the full detail
  /// sheet. Both still funnel to core `simulateProductTap` via the container. `null` →
  /// falls back to [onOpenProduct]. Default no-op for demo / golden instances.
  final void Function(LBProduct product)? onQuickAdd;

  /// Host-wired 縮圖點擊 → 影片跳轉到該商品介紹時間（`LBProduct.beginTime`，秒）。對齊設計
  /// `LBPProductRow` 的縮圖 `onSeek`（issue 5）。容器轉發到 host-wired `onSeekToProductIntro`，
  /// 預設呼 core `seek(beginTime)`。Default no-op for demo / golden instances.
  final void Function(LBProduct product)? onSeekToIntro;

  /// Host-wired 列分享鈕點擊 → 系統分享，連結帶該商品介紹時間 `?t=beginTime`。對齊設計
  /// `LBPProductRow` 的 `onShare`（精簡圓形 icon，與明細 footer 直式分享為不同元件，issue 6）。
  /// Default no-op for demo / golden instances.
  final void Function(LBProduct product)? onShareProduct;

  /// Host-wired cart-CTA tap → `model.openCart()` (host passthrough). Default
  /// no-op for demo / golden instances.
  final void Function()? onOpenCart;

  /// Header 右上角關閉 icon tap (rb-flutter-sheet-header-close-unify): no longer decorative —
  /// forwards to the host (Flutter's ProductList drawer is always-inline, no presented flag, so
  /// closing is a host concern, like Android). Null → inert (demo / golden).
  final void Function()? onClose;

  /// 售完列補貨鈴鐺專屬入口 → NotifyRestock (rb-flutter-soldout-row-detail-vs-restock，問題 2)。
  /// null → falls back to [onOpenProduct]. 名稱 / 明細 keep [onOpenProduct] (→ detail).
  final void Function(LBProduct product)? onNotifyRestock;

  /// 搜尋兩態 seed（rb-flutter-product-list-search，問題 2）：預設收合 / 空 → 既有 golden
  /// byte-identical；golden 測試可 seed 展開態（命中 / 無結果）。
  final bool searchOpenInitial;
  final String queryInitial;

  const ProductListSheet({
    super.key,
    required this.theme,
    required this.products,
    required this.cartCount,
    this.live = false,
    this.introducingProductIds = const {},
    this.mode,
    this.playbackPosition = 0,
    this.onOpenProduct,
    this.onQuickAdd,
    this.onSeekToIntro,
    this.onShareProduct,
    this.onOpenCart,
    this.onClose,
    this.onNotifyRestock,
    this.searchOpenInitial = false,
    this.queryInitial = '',
  });

  @override
  State<ProductListSheet> createState() => _ProductListSheetState();
}

class _ProductListSheetState extends State<ProductListSheet> {
  // 本地搜尋 UI 狀態——使用者驅動的呈現過濾，非 view-model（parity iOS/Android）。
  late bool _searchOpen = widget.searchOpenInitial;
  late final TextEditingController _query =
      TextEditingController(text: widget.queryInitial);

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    // 顯示過濾：case-insensitive `name` contains。純呈現過濾、不 mutate products snapshot。
    final q = _query.text.trim().toLowerCase();
    final displayed = q.isEmpty
        ? widget.products
        : widget.products
            .where((p) => p.name.toLowerCase().contains(q))
            .toList();

    // Top-rounded bottom-sheet shell (`LBPBottomSheet` borderRadius 20 20 0 0). The
    // grab handle + 銷售商品 header PIN at top, the 查看購物車 CTA PINS at bottom, and only
    // the product rows BODY scrolls — within the ½-screen cap (rb-sheet-pinned-header-footer,
    // iOS parity): a long product list now scrolls between the pinned header and the
    // always-visible cart CTA. Unlike the iOS snapshot path, the Flutter golden renders the
    // `SingleChildScrollView` correctly, so the golden reflects the pinned layout.
    // E2E key (INERT — KeyedSubtree paints nothing) on the list-sheet root.
    return KeyedSubtree(
      key: LbTestKeys.productList,
      child: Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.background,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: LBSheetScaffold(
        // 拖曳把手即時調整高度＋拖曳收合（下限↔80%，一條連續手勢，
        // rb-flutter-sheetkit-resize-dismiss-unify）—— 先前完全不可拖曳，現與其餘 4 個 sheet
        // 共用同一套機制。
        onDismiss: widget.onClose,
        header: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _GrabHandle(),
            // 收合：🔍 鈕（可點，展開）· 標題 · 關閉；展開：搜尋膠囊 + 取消（parity iOS/Android）。
            if (_searchOpen)
              _SearchHeader(
                theme: theme,
                controller: _query,
                onChanged: (_) => setState(() {}),
                onCancel: () => setState(() {
                  _searchOpen = false;
                  _query.clear();
                }),
              )
            else
              _SheetHeader(
                theme: theme,
                productCount: widget.products.length,
                onSearch: () => setState(() => _searchOpen = true),
                onClose: widget.onClose,
              ),
          ],
        ),
        body: displayed.isEmpty
            // 區分「本來就沒商品」與「搜尋無命中」（parity iOS/Android）。
            ? _EmptyState(
                theme: theme,
                message: widget.products.isEmpty
                    ? _emptyLabel
                    : _noResultsLabel(_query.text),
              )
            // Plain Column (in the scaffold's scroll body) — each row carries its own
            // bottom hairline.
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < displayed.length; i++)
                    ...() {
                      final product = displayed[i];
                      // 縮圖疊層由播放 MODE 決定（product-row-status-overlay），透過純函式。`mode` 為
                      // null（既有呼叫點 / golden）→ 由真實影格 `live` 派生（live → live else vod）保
                      // golden byte-identical。showPlay / showIntroducing 在單一 row 互斥。
                      final effectiveMode = widget.mode ??
                          (widget.live ? ProductRowMode.live : ProductRowMode.vod);
                      final isNarratingThis = ProductBagNarratingBadge.isNarrating(
                          product.id, widget.introducingProductIds);
                      final overlay = productRowOverlay(
                        mode: effectiveMode,
                        isNarrating: isNarratingThis,
                        beginTime: product.beginTime,
                        endTime: product.endTime,
                        position: widget.playbackPosition,
                      );
                      return [
                        ProductRow(
                          rowIndex: i,
                          theme: theme,
                          product: product,
                          live: widget.live,
                          showPlay: overlay.showPlay,
                          isIntroducing: overlay.showIntroducing,
                          showShare: overlay.showShare,
                          onOpenProduct: widget.onOpenProduct,
                          onQuickAdd: widget.onQuickAdd,
                          onNotifyRestock: widget.onNotifyRestock,
                          onSeekToIntro: widget.onSeekToIntro,
                          onShareProduct: widget.onShareProduct,
                        ),
                      ];
                    }(),
                ],
              ),
        footer: _CartCTAFooter(
          theme: theme,
          cartCount: widget.cartCount,
          onOpenCart: widget.onOpenCart,
        ),
      ),
      ),
    );
  }
}

// MARK: - Grab handle (`LBPBottomSheet` handle — shared styling w/ WinClaimSheet)

/// A 36×4 fully-rounded grab handle, centered (`theme.surface.strokeStrong` fill).
class _GrabHandle extends StatelessWidget {
  const _GrabHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: _strokeStrong,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ),
    );
  }
}

// MARK: - Sheet header (`LBPSheetHeader` — search slot · centered title · close)
//
// Mirrors `LBPSheetHeader`: a 32-wide leading slot (search affordance — purely
// decorative here, the list search field is out of scope for the reference-ui
// surface), a centered bold title, and a trailing decorative close circle. The
// title shows the count when there are products (matches `ProductListSheet`'s
// 「銷售商品 (n)」), otherwise the plain「銷售商品」.

class _SheetHeader extends StatelessWidget {
  final ReferenceUITheme theme;
  final int productCount;
  final void Function()? onClose;
  final void Function()? onSearch;

  const _SheetHeader({
    required this.theme,
    required this.productCount,
    this.onClose,
    this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final title =
        productCount > 0 ? '$_titleLabel ($productCount)' : _titleLabel;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Row(
        children: [
          // Leading 32-wide search button — taps expand the search field
          // (rb-flutter-product-list-search，問題 2). No longer decorative.
          GestureDetector(
            key: LbTestKeys.productSearchButton,
            behavior: HitTestBehavior.opaque,
            onTap: onSearch,
            child: SizedBox(
              width: 32,
              height: 32,
              child: Center(
                child: Text(
                  '🔍',
                  style: TextStyle(
                    color: theme.text,
                    fontSize: 15 * theme.fontScale,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.text,
                fontSize: 15 * theme.fontScale,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Trailing close — shared transparent close button (rb-flutter-sheet-header-close-unify).
          // No longer decorative: tapping forwards `onClose` (host-wired drawer close).
          SheetHeaderCloseButton(theme: theme, onTap: onClose),
        ],
      ),
    );
  }
}

// MARK: - Expanded search header (`LBPSheetHeader` 展開態, parity iOS/Android)

/// bgSunken 膠囊（🔍 + TextField「搜尋商品名稱」）+ 取消 accent 文字鈕。清除（x）鈕已移除——
/// 取消已同時收合搜尋列並清空 query，單獨的清除鈕是多餘的（rb-search-bar-cancel-only）。
class _SearchHeader extends StatelessWidget {
  final ReferenceUITheme theme;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final void Function() onCancel;

  const _SearchHeader({
    required this.theme,
    required this.controller,
    required this.onChanged,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: _bgSunken,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  Text('🔍',
                      style: TextStyle(
                          color: _textDim, fontSize: 14 * theme.fontScale)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      key: LbTestKeys.sheetSearchField,
                      controller: controller,
                      onChanged: onChanged,
                      maxLines: 1,
                      cursorColor: theme.accent,
                      style: TextStyle(
                          color: theme.text, fontSize: 14 * theme.fontScale),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        hintText: _searchPlaceholder,
                        hintStyle: TextStyle(
                            color: _textDim, fontSize: 14 * theme.fontScale),
                      ),
                    ),
                  ),
                  // Clear ("x") button removed — 取消 already collapses the search bar AND
                  // clears the query in one tap, making a separate clear affordance redundant
                  // (rb-search-bar-cancel-only).
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            key: LbTestKeys.sheetSearchCancel,
            behavior: HitTestBehavior.opaque,
            onTap: onCancel,
            child: Text(
              _searchCancel,
              style: TextStyle(
                color: theme.accent,
                fontSize: 14 * theme.fontScale,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// MARK: - Empty state (no products / no search results)

/// A centered empty-state line. [message] distinguishes「目前沒有商品」(empty list) from
///「找不到符合『…』的商品」(search no-hit).
class _EmptyState extends StatelessWidget {
  final ReferenceUITheme theme;
  final String message;

  const _EmptyState({required this.theme, this.message = _emptyLabel});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Text(
          message,
          style: TextStyle(
            color: _textDim,
            fontSize: 13 * theme.fontScale,
          ),
        ),
      ),
    );
  }
}

// MARK: - Product row — EXTRACTED to `product_row.dart` (rb-flutter-product-detail-
//         recommendations §1). `ProductRow(layout: .row, ...)` above is the direct,
//         byte-identical successor to the former private `_ProductRow` that used to
//         live here; `.grid` (recommendation cards) is a NEW layout used by
//         `ProductDetailSheet`'s「更多商品」section, not by this list.

// MARK: - Bottom cart CTA footer (`LBPCartCTA` — bag glyph + label + count)
//
// A top-hairline-separated footer carrying the full-width accent cart CTA, badged
// with the cart count when `> 0`.

class _CartCTAFooter extends StatelessWidget {
  final ReferenceUITheme theme;
  final int cartCount;
  final void Function()? onOpenCart;

  const _CartCTAFooter({
    required this.theme,
    required this.cartCount,
    required this.onOpenCart,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Top hairline over the CTA footer (LBPCartCTA footer borderTop: 1px stroke).
        Container(height: 1, color: _stroke),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
          child: GestureDetector(
            key: LbTestKeys.cartCtaFooter,
            behavior: HitTestBehavior.opaque,
            onTap: onOpenCart,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: theme.accent,
                // 統一按鈕圓角 → theme.cornerRadius（原 14，rb-flutter-button-corner-radius-unify）。
                borderRadius: BorderRadius.circular(theme.cornerRadius),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.max,
                children: [
                  // rb-flutter-cart-cta-shopbag-glyph: design `LBPCartCTA` uses the white outline
                  // `shopBag` (full handle ring + mouth line), NOT the multicolor 🛍 emoji.
                  ShopBagGlyph(color: const Color(0xFFFFFFFF), size: 20 * theme.fontScale),
                  const SizedBox(width: 10),
                  Text(
                    _cartLabel,
                    style: TextStyle(
                      color: const Color(0xFFFFFFFF),
                      fontSize: 16 * theme.fontScale,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  // rb-flutter-product-sheet-cart-cta-cleanup (問題6) — `cartCount` is the per-session
                  // successful-add count (`DefaultCartCTA.count`), NOT the real cart quantity, so the
                  // misleading `(n)` badge is no longer rendered. The field is RETAINED (call site
                  // still passes it, ctor stable, one-line restore) but only the fixed label shows.
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
