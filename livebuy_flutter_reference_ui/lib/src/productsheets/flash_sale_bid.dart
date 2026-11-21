import 'package:flutter/widgets.dart';
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show LBBidOutcome, LBBidOutcomeFailed, LBBidOutcomePlaced;

import '../i18n/i18n.dart';
import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';
import 'hourglass_glyph.dart';
import 'product_detail_sheet.dart' show showsStockCaption;

// MARK: - Flash-sale bid presentation helpers (rb-flutter-flash-sale-bid)
//
// Spec: `reference-ui-rendering/spec.md` §「LivebuyReferenceUI 搶購場商品明細狀態：等待結果橫幅、每人
//       限購、隱藏購買鈕（Flutter）」/ §「LivebuyReferenceUI 搶購下標結果提示（Flutter）」.
// Design: `design/templates/minimal/screens.jsx` `LBPBidWaitingBanner` / `LBPQtyHint`;
//         `design/contract/claude-design-sync.md` D10.
// Flutter parity of iOS `FlashSaleBid.swift` / Android `FlashSaleBid.kt` / RN `FlashSaleBid.tsx`.
//
// Pure presentation over the view-model fields `LBProductDetailState.bidWaiting` / `limitNum` /
// `buyButtonHidden` and `DefaultPlayerTemplate.bidOutcome` (live-bid-flutter-template). Every
// decision is a pure function so it is unit-testable without rendering.

// MARK: - Qty-row hint (LBPQtyHint)

/// What the qty row shows to the left of the stepper.
enum QtyHintKind { none, limit, stock }

/// The resolved qty-row hint: [kind] plus, for [QtyHintKind.limit], the per-person limit [num].
@immutable
class QtyHint {
  final QtyHintKind kind;
  final int num;
  const QtyHint._(this.kind, [this.num = 0]);

  static const QtyHint none = QtyHint._(QtyHintKind.none);
  static const QtyHint stock = QtyHint._(QtyHintKind.stock);
  const QtyHint.limit(int num) : this._(QtyHintKind.limit, num);

  /// PURE — design `LBPQtyHint` order: sold out > 每人限購 > 庫存. Sold out keeps the existing rule of
  /// drawing NO caption in the qty row (the price row already reads「已售完」); `limitNum > 0` →
  /// 「每人限購 {num} 組」regardless of [showStock]; otherwise the stock caption stays decided by the
  /// single existing predicate [showsStockCaption].
  static QtyHint resolve({
    required bool isSoldOut,
    required bool showStock,
    required int limitNum,
  }) {
    if (isSoldOut) return none;
    if (limitNum > 0) return QtyHint.limit(limitNum);
    return showsStockCaption(showStock, isSoldOut) ? stock : none;
  }

  @override
  bool operator ==(Object other) => other is QtyHint && other.kind == kind && other.num == num;

  @override
  int get hashCode => Object.hash(kind, num);

  @override
  String toString() => 'QtyHint($kind, $num)';
}

// MARK: - Detail / add-to-cart footer slots

/// Which footer slots the product sheet draws. `buyButtonHidden`（直播管家搶購場、商品沒設搶購關鍵字）
/// removes the CTA outright — no placeholder, no substitute copy (design D10). When neither slot
/// remains the footer (incl. its top separator) is not drawn at all.
@immutable
class ProductSheetFooterSlots {
  final bool share;
  final bool cta;
  const ProductSheetFooterSlots({required this.share, required this.cta});

  bool get isEmpty => !share && !cta;

  /// PURE — 分享 only on the `.detail` presentation while NOT live (rb-flutter-live-hide-product-share);
  /// CTA unless `buyButtonHidden`.
  static ProductSheetFooterSlots resolve({
    required bool isDetailPresentation,
    required bool isLive,
    required bool buyButtonHidden,
  }) =>
      ProductSheetFooterSlots(
        share: isDetailPresentation && !isLive,
        cta: !buyButtonHidden,
      );

  @override
  bool operator ==(Object other) =>
      other is ProductSheetFooterSlots && other.share == share && other.cta == cta;

  @override
  int get hashCode => Object.hash(share, cta);

  @override
  String toString() => 'ProductSheetFooterSlots(share: $share, cta: $cta)';
}

// MARK: - Bid outcome → toast copy

/// PURE: string key for a failed bid by backend `error_code` (rb-flash-sale-bid-strings design.md
/// §2): `purchase_limit_exceeded` → `bid_limit` (`limitNum <= 0` → `bid_failed`), `out_of_stock` →
/// `bid_failed_out_of_stock`, `keyword_missing` → `bid_failed_unavailable`, anything else / null →
/// `bid_failed`.
String bidFailureKey(String? code, int limitNum) {
  switch (code) {
    case 'purchase_limit_exceeded':
      return limitNum > 0 ? 'bid_limit' : 'bid_failed';
    case 'out_of_stock':
      return 'bid_failed_out_of_stock';
    case 'keyword_missing':
      return 'bid_failed_unavailable';
    default:
      return 'bid_failed';
  }
}

/// The toast shown for a flash-sale bid outcome (`DefaultPlayerTemplate.bidOutcome`).
@immutable
class BidToastContent {
  final String key;
  final Map<String, Object> args;
  final bool isError;
  const BidToastContent({required this.key, this.args = const {}, required this.isError});

  /// The copy in the current reference-ui language.
  String get text => ReferenceUIStrings.text(key, args);

  /// PURE — placed → success「已加入搶購」; failed → error copy from [bidFailureKey]
  /// (`{num}` = [limitNum] only for `bid_limit`).
  static BidToastContent resolve(LBBidOutcome outcome, int limitNum) {
    if (outcome is LBBidOutcomeFailed) {
      final key = bidFailureKey(outcome.code, limitNum);
      return BidToastContent(
        key: key,
        args: key == 'bid_limit' ? {'num': limitNum} : const {},
        isError: true,
      );
    }
    assert(outcome is LBBidOutcomePlaced);
    return const BidToastContent(key: 'bid_placed_toast', isError: false);
  }

  @override
  bool operator ==(Object other) =>
      other is BidToastContent &&
      other.key == key &&
      other.isError == isError &&
      other.args.length == args.length &&
      other.args.entries.every((e) => args[e.key] == e.value);

  @override
  int get hashCode => Object.hash(key, isError, args.length);

  @override
  String toString() => 'BidToastContent($key, $args, isError: $isError)';
}

/// PURE: whether an add attempt produced a NEW bid outcome to flash. The Flutter template is not a
/// `ChangeNotifier` (`bidOutcome` is a plain field, live-bid-flutter-template design D2), so the
/// container reads it around `await addToCart()`: [before] right after the synchronous prefix (the
/// template resets it to null there whenever it handles the attempt), [after] once the add settles.
/// A value that was already present before the attempt (e.g. on mount, or an attempt the template
/// ignored without resetting) is the SAME object afterwards → no flash.
bool shouldFlashBidOutcome(LBBidOutcome? before, LBBidOutcome? after) =>
    after != null && !identical(before, after);

// MARK: - BidWaitingBanner (LBPBidWaitingBanner)

/// `#F03246` — design `LBPBidWaitingBanner` background (same literal as iOS / Android / RN).
const Color kBidWaitingRed = Color(0xFFF03246);

/// Full-width `#F03246` banner: hourglass +「正在等待結果...」on the left,「搶購中」on the right
/// (white, 12 bold, padding 16 / 8, gaps 6 / 10). Drawn at the top of the sheet body while
/// `detail.bidWaiting`.
class BidWaitingBanner extends StatelessWidget {
  final ReferenceUITheme theme;
  const BidWaitingBanner({super.key, required this.theme});

  @override
  Widget build(BuildContext context) => referenceUILocalized(() => _build());

  Widget _build() {
    final label = TextStyle(
      color: const Color(0xFFFFFFFF),
      fontSize: 12 * theme.fontScale,
      fontWeight: FontWeight.bold,
    );
    return Container(
      key: LbTestKeys.bidWaitingBanner,
      width: double.infinity,
      color: kBidWaitingRed,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const HourglassGlyph(color: Color(0xFFFFFFFF), size: 14, strokeWidth: 2),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    ReferenceUIStrings.text('bid_waiting'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: label,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(ReferenceUIStrings.text('product_rush'), maxLines: 1, style: label),
        ],
      ),
    );
  }
}
