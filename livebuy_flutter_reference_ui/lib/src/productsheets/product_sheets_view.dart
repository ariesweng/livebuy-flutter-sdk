import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart' show LBProduct;
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show
        DefaultPlayerTemplate,
        LBProductDetailState,
        LBProductRecommendation,
        LBAuthGateState,
        LBAuthTriggerAction;
import '../gapsurfaces/auth_gate_modal.dart';

import '../reference_ui_theme.dart';
import 'bottom_sheet_presenter.dart';
import 'product_sheets_model.dart';
// Surface widgets — landed by the parallel Surfaces agents. The container fixes the
// call-site shapes; the file names match the imports EXACTLY (no shim files).
import 'product_list_sheet.dart';
import 'product_detail_sheet.dart';
// `ProductRecommendationDisplay.asDisplayProduct` extension (rb-flutter-product-detail-
// recommendations §5) — Dart extension methods require an explicit import to be in scope.
import 'product_row.dart' show ProductRecommendationDisplay;
import 'select_variant_prompt_modal.dart';
// mini_cart_peek.dart is no longer rendered as a floating surface here
// (rb-flutter-remove-minicart-peek-surface); the MiniCartPeek widget is still used by the
// now-introducing carousel + exported by the package barrel.
import 'notify_restock_sheet.dart';
import 'product_zoom_overlay.dart';
import 'cart_toast_view.dart';
import 'cart_loading_floor.dart';

// rb-flutter-show-stock-caption-toggle — the two pure entry points for the
// `extensions.show_stock` merchant gate live next to the surface that consumes them
// (`product_detail_sheet.dart`, the same placement iOS / Android / RN chose). They are
// re-exported HERE, by name only, because this container file is already in the package
// barrel while `product_detail_sheet.dart` is NOT — a host composing its own
// `ReferenceUIDesign` can then resolve the raw wire value EXACTLY the way reference-ui
// does. Deliberately a `show` re-export (same idiom as `live_buy_widget.dart`'s
// `export 'widget_data.dart' show WidgetContainerMode;`) rather than adding the whole
// sheet library to the barrel, which would publish an unrelated set of widget types.
export 'product_detail_sheet.dart' show normalizeShowStock, showsStockCaption;

// ProductSheetsOverlayView — family-3 product sheet-stack container (Flutter SKELETON).
//
// Spec: `reference-ui-rendering/spec.md` (family-3 product + sheets, 4 surfaces).
// Flutter sibling of iOS `ProductSheetsOverlayView.swift` (rb-ios-product-sheets +
// rb-ios-gap-surfaces-design-reconcile 收藏鈕) and Android `ProductSheetsOverlayView.kt`
// (rb-android-product-sheets).
//
// The top-level family-3 container. It lays out the FOUR family-3 surface widgets:
//
//   1. ProductListSheet     — bottom sheet product list drawer + cart CTA
//                             (`LBPBottomSheet` / `LBPSheetHeader` / `LBPProductRow`
//                             / `LBPCartCTA`)
//   2. ProductDetailSheet   — product detail sheet (variant chips / qty stepper /
//                             加入購物車 / RECONCILED 收藏鈕), presented when the
//                             selected `detail` is NOT sold-out
//                             (`LBPVariantPicker` / `LBPQtyStepper` / `LBPFavButton`)
//   3. MiniCartPeek         — floating mini-cart peek (`LBPMiniCart`), drawn only
//                             when `miniCart.peek != null`
//   4. NotifyRestockSheet   — restock-notify sheet, presented WHEN the selected
//                             `detail` IS sold-out (`detail.soldOut == 1`)
//
// This SKELETON owns the layout, a read-only [ProductSheetsModel], the resolved
// [ReferenceUITheme], and composes the four surface widgets BY TYPE NAME (the
// parallel Surfaces agents land those types after this skeleton — forward refs are
// fine within one Dart package). Until they exist this file will not compile on its
// own; that is expected. The container FIXES the call-site shapes so the agents
// converge on the SUB-VIEW INPUT PATTERN documented below.
//
// ─────────────────────────────────────────────────────────────────────────────
// SUB-VIEW INPUT PATTERN — the contract the 4 Surfaces agents MUST follow
// ─────────────────────────────────────────────────────────────────────────────
//
// Every family-3 surface widget is a `class … extends StatelessWidget` whose
// constructor takes, IN THIS ORDER (named params):
//
//   1. `theme:` (ReferenceUITheme, required)  — FIRST, always.
//   2. its bound SNAPSHOT VALUE(S)            — read-only state, passed BY VALUE
//                                                from ProductSheetsModel (never the
//                                                model, never the template).
//   3. optional action callbacks             — trailing, EACH defaulting to a
//                                                no-op. The container owns NO core
//                                                action; the host wires the exits
//                                                (product tap / cart / add / fav /
//                                                restock notice / mini-cart).
//
// A surface widget reads ONLY its passed-in values — it MUST NOT reach back into
// ProductSheetsModel or DefaultPlayerTemplate (one-way data flow), MUST NOT hold a
// second copy of state, MUST render correctly with all callbacks null / omitted (so
// golden / widget tests construct it action-free), MUST NOT use any scrollable
// container (`ListView` / `GridView` / `SingleChildScrollView`) or network image
// (`Image.network` / `NetworkImage`). The restock 「通知我補貨」toggle is a custom
// pill switch (`Container` capsule + circle knob) — NOT a Material `Switch`. The
// variant chip group is a `Wrap` (or chunked `Row`) — NOT a `GridView`.
//
// The four Surfaces agents implement EXACTLY these constructors (see the call sites
// in `build` below):
//
// ⚠️ HISTORICAL SNAPSHOT — the four signatures listed below are the family-3 SKELETON's
// original contract, NOT the current one. The surfaces have since gained parameters this
// list never got (e.g. `ProductDetailSheet`'s `selectedSpec` / `addToCartInFlight` /
// `presentation` / `live` / `isLive` / `brief` / `showStock` / `onShare` / `onDismiss` /
// `onZoomImage`), so the word "EXACTLY" above stopped being literally true long before
// `showStock` arrived. What this block still pins is the PARAMETER-ORDER RULE
// (theme → snapshot values → trailing optional callbacks); for the current signature of
// any surface, read that widget's own constructor.
//
//   ProductListSheet({
//       required ReferenceUITheme theme,
//       required List<LBProduct> products, required int cartCount,
//       void Function(LBProduct product)? onOpenProduct,   // → host → core simulateProductTap
//       void Function()? onOpenCart })                     // → model.openCart()
//
//     Bottom sheet shell (`LBPBottomSheet` + `LBPSheetHeader`); plain non-scrolling
//     `Column` of product rows (縮圖 placeholder / 名 / 售價 / 原價劃線 / 售完態,
//     `LBPProductRow`); bottom cart CTA (`LBPCartCTA`) shows `cartCount`. A row tap
//     forwards `onOpenProduct(product)` (host wires it to core
//     `LivebuyPlayer.simulateProductTap` — reference-ui NEVER opens the detail
//     itself). The cart CTA forwards `onOpenCart`.
//
//   ProductDetailSheet({
//       required ReferenceUITheme theme,
//       required LBProductDetailState detail,
//       required List<LBVariantGroup> variantGroups,
//       required Map<int, int> variantSelection,
//       required LBQtyState qty,
//       required bool needsVariantSelection, required bool addToCartFailed,
//       bool faved = false,
//       void Function(int groupIndex, int optionIndex)? onSelectVariant,
//       void Function(int qty)? onSetQty,
//       void Function()? onInc, void Function()? onDec,
//       void Function()? onAddToCart,
//       void Function()? onToggleFavorite })
//
//     `LBPBottomSheet` shell; 縮圖 placeholder `photos` / `name` / `priceShow` /
//     `originalPriceShow` 劃線. Variant chips (`LBPVariantPicker`, `Wrap`/chunked
//     `Row`, selected when `variantSelection[gi] == oi`) → `onSelectVariant(gi, oi)`.
//     Qty stepper (`LBPQtyStepper`, reads `qty.{qty,min,max}`; DISABLED when
//     `qty.max == 0`) → `onSetQty` / `onInc` / `onDec`. Bottom action row: a width-56
//     RECONCILED 收藏鈕 (`LBPFavButton`) to the LEFT of the 加入購物車 CTA —
//     `faved == false` → 空心 `Icons.favorite_border` + label「收藏」; `faved == true`
//     → 實心 `Icons.favorite` + accent + label「已收藏」; tap → `onToggleFavorite`.
//     加入購物車 CTA → `onAddToCart`. `needsVariantSelection` → centered「請選規格」
//     prompt (`LBPAlertModal` / `LBPCenterPopup`); `addToCartFailed` → error banner.
//
//   MiniCartPeek({
//       required ReferenceUITheme theme,
//       required LBMiniCartPeek peek,
//       void Function()? onDismiss,        // → model.dismissMiniCart()
//       void Function()? onOpenDetail })   // → model.openDetailFromMiniCart()
//
//     Floating peek (`LBPMiniCart`) — reads `name` / `priceShow` / `soldOut`. The
//     container draws it ONLY when `peek != null` (a non-null peek is passed here).
//
//   NotifyRestockSheet({
//       required ReferenceUITheme theme,
//       required LBProductDetailState detail, required bool noticeEnabled,
//       void Function()? onToggleNotice })   // → model.toggleNotice(productId)
//
//     `LBPBottomSheet` shell; 縮圖 placeholder + 名 +「已售完」+ DISABLED qty stepper
//     + bottom「通知我補貨」custom pill switch (reads `noticeEnabled`; NOT a Material
//     `Switch`). FAMILY BOUNDARY: touches goods-tracking ONLY for the NOTICE
//     subscription — MUST NOT render the AWAIT switch (that is the product-detail
//     收藏鈕) or the notice-TAB open-state (family-6 gap-surfaces).
// ─────────────────────────────────────────────────────────────────────────────

// MARK: - sheetKindFor — pure sheet selection by entry (rb-flutter-soldout-row-detail-vs-restock)
//
// Which sheet a detail snapshot presents is decided by the ENTRY the user tapped (`_actionMode`),
// NOT by `soldOut` (iOS/Android parity `sheetKind(for:)` / `sheetKindFor`): 補貨鈴鐺 (restock) →
// restock-notify sheet, 加購鈕 (addToCart) → compact AddToCart, 名稱 / 明細 (detail) → full detail
// sheet. A sold-out product opened via 名稱 / 明細 thus lands on the detail sheet (which自帶 disabled
// CTA + 已售完); the restock sheet is reachable ONLY from the sold-out row's dedicated bell. Pure +
// unit-testable.

/// The three product sheets selectable by [ProductSheetPresentation].
enum ProductSheetKind { detail, addToCart, notifyRestock }

/// Map the tapped entry ([ProductSheetPresentation]) to the sheet to present. Pure.
ProductSheetKind sheetKindFor(ProductSheetPresentation mode) {
  switch (mode) {
    case ProductSheetPresentation.restock:
      return ProductSheetKind.notifyRestock;
    case ProductSheetPresentation.addToCart:
      return ProductSheetKind.addToCart;
    case ProductSheetPresentation.detail:
      return ProductSheetKind.detail;
  }
}

/// The family-3 product-sheets container. Binds the relevant template
/// `ChangeNotifier`s (`productOverlay` + `cartCTA` + `productSheet` + `variantPicker`
/// + `qtyStepper` + `miniCart` + `goodsTracking`) with `ListenableBuilder`, re-reads
/// the read-only [ProductSheetsModel] on each notify, and passes snapshot values BY
/// VALUE to the four surface widgets. Paints with the resolved [ReferenceUITheme].
///
/// `template == null` → the container uses the deterministic [ProductSheetsSeeds] (no
/// listenables to bind); the host normally supplies a live [DefaultPlayerTemplate].
class ProductSheetsOverlayView extends StatefulWidget {
  /// Live template (host-supplied). `null` → deterministic demo seeds.
  final DefaultPlayerTemplate? template;

  /// Resolved reference-ui theme.
  final ReferenceUITheme theme;

  /// `false` (snapshot / demo) → sheet thumbnails draw deterministic placeholders only
  /// (goldens unchanged). `true` (host runtime, real video surface) → product photos
  /// load over the placeholders via a gated `Image.network` (rb-product-real-images).
  /// Threaded to the list + the three sheet surfaces. Default `false`.
  final bool live;

  /// MERCHANT capability gate for the product sheet's「只剩庫存 N 組」caption
  /// (rb-flutter-show-stock-caption-toggle). RAW `sdkConfig.extensions['show_stock']` wire
  /// value, forwarded VERBATIM to [ProductDetailSheet] — this container does NOT normalize
  /// it and does NOT read `sdkConfig` itself (`extensions` is an opaque raw bag; reading it
  /// is the host's job). `null` (default) = "the backend sent nothing" → caption shown, so
  /// existing call sites and goldens are unchanged.
  ///
  /// Deliberately NOT forwarded to `NotifyRestockSheet` — see [_buildDetailOrRestockSheet].
  final Object? showStock;

  /// Whether the product-detail sheet's INLINE 收藏鈕 row is drawn at all
  /// (rb-flutter-subscribe-favorite-visibility-toggle, parity iOS / Android / RN).
  /// Forwarded VERBATIM to [ProductDetailSheet.showsFavorite] — this container does not
  /// interpret it. Default `true` (this WIDGET's own default — existing call sites
  /// unaffected); the turnkey container (`LivebuyPlayer`) flips it off by default via
  /// `LivebuyPlayerConfig.showFavorite`.
  final bool showFavorite;

  // Host-wired interaction callbacks. The container owns NO core action — each is
  // forwarded to the host (which wires it to the template / core exit). All optional.

  /// Host-wired product-row tap (host → core `LivebuyPlayer.simulateProductTap`).
  /// reference-ui NEVER opens the detail itself — the open is the host's / core's job.
  final void Function(LBProduct product)? onProductTap;

  /// Host-wired 分享 tap from the product-detail footer's 3-slot [收藏][分享][CTA].
  /// Share is a HOST CONCERN — the headless SDK has no share route, so the container
  /// forwards the intent to this host-provided callback (passthrough). Optional.
  final VoidCallback? onShare;

  /// Host-wired 商品列表列**縮圖**點擊 → 影片跳轉到該商品介紹時間（`LBProduct.beginTime`）。
  /// 轉發給 `ProductListSheet.onSeekToIntro`；host 接到 core `seek(beginTime)`（issue 5）。Optional.
  final void Function(LBProduct product)? onSeekToProductIntro;

  /// Host-wired 商品列表列**分享鈕**點擊 → 系統分享，連結帶該商品介紹時間 `?t=beginTime`。
  /// 轉發給 `ProductListSheet.onShareProduct`；與明細 footer 的 `onShare` 為不同入口（issue 6）。Optional.
  final void Function(LBProduct product)? onShareProduct;

  /// Whether the product LIST drawer is open. Container-owned single source (default `false`);
  /// the GOODS rail/bag tap opens it, the scrim / close button dismisses it (re-openable).
  /// Parity with iOS `ProductSheetsModel.listPresented` (default false) — no auto-present.
  final bool presented;

  /// Dismiss the product LIST drawer (scrim tap / close button).
  final VoidCallback? onDismissList;

  /// Host-wired「前往登入」for the add-to-cart needs-login gate (cart-needs-login-gate). When the
  /// template's `addToCartNeedsLogin` flips true (route-B add hit the empty-`buy_no` 401), the
  /// container presents `AuthGateModalView(cartAdd)`; its 前往登入 CTA routes HERE — the HOST's own
  /// login flow (`config.onLogin`). reference-ui NEVER logs in itself (same invariant as the comment
  /// login-gate). Optional (the gate defaults not-presented → goldens unchanged).
  final VoidCallback? onRequestLogin;

  /// Host-wired「更多商品」推薦卡播放圖示 tap → 換片 (rb-flutter-recommendation-nav-simplify,
  /// reversing rb-flutter-product-detail-recommendations §4/design.md D3). Carries the
  /// recommendation's `videoId` (already non-null — the sheet hides the button
  /// entirely for a null one). `null` (default) → no-op (demo / golden instances);
  /// the production container (`LivebuyPlayer`) wires this to the SAME `_switchVideo`
  /// default `onPickHot` uses (load + track + notify — `LivebuyPlayer.swift:102`-style
  /// parity). Unlike the prior design, the container ALSO closes the WHOLE sheet stack
  /// right after forwarding this call (see `_handlePlayRecommendation`) — switching
  /// video via a recommendation card is now a "switch AND leave the sheet(s)" gesture,
  /// not a "switch in the background, stay put" one. "Whole stack" means BOTH the
  /// product-detail sheet (`_handleDismissDetail`) AND, if it happens to be open too,
  /// the outer product list/bag drawer (`widget.onDismissList`,
  /// rb-flutter-recommendation-close-bag-sheet-on-switch) — a plain
  /// `_handleDismissDetail()` call only closes the former, leaving the latter's scrim
  /// stranded over the video.
  final ValueChanged<String>? onSwitchRecommendationVideo;

  const ProductSheetsOverlayView({
    super.key,
    this.template,
    required this.theme,
    this.live = false,
    this.showStock,
    this.showFavorite = true,
    this.onProductTap,
    this.onShare,
    this.onSeekToProductIntro,
    this.onShareProduct,
    this.presented = false,
    this.onDismissList,
    this.onRequestLogin,
    this.onSwitchRecommendationVideo,
  });

  @override
  State<ProductSheetsOverlayView> createState() =>
      _ProductSheetsOverlayViewState();
}

class _ProductSheetsOverlayViewState extends State<ProductSheetsOverlayView> {
  /// FALLBACK cache for `ProductSheetsModel.briefFor` / `.descriptionFor`
  /// (rb-flutter-recommendation-product-intro-carry-through) — a persistent,
  /// `productId`-keyed cache of「更多商品」推薦卡 items, written by
  /// [_handleOpenRecommendation] / [_handleQuickAddRecommendation] at the moment a
  /// recommendation card is tapped (before forwarding through `onProductTap`). This
  /// `State` object is itself the container's one persistent instance for the whole
  /// mount lifetime (unlike a value-type view), so a plain field here already gives
  /// the "write once, every later read sees it" guarantee — no need to move this
  /// cache onto `ProductSheetsModel` (see design.md's Decision for the full
  /// rationale). Never cleared for the lifetime of this `State` (bounded by
  /// realistic distinct-recommendation-taps-per-session, an accepted trade-off —
  /// mirrors iOS `ProductSheetsModel.recommendationResolvedProducts`).
  final Map<String, LBProductRecommendation> _recommendationFallbackCache = {};

  /// Read-only snapshot bridge (re-read inside the ListenableBuilder on notify).
  late ProductSheetsModel _model = ProductSheetsModel(
    template: widget.template,
    recommendationFallbackCache: _recommendationFallbackCache,
  );

  /// Which presentation the next non-sold-out detail uses (rb-align-flutter-product-action-sheet,
  /// iOS parity): the list 加購鈕 (`onQuickAdd`) sets `.addToCart` (compact purchase sheet); the
  /// 明細鈕 / 商品名 (`onOpenProduct`) sets `.detail` (full browse). A LOCAL presentation choice
  /// only — the detail DATA still loads via the host-wired `onProductTap` (→ core
  /// `simulateProductTap`); `soldOut == 1` overrides this and always shows the restock sheet.
  ProductSheetPresentation _actionMode = ProductSheetPresentation.detail;

  /// The product whose image is currently zoomed in the full-frame [ProductImageZoomOverlay],
  /// if any (rb-flutter-product-image-zoom-lightbox). A LOCAL presentation-only affordance (NOT
  /// view-model): a sheet's zoom badge sets it, the lightbox close clears it. Mounted as the LAST
  /// `Stack` child so the viewer covers the open sheet. iOS parity (`zoomedDetail`).
  LBProductDetailState? _zoomedDetail;

  /// The photo URL the lightbox should OVERRIDE with, if any (rb-flutter-product-detail-image-
  /// gallery). Set alongside [_zoomedDetail] by whichever sheet's zoom badge fired:
  /// `ProductDetailSheet`'s `.detail` gallery badge passes its CURRENTLY SELECTED photo;
  /// `NotifyRestockSheet`'s badge (no gallery concept) always passes `null`. Forwarded verbatim
  /// to `ProductImageZoomOverlay.overridePhotoURL` — `null` → the lightbox falls back to its
  /// existing `resolveProductPhoto` resolution, unchanged from before this field existed.
  String? _zoomedPhotoOverride;

  /// Dismiss latch for the add-to-cart needs-login gate (cart-needs-login-gate). Set true when the
  /// user taps 稍後再說 / 前往登入; re-armed (false) on each new add attempt so a fresh 401 re-presents
  /// the gate even though reference-ui cannot reset the template flag. Default false → the gate
  /// shows whenever `model.addToCartNeedsLogin` is true and not dismissed (the genuine-failure
  /// banner is unaffected — it draws on the orthogonal `addToCartFailed`).
  bool _cartGateDismissed = false;

  /// Dismiss latch for the「請選規格」prompt (flutter-variant-prompt-overlay-fix, iOS/Android/RN
  /// parity). Set true when the user taps 我知道了 / scrim; re-armed (false) on each new add attempt
  /// in [_handleAddToCart] so a fresh 未選規格加購 re-presents the prompt even though reference-ui
  /// cannot reset the read-only template flag `needsVariantSelection`. Default false → the prompt
  /// shows whenever `model.needsVariantSelection` is true and not locally dismissed. MIRRORS
  /// [_cartGateDismissed] exactly (the established Flutter gate idiom). HOISTED to the overlay root
  /// (NOT the sheet card) so its full-bleed scrim can't break the sheet's layout (the old 跑版 / 死鎖).
  bool _variantPromptDismissed = false;

  // 加購成功提示 toast (rb-flutter-cart-add-success-toast, parity iOS/Android/RN) — flashed ~1.8s
  // on a `cartCTA.count` RISE (success → the template increments it). The watermark `_lastCartCount`
  // is seeded in `initState` (and re-seeded when the template changes) so the bind-time / demo-seed
  // value does NOT flash; only a STRICT increase past it does. dedup / needsLogin / failure leave
  // the count unchanged → no toast (D-1 known limitation). The rise is detected by a DEDICATED
  // listener on `template.cartCTA` (build-safe — `_buildContent` runs inside `ListenableBuilder`'s
  // builder, where `setState` is illegal). A rapid second success cancels the pending dismiss timer
  // and re-arms (extends the toast, parity iOS cancel+re-arm).
  bool _cartToastVisible = false;
  int _lastCartCount = -1;
  Timer? _cartToastTimer;

  // 加購 CTA 請求中 loading (rb-flutter-cart-add-loading-state, parity iOS/Android/RN) — Flutter
  // template 非 ChangeNotifier，`addToCartInFlight` 為純欄位、無自身通知，故 in-flight 呈現由
  // 容器驅動：`_handleAddToCart` 以「同步前綴讀 model.addToCartInFlight → 顯示 → await → 320ms
  // floor 後解除」derive 防閃爍 `_cartLoadingVisible`，傳入 `ProductDetailSheet` 的加購 CTA。
  // demo / unbound（addToCartInFlight 恆 false）→ 不顯示，既有 golden byte-identical。
  bool _cartLoadingVisible = false;
  DateTime? _cartLoadingShownAt;
  Timer? _cartLoadingTimer;

  @override
  void initState() {
    super.initState();
    _lastCartCount = _model.cartCount;
    widget.template?.cartCTA.addListener(_onCartCTAChanged);
  }

  /// Re-read `cartCount` off the model and flash the toast on a STRICT rise past the seeded
  /// watermark. Runs OUTSIDE build (a ChangeNotifier callback), so `setState` is safe.
  void _onCartCTAChanged() {
    final c = _model.cartCount;
    final last = _lastCartCount;
    _lastCartCount = c;
    if (last < 0 || c <= last) return; // first pass / non-rise (dedup / clear) → no toast.
    _cartToastTimer?.cancel();
    setState(() => _cartToastVisible = true);
    _cartToastTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _cartToastVisible = false);
    });
  }

  @override
  void didUpdateWidget(covariant ProductSheetsOverlayView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.template != widget.template) {
      oldWidget.template?.cartCTA.removeListener(_onCartCTAChanged);
      _model = ProductSheetsModel(
        template: widget.template,
        // Same Map instance across a template swap — cache contents (from prior
        // recommendation taps) are NOT lost when `_model` is reconstructed
        // (rb-flutter-recommendation-product-intro-carry-through).
        recommendationFallbackCache: _recommendationFallbackCache,
      );
      _lastCartCount = _model.cartCount; // re-seed so the new template's count does not flash.
      widget.template?.cartCTA.addListener(_onCartCTAChanged);
    }
  }

  @override
  void dispose() {
    _cartToastTimer?.cancel();
    _cartLoadingTimer?.cancel();
    widget.template?.cartCTA.removeListener(_onCartCTAChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.template;

    // Bind the relevant template ChangeNotifiers so a change re-reads the model.
    // With no live template (demo seeds) there is nothing to listen to — render the
    // seeds directly.
    final mergeable = <Listenable>[
      if (t != null) ...[
        t.productOverlay,
        t.cartCTA,
        t.productSheet,
        t.variantPicker,
        t.qtyStepper,
        t.miniCart,
        t.goodsTracking,
      ],
    ];

    Widget content = _buildContent(context);
    if (mergeable.isNotEmpty) {
      content = ListenableBuilder(
        listenable: Listenable.merge(mergeable),
        builder: (context, _) => _buildContent(context),
      );
    }
    return content;
  }

  Widget _buildContent(BuildContext context) {
    final theme = widget.theme;
    final m = _model;
    final detail = m.detail;

    return Stack(
      children: [
        // Surface 1 — product list drawer (GATED): a dim scrim (tap → dismiss) + the bottom-anchored
        // drawer. Container-driven (default closed; the GOODS rail/bag tap opens it) — parity iOS
        // `ProductSheetsModel.listPresented`, so it no longer auto-presents over the video.
        if (widget.presented) ...[
          Positioned.fill(
            child: GestureDetector(
              onTap: () => widget.onDismissList?.call(),
              child: const ColoredBox(color: Color(0x73000000)),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: ProductListSheet(
              theme: theme,
              products: m.products,
              cartCount: m.cartCount,
              live: widget.live,
              // LIVE narrate_status==2 introducing products (ALL, not just the first — the
              // backend can flag multiple simultaneously) → 介紹中 banner + hide play on every
              // matching row (products are introducing-first; row MUST NOT re-sort).
              // flutter-product-bag-multi-narrating: was `introducingProductId:
              // m.introducingProductId` (single value, core's "first" convenience) — now the
              // FULL set via the mirrored view-model aggregate `liveActiveProducts`.
              introducingProductIds:
                  Set<String>.of(m.liveActiveProducts.map((p) => p.id)),
              // 縮圖疊層三模式（product-row-status-overlay）：rowMode 為 null（demo model）→
              // ProductListSheet 回退 `live` 派生（golden byte-identical）；live-bound model 供應
              // 真實 mode + 播放秒數。
              mode: m.rowMode,
              playbackPosition: m.position.floor(),
              onOpenProduct: _handleOpenProduct,
              onQuickAdd: _handleQuickAdd,
              onNotifyRestock: _handleNotifyRestock,
              // 列縮圖 → 影片跳轉到商品介紹時間（issue 5）；列分享鈕 → 系統分享帶 ?t=beginTime（issue 6）。
              onSeekToIntro: widget.onSeekToProductIntro,
              onShareProduct: widget.onShareProduct,
              onOpenCart: _handleOpenCart,
              onClose: widget.onDismissList,
            ),
          ),
        ],

        // Surface 3 — floating mini-cart peek REMOVED (rb-flutter-remove-minicart-peek-surface,
        // parity iOS e87e3e0 / Android 2918664 / RN dbc1378): the floating peek looked identical
        // to the VOD now-introducing card (same MiniCartPeek widget) and duplicated the「current
        // product」(VOD → now-introducing carousel / LIVE → pinned card); recent-add confirmation
        // is the bag-button badge. The MiniCartPeek widget is retained (the now-introducing
        // carousel still renders it); `m.miniCartPeek` / `ProductSheetsSeeds.miniCart` stay vestigial.

        // Surface 2 / 4 — the detail-or-restock sheet, presented when a detail is
        // open. A SOLD-OUT detail (`soldOut == 1`) presents the restock-notify sheet;
        // otherwise the product detail sheet (variant / qty / 加購 / 收藏鈕). Presented via
        // the shared [BottomSheetPresenter] (iOS `.lbBottomSheet` parity): a full-bleed dim
        // scrim BLOCKS the host content below + dismisses on a background tap, and the card
        // slides up on present / down on dismiss (the presenter keeps the outgoing card
        // rendered so the dismiss slide has content).
        Positioned.fill(
          child: BottomSheetPresenter(
            open: detail != null,
            sheetKey: const ValueKey('detail-open'),
            onDismiss: _handleDismissDetail,
            child: detail == null
                ? null
                : _buildDetailOrRestockSheet(theme, m, detail),
          ),
        ),

        // Product-image lightbox — the LAST Stack child so it layers ABOVE the
        // BottomSheetPresenter (covers the open sheet), mirroring the design's
        // ProductZoomOverlay mounted at the player root. Present only while a sheet's
        // zoom badge has set `_zoomedDetail`.
        if (_zoomedDetail != null)
          Positioned.fill(
            child: ProductImageZoomOverlay(
              theme: theme,
              detail: _zoomedDetail!,
              // 已選規格 → 放大圖與 sheet 主圖用**同一份**來源解析
              // （flutter-product-sheet-spec-photo-reference-ui, parity iOS
              // `ProductSheetsOverlayView` 傳 `model.variant.selectedSpec`）。若燈箱自己再推導一次
              // 退化階梯，兩份推導一分歧就會出現「主圖規格圖、燈箱商品圖」。無條件傳入（含由到貨通知
              // sheet 的 zoom badge 開啟時），與 iOS lead 行為一致。
              selectedSpec: m.selectedSpec,
              // 相簿目前選中圖 override（rb-flutter-product-detail-image-gallery）——非空時優先於
              // 上一行 `resolveProductPhoto` 的解析結果，讓燈箱顯示與開啟它的相簿同一頁。
              // `NotifyRestockSheet`（無相簿概念）恆灌 `null`，行為與本 change 之前不變。
              overridePhotoURL: _zoomedPhotoOverride,
              live: widget.live,
              onClose: () => setState(() {
                _zoomedDetail = null;
                _zoomedPhotoOverride = null;
              }),
            ),
          ),

        // 加購「需登入」gate (cart-needs-login-gate) — the LAST Stack child (topmost). REUSES the
        // comment login-gate's AuthGateModalView surface (no new pixel surface); the modal owns its
        // own scrim. Shown while needs-login is set and not locally dismissed; the genuine-failure
        // banner is unaffected (orthogonal flag). 前往登入 → host onRequestLogin (reference-ui NEVER
        // logs in itself); 稍後再說 / scrim → dismiss. `isLoggedIn: false` — needs-login fires for a guest.
        if (m.addToCartNeedsLogin && !_cartGateDismissed)
          Positioned.fill(
            child: AuthGateModalView(
              theme: theme,
              gate: const LBAuthGateState(
                  triggerAction: LBAuthTriggerAction.cartAdd),
              isLoggedIn: false,
              // Optional-preserving (lbForwardLogin): null onRequestLogin → null → 前往登入 hidden
              // (dismiss still via 稍後再說 / scrim). dropin-hide-unwired-affordances-flutter.
              onLogin: lbForwardLogin(
                widget.onRequestLogin,
                () => setState(() => _cartGateDismissed = true),
              ),
              onDismiss: () => setState(() => _cartGateDismissed = true),
            ),
          ),

        // 「請選規格」prompt — topmost Stack child, same layer as the cart-needs-login gate. A
        // centered LBPAlertModal over its own full-bleed scrim; 我知道了 / scrim → dismiss latch so
        // the variant chips become reachable. Hoisted here (flutter-variant-prompt-overlay-fix) — it
        // used to be nested in `ProductDetailSheet` as a Positioned.fill and broke the sheet layout
        // (跑版 / 死鎖). Mirrors the cart-gate's `liveFlag && !dismissed` latch idiom.
        if (m.needsVariantSelection && !_variantPromptDismissed)
          Positioned.fill(
            child: SelectVariantPromptModalView(
              theme: theme,
              onDismiss: () => setState(() => _variantPromptDismissed = true),
            ),
          ),

        // 加購成功提示 toast — the LAST Stack child (topmost), bottom-centered over the player
        // frame. Wrapped in IgnorePointer so it never eats taps (iOS `allowsHitTesting(false)`
        // parity); the下層 sheet / 手勢 stays interactive. Default-hidden (not in the Stack) →
        // goldens byte-identical. Flashed on a `cartCTA.count` rise, auto-dismissed ~1.8s later.
        if (_cartToastVisible)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 96),
              child: IgnorePointer(child: CartToastView(theme: theme)),
            ),
          ),
      ],
    );
  }

  /// Pick the sheet for `detail` by ENTRY (`_actionMode`) via the pure [sheetKindFor]
  /// (rb-flutter-soldout-row-detail-vs-restock): 補貨鈴鐺 (restock) → `NotifyRestockSheet`;
  /// 加購鈕 / 名稱 / 明細 → `ProductDetailSheet` (addToCart vs detail presentation). The prior
  /// `soldOut == 1` first-priority override is REMOVED — sold-out 名稱/明細 now open the detail
  /// sheet (disabled CTA + 已售完). The model resolves `goodsGpn` from its `products` snapshot
  /// (D-5) — `LBProductDetailState` carries only `productId`, `goodsTracking` keyed by `goodsGpn`.
  Widget _buildDetailOrRestockSheet(
    ReferenceUITheme theme,
    ProductSheetsModel m,
    LBProductDetailState detail,
  ) {
    if (sheetKindFor(_actionMode) == ProductSheetKind.notifyRestock) {
      // NO `showStock:` here — DELIBERATE, and the same decision on all four platforms
      // (rb-flutter-show-stock-caption-toggle). The restock sheet's「尚無庫存」is a
      // SOLD-OUT STATUS line, not the stock NUMBER the merchant gate governs, so this
      // branch must stay inert under `extensions.show_stock`. Do NOT "fix" this as a
      // missed hand-off, and do NOT add the flag to `NotifyRestockSheet`'s parameters.
      return NotifyRestockSheet(
        theme: theme,
        detail: detail,
        noticeEnabled: m.noticeEnabled(detail.productId),
        live: widget.live,
        onToggleNotice: () => _handleToggleNotice(detail.productId),
        onDismiss: _handleDismissDetail,
        // No gallery concept here — always clear any override (rb-flutter-product-detail-image-gallery).
        onZoomImage: () => setState(() {
          _zoomedDetail = detail;
          _zoomedPhotoOverride = null;
        }),
      );
    }
    return ProductDetailSheet(
      theme: theme,
      detail: detail,
      variantGroups: m.variantGroups,
      variantSelection: m.variantSelection,
      // 已選規格 → 價格線同源解析（flutter-product-sheet-spec-price-reference-ui, parity iOS）：
      // sheet 的售價 / 刪除線原價整對跟隨 `DefaultVariantPicker.selectedSpec`，未選完 / 無解
      // （null）則整對退回商品層。庫存線早已吃這條資料，價格線在此補齊。
      selectedSpec: m.selectedSpec,
      qty: m.qty,
      needsVariantSelection: m.needsVariantSelection,
      addToCartFailed: m.addToCartFailed,
      // 加購請求中 loading（rb-flutter-cart-add-loading-state）— 容器 derive 的防閃爍 visible。
      addToCartInFlight: _cartLoadingVisible,
      // 收藏（到貨追蹤 type=1）— model resolves goodsGpn from productId.
      faved: m.favEnabled(detail.productId),
      // The local presentation choice set by which list entry was tapped
      // (加購鈕 → .addToCart compact purchase; 明細鈕 / 商品名 → .detail full browse).
      presentation: _actionMode,
      live: widget.live,
      // 進行中直播隱藏分享鈕（rb-flutter-live-hide-product-share, design R12, parity iOS
      // `ProductSheetsOverlayView` passing `isLive: model.isLive`). Already-republished
      // strict live signal — no new state.
      isLive: m.isLive,
      // 商品說明（brief）由 products 快照以 productId 解析（問題 4，rb-flutter-product-sheet-detail-polish）。
      brief: m.briefFor(detail.productId),
      // 商品介紹（description）同一模式由 products 快照以 productId 解析
      // （rb-flutter-product-intro-real-data）。與上一行的 brief 是完全獨立的兩個欄位。
      description: m.descriptionFor(detail.productId),
      // Raw hand-off — the sheet owns the single fallback (`normalizeShowStock`).
      // THE ONLY production construction point of `ProductDetailSheet`, and it serves BOTH
      // presentations (`detail` + `addToCart`) via the `presentation: _actionMode` argument
      // above, so this one line gates both. Dropping it silently disables the merchant
      // setting on both sheets at once (rb-flutter-show-stock-caption-toggle).
      showStock: widget.showStock,
      // 商品介紹（rb-flutter-product-detail-recommendations §2）— production ALWAYS shows it;
      // the widget's own `false` default only protects PRE-EXISTING golden/widget-test call
      // sites that construct `ProductDetailSheet` directly (see that flag's doc).
      showsProductIntro: true,
      // rb-flutter-recommendation-nav-simplify — the container no longer tracks any
      // "nested detail" depth (the `_detailBreadcrumb` mechanism is gone), so the guard that
      // used to hide a drill-in detail's own「更多商品」section no longer has anything to key
      // off of. Every detail — first tap or reached via a recommendation card swap — is the
      // SAME flat single-slot sheet, so its own recommendations (if any) SHALL always show,
      // same as `showsProductIntro` two lines above.
      showsRecommendations: true,
      // 收藏鈕顯示/隱藏（rb-flutter-subscribe-favorite-visibility-toggle）— raw hand-off,
      // this container does not interpret it (parity `showStock` above).
      showsFavorite: widget.showFavorite,
      onSelectVariant: _handleSelectVariant,
      onSetQty: _handleSetQty,
      onInc: _handleInc,
      onDec: _handleDec,
      onAddToCart: _handleAddToCart,
      onToggleFavorite: () => _handleToggleFavorite(detail.productId),
      // 分享 is a host concern — forward the container's host passthrough.
      onShare: widget.onShare,
      // 更多商品推薦格 (rb-flutter-recommendation-nav-simplify): play icon → 換片 THEN close the
      // whole sheet (`_handlePlayRecommendation`); card body / quick-add → SWAP the same slot
      // via `onProductTap`, no breadcrumb recorded (`_handleOpenRecommendation` /
      // `_handleQuickAddRecommendation`).
      onPlayRecommendation: _handlePlayRecommendation,
      onOpenRecommendation: _handleOpenRecommendation,
      onQuickAddRecommendation: _handleQuickAddRecommendation,
      // Header close glyph is ALWAYS the real dismiss now (rb-flutter-recommendation-nav-simplify
      // removed the「返回」breadcrumb affordance) — `showBackButton` omitted (widget default
      // `false`), `onDismiss` always `_handleDismissDetail`.
      onDismiss: _handleDismissDetail,
      // 帶入相簿目前選中圖的 URL（可能為 null，rb-flutter-product-detail-image-gallery）——
      // `.addToCart` 精簡卡的 badge 恆傳 null，`.detail` 相簿的 badge 傳目前選中頁。
      onZoomImage: (photoUrl) => setState(() {
        _zoomedDetail = detail;
        _zoomedPhotoOverride = photoUrl;
      }),
    );
  }

  // -- Interaction funnels (container owns NO core action) --------------------

  /// Forward a 明細鈕 / 商品名 tap → FULL browse sheet. reference-ui NEVER opens the detail
  /// itself — set the LOCAL presentation mode, then forward to the host-wired core
  /// product-tap exit (`onProductTap` → core `LivebuyPlayer.simulateProductTap`).
  void _handleOpenProduct(LBProduct product) {
    _actionMode = ProductSheetPresentation.detail;
    widget.onProductTap?.call(product);
  }

  /// Forward a 加購鈕 (in-stock cart glyph) tap → COMPACT AddToCart sheet. Same host-wired
  /// core product-tap exit as `_handleOpenProduct`; only the LOCAL presentation mode differs.
  void _handleQuickAdd(LBProduct product) {
    _actionMode = ProductSheetPresentation.addToCart;
    widget.onProductTap?.call(product);
  }

  /// Forward a 售完列補貨鈴鐺 tap → restock sheet (rb-flutter-soldout-row-detail-vs-restock，問題 2).
  /// Sets the LOCAL `.restock` presentation (so `sheetKindFor` picks NotifyRestock), then forwards
  /// the host-wired core product-tap exit. 名稱 / 明細 keep `.detail`; no longer soldOut-overridden.
  void _handleNotifyRestock(LBProduct product) {
    _actionMode = ProductSheetPresentation.restock;
    widget.onProductTap?.call(product);
  }

  /// A sheet dismiss → clear the template's `productSheet.detail` (so a re-tap of the
  /// SAME product re-opens it — `openDetail` is diff-then-notify) AND reset the local
  /// presentation mode back to `.detail`. Mirrors the iOS container's `dismissDetail()`.
  ///
  /// The ONE path that TRULY closes the whole sheet stack — reached from the header's
  /// close glyph (always, `rb-flutter-recommendation-nav-simplify` removed the old
  /// breadcrumb-gated「返回」branch), the scrim tap / drag-to-dismiss, AND now also from
  /// [_handlePlayRecommendation] (switching video via a recommendation card closes the
  /// sheet too, see its doc).
  void _handleDismissDetail() {
    _actionMode = ProductSheetPresentation.detail;
    _model.closeDetail();
  }

  // -- 更多商品推薦格 (rb-flutter-recommendation-nav-simplify) --

  /// 推薦卡**卡片本體** tap → SAME-SHEET SWAP, no nested/「返回」state recorded. Sets
  /// `.detail`, then reuses the EXACT SAME `onProductTap` path a plain product-list tap
  /// uses — `item.asDisplayProduct` (see `product_row.dart`) SWAPS the single
  /// `detail`/`variant`/`qty` slot, it does NOT open a second sheet and does NOT push
  /// anything onto any kind of history/breadcrumb (that mechanism was removed —
  /// rb-flutter-recommendation-nav-simplify, reversing the prior
  /// rb-flutter-product-detail-recommendations §5/design.md D1 decision). The sheet
  /// header stays the plain「✕ 關閉」affordance no matter how many times this fires.
  void _handleOpenRecommendation(LBProductRecommendation item) {
    _actionMode = ProductSheetPresentation.detail;
    // rb-flutter-recommendation-product-intro-carry-through: cache the tapped
    // recommendation (by productId) BEFORE forwarding, so ProductSheetsModel.briefFor
    // / .descriptionFor can fall back to it if this product turns out to not be in
    // the current video's own `products` snapshot.
    _recommendationFallbackCache[item.productId] = item;
    widget.onProductTap?.call(item.asDisplayProduct);
  }

  /// 推薦卡**加購鈕** tap → SAME-SHEET SWAP into the compact AddToCart presentation. Same
  /// swap as [_handleOpenRecommendation]; only the LOCAL presentation mode differs
  /// (mirrors [_handleQuickAdd]'s relationship to [_handleOpenProduct]).
  void _handleQuickAddRecommendation(LBProductRecommendation item) {
    _actionMode = ProductSheetPresentation.addToCart;
    // rb-flutter-recommendation-product-intro-carry-through: same cache-before-forward
    // as _handleOpenRecommendation (see its doc).
    _recommendationFallbackCache[item.productId] = item;
    widget.onProductTap?.call(item.asDisplayProduct);
  }

  /// 推薦卡**播放圖示** tap → 換片，然後關閉整個 sheet stack —— 商品明細 sheet **與**外層
  /// 商品清單/商品袋 sheet（若當時開啟）都要關 (rb-flutter-recommendation-nav-simplify,
  /// reversing the prior rb-flutter-product-detail-recommendations §4/design.md D3
  /// "stays open" decision; extended by rb-flutter-recommendation-close-bag-sheet-on-switch
  /// to also close the outer list/bag drawer — closing only the detail sheet left that
  /// drawer's scrim stranded over the video when it had been open, e.g. list → tap a
  /// product → detail → tap a recommendation card's play icon).
  /// `videoId == null` is already filtered by `ProductDetailSheet` (the button is
  /// hidden, not wired to a no-op), so this only ever fires with a real id — that guard
  /// is unchanged: a null id triggers neither the video switch nor either dismiss below.
  /// Forwards the switch FIRST, then closes via the same [_handleDismissDetail] every
  /// other "truly close the [detail] sheet" path uses (header ✕ / scrim /
  /// drag-to-dismiss) — no separate close mechanism for the detail sheet — and FINALLY
  /// forwards to the host-wired [ProductSheetsOverlayView.onDismissList] (null-safe:
  /// a no-op if the list drawer was not open, or `onDismissList` is `null`, e.g. demo /
  /// golden call sites). [_handleDismissDetail] itself is deliberately left untouched
  /// (see design.md "Decisions") — its other call sites (header ✕ / scrim /
  /// drag-to-dismiss) are a lighter-weight "close the detail, keep browsing the list"
  /// gesture and MUST NOT start closing the list drawer too.
  void _handlePlayRecommendation(LBProductRecommendation item) {
    final videoId = item.videoId;
    if (videoId == null) return;
    widget.onSwitchRecommendationVideo?.call(videoId);
    _handleDismissDetail();
    widget.onDismissList?.call();
  }

  /// Forward a cart-CTA tap → `DefaultPlayerTemplate.openCart()` (host passthrough;
  /// no-op for demo instances via the model).
  void _handleOpenCart() {
    _model.openCart();
  }

  /// Forward a variant chip tap → `DefaultPlayerTemplate.selectVariant(gi, oi)`.
  void _handleSelectVariant(int groupIndex, int optionIndex) {
    _model.selectVariant(groupIndex, optionIndex);
  }

  /// Forward a direct qty set → `DefaultPlayerTemplate.setQty(n)`.
  void _handleSetQty(int value) {
    _model.setQty(value);
  }

  /// Forward a qty `+` tap → `DefaultPlayerTemplate.incQty()`.
  void _handleInc() {
    _model.incQty();
  }

  /// Forward a qty `-` tap → `DefaultPlayerTemplate.decQty()`.
  void _handleDec() {
    _model.decQty();
  }

  /// Forward the 加入購物車 intent → `DefaultPlayerTemplate.addToCart()` (template
  /// assembles route-B request; reference-ui NEVER calls core addToCart directly).
  ///
  /// cart-add-loading-state-flutter: template 非 ChangeNotifier、`addToCartInFlight` 為純欄位，
  /// 故 in-flight 呈現由此驅動 —— `_model.addToCart()` 的**同步前綴**（通過 guards 後同步設
  /// template inFlight true，在第一個 `await` 之前）跑完即返回 Future；此時讀 `_model.addToCartInFlight`
  /// 可判斷是否真的送出（guard 阻擋則 false → 不顯示 loading）。顯示後 `await` 結果，再以 320ms
  /// `CartLoadingFloor` 解除（防 dedup 同步回應造成 spinner strobe）。
  Future<void> _handleAddToCart() async {
    // New attempt — re-arm the needs-login gate latch so a fresh 401 re-presents it, and the
    // 「請選規格」prompt latch so a fresh 未選規格加購 re-presents it (flutter-variant-prompt-overlay-fix).
    setState(() {
      _cartGateDismissed = false;
      _variantPromptDismissed = false;
    });
    final future = _model.addToCart();
    // 同步前綴已跑完 → 真的送出請求才顯示 loading（guard 阻擋 → inFlight 仍 false）。
    if (_model.addToCartInFlight) _showCartLoading();
    if (mounted) setState(() {});
    await future;
    // 結果回來 → 套 320ms 防閃爍 floor 後解除 loading。
    _settleCartLoading();
    // Re-read the template's transient flags (failure banner / needs-login gate) after the async
    // result. They are plain fields on the template (no ChangeNotifier of their own), so an
    // explicit rebuild is required for them to surface — parity with the gate's reactive present.
    if (mounted) setState(() {});
  }

  /// 顯示加購 loading 並記下起始時間（防閃爍 floor 的基準）。cart-add-loading-state-flutter.
  void _showCartLoading() {
    _cartLoadingTimer?.cancel();
    _cartLoadingShownAt = DateTime.now();
    _cartLoadingVisible = true;
  }

  /// 結果回來時，套用 320ms 防閃爍 floor 解除 loading：elapsed ≥ floor 立即隱藏，否則延後剩餘。
  void _settleCartLoading() {
    final shownAt = _cartLoadingShownAt;
    if (shownAt == null) return; // 未曾顯示（guard 阻擋）→ 無事。
    final elapsed = DateTime.now().difference(shownAt).inMilliseconds;
    final remaining = CartLoadingFloor.remainingHoldMillis(elapsed);
    if (remaining <= 0) {
      _cartLoadingVisible = false;
      return;
    }
    _cartLoadingTimer?.cancel();
    _cartLoadingTimer = Timer(Duration(milliseconds: remaining), () {
      if (mounted) setState(() => _cartLoadingVisible = false);
    });
  }

  /// Forward a 收藏（到貨追蹤 type=1）toggle → `goodsTracking.toggleAwait(goodsGpn)`
  /// (model resolves goodsGpn from productId).
  void _handleToggleFavorite(String productId) {
    _model.toggleFavorite(productId);
  }

  /// Forward a restock-notify toggle → `goodsTracking.toggleNotice(goodsGpn)`
  /// (model resolves goodsGpn from productId; NOTICE flag only).
  void _handleToggleNotice(String productId) {
    _model.toggleNotice(productId);
  }

  // Mini-cart peek dismiss / open-detail handlers REMOVED with the floating peek surface
  // (rb-flutter-remove-minicart-peek-surface); `model.dismissMiniCart()` /
  // `openDetailFromMiniCart()` stay vestigial forwarders on the model.
}
