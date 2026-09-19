// ProductRowDiscountBadge — 商品列 `.row` 排版折扣百分比純決策（Flutter）.
//
// rb-flutter-product-row-layout-and-price-color (design R45, parity iOS
// `ProductRowDiscountBadge.swift` / Android / RN sibling changes — same-round, each
// platform independently landing its own file). 純函式（無 Flutter import）→ 可獨立單元
// 測試，比照本模組既有 `product_row_overlay.dart` / `product_row_name_tag.dart` 的既定風格
// （top-level function，不包一層 class）。
//
// 讀 `LBProduct` 的原始數值欄位 `price` / `originalPrice`（NOT 已格式化的顯示字串
// `priceShow` / `originalPriceShow` —— 那兩個是 locale 格式化文字，如 `"NT$590"`，無法解析
// 回數字）。
//
// 公式：`floor((originalPrice - price) / originalPrice * 100)` —— 已對照設計來源
// `design/templates/minimal/sdk-components.jsx` 手寫的 demo data 反推驗證
// （`originalPrice: 890, price: 590` → 設計稿寫死 `off: 33`）：`floor(33.708...) == 33`
// 相符；`round(33.708...) == 34` 不符——這是採用 `floor` 而非 `round` 的判定依據（設計來源
// 沒有明確的取捨註解，demo data 是唯一可查證的 ground truth）。

/// 商品列 `.row` 排版「原價劃線 + 折扣百分比」的百分比純決策
/// （rb-flutter-product-row-layout-and-price-color）。
///
/// `null` 代表沒有任何有意義的東西可顯示：
/// - [price] 或 [originalPrice] 缺值（呼叫端理應已用既有 `originalPriceShow.isNotEmpty &&
///   originalPriceShow != priceShow` 判斷式先行守門才呼叫本函式，但本函式仍自行重新推導
///   防禦性 `null`，不信任呼叫端）；
/// - [originalPrice] 未實際高於 [price]，或非正值（避免除以零）；
/// - 算出的百分比 floor 後恰好是 `0`（例如 `originalPrice: 101, price: 100` →
///   `0.99...%` → floor → `0`——一個真實但罕見的 floor 取整邊界，不是錯誤；顯示一個誤導
///   的「0%」標籤會比完全不顯示更糟）。
int? productRowDiscountPercent({
  required double? price,
  required double? originalPrice,
}) {
  if (price == null || originalPrice == null) return null;
  if (originalPrice <= price || originalPrice <= 0) return null;
  final off = ((originalPrice - price) / originalPrice * 100).floor();
  return off > 0 ? off : null;
}
