import 'package:flutter/material.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart' show LBSpec;
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show
        LBProductDetailState,
        LBProductRecommendation,
        LBVariantGroup,
        LBQtyState;

import '../reference_ui_theme.dart';
import '../share_glyph.dart';
import '../testing/lb_test_keys.dart';
import 'cart_spinner.dart';
import 'product_row.dart';
import 'resolved_price_display.dart';
import 'resolved_product_photo.dart';
import 'sheet_header_close_button.dart';
import 'sheet_scaffold.dart';
import 'zoom_badge.dart';

/// How this sheet presents the same product-detail state (rb-align-flutter-product-action-sheet,
/// iOS parity): [detail] = full browse (header「商品明細」+ 168 大圖 + body 底部單獨置中一行的
/// inline 收藏鈕 + 2-slot `[分享][CTA]` footer — 收藏鈕 moved from the footer into the body,
/// rb-flutter-product-sheet-resize-fav-inline, design R19); [addToCart] = compact purchase
/// (header「加入購物車」+ 96×96 product card + CTA-only footer, no 收藏 / 分享) — the design's
/// `AddToCartSheet`. Defaults to [detail].
// restock：售完列補貨鈴鐺專屬入口 → NotifyRestockSheet（rb-flutter-soldout-row-detail-vs-restock，
// iOS/Android parity）。售完品經名稱 / 明細走 detail（ProductDetailSheet 自帶售完處理），不再以 soldOut 覆蓋。
enum ProductSheetPresentation { detail, addToCart, restock }

// ProductDetailSheet — family-3 product sheet-stack surface 2 (detail + variant
// + qty + add-to-cart + INLINE 收藏鈕).
//
// Spec: `reference-ui-rendering/spec.md` (family-3 product + sheets, surface 2).
// Design: `design/templates/minimal/screens.jsx` `ProductDetailSheet` (606-697) /
//          `AddToCartSheet` (699-769) +
//          `design/templates/minimal/sdk-components.jsx` `LBPBottomSheet` /
//          `LBPSheetHeader` / `LBPVariantPicker` / `LBPQtyStepper` / `LBPButton`
//          (primary) / `LBPCartCTA` / `LBPAlertModal` / `LBPFavButton` (1033).
// Parity: iOS `ProductDetailSheetView.swift`
//   (ios/Sources/LivebuyReferenceUI/ProductSheets/ProductDetailSheetView.swift,
//   rb-ios-product-sheets D-3 + rb-ios-gap-surfaces-design-reconcile 收藏鈕) and
//   Android `ProductDetailSheet.kt`
//   (android/livebuy-reference-ui/.../productsheets/ProductDetailSheet.kt). Golden
//   parity names: `product-detail-sheet-variant-instock` (faved=false) +
//   `product-detail-sheet-favorited` (faved=true).
//
// The product-DETAIL sheet for ONE `LBProductDetailState`. It is the second of the
// four family-3 surface widgets composed by `ProductSheetsOverlayView`, and it
// implements the agreed SUB-VIEW INPUT PATTERN documented in
// `product_sheets_view.dart`:
//
//   1. `theme:` (ReferenceUITheme, required)        — FIRST, always.
//   2. bound SNAPSHOT VALUES (read-only, BY VALUE):
//        `detail: LBProductDetailState`, `variantGroups: List<LBVariantGroup>`,
//        `variantSelection: Map<int, int>`, `qty: LBQtyState`,
//        `needsVariantSelection: bool`, `addToCartFailed: bool`, `faved: bool` —
//        passed BY VALUE from `ProductSheetsModel` (never the model, never the
//        template).
//   3. action callbacks (LAST, each defaulting to a no-op):
//        `onSelectVariant(gi, oi)` (chip tap → `template.selectVariant`),
//        `onSetQty` / `onInc` / `onDec` (qty stepper → `template.{setQty,incQty,
//        decQty}`), `onAddToCart` (加入購物車 → `template.addToCart()`),
//        `onToggleFavorite` (收藏 → `goodsTracking.toggleAwait(goodsGpn)`).
//
// This sub-view reads ONLY its passed-in values; it never reaches back into
// `ProductSheetsModel` / `DefaultPlayerTemplate` (one-way data flow, D-1). It also
// renders correctly with all callbacks null (so demo / golden / widget tests
// construct it action-free).
//
// reference-ui NEVER builds HTTP nor calls core `addToCart` / `toggleAwait` — the
// 加入購物車 CTA funnels to `onAddToCart` (the container wires it to
// `model.addToCart()` → `template.addToCart()`, which assembles the route-B request
// internally), and the 收藏鈕 funnels to `onToggleFavorite` (container →
// `model.toggleFavorite()` → `goodsTracking.toggleAwait`). reference-ui never flips
// either flag itself; `faved` is read from `goodsTracking.awaitEnabled(goodsGpn)`.
//
// Variant / qty / add-to-cart guards (D-3):
//   • Variant chips are drawn once per `variantGroups`; the selected chip is
//     `variantSelection[groupIndex]`. Chip tap → `onSelectVariant(group, option)`.
//     The chip group is a `Wrap` (NOT a `GridView`).
//   • Qty stepper is bound to `qty.qty` within `[qty.min, qty.max]`; it is DISABLED
//     when `qty.max == 0` (sold out). `-`/value/`+` → `onDec`/(`onSetQty`)/`onInc`.
//   • The primary 加入購物車 CTA is DISABLED when sold out (`qty.max == 0`).
//   • `needsVariantSelection` → the centered「請選規格」prompt is NO LONGER drawn here; it is hoisted
//     to the container's overlay root (`SelectVariantPromptModalView`). The field is retained for
//     signature stability but unused by this widget.
//   • `addToCartFailed` → retryable error banner.
//
// INLINE 收藏鈕 (rb-flutter-product-sheet-resize-fav-inline, design R19 — supersedes the
// prior "RECONCILED" footer placement, design 2026-06-06): `.detail` draws a HORIZONTAL
// icon+label 收藏鈕 (`LBPFavButton(inline: true)`), centered on its OWN row at the BOTTOM of
// the scrollable BODY (after the qty row / before the add-to-cart failure banner) — NOT in
// the footer action row.
//   • `faved == false` → 空心 `Icons.favorite_border` + theme.text + label「收藏」.
//   • `faved == true`  → 實心 `Icons.favorite` + accent + label「已收藏」.
//   • tap → `onToggleFavorite`. The fav state reads the SAME source as the restock
//     await flag (`goodsTracking.awaitEnabled(goodsGpn)`) — this layer holds NO
//     second copy of it.
//   • `.addToCart` presentation never drew this row (unaffected).
//
// 分享 button (rb-align-flutter-product-sheets — four-platform parity with iOS #8 /
// Android #9): the footer is now a 2-slot `[分享][CTA]` (收藏鈕 moved into the body above).
// A width-56 vertical 分享 button sits to the LEFT of the CTA. Share is a HOST CONCERN — the
// headless SDK exposes no share route, so reference-ui only forwards the tap to `onShare`;
// it builds no share logic and never calls core / template.
//
// DELIBERATE DEVIATION (data gap — iOS/Android lockstep): the design's detail header
// is a LEFT-aligned host-badge row (host avatar + host name + close), but
// `LBProductDetailState` carries NO host data, so the centered「商品明細」title is kept
// and the host-badge header is recorded as a cross-layer follow-up. The design's
// product sub-line (`product.sub`) is likewise not drawn (no `sub` field).
//
// PRESENTATION (rb-align-flutter-product-action-sheet, iOS parity): the same detail
// state renders in two modes via [presentation]. `.detail` (the 明細鈕 / 商品名 route) =
// full browse: 商品明細 header + 168 大圖 + a body-bottom inline 收藏鈕 row + the 2-slot
// [分享][CTA] footer (收藏鈕 relocated out of the footer, rb-flutter-product-sheet-resize-fav-inline).
// `.addToCart` (the list 加購鈕 route) = compact purchase: 加入購物車 header + a 96×96 product card +
// a CTA-ONLY footer (no 收藏 / 分享) — the design's `AddToCartSheet`. A sold-out product
// opens the restock sheet instead (the container's split), so this sheet is never sold-out
// in `.addToCart`.
//
// LAYOUT (rb-sheet-pinned-header-footer, iOS parity): the grab handle + header PIN at the
// top, the [分享][CTA] footer PINS at the bottom, and only the photo / variant / qty / inline
// 收藏鈕 BODY scrolls — within a screen-height cap (via [LBSheetScaffold], now a FIXED 90%
// for `.detail`, draggable 25%–90%, rb-flutter-product-sheet-resize-fav-inline). Unlike the
// iOS `ImageRenderer` snapshot path, the Flutter golden path renders the
// `SingleChildScrollView` correctly, so the golden reflects the pinned layout (no snapshot
// escape hatch).
//
// SHOW-STOCK GATE (rb-flutter-show-stock-caption-toggle, parity iOS `ca77b6d5` /
// Android `d77903e7` / RN `f6996abd`): the「只剩庫存 N 組」caption in the qty row is gated
// by a MERCHANT capability flag the host injects as [showStock].
//
//   • RAW, NOT typed. [showStock] is `Object?` — the VERBATIM
//     `sdkConfig.extensions['show_stock']` wire value. `extensions` is an OPAQUE RAW BAG
//     (`sdk-config` capability: the SDK never interprets its semantics), and Flutter core
//     types it `Map<String, Object?>`, so the host assigns it in one line with zero cast
//     and zero home-grown default. This mirrors THIS layer's own two precedents —
//     `CarouselCardView.productCard` (raw `String?` + `normalizeProductCardMode`) and
//     `LivebuyLiveEntryConfig.position` / `.timing` (raw `String?` +
//     `normalizeFloatingPosition` / `normalizeFloatingTiming`) — and deliberately DIFFERS
//     from iOS / Android, whose config field is a typed `Bool`. Handing the host a typed
//     bool would push the fallback back onto every host, which is exactly how the four
//     platforms grow different edges.
//   • ONE normalization point. [normalizeShowStock] is the ONLY place the raw value
//     becomes a bool (called exactly once, in `_showsStockCaption`).
//   • AND, not OR. [showsStockCaption] = `showStock && !isSoldOut`. The pre-existing
//     "sold out ⇒ no stock caption" rule is UNTOUCHED — the new flag is an ADDITIONAL
//     merchant gate stacked on top, so it is a deliberate NO-OP on a sold-out product.
//   • Off ⇒ the row is REMOVED, not blanked: the collection-if simply is not expanded,
//     so the caption `Text` AND the `SizedBox(width: 12)` that separates it from the
//     stepper both vanish. The load-bearing `Spacer()` keeps the stepper pinned to the
//     trailing edge. NEVER add a placeholder / substitute copy to "keep the alignment".
//   • NAME CLASH, different signal: core `LBVideoItem.showStock` (`POST /sdk/widget`'s
//     `videos.data[].show_stock`) is a DIFFERENT channel this layer does not render.
//     See [normalizeShowStock]'s doc.
//
// RENDERING GOTCHAS (inherited from iOS / Android / family-1/2 lessons): plain
// Column / Row / Wrap / Stack + the scaffold's single `SingleChildScrollView` body.
// The photo is a deterministic gradient placeholder; at runtime (`live == true`) a
// gated `Image.network` overlays it (rb-product-real-images) — `live == false` (golden /
// demo) keeps ONLY the placeholder (byte-stable, no network). Glyphs are `Icons.*`. No
// animation / no randomness so the golden is byte-stable.

// MARK: - Decorative design tokens (literal minimal hex via colorFromHex)
//
// accent / text / background come from the resolved [ReferenceUITheme]. These are
// FIXED decorative colors lifted verbatim from the design `theme.surface.*` /
// `theme.soldOut` (light mode, `design/brands/livebuy/tokens.jsx`). They mirror the
// iOS `ProductDetailSheetView` static colors + Android `ProductDetailSheet` byte-
// for-byte so the three platforms read as one family.

/// `theme.surface.textDim` (secondary / caption text).
final Color _textDim = colorFromHex('#6B6775') ?? const Color(0xFF6B6775);

/// `theme.surface.textFaint` (disabled stepper digit / off control).
final Color _textFaint = colorFromHex('#B6B2BE') ?? const Color(0xFFB6B2BE);

/// `theme.surface.stroke` (hairline divider / footer top border).
final Color _stroke = colorFromHex('#ECEAF0') ?? const Color(0xFFECEAF0);

/// `theme.surface.strokeStrong` (chip outline / stepper border / grab handle /
/// disabled CTA fill).
final Color _strokeStrong = colorFromHex('#D8D5DE') ?? const Color(0xFFD8D5DE);

/// `theme.surface.bgSunken` (sunken control fill — close circle / stepper button).
final Color _bgSunken = colorFromHex('#F4F4F6') ?? const Color(0xFFF4F4F6);

/// `theme.soldOut` (sold-out copy color — design `#9A96A3`).
final Color _soldOutColor = colorFromHex('#9A96A3') ?? const Color(0xFF9A96A3);

/// Product-photo placeholder gradient stops (the design's 4:3 warm media chip).
final Color _photoStart = colorFromHex('#FFD7A8') ?? const Color(0xFFFFD7A8);
final Color _photoEnd = colorFromHex('#E27D5A') ?? const Color(0xFFE27D5A);

// MARK: - Fixed localized copy (static presentation strings — parity to iOS/Android)

const String _headerTitle = '商品明細';
const String _soldOutLabel = '已售完';
const String _qtyLabel = '數量';
const String _stockCaptionPrefix = '只剩庫存 ';
const String _stockCaptionSuffix = ' 組';
const String _addToCartLabel = '加入購物車';
/// 加購請求中 CTA 文字（rb-flutter-cart-add-loading-state，對齊設計 `LBPButton.loadingLabel`）。
const String _addingLabel = '加入中…';
const String _favLabel = '收藏';
const String _favedLabel = '已收藏';
const String _shareLabel = '分享';
const String _retryLabel = '重試';
const String _failureTitle = '加入購物車失敗,請稍後再試';
// 「請選規格」prompt 的 copy 已搬到 `select_variant_prompt_modal.dart`（hoist 到容器 overlay root）。

/// 「商品介紹」區塊標題（design `screens.jsx` `ProductDetailSheet` L879；
/// rb-flutter-product-detail-recommendations §2）。Flutter `LBProduct.description` 已由
/// `add-product-description-core-flutter` 補齊，`rb-flutter-product-intro-real-data` 接上這條
/// 資料線。`rb-flutter-product-intro-bgcolor-and-hide-empty` **反轉**了該次定案的「空字串退回
/// fallback 文案、區塊恆顯示」規則（使用者明確要求，非疏漏）：`description` 空字串時整個區塊
/// （含標題）MUST NOT 顯示，比照既有「商品說明」(`brief`) 的空字串不畫規則對齊——見
/// [ProductDetailSheet.description] / [ProductDetailSheet.showsProductIntro] /
/// [_productIntroSection]。設計稿字面上的 `product.intro || '商品介紹內容'` fallback 因此在
/// Flutter 這裡不再適用，`_productIntroFallback` 常數已隨這個反轉一併移除。
const String _productIntroTitle = '商品介紹';

/// 「更多商品」推薦格標題（design `screens.jsx` L886；rb-flutter-product-detail-recommendations §3）。
const String _recommendationsTitle = '更多商品';

/// 推薦格裁切張數上限（design.md D1，`expose-other-goods-recommendations-template` —
/// 「裁切成幾張」刻意留給 reference-ui 自行決定，不需要動 template）。原始值為 4
/// （`rb-flutter-product-detail-recommendations`），使用者要求顯示更多後由
/// `rb-flutter-recommendations-cap-raise-to-twelve` 調高為 12——純常數調整，`.take()` 消費端
/// 與既有的 2 欄 chunk 版面邏輯本身與筆數無關，不需要跟著改。
const int _recommendationsLimit = 12;

/// Sale 徽章固定文案（rb-flutter-product-sale-badge）。設計稿是 `product.badge || 'Sale'`
/// fallback，但 Flutter 商品模型無 per-product 自訂徽章文字欄位，故恆為此字面值。
const String _saleLabel = 'Sale';

/// Up-to-2-char monogram from the product name (deterministic, pure). Mirrors iOS
/// `ProductDetailSheetView.monogram` / Android `monogram`.
String _monogram(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'LB';
  return trimmed.substring(0, trimmed.length < 2 ? trimmed.length : 2).toUpperCase();
}

// MARK: - show_stock — the merchant capability gate for the stock caption
//         (rb-flutter-show-stock-caption-toggle)

/// THE ONLY place a raw `extensions.show_stock` value becomes a bool.
///
/// Mirrors the design's `normalizeShowStock(raw)`
/// (`design/templates/minimal/sdk-components.jsx`, verbatim
/// `return !(raw === 0 || raw === '0' || raw === false);`). Only three values turn the
/// caption OFF — `false`, the NUMBER zero (`0` / `0.0` / `-0.0`), and the VERBATIM string
/// `'0'`. Everything else returns `true`:
///
/// ```text
/// off : false | 0 | 0.0 | -0.0 | '0'
/// on  : null | missing key | true | 1 | 2 | -1 | 0.5 | '' | ' 0 ' | '0 ' | '00'
///       | '0.0' | '1' | 'false' | 'FALSE' | Map | List | any other type
/// ```
///
/// The comparison is STRICT: it does **not** trim surrounding whitespace, does **not**
/// case-fold and does **not** alias (`'false'` / `'off'` stay ON). Deliberately as strict
/// as the design so all four platforms land on the SAME value when the backend emits a
/// malformed one — that is precisely when a divergence is hardest to notice (the backend
/// passes `extensions` through RAW and normalizes nothing).
///
/// ⚠️ IMPLEMENTED AS TYPE BRANCHES, not as `raw == 0 || raw == '0' || raw == false`.
/// Dart has no `===`: writing `raw == 0` against an `Object?` dispatches to the OPERAND's
/// own `==`, so a caller type that overrides `==` could report equality with `0` and slip
/// past "any unexpected type falls back to ON". Testing `is` first confines every
/// comparison to a known wire primitive. `is num` covers `int` AND `double` in ONE branch
/// on purpose — enumerating subtypes one by one is how a case gets missed (`0.0` and
/// `-0.0` are both `== 0` in Dart, so both are OFF, matching JS's `0.0 === 0`).
///
/// ⚠️ FALLBACK LANDS ON "SHOW", and the reason is NOT "the backend defaults to 1".
/// The backend contract (`openspec/specs/backend/sdk-config.md`, Requirement
/// 「`extensions` raw bag schema」) says of `show_stock`: 「直接取商家該欄位的值,本契約
/// 不宣告其預設」— it declares NO default (unlike its table neighbours `show_pv_num` /
/// `video_title_scroll`, which do). The two reasons this layer lands on "show" are:
///   1. it matches the design as it stood before R15 (the caption was drawn
///      unconditionally), and
///   2. it matches Flutter's own pre-existing behaviour (the caption was gated ONLY by
///      sold-out), so a missing key never makes an existing screen lose a line of text
///      and every existing host / golden stays untouched.
/// Never restate this as "the wire default is 1".
///
/// ⚠️ NAME CLASH — a DIFFERENT signal: core `LBVideoItem.showStock` (`bool`) comes from
/// `POST /sdk/widget`'s `videos.data[].show_stock`, a different endpoint and a different
/// channel. This layer does not render that one (it only fills it in when CONSTRUCTING an
/// `LBVideoItem`, and mirrors it into the native bridge map in
/// `container/widget_data.dart`). This flag MUST NOT be wired to it, MUST NOT reuse its
/// value, and the bridge line MUST NOT be touched: there is no evidence the two share a
/// source, and combining them would be a cross-layer product decision no document has made.
///
/// Reading `extensions` is the HOST's job — this layer never touches `sdkConfig`. The
/// result MUST NOT be written back into config or any view-model.
bool normalizeShowStock(Object? raw) {
  if (raw is bool) return raw; // false → off; true → on
  if (raw is num) return raw != 0; // 0 / 0.0 / -0.0 → off
  if (raw is String) return raw != '0'; // verbatim '0' → off
  return true; // null / missing / any other type → on
}

/// THE ONLY predicate deciding whether the「只剩庫存 N 組」caption is drawn.
///
/// AND, deliberately — the two inputs answer DIFFERENT questions and neither may stand in
/// for the other:
///
///  * [isSoldOut] (`qty.max == 0`) — **"is there a stock number worth stating?"** A DATA
///    state. Sold out already redraws the price row as「已售完」; saying「只剩庫存 0 組」
///    next to it would contradict itself. This rule predates [showStock] and MUST NOT be
///    relaxed by it.
///  * [showStock] — **"is the merchant willing to expose the number?"** A backend /
///    merchant capability gate (`extensions.show_stock`, see [normalizeShowStock]).
///
/// Hence AND, not OR — and hence [showStock] is a deliberate NO-OP on a sold-out product.
///
/// The widget MUST route the caption through this function alone; it MUST NOT restate the
/// condition inline. (That restriction is about the CAPTION only — `isSoldOut` keeps
/// driving the disabled stepper, the disabled CTA and the「已售完」price treatment.)
///
/// Signature is verbatim-identical to the iOS / Android / RN siblings (`showStock` first,
/// `isSoldOut` second, returns bool) so the four gates read as one; only what feeds
/// `showStock` differs per platform (raw here and on RN, typed on iOS / Android).
bool showsStockCaption(bool showStock, bool isSoldOut) => showStock && !isSoldOut;

/// The family-3 product-detail sheet for one [detail]. Renders the product photo
/// placeholder / name / price (with strike-through original), the variant chip
/// picker (one chip group per [variantGroups] entry), the qty stepper, an inline 收藏鈕 row,
/// and the primary 加入購物車 CTA in the footer — plus the retryable add-to-cart failure
/// banner when its guard flag is set. The「請選規格」prompt is NO LONGER
/// drawn here — it is hoisted to the container's player overlay root
/// (`SelectVariantPromptModalView`); see [needsVariantSelection].
class ProductDetailSheet extends StatelessWidget {
  /// Resolved reference-ui theme (FIRST positional argument, always).
  final ReferenceUITheme theme;

  /// The product-detail this sheet renders (`DefaultProductSheet.detail`). Read-only.
  final LBProductDetailState detail;

  /// Variant chip groups (`DefaultVariantPicker.groups`). Read-only.
  final List<LBVariantGroup> variantGroups;

  /// Current variant selection (`DefaultVariantPicker.selection`,
  /// `groupIndex → optionIndex`; a chip is selected when `selection[gi] == oi`).
  /// Read-only.
  final Map<int, int> variantSelection;

  /// The RESOLVED variant spec for the current selection (`DefaultVariantPicker.selectedSpec`,
  /// threaded in by the container as `ProductSheetsModel.selectedSpec`). Read-only BY-VALUE
  /// snapshot, per this file's SUB-VIEW INPUT PATTERN — this widget MUST NOT reach back into
  /// `ProductSheetsModel` / `DefaultPlayerTemplate` to fetch it.
  ///
  /// Drives TWO spec-aware rules, both resolved the way the stock line already is:
  ///
  ///   • the PRICE ROW (flutter-product-sheet-spec-price-reference-ui, parity iOS
  ///     `ProductDetailSheetView`'s `variant.selectedSpec`) — via [_resolvedPrice].
  ///   • the PRODUCT PHOTO SOURCE (flutter-product-sheet-spec-photo-reference-ui) — via
  ///     [_resolvedPhoto], covering BOTH the `.detail` 168 大圖 and the `.addToCart` 96×96
  ///     thumbnail. The container feeds the SAME value to `ProductImageZoomOverlay`, so the
  ///     sheet and the lightbox can never disagree about which photo they show.
  ///
  /// `null` (the DEFAULT) → both rules fall back to the product level, so every existing
  /// call site / demo / golden stays byte-identical.
  ///
  /// It is consumed ONLY through [_resolvedPrice] / [_resolvedPhoto] — never dereferenced
  /// field-by-field at a render site, because the sale price and the struck-through original
  /// MUST stay SAME-SOURCE (see `resolved_price_display.dart`), and "is this photo source
  /// valid" and "which photo do we draw" MUST stay the SAME PREDICATE (see
  /// `resolved_product_photo.dart`).
  final LBSpec? selectedSpec;

  /// Qty-stepper snapshot (`DefaultQtyStepper.state` — `{ qty, min, max }`).
  /// Sold-out → `max == 0` (stepper + CTA disabled). Read-only.
  final LBQtyState qty;

  /// 「請選規格」guard flag (`DefaultPlayerTemplate.needsVariantSelection`). Read-only. RETAINED
  /// for call-site / test signature stability — this widget NO LONGER renders the prompt (it is
  /// hoisted to the container's overlay root, `SelectVariantPromptModalView`). The container
  /// (`ProductSheetsOverlayView`) reads `m.needsVariantSelection` directly to drive that modal.
  final bool needsVariantSelection;

  /// Add-to-cart failure flag (`DefaultPlayerTemplate.addToCartFailed`). Read-only.
  final bool addToCartFailed;

  /// 加購「請求中」loading flag (rb-flutter-cart-add-loading-state) — 由容器以
  /// `ProductSheetsModel.addToCartInFlight` 經 320ms 防閃爍 floor derive 後傳入。`true` → CTA 切
  /// `CartSpinner` +「加入中…」（保 accent 底、點擊 no-op），qty stepper / 規格 chips 鎖定。
  /// Defaults to `false`（既有 golden byte-identical）。Read-only.
  final bool addToCartInFlight;

  /// 收藏（到貨追蹤 type=1）flag (`DefaultGoodsTracking.awaitEnabled(goodsGpn)`).
  /// Drives the 收藏鈕 fill / label. Read-only — this layer holds NO second copy.
  final bool faved;

  /// Host-wired variant chip tap → `model.selectVariant(gi, oi)` →
  /// `template.selectVariant`. `null` for demo / golden instances.
  final void Function(int groupIndex, int optionIndex)? onSelectVariant;

  /// Host-wired direct qty set → `model.setQty(n)` → `template.setQty(n)`.
  final void Function(int qty)? onSetQty;

  /// Host-wired qty `+` → `model.incQty()` → `template.incQty()`.
  final VoidCallback? onInc;

  /// Host-wired qty `-` → `model.decQty()` → `template.decQty()`.
  final VoidCallback? onDec;

  /// Host-wired 加入購物車 → `model.addToCart()` → `template.addToCart()`. reference-ui
  /// NEVER calls core addToCart directly (D-3). `null` for demo / golden instances.
  final VoidCallback? onAddToCart;

  /// Host-wired 收藏 toggle → `model.toggleFavorite()` →
  /// `goodsTracking.toggleAwait(goodsGpn)`. reference-ui NEVER calls core directly.
  /// `null` for demo / golden instances.
  final VoidCallback? onToggleFavorite;

  /// Host-wired 分享 tap (the footer's 2-slot `[分享][CTA]` left slot). Share is a HOST
  /// CONCERN — the headless SDK exposes no share route, so reference-ui only FORWARDS
  /// the intent to this callback; it NEVER builds share logic / calls core / template.
  /// `null` for demo / golden instances (the button renders correctly action-free).
  final VoidCallback? onShare;

  /// Host-wired close / dismiss (clears the container's presentation binding →
  /// `model.closeDetail()` → `template.closeProductDetail()`). `null` for demo /
  /// golden instances — the close glyph renders correctly action-free.
  final VoidCallback? onDismiss;

  /// Presentation mode (rb-align-flutter-product-action-sheet, iOS parity):
  /// [ProductSheetPresentation.detail] = full browse (商品明細 header + 168 大圖 + a
  /// body-bottom inline 收藏鈕 row + 2-slot [分享][CTA] footer,
  /// rb-flutter-product-sheet-resize-fav-inline); [ProductSheetPresentation.addToCart] =
  /// compact purchase (加入購物車 header + 96×96 product card + CTA-only footer, no 收藏 / 分享).
  /// Defaults to [ProductSheetPresentation.detail] so existing call sites are unchanged.
  final ProductSheetPresentation presentation;

  /// `false` (snapshot / demo) → the photo draws the deterministic gradient placeholder
  /// ONLY (goldens unchanged). `true` (host runtime) → load `detail.photos[0]` over it
  /// via a gated `Image.network` (rb-product-real-images). Read-only.
  final bool live;

  /// LIVE/VOD flag (`ProductSheetsModel.isLive` / `header.isLive`, `liveStatus == 1`).
  /// **Different semantics from [live]** (which only gates real-image loading vs the
  /// deterministic placeholder) — do NOT conflate the two. `.detail` presentation's
  /// footer 分享鈕 (`_shareButton`) is hidden ⟺ `isLive == true` (rb-flutter-live-hide-product-share,
  /// parity iOS `ProductDetailSheetView.isLive` / design R12): a genuinely-in-progress live
  /// product has no finalized start-time parameter, so a share link cannot carry a correct
  /// timing anchor the way a VOD / replay share can (replay has real `beginTime`/`endTime`).
  /// `favButton` and the 加入購物車 CTA are UNAFFECTED. Defaults to `false` (VOD / replay / demo)
  /// so every existing call site / golden stays byte-identical. Read-only.
  final bool isLive;

  /// 商品說明（`LBProduct.brief`）— `.detail` 呈現在價格下方畫一段說明（對齊設計 ProductDetailSheet
  /// 的說明文字）。`LBProductDetailState` 不帶 `brief`，故由容器 / `ProductSheetsModel` 從
  /// `productOverlay.products` 快照以 `detail.productId` 解析後傳入（`briefFor`）。空字串 → 不畫
  /// （使既有無 brief 的 demo / golden byte-identical）。`.addToCart` 呈現不畫。Read-only.
  final String brief;

  /// 商品介紹（`LBProduct.description`, `add-product-description-core-flutter`）— `.detail`
  /// 呈現在「商品介紹」文字區使用（見 [showsProductIntro] / [_productIntroSection]）。與
  /// [brief] 是完全獨立的兩個欄位，但顯示規則現在**一致**：`brief` 空字串時整段不畫，
  /// `description` 空字串時整個區塊（含標題）同樣 MUST NOT 顯示
  /// （`showsProductIntro && description.isNotEmpty` 兩個條件缺一不可，見呼叫端 `_body()`）。
  /// `rb-flutter-product-intro-real-data` 當時定案的「空字串退回 fallback 文案、區塊恆顯示」規則
  /// 已被 `rb-flutter-product-intro-bgcolor-and-hide-empty` **刻意反轉**（使用者明確要求，非
  /// 疏漏）。`LBProductDetailState` 不帶 `description`（只有 `productId`），故由容器 /
  /// `ProductSheetsModel` 從 `products` 快照以 `detail.productId` 解析後傳入
  /// （`descriptionFor`，比照 [brief] 的 `briefFor` 同一模式）。Read-only；本 widget 從不回頭抓
  /// model / template。
  final String description;

  /// MERCHANT capability gate for the「只剩庫存 N 組」caption
  /// (rb-flutter-show-stock-caption-toggle, parity iOS / Android / RN).
  ///
  /// Carries the VERBATIM `sdkConfig.extensions['show_stock']` wire value — RAW, not a
  /// bool. `extensions` is an opaque raw bag the SDK never interprets, so the HOST reads
  /// it out and hands it straight in (`showStock: cfg.extensions['show_stock']`, zero
  /// cast); this widget owns the single fallback via [normalizeShowStock]. Omitted /
  /// `null` = "the backend sent nothing" → the caption is SHOWN, so every pre-existing
  /// call site and golden is unchanged.
  ///
  /// AND'ed with the pre-existing sold-out gate through [showsStockCaption] — it is a
  /// deliberate NO-OP on a sold-out product and it MUST NOT relax that rule.
  ///
  /// ⚠️ Semantically UNRELATED to the two neighbouring flags in this section: [live]
  /// gates real-image loading, [isLive] is the LIVE/VOD signal. Do not conflate. Also
  /// unrelated to core `LBVideoItem.showStock` — a different endpoint, see
  /// [normalizeShowStock]. Read-only.
  final Object? showStock;

  /// Host-wired zoom badge tap → container opens the full-frame [ProductImageZoomOverlay]
  /// (rb-flutter-product-image-zoom-lightbox). `null` for demo / golden instances (the badge
  /// renders byte-identical to the prior decorative badge; tap is inert).
  ///
  /// SIGNATURE CHANGE (rb-flutter-product-detail-image-gallery): was `VoidCallback?`, now
  /// carries the photo URL the badge should open the lightbox on. `.detail`'s main-photo
  /// gallery (see `_ProductPhotoGallery`) calls this with its CURRENTLY SELECTED page's URL
  /// (may be `null`); `.addToCart`'s 96×96 compact-card badge (no gallery concept) always
  /// calls it with `null`. The container forwards the value straight through to
  /// `ProductImageZoomOverlay.overridePhotoURL`, so the lightbox shows the same photo the
  /// gallery was on instead of unconditionally re-deriving `primaryPhoto`.
  final void Function(String? photoUrl)? onZoomImage;

  /// Whether the「商品介紹」text section CAN be drawn at all (rb-flutter-product-detail-
  /// recommendations §2). Default `false` — **baseline protection**, NOT the production
  /// behavior: the production container (`ProductSheetsOverlayView`) always passes `true` on
  /// its one call site, so this default only protects EXISTING `.detail` golden / widget-test
  /// call sites (`test/goldens/product-detail-sheet-*.png` etc., which never pass this flag)
  /// from suddenly growing a new section they never asked for.
  ///
  /// Actually drawing the section additionally requires [description] to be non-empty
  /// (`showsProductIntro && description.isNotEmpty`, rb-flutter-product-intro-bgcolor-and-hide-
  /// empty — reverses `rb-flutter-product-intro-real-data`'s earlier "always show, fall back to
  /// static copy when empty" decision) — MUST NOT be relaxed back to an OR. `.addToCart`
  /// presentation never draws this section regardless of either flag.
  final bool showsProductIntro;

  /// Whether the「更多商品」推薦格 CAN be drawn at all (rb-flutter-product-detail-
  /// recommendations §5). Default `true` — safe as a default (unlike
  /// [showsProductIntro]) because the section is ALSO gated on
  /// `detail.recommendations.isNotEmpty`, and every pre-existing demo / test / golden
  /// fixture's `recommendations` defaults to `const []`, so this flag changes nothing
  /// for them regardless of its value. What it DOES gate is the container's OWN nested
  /// (drill-in) detail: a nested detail's `recommendations` is NOT naturally empty
  /// (`DefaultPlayerTemplate` recomputes it from the SAME video's `otherGoods`, merely
  /// excluding the new current product — see the container's
  /// `_buildDetailOrRestockSheet`), so WITHOUT this flag a nested detail would render
  /// its own second「更多商品」grid — an infinite-recursion-shaped UI design.md
  /// explicitly forbids. The container passes `false` while its `_detailBreadcrumb` is
  /// non-empty (a drill-in is active) and `true` otherwise.
  final bool showsRecommendations;

  /// Host-wired「更多商品」推薦卡播放圖示 tap → 換片（design.md D3 of
  /// rb-ios-product-detail-recommendations, ported verbatim to Flutter). `null` for demo /
  /// golden instances. This sheet MUST NOT decide whether to call it — the recommendation
  /// card already hides the button entirely when `item.videoId == null` (see
  /// `_recommendationCard`), so when this fires [item] always carries a non-null `videoId`.
  final void Function(LBProductRecommendation item)? onPlayRecommendation;

  /// Host-wired「更多商品」推薦卡**卡片本體** tap → 巢狀明細（design.md D1, SWAP + BREADCRUMB）.
  /// `null` for demo / golden instances. This sheet forwards the ORIGINAL [LBProductRecommendation]
  /// (not the presentation-only `asDisplayProduct` conversion used for pixels) — the container
  /// resolves what to do with it.
  final void Function(LBProductRecommendation item)? onOpenRecommendation;

  /// Host-wired「更多商品」推薦卡**加購鈕** tap → 巢狀 AddToCart（design.md D1). `null` for demo /
  /// golden instances.
  final void Function(LBProductRecommendation item)? onQuickAddRecommendation;

  /// Whether the header's close glyph shows「返回」(back-chevron) instead of「✕」(close)
  /// (rb-flutter-product-detail-recommendations §5.4, design.md D1). The container sets this
  /// `true` while its `detailBreadcrumb` is non-empty (a nested-recommendation drill-in is
  /// active) — [onDismiss] itself is still the ONE callback wired either way; the container
  /// decides what it forwards TO based on the same breadcrumb state. Default `false` (existing
  /// call sites unaffected — plain ✕ close, byte-identical).
  final bool showBackButton;

  /// Whether the INLINE 收藏鈕 row (icon+label, [_favButtonInline]) CAN be drawn at all
  /// (rb-flutter-subscribe-favorite-visibility-toggle, parity iOS / Android / RN). Default
  /// `true` — this WIDGET's own default preserves EXISTING `.detail` call sites / golden
  /// baselines (`product-detail-sheet-favorited.png` etc., which never pass this flag)
  /// byte-identical: production has ALWAYS shown the button, unlike e.g. [showsProductIntro]
  /// which flips a NEW section on. The turnkey container (`LivebuyPlayer`) is the one that
  /// actually turns it off by default via `LivebuyPlayerConfig.showFavorite` (default
  /// `false` — favorite/收藏 is opt-IN chrome a host explicitly turns on). `.addToCart`
  /// presentation never draws this row regardless of this flag (unaffected — it never did).
  /// `false` removes the divider hairline ABOVE the button too (not just the button), so
  /// hiding it does not leave an orphaned rule sitting over nothing.
  final bool showsFavorite;

  const ProductDetailSheet({
    super.key,
    required this.theme,
    required this.detail,
    required this.variantGroups,
    required this.variantSelection,
    required this.qty,
    required this.needsVariantSelection,
    required this.addToCartFailed,
    this.selectedSpec,
    this.addToCartInFlight = false,
    this.faved = false,
    this.presentation = ProductSheetPresentation.detail,
    this.live = false,
    this.isLive = false,
    this.brief = '',
    this.description = '',
    this.showStock,
    this.onSelectVariant,
    this.onSetQty,
    this.onInc,
    this.onDec,
    this.onAddToCart,
    this.onToggleFavorite,
    this.onShare,
    this.onDismiss,
    this.onZoomImage,
    this.showsProductIntro = false,
    this.showsRecommendations = true,
    this.onPlayRecommendation,
    this.onOpenRecommendation,
    this.onQuickAddRecommendation,
    this.showBackButton = false,
    this.showsFavorite = true,
  });

  bool get _isAddToCart => presentation == ProductSheetPresentation.addToCart;

  // MARK: - Derived presentation (pure)

  /// Sold-out / out-of-stock (`qty.max == 0`, set by `DefaultQtyStepper`'s bounds
  /// rule when `soldOut == 1 || stock <= 0`). Drives the disabled qty stepper +
  /// disabled CTA + the「已售完」price treatment.
  bool get _isSoldOut => qty.max == 0;

  /// The SAME-SOURCE price pair for the price row — the SINGLE resolution point
  /// (flutter-product-sheet-spec-price-reference-ui, parity iOS `ProductDetailSheetView.resolvedPrice`).
  ///
  /// Resolves [detail] + [selectedSpec] atomically so the sale price and the struck-through
  /// original can NEVER come from different sources (a mixed pair would render a FAKE
  /// DISCOUNT RATE — see `resolved_price_display.dart`). [_priceRow] reads ONE instance of
  /// this pair for BOTH the strike-through gate (`hasOriginalPrice`) and the rendered
  /// strings, so "is a strike-through drawn" and "which string is drawn" always agree.
  ///
  /// The former `_hasOriginalPrice` getter (which re-derived the flag straight from
  /// `detail.originalPriceShow`) is REMOVED: re-deriving it independently is exactly the
  /// disagreement this pair exists to prevent.
  ResolvedPriceDisplay get _resolvedPrice =>
      resolvePriceDisplay(detail: detail, selectedSpec: selectedSpec);

  /// Whether the Sale badge chip is drawn (rb-flutter-product-sale-badge, parity design
  /// `screens.jsx` `ProductDetailSheet`'s `onSale && !product.sold` / `AddToCartSheet`'s
  /// `was != null && !product.sold`). Reuses [_resolvedPrice]'s SAME-SOURCE
  /// `hasOriginalPrice` (see `resolved_price_display.dart`) rather than re-deriving "is
  /// there an original price" independently, and reuses the pre-existing [_isSoldOut] —
  /// this getter introduces NO new judgement, only the AND of two existing ones. Drives
  /// BOTH the `.detail` and `.addToCart` insertion points (same widget, same predicate).
  bool get _showsSaleBadge => _resolvedPrice.hasOriginalPrice && !_isSoldOut;

  /// The resolved product-photo SOURCE — the SINGLE resolution point for BOTH photo draw
  /// sites (flutter-product-sheet-spec-photo-reference-ui, parity iOS
  /// `ProductDetailSheetView.resolvedPhoto`).
  ///
  /// Resolves [detail] + [selectedSpec] into whichever `photos` array won, so the photo
  /// follows the selected variant. `primaryPhoto` is the ONLY answer to "which one do we
  /// draw" — and is the FIRST NON-BLANK entry, not `photos.first`; the resolver's own
  /// validity guard reuses that same predicate, so a source can never be selected and then
  /// fail to draw (see `resolved_product_photo.dart`).
  ///
  /// The former inline `detail.photos.isEmpty ? null : detail.photos.first` at each draw
  /// site is REMOVED: two independent derivations are exactly the disagreement this
  /// resolution exists to prevent (sheet showing the spec photo, lightbox the product one).
  ResolvedProductPhoto get _resolvedPhoto =>
      resolveProductPhoto(detail: detail, selectedSpec: selectedSpec);

  String get _stockCaption =>
      '$_stockCaptionPrefix${qty.max}$_stockCaptionSuffix';

  /// Whether the「只剩庫存 N 組」caption is drawn — the SINGLE decision point
  /// (rb-flutter-show-stock-caption-toggle). The ONE call of [normalizeShowStock] in this
  /// widget lives here, so the raw wire value is resolved exactly once and the merchant
  /// gate is AND'ed with the pre-existing sold-out gate in exactly one place.
  /// `_qtyRow` reads THIS; it MUST NOT restate the condition inline.
  bool get _showsStockCaption =>
      showsStockCaption(normalizeShowStock(showStock), _isSoldOut);

  @override
  Widget build(BuildContext context) {
    // Top-rounded sheet shell (LBPBottomSheet rounds ONLY the top two corners,
    // 20 20 0 0). The grab handle + header pin at top, the footer pins at bottom, and
    // only the photo / variant / qty body scrolls within the ½-screen cap
    // (rb-sheet-pinned-header-footer, iOS parity). The 「請選規格」prompt is NO LONGER drawn
    // here — it is hoisted to the container's player overlay root (`SelectVariantPromptModalView`).
    // E2E key (INERT — KeyedSubtree paints nothing) on the sheet root. `.addToCart` is a
    // presentation mode of THIS same widget (no distinct sub-sheet widget), so the root
    // carries `addToCartSheet` in compact-purchase mode and `productDetail` otherwise.
    return KeyedSubtree(
      key: _isAddToCart ? LbTestKeys.addToCartSheet : LbTestKeys.productDetail,
      child: Stack(
      children: [
        ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
          child: ColoredBox(
            color: theme.background,
            child: LBSheetScaffold(
              // addToCart（精簡購買 sheet）維持既有固定 0.4（與 NotifyRestock 同高，
              // rb-flutter-addtocart-sheet-height-align-restock）；detail 回退為 content-sized，
              // cap 0.5（rb-flutter-sheetkit-resize-dismiss-unify——取代
              // rb-flutter-product-sheet-resize-fav-inline 曾引入、開啟就逼近全螢幕的固定 0.9；
              // 80% 現為拖曳調高的共用上限（rb-flutter-sheetkit-resize-ceiling-eighty-percent，原
              // 90%），非 `.detail` 專屬靜態值）。
              fillToCap: _isAddToCart,
              heightFraction: _isAddToCart ? 0.4 : null,
              // 拖曳把手即時調整高度＋拖曳收合（下限↔80%，一條連續手勢，
              // rb-flutter-sheetkit-resize-dismiss-unify）—— 現為全部 5 個 sheet 統一具備，不再是
              // opt-in（`draggable` 參數已移除）。
              onDismiss: onDismiss,
              header: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _grabHandle(),
                  _header(),
                ],
              ),
              body: _body(),
              footer: _footer(),
            ),
          ),
        ),

        // 「請選規格」prompt 已 hoist 到容器 `ProductSheetsOverlayView` 的 player overlay root
        // （topmost `Stack` child，`SelectVariantPromptModalView`，與 cart-needs-login gate
        // `AuthGateModalView` 同層）。不再以 `Positioned.fill` 掛在這個 sheet `Stack` 內——卡內掛全幅
        // scrim 會破壞 `LBSheetScaffold` 版面量測造成跑版（flutter-variant-prompt-overlay-fix,
        // iOS/Android/RN parity）。`needsVariantSelection` 建構子 input 仍保留（簽章不變）但本 widget
        // 不再消費它。
      ],
      ),
    );
  }

  // MARK: - Grab handle (LBPBottomSheet handle — shared styling with the family)

  Widget _grabHandle() {
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

  // MARK: - Sheet header (LBPSheetHeader — centered title + trailing close)
  //
  // The centered title switches by presentation (商品明細 browse vs 加入購物車 compact
  // purchase). The trailing close circle forwards [onDismiss] (→ model.closeDetail()
  // → template.closeProductDetail()); it renders correctly action-free for golden /
  // demo instances (onDismiss null → inert tap).

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 標題只在 .detail 呈現畫「商品明細」；.addToCart 無標題——只右上角關閉鈕
          // （對齊設計 AddToCartSheet header 的 flex-end close-only，rb-flutter-product-sheet-detail-polish 問題 3）。
          if (!_isAddToCart)
            Text(
              _headerTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.text,
                fontSize: 15 * theme.fontScale,
                fontWeight: FontWeight.bold,
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            // Shared transparent close (rb-flutter-sheet-header-close-unify): replaces the prior
            // deep `Container(bgSunken)+Icon(close)` so detail / add-to-cart match the list &
            // VideoInfoPanel. Behavior unchanged (onDismiss → dismissDetail / backOrDismiss).
            // `isBack` (rb-flutter-product-detail-recommendations §5.4) swaps the glyph to a
            // back-chevron while a breadcrumb drill-in is active — [onDismiss] is still the ONE
            // wired callback; the container decides what it forwards to.
            child: SheetHeaderCloseButton(
              theme: theme,
              onTap: onDismiss,
              isBack: showBackButton,
            ),
          ),
        ],
      ),
    );
  }

  // MARK: - Body (photo + name + price + variant chips + qty + failure banner)
  //
  // The scrollable body region of [LBSheetScaffold] (pinned header / footer; the body
  // scrolls within the ½-screen cap — rb-sheet-pinned-header-footer). A `mainAxisSize.min`
  // Column; the scaffold's `SingleChildScrollView` lets a tall product (many variant
  // groups + a failure banner) scroll between the pinned chrome instead of overflowing.
  //
  // BACKGROUND LAYERING (rb-flutter-product-intro-bgcolor-and-hide-empty, design
  // `screens.jsx` `ProductDetailSheet` L805-895 + `sdk-components.jsx` `LBPBottomSheet`
  // L921-1003): `.detail` ONLY — the scrollable body sits on a sunken grey backdrop
  // (`_bgSunken`) and its content is split into independent WHITE content cards (see
  // [_whiteCard]) so the existing `SizedBox(height: 20)` gaps between them read as
  // visible grey seams. grab handle / header / footer stay `theme.background` (white) —
  // they are [LBSheetScaffold]'s own `header` / `footer` params, never part of this grey
  // scrollable region. `.addToCart` (design's `AddToCartSheet`) has NO grey layer at all
  // — its branch below is BYTE-IDENTICAL to the pre-existing implementation.

  Widget _body() {
    if (_isAddToCart) {
      // `.addToCart`（精簡購買）：與改動前逐字相同——design 的 AddToCartSheet 本身沒有灰底
      // 分層，這個分支的存在理由是「維持原樣」，MUST NOT 套用 `_bgSunken` / `_whiteCard`。
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _compactProductCard(),
            if (variantGroups.isNotEmpty) ...[
              _hairline(vertical: 18),
              _variantPickers(),
            ],
            _hairline(vertical: 18),
            _qtyRow(),
            // Add-to-cart failure banner (retryable), only when the route-B add
            // threw (D-3). Sits above the footer so it reads as feedback.
            if (addToCartFailed) ...[
              const SizedBox(height: 16),
              _failureBanner(),
            ],
          ],
        ),
      );
    }

    // `.detail`（完整瀏覽）：外層灰底，內容拆成獨立白卡（design.md D1/D2）。
    //
    // TRAILING BOTTOM GAP FIX (rb-flutter-product-detail-bottom-gray-gap-fix): this body
    // used to wrap its WHOLE Column in a static `Padding(bottom: 12)` sitting directly on
    // the grey `_bgSunken` backdrop, so scrolling to the very end always exposed 12pt of
    // bare grey below whichever block happened to render last — most visibly below 更多商品
    // (the reported bug), but the identical seam appears below 商品介紹 when 更多商品 is
    // hidden/empty, or below 白卡 1 when BOTH are hidden. The fix removes that outer wrapper
    // and moves the SAME 12pt INSIDE the LAST VISIBLE white card's OWN background instead —
    // mirrors this file's existing 白卡 1 "bottom padding is 0 at the TOP because it touches
    // the scroll area's own top edge" convention (see the comment on 白卡 1 below), applied
    // symmetrically to the BOTTOM edge, so the last on-screen pixel row is white, not grey.
    //
    // `addToCartFailed`'s banner is the ONE exception: it deliberately has NO white card
    // (design.md D3 — no design reference for that state), so when it is present IT is the
    // true last element and keeps the grey trailing 12pt on its OWN `Padding` (below) —
    // a white card followed by the banner MUST NOT also claim the extra 12, or the banner
    // would gain an unwanted gap above it that never existed pre-fix.
    final showsIntroCard = showsProductIntro && description.isNotEmpty;
    final showsRecsCard =
        showsRecommendations && detail.recommendations.isNotEmpty;
    final card1IsLastVisible =
        !showsIntroCard && !showsRecsCard && !addToCartFailed;
    final introIsLastVisible =
        showsIntroCard && !showsRecsCard && !addToCartFailed;
    final recsIsLastVisible = showsRecsCard && !addToCartFailed;

    return Container(
      width: double.infinity,
      color: _bgSunken,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 白卡 1：縮圖～收藏鈕（168 大圖 → Sale 徽章 → 商品名 → 價格列 → brief → 規格
          // chips → 數量列 → 收藏鈕），對齊設計第一個 `theme.surface.bg` 內容卡
          // （`padding: '0 16px 16px'` — 頂部 0，因為這張卡緊貼捲動區域最頂端）。底部改為
          // `card1IsLastVisible ? 28 : 16`——本卡是最後可見白卡時多吸收 12pt trailing gap
          // （見上方 TRAILING BOTTOM GAP FIX comment），其餘情況維持原本的 16。
          _whiteCard(
            padding: EdgeInsets.fromLTRB(16, 0, 16, card1IsLastVisible ? 28 : 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _productPhoto(),
                // Sale 徽章 (rb-flutter-product-sale-badge, design `ProductDetailSheet`
                // `onSale && !product.sold`): sits between the 168 大圖 and the product
                // name. Presence changes the photo→name gap (12 without the badge, 12+6
                // with — mirrors the design's `marginTop: onSale && !product.sold ? 6 :
                // 12` on the name).
                if (_showsSaleBadge) ...[
                  const SizedBox(height: 12),
                  _saleBadge(
                    fontSize: 11,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  ),
                  const SizedBox(height: 6),
                ] else
                  const SizedBox(height: 12),
                _productName(),
                const SizedBox(height: 10),
                _priceRow(),
                // 商品說明（brief）— 只在 brief 非空時畫（對齊設計 ProductDetailSheet 的
                // 說明文字：12pt / textDim / 多行；rb-flutter-product-sheet-detail-polish
                // 問題 4）。
                if (brief.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    brief,
                    style: TextStyle(
                      color: _textDim,
                      fontSize: 12 * theme.fontScale,
                      height: 1.6,
                    ),
                  ),
                ],
                if (variantGroups.isNotEmpty) ...[
                  _hairline(vertical: 18),
                  _variantPickers(),
                ],
                _hairline(vertical: 18),
                _qtyRow(),
                // INLINE 收藏鈕 (rb-flutter-product-sheet-resize-fav-inline, design R19):
                // a single centered horizontal icon+label row at the bottom of this card.
                // Gated on [showsFavorite] (rb-flutter-subscribe-favorite-visibility-toggle) —
                // the divider hairline is gated TOGETHER with the button so hiding it does
                // not leave an orphaned rule with nothing below.
                if (showsFavorite) ...[
                  _hairline(vertical: 18),
                  _favButtonInline(),
                ],
              ],
            ),
          ),

          // 白卡 2：商品介紹 (rb-flutter-product-detail-recommendations §2). 現在只在
          // `showsIntroCard`（= `showsProductIntro && description.isNotEmpty`）時渲染
          // （rb-flutter-product-intro-bgcolor-and-hide-empty 反轉了先前「恆顯示 +
          // fallback」的規則，見 [description] 的 doc comment）。Sits after 白卡 1（收藏
          // 鈕），before 更多商品 / the failure banner. 底部同樣改為
          // `introIsLastVisible ? 28 : 16`（TRAILING BOTTOM GAP FIX，規則同白卡 1）。
          if (showsIntroCard) ...[
            const SizedBox(height: 20),
            _whiteCard(
              padding: EdgeInsets.fromLTRB(16, 16, 16, introIsLastVisible ? 28 : 16),
              child: _productIntroSection(),
            ),
          ],

          // 白卡 3：更多商品 grid（2 欄，上限 [_recommendationsLimit]=12 張／最多 6 列，
          // rb-flutter-recommendations-cap-raise-to-twelve 由舊值 4 調高——列數依實際筆數浮動，
          // 不是固定 2×2）(rb-flutter-product-detail-recommendations §3/§5) —
          // gated on `showsRecsCard`（= [showsRecommendations]（default true — 見其 doc）
          // AND `recommendations.isNotEmpty`）。The container sets [showsRecommendations] to
          // `false` for a NESTED (drill-in) detail so it does not render a second grid. When
          // shown this card always renders LAST among the white cards (nothing white-card-
          // based follows it), so — barring the `addToCartFailed` banner — it is always the
          // last visible one; its bottom padding absorbs the trailing 12pt whenever
          // `recsIsLastVisible`（TRAILING BOTTOM GAP FIX，規則同白卡 1 / 白卡 2）。
          if (showsRecsCard) ...[
            const SizedBox(height: 20),
            _whiteCard(
              padding: EdgeInsets.fromLTRB(16, 16, 16, recsIsLastVisible ? 28 : 16),
              child: _recommendationsSection(),
            ),
          ],

          // Add-to-cart failure banner (retryable), only when the route-B add threw
          // (D-3). Sits directly on the grey backdrop (no white card — no design
          // reference for this state; design.md D3), above the footer. Whenever shown it
          // is UNCONDITIONALLY the true last element (nothing white-card-based renders
          // after it, and none of the white cards above claim the extra 12pt in this case
          // — see `card1IsLastVisible` / `introIsLastVisible` / `recsIsLastVisible`'s
          // `!addToCartFailed` guard), so it keeps the grey trailing 12pt on ITS OWN bottom
          // padding instead — exactly what the removed outer `Padding(bottom: 12)` used to
          // contribute in this scenario (TRAILING BOTTOM GAP FIX, byte-identical spacing
          // to pre-fix in this state).
          if (addToCartFailed) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: _failureBanner(),
            ),
          ],
        ],
      ),
    );
  }

  /// One white content "card" on the `.detail` grey scroll body (design's per-block
  /// `theme.surface.bg` wrapper, `screens.jsx` L806/878/885). `width: double.infinity`
  /// follows this file's existing "force full-bleed color inside a `CrossAxisAlignment
  /// .start` Column" convention (`_failureBanner()` / `_hairline()`) — a bare `ColoredBox`
  /// would only wrap its child's natural width, not span the sheet.
  Widget _whiteCard({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(16),
  }) {
    return Container(
      width: double.infinity,
      color: theme.background,
      padding: padding,
      child: child,
    );
  }

  // MARK: - Compact product card (AddToCartSheet 96×96 thumb + name + price)
  //
  // The `.addToCart` presentation uses the design's horizontal product card (96×96 縮圖 +
  // 名 + 價), aligned with `NotifyRestockSheet`'s product block — NOT the `.detail` 168 大圖.
  // The thumbnail is the gated live image over a sunken placeholder (rb-product-real-images).
  //
  // PHOTO SOURCE (flutter-product-sheet-spec-photo-reference-ui, parity iOS): the url comes
  // from [_resolvedPhoto] — the SAME resolution the `.detail` 大圖 and the zoom lightbox read
  // — so the thumbnail follows the selected variant and all three draw sites agree.

  Widget _compactProductCard() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 96×96 rounded thumbnail (mirrors NotifyRestockSheet): bgSunken placeholder,
        // a centered photo glyph, bottom-trailing zoom badge, live real image overlay.
        SizedBox(
          width: 96,
          height: 96,
          child: liveProductImage(
            live: live,
            url: _resolvedPhoto.primaryPhoto,
            borderRadius: BorderRadius.circular(12),
            placeholder: Container(
              decoration: BoxDecoration(
                color: _bgSunken,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Icon(Icons.image_outlined,
                        size: 28, color: _textFaint),
                  ),
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: ZoomBadge(
                      diameter: 24,
                      discColor: const Color(0x8C000000), // black @ 0.55
                      glyphColor: const Color(0xFFFFFFFF),
                      // .addToCart has no gallery concept (rb-flutter-product-detail-image-gallery
                      // scopes the multi-image gallery to `.detail`'s main photo only) — always
                      // forwards `null`, so the lightbox falls back to the existing resolver, same
                      // as before this change.
                      onTap: onZoomImage == null ? null : () => onZoomImage!(null),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sale 徽章 (rb-flutter-product-sale-badge, design `AddToCartSheet`
              // `was != null && !product.sold`): sits above the product name, inside the
              // 縮圖旁欄位 (mirrors the design's `marginBottom: 4` on the badge wrapper).
              if (_showsSaleBadge) ...[
                _saleBadge(
                  fontSize: 10,
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                ),
                const SizedBox(height: 4),
              ],
              Text(
                detail.name,
                style: TextStyle(
                  color: theme.text,
                  fontSize: 15 * theme.fontScale,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              _priceRow(),
            ],
          ),
        ),
      ],
    );
  }

  // MARK: - Product photo (4:3 gradient placeholder + monogram, gated live image)
  //
  // `photos` are remote URLs. `live == false` (golden / demo) draws ONLY the 4:3
  // gradient placeholder chip with a monogram (deterministic — no network); `live ==
  // true` (host runtime) overlays the real photo via a gated `Image.network` that falls
  // back to the placeholder on load / error (rb-product-real-images). Mirrors the design's
  // rounded media.
  //
  // PHOTO SOURCE (flutter-product-sheet-spec-photo-reference-ui, parity iOS): the underlying
  // source is `_resolvedPhoto.photos` (the FULL array of the winning source — spec-aware, NOT
  // `detail.photos.first`), the same single resolution point shared with the `.addToCart`
  // thumbnail and the zoom lightbox.
  //
  // MULTI-IMAGE GALLERY (rb-flutter-product-detail-image-gallery, design R34): delegates to
  // [_ProductPhotoGallery] — see that widget's own header comment for the gallery / thumbnail
  // / zoom-badge-override behavior. `_resolvedPhoto.photos.length <= 1` (every existing
  // `ProductSheetsSeeds` fixture, whose `photos` is always `const []`) renders the SAME single
  // 168-tall image + zoom badge this method drew before this change — byte-identical.

  Widget _productPhoto() {
    return _ProductPhotoGallery(
      theme: theme,
      photos: _resolvedPhoto.photos,
      productId: detail.productId,
      name: detail.name,
      live: live,
      height: 168,
      onZoomImage: onZoomImage,
    );
  }

  // MARK: - Sale badge (rb-flutter-product-sale-badge)
  //
  // A single inline-block chip, shared by BOTH `.detail` (168 大圖 column) and
  // `.addToCart` (96×96 compact card) — the two call sites differ ONLY in [fontSize] /
  // [padding] (parity design `screens.jsx` `ProductDetailSheet` L809-816 vs
  // `AddToCartSheet` L971-975); background / text color / weight / letter-spacing /
  // corner radius / label are IDENTICAL, so a single parameterized helper avoids the two
  // definitions drifting apart. Purely decorative — no tap target, no view-model.

  Widget _saleBadge({required double fontSize, required EdgeInsets padding}) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: theme.accent,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        _saleLabel,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize * theme.fontScale,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  // MARK: - Product name (ProductDetailSheet title)

  Widget _productName() {
    return Text(
      detail.name,
      style: TextStyle(
        color: theme.text,
        fontSize: 16 * theme.fontScale,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  // MARK: - Price row (priceShow accent + originalPriceShow strike-through)
  //
  // Sold out → 已售完 in the sold-out color. In stock → accent priceShow + dim
  // strike-through originalPriceShow.
  //
  // PRICE SOURCE (flutter-product-sheet-spec-price-reference-ui, parity iOS): both strings
  // come from [_resolvedPrice] — the SAME-SOURCE pair resolved from `detail` + `selectedSpec`
  // — so a selected variant's price is shown instead of the product-level default, and the
  // sale price / struck-through original can never disagree (no fake discount rate). Both
  // presentations funnel here: `.detail`'s 168 大圖 column AND `.addToCart`'s 96×96
  // `_compactProductCard`, so this single call site covers both. The resolved
  // `originalPriceShow` is a NON-NULL `String` (`''` = no was-price), which is why the
  // former `detail.originalPriceShow!` null assertion is gone.
  //
  // SOLD-OUT IS UNCHANGED: `_isSoldOut` (`qty.max == 0`) still wins over any price, and is
  // NOT touched by the spec-aware price rule.

  Widget _priceRow() {
    if (_isSoldOut) {
      return Text(
        _soldOutLabel,
        style: TextStyle(
          color: _soldOutColor,
          fontSize: 15 * theme.fontScale,
          fontWeight: FontWeight.bold,
        ),
      );
    }
    final resolved = _resolvedPrice;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          resolved.priceShow,
          style: TextStyle(
            color: theme.accent,
            fontSize: 20 * theme.fontScale,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (resolved.hasOriginalPrice) ...[
          const SizedBox(width: 8),
          Text(
            resolved.originalPriceShow,
            style: TextStyle(
              color: _textDim,
              fontSize: 13 * theme.fontScale,
              decoration: TextDecoration.lineThrough,
              decorationColor: _textDim,
            ),
          ),
        ],
      ],
    );
  }

  // MARK: - Variant pickers (one chip group per LBVariantGroup — LBPVariantPicker)
  //
  // Chip group: label + pill chips laid out with flex-wrap via a native `Wrap`
  // (`spacing: 8` / `runSpacing: 8`), aligned to the design `LBPVariantPicker`
  // (`display:flex; flexWrap:'wrap'; gap:8`). Each chip takes its NATURAL width and
  // wraps to the next run when a row is full — so many options / a long option are
  // never clipped past the container edge (the fixed 3-per-row chunked `Row` this
  // replaces overflowed once a row's chips exceeded the width). Flutter's `Wrap` is a
  // native flow-layout primitive (like RN Yoga `flexWrap` / CSS `flex-wrap`); it
  // measures correctly HERE because the chip group sits under the sheet body's
  // `Padding` → `Column` (a WIDTH-BOUNDED container) and its children are
  // intrinsic-width chips (not `Expanded`) — so it stays deterministic and
  // golden-stable (no under-measure / RenderFlex overflow). NOT a `GridView` /
  // `ListView` / `SingleChildScrollView`. The selected chip (`variantSelection[gi]`)
  // is accent-outlined + accent-tinted; chip tap → `onSelectVariant(gi, oi)`.

  Widget _variantPickers() {
    final pickers = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var gi = 0; gi < variantGroups.length; gi++) ...[
          if (gi > 0) const SizedBox(height: 16),
          Text(
            variantGroups[gi].label,
            style: TextStyle(
              color: theme.text,
              fontSize: 13 * theme.fontScale,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          _chipRows(gi),
        ],
      ],
    );
    // 加購請求中 → dim 規格區（onTap 於 chip 已 gate no-op）。**條件式**：非 in-flight 回 plain
    // Column → 既有 golden byte-identical（rb-flutter-cart-add-loading-state）。
    return addToCartInFlight ? Opacity(opacity: 0.5, child: pickers) : pickers;
  }

  /// The chips for group [gi] as a flex-wrap `Wrap` (`spacing: 8` / `runSpacing: 8`):
  /// each chip takes its NATURAL width and wraps to the next run when a row is full,
  /// so many options / a long option are never clipped past the container edge
  /// (the fixed 3-per-row chunked `Row` this replaces overflowed once a row's chips
  /// exceeded the width). Aligned to the design `LBPVariantPicker` (`flexWrap:'wrap';
  /// gap:8`) + iOS `ChipFlowLayout` / Android `FlowRow` / RN Yoga `flexWrap` parity.
  Widget _chipRows(int gi) {
    final options = variantGroups[gi].options;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var oi = 0; oi < options.length; oi++)
          _variantChip(
            gi: gi,
            oi: oi,
            label: options[oi],
            selected: variantSelection[gi] == oi,
          ),
      ],
    );
  }

  /// One variant chip — accent-outlined + accent-tinted when selected, neutral
  /// stroke otherwise. Tap → `onSelectVariant(gi, oi)` (no-op when null).
  Widget _variantChip({
    required int gi,
    required int oi,
    required String label,
    required bool selected,
  }) {
    return GestureDetector(
      key: LbTestKeys.variantChip(gi, oi),
      behavior: HitTestBehavior.opaque,
      // 加購請求中鎖定規格（onTap no-op；外層 _variantPickers 以 Opacity dim）。
      onTap: addToCartInFlight ? null : () => onSelectVariant?.call(gi, oi),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? theme.accent.withValues(alpha: 0.08) : null,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? theme.accent : _strokeStrong,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? theme.accent : theme.text,
            fontSize: 13 * theme.fontScale,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // MARK: - Qty row (數量 label + stock caption + LBPQtyStepper)
  //
  // Bound to `qty.qty` within `[qty.min, qty.max]`. The stepper is DISABLED when
  // sold out (`qty.max == 0`); `-` is also disabled at `qty.min`, `+` at `qty.max`.
  //
  // STOCK CAPTION GATE (rb-flutter-show-stock-caption-toggle): the caption is drawn iff
  // `_showsStockCaption` — the AND of the merchant capability flag [showStock] (raw
  // `extensions.show_stock`, resolved by `normalizeShowStock`) and the PRE-EXISTING
  // sold-out gate. The new flag is stacked ON TOP of the old rule, never replacing it, so
  // it is a deliberate no-op on a sold-out product. This row MUST NOT test `_isSoldOut`
  // directly for the caption (the stepper's own `enabled` still may — different concern).
  //
  // WHY REMOVING THE CAPTION DOES NOT MOVE THE STEPPER (structural, not numeric):
  //   • The `const Spacer()` after the「數量」label is LOAD-BEARING — it is an `Expanded`
  //     that eats the row's remaining width, and that is what pins the stepper to the
  //     trailing edge. It MUST NOT be removed or turned into a fixed width.
  //   • This `Row` has NO container-level spacing (no `Row(spacing: …)`); the 12 gap lives
  //     as a `SizedBox` INSIDE the same collection-if block as the caption, so caption and
  //     gap appear and disappear together — no leftover hole, no placeholder needed.
  // Never add an empty `Text` / extra `Spacer` / fixed-width box "to keep the alignment".

  Widget _qtyRow() {
    return Row(
      children: [
        Text(
          _qtyLabel,
          style: TextStyle(
            color: theme.text,
            fontSize: 14 * theme.fontScale,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        if (_showsStockCaption) ...[
          Text(
            _stockCaption,
            style: TextStyle(
              color: _textDim,
              fontSize: 12 * theme.fontScale,
            ),
          ),
          const SizedBox(width: 12),
        ],
        _qtyStepper(),
      ],
    );
  }

  /// LBPQtyStepper: `-`  value  `+`. Disabled entirely when sold out.
  Widget _qtyStepper() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepButton(
          buttonKey: LbTestKeys.qtyMinus,
          icon: Icons.remove,
          // 加購請求中鎖定 stepper（rb-flutter-cart-add-loading-state）。
          enabled: !_isSoldOut && !addToCartInFlight && qty.qty > qty.min,
          onTap: onDec,
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 24,
          child: Text(
            '${qty.qty}',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: qty.qty > 0 ? theme.accent : _textFaint,
              fontSize: 16 * theme.fontScale,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 10),
        _stepButton(
          buttonKey: LbTestKeys.qtyPlus,
          icon: Icons.add,
          // 加購請求中鎖定 stepper（rb-flutter-cart-add-loading-state）。
          enabled: !_isSoldOut && !addToCartInFlight && qty.qty < qty.max,
          onTap: onInc,
        ),
      ],
    );
  }

  /// One stepper button — 28×28 rounded square, dimmed + non-tappable when off.
  Widget _stepButton({
    required Key buttonKey,
    required IconData icon,
    required bool enabled,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      key: buttonKey,
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? _bgSunken : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _strokeStrong, width: 1),
        ),
        child: Icon(
          icon,
          size: 14,
          color: enabled ? theme.text : _textFaint,
        ),
      ),
    );
  }

  // MARK: - Add-to-cart failure banner (retryable)

  Widget _failureBanner() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, size: 15, color: theme.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _failureTitle,
              style: TextStyle(
                color: theme.text,
                fontSize: 13 * theme.fontScale,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // 重試 re-invokes onAddToCart (disabled when sold out).
          GestureDetector(
            key: LbTestKeys.addToCartRetry,
            behavior: HitTestBehavior.opaque,
            onTap: _isSoldOut ? null : onAddToCart,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: theme.accent, width: 1),
              ),
              child: Text(
                _retryLabel,
                style: TextStyle(
                  color: theme.accent,
                  fontSize: 13 * theme.fontScale,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // MARK: - Footer (design 2-slot [分享][CTA] — 收藏鈕 relocated to the body, see
  // `_favButtonInline`, rb-flutter-product-sheet-resize-fav-inline)
  //
  // Bottom action row: width-56 vertical 分享鈕 is the ONE secondary slot to the LEFT of
  // the primary 加入購物車 CTA. The CTA is DISABLED when sold out (qty.max == 0) — the
  // disabled fill is strokeStrong (mirrors LBPButton's disabled style). 分享 is a HOST
  // CONCERN — forwarded to `onShare` (iOS / Android parity).
  //
  // rb-flutter-live-hide-product-share (design R12, parity iOS `ProductDetailSheetView`):
  // the 分享鈕 is ADDITIONALLY gated on `!isLive` — a genuinely-in-progress live product has
  // no finalized start-time parameter, so its share link cannot carry a correct timing
  // anchor (VOD / replay products have real `beginTime`/`endTime` and stay shareable). 收藏鈕
  // (now inline in the body) is UNAFFECTED by `isLive`.

  Widget _footer() {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _stroke, width: 1)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // `.addToCart` (compact purchase) drops 分享 — CTA only (the design's
            // AddToCartSheet). `.detail` keeps the 分享鈕 slot; it further hides while
            // `isLive` (rb-flutter-live-hide-product-share). 收藏鈕 no longer lives here
            // (moved to the body, `_favButtonInline`).
            if (!_isAddToCart && !isLive) ...[
              _shareButton(),
              const SizedBox(width: 12),
            ],
            Expanded(child: _addToCartButton()),
          ],
        ),
      ),
    );
  }

  /// 分享鈕 — the footer's left slot (width-56 vertical icon + label). The glyph is
  /// `Icons.ios_share` (the box + up-arrow `square.and.arrow.up` shape, matching iOS /
  /// Android). Share is a HOST CONCERN: the tap only forwards to `onShare` (no-op when
  /// null) — reference-ui builds no share logic and never calls core / template. Hidden
  /// entirely (by the `_footer` call site) while [isLive] — see [isLive] doc
  /// (rb-flutter-live-hide-product-share).
  Widget _shareButton() {
    return GestureDetector(
      key: LbTestKeys.shareButton,
      behavior: HitTestBehavior.opaque,
      onTap: onShare,
      child: SizedBox(
        width: 56,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 分享 改設計稿自繪三節點 ShareGlyph（rb-flutter-share-icon-design-align，問題 8）。
            ShareGlyph(color: theme.text, size: 20),
            const SizedBox(height: 4),
            Text(
              _shareLabel,
              style: TextStyle(
                color: _textDim,
                fontSize: 11 * theme.fontScale,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// INLINE 收藏鈕 (`LBPFavButton(inline: true)` — HORIZONTAL icon+label, centered on its
  /// own row at the bottom of the body; rb-flutter-product-sheet-resize-fav-inline, design
  /// R19 — supersedes the prior vertical footer-row `_favButton`). `faved == false` →
  /// 空心 heart + theme.text + 「收藏」; `faved == true` → 實心 heart + accent + 「已收藏」.
  /// Tap → `onToggleFavorite` (no-op when null). reference-ui never flips the flag itself —
  /// `faved` reads `goodsTracking.awaitEnabled(goodsGpn)`. Keeps the SAME `LbTestKeys.favButton`
  /// identity as the prior footer placement (relocated, not renamed) so existing E2E lookups
  /// by key keep working.
  Widget _favButtonInline() {
    return Center(
      child: GestureDetector(
        key: LbTestKeys.favButton,
        behavior: HitTestBehavior.opaque,
        onTap: onToggleFavorite,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              faved ? Icons.favorite : Icons.favorite_border,
              size: 18,
              color: faved ? theme.accent : theme.text,
            ),
            const SizedBox(width: 6),
            Text(
              faved ? _favedLabel : _favLabel,
              style: TextStyle(
                color: faved ? theme.accent : _textDim,
                fontSize: 13 * theme.fontScale,
                fontWeight: faved ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // MARK: - 商品介紹 (design `screens.jsx` L878-883, rb-flutter-product-detail-recommendations §2)
  //
  // The CALLER (`_body()`) only invokes this when `showsProductIntro && description.isNotEmpty`
  // (rb-flutter-product-intro-bgcolor-and-hide-empty — reverses `rb-flutter-product-intro-
  // real-data`'s earlier "always show, fall back to static copy when empty" decision; the
  // section now behaves like the existing「商品說明」(`brief`, hidden when empty) instead of
  // diverging from it). [description] is therefore ALWAYS non-empty by the time this method
  // runs, so it renders the real `LBProduct.description` directly — no fallback branch. Kept as
  // a plain function (not re-derived here) because `description` is a bound snapshot value
  // resolved by the container via `ProductSheetsModel.descriptionFor` (mirrors [brief]'s
  // `briefFor`) — this widget only reads the passed-in value, it never reaches back into the
  // model / template.

  Widget _productIntroSection() {
    return KeyedSubtree(
      key: LbTestKeys.productIntroSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _productIntroTitle,
            style: TextStyle(
              color: theme.text,
              fontSize: 14 * theme.fontScale,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: TextStyle(
              color: _textDim,
              fontSize: 13 * theme.fontScale,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }

  // MARK: - 更多商品 grid (design `screens.jsx` L885-895, rb-flutter-product-detail-
  //         recommendations §3-5)
  //
  // Reads `detail.recommendations` (`expose-other-goods-recommendations-template`, already
  // filtered to exclude the current product, uncapped), takes the first
  // [_recommendationsLimit] (裁切邏輯屬 reference-ui 版面決定, design.md D1 — 上限值原為 4,
  // rb-flutter-recommendations-cap-raise-to-twelve 調高為 12), and renders each via
  // `ProductRow(layout: .grid, hideSub: true)` in a plain 2-column flow (NOT a `GridView` —
  // this codebase's SNAPSHOT-DETERMINISM rule bars scrollable containers inside the sheet
  // body). Always exactly 2 COLUMNS wide, but the ROW count is NOT fixed — it floats with
  // `items.length` (up to 6 rows at the new 12-item cap), so this is no longer describable
  // as a literal "2×2" grid the way it was at the old cap of 4.
  // Card-body / cart-button taps forward the ORIGINAL `LBProductRecommendation` (not the
  // presentation-only `asDisplayProduct`) up through [onOpenRecommendation] /
  // [onQuickAddRecommendation] so the container can push the outgoing product onto its
  // breadcrumb before drilling in (design.md D1); the play icon forwards through
  // [onPlayRecommendation] and is hidden entirely when `item.videoId == null` (design.md D3 +
  // §4.1) — this sheet makes NO core call itself (D-2/D-3 boundary unchanged).

  Widget _recommendationsSection() {
    final items = detail.recommendations.take(_recommendationsLimit).toList();
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i += 2) {
      final left = items[i];
      final right = i + 1 < items.length ? items[i + 1] : null;
      rows.add(Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _recommendationCard(left, i)),
            const SizedBox(width: 10),
            Expanded(
              child: right == null
                  ? const SizedBox.shrink()
                  : _recommendationCard(right, i + 1),
            ),
          ],
        ),
      ));
    }
    return KeyedSubtree(
      key: LbTestKeys.recommendationsSection,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _recommendationsTitle,
            style: TextStyle(
              color: theme.text,
              fontSize: 14 * theme.fontScale,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          ...rows,
        ],
      ),
    );
  }

  /// One recommendation card. Renders [item]'s presentation-only `asDisplayProduct`
  /// conversion (pixels only — see `product_row.dart`'s doc on the conversion's Flutter-
  /// specific widened caveat) but forwards the ORIGINAL [item] to every callback.
  Widget _recommendationCard(LBProductRecommendation item, int index) {
    return ProductRow(
      rowIndex: index,
      theme: theme,
      product: item.asDisplayProduct,
      live: live,
      layout: ProductRowLayout.grid,
      hideSub: true,
      onOpenProduct: (_) => onOpenRecommendation?.call(item),
      onQuickAdd: (_) => onQuickAddRecommendation?.call(item),
      onPlayClick: item.videoId == null
          ? null
          : () => onPlayRecommendation?.call(item),
    );
  }

  /// Primary 加入購物車 CTA (LBPButton primary — accent fill, white label). DISABLED
  /// when sold out (qty.max == 0) — disabled fill = strokeStrong.
  /// 加購請求中（addToCartInFlight）→ `CartSpinner` +「加入中…」、保 accent 底、點擊 no-op
  /// （對齊設計 `LBPButton.loading`，rb-flutter-cart-add-loading-state）。
  Widget _addToCartButton() {
    return GestureDetector(
      key: LbTestKeys.addToCartCta,
      behavior: HitTestBehavior.opaque,
      // in-flight 期間停用點擊（與售完一致 → onTap null）。
      onTap: (_isSoldOut || addToCartInFlight) ? null : onAddToCart,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // in-flight 維持 accent（不退灰）；只有售完退 strokeStrong。
          color: _isSoldOut ? _strokeStrong : theme.accent,
          // 統一按鈕圓角 → theme.cornerRadius（rb-flutter-button-corner-radius-unify）。
          borderRadius: BorderRadius.circular(theme.cornerRadius),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (addToCartInFlight)
              const CartSpinner(size: 18, strokeWidth: 2)
            else
              const Icon(Icons.shopping_cart_outlined,
                  size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Text(
              addToCartInFlight ? _addingLabel : _addToCartLabel,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15 * theme.fontScale,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // MARK: - Hairline divider (AddToCartSheet section divider)

  Widget _hairline({required double vertical}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: vertical),
      child: SizedBox(
        height: 1,
        width: double.infinity,
        child: ColoredBox(color: _stroke),
      ),
    );
  }
}

// MARK: - _ProductPhotoGallery — `.detail` main-photo multi-image gallery
//         (rb-flutter-product-detail-image-gallery, design R34)
//
// Design: `design/templates/minimal/screens.jsx` `ProductDetailSheet`'s `images` gallery
// (drag + `scrollSnapType: 'x mandatory'` main viewer + a below-fold thumbnail strip, only
// shown when `images.length > 1`). Parity: iOS / Android / RN each carry their own independent
// `rb-{platform}-product-detail-image-gallery` change.
//
// SOURCE: `resolveProductPhoto(...).photos` (a param here, passed in BY VALUE from
// `ProductDetailSheet._resolvedPhoto.photos` — this widget MUST NOT re-derive the photo-source
// degradation ladder itself; `resolveProductPhoto` remains the ONE resolution point, shared
// with `.addToCart`'s compact thumbnail and the zoom lightbox).
//
// `photos.length <= 1` (every existing `ProductSheetsSeeds` fixture — `photos` is always
// `const []`) renders EXACTLY the pre-existing single 168-tall gradient-placeholder-or-real-
// photo Stack + 32×32 zoom badge, with NO thumbnail row and NO swipe `GestureDetector` — byte-
// identical to this file's behavior before this change.
//
// `photos.length > 1` adds:
//   • horizontal swipe on the main image (a `GestureDetector.onHorizontalDragEnd` velocity
//     threshold flips the page — this package's EXISTING carousel idiom, reused verbatim from
//     `_LivePinnedCardCarousel` / `NowIntroducingCarousel` in `live_overlay_chrome_view.dart` /
//     `now_introducing_carousel.dart`. Deliberately NOT a `PageView` — see design.md D1: no
//     animation-driven scroll keeps every frame golden-deterministic).
//   • a thumbnail selector row below (48×48 chips, `SingleChildScrollView(scrollDirection:
//     Axis.horizontal)` + `Row` — this package's existing horizontal-scroll-strip idiom, see
//     `carousel.dart:320`'s turnkey card row). Tapping a thumbnail jumps the main image to it
//     immediately (no animation). The NON-selected thumbnails carry a `rgba(0,0,0,0.5)` scrim;
//     the selected one does not (design's `i !== activeImg` overlay).
//
// SELECTED INDEX is presentation-only local `State` (design.md D2) — `ProductDetailSheet`
// itself stays a `StatelessWidget`; this widget does NOT read or write any view-model. It
// resets to 0 when [productId] changes (design.md D5, mirrors the design's
// `useEffect(() => setActiveImg(0), [product.id])`) — NOT when [photos] content changes under
// the SAME product (e.g. a variant-spec swap that changes which photo array won), so switching
// specs never yanks the user back to page 1.
//
// ZOOM BADGE: tapping it calls [onZoomImage] with the photo CURRENTLY on screen (may be
// `null` when there is nothing drawable) — the container threads this straight through to
// `ProductImageZoomOverlay.overridePhotoURL`, so the lightbox opens on the same page the
// gallery was showing.
class _ProductPhotoGallery extends StatefulWidget {
  const _ProductPhotoGallery({
    required this.theme,
    required this.photos,
    required this.productId,
    required this.name,
    required this.live,
    required this.height,
    this.onZoomImage,
  });

  /// Resolved reference-ui theme (FIRST, always).
  final ReferenceUITheme theme;

  /// The winning photo source's photos, VERBATIM — `ProductDetailSheet._resolvedPhoto.photos`.
  /// This widget MUST NOT re-derive the source itself.
  final List<String> photos;

  /// The product this gallery belongs to (`detail.productId`) — drives the index-reset rule
  /// (design.md D5). NOT used for anything else (no re-fetching, no core / view-model calls).
  final String productId;

  /// The product name, for the monogram placeholder (mirrors `_monogram(detail.name)`).
  final String name;

  /// `false` (golden / demo) → gradient + monogram placeholder only; `true` → real photo.
  final bool live;

  /// Main-image height (168, the pre-existing `.detail` value — passed in rather than
  /// hardcoded so a future call site could reuse this widget at a different size).
  final double height;

  /// Host-wired zoom badge tap, carrying the CURRENTLY SELECTED photo's URL (may be `null`).
  /// `null` for demo / golden instances (the badge renders byte-identical to the prior
  /// decorative-when-inert badge; tap is inert).
  final void Function(String? photoUrl)? onZoomImage;

  @override
  State<_ProductPhotoGallery> createState() => _ProductPhotoGalleryState();
}

/// Swipe velocity (px/s) that commits a main-image page flip — matches this package's existing
/// carousel threshold (`_LivePinnedCardCarousel._pinnedSwipeVelocity` /
/// `NowIntroducingCarousel._swipeVelocity`, both `80`).
const double _gallerySwipeVelocity = 80;

/// Thumbnail chip geometry (design `screens.jsx` `ProductDetailSheet` thumbnail row: `width:
/// 48, height: 48`, `gap: 8`, `borderRadius: 4`, active border `2px solid accent` / inactive
/// `2px solid transparent`).
const double _galleryThumbSize = 48;
const double _galleryThumbGap = 8;
const double _galleryThumbRadius = 4.0;

class _ProductPhotoGalleryState extends State<_ProductPhotoGallery> {
  int _index = 0;

  @override
  void didUpdateWidget(covariant _ProductPhotoGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset to page 1 ONLY when the PRODUCT changed (design.md D5) — a `photos` content change
    // under the SAME product (e.g. a variant-spec swap) MUST NOT reset the page the user is on.
    if (oldWidget.productId != widget.productId) {
      _index = 0;
    }
  }

  /// The gradient + monogram placeholder, parameterized by font size (26 on the main image,
  /// 12 on a thumbnail) — same gradient stops / monogram text as the pre-existing single-photo
  /// placeholder this replaces.
  Widget _placeholder(double fontSize) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_photoStart, _photoEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          _monogram(widget.name),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.92),
            fontSize: fontSize * widget.theme.fontScale,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.photos;
    final hasMultiple = photos.length > 1;
    final count = photos.isEmpty ? 1 : photos.length;
    final i = _index.clamp(0, count - 1);
    final current = photos.isEmpty ? null : photos[i];

    // The main image + zoom badge — structurally IDENTICAL to the pre-existing single-photo
    // `_productPhoto()` Stack (same 12-radius clip, same 4:3 gradient placeholder, same 32×32
    // badge position/colors), just reading `current` (the gallery's selected page) instead of
    // `_resolvedPhoto.primaryPhoto` directly. Wrapped in an INERT `KeyedSubtree` (paints
    // nothing) so tests can find THIS `Image` specifically, disambiguated from the thumbnail
    // row's own `Image` widgets.
    Widget mainImage = KeyedSubtree(
      key: LbTestKeys.productGalleryMainImage,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: widget.height,
          width: double.infinity,
          child: Stack(
            children: [
              Positioned.fill(
                child: liveProductImage(
                  live: widget.live,
                  url: current,
                  placeholder: _placeholder(26),
                ),
              ),
              Positioned(
                right: 10,
                bottom: 10,
                child: ZoomBadge(
                  diameter: 32,
                  discColor: const Color(0xD9FFFFFF), // white @ 0.85
                  glyphColor: const Color(0xFF15131A),
                  onTap: widget.onZoomImage == null
                      ? null
                      : () => widget.onZoomImage!(current),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // photos.length <= 1 (every existing golden fixture): the bare main image — NO swipe
    // wrapper, NO thumbnail row. Byte-identical to this file's pre-gallery behavior.
    //
    // > 1: wrap the main image in a horizontal-swipe GestureDetector (this package's existing
    // velocity-threshold carousel idiom — NOT a PageView, see design.md D1) and add the
    // thumbnail selector row below.
    //
    // Either way the result is wrapped in a `KeyedSubtree` (INERT — paints nothing) carrying
    // `LbTestKeys.productGallery`, so tests can target the swipeable area directly without
    // depending on this private widget's type.
    final Widget content = !hasMultiple
        ? mainImage
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onHorizontalDragEnd: (details) {
                  final v = details.primaryVelocity ?? 0;
                  if (v < -_gallerySwipeVelocity) {
                    setState(() => _index = (i + 1).clamp(0, count - 1));
                  } else if (v > _gallerySwipeVelocity) {
                    setState(() => _index = (i - 1).clamp(0, count - 1));
                  }
                },
                child: mainImage,
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: _galleryThumbSize,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var idx = 0; idx < photos.length; idx++) ...[
                        if (idx > 0) const SizedBox(width: _galleryThumbGap),
                        _thumb(idx, photos[idx], idx == i),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );

    return KeyedSubtree(key: LbTestKeys.productGallery, child: content);
  }

  /// One 48×48 thumbnail chip — tap jumps the main image to [idx] immediately (no animation).
  /// The non-selected scrim (`rgba(0,0,0,0.5)`) mirrors the design's `i !== activeImg` overlay.
  Widget _thumb(int idx, String url, bool active) {
    return GestureDetector(
      key: LbTestKeys.productGalleryThumb(idx),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _index = idx),
      child: Container(
        width: _galleryThumbSize,
        height: _galleryThumbSize,
        decoration: BoxDecoration(
          border: Border.all(
            color: active ? widget.theme.accent : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(_galleryThumbRadius),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            liveProductImage(
              live: widget.live,
              url: url,
              placeholder: _placeholder(12),
            ),
            if (!active)
              Container(color: Colors.black.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}
