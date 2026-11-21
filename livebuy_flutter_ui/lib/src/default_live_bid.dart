import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart';

// MARK: - 搶購下標與得標視窗（view-model 層，live-bid-flutter-template，parity iOS
// live-bid-ios-template / Android live-bid-android-template / RN live-bid-rn-template）
//
// 搶購場直播中（`header.isFlashSale && header.isLive`），`DefaultPlayerTemplate.addToCart()` 改走
// 注入的 [BidRequester]（預設接 core `LivebuySDK.placeBid`），結果寫入
// `DefaultPlayerTemplate.bidOutcome`。core `BID_WON` 經 `TemplateAttachment` 餵入 [DefaultBidWon]
// （「恭喜搶購成功」視窗狀態）。行為 / 狀態 only——不繪製像素、不含任何文字（reference-ui 依狀態與
// 錯誤代碼取文案）。只 import `package:flutter/foundation.dart`（ChangeNotifier）+ core models。

/// 一筆搶購下標請求，由 template 從目前商品明細 + 已選規格 + 數量組成（parity iOS / Android / RN
/// `LBBidRequest`）。形狀比照 `LBAddToCartOptions`：`goodsId` / `specificationId` 為 `int?`
/// （`int.tryParse` 失敗為 null），無規格商品 `specificationId` 為 null；`videoId` 為 template 由
/// `VIDEO_OPEN` 追蹤的當前影片短碼，尚未收到時為 null。
@immutable
class LBBidRequest {
  final int? goodsId;
  final int num;
  final int? specificationId;
  final String? videoId;

  const LBBidRequest({
    required this.goodsId,
    required this.num,
    this.specificationId,
    this.videoId,
  });

  @override
  bool operator ==(Object other) =>
      other is LBBidRequest &&
      other.goodsId == goodsId &&
      other.num == num &&
      other.specificationId == specificationId &&
      other.videoId == videoId;

  @override
  int get hashCode => Object.hash(goodsId, num, specificationId, videoId);
}

/// 最近一次搶購下標的結果（parity iOS / Android / RN `LBBidOutcome`）。template 上為 `null` = 這次
/// 嘗試 / 這個明細還沒有結果。兩個子類別：[LBBidOutcomePlaced]、[LBBidOutcomeFailed]（小型 plain
/// class 階層，比照同套件 `ReplayChatReconcile` 慣例）。
abstract class LBBidOutcome {
  const LBBidOutcome();
}

/// 下標成功（template 同時關閉商品明細）。
class LBBidOutcomePlaced extends LBBidOutcome {
  const LBBidOutcomePlaced();

  @override
  bool operator ==(Object other) => other is LBBidOutcomePlaced;
  @override
  int get hashCode => (LBBidOutcomePlaced).hashCode;
}

/// 下標失敗。[code] 為後端 `error_code`（`purchase_limit_exceeded` / `out_of_stock` / …），沒有代碼
/// （網路錯誤、舊後端、未接線）為 null，reference-ui 依代碼選文案。
class LBBidOutcomeFailed extends LBBidOutcome {
  final String? code;
  const LBBidOutcomeFailed(this.code);

  @override
  bool operator ==(Object other) => other is LBBidOutcomeFailed && other.code == code;
  @override
  int get hashCode => code.hashCode;
}

/// 搶購下標 requester。template 在搶購場直播中的 `addToCart()` 呼叫它；完成 = 下標成功，丟出 =
/// core 的 typed `LBError`（或任意值）。預設 [defaultBidRequester]（接 core `LivebuySDK.placeBid`）。
typedef BidRequester = Future<void> Function(LBBidRequest request);

/// 得標確認 requester：`(videoId, buyingIds)`，每次「確定」呼叫一次、帶全部 `buying_id`。預設
/// [defaultBidConfirmRequester]（fire-and-forget 呼叫 `LivebuySDK.confirmBidWin`，失敗只記 debug log）。
typedef BidConfirmRequester = void Function(String videoId, List<String> buyingIds);

/// 預設下標 requester：`goodsId` 不是整數或尚未追蹤到 `videoId` 時丟 [StateError]（分類為
/// `failed(null)`，同 RN 預設 / Android wiring 的守門），否則委派 `LivebuySDK.placeBid`。
Future<void> defaultBidRequester(LBBidRequest request) async {
  final goodsId = request.goodsId;
  final videoId = request.videoId;
  if (goodsId == null || videoId == null || videoId.isEmpty) {
    throw StateError('placeBid requires a numeric goodsId and a tracked videoId');
  }
  await LivebuySDK.placeBid(
    videoId: videoId,
    goodsId: goodsId,
    specificationId: request.specificationId,
    num: request.num,
  );
}

/// 預設得標確認 requester：fire-and-forget 呼叫 `LivebuySDK.confirmBidWin`，失敗只記 debug log。
void defaultBidConfirmRequester(String videoId, List<String> buyingIds) {
  unawaited(LivebuySDK.confirmBidWin(videoId, buyingIds).then((_) {}, onError: (Object e) {
    debugPrint('[livebuy] confirmBidWin failed: $e');
  }));
}

/// 下標錯誤的分類種類（parity Android `BidRequestOutcome`；Dart 沒有協程取消，故無 `Cancelled`）。
enum BidRejectionKind { deduplicated, needsLogin, failed }

/// 下標錯誤的分類結果；[code] 只在 [BidRejectionKind.failed] 有意義。
@immutable
class BidRejection {
  final BidRejectionKind kind;
  final String? code;
  const BidRejection(this.kind, [this.code]);

  @override
  bool operator ==(Object other) =>
      other is BidRejection && other.kind == kind && other.code == code;
  @override
  int get hashCode => Object.hash(kind, code);
}

/// PURE：下標錯誤 → 分類。[LBErrorCartAddDeduplicated] → deduplicated（同一商品規格的下標仍在
/// 進行中，結果不變）；[LBErrorServer] `code == 401` → needsLogin；其他 → failed，帶
/// `LBError.backendErrorCode`（非空字串才算，否則 null）。
BidRejection classifyBidRejection(Object error) {
  if (error is LBErrorCartAddDeduplicated) {
    return const BidRejection(BidRejectionKind.deduplicated);
  }
  if (error is LBErrorServer && error.code == 401) {
    return const BidRejection(BidRejectionKind.needsLogin);
  }
  final code = error is LBError ? error.backendErrorCode : null;
  return BidRejection(
      BidRejectionKind.failed, (code == null || code.isEmpty) ? null : code);
}

/// PURE（parity iOS `DefaultPlayerTemplate.isBuyButtonHidden` / Android / RN）：直播管家搶購場需要
/// 關鍵字（`saleKeywordRequired`）而這個商品沒設 → 隱藏購買鈕（同網頁 `xslNoKeyword`）。不綁直播狀態。
bool isBuyButtonHidden(LBProduct product, bool saleKeywordRequired) =>
    saleKeywordRequired && product.saleKeyword.isEmpty;

/// PURE：有效每人限購——已選規格的 `limitNum > 0` 取規格值，否則取商品層 [productLimit]；非搶購場
/// 直播中（[bidMode] false）為 0（parity Android / RN `effectiveLimitNum`）。
int effectiveLimitNum(int productLimit, LBSpec? spec, bool bidMode) {
  if (!bidMode) return 0;
  final specLimit = spec?.limitNum ?? 0;
  return specLimit > 0 ? specLimit : productLimit;
}

/// 「恭喜搶購成功」視窗中的一筆得標（parity iOS / Android / RN `LBBidWonItem`）。
@immutable
class LBBidWonItem {
  final String buyingId;
  final String productId;

  /// 無具名規格為 `''`。
  final String specificationId;

  /// 後端組好的名稱，例如 `'保溫杯(紅)'`。
  final String name;
  final int num;

  /// `ordered` / `failed`（core `BID_WON.status`）。
  final String status;

  const LBBidWonItem({
    required this.buyingId,
    required this.productId,
    required this.specificationId,
    required this.name,
    required this.num,
    required this.status,
  });

  /// PURE：`BID_WON` params → 一筆得標；沒有非空字串 `buying_id` 回 null。
  static LBBidWonItem? fromParams(Map<String, Object?> params) {
    final buyingId = _stringParam(params, 'buying_id');
    if (buyingId.isEmpty) return null;
    final rawNum = params['num'];
    return LBBidWonItem(
      buyingId: buyingId,
      productId: _stringParam(params, 'product_id'),
      specificationId: _stringParam(params, 'specification_id'),
      name: _stringParam(params, 'name'),
      // 欄位名 `num` 在類別範圍內遮蔽了型別 `num`，故分別判斷 int / double。
      num: rawNum is int ? rawNum : (rawNum is double ? rawNum.toInt() : 0),
      status: _stringParam(params, 'status'),
    );
  }

  static String _stringParam(Map<String, Object?> params, String key) {
    final value = params[key];
    return value is String ? value : '';
  }

  @override
  bool operator ==(Object other) =>
      other is LBBidWonItem &&
      other.buyingId == buyingId &&
      other.productId == productId &&
      other.specificationId == specificationId &&
      other.name == name &&
      other.num == num &&
      other.status == status;

  @override
  int get hashCode =>
      Object.hash(buyingId, productId, specificationId, name, num, status);
}

/// 「恭喜搶購成功」視窗 view-model（parity iOS / Android / RN `DefaultBidWon`，`template.bidWon`）。
/// 收到 `BID_WON`（`ordered` 或 `failed` 都算得標）→ [record]；「確定」→
/// `DefaultPlayerTemplate.confirmBidWin()`；「取消」/ 換片 → [clear]。自己是 `ChangeNotifier`
/// （比照 `DefaultWinClaim`），每次真的變更通知一次（diff-then-notify）。
class DefaultBidWon extends ChangeNotifier {
  List<LBBidWonItem> _items = const [];
  bool _isPresented = false;

  /// 待呈現的得標（加入順序，唯讀）。
  List<LBBidWonItem> get items => _items;

  /// 視窗是否呈現中。
  bool get isPresented => _isPresented;

  /// 加入一筆（同 `buyingId` 不重複）並呈現。有變更才通知。
  @internal
  void record(LBBidWonItem item) {
    final exists = _items.any((it) => it.buyingId == item.buyingId);
    if (exists && _isPresented) return;
    if (!exists) _items = List.unmodifiable([..._items, item]);
    _isPresented = true;
    notifyListeners();
  }

  /// 「確定」：先清空關閉，再以全部 `buyingId` 呼叫 [forward] 一次（不等結果，同網頁）。[forward]
  /// 同步丟錯只記 debug log——確認失敗 MUST NOT 讓 items 回來。
  @internal
  void confirm(void Function(List<String> buyingIds) forward) {
    final ids = _items.map((it) => it.buyingId).toList(growable: false);
    clear();
    if (ids.isEmpty) return;
    try {
      forward(ids);
    } catch (e) {
      debugPrint('[DefaultBidWon] confirm requester threw: $e');
    }
  }

  /// 「取消」/ 換片：清空關閉，不確認。有變更才通知。
  void clear() {
    if (_items.isEmpty && !_isPresented) return;
    _items = const [];
    _isPresented = false;
    notifyListeners();
  }
}
