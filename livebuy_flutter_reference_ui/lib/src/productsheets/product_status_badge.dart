// ProductStatusBadge — 商品狀態標籤的單一優先序解析（Flutter）.
//
// goods-status-label-render (parity iOS `ProductStatusBadge.swift` / Android
// `ProductStatusBadge.kt` / RN `ProductStatusBadge.ts`). 後端 batch ③ 由 SDK 算好
// 結論欄 `LBProduct.label`（唯一優先序 `sold_out > narrating > out_soon > hot`，四者
// 皆無 → `''`）。reference-ui 以此為單一來源、停止各自用 raw 欄位臨時自組。為相容舊後端 /
// demo（`label` 空），[resolve] 在 label 空時以 raw 欄位**同序** fallback；[fromLabel] 則
// 只認**明確** label（給「新視覺」用，空 → [none]，不臆測 raw）。
//
// 純函式（無 Flutter import）→ 可獨立單元測試（與 `product_row_overlay.dart` 同風格）。

import 'package:livebuy_flutter/livebuy_flutter.dart' show LBProduct;

/// 商品狀態標籤。對齊 iOS `ProductStatusBadge` enum / Android / RN。
/// - [soldOut]   售罄
/// - [narrating] 介紹中（僅直播 type=2 有意義）
/// - [outSoon]   即將售完
/// - [hot]       熱賣中
/// - [none]      無標籤
enum ProductStatusBadge {
  soldOut,
  narrating,
  outSoon,
  hot,
  none;

  /// 後端結論欄 `label` 字串 → badge（只認明確 label；空 / 未知 → [none]）。Pure.
  static ProductStatusBadge fromLabel(String label) {
    switch (label) {
      case 'sold_out':
        return ProductStatusBadge.soldOut;
      case 'narrating':
        return ProductStatusBadge.narrating;
      case 'out_soon':
        return ProductStatusBadge.outSoon;
      case 'hot':
        return ProductStatusBadge.hot;
      default:
        return ProductStatusBadge.none;
    }
  }

  /// 單一優先序解析：`label` 優先；`label` 空（舊後端 / demo / 未計算）時以 raw 欄位
  /// （`soldOut` / `isNarrating`（或 `narrateStatus == 2`）/ `isOutSoon` / `isHot`）**同序**
  /// fallback。Pure / testable.
  static ProductStatusBadge resolve(LBProduct p) {
    final byLabel = fromLabel(p.label);
    if (byLabel != ProductStatusBadge.none) return byLabel;
    // fallback（label 空）：維持與後端相同的優先序，確保既有視覺（已售完）相容。
    if (p.soldOut == 1) return ProductStatusBadge.soldOut;
    if (p.isNarrating || p.narrateStatus == 2) return ProductStatusBadge.narrating;
    if (p.isOutSoon == 1) return ProductStatusBadge.outSoon;
    if (p.isHot == 1) return ProductStatusBadge.hot;
    return ProductStatusBadge.none;
  }
}
