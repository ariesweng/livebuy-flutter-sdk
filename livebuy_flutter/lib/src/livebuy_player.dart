import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'models.dart';

// MARK: - LivebuyPlayerCore (Flutter widget — headless bridge)
//
// decouple-ui-from-logic: this widget is a thin bridge to the native
// player view. Per
// `openspec/changes/decouple-ui-from-logic/specs/component-contracts/spec.md`
// §Player 元件契約 + §四端命名映射.
//
// Two event streams flow through the bridge:
//   1. Per-view "deprecated" callbacks (stateChange / productTap / pollReceived
//      / error) — exposed as widget props for backward compat. These flow
//      through the EventChannel `tv.livebuy/player_events`.
//   2. The full 38-event SDK surface (including the 19 new decouple-ui events
//      such as CHAT_TOGGLE / DISMISS_REQUEST / PRODUCT_PANEL_TOGGLE) — these
//      flow through the SDK MethodChannel `tv.livebuy/sdk` reverse-call
//      `onSdkEvent`, consumed via `LivebuySDK.setListener(...)` from
//      `livebuy_sdk.dart`. Host apps should subscribe at the SDK level
//      (once per session), not per-view.

const _eventChannel = EventChannel('tv.livebuy/player_events');

// MARK: - Bridge-level types for simulate* parameters (expand-simulate-bridge-parity)

/// Reduced LBSpec shape — only fields available at the bridge layer.
class LBBridgeSpec {
  final String id;
  final String name;
  final String? priceShow;

  const LBBridgeSpec({required this.id, required this.name, this.priceShow});

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        if (priceShow != null) 'priceShow': priceShow,
      };
}

/// Reduced LBHotItem shape for bridge simulate* calls.
/// Note: `watchNum` is NOT present (not returned by the API `hot[]` response
/// per SDK invariant — see CLAUDE.md). Pass `duration` as a formatted string,
/// e.g. `"38:36"`.
class LBBridgeHotItem {
  final String id;
  final String title;
  final String cover;
  final String? duration;

  const LBBridgeHotItem(
      {required this.id,
      required this.title,
      required this.cover,
      this.duration});

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'cover': cover,
        if (duration != null) 'duration': duration,
      };
}

/// Reduced LBVideoItem shape for Widget simulate* calls.
class LBBridgeVideoItem {
  final String id;
  final String title;
  final String cover;
  final String? liveurl;
  final String? playbackurl;
  final int? liveStatus;

  const LBBridgeVideoItem(
      {required this.id,
      required this.title,
      required this.cover,
      this.liveurl,
      this.playbackurl,
      this.liveStatus});

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'cover': cover,
        if (liveurl != null) 'liveurl': liveurl,
        if (playbackurl != null) 'playbackurl': playbackurl,
        if (liveStatus != null) 'liveStatus': liveStatus,
      };
}

// MARK: - Sub-controllers (expand-simulate-bridge-parity)

/// Convert [LBProduct] to a bridge-safe map for MethodChannel transport.
///
/// product-bridge-data-core: serializes the full field set (camelCase keys
/// per design D1) incl. nested [LBProduct.specifications] / [specOptions].
/// `soldOut` / `isHot` keep the existing Flutter bridge bool convention
/// (`!= 0`); the new `isOutSoon` / `isAwait` / `isAwaitNotice` follow the
/// same bool style for same-platform consistency. `narrateStatus` stays Int.
Map<String, dynamic> _productToMap(LBProduct p) => {
      'id': p.id,
      'goodsNo': p.goodsNo,
      'name': p.name,
      'price': p.price,
      'priceShow': p.priceShow,
      'originalPrice': p.originalPrice,
      'originalPriceShow': p.originalPriceShow,
      'stock': p.stock,
      'pic': p.pic,
      'photos': p.photos,
      'brief': p.brief,
      // add-product-description-core-flutter: camelCase key, always present (possibly "").
      'description': p.description,
      'goodsGpn': p.goodsGpn,
      'soldOut': p.soldOut != 0,
      'isHot': p.isHot != 0,
      'isOutSoon': p.isOutSoon != 0,
      'narrateStatus': p.narrateStatus,
      // Goods conclusion fields (goods-conclusion-fields spec) — bools (camelCase).
      'canView': p.canView,
      'canBuy': p.canBuy,
      'isNarrating': p.isNarrating,
      'needLabel': p.needLabel,
      'label': p.label,
      'isAwait': p.isAwait != 0,
      'isAwaitNotice': p.isAwaitNotice != 0,
      'beginTime': p.beginTime,
      'endTime': p.endTime,
      'diversionUrl': p.diversionUrl,
      'specifications': p.specifications.map((s) => s.toMap()).toList(),
      'specOptions': p.specOptions.map((o) => o.toMap()).toList(),
      // add-product-video-id-core-flutter: cross-video product reference
      // (other_goods[] only, camelCase per design D1). Round-trips through
      // native `flutterLBProductFromArgs` (iOS) / `lbProductFrom` (Android)
      // so `simulateProductTap` can drive an other_goods換片 test scenario.
      'videoId': p.videoId,
    };

/// Test-only accessor for [_productToMap] (the bridge serialization used by
/// every `simulate*ProductTap` / `simulateAddCart` / `simulateRestockNotice`
/// dispatch). Per `docs/unit-test-discipline.md` `*ForTesting` naming. Not
/// part of the public API.
@visibleForTesting
Map<String, dynamic> productToMapForTesting(LBProduct p) => _productToMap(p);

class ChatViewController {
  MethodChannel? _channel;
  void _attach(MethodChannel ch) => _channel = ch;

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) async =>
      await _channel?.invokeMethod(method, args);

  /// Simulate user submitting a chat message. Gated by SDK `canSend` state.
  Future<void> simulateSendTap(String text, {int? eventId}) => _invoke(
      'chatView_simulateSendTap',
      eventId != null ? {'text': text, 'eventId': eventId} : {'text': text});

  /// Simulate user scrolling to top to load older chat history.
  Future<void> simulateLoadHistoryTap() =>
      _invoke('chatView_simulateLoadHistoryTap');

  /// Simulate user tapping "join event" on an event-begin chat row.
  Future<void> simulateEventJoinTap(int eid, String keyword) =>
      _invoke('chatView_simulateEventJoinTap', {'eid': eid, 'keyword': keyword});
}

class ProductOverlayController {
  MethodChannel? _channel;
  void _attach(MethodChannel ch) => _channel = ch;

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) async =>
      await _channel?.invokeMethod(method, args);

  /// Simulate user tapping a product anywhere (push card / floating banner).
  Future<void> simulateProductTap(LBProduct product) =>
      _invoke('productOverlay_simulateProductTap', _productToMap(product));

  /// Simulate user explicitly dismissing the push card (× button).
  Future<void> simulatePushCardDismiss() =>
      _invoke('productOverlay_simulatePushCardDismiss');

  /// Simulate toggling the product list panel open / closed.
  Future<void> simulatePanelToggle() =>
      _invoke('productOverlay_simulatePanelToggle');
}

class ProductListPanelController {
  MethodChannel? _channel;
  void _attach(MethodChannel ch) => _channel = ch;

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) async =>
      await _channel?.invokeMethod(method, args);

  /// Simulate user tapping a product in the list.
  Future<void> simulateProductTap(LBProduct product) =>
      _invoke('productListPanel_simulateProductTap', _productToMap(product));

  /// Simulate user tapping add-to-cart for a product with optional spec.
  Future<void> simulateAddCart(LBProduct product, {LBBridgeSpec? spec}) =>
      _invoke('productListPanel_simulateAddCart', {
        'product': _productToMap(product),
        if (spec != null) 'spec': spec.toMap(),
      });

  /// Simulate user tapping restock-notification for a sold-out product.
  Future<void> simulateRestockNotice(LBProduct product) =>
      _invoke('productListPanel_simulateRestockNotice', _productToMap(product));
}

class OperationPanelController {
  MethodChannel? _channel;
  void _attach(MethodChannel ch) => _channel = ch;

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) async =>
      await _channel?.invokeMethod(method, args);

  Future<void> simulateGoodsTap() =>
      _invoke('operationPanel_simulateGoodsTap');
  Future<void> simulateChatToggleTap() =>
      _invoke('operationPanel_simulateChatToggleTap');
  Future<void> simulateLikeTap() => _invoke('operationPanel_simulateLikeTap');
  Future<void> simulateShareTap() =>
      _invoke('operationPanel_simulateShareTap');
  Future<void> simulateSubtitleToggleTap() =>
      _invoke('operationPanel_simulateSubtitleToggleTap');
  Future<void> simulateServiceLinkTap() =>
      _invoke('operationPanel_simulateServiceLinkTap');
  Future<void> simulateMoreTap() => _invoke('operationPanel_simulateMoreTap');
  Future<void> simulateGuestNameEditTap() =>
      _invoke('operationPanel_simulateGuestNameEditTap');
  Future<void> simulateSkipStartTap() =>
      _invoke('operationPanel_simulateSkipStartTap');
  Future<void> simulateBackToLiveTap() =>
      _invoke('operationPanel_simulateBackToLiveTap');
}

class VideoInfoPanelController {
  MethodChannel? _channel;
  void _attach(MethodChannel ch) => _channel = ch;

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) async =>
      await _channel?.invokeMethod(method, args);

  Future<void> simulateSubscribeTap() =>
      _invoke('videoInfoPanel_simulateSubscribeTap');
  Future<void> simulateServiceLinkTap() =>
      _invoke('videoInfoPanel_simulateServiceLinkTap');
  Future<void> simulateShopTap() => _invoke('videoInfoPanel_simulateShopTap');
  Future<void> simulateDismiss() => _invoke('videoInfoPanel_simulateDismiss');

  /// [tab] must be `"info"` (default) or `"notice"`. Guarded by SDK: notice
  /// tab is a no-op when no notice content is available.
  Future<void> simulateTabChange(String tab) =>
      _invoke('videoInfoPanel_simulateTabChange', {'tab': tab});
}

class EndScreenController {
  MethodChannel? _channel;
  void _attach(MethodChannel ch) => _channel = ch;

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) async =>
      await _channel?.invokeMethod(method, args);

  Future<void> simulateCancelTap() =>
      _invoke('endScreen_simulateCancelTap');

  /// Simulate user tapping a hot-recommendation card.
  /// Note: `watchNum` is not available at bridge level — omit or pass `null`.
  Future<void> simulateHotItemTap(LBBridgeHotItem item) =>
      _invoke('endScreen_simulateHotItemTap', item.toMap());
}

// MARK: - Controller

class LivebuyPlayerController {
  MethodChannel? _channel;

  // Sub-component controllers (expand-simulate-bridge-parity)
  final chatView = ChatViewController();
  final productOverlay = ProductOverlayController();
  final productListPanel = ProductListPanelController();
  final operationPanel = OperationPanelController();
  final videoInfoPanel = VideoInfoPanelController();
  final endScreen = EndScreenController();

  void _attach(MethodChannel ch) {
    _channel = ch;
    chatView._attach(ch);
    productOverlay._attach(ch);
    productListPanel._attach(ch);
    operationPanel._attach(ch);
    videoInfoPanel._attach(ch);
    endScreen._attach(ch);
  }

  /// Test-only hook mirroring the library-private [_attach] (which is called in
  /// production by `_LivebuyPlayerCoreState._onPlatformViewCreated` with the
  /// per-view channel `tv.livebuy/player_$id`). PlatformViewsService is
  /// unavailable in unit tests, so this attaches the controller to a known test
  /// channel so its method-channel dispatch (e.g. [notifyPictureInPictureModeChanged])
  /// can be driven. Per `docs/unit-test-discipline.md` `*ForTesting` naming;
  /// not part of the public API.
  @visibleForTesting
  void attachForTesting(MethodChannel ch) => _attach(ch);

  Future<void> play() => _invoke('play');
  Future<void> pause() => _invoke('pause');
  Future<void> setMuted(bool muted) => _invoke('setMuted', {'muted': muted});

  /// Absolute seek (VOD-1; parity iOS `Player.seek(seconds:)` / Android
  /// `LivebuyPlayerView.seek(seconds:)`).
  ///
  /// [liveStatus] / [duration] are OPTIONAL VOD-scrub gate context
  /// (flutter-vod-playback-progress-core). When [liveStatus] is supplied, this
  /// method pre-gates in Dart via [vodScrubAllowed] BEFORE touching the method
  /// channel — a failed gate is a silent no-op (the `Future` resolves
  /// immediately without invoking the channel), the same best-effort posture as
  /// this controller's existing "not attached" no-op elsewhere. Omitting both
  /// params (the default) preserves byte-identical pre-existing forwarding
  /// behavior — native stays the authoritative enforcer wherever it enforces
  /// (iOS today; see the platform's own `seek` gate for the real guarantee).
  /// A host typically supplies `liveStatus` from the latest
  /// `LBPlayerChannelInfo.liveStatus` (`onChannelChange`) and `duration` from
  /// the latest `LBPlaybackProgress.duration` (`onPlaybackProgressChange`).
  Future<void> seek(double seconds, {int? liveStatus, double? duration}) {
    if (liveStatus != null && !vodScrubAllowed(liveStatus, duration ?? 0)) {
      return Future.value();
    }
    return _invoke('seek', {'seconds': seconds});
  }

  /// Relative seek (VOD-1 control exit; parity iOS `Player.seekBy(_:)` —
  /// clamped to `[0, duration]` natively on iOS; the Android bridge composes an
  /// equivalent clamp from existing `play()`/`pause()`/`seek()`/`playbackProgress`
  /// — see `flutter-vod-playback-progress-core`). Same optional gate params /
  /// silent-no-op-on-failed-gate posture as [seek].
  Future<void> seekBy(double seconds, {int? liveStatus, double? duration}) {
    if (liveStatus != null && !vodScrubAllowed(liveStatus, duration ?? 0)) {
      return Future.value();
    }
    return _invoke('seekBy', {'seconds': seconds});
  }

  /// Toggle play ⇄ pause (VOD-1 control exit; parity iOS `Player.togglePlayPause()`
  /// — the Android bridge composes an equivalent toggle from existing
  /// `play()`/`pause()`/`playbackProgress.isPlaying` — see
  /// `flutter-vod-playback-progress-core`).
  Future<void> togglePlayPause() => _invoke('togglePlayPause');

  /// Send chat. `eventId` is forwarded as `event_id` for event-begin replies
  /// (per spec §LBPushMsg event 欄位 + sendChat extension).
  Future<void> sendChat(String message, {int? eventId}) =>
      _invoke('sendChat',
          eventId != null && eventId > 0
              ? {'message': message, 'eventId': eventId}
              : {'message': message});

  Future<void> load(String videoId) =>
      _invoke('load', {'videoId': videoId});
  Future<void> unload() => _invoke('unload');
  Future<void> skipStart() => _invoke('skipStart');
  Future<void> cancelAutoNext() => _invoke('cancelAutoNext');
  Future<void> requestEventJoin(int eid, String keyword) =>
      _invoke('requestEventJoin', {'eid': eid, 'keyword': keyword});

  /// 查看購物車 CTA → core seam（emit `VIEW_CART`，notification / 非 navigation /
  /// 不 auto-PiP）。[productId] 為商品詳情頁 CTA 點擊的商品 id；商品列表底部 CTA 省略
  /// （傳 null → native 省略 `product_id` key）。`video_id` 由 native 解析。對應
  /// native `Player.requestViewCart(productId:)`（view-cart-event-core）。
  Future<void> requestViewCart({String? productId}) =>
      _invoke('requestViewCart',
          productId != null ? {'productId': productId} : const {});

  /// 直播抽獎「停留補登」上報（fire-and-forget）。參加抽獎的第二入口：達到停留門檻後
  /// 補登參加票。[eventId] 須 >0（否則 native no-op）；[stayTime] 為 host 計算的已觀看
  /// 秒數（選填）。SDK 自動帶 video_id / name / guest_id / token；端點恆 200，中獎結果
  /// 走 WIN_RECEIVED。對應 native `reportEventStay(eventId:stayTime:)`。
  Future<void> reportEventStay(int eventId, {int? stayTime}) =>
      _invoke('reportEventStay',
          stayTime != null
              ? {'eventId': eventId, 'stayTime': stayTime}
              : {'eventId': eventId});

  /// 直播抽獎「進行中活動」唯讀快照 accessor（active-event-accessor-flutter-core，
  /// parity iOS `activeEvents()` / Android `activeEvents()` / RN
  /// `activeEvents(): Promise<LBActiveEvent[]>`）。
  ///
  /// 讓「中途進場」host——於活動已開始後才裝 `LBEventListener`、因而 miss 掉 fire-once
  /// `ACTIVE_EVENT_STARTED` 通知——主動拉取當前進行中活動快照，補齊 push 型事件的
  /// late-subscriber 盲點。唯讀、無副作用、不觸發網路；回傳反映最近一次
  /// `POST /sdk/video/goods` `event[]` 快照（活動已結束 → goods 不再回該 event →
  /// 快照中缺席）。
  ///
  /// 每筆 [LBActiveEvent] 為既有 model（`{ id, title, keyword?, duration, surplus,
  /// award }`），**不含** `stayTime`（turnkey 內部停留門檻——native 序列化已排除）。
  /// `keyword` 為 optional（native 為 null / 空時省略 key → `LBActiveEvent.fromMap` 讀
  /// 為 `null`，語意「無可參加 keyword」）。
  ///
  /// 無進行中活動 / controller 未 attach（`_channel == null`）/ native 回 `null` 或
  /// 非 `List` → 回傳 `[]`（不拋錯）。因 Flutter `invokeMethod` 天然回傳 `Future`，
  /// accessor 直接落在既有 per-view method channel 上（`tv.livebuy/player_$id`）。
  Future<List<LBActiveEvent>> activeEvents() async {
    final raw = await _channel?.invokeMethod('activeEvents');
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => LBActiveEvent.fromMap(Map<Object?, Object?>.from(e)))
        .toList();
  }

  /// player-scoped 已驗證暱稱設定（`guest-nickname-checkname-on-set-flutter` +
  /// `guest-nickname-verified-fails-loudly-flutter`，parity iOS
  /// `LivebuyPlayerViewController.setGuestNicknameVerified(_:)` / Android
  /// `LivebuyPlayerView.setGuestNicknameVerified(name:)`）。
  ///
  /// 在 commit（持久化 + 廣播）之前，native 端先對**目前 video** 呼叫既有 `ChatClient.checkName`
  /// 驗證該名稱是否可用，讓「設定暱稱」這個動作本身能回報結果。此方法與既有
  /// `LivebuySDK.setGuestNickname(String name)`（`tv.livebuy/sdk` method channel，同步、無驗證）是
  /// **平行**入口——不改動、不取代後者。
  ///
  /// ## 「Future 未 reject」⟺「暱稱已提交」
  ///
  /// 任何**沒有**完成 commit（持久化 + `AUTH_STATE_CHANGED` 廣播）的路徑都會 reject，**包含 Dart
  /// 層自己的路徑**——沒有任何「沒提交卻正常 resolve」的縫隙。因此呼叫端可以直接把「正常 resolve」
  /// 當成功處理（關閉暱稱 modal、續作後續流程），不需要其他判準
  /// （`guest-nickname-verified-fails-loudly-flutter`；core 側契約見
  /// `guest-nickname-verified-fails-loudly-core`）。
  ///
  /// ## 失敗時的 `PlatformException.code`
  ///
  /// 全部落在既有 per-view method channel（`tv.livebuy/player_$id`）上，`code` 兩兩互斥，呼叫端可
  /// 僅憑 `e.code` 決定補救動作：
  ///
  /// | `code` | 意思 | host 該做什麼 |
  /// |---|---|---|
  /// | （不 reject） | 名稱可用、已持久化 + 已廣播 | 關 modal、續作 |
  /// | `NICKNAME_SET_PRECONDITION_FAILED` | native 前置條件不成立，**checkName 根本沒送出**（名稱 trim 後為空 / 播放器尚未 `load` 任何影片） | **重試不會成功**——先修正參數或呼叫時機 |
  /// | `NOT_CONFIGURED` | `LivebuySDK.configure(...)` 尚未成功返回，同樣沒送出任何請求 | 先完成 configure |
  /// | `NOT_ATTACHED` | controller 尚未 attach 任何 per-view channel（platform view 未建立） | 等 player widget 建立完成再呼叫 |
  /// | `GUEST_NAME_TAKEN` | checkName 回 403，名稱已被使用；不持久化、不廣播 | 留在輸入框、提示換一個名字 |
  /// | `CHECKNAME_FAILED` | 請求**送出了但結果未定**（網路 / server error）；不持久化、不廣播 | 可重試，文案應與「被取走」不同 |
  /// | `BAD_ARG` | 缺 `name` 參數（呼叫端誤用） | 修正呼叫 |
  ///
  /// 前三者是同一個大類——**什麼都沒送出、沒有任何東西被驗證或提交**——與 `GUEST_NAME_TAKEN`
  /// （送出了、被拒）和 `CHECKNAME_FAILED`（送出了、結果未定）是三個不同的類別。**不要**把
  /// `NICKNAME_SET_PRECONDITION_FAILED` 當成可重試錯誤處理。
  ///
  /// ⚠️ `NOT_ATTACHED` 由 **Dart 端本地 raise，沒有 channel round-trip**（native 完全不被觸及，
  /// 也不會送出任何 method call）——它不是任一端 native plugin 會回的 code。之所以仍用
  /// [PlatformException] 而非 `StateError`，是為了讓呼叫端只需要**一種** catch 形狀就能處理
  /// 「暱稱沒設成功」的全部原因。此路徑在 drop-in（`LivebuyPlayer` turnkey 容器）不可達——
  /// controller 於 platform view 建立時即 attach、暱稱 modal 只在已載入影片的播放器上開。
  ///
  /// 此前置檢查寫在本方法自身，**不**改動共用的 `_invoke` helper——`play()` / `pause()` /
  /// `setMuted()` / `seek()` / `load()` 等經同一個 helper 轉發的方法，在未 attach 時的既有行為
  /// （靜默略過）逐字不變：它們的契約是 best-effort 轉發、結果走事件回報，並沒有「未 reject ⟺
  /// 已完成」這回事可違反。
  ///
  /// ```dart
  /// try {
  ///   await controller.setGuestNicknameVerified(name);
  ///   // 成功：已持久化、已廣播
  /// } on PlatformException catch (e) {
  ///   if (e.code == 'GUEST_NAME_TAKEN') {
  ///     // 被取走：留在輸入框、換一個名字
  ///   } else if (e.code == 'CHECKNAME_FAILED') {
  ///     // 送出了但結果未定：可重試
  ///   } else {
  ///     // NICKNAME_SET_PRECONDITION_FAILED / NOT_CONFIGURED / NOT_ATTACHED / BAD_ARG：
  ///     // 什麼都沒送出，重試沒有意義——這是呼叫端自己要修的
  ///   }
  /// }
  /// ```
  Future<void> setGuestNicknameVerified(String name) async {
    // guest-nickname-verified-fails-loudly-flutter: 未 attach 時 `_invoke` 會 `await null` →
    // Future 正常 resolve，呼叫端會把「什麼都沒發生」讀成「暱稱已設定」。這是 core 這次修掉的
    // 缺陷在 Dart 層的同型站點，且**即使 core 修好也仍然靜默**（根本沒走到 native），所以必須
    // 在這裡自己擋。刻意只擋這一支方法 —— `_invoke` 的跨方法語意保持不變（見上方 doc）。
    if (_channel == null) {
      throw PlatformException(
        code: 'NOT_ATTACHED',
        message: 'LivebuyPlayerController is not attached to a player view yet; '
            'the nickname was NOT submitted. Call this after the player widget '
            'has been built (its platform view created).',
      );
    }
    await _invoke('setGuestNicknameVerified', {'name': name});
  }

  /// Template 於 LBWinSheet 確認 contact 後呼叫。未攔截時 SDK 原生發 POST /sdk/video/claim
  /// 並以 AWARD_CLAIM_RESULT 回報;contact.email 必填(product/discount 皆需),
  /// 僅在前序 interceptor 已提供時可省略。
  ///
  /// ## AWARD_CLAIM_RESULT 的 params 契約（win-claim-email-result-params-flutter-core）
  ///
  /// 領獎結束後 SDK 以**通知型**事件 `LBEvent.awardClaimResult` 派發結果,`params` 帶**完整獎品與
  /// 活動資訊**供 host 自行處理後續(例如加入自家購物車、導向自家獎品頁)。Flutter 端 `params` 為
  /// 裸 `Map<String, Object?>`(統一 listener 的全部事件共用同一泛型入口,**無 typed params
  /// class**),故以下表為欄位的權威清單。扁平 snake_case,對齊 `WIN_RECEIVED` 風格。
  ///
  /// **記憶體來源**(成功 / 失敗皆可靠):
  ///
  /// | key | Dart 型別 | 來源 | 何時有 |
  /// |---|---|---|---|
  /// | `status` | `String` | — | 恆有 |
  /// | `award_type` | `String` | `winner.award.type` | 恆有 |
  /// | `winner_id` | `String` | `winner.id`(領獎票券 id,供 host 串回稍早的 `WIN_RECEIVED`) | 恆有 |
  /// | `event_title` | `String` | `winner.title` | **非空才帶** |
  ///
  /// **API 回應來源**(僅領獎成功時存在):
  ///
  /// | key | Dart 型別 | 來源 | 何時有 |
  /// |---|---|---|---|
  /// | `event_id` | `int` | 回應 `event_id` | 僅成功 |
  /// | `award_name` | `String` | 回應 `name` | 僅成功且非空 |
  /// | `award_image_url` | `String` | 回應 `image_url` | 僅成功且非空 |
  /// | `award_stock` | `int` | 回應 `stock` | 僅成功且有值(**含 `0`**＝已無庫存) |
  /// | `award_code` | `String` | 回應 `code` | **discount-only**,成功且非空 |
  /// | `award_expiration` | `String` | 回應 `expiration_time` | **discount-only**,成功且非空 |
  ///
  /// 規則:
  ///
  /// - **省略規則**:值為 nil 或空字串的欄位,SDK **整個省略該 key**(Dart 端 `params['x']` 讀為
  ///   `null`);SDK **不會**以空字串佔位。要分辨「省略」與「顯式 null」請用 `params.containsKey('x')`
  ///   ——Dart 對缺 key 與顯式 null 皆回 `null`。
  /// - **失敗白名單**:領獎失敗(`failed` / `unknown_<code>`,**含 `contact.email` 缺漏的 fail-fast
  ///   ——連 API 都沒送出)時,`params` **只帶四個記憶體來源 key**,不含任何 API 回應來源欄位。
  /// - **discount-only**:`award_code` / `award_expiration` 只在 discount award 出現;product award
  ///   不帶這兩欄。
  /// - **`award_stock` 的 `0` 是有效值**(代表已無庫存),不可當成缺值。
  /// - **副作用邊界**(`award-product-auto-cart` 限縮後):SDK **MUST NOT 導頁**、**MUST NOT 渲染任何
  ///   UI**;**discount 型**獎品 SDK 不加入購物車。**product 型獎品為明確例外**——core 會在領獎成功後
  ///   **自動**呼叫 addcart 把獎品加入後端結帳清單。除此之外,拿到獎品資訊後要做什麼完全由 host 決定。
  ///
  /// ## product 型獎品的雙事件序列（`award-product-auto-cart`）
  ///
  /// 1. 領獎 API 成功 → SDK **立即**派 `AWARD_CLAIM_RESULT`（`status == 'claimed'`）。此事件
  ///    **不等待** addcart 往返,其 `status` 也 **MUST NOT** 因後續加購失敗被改判。
  /// 2. addcart 成功 → SDK **接著**派一筆 `CART_ADD_REQUEST`,其 `params` 多帶
  ///    `award_winner_id`（＝本次的 `winner_id`）。typed 讀法見
  ///    [LBCartAddRequest.awardWinnerId]（一般加購該欄為 `null`,**不是** `''`）。
  /// 3. addcart **失敗** → SDK **不派任何事件**（含不派任何加購失敗事件）。因此 host 收到
  ///    `AWARD_CLAIM_RESULT(status: 'claimed', award_type: 'product')` 卻**沒有**收到配對的
  ///    `CART_ADD_REQUEST`,即代表**獎品沒進結帳清單**。此情境下 host 只有獎品名稱與圖
  ///    （`award_name` / `award_image_url`）、**沒有任何 host 側商品 / 規格 id**,故無法自行把獎品
  ///    補進自家購物車,只能呈現「已領取、後續另行處理」——這是刻意的最小對外面積取捨,非疏漏。
  ///
  /// ⚠️ 因此 host **MUST NOT** 在收到 product 型 `AWARD_CLAIM_RESULT` 時自行再打一次後端加購——
  /// 那會**重複加購**。要加進**自家** app 的購物車,請以 `CART_ADD_REQUEST` 為準（該事件才帶
  /// `goods_no` / `specification_no` 等 host 側 id）。
  ///
  /// 取值慣例(經 StandardMessageCodec 反序列化,數字為 `int`、字串為 `String`):
  ///
  /// ```dart
  /// LivebuySDK.setListener((event) async {
  ///   if (event.eventName == LBEvent.awardClaimResult) {
  ///     final p = event.params;
  ///     final status = LBAwardClaimStatus.fromWire(p['status'] as String);
  ///     if (status == LBAwardClaimStatus.claimed) {
  ///       final name = p['award_name'] as String?;      // 缺 key → null
  ///       final stock = p['award_stock'] as int?;       // 0 亦為有效值
  ///       final code = p['award_code'] as String?;      // discount-only
  ///       // …呈現獎品 / 導向獎品頁。
  ///       // product 型**不要**在這裡再打一次後端加購——core 已自動加購,
  ///       // 之後會另派一筆帶 award_winner_id 的 CART_ADD_REQUEST。
  ///     }
  ///   }
  ///   if (event.eventName == LBEvent.cartAddRequest) {
  ///     final req = LBCartAddRequest.fromMap(event.params);
  ///     if (req?.awardWinnerId != null) {
  ///       // 這筆是獎品自動加購,可用 awardWinnerId 串回上面的 winner_id
  ///     }
  ///   }
  ///   return LBEventReply.acknowledge;
  /// });
  /// ```
  ///
  /// 權威來源為 `openspec/specs/event-interceptor/spec.md` §通知型事件 的 `AWARD_CLAIM_RESULT`
  /// 條目與 `openspec/specs/component-contracts/spec.md` §中獎領獎流程契約;本表為 host 便利複本,
  /// 四端(iOS / Android / RN / Flutter)欄位完全一致。
  Future<void> requestAwardClaim(LBWinner winner, {LBAwardClaimInput? contact}) =>
      _invoke('requestAwardClaim', {
        'winner': winner.toMap(),
        if (contact != null) 'contact': contact.toMap(),
      });

  /// v1.x scope deferred — emits a debugPrint and returns immediately.
  Future<void> minimize() async {
    debugPrint('LivebuyPlayerCore.minimize() not implemented in v1.x; '
        'deferred to next UI propose (in-app PiP).');
  }

  /// v1.x scope deferred — no-op.
  Future<void> expand() async {
    debugPrint('LivebuyPlayerCore.expand() not implemented in v1.x; '
        'deferred to next UI propose (in-app PiP).');
  }

  /// Forward the host Android Activity's own `onPictureInPictureModeChanged(...)`
  /// confirmation into the wrapped native player view
  /// (flutter-android-pip-mode-forward-core; depends on Android core
  /// `LivebuyPlayerView.notifyPictureInPictureModeChanged`, android-view-mode-pip-forward-core).
  ///
  /// **Android-only / View-mode host responsibility.** Android delivers the PiP
  /// entry/exit confirmation callback ONLY to the Activity that owns it — a
  /// Flutter platform view embedded in your host `FlutterActivity` cannot observe
  /// it. Call this from your host `Activity.onPictureInPictureModeChanged`
  /// override (after `super`) so PiP-dependent SDK behaviour works:
  ///   - watch-time (`person_time` / `person_duration`, sdk-stat-reporting) stops
  ///     during PiP (PiP is not foreground watching);
  ///   - the IVS live seek-bar / native control chrome stays locked in PiP.
  ///
  /// **iOS: no-op.** iOS drives PiP via `AVPictureInPictureController`'s delegate,
  /// which reaches the SDK regardless of the host container, so there is no
  /// host-forward gap. On non-Android platforms this returns immediately without
  /// touching the method channel (the iOS Flutter plugin does not register this
  /// method; guarding here avoids a `MissingPluginException`). Same platform
  /// convention as `LivebuyPlayerCore.build()`'s `AndroidView` / `UiKitView` split.
  Future<void> notifyPictureInPictureModeChanged(
      bool isInPictureInPictureMode) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    await _invoke('notifyPictureInPictureModeChanged',
        {'isInPictureInPictureMode': isInPictureInPictureMode});
  }

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) async {
    await _channel?.invokeMethod(method, args);
  }
}

// MARK: - Widget

/// The **bare** headless player widget — a thin bridge to the native player
/// view (`UiKitView` / `AndroidView`), zero overlay pixels.
///
/// rename-bare-player-livebuyplayercore-flutter: this widget was previously
/// named `LivebuyPlayer`. The `LivebuyPlayer` name is being **repurposed** for
/// the turnkey drop-in container in a future release (philosophy B, see iOS
/// `introduce-dropin-player-container` design D-0). Use [LivebuyPlayerCore]
/// for the bare bridge widget; existing host code using `LivebuyPlayer(...)`
/// keeps working through a deprecated alias until v2.0.
class LivebuyPlayerCore extends StatefulWidget {
  final String videoId;
  final bool showChat;
  final bool showProducts;
  final bool enablePiP;
  final int autoDismissDelay;
  final LivebuyPlayerController? controller;

  // Deprecated per-view callbacks — v2.0 removal.
  // For the full event surface (chatToggle / productPanelToggle / dismissRequest
  // / etc.), use `LivebuySDK.setListener(...)` from `livebuy_sdk.dart` once
  // at SDK level — events arrive via the `onSdkEvent` reverse method call.
  final void Function(LBPlayerState)? onStateChange;
  final void Function(LBPollResponse)? onPollReceived;
  final void Function(LBError)? onError;
  final void Function(LBProduct)? onProductTap;

  /// upcoming-intro-core-flutter — channel-info forward. Fired when the native
  /// player loads / changes a channel, carrying the LIGHTWEIGHT [LBPlayerChannelInfo]
  /// projection (`publishAt` / `cover` / `start` / `liveStatus` / `title`). The host
  /// feeds these into the `flutter-ui` template's upcoming view-model (the player
  /// state `"awaitingLive"` alone cannot carry the channel fields). Purely additive
  /// — leaving this null is an inert no-op; the existing 4 callbacks are unaffected.
  final void Function(LBPlayerChannelInfo)? onChannelChange;

  /// flutter-vod-playback-progress-core — VOD-1 playback-progress forward.
  /// Fired whenever the native player publishes an [LBPlaybackProgress]
  /// snapshot (iOS: ~1Hz while a non-live VOD/replay stream plays; Android:
  /// whenever the replay-mode flag recomputes — see each platform's own core
  /// spec slice for the exact cadence). Purely additive — leaving this null is
  /// an inert no-op; the existing callbacks are unaffected.
  final void Function(LBPlaybackProgress)? onPlaybackProgressChange;

  /// rb-flutter-subtitle-channel-bridge-core — per-channel VTT subtitle
  /// forward. Fired once per loaded channel (NOT on every state tick) with
  /// the current [LBSubtitleInfo] (`available` / `url`, from
  /// `channel.is_subtitle` / `channel.subtitle_url`). Does NOT carry the
  /// runtime CC on/off toggle — that already reaches any host that calls
  /// `LivebuySDK.setListener(...)` as `LBEvent.subtitleToggle`
  /// (`SUBTITLE_TOGGLE`, `params['enabled']`), no bridge change needed.
  /// Purely additive — leaving this null is an inert no-op; the existing
  /// callbacks are unaffected.
  final void Function(LBSubtitleInfo)? onSubtitleChange;

  const LivebuyPlayerCore({
    super.key,
    required this.videoId,
    this.showChat = true,
    this.showProducts = true,
    this.enablePiP = true,
    this.autoDismissDelay = 5,
    this.controller,
    this.onStateChange,
    this.onPollReceived,
    this.onError,
    this.onProductTap,
    this.onChannelChange,
    this.onPlaybackProgressChange,
    this.onSubtitleChange,
  });

  @override
  State<LivebuyPlayerCore> createState() => _LivebuyPlayerCoreState();
}

class _LivebuyPlayerCoreState extends State<LivebuyPlayerCore> {
  late MethodChannel _methodChannel;
  StreamSubscription<dynamic>? _eventSub;

  @override
  void initState() {
    super.initState();
    _eventSub = _eventChannel.receiveBroadcastStream().listen(_handleEvent);
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    // `release` is the legacy method name (aliased to `unload` in the
    // native bridges for backward compat).
    _methodChannel.invokeMethod('release');
    super.dispose();
  }

  void _onPlatformViewCreated(int id) {
    _methodChannel = MethodChannel('tv.livebuy/player_$id');
    widget.controller?._attach(_methodChannel);
    _methodChannel.invokeMethod('load', {'videoId': widget.videoId});
  }

  @override
  void didUpdateWidget(LivebuyPlayerCore old) {
    super.didUpdateWidget(old);
    if (old.videoId != widget.videoId) {
      _methodChannel.invokeMethod('load', {'videoId': widget.videoId});
    }
  }

  void _handleEvent(dynamic raw) {
    if (raw is! Map) return;
    final event = Map<Object?, Object?>.from(raw);
    final name = event['event'] as String?;
    switch (name) {
      case 'stateChange':
        widget.onStateChange
            ?.call(lbPlayerStateFromString(event['state'] as String));
        break;
      case 'productTap':
        widget.onProductTap?.call(LBProduct.fromMap(event));
        break;
      case 'pollReceived':
        widget.onPollReceived?.call(LBPollResponse.fromMap(event));
        break;
      case 'error':
        widget.onError?.call(lbErrorFromMap(event));
        break;
      case 'channelChange':
        // upcoming-intro-core-flutter — channel-info forward (lightweight
        // projection for the player-side upcoming chrome). Inert when null.
        widget.onChannelChange?.call(LBPlayerChannelInfo.fromMap(event));
        break;
      case 'playbackProgress':
        // flutter-vod-playback-progress-core — VOD-1 playback-progress
        // forward. Inert when null.
        widget.onPlaybackProgressChange?.call(LBPlaybackProgress.fromMap(event));
        break;
      case 'subtitleChange':
        // rb-flutter-subtitle-channel-bridge-core — per-channel VTT subtitle
        // forward (available/url). Inert when null.
        widget.onSubtitleChange?.call(LBSubtitleInfo.fromMap(event));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    const viewType = 'LivebuyPlayerView';
    final creationParams = <String, dynamic>{
      'videoId': widget.videoId,
      'showChat': widget.showChat,
      'showProducts': widget.showProducts,
      'enablePiP': widget.enablePiP,
      'autoDismissDelay': widget.autoDismissDelay,
    };

    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidView(
        viewType: viewType,
        onPlatformViewCreated: _onPlatformViewCreated,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    return UiKitView(
      viewType: viewType,
      onPlatformViewCreated: _onPlatformViewCreated,
      creationParams: creationParams,
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}

// MARK: - Deprecated alias (rename-bare-player-livebuyplayercore-flutter)

/// **Deprecated** — renamed to [LivebuyPlayerCore].
///
/// The `LivebuyPlayer` name is being **repurposed** for the turnkey drop-in
/// container in a future release (philosophy B, see iOS
/// `introduce-dropin-player-container` design D-0). This thin subclass keeps
/// existing host code (`LivebuyPlayer(videoId: ...)`) compiling + running with
/// **byte-equivalent behavior** (it overrides nothing — `is LivebuyPlayerCore`
/// is `true`) for one major transition cycle. It will be **removed at v2.0**,
/// after which the `LivebuyPlayer` name is taken over by the drop-in container.
///
/// Migrate bare-player usage to [LivebuyPlayerCore].
@Deprecated('Renamed to LivebuyPlayerCore; the LivebuyPlayer name is being '
    'repurposed for the turnkey drop-in container in a future release. '
    'Migrate bare-player usage to LivebuyPlayerCore.')
class LivebuyPlayer extends LivebuyPlayerCore {
  const LivebuyPlayer({
    super.key,
    required super.videoId,
    super.showChat,
    super.showProducts,
    super.enablePiP,
    super.autoDismissDelay,
    super.controller,
    super.onStateChange,
    super.onPollReceived,
    super.onError,
    super.onProductTap,
    super.onChannelChange,
    super.onPlaybackProgressChange,
    super.onSubtitleChange,
  });
}

// MARK: - Widget / FloatingWidget (expand-simulate-bridge-parity Tier 2)

/// Controller for [LivebuyWidgetCore]. Exposes simulate* for host-driven UI.
class LivebuyWidgetController {
  MethodChannel? _channel;

  /// widget-bridge-color-core: invoked when carousel / grid `POST /sdk/widget`
  /// completes and the native widget view forwards the web-embed colors
  /// (`widget_color` / `widget_bgcolor`) via the reverse method call
  /// `onWidgetResponse`. Purely additive — leaving this null is a no-op; the
  /// existing simulate* / videoTap / loadMore behavior is unaffected. Raw
  /// passthrough: the SDK does not interpret the colors and never mixes them
  /// with `sdkConfig.theme.primaryColor`. Floating widget
  /// (`POST /sdk/widget/live`) does NOT emit this (no color fields there).
  void Function(LBWidgetColors)? onWidgetResponse;

  void _attach(MethodChannel ch) {
    _channel = ch;
    ch.setMethodCallHandler(_handleReverseCall);
  }

  /// Test-only hook mirroring [_attach] (the library-private wiring is not
  /// reachable from the test target, which has no platform view). Per
  /// `docs/unit-test-discipline.md` `*ForTesting` naming. Not part of the
  /// public API.
  @visibleForTesting
  void attachForTesting(MethodChannel ch) => _attach(ch);

  /// Handle native → Dart reverse method calls on the per-view widget channel.
  Future<Object?> _handleReverseCall(MethodCall call) async {
    switch (call.method) {
      case 'onWidgetResponse':
        final raw = call.arguments;
        if (raw is Map) {
          onWidgetResponse?.call(
            LBWidgetColors.fromMap(Map<Object?, Object?>.from(raw)),
          );
        }
        return null;
      default:
        return null;
    }
  }

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) async =>
      await _channel?.invokeMethod(method, args);

  /// Simulate user tapping a card. Triggers `onVideoTap` + player presenter.
  Future<void> simulateCardTap(LBBridgeVideoItem video) =>
      _invoke('simulateCardTap', video.toMap());

  /// Simulate user closing the widget.
  Future<void> simulateClose() => _invoke('simulateClose');

  /// Simulate a card entering or leaving the visible region. Used by the
  /// host's UI layer to inform the widget's LRU bookkeeping.
  Future<void> simulateCardVisibilityChanged(
          LBBridgeVideoItem video, bool visible) =>
      _invoke('simulateCardVisibilityChanged',
          {'video': video.toMap(), 'visible': visible});
}

/// Controller for [LivebuyFloatingWidget]. Exposes simulate* for host-driven UI.
class LivebuyFloatingWidgetController {
  MethodChannel? _channel;
  void _attach(MethodChannel ch) => _channel = ch;

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) async =>
      await _channel?.invokeMethod(method, args);

  /// Simulate user closing the floating widget.
  Future<void> simulateClose() => _invoke('simulateClose');

  /// Simulate user tapping the floating widget button.
  Future<void> simulateTap() => _invoke('simulateTap');
}

/// Flutter widget wrapping the native widget view (headless bridge).
/// Accepts a [controller] for imperative simulate* calls.
///
/// Renamed from `LivebuyWidget` (rename-bare-widget-to-core-flutter): the
/// `LivebuyWidget` golden name is being repurposed for the turnkey drop-in
/// container in `livebuy_flutter_reference_ui`. See the `@Deprecated`
/// [LivebuyWidget] alias below for the migration path.
class LivebuyWidgetCore extends StatefulWidget {
  final String shopId;
  final LivebuyWidgetController? controller;

  const LivebuyWidgetCore({
    super.key,
    required this.shopId,
    this.controller,
  });

  @override
  State<LivebuyWidgetCore> createState() => _LivebuyWidgetCoreState();
}

class _LivebuyWidgetCoreState extends State<LivebuyWidgetCore> {
  late MethodChannel _methodChannel;

  void _onPlatformViewCreated(int id) {
    _methodChannel = MethodChannel('tv.livebuy/widget_$id');
    widget.controller?._attach(_methodChannel);
  }

  @override
  Widget build(BuildContext context) {
    const viewType = 'LivebuyWidgetView';
    final creationParams = <String, dynamic>{'shopId': widget.shopId};

    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidView(
        viewType: viewType,
        onPlatformViewCreated: _onPlatformViewCreated,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    return UiKitView(
      viewType: viewType,
      onPlatformViewCreated: _onPlatformViewCreated,
      creationParams: creationParams,
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}

/// Deprecated alias for [LivebuyWidgetCore]. The `LivebuyWidget` name is being
/// repurposed for the turnkey drop-in container in `livebuy_flutter_reference_ui`.
/// Migrate bare-widget usage to [LivebuyWidgetCore]. Removed in v2.0.
@Deprecated('Renamed to LivebuyWidgetCore; the LivebuyWidget name is being '
    'repurposed for the turnkey drop-in container in a future release. '
    'Migrate bare-widget usage to LivebuyWidgetCore.')
class LivebuyWidget extends LivebuyWidgetCore {
  const LivebuyWidget({
    super.key,
    required super.shopId,
    super.controller,
  });
}

/// Flutter widget wrapping the native [FloatingWidget] view.
/// Accepts a [controller] for imperative simulate* calls.
class LivebuyFloatingWidget extends StatefulWidget {
  final String videoId;
  final LivebuyFloatingWidgetController? controller;

  const LivebuyFloatingWidget({
    super.key,
    required this.videoId,
    this.controller,
  });

  @override
  State<LivebuyFloatingWidget> createState() => _LivebuyFloatingWidgetState();
}

class _LivebuyFloatingWidgetState extends State<LivebuyFloatingWidget> {
  late MethodChannel _methodChannel;

  void _onPlatformViewCreated(int id) {
    _methodChannel = MethodChannel('tv.livebuy/floating_widget_$id');
    widget.controller?._attach(_methodChannel);
  }

  @override
  Widget build(BuildContext context) {
    const viewType = 'LivebuyFloatingWidgetView';
    final creationParams = <String, dynamic>{'videoId': widget.videoId};

    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidView(
        viewType: viewType,
        onPlatformViewCreated: _onPlatformViewCreated,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    return UiKitView(
      viewType: viewType,
      onPlatformViewCreated: _onPlatformViewCreated,
      creationParams: creationParams,
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}
