import 'package:livebuy_flutter/livebuy_flutter.dart' show LBProduct;
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show LBProductDetailState;

// detail_breadcrumb — pure push/pop for `ProductSheetsOverlayView._detailBreadcrumb`
// (rb-flutter-product-detail-recommendations §5, design.md D1 "SWAP + BREADCRUMB").
//
// Extracted as PURE FUNCTIONS (no Flutter import, `docs/unit-test-discipline.md`
// 純函式抽出) rather than inlined into the container's `State` — a
// `List<LBProduct>` field on a `StatefulWidget`'s `State` cannot be exercised from a
// plain unit test without standing up the whole widget tree; these two functions can
// be tested directly. Mirrors this file's siblings' established idiom
// (`product_row_overlay.dart`'s `productRowOverlay`, `product_status_badge.dart`'s
// `ProductStatusBadge.resolve`).
//
// The breadcrumb only ever holds AT MOST ONE entry in practice: a nested
// recommendation detail MUST NOT render its own「更多商品」section (design.md, "巢狀
// 明細 MUST NOT 再渲染自己的更多商品推薦格" — no infinite-recursion UI), so a push can
// only ever happen from the OUTER (first-level) detail. These functions do not assume
// or enforce that depth-1 invariant themselves — they are generic list push/pop — the
// container's call sites are what keep it true.

/// Synthesize a presentation-quality [LBProduct] from the CURRENTLY-open [detail]
/// snapshot (`ProductSheetsModel.detail`) — used to push "what's currently open" onto
/// the breadcrumb before a recommendation drill-in swaps the slot's content.
///
/// Unlike `LBProductRecommendation.asDisplayProduct` (`product_row.dart`, used for the
/// TAPPED recommendation, which only ever carries the deliberately-minimal
/// `LBProductRecommendation` shape), this conversion is LOSSLESS for everything the
/// later "back" re-open path reads: `LBProductDetailState` already carries
/// `specifications`/`specOptions`/`stock`/`price`/`photos`/`soldOut` in full — that is
/// exactly the data a `productTap` round-trip would have produced. Only identity-only
/// fields the re-open path never reads (`goodsNo`/`goodsGpn`/`brief`/`videoId`/
/// `beginTime`/`endTime`/...) are left at their defaults. Mirrors RN's
/// `detailAsDisplayProduct` (`rb-rn-product-detail-recommendations`) — the same
/// mitigation for the same underlying constraint (this reference-ui layer has no
/// synchronous `channel.otherGoods` accessor to resolve something richer from; see
/// `product_row.dart`'s `asDisplayProduct` doc).
LBProduct detailAsDisplayProduct(LBProductDetailState detail) => LBProduct(
      id: detail.productId,
      name: detail.name,
      priceShow: detail.priceShow,
      originalPriceShow: detail.originalPriceShow ?? '',
      price: detail.price,
      stock: detail.stock,
      photos: detail.photos,
      goodsGpn: '',
      soldOut: detail.soldOut,
      isHot: 0,
      diversionUrl: '',
      specifications: detail.specifications,
      specOptions: detail.specOptions,
    );

/// Push [current] onto [breadcrumb] and return the NEW list ([breadcrumb] itself is
/// untouched). `current == null` (the container could not resolve a full [LBProduct]
/// for what's currently open — see `ProductSheetsOverlayView._resolveCurrentProduct`)
/// → returns [breadcrumb] unchanged (no push): pushing a placeholder would make
/// "back" return to nothing useful, so skipping is the safer default over a synthetic
/// entry.
List<LBProduct> pushDetailBreadcrumb(
  List<LBProduct> breadcrumb,
  LBProduct? current,
) {
  if (current == null) return breadcrumb;
  return [...breadcrumb, current];
}

/// The result of [popDetailBreadcrumb]: the popped product (`null` when [breadcrumb]
/// was already empty) + the remaining list.
class PoppedDetailBreadcrumb {
  final LBProduct? product;
  final List<LBProduct> remaining;

  const PoppedDetailBreadcrumb({required this.product, required this.remaining});
}

/// Pop the LAST entry off [breadcrumb]. Pure — [breadcrumb] itself is untouched.
/// Empty [breadcrumb] → `product: null`, `remaining: breadcrumb` (the caller's cue to
/// fall through to a full dismiss instead of a "back").
PoppedDetailBreadcrumb popDetailBreadcrumb(List<LBProduct> breadcrumb) {
  if (breadcrumb.isEmpty) {
    return PoppedDetailBreadcrumb(product: null, remaining: breadcrumb);
  }
  return PoppedDetailBreadcrumb(
    product: breadcrumb.last,
    remaining: breadcrumb.sublist(0, breadcrumb.length - 1),
  );
}
