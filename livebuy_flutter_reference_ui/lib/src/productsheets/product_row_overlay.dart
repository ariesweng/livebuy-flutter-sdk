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

/// [productRowOverlay] 的結果。[showPlay] 與 [showIntroducing] 在所有模式（含 VOD）恆互斥、
/// 且恆有一者為 `true`（rb-flutter-product-row-vod-done-state-removed, 2026-09-07 撤回先前
/// VOD 兩者皆 `false` 的 `done` 例外態，見 [ProductRowMode.vod] doc below）。
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
/// 「介紹中」標籤在任一 row 恆互斥、恆有一者為 `true`（VOD 也不例外，見下）。
///
/// - VOD (rb-flutter-product-row-vod-done-state-removed, 2026-09-07 — TWO states, 同構於
///   REPLAY；取代先前 rb-flutter-product-row-vod-intro-mask / design R36 的三態):
///   `beginTime`/`endTime` 缺任一者 → 退回舊行為（永遠可 seek，`showPlay: true,
///   showIntroducing: false`）。兩者皆有值時依 [position] 分二態：`beginTime <= position <
///   endTime` → now（`showPlay: false, showIntroducing: true`，滿版等化器遮罩）；其餘所有情況
///   （`position < beginTime` 或 `position >= endTime`）→ 統一顯示置中播放鈕
///   （`showPlay: true, showIntroducing: false`）——不再有「已介紹完畢」的無覆蓋層第三態。
///   二態決策忽略 [isNarrating]。
/// - active live: 「介紹中」⟺ [isNarrating]（`narrate_status == 2` 的商品）；永不顯示
///   播放 affordance（直播無未來可 scrub）。TWO states only（介紹中 / 非介紹中）。
/// - replay: 「介紹中」⟺ 當下播放 [position] 落在商品 `[beginTime, endTime]` 窗（含邊界）；
///   否則顯示播放 affordance（seek 到該片段）。replay 不看 [isNarrating]
///   （`introducingProductId` 只在 active live 非 null）。TWO states only（介紹中 / 可 seek），
///   永遠顯示某種覆蓋層——與 VOD 現在同構。**例外**：[isReplayNeverIntroduced] 為真（`beginTime`/
///   `endTime` 皆為 `0`，一個獨立於上述二態結構的第三態 sentinel）時，兩者皆不顯示——見該函式
///   doc（rb-flutter-replay-never-introduced-no-ui，parity iOS `rb-ios-replay-never-introduced-no-ui`）。
ProductRowOverlayResult productRowOverlay({
  required ProductRowMode mode,
  required bool isNarrating,
  required int? beginTime,
  required int? endTime,
  required int position,
}) {
  switch (mode) {
    case ProductRowMode.vod:
      if (beginTime == null || endTime == null) {
        // Missing timestamp fallback — same visual as "not currently introducing"
        // (always seekable).
        return const ProductRowOverlayResult(
            showPlay: true, showIntroducing: false, showShare: true);
      }
      if (position >= beginTime && position < endTime) {
        // now — inside the intro window.
        return const ProductRowOverlayResult(
            showPlay: false, showIntroducing: true, showShare: true);
      }
      // Not currently introducing (position < beginTime OR position >= endTime) —
      // two-state VOD (rb-flutter-product-row-vod-done-state-removed, 2026-09-07):
      // the former VOD-exclusive `done` third state (position >= endTime → no
      // overlay at all) is retired. VOD is now isomorphic to `replay`'s two states.
      return const ProductRowOverlayResult(
          showPlay: true, showIntroducing: false, showShare: true);
    case ProductRowMode.live:
      return ProductRowOverlayResult(
          showPlay: false, showIntroducing: isNarrating, showShare: false);
    case ProductRowMode.replay:
      if (isReplayNeverIntroduced(beginTime: beginTime, endTime: endTime)) {
        // Never-introduced sentinel: a clean thumbnail, neither affordance shown.
        // showShare is unaffected — this `.replay` branch always shows it regardless.
        return const ProductRowOverlayResult(
            showPlay: false, showIntroducing: false, showShare: true);
      }
      final inWindow = beginTime != null &&
          endTime != null &&
          beginTime <= position &&
          position <= endTime;
      return ProductRowOverlayResult(
          showPlay: !inWindow, showIntroducing: inWindow, showShare: true);
  }
}

/// `.replay`-only sentinel: `beginTime`/`endTime` BOTH being exactly `0` (not `null`) means
/// this product was NEVER narrated during the original live broadcast — a backend sentinel,
/// distinct from missing (`null`) data, which falls back to the play affordance via the
/// normal window comparison above. Scoped ONLY to this exact `[0, 0]` pair: `beginTime == 0`
/// alone with a real, non-zero `endTime` (e.g. `[0, 10)`, a product introduced from the very
/// start of the recording) MUST NOT be swept into this sentinel — it evaluates via the normal
/// window comparison. Does NOT apply to `.vod` / `.live` (those modes never consult this
/// function; a `.vod` product with `beginTime == 0 && endTime == 0` is real, meaningful data
/// evaluated by the `.vod` case's own window logic).
///
/// (rb-flutter-replay-never-introduced-no-ui, parity iOS
/// `ProductRowOverlay.isReplayNeverIntroduced(beginTime:endTime:)`.) Pure — exported for reuse
/// by the product-list drawer's thumbnail-tap handler (`ProductRow._playTap`).
bool isReplayNeverIntroduced({required int? beginTime, required int? endTime}) =>
    beginTime == 0 && endTime == 0;

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

// MARK: - productRowNumberBadgeIndex（design R35，rb-flutter-product-row-number-badge）
//
// 商品列表 sheet（直播 / 直播回放限定，VOD 排除）縮圖左上角「編號徽章」的純決策：算出某商品在
// **後端原始清單順序**（`ProductSheetsModel.productsBackendOrder`，鏡射既有 view-model
// `DefaultProductOverlayState.products` —— 未依介紹中重排）中的 1-based 位置。與
// `ProductBagNarratingBadge.isNarrating` 一樣，純函式、無 Flutter import → 可獨立單元測試，不需要
// 渲染 `ProductListSheet`。Parity iOS / Android / RN `productRowNumberBadge`。

/// [mode] 為 [ProductRowMode.vod] 時恆回傳 `null`（VOD 商品列表不顯示編號徽章）。否則在
/// [backendOrderProductIds]（`ProductSheetsModel.productsBackendOrder` 已先 map 成 id 清單）以
/// `indexOf` 找 [productId]：找到（`>= 0`）回傳 `index + 1`（1-based）；找不到（防禦性——例如快照
/// 尚未同步）回傳 `null`（不顯示徽章）。
///
/// 刻意吃 `List<String>` 而非 `List<LBProduct>`，維持這個檔案「無 import、純 Dart」的既有慣例——
/// 呼叫端（`ProductListSheet`）先把商品清單 map 成 id 字串清單再傳入。
int? productRowNumberBadgeIndex({
  required ProductRowMode mode,
  required String productId,
  required List<String> backendOrderProductIds,
}) {
  if (mode == ProductRowMode.vod) return null;
  final i = backendOrderProductIds.indexOf(productId);
  return i >= 0 ? i + 1 : null;
}
