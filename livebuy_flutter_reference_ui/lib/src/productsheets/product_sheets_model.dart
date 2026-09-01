import 'package:livebuy_flutter/livebuy_flutter.dart'
    show LBProduct, LBSpec, LBSpecOption;

import 'product_row_overlay.dart' show ProductRowMode;
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show
        DefaultPlayerTemplate,
        LBProductDetailState,
        LBProductRecommendation,
        LBVariantGroup,
        LBQtyState,
        LBMiniCartPeek;

// ProductSheetsModel — family-3 product sheet-stack read-only snapshot bridge
// (Flutter).
//
// Spec: `reference-ui-rendering/spec.md` (family-3 product + sheets, 4 surfaces).
// Flutter sibling of iOS `ProductSheetsModel.swift` (rb-ios-product-sheets D-1..D-5
// + rb-ios-gap-surfaces-design-reconcile 收藏鈕) and Android `ProductSheetsModel.kt`
// (rb-android-product-sheets).
//
// It bridges the headless template view-models exposed by `DefaultPlayerTemplate`
// (obtained at runtime by the host; tests take `LivebuyUI.attachedTemplateForTesting`)
// into a read-only snapshot the four family-3 Flutter surface widgets read. It is a
// pure read-only MIRROR — IDENTICAL pattern to family-1 `PlayerShellModel` /
// family-2 `FeedWinModel`:
//
//   - It owns NO second copy of authoritative state. Every getter reads the
//     template's own public getter each call (`productOverlay.products` /
//     `cartCTA.count` / `productSheet.detail` / `variantPicker.{groups,selection,
//     hasGroups}` / `qtyStepper.state` / `miniCart.peek` /
//     `goodsTracking.{awaitEnabled,noticeEnabled}` / `needsVariantSelection` /
//     `addToCartFailed`), so there is nothing to drift from the template (D-1).
//   - It adds NO pixels and adds NO accessor / view-model to `livebuy_flutter_ui`
//     (that would be a template-layer concern, out of scope here).
//   - reference-ui NEVER calls core `addToCart` / `setAwaitGoods` / `setNoticeGoods`
//     directly. Mutating interactions are thin forwarders to the EXISTING public
//     template exits (`selectVariant` / `setQty` / `incQty` / `decQty` /
//     `addToCart` / `dismissMiniCart` / `openCart` / `goodsTracking.toggleNotice` /
//     `goodsTracking.toggleAwait`). The template assembles the route-B cart request
//     internally (NO HTTP in the template's view-model construction).
//   - PRODUCT-ROW TAP is NOT a template forwarder. Opening a product detail is the
//     CORE product-tap exit (`LivebuyPlayer.simulateProductTap`); the list row only
//     forwards the tap to a HOST-WIRED container callback (`onProductTap`). This
//     model carries NO row-tap forwarder (mirrors family-2 `ChatFeedView`'s eventJoin
//     host-wired exit — the open is the host's / core's job, not this layer's).
//
// Flutter observes via ChangeNotifier; the container [ProductSheetsOverlayView] binds
// the relevant `ChangeNotifier`s (`productOverlay` / `cartCTA` / `productSheet` /
// `variantPicker` / `qtyStepper` / `miniCart` / `goodsTracking`) with
// `ListenableBuilder` and RE-READS these getters on each notify — so this holder
// keeps NO Flutter state of its own (no `extends ChangeNotifier`); it just
// centralizes the read mapping + deterministic demo seeds. Mirrors the iOS / Android
// `ProductSheetsModel` intent.
//
// No Flutter-framework dependency here — pure reads + plain-literal demo seeds, so it
// stays unit-testable (see `docs/unit-test-discipline.md`).

/// Read-only snapshot bridge for the family-3 product-sheets surfaces. Wraps a live
/// [DefaultPlayerTemplate]; every accessor reads the template's public getter each
/// call (no stored mirror). For demos / previews / golden tests, construct with
/// `template: null` and the accessors return the deterministic [ProductSheetsSeeds]
/// defaults instead.
class ProductSheetsModel {
  /// The bound template, or `null` for demo / golden instances.
  final DefaultPlayerTemplate? template;

  /// FALLBACK source for [briefFor] / [descriptionFor]
  /// (rb-flutter-recommendation-product-intro-carry-through) — a container-owned,
  /// `productId`-keyed cache of「更多商品」推薦卡 (`LBProductRecommendation`) items,
  /// populated by `_ProductSheetsOverlayViewState._handleOpenRecommendation` /
  /// `_handleQuickAddRecommendation` at the moment a recommendation card is tapped.
  /// `null` for demo / golden instances (no container to populate one). Read-only
  /// here — this model never writes to it; the container owns the `Map` instance
  /// and mutates it in place, so the SAME reference is visible to every subsequent
  /// read regardless of how many times `ProductSheetsModel` itself is reconstructed
  /// (mirrors [template] itself: an external input this model reads, not owns).
  final Map<String, LBProductRecommendation>? recommendationFallbackCache;

  /// Bridge a live template (host-supplied) — or `null` for the deterministic demo
  /// seeds (previews / golden tests). [recommendationFallbackCache] is an optional
  /// container-supplied fallback source for [briefFor] / [descriptionFor].
  const ProductSheetsModel({this.template, this.recommendationFallbackCache});

  // -- Surface 1: ProductListSheet ← product list drawer + cart CTA -----------

  /// The core-fed products snapshot, INTRODUCING-FIRST
  /// (`DefaultProductOverlayState.productsIntroducingFirst`): the currently-introducing
  /// product (LIVE narrate_status==2) floated to the head, the rest in their original
  /// order. Already ordered by the data layer — this layer MUST NOT slice / merge /
  /// re-sort. Parity iOS / Android / RN. For demo instances returns
  /// [ProductSheetsSeeds.products].
  // demo seed ONLY when unbound; a BOUND template returns its real (possibly empty) list —
  // the `??` must NOT leak demo products into a real session (rb-flutter-player-demo-seed-leak).
  List<LBProduct> get products => template == null
      ? ProductSheetsSeeds.products
      : template!.productOverlay.productsIntroducingFirst;

  /// The currently-introducing product's id
  /// (`DefaultProductOverlayState.introducingProductId`, LIVE narrate_status==2), or
  /// `null` (VOD / demo / nothing introducing → no banner). Threaded to the list → rows
  /// so the matching row draws the「介紹中」banner + hides the play affordance. For demo
  /// instances returns `null` (deterministic — no banner). Parity iOS / Android / RN.
  String? get introducingProductId =>
      template?.productOverlay.introducingProductId;

  /// ALL currently-introducing products (LIVE narrate_status==2 — every match, not just the
  /// first), mirroring existing view-model `DefaultPlayerTemplate.liveActiveProducts`
  /// (`flutter-ui/lib/src/default_template.dart`, shipped by
  /// `2026-06-18-flutter-live-now-introducing-carousel`). Same read PlayerShellModel already
  /// performs for the family-1 pinned-card carousel (`PlayerShellModel.liveActiveProducts`) —
  /// this is a second, independent mirror for the family-3 product-bag list drawer, which binds
  /// its own `ProductSheetsModel` instance (the two are NOT the same model / not reachable from
  /// each other). Threaded to `ProductListSheet.introducingProductIds` so EVERY simultaneously
  /// `narrate_status == 2` product draws the「介紹中」banner, not just the single one
  /// [introducingProductId] surfaces. For demo instances (and a bound-but-empty template)
  /// returns `[]` — deterministic, matches [PlayerShellModel]'s own gating choice (no seed to
  /// leak here). Parity iOS / Android / RN `ProductSheetsModel.liveActiveProducts`
  /// (flutter-product-bag-multi-narrating).
  List<LBProduct> get liveActiveProducts =>
      template == null ? const [] : template!.liveActiveProducts;

  // -- Surface 1: ProductList ← product-row thumbnail overlay mode (product-row-status-overlay) --
  //
  // Playback-mode signals for the row thumbnail overlay. Mirrored from the template
  // `header.isLive` / `playbackProgress.isReplay` / `.position`. For demo instances
  // (`template == null`) return false / false / 0 so [rowMode] is `null` → ProductList
  // falls back to the real-frame `live` flag (goldens byte-identical). Parity iOS /
  // Android / RN `ProductSheetsModel.isLive` / `isReplay` / `position`.

  /// LIVE/VOD flag (`header.isLive`). Demo → false.
  bool get isLive => template?.header.isLive ?? false;

  /// Replay variant flag (`playbackProgress.isReplay`). Demo → false.
  bool get isReplay => template?.playbackProgress.isReplay ?? false;

  /// Current playhead seconds (`playbackProgress.position`). Demo → 0.
  double get position => template?.playbackProgress.position ?? 0;

  /// Derived playback mode for the product-row overlay (replay takes precedence over
  /// live). `null` for a demo / golden model (no bound template) → the view falls back
  /// to its real-frame `live` flag so goldens stay byte-identical. Parity iOS / Android /
  /// RN `ProductSheetsModel.rowMode`.
  ProductRowMode? get rowMode {
    if (template == null) return null;
    if (isReplay) return ProductRowMode.replay;
    if (isLive) return ProductRowMode.live;
    return ProductRowMode.vod;
  }

  /// Per-session successful-add count (`DefaultCartCTA.count`); the cart CTA shows
  /// it (the badge is drawn when `> 0`). For demo instances returns
  /// [ProductSheetsSeeds.cartCount].
  // demo seed ONLY when unbound; a BOUND template returns its real count (0 when none) —
  // the `??` must NOT leak the demo count badge into a real session (rb-flutter-player-demo-seed-leak).
  int get cartCount =>
      template == null ? ProductSheetsSeeds.cartCount : template!.cartCTA.count;

  // -- Surface 2/4: ProductDetailSheet / NotifyRestockSheet ← detail snapshot --

  /// Product-detail sheet snapshot (`DefaultProductSheet.detail`); `null` until a
  /// `diversion == 0` product-tap opens a detail. Drives whether the detail (and,
  /// when sold-out, the restock-notify) sheet is presented. For demo instances
  /// returns [ProductSheetsSeeds.detail] (the in-stock variant detail).
  // demo seed ONLY when unbound; a BOUND template with no open detail → null (no sheet) —
  // the `??` must NOT leak the demo detail sheet into a real session before any product-tap
  // (rb-flutter-player-demo-seed-leak). variant / qty are read only when detail != null, so
  // gating detail alone keeps the whole detail sheet from leaking.
  LBProductDetailState? get detail =>
      template == null ? ProductSheetsSeeds.detail : template!.productSheet.detail;

  // -- Surface 2: ProductDetailSheet ← variant + qty --------------------------

  /// Variant chip groups (`DefaultVariantPicker.groups`). For demo instances
  /// returns [ProductSheetsSeeds.variantGroups].
  List<LBVariantGroup> get variantGroups =>
      template?.variantPicker.groups ?? ProductSheetsSeeds.variantGroups;

  /// Current variant selection (`DefaultVariantPicker.selection`,
  /// `groupIndex → optionIndex`; a chip is selected when `selection[gi] == oi`).
  /// For demo instances returns [ProductSheetsSeeds.variantSelection].
  Map<int, int> get variantSelection =>
      template?.variantPicker.selection ?? ProductSheetsSeeds.variantSelection;

  /// The RESOLVED variant spec for the current selection
  /// (`DefaultVariantPicker.selectedSpec` — `flutter-ui/lib/src/default_product_sheet.dart:147`,
  /// view-model layer, NOT modified by this change). `null` when the product has spec
  /// groups but the selection is still incomplete / unresolvable, and for a no-spec
  /// product. Threaded to `ProductDetailSheet` so its PRICE ROW follows the selected
  /// spec the way the stock line already does
  /// (flutter-product-sheet-spec-price-reference-ui; parity iOS `LBVariantState.selectedSpec`).
  ///
  /// DEMO INSTANCES RETURN `null` (no `??` seed fallback) — deliberately, for two reasons:
  ///   1. SEMANTICS: `selectedSpec` is not independent state, it is RESOLVED by
  ///      `DefaultVariantPicker` from `specifications` + `selection`. A demo model has no
  ///      picker, so there is nothing to resolve → `null` is the honest answer. This
  ///      matches the `detail` / `miniCartPeek` "bound-only" gating pattern.
  ///   2. GOLDEN STABILITY: `ProductSheetsSeeds._variantSpecs` carry `priceShow 'NT$380'`
  ///      (same as the seed detail) but NO `originalPriceShow` (defaults to `''`), while
  ///      the seed detail's is `'NT$480'`. Seeding a demo `selectedSpec` would therefore
  ///      CORRECTLY drop the strike-through from every existing golden — i.e. it would
  ///      change baselines. Enriching those seeds is an independent fixture decision
  ///      (recorded as an Open Question in the change's design.md) and is NOT done here.
  LBSpec? get selectedSpec => template?.variantPicker.selectedSpec;

  /// True when the product HAS spec groups (`DefaultVariantPicker.hasGroups`).
  /// For demo instances derives it from the seed groups.
  bool get hasGroups =>
      template?.variantPicker.hasGroups ??
      ProductSheetsSeeds.variantGroups.isNotEmpty;

  /// Qty-stepper snapshot (`DefaultQtyStepper.state`: `{ qty, min, max }`).
  /// Sold-out / out-of-stock → `max == 0` (stepper disabled). For demo instances
  /// returns [ProductSheetsSeeds.qty].
  LBQtyState get qty => template?.qtyStepper.state ?? ProductSheetsSeeds.qty;

  // -- Surface 2 (guard flags): add-to-cart prompts ---------------------------

  /// 「請選規格」guard flag (`DefaultPlayerTemplate.needsVariantSelection`) — set
  /// true when `addToCart()` is called with an incomplete spec selection. For demo
  /// instances false.
  bool get needsVariantSelection => template?.needsVariantSelection ?? false;

  /// Add-to-cart failure flag (`DefaultPlayerTemplate.addToCartFailed`) — set true
  /// when the route-B add threw; drives the failure banner. For demo instances false.
  bool get addToCartFailed => template?.addToCartFailed ?? false;

  /// Add-to-cart「需登入」flag (`DefaultPlayerTemplate.addToCartNeedsLogin`) — set true when
  /// the route-B add hit the core empty-`buy_no` serverError(401); drives the
  /// `AuthGateModalView(cartAdd)` login gate instead of the failure banner (orthogonal to
  /// [addToCartFailed]). For demo instances false (cart-needs-login-gate).
  bool get addToCartNeedsLogin => template?.addToCartNeedsLogin ?? false;

  /// 加購「請求中」flag (`DefaultPlayerTemplate.addToCartInFlight`, rb-flutter-cart-add-loading-state) —
  /// addcart 請求委派中為 true、各結果（success/dedupe/failure/needs-login）回 false。驅動加購 CTA
  /// loading（spinner +「加入中…」、鎖 stepper/規格）。容器以 320ms 防閃爍 floor derive 後傳入 CTA。
  /// 與 [addToCartFailed] / [addToCartNeedsLogin] 正交。For demo instances false.
  bool get addToCartInFlight => template?.addToCartInFlight ?? false;

  // -- Surface 3: MiniCartPeek ← mini-cart peek -------------------------------

  /// Mini-cart peek snapshot (`DefaultMiniCart.peek`); `null` → no floating peek.
  /// For demo instances returns [ProductSheetsSeeds.miniCartPeek].
  // demo seed ONLY when unbound; a BOUND template with no recent add → null. The `??` must
  // NOT leak the demo peek into a real session (rb-flutter-player-demo-seed-leak). Vestigial
  // after the floating peek surface was removed (rb-flutter-remove-minicart-peek-surface),
  // but kept gated.
  LBMiniCartPeek? get miniCartPeek =>
      template == null ? ProductSheetsSeeds.miniCartPeek : template!.miniCart.peek;

  // -- Goods-tracking reads (product-detail 收藏 type=1 / restock notice type=2) --

  /// Read the current 收藏（await type=1）state for a product detail —
  /// `DefaultGoodsTracking.awaitEnabled(goodsGpn)`. For demo instances returns
  /// [ProductSheetsSeeds.demoFavEnabled] (false for the variant-instock golden,
  /// true for the favorited golden — the container picks via the demo flag).
  /// Returns false when the product is not in the snapshot.
  bool favEnabled(String productId) {
    final t = template;
    if (t == null) return ProductSheetsSeeds.demoFavEnabled;
    final goodsGpn = resolveGoodsGpn(productId);
    if (goodsGpn == null) return false;
    return t.goodsTracking.awaitEnabled(goodsGpn);
  }

  /// Read the current restock-notify subscription state for a product detail —
  /// `DefaultGoodsTracking.noticeEnabled(goodsGpn)`. This is a READ of the NOTICE
  /// flag ONLY (the AWAIT flag is the 收藏 affordance, read via [favEnabled]). For
  /// demo instances returns [ProductSheetsSeeds.demoNoticeEnabled]. Returns false
  /// when the product is not in the snapshot.
  bool noticeEnabled(String productId) {
    final t = template;
    if (t == null) return ProductSheetsSeeds.demoNoticeEnabled;
    final goodsGpn = resolveGoodsGpn(productId);
    if (goodsGpn == null) return false;
    return t.goodsTracking.noticeEnabled(goodsGpn);
  }

  // -- Read-only host intents (pass-through to the bound template) ------------
  //
  // Thin forwarders for the template-owned product sheet-stack intents the family-3
  // surfaces drive. Each is a no-op for demo instances (no bound template).
  // reference-ui NEVER calls core directly — these route through the EXISTING
  // public template / model exits.

  /// Forward a variant chip tap → `DefaultPlayerTemplate.selectVariant(gi, oi)`.
  /// No-op for demo instances.
  void selectVariant(int groupIndex, int optionIndex) =>
      template?.selectVariant(groupIndex, optionIndex);

  /// Forward a direct qty set → `DefaultPlayerTemplate.setQty(n)`. No-op for demo.
  void setQty(int value) => template?.setQty(value);

  /// Forward a qty `+` tap → `DefaultPlayerTemplate.incQty()`. No-op for demo.
  void incQty() => template?.incQty();

  /// Forward a qty `-` tap → `DefaultPlayerTemplate.decQty()`. No-op for demo.
  void decQty() => template?.decQty();

  /// Forward the 加入購物車 intent → `DefaultPlayerTemplate.addToCart()` (template
  /// assembles route-B request internally; reference-ui NEVER calls core addToCart
  /// directly — NO HTTP here). Returns the delegated future so the container can await it and
  /// re-read the transient flags (failure banner / needs-login gate). No-op for demo instances.
  Future<void> addToCart() async => template?.addToCart();

  /// Forward a cart-CTA tap → `DefaultPlayerTemplate.openCart()` (host passthrough;
  /// the template owns no checkout page). No-op for demo instances.
  void openCart() => template?.openCart();

  /// Forward a sheet dismiss → `DefaultPlayerTemplate.closeProductDetail()` so the
  /// template's `productSheet.detail` returns to null (and a re-tap of the SAME
  /// product can re-open it — `openDetail` is diff-then-notify). Mirrors the iOS
  /// container's `dismissDetail()` → `model.closeDetail()` wiring
  /// (expose-close-product-detail-template). No-op for demo instances.
  void closeDetail() => template?.closeProductDetail();

  /// Forward a mini-cart dismiss → `DefaultPlayerTemplate.dismissMiniCart()`. No-op
  /// for demo instances.
  void dismissMiniCart() => template?.dismissMiniCart();

  /// Forward a mini-cart「開明細」intent. The Flutter `DefaultPlayerTemplate` does
  /// NOT (yet) expose a public `openDetailFromMiniCart()` exit (its doc references an
  /// `openMiniCartDetail` re-open that the host re-feeds the full `LBProduct` for) —
  /// unlike the iOS `DefaultMiniCart.openDetail()`. To avoid reaching past the
  /// template's public surface (and since this layer MUST NOT add a view-model), this
  /// forwarder is a best-effort no-op at the model level; the surface's `onOpenDetail`
  /// callback still flows to the host-wired container callback so a host that re-opens
  /// the detail (re-feeding the `LBProduct`) wires it there. No-op for demo instances.
  void openDetailFromMiniCart() {
    // Intentionally inert at the model layer — the Flutter template exposes no
    // public re-open exit here. The host wires the re-open via the container's
    // host callback (which re-feeds the full LBProduct).
  }

  /// Forward a restock-notify toggle → `DefaultGoodsTracking.toggleNotice(goodsGpn)`
  /// (optimistic flip of ONLY the notice flag → core `setNoticeGoods` type=2;
  /// corrected by `NOTICE_GOODS_CHANGED`). This is the ONLY goods-tracking write the
  /// restock sheet makes (the AWAIT switch is the product-detail 收藏 affordance).
  /// No-op for demo instances or when the product is not in the snapshot.
  void toggleNotice(String productId) {
    final goodsGpn = resolveGoodsGpn(productId);
    if (goodsGpn == null) return;
    template?.goodsTracking.toggleNotice(goodsGpn);
  }

  /// Forward a 收藏（到貨追蹤 type=1）toggle → `DefaultGoodsTracking.toggleAwait(goodsGpn)`
  /// (optimistic flip of ONLY the await flag → core `setAwaitGoods` type=1; corrected
  /// by `AWAIT_GOODS_CHANGED`). This is the product-detail 收藏 / 加入我的最愛 affordance
  /// (reconciled into family-3 — design 2026-06-06); the restock NOTICE toggle is
  /// independent. No-op for demo instances or when the product is not in the snapshot.
  void toggleFavorite(String productId) {
    final goodsGpn = resolveGoodsGpn(productId);
    if (goodsGpn == null) return;
    template?.goodsTracking.toggleAwait(goodsGpn);
  }

  // -- Convenience reads (surface helpers, pure) ------------------------------

  /// Resolve the goods-tracking key (`goodsGpn`) for a product detail from the
  /// `products` snapshot (D-5: 「goodsGpn 從 product 讀」). `LBProductDetailState`
  /// carries only `productId`, but `DefaultGoodsTracking` is keyed by `goodsGpn`
  /// (the template seeds it via `LBProduct.goodsGpn`), so the restock / favorite
  /// toggles MUST map productId → the originating `LBProduct.goodsGpn` rather than
  /// key off the productId directly. `null` when the product is not in the current
  /// list.
  String? resolveGoodsGpn(String productId) {
    for (final p in products) {
      if (p.id == productId) return p.goodsGpn;
    }
    return null;
  }

  /// 商品說明（`LBProduct.brief`）— PRIMARY 來源為 `products` 快照以 `productId` 解析（D-3
  /// 同模式：`LBProductDetailState` 不帶 `brief`，只有 `productId`；`brief` 在原始 `LBProduct`
  /// 上）。PRIMARY 回傳空字串時（查無此商品，或查到但 `brief` 本身就是空字串）SHALL 退回
  /// [recommendationFallbackCache]（rb-flutter-recommendation-product-intro-carry-through）——
  /// 讓一筆解析自「更多商品」推薦格（不在目前影片自己的 `products` 快照裡）的商品，仍能顯示其
  /// 真實 `brief`。快取亦無對應項目（或該項目 `brief` 為空）時一樣回 `''`，呼叫端據此 gate 不畫
  /// 說明區塊（rb-flutter-product-sheet-detail-polish 問題 4，iOS
  /// `ProductSheetsModel.brief(forProductId:)` parity）。此 FALLBACK MUST NOT 改變 PRIMARY 的
  /// 優先序——`products` 內已有的商品永遠先命中 PRIMARY。
  String briefFor(String productId) {
    for (final p in products) {
      if (p.id == productId && p.brief.isNotEmpty) return p.brief;
    }
    return recommendationFallbackCache?[productId]?.brief ?? '';
  }

  /// 商品介紹（`LBProduct.description`）— PRIMARY 來源為 `products` 快照以 `productId` 解析
  /// （同一模式：`LBProductDetailState` 不帶 `description`，只有 `productId`；`description` 在
  /// 原始 `LBProduct` 上，`add-product-description-core-flutter`）。PRIMARY 回傳空字串時（查無
  /// 此商品，或查到但 `description` 本身就是空字串）SHALL 退回 [recommendationFallbackCache]
  /// （rb-flutter-recommendation-product-intro-carry-through，與 [briefFor] 共用同一份快取）——
  /// 讓一筆解析自「更多商品」推薦格的商品仍能顯示其真實 `description`。快取亦無對應項目（或該
  /// 項目 `description` 為空）時一樣回 `''`，呼叫端據此決定顯示真實文案還是整塊隱藏
  /// （`rb-flutter-product-intro-bgcolor-and-hide-empty`，iOS `ProductSheetsModel.description(
  /// forProductId:)` / RN `descriptionForProduct(productId)` parity）。此 FALLBACK MUST NOT
  /// 改變 PRIMARY 的優先序。
  String descriptionFor(String productId) {
    for (final p in products) {
      if (p.id == productId && p.description.isNotEmpty) return p.description;
    }
    return recommendationFallbackCache?[productId]?.description ?? '';
  }
}

// MARK: - Deterministic demo seeds (previews / golden tests)

/// Plain-literal deterministic seeds for the family-3 surfaces' previews + the
/// per-surface golden / widget tests. Constructed via the public core / template
/// ctors (`LBProduct` / `LBProductDetailState` / `LBVariantGroup` / `LBQtyState` /
/// `LBMiniCartPeek`) so a snapshot does NOT depend on a live player. Mirrors the
/// iOS demo seeds (the memberwise `ProductSheetsModel` demo init values) and the
/// Android `ProductSheetsSeeds`.
///
/// The seeds are FULLY stocked so the container can drive all four golden states
/// with a single `template: null` model:
///   • [products] — the list drawer (one sold-out row) + `cartCount == 2`.
///   • [detail] / [variantGroups] / [variantSelection] / [qty] — the in-stock
///     variant detail (`product-detail-sheet-variant-instock`; favorited golden
///     re-uses the same detail with `demoFavEnabled == true`).
///   • [miniCartPeek] — the in-stock mini-cart peek (`mini-cart-peek-in-stock`).
///   • [restockDetail] — the SOLD-OUT detail for the restock-notify sheet
///     (`notify-restock-sheet-not-subscribed`, `demoNoticeEnabled == false`).
class ProductSheetsSeeds {
  ProductSheetsSeeds._();

  // -- goodsGpn constants (keep the seed products / detail self-consistent) ----

  /// goodsGpn of the in-stock variant product (detail + list row + fav/notice key).
  static const String variantGoodsGpn = 'gpn-velvet-lip-04';

  /// goodsGpn of the sold-out product (list sold-out row + restock detail key).
  static const String soldOutGoodsGpn = 'gpn-aurora-blush-soldout';

  /// productId of the in-stock variant product.
  static const String variantProductId = 'demo-prod-velvet-lip';

  /// productId of the sold-out product.
  static const String soldOutProductId = 'demo-prod-aurora-blush';

  // -- Demo goods-tracking flags (golden selectors) ---------------------------

  /// 收藏（await type=1）demo flag: the variant-instock golden reads `false`
  /// (空心 heart「收藏」); the favorited golden flips this to `true` (實心 heart +
  /// accent「已收藏」). The container's favorited demo path overrides this read.
  static const bool demoFavEnabled = false;

  /// Restock notice（type=2）demo flag: `notify-restock-sheet-not-subscribed`
  /// reads `false` (toggle off).
  static const bool demoNoticeEnabled = false;

  // -- Surface 1: product list drawer + cart CTA ------------------------------

  /// Per-session add count for the cart CTA (`product-list-drawer-populated`
  /// shows `count == 2`).
  static const int cartCount = 2;

  /// Deterministic demo products: the in-stock variant product, a second in-stock
  /// product, and a SOLD-OUT product (one `soldOut == 1` row, as the spec requires).
  /// Insertion-ordered (the list MUST NOT re-sort). Mirrors iOS / Android list seeds.
  static final List<LBProduct> products = [
    LBProduct(
      id: variantProductId,
      goodsNo: 'V-LIP-04',
      name: '絲絨霧面唇釉 #04 焦糖',
      price: 380,
      priceShow: 'NT\$380',
      originalPrice: 480,
      originalPriceShow: 'NT\$480',
      stock: 9,
      photos: const [],
      goodsGpn: variantGoodsGpn,
      // 商品說明（brief）— 不在列表渲染（只在 detail 出現），故不影響 golden；供 briefFor 解析
      // （問題 4，rb-flutter-product-sheet-detail-polish）。
      brief: '夏日通勤彩妝主打色',
      // 商品介紹（description）— 不在列表渲染（只在 detail 出現），故不影響 golden；供
      // descriptionFor 解析（rb-flutter-product-intro-real-data）。與上方 brief 是完全獨立的
      // 兩個欄位，刻意給不同文案避免測試誤把兩者混淆。
      description: '啞光質地、單次上色，日常通勤也能輕鬆駕馭的顯色唇釉。',
      soldOut: 0,
      isHot: 1,
      diversionUrl: '',
      specifications: _variantSpecs,
      specOptions: _variantSpecOptions,
    ),
    LBProduct(
      id: 'demo-prod-glow-serum',
      goodsNo: 'GLOW-SER',
      name: '亮顏精華露 30ml',
      price: 690,
      priceShow: 'NT\$690',
      originalPriceShow: '',
      stock: 5,
      photos: const [],
      goodsGpn: 'gpn-glow-serum',
      soldOut: 0,
      isHot: 0,
      diversionUrl: '',
    ),
    LBProduct(
      id: soldOutProductId,
      goodsNo: 'AURORA-BLUSH',
      name: 'Aurora 腮紅 #02 蜜桃',
      price: 320,
      priceShow: 'NT\$320',
      originalPrice: 420,
      originalPriceShow: 'NT\$420',
      stock: 0,
      photos: const [],
      goodsGpn: soldOutGoodsGpn,
      soldOut: 1,
      isHot: 0,
      diversionUrl: '',
    ),
  ];

  // -- Surface 2: in-stock variant product detail -----------------------------

  /// The in-stock variant spec dimensions (`specOptions` → `variantGroups`):
  /// one「色號」group with three options. Drives `variantGroups` non-empty.
  static const List<LBSpecOption> _variantSpecOptions = [
    LBSpecOption(name: '色號', child: ['#02 裸粉', '#04 焦糖', '#07 楓糖']),
  ];

  /// The resolvable specs for the variant product (one per color option), so a
  /// completed selection resolves to a purchasable spec.
  ///
  /// PHOTOS ARE DELIBERATELY LEFT EMPTY (`LBSpec.photos` defaults to `const []`) — see
  /// the note on [detail]'s `photos` below. The golden path CANNOT draw a spec photo, so
  /// seeding fake URLs here would only make this fixture LOOK like it covers the
  /// spec-photo rule (flutter-product-sheet-spec-photo-reference-ui) while covering
  /// nothing. That rule's real coverage lives in
  /// `test/productsheets/resolved_product_photo_test.dart` (pure-function matrix) plus
  /// the widget wiring tests — NOT here.
  static const List<LBSpec> _variantSpecs = [
    LBSpec(id: 'spec-02', name: '#02 裸粉', specificationNo: 'SN-02', priceShow: 'NT\$380', stock: 4),
    LBSpec(id: 'spec-04', name: '#04 焦糖', specificationNo: 'SN-04', priceShow: 'NT\$380', stock: 9),
    LBSpec(id: 'spec-07', name: '#07 楓糖', specificationNo: 'SN-07', priceShow: 'NT\$380', stock: 6),
  ];

  /// A selected-spec fixture whose price pair DIFFERS from [detail]'s — the ONLY demo
  /// fixture that makes "the spec price REPLACES the product price" observable in a
  /// golden (flutter-product-sheet-demo-fixture-spec-coverage-reference-ui; mirrors iOS
  /// `ProductSheetsModel.demoVariantSpecPriced`).
  ///
  /// WHY THIS EXISTS — every golden call site builds the sheet directly and passes NO
  /// `selectedSpec` (it defaults to `null`), so `resolvePriceDisplay` on the golden path
  /// ALWAYS takes rung 1 (whole pair from the product level). The existing baselines
  /// therefore have ZERO discriminating power over the spec-price rule: a regression that
  /// makes the resolver always return `detail` keeps every one of them green. "The
  /// baseline did not move" is NOT a correctness signal there — it is a blind spot.
  ///
  /// Passing THIS fixture as `selectedSpec` drives rung 3, so the price row is drawn from
  /// the spec and any drift becomes pixel-visible:
  ///   • falls back to the product level  → `NT$380` / `NT$480` (both rows differ)
  ///   • mixes sources (fake discount)    → `NT$290` sale with `NT$480` was-price
  ///
  /// WHY THESE VALUES — `NT$290` / `NT$490` against [detail]'s `NT$380` / `NT$480`:
  ///   • BOTH differ, so "the sale price didn't follow the spec" and "the was-price
  ///     didn't follow the spec" are each independently detectable.
  ///   • SAME CHARACTER WIDTH (same `NT$` prefix, 3 digits, no space — matching the seed
  ///     format verbatim), so the difference lands on glyphs only and triggers NO layout
  ///     reflow. That is what lets the new golden be compared against its twin
  ///     (`product-detail-sheet-variant-instock` / `add-to-cart-sheet-variant-instock`)
  ///     to prove the delta is confined to the price row. A value like `NT$1,290` would
  ///     change the text width, push neighbouring elements, and pollute the comparison.
  ///   • VERBATIM EQUAL to the `specWithOwnPrices` used by the widget wiring tests in
  ///     `test/productsheets/product_detail_sheet_test.dart`, so the same pair is guarded
  ///     at both the `find.text` layer and the pixel layer instead of Flutter growing two
  ///     rival "differing price" magic strings.
  ///
  /// Structurally identical to `_variantSpecs[1]` (`spec-04`, the option that
  /// [variantSelection] selects) — same name / specificationNo / stock — so the ONLY
  /// variable between the new goldens and their twins is the price pair. `photos` stays
  /// empty for the reason documented on [_variantSpecs].
  static const LBSpec variantSpecPriced = LBSpec(
    id: 'spec-04',
    name: '#04 焦糖',
    specificationNo: 'SN-04',
    priceShow: 'NT\$290',
    originalPriceShow: 'NT\$490',
    stock: 9,
  );

  /// The in-stock product detail (`product-detail-sheet-variant-instock` +
  /// `product-detail-sheet-favorited`): has `specOptions` → variant groups,
  /// `soldOut == 0`, `stock == 9`.
  ///
  /// `photos` IS DELIBERATELY EMPTY, AND MUST STAY EMPTY — a documented blind spot, not
  /// an oversight (flutter-product-sheet-demo-fixture-spec-coverage-reference-ui D2,
  /// mirroring the iOS lead change).
  ///
  /// `ProductDetailSheet.live` defaults to `false` and EVERY golden runs on that default;
  /// with `live == false` the sheet draws only the deterministic gradient + monogram
  /// placeholder and builds NO `Image.network`. That gating is the whole point of the
  /// flag: it keeps network I/O and load timing out of the baselines. So no fixture
  /// change of any kind can make a golden render a real photo.
  ///
  /// Seeding plausible-looking URLs here would therefore buy ZERO pixel coverage while
  /// making this fixture LOOK like it exercises the spec-photo rule — which is exactly
  /// the false-coverage signal this change exists to eliminate, merely replayed on the
  /// photo axis. Leaving it empty and documenting the gap keeps the limitation visible
  /// instead of disguised.
  ///
  /// Real coverage for the photo rule lives in
  /// `test/productsheets/resolved_product_photo_test.dart` (pure-function matrix) plus
  /// the sibling change's widget wiring tests. That is the correct level: resolution is a
  /// pure function and drawing is a one-line `live` conditional — neither needs a golden.
  static final LBProductDetailState detail = LBProductDetailState(
    productId: variantProductId,
    name: '絲絨霧面唇釉 #04 焦糖',
    priceShow: 'NT\$380',
    originalPriceShow: 'NT\$480',
    price: 380,
    stock: 9,
    soldOut: 0,
    photos: const [],
    specifications: _variantSpecs,
    specOptions: _variantSpecOptions,
  );

  /// Demo variant groups (mapped from [_variantSpecOptions] the way
  /// `DefaultVariantPicker.reset` maps them: `label = name`, `options = child`).
  static const List<LBVariantGroup> variantGroups = [
    LBVariantGroup(label: '色號', options: ['#02 裸粉', '#04 焦糖', '#07 楓糖']),
  ];

  /// Demo variant selection: the middle option (`#04 焦糖`, optionIndex 1) of the
  /// single group (groupIndex 0) is selected (`selection[0] == 1`).
  static const Map<int, int> variantSelection = {0: 1};

  /// Demo qty state for the in-stock detail: `{ qty: 1, min: 1, max: 9 }` (matches
  /// the variant product's stock).
  static const LBQtyState qty = LBQtyState(qty: 1, min: 1, max: 9);

  // -- Surface 3: in-stock mini-cart peek -------------------------------------

  /// The in-stock mini-cart peek (`mini-cart-peek-in-stock`): a just-added in-stock
  /// product (`soldOut == 0`).
  static const LBMiniCartPeek miniCartPeek = LBMiniCartPeek(
    productId: variantProductId,
    name: '絲絨霧面唇釉 #04 焦糖',
    priceShow: 'NT\$380',
    soldOut: 0,
  );

  // -- Surface 4: sold-out detail for the restock-notify sheet ----------------

  /// The SOLD-OUT product detail (`notify-restock-sheet-not-subscribed`):
  /// `soldOut == 1`, `stock == 0`, no specs. Its `goodsGpn` (resolved from
  /// [products] by `productId`) reads `noticeEnabled == false` (not subscribed).
  static final LBProductDetailState restockDetail = LBProductDetailState(
    productId: soldOutProductId,
    name: 'Aurora 腮紅 #02 蜜桃',
    priceShow: 'NT\$320',
    originalPriceShow: 'NT\$420',
    price: 320,
    stock: 0,
    soldOut: 1,
    photos: const [],
    specifications: const [],
    specOptions: const [],
  );
}
