// 加購 loading 防閃爍最小顯示時間（純函式）— rb-flutter-cart-add-loading-state.
//
// Flutter parity of iOS `CartLoadingFloor.remainingHoldNanos` / Android
// `CartLoadingFloor.remainingHoldMillis` / RN `cartLoadingFloorRemainingMs`。template 的
// `addToCartInFlight` 可能在極短時間內 true→false（特別是 dedup 同步丟 `cartAddDeduplicated`），
// 不加 floor 會讓 spinner 一閃即逝（strobe）。容器層以此純函式 derive 還需 hold 多久才可解除 loading。
class CartLoadingFloor {
  CartLoadingFloor._();

  /// 加購 loading 最小顯示時間（ms）— 與 iOS / Android / RN 320ms 對稱。
  static const int floorMillis = 320;

  /// 給「loading 已顯示」的 [elapsedMillis]，回傳還需 hold 多久（ms）才可隱藏。
  /// elapsed ≥ floor → 0（可立即隱藏）；否則回剩餘正值（容器 `Timer(remaining)` 再隱藏）。
  /// 純函式（不依賴時鐘）→ 可單元測試。
  static int remainingHoldMillis(int elapsedMillis) {
    final remaining = floorMillis - elapsedMillis;
    return remaining > 0 ? remaining : 0;
  }
}
