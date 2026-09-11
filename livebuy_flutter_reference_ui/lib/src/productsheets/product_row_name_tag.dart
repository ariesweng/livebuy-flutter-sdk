// ProductRowNameTag — 商品名稱前標籤系統的純決策（Flutter）.
//
// rb-flutter-product-row-name-tag-system (design R39, parity iOS
// `ProductRowNameTag.swift` / Android `ProductRowNameTag.kt` / RN
// `ProductRowNameTag.ts`). 決定 `ProductRow._buildRow`（`.row` 排版）商品名稱**之前**要顯示
// 哪一種 inline 標籤——直播價（LIVE）、即將售完 / 熱賣中（VOD / REPLAY，依既有
// `ProductStatusBadge.fromLabel` 明確 label），或完全不顯示（已售完，或 label 不明確）。
//
// 純函式（無 Flutter import）→ 可獨立單元測試，比照本模組既有 `product_row_overlay.dart` 的
// 既定風格。

import 'product_row_overlay.dart' show ProductRowMode;
import 'product_status_badge.dart' show ProductStatusBadge;

/// 商品名稱前標籤的解析結果。對齊設計來源 `sdk-components.jsx:LBPProductRow` 的 `nameTag`：
/// - [livePrice]  直播價（`ProductRowMode.live`，未售罄，`isFlashSale == false` 的一般模式）
/// - [rush]       搶購中（`ProductRowMode.live`，未售罄，`isFlashSale == true` — design R39
///                 「liveMode === 'rush'」分支，rb-flutter-flash-sale-live-signal-wiring 接線；
///                 先前 [resolve] 文件的「pipe-first, no water yet」佔位敘述已解除）
/// - [outSoon]    即將售完（VOD / REPLAY，`label == 'out_soon'`）
/// - [hot]        熱賣中（VOD / REPLAY，`label == 'hot'`）
/// - [none]       無標籤（已售完，或 label 不明確 / narrating / sold_out）
enum ProductRowNameTag { livePrice, rush, outSoon, hot, none }

/// 商品名稱前標籤的純決策（rb-flutter-product-row-name-tag-system）。
///
/// **已售完是最高優先序的閘門，在 `switch (mode)` 之前檢查，對 [ProductRowMode.live] /
/// `.vod` / `.replay` 一視同仁**——對齊設計來源 `nameTag` 邏輯的第一步 `p.sold ? null : ...`，
/// 不分 mode。[soldOut] SHALL 由呼叫端傳入**已解析**的售罄狀態（`ProductRow._buildRow` 既有的
/// `soldOut` local，即 `ProductStatusBadge.resolve(product) == ProductStatusBadge.soldOut`，
/// 涵蓋 `label == 'sold_out'` 明確值與 `label == '' && product.soldOut == 1` raw fallback
/// 兩種來源）——本函式 MUST NOT 只靠 `ProductStatusBadge.fromLabel(label) ==
/// ProductStatusBadge.soldOut` 自行判斷（那只認得到明確字串 `'sold_out'`，會漏掉 raw fallback
/// 的售罄商品；這正是 iOS sibling change 初版曾漏做 `.live` 分支檢查的 bug 根因，本函式從
/// 一開始即在 `switch` 之前短路，涵蓋全部三個 mode，不重蹈覆轍）。
///
/// **The pipe now carries water**（僅適用未售罄的 `.live` 分支，rb-flutter-flash-sale-live-
/// signal-wiring）：`mode == ProductRowMode.live` 且 `soldOut == false` 時依 [isFlashSale] 二選一
/// —— `true` → [rush]（design R39「搶購中」，`sdk-components.jsx`'s `liveMode === 'rush'`
/// 分支）、`false` → [livePrice]（既有「直播價」）。不因 [label] 而改變。[isFlashSale] SHALL 由
/// 呼叫端傳入 channel 層的 `isFlashSale` 旗標（`channel.isFlashSale`，經
/// `DefaultPlayerHeaderState.isFlashSale` 一路透傳）——先前這裡是「先接水管、水之後再來」的
/// pipe-first 佔位（本函式以 `switch (mode)` 撰寫,未來若有更多 rush 相關訊號可直接擴充,不需重構
/// 既有結構),現在水已經接上。
///
/// `.vod` / `.replay` 分支委派既有 [ProductStatusBadge.fromLabel]（只認明確 `label`，空 /
/// 未知 → [ProductStatusBadge.none]，不臆測 raw 欄位）：`outSoon` → [ProductRowNameTag.outSoon]、
/// `hot` → [ProductRowNameTag.hot]，其餘（含 `none` / `narrating` / `soldOut` 本身，理論上已被
/// 上面的 [soldOut] 短路擋掉）→ [ProductRowNameTag.none]。`isFlashSale` 對 `.vod` / `.replay` 無
/// 作用（design 的 rush 變體只存在於 `liveMode`，即直播中）。
ProductRowNameTag resolve({
  required ProductRowMode mode,
  required String label,
  required bool soldOut,
  required bool isFlashSale,
}) {
  if (soldOut) return ProductRowNameTag.none;
  switch (mode) {
    case ProductRowMode.live:
      return isFlashSale ? ProductRowNameTag.rush : ProductRowNameTag.livePrice;
    case ProductRowMode.vod:
    case ProductRowMode.replay:
      switch (ProductStatusBadge.fromLabel(label)) {
        case ProductStatusBadge.outSoon:
          return ProductRowNameTag.outSoon;
        case ProductStatusBadge.hot:
          return ProductRowNameTag.hot;
        default:
          return ProductRowNameTag.none;
      }
  }
}
