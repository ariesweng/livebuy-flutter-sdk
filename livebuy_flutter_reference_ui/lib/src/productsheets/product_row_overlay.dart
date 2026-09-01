// ProductRowOverlay — 商品列縮圖疊層三模式純決策（Flutter）.
//
// product-row-status-overlay (parity iOS `ProductRowOverlay.swift` / Android
// `ProductRowOverlay.kt` / RN `ProductRowOverlay.ts`). 與真實影格 `live` 旗標（縮圖載
// 真實圖 vs placeholder）正交——此處決定的是 VOD / active-live / replay 三模式下的
// 「播放 icon vs 介紹中」疊層。純函式（無 Flutter import）→ 可獨立單元測試。

/// 商品列 row 縮圖疊層的播放模式。與真實影格的 `live` 旗標（圖片載入）不同——這是
/// VOD vs active-live vs replay。
/// - [vod]    純點播：可 seek 到商品介紹片段 → 播放 icon。
/// - [live]   直播中：無未來可跳 → 正在介紹的商品標「介紹中」、其餘無 icon。
/// - [replay] 直播回放：依 begin_time/end_time vs 當下播放秒數逐商品判「介紹中」。
enum ProductRowMode { vod, live, replay }

/// [productRowOverlay] 的結果。[showPlay] 與 [showIntroducing] 在單一 row 互斥。
/// [showShare]（rb-flutter-live-hide-product-share, design R12, parity iOS
/// `ProductRowOverlay.decide` `showShare`）獨立於前兩者：`mode != ProductRowMode.live`
/// — VOD / replay 商品有可用的 `beginTime`/`endTime`，分享連結可帶正確時間點，維持顯示；
/// 進行中直播商品沒有已定案的開始銷售時間，隱藏分享 icon。
class ProductRowOverlayResult {
  final bool showPlay;
  final bool showIntroducing;
  final bool showShare;
  const ProductRowOverlayResult({
    required this.showPlay,
    required this.showIntroducing,
    required this.showShare,
  });
}

/// 商品列 row 縮圖疊層的純決策（product-row-status-overlay）。播放 affordance 與
/// 「介紹中」標籤在任一 row 互斥。
///
/// - VOD: 播放 affordance（seek-to-intro），永不「介紹中」。
/// - active live: 「介紹中」⟺ [isNarrating]（`narrate_status == 2` 的商品）；永不顯示
///   播放 affordance（直播無未來可 scrub）。
/// - replay: 「介紹中」⟺ 當下播放 [position] 落在商品 `[beginTime, endTime]` 窗（含邊界）；
///   否則顯示播放 affordance（seek 到該片段）。replay 不看 [isNarrating]
///   （`introducingProductId` 只在 active live 非 null）。
ProductRowOverlayResult productRowOverlay({
  required ProductRowMode mode,
  required bool isNarrating,
  required int? beginTime,
  required int? endTime,
  required int position,
}) {
  switch (mode) {
    case ProductRowMode.vod:
      return const ProductRowOverlayResult(
          showPlay: true, showIntroducing: false, showShare: true);
    case ProductRowMode.live:
      return ProductRowOverlayResult(
          showPlay: false, showIntroducing: isNarrating, showShare: false);
    case ProductRowMode.replay:
      final inWindow = beginTime != null &&
          endTime != null &&
          beginTime <= position &&
          position <= endTime;
      return ProductRowOverlayResult(
          showPlay: !inWindow, showIntroducing: inWindow, showShare: true);
  }
}

// MARK: - ProductBagNarratingBadge (flutter-product-bag-multi-narrating)
//
// LIVE 可能同時把兩件（以上）商品標記 `narrate_status == 2`
// （`DefaultPlayerTemplate.liveActiveProducts` 已回傳全量集合）。商品袋清單的「介紹中」判斷
// 因此改用集合成員測試，而非單一 id 相等比較——這樣多商品同時介紹時每一件都能被標到，不會
// 只命中資料層排序後的第一件。Parity iOS `ProductBagNarratingBadge.isNarrating(productId:
// narratingIds:)` / Android `ProductBagNarratingBadge.isNarrating(productId, narratingIds)` /
// RN `ProductBagNarratingBadge.isNarrating(productId, narratingIds)`.

/// 商品袋清單「是否介紹中」的純判斷（`product-row-status-overlay` 的 `isNarrating` 輸入來源）。
/// 純函式、無 Flutter import → 可獨立單元測試，不需要渲染 `ProductListSheet`。
class ProductBagNarratingBadge {
  ProductBagNarratingBadge._();

  /// [productId] 是否落在 [narratingIds]（`ProductSheetsModel.liveActiveProducts` 的 id 集合）
  /// 內。空集合（VOD / demo / 無介紹中）對任何 id 一律回傳 `false`。
  static bool isNarrating(String productId, Set<String> narratingIds) =>
      narratingIds.contains(productId);
}
