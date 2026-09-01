import 'package:flutter/material.dart';
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show LBProductDetailState;

import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';
import 'sheet_header_close_button.dart';
import 'sheet_scaffold.dart';
import 'zoom_badge.dart';

// NotifyRestockSheet — family-3 product sheet-stack surface 4 (restock-notify).
//
// Spec: `reference-ui-rendering/spec.md` (family-3 product + sheets, surface 4).
// Design: `design/templates/minimal/screens.jsx` `NotifyRestockSheet` (lines
//          777-814) + `sdk-components.jsx` `LBPBottomSheet` / `LBPSheetHeader` /
//          `LBPButton` (outline) / `LBPQtyStepper` (disabled).
// Parity: iOS `NotifyRestockSheetView.swift`
//   (ios/Sources/LivebuyReferenceUI/ProductSheets/NotifyRestockSheetView.swift,
//   rb-ios-product-sheets D-5) and Android `NotifyRestockSheet.kt`
//   (android/livebuy-reference-ui/.../productsheets/NotifyRestockSheet.kt). Golden
//   parity name: `notify-restock-sheet-not-subscribed` (`noticeEnabled == false`).
//
// The SOLD-OUT restock-notify sheet for ONE sold-out `LBProductDetailState`
// (`detail.soldOut == 1`). It is the fourth of the four family-3 surface widgets
// composed by `ProductSheetsOverlayView`, and it implements the agreed SUB-VIEW
// INPUT PATTERN documented in `product_sheets_view.dart`:
//
//   1. `theme:` (ReferenceUITheme, required)        — FIRST, always.
//   2. bound SNAPSHOT VALUES (read-only, BY VALUE):
//        `detail: LBProductDetailState` (a sold-out product) + `noticeEnabled: bool`
//        — passed BY VALUE from `ProductSheetsModel` (never the model, never the
//        template).
//   3. action callbacks (LAST, each defaulting to a no-op):
//        `onToggleNotice: VoidCallback?` (funnels to `model.toggleNotice(productId)`
//        → `DefaultGoodsTracking.toggleNotice(goodsGpn)`, type=2 restock
//        subscription) + `onDismiss: VoidCallback?` (close affordance).
//
// This sub-view reads ONLY its passed-in values; it never reaches back into
// `ProductSheetsModel` / `DefaultPlayerTemplate` (one-way data flow, D-1 / D-5). It
// also renders correctly with all callbacks null (so demo / golden / widget tests
// construct it action-free), and it NEVER calls core `addToCart` (the restock sheet
// has no add affordance at all — the product is sold-out).
//
// FAMILY-3 BOUNDARY (D-5): this is the RESTOCK-NOTIFY subscription ONLY. The
// 「通知我補貨」toggle reflects `noticeEnabled` and forwards `onToggleNotice`
// (→ `goodsTracking.toggleNotice(goodsGpn)`, the NOTICE flag only — the container
// resolves `goodsGpn` from the products snapshot). It MUST NOT render the
// goods-tracking AWAIT switch (`toggleAwait` / `awaitEnabled`, 到貨追蹤 type=1 —
// that is the product-detail 收藏鈕) or a notice-tab open-state (family-6
// gap-surfaces).
//
// LAYOUT (rb-sheet-pinned-header-footer, iOS parity): the grab handle + 補貨通知 header
// PIN at top, the 通知我補貨 footer PINS at bottom, and only the product block + qty body
// scrolls — within the ½-screen cap (via `LBSheetScaffold`). The Flutter golden path
// renders the scaffold's `SingleChildScrollView` correctly (the iOS snapshot escape
// hatch is not needed).
//
// RENDERING GOTCHAS (inherited from family-1/2 / iOS / Android): plain Column / Row /
// Stack + the scaffold's single `SingleChildScrollView` body. The 96×96 thumbnail is the
// gated live image over a placeholder (`live == false` → placeholder only, byte-stable;
// `live == true` → real `Image.network` — rb-product-real-images). The restock 「通知我補貨」
// toggle is a CUSTOM PILL SWITCH (a capsule track `Container` + a circle knob) — NOT a
// Material `Switch`. Glyphs are `Icons.*`. No animation / no randomness so the golden is
// byte-stable.

// MARK: - Decorative design tokens (literal minimal hex via colorFromHex)
//
// accent / text / background come from the resolved [ReferenceUITheme]. These are
// FIXED decorative colors lifted verbatim from the design's `theme.surface.*` /
// `theme.soldOut` (light mode, `design/brands/livebuy/tokens.jsx`). They mirror the
// iOS / Android `NotifyRestockSheet` static colors so the three platforms read as
// one family.

/// `theme.surface.textFaint` (faint / disabled text — disabled stepper / 尚無庫存).
final Color _textFaint = colorFromHex('#9A9BA5') ?? const Color(0xFF9A9BA5);

/// `theme.surface.stroke` (hairline border / divider).
final Color _stroke = colorFromHex('#ECEAF0') ?? const Color(0xFFECEAF0);

/// `theme.surface.strokeStrong` (grab handle / pill-switch off track).
final Color _strokeStrong = colorFromHex('#D8D5DE') ?? const Color(0xFFD8D5DE);

/// `theme.surface.bgSunken` (sunken card / photo placeholder / close-circle fill).
final Color _bgSunken = colorFromHex('#F4F4F6') ?? const Color(0xFFF4F4F6);

/// `theme.soldOut` (sold-out caption — design `#9A9BA5`).
final Color _soldOut = colorFromHex('#9A9BA5') ?? const Color(0xFF9A9BA5);

// MARK: - Fixed localized copy (static presentation strings — parity to iOS/Android)

const String _soldOutLabel = '已售完';
const String _qtyLabel = '數量';
const String _noStockLabel = '尚無庫存';
// 補貨 CTA 文案（對齊 design `screens.jsx` `NotifyRestockSheet` + iOS/Android）。
const String _noticeOffLabel = '補貨通知我';
const String _noticeOnLabel = '已開啟補貨通知';

/// The family-3 SOLD-OUT restock-notify sheet for one sold-out
/// [LBProductDetailState]. Renders the bottom-sheet shell (grab handle + centered
/// title + trailing close) over a deterministic product photo placeholder + name +
/// 已售完, a divider, a DISABLED qty row (visual-only `−  0  +`), and a bottom
/// 「通知我補貨」row with a CUSTOM PILL SWITCH bound to [noticeEnabled]. The toggle
/// forwards [onToggleNotice]; RESTOCK-NOTIFY ONLY — no AWAIT switch (family-6).
class NotifyRestockSheet extends StatelessWidget {
  /// Resolved reference-ui theme (FIRST positional argument, always).
  final ReferenceUITheme theme;

  /// The sold-out product-detail this sheet subscribes restock-notify for
  /// (`detail.soldOut == 1`). Read-only.
  final LBProductDetailState detail;

  /// Whether restock-notify (type=2) is currently subscribed for this product
  /// (`DefaultGoodsTracking.noticeEnabled(goodsGpn)`). Drives the pill-switch
  /// on/off state. Read-only.
  final bool noticeEnabled;

  /// `false` (snapshot / demo) → the 96×96 thumbnail draws the deterministic placeholder
  /// only (goldens unchanged). `true` (host runtime) → load `detail.photos[0]` over it
  /// via a gated `Image.network` (rb-product-real-images). Read-only.
  final bool live;

  /// Host-wired restock-notify toggle. The container forwards
  /// `model.toggleNotice(productId)` → `DefaultGoodsTracking.toggleNotice(goodsGpn)`
  /// (optimistic flip of the NOTICE flag only — type=2; corrected by
  /// `NOTICE_GOODS_CHANGED`). `null` for demo / golden instances — the sheet
  /// renders correctly action-free.
  final VoidCallback? onToggleNotice;

  /// Host-wired close / dismiss (→ `model.closeDetail()` → `template.closeProductDetail()`).
  /// `null` for demo / golden instances.
  final VoidCallback? onDismiss;

  /// Host-wired zoom badge tap → container opens the full-frame [ProductImageZoomOverlay]
  /// (rb-flutter-product-image-zoom-lightbox). `null` for demo / golden instances (inert).
  final VoidCallback? onZoomImage;

  const NotifyRestockSheet({
    super.key,
    required this.theme,
    required this.detail,
    required this.noticeEnabled,
    this.live = false,
    this.onToggleNotice,
    this.onDismiss,
    this.onZoomImage,
  });

  @override
  Widget build(BuildContext context) {
    // Top-rounded sheet shell (LBPBottomSheet rounds ONLY the top two corners,
    // radius 20). The grab handle + 補貨通知 header PIN at top, the 通知我補貨 footer PINS
    // at bottom, and only the product block + qty body scrolls — within the ½-screen cap
    // (rb-sheet-pinned-header-footer, iOS parity). Shadows are host-handled / disabled in
    // golden tests, so this stays deterministic.
    // E2E key (INERT — KeyedSubtree paints nothing) on the restock-sheet root.
    return KeyedSubtree(
      key: LbTestKeys.notifyRestockSheet,
      child: ClipRRect(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(20),
        topRight: Radius.circular(20),
      ),
      child: ColoredBox(
        color: theme.background,
        child: LBSheetScaffold(
          // 固定高度填滿到 cap，與 AddToCart 同高（rb-flutter-addtocart-sheet-height-align-restock）。
          fillToCap: true,
          // 拖曳把手即時調整高度＋拖曳收合（下限↔80%，一條連續手勢，
          // rb-flutter-sheetkit-resize-dismiss-unify）—— 與其餘 4 個 sheet 共用同一套機制，不再是
          // opt-in。
          onDismiss: onDismiss,
          header: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _grabHandle(),
              _sheetHeader(),
            ],
          ),
          body: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 6),
                child: _productBlock(),
              ),
              // Hairline divider (design `margin: '18px 0'`).
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                child: Container(height: 1, color: _stroke),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _qtyRow(),
              ),
            ],
          ),
          footer: _noticeFooter(),
        ),
      ),
      ),
    );
  }

  // MARK: - Grab handle (LBPBottomSheet handle — shared across the sheet-stack)

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

  // MARK: - Sheet header (NotifyRestockSheet — trailing close only, NO title)
  //
  // 對齊設計 NotifyRestockSheet header（flex-end）：**無標題**，只右上角關閉鈕
  // （rb-flutter-product-sheet-detail-polish 問題 3——還原先前為「四張 sheet 一致」刻意加上的
  // 置中「補貨通知」標題 deviation）。close 為 no-op 當 `onDismiss == null`。

  Widget _sheetHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 無標題（flex-end）—— 只右上角關閉鈕。
          Align(
            alignment: Alignment.centerRight,
            // Shared transparent close (rb-flutter-sheet-header-close-unify): replaces the prior
            // deep `Container(bgSunken)+Icon(close)`. Behavior unchanged (onDismiss → dismiss).
            child: SheetHeaderCloseButton(theme: theme, onTap: onDismiss),
          ),
        ],
      ),
    );
  }

  // MARK: - Product block (photo placeholder + name + 已售完 — NotifyRestockSheet body)

  Widget _productBlock() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Square photo (design 96×96 / radius 12). `live == false` (golden / demo) →
        // the deterministic sunken placeholder only; `live == true` (runtime) → the
        // real photo loads over it via a gated `Image.network` (rb-product-real-images).
        SizedBox(
          width: 96,
          height: 96,
          child: liveProductImage(
            live: live,
            url: detail.photos.isEmpty ? null : detail.photos.first,
            borderRadius: BorderRadius.circular(12),
            placeholder: Container(
              decoration: BoxDecoration(
                color: _bgSunken,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Stack(
                children: [
                  Center(
                    child:
                        Icon(Icons.image_outlined, size: 28, color: _textFaint),
                  ),
                  // Tappable zoom badge (design screens.jsx ZoomBadge): 24 black@0.55 disc
                  // + white magnifier glyph, bottom-trailing inset 6. Tap → onZoomImage.
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: ZoomBadge(
                      diameter: 24,
                      discColor: const Color(0x8C000000), // black @ 0.55
                      glyphColor: const Color(0xFFFFFFFF),
                      onTap: onZoomImage,
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
              Text(
                detail.name,
                style: TextStyle(
                  color: theme.text,
                  fontSize: 15 * theme.fontScale,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 6),
              // 已售完 — design `color: theme.soldOut`.
              Text(
                _soldOutLabel,
                style: TextStyle(
                  color: _soldOut,
                  fontSize: 13 * theme.fontScale,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // MARK: - Qty row (數量 + 尚無庫存 + disabled stepper — design qty row)
  //
  // Sold-out → no stock. The stepper is a DISABLED affordance (dimmed, the design's
  // `<LBPQtyStepper value={0} disabled />`) — purely presentational, no qty intent
  // is forwarded from this sheet (the restock sheet has no add affordance).

  Widget _qtyRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
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
        Text(
          _noStockLabel,
          style: TextStyle(
            color: _textFaint,
            fontSize: 12 * theme.fontScale,
          ),
        ),
        const SizedBox(width: 14),
        _disabledStepper(),
      ],
    );
  }

  /// Disabled qty stepper affordance (`−  0  +`, all dimmed / non-tappable),
  /// mirroring the design's `disabled` `LBPQtyStepper`. No callbacks — it forwards
  /// nothing (the restock sheet has no add affordance).
  Widget _disabledStepper() {
    return Opacity(
      opacity: 0.6,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _stroke, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _stepperGlyph(Icons.remove),
            SizedBox(
              width: 36,
              child: Text(
                '0',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _textFaint,
                  fontSize: 14 * theme.fontScale,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _stepperGlyph(Icons.add),
          ],
        ),
      ),
    );
  }

  Widget _stepperGlyph(IconData icon) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Icon(icon, size: 14, color: _textFaint),
    );
  }

  // MARK: - Notice footer (補貨 CTA — design LBPButton outline + bell)
  //
  // The restock-notify subscription CTA. A SINGLE full-width outline/filled accent
  // button (design `screens.jsx` `NotifyRestockSheet` footer = `LBPButton
  // kind="outline"`; parity iOS/Android), reflecting `noticeEnabled`:
  //   • not subscribed → transparent fill + 1.5pt accent border + bell + 「補貨通知我」(accent).
  //   • subscribed     → accent fill + bell + 「已開啟補貨通知」(white).
  // Tapping the CTA forwards `onToggleNotice` (a no-op for demo / golden). It sits
  // above a top hairline (design `borderTop`). RESTOCK-NOTIFY ONLY — no AWAIT switch.

  Widget _noticeFooter() {
    final Color fg = noticeEnabled ? Colors.white : theme.accent;
    // 頂部分隔線改用 DecoratedBox 的 Border(top)（全寬、貼頂緣），鏡像 product_detail_sheet._footer()
    // （parity iOS rb-ios-compact-sheet-cap-and-footer）。footer padding 由 call site 移入此處。
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _stroke, width: 1)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
        child: GestureDetector(
          key: LbTestKeys.restockNoticeCta,
          behavior: HitTestBehavior.opaque,
          onTap: onToggleNotice,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: noticeEnabled ? theme.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.accent, width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  noticeEnabled ? Icons.notifications_active : Icons.notifications_none,
                  size: 18,
                  color: fg,
                ),
                const SizedBox(width: 8),
                Text(
                  noticeEnabled ? _noticeOnLabel : _noticeOffLabel,
                  style: TextStyle(
                    color: fg,
                    fontSize: 15 * theme.fontScale,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
