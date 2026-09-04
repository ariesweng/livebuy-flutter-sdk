import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:share_plus/share_plus.dart' show Share;
// HIDE the deprecated `LivebuyPlayer` alias the core package still exports (→ `LivebuyPlayerCore`,
// removed at v2.0): this reference-ui package defines the GOLDEN-NAME `LivebuyPlayer` (the
// turnkey container), so importing both packages would otherwise be an ambiguous-import error.
import 'package:livebuy_flutter/livebuy_flutter.dart' hide LivebuyPlayer;
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart';

import '../reference_ui_theme.dart';
import 'chat_composer_bar.dart';
import 'live_now_poll_controller.dart';
import 'reference_ui_design.dart';

// MARK: - LivebuyPlayer — turnkey drop-in player container (Flutter)
//
// The SDK `LivebuyPlayerCore` is a HEADLESS native platform view (video pixels only) and
// `livebuy_flutter_ui` attaches a zero-pixel `DefaultPlayerTemplate`. To SEE player chrome
// (shell / feed-win / product-sheets / moments / gap-surfaces / chat composer) a host must
// overlay the reference-ui pixel surfaces on top of the native view and wire every
// interaction back to the controller / template. That assembly — never built in Flutter
// before (the example rendered the bare `LivebuyPlayerCore`, and this package was an orphan)
// — is what `LivebuyPlayer` PROMOTES into ONE line:
//
//     LivebuyPlayer(videoId: '123')                          // turnkey: all seams defaulted
//     LivebuyPlayer(videoId: '123', config: cfg)             // override only what differs
//
// It is a PURE ASSEMBLY layer (governance: reference-ui MUST NOT add/modify view-models or
// pixels beyond composing existing surfaces): it composes existing reference-ui surfaces +
// existing core `LivebuyPlayerController` forwarders. Dependency direction stays one-way
// `livebuy_flutter_reference_ui → livebuy_flutter_ui → livebuy_flutter`. `LivebuyPlayer` is
// the GOLDEN NAME (design D-0); the bare native view stays `LivebuyPlayerCore` (rename done by
// the prerequisite core change `rename-bare-player-livebuyplayercore-flutter`).
//
// OVERLAY COMPOSITION (D-1): ONE widget tree, ONE `Stack` — the native view at the bottom,
// the pixel surfaces above. They MUST NOT be arranged as gesture-fighting siblings; each
// surface uses its existing `HitTestBehavior` / null-callback inert convention so empty /
// transparent areas pass touches through to the native view below.
//
// TEMPLATE BINDING (R2 — honest boundary): `livebuy_flutter_ui` attaches the
// `DefaultPlayerTemplate` at the SDK-GLOBAL level (via `setListener`); there is currently NO
// public per-player read path (only the test-only `attachedTemplateForTesting`). This
// reference-ui change MUST NOT add a public accessor in the template layer (I7). So the
// container passes `template: null` to the surfaces — each surface degrades to its
// deterministic demo seeds and does not crash. The controller seams (mute / chat / load /
// simulate*) work regardless of the template. A public attached-template read path is a
// documented template-layer follow-up (design Open Question); when it lands, swapping
// `template: null` for that accessor makes the overlays live with zero container restructure.

/// VIDEO_SWITCH 事件的目標影片 id（core 自動接續 / 換片時的 `to_video_id`）。Pure 供單元測 +
/// 容器的換片追蹤共用。`eventName == LBEvent.videoSwitch` 且 `params['to_video_id']` 為非空字串
/// → 回該 id；否則回 null（非換片事件 / 缺值）。容器以此在 core 自動接續後保持 swipe 基準最新
/// （rb-flutter-swipe-prev-after-autoadvance，parity iOS/Android）。
String? videoSwitchToId(String eventName, Map<String, Object?> params) {
  if (eventName != LBEvent.videoSwitch) return null;
  final to = params['to_video_id'];
  return (to is String && to.isNotEmpty) ? to : null;
}

/// 「該不該同步浮卡到接播後影片」的決策（rb-flutter-collapsible-autoadvance-switch-sync，第四條換片同步
/// 路徑；parity iOS / Android / RN `shouldSyncAutoAdvance`）。純函式供單元測 + 容器 `VIDEO_SWITCH` listener
/// 共用一份。回 `true`（同步）僅當 [to] 非 null **且** [to] 與容器 swipe 基準 [currentId] 不同：
/// - **core 自主接播**：core 內部 `load(next)`，**不**經 reference-ui 呼叫 `_switchVideo` / `_notifySwitchedVideo`，
///   故 [currentId]（`_currentVideoId`）仍是接播前那支 id → `to != currentId` → **同步**（更新基準 + 走既有
///   `onVideoSwitchedItem` 出口更新浮卡）。
/// - **使用者互動換片（swipe / hot-pick）**：Dart handler 內**同步**先呼叫 `_switchVideo(to)` / `_notifySwitchedVideo(to)`
///   （兩者第一行皆 `_currentVideoId = id`），而 `_controller.load(to)` 觸發的 `VIDEO_SWITCH` 為**非同步**（跨 native
///   bridge）→ listener 跑時 `to == currentId` → **skip**（不重複 fire、真 cover 不被空 cover 覆蓋、host 不被重複呼叫）。
bool shouldSyncAutoAdvance(String? to, String currentId) =>
    to != null && to != currentId;

/// Host-reply-first / template-reply-fallback priority for the container's wrapper
/// `setListener` closure (rb-flutter-dropin-container-event-forwarding, matching
/// design.md D3 of add-flutter-dropin-container-event-forward-template verbatim).
/// `hostReply` is `null` exactly when the host never installed `config.eventListener`
/// (a configured host's actual reply — even a `passthrough` one — always wins).
LBEventReply resolveContainerEventReply(
  LBEventReply? hostReply,
  LBEventReply templateReply,
) =>
    hostReply ?? templateReply;

/// 組商品分享連結（issue 6）：在 [base]（= `channel.share_url`）後加上商品介紹時間 `t=<beginTime>`（秒）。
/// Pure（無副作用）所以單元測 + host override 共用一份實作（iOS / Android `productShareURLString`
/// parity）。Flutter reference-ui 無系統分享 plugin，故此 helper 供 host 自組連結後分享。
/// - [base] 為空 → 回 `''`。
/// - [beginTime] 為 null 或負 → 回 [base]（不加 `?t=`）。
/// - [base] 已含 query（`?`）→ 用 `&` 串接，否則 `?`。
String productShareUrlString(String base, int? beginTime) {
  if (base.isEmpty) return '';
  if (beginTime == null || beginTime < 0) return base;
  final sep = base.contains('?') ? '&' : '?';
  return '$base${sep}t=$beginTime';
}

/// 頻道分享是否該呈現（dropin-player-default-share-sheet-flutter）：`shareUrl` 非空才呈現（空 → no-op，
/// 不開空 sheet）。Pure 所以決策與測試共用一份。頻道級分享**不**附 `?t=`（與 [productShareUrlString] 區隔）。
bool lbShouldPresentChannelShare(String shareUrl) => shareUrl.isNotEmpty;

/// 留言 pill 預設 gating（純函式，與容器 `onComment` 共用一份；parity iOS / Android / RN 同名）：
/// 暱稱**尚未選名**（`!isLoggedIn && displayName.isEmpty`）→ 回 `true`，容器先呈現 設定暱稱 modal；
/// 已選名（訪客經 `setGuestNicknameVerified` 設名 → displayName 非空）或已登入 → 回 `false`，直接開 composer。
/// host 自訂 `config.onComment` 時 MUST NOT 經此函式（完全接管、不套 gating）。
///
/// R2：Flutter 容器無 public per-player template 讀路徑，故 `displayName` 由容器本地鏡像
/// `_guestNickname` 提供、`isLoggedIn` 在 guest 流程取 `false`（host 登入則自會 override `onComment`）。
bool liveCommentRequiresNickname(bool isLoggedIn, String displayName) =>
    !isLoggedIn && displayName.isEmpty;

/// 留言 pill 預設**登入**閘（純函式，與容器 `onComment` 共用一份；rb-flutter-live-comment-login-gate，
/// 方案 A，parity iOS / Android / RN 同名）：該場直播 `guest_comment == 0` → `chatEnabled == false`
/// （留言 pill 只在 LIVE 出現，故 `!chatEnabled ⟺ guest_comment==0`；Flutter `chatEnabled` 來自 core
/// 已含 `!(isGuest && gc==0)`）且**未登入** → 回 `true`，容器先本地呈現「請先登入」modal
/// （`AuthGateModalView(commentSend)`），MUST NOT 開 composer / 跳暱稱 modal。已登入者一律 `false`
/// （`guest_comment` 只閘訪客）。**登入閘 MUST 優先於暱稱閘**。host 自訂 `config.onComment` 時 MUST NOT
/// 經此函式（完全接管、不套 gating）。
bool liveCommentRequiresLogin(bool isLoggedIn, bool chatEnabled) =>
    !isLoggedIn && !chatEnabled;

/// 訂閱鈕預設**登入**閘（純函式，與容器 `onToggleSubscribe` 共用一份；rb-flutter-subscribe-login-gate，
/// parity iOS / Android / RN 同名）：使用者**未登入** → 回 `true`，容器先本地呈現「請先登入」modal
/// （`AuthGateModalView(subscribe)`），MUST NOT `simulateSubscribeTap()`；已登入 → 回 `false`，直接
/// `simulateSubscribeTap()`（→ core `toggleSubscribe()` + `SUBSCRIBE_CHANGED`）。訂閱要登入，故**只看登入
/// 狀態、不看 chatEnabled**（與留言閘 [liveCommentRequiresLogin] 的雙條件不同——留言可開放訪客，訂閱不行）。
/// host 自訂 `config.onToggleSubscribe` 時 MUST NOT 經此函式（完全接管、不套 gating）。
bool subscribeRequiresLogin(bool isLoggedIn) => !isLoggedIn;

/// 「加入活動」抽獎 CTA 的三層閘決策（rb-flutter-event-join-gate，parity iOS `eventJoinGateDecision` /
/// Android / RN）。加入活動送出的本質**就是一則公開留言**（core `requestEventJoin` → `performSendChat`），
/// 故套與留言送出**一致**的閘，且 **MUST** 共用留言入口的**同一組純函式**（[liveCommentRequiresLogin] /
/// [liveCommentRequiresNickname]）——決策**不複製條件**、一律委派，讓兩入口**永不分歧**。優先序同
/// `onComment`：①**登入閘優先**（訪客 + 該場 `guest_comment==0` ⟺ `!chatEnabled`）→ [EventJoinGateDecision.login]；
/// ②否則暱稱閘（未設名訪客）→ [EventJoinGateDecision.nickname]；③否則 [EventJoinGateDecision.proceed]。
/// Pure（無副作用）→ 可脫離 widget 單元測試。
enum EventJoinGateDecision {
  /// 訪客且該場留言需登入（`!isLoggedIn && !chatEnabled`）→ 先請登入，MUST NOT join / markJoined。
  login,

  /// 未設名訪客（`!isLoggedIn && displayName.isEmpty`，`chatEnabled==true`）→ 先設定暱稱、記 pending
  /// join，MUST NOT join；設名成功後接續完成該次 join。
  nickname,

  /// 已登入 / 已設名 → 直接 join。
  proceed,
}

/// See [EventJoinGateDecision]. **登入閘 MUST 優先於暱稱閘**（非登入不可留言的訪客不該先被叫去設一個
/// 用不到的暱稱）。決策一律委派既有兩純函式，故與留言入口永不分歧。
EventJoinGateDecision eventJoinGateDecision(
    bool isLoggedIn, bool chatEnabled, String displayName) {
  if (liveCommentRequiresLogin(isLoggedIn, chatEnabled)) {
    return EventJoinGateDecision.login;
  }
  if (liveCommentRequiresNickname(isLoggedIn, displayName)) {
    return EventJoinGateDecision.nickname;
  }
  return EventJoinGateDecision.proceed;
}

/// 套用「加入活動」三層閘（rb-flutter-event-join-gate，parity iOS `applyEventJoinGate`）：跑
/// [eventJoinGateDecision]，依決策執行對應副作用（[presentLogin] / [presentNickname] 皆以參數注入 → 本函式
/// 為純控制流、可用 capturing fake 單元測試，無需 widget / template / controller）。回傳是否**已攔截**
/// （`true` → 呼叫端 MUST NOT forward join 到 markJoined / 送出）。[EventJoinGateDecision.nickname] 時把該次
/// `(eid, keyword)` 交給 [presentNickname] 記為 pending join。
bool applyEventJoinGate({
  required bool isLoggedIn,
  required bool chatEnabled,
  required String displayName,
  required int eid,
  required String keyword,
  required void Function() presentLogin,
  required void Function(int eid, String keyword) presentNickname,
}) {
  switch (eventJoinGateDecision(isLoggedIn, chatEnabled, displayName)) {
    case EventJoinGateDecision.login:
      presentLogin();
      return true;
    case EventJoinGateDecision.nickname:
      presentNickname(eid, keyword);
      return true;
    case EventJoinGateDecision.proceed:
      return false;
  }
}

/// 設定暱稱送出後接續 pending 的「加入活動」（rb-flutter-event-join-gate，parity iOS
/// `completePendingEventJoin`）：若存在暱稱閘記下的 [pending] join 意圖，透過注入的 [forwardJoin] **恰送
/// 一次**（呼叫端以 bypass-gate 的 forward 實作 = markJoined + core 送出），回傳是否有 forward。Pure
/// （副作用注入）→ 可用 fake 單測「有 pending → 接續一次」「無 pending → 不送」。
bool completePendingEventJoin(
  ({int eid, String keyword})? pending,
  void Function(int eid, String keyword) forwardJoin,
) {
  if (pending == null) return false;
  forwardJoin(pending.eid, pending.keyword);
  return true;
}

/// 🔴 完成一次被暱稱閘擋下的 pending「加入活動」，並把**三路 funnel** 綁成同一個觸發條件
/// （flutter-event-join-gate-notify-host-on-resume，parity Android `d33ce9d0` / RN `9b6be750` 的 D3）。
///
/// Spec: `openspec/specs/event-join-gate/spec.md`
///   § "host 觀察 callback 的觸發條件 SHALL 與實際 join 一致（Flutter）"
///
/// **它修的缺陷（漏報）**：續作路徑原本是 [_LivebuyPlayerState._submitGuestNickname] 裡的一段 inline
/// lambda，只做了樂觀 `markJoined` + core 送出，**沒有**通知 host 的觀察 hook `config.onJoinEvent`。
/// 被暱稱閘擋下、設名成功後自動接續的那次 join **真的發生了**（CTA 翻「已參加」、core 收到
/// `requestEventJoin`），host 卻收不到任何通知 —— 一個「join 發生了卻不回報」的觀察 hook 就是壞掉。
/// 補上之後 `config.onJoinEvent` 的觸發條件才收成乾淨的 **iff：有 forward ⟺ 有通知**
/// （閘攔截 → 零次；閘放行 → 恰一次；**續作 → 恰一次**）。
///
/// 🔴 **雙送防線 —— [requestEventJoin] 是本函式唯一的 core 出口，MUST NOT 再多接一條。** 呼叫端
/// （容器）把它接到 `_controller.requestEventJoin`。**MUST NOT** 為了「順手也走一次正常路徑」而一併
/// 呼叫 `FeedWinOverlayView.onJoinEventWithKeyword` —— 那在容器裡就是
/// `buildEventJoinSend(_controller.requestEventJoin)`，同一次續作會送出**兩次** `requestEventJoin`
/// （後端收到兩則口令留言），直接違反 `reference-ui-rendering` 的「容器每次 SHALL 只送出一次
/// `requestEventJoin`（no double-send）」。續作路徑的送出 SHALL 維持**恰一次**。
///
/// [notifyHostJoin] 只帶 `eid`（不帶 `keyword`）：`LivebuyPlayerConfig.onJoinEvent` 是已發佈 1.3.0 的
/// `ValueChanged<int>?`，`reference-ui-rendering` 明令 MUST NOT 就地加寬該簽名 —— 正常 CTA tap 路徑
/// （`FeedWinOverlayView._handleJoin` 的 `onJoinEvent?.call(eid)`）亦然。這是既有簽名約束，**不是**
/// 本函式的覆蓋缺口。host 未接（`null`）→ `?.call` 零成本、行為不變。
///
/// 三路順序刻意鏡像 `_handleJoin` 的 1→2→3（樂觀翻轉 → host 觀察 → core 送出）：兩條路徑完成的是
/// **同一件事**，host 從觀察 hook 看到的世界應該一樣。
///
/// **為何是具名純函式**：續作 forward 原本住在容器 `LivebuyPlayer` 的 State private method 裡，而該
/// 容器在測試環境**不可建構**（`LivebuyPlayerController` 走 MethodChannel、無 platform view）——
/// inline lambda 無法被測，這正是本缺陷得以存活的物理位置。抽出後可用 capturing fake 直接釘住
/// 「通知恰一次 / 帶原 eid / 送出恰一次 / 無 pending 則三路皆零」，零 widget、零 controller、零網路
/// （與 [buildEventJoinSend] / [buildAwardClaimSubmit] 同一既定模式）。
///
/// 「恰一次 / 無 pending 則零次」**委派**既有 [completePendingEventJoin]（其簽名與語意不變），本函式
/// 只負責**組合三路**。回傳值原樣透傳「是否有 forward」。
bool completePendingEventJoinNotifyingHost({
  required ({int eid, String keyword})? pending,
  required void Function(int eid) markJoined,
  required void Function(int eid)? notifyHostJoin,
  required EventJoinRequester requestEventJoin,
}) {
  return completePendingEventJoin(pending, (eid, keyword) {
    markJoined(eid);
    notifyHostJoin?.call(eid);
    requestEventJoin(eid, keyword);
  });
}

/// Pure, framework-free foreground-resume state machine — the Flutter Dart mirror of iOS
/// `LivebuyReferenceUI/Container/LivebuyPlayer.swift`'s `ForegroundResumeController`
/// (`ios-refui-pip-pause-foreground-resume`). It closes the SAME frozen-frame gap on **iOS**:
/// while a Flutter drop-in `LivebuyPlayer` is playing, backgrounding the app makes the wrapped
/// core auto-enter AVKit OS PiP; if the user PAUSES inside the PiP window and returns to the app,
/// AVKit's PiP restore only re-parents the picture — it does NOT un-pause the stream the user
/// paused — so the video freezes. Nobody calls `play()`. This controller supplies the missing
/// resume.
///
/// The two latches mirror iOS exactly:
///   - [_armed] — was the player playing when we LEFT the foreground? The resume gate. It MUST be
///     a was-playing latch, NOT a live `playerState == paused` check: the IVS live backend keeps
///     `playerState` stale at `playing` after a pause (it has no `paused` mapping), so a `paused`
///     gate would never fire for live.
///   - [_resumeOnPiPExit] — set ONLY when we return to the foreground while STILL in real OS PiP.
///     At that instant AVKit has not finished its PiP restore, so resuming immediately could race
///     it; instead we defer the resume to the moment PiP actually ends
///     (`PIP_STATE_CHANGE active→false` → [pipDidExit]). Because it is set only in the foreground,
///     a PiP window CLOSED while the app is still backgrounded leaves it false → no spurious resume.
///
/// [resume] is the idempotent core `LivebuyPlayerController.play()` (unfreezes AVPlayer VOD and IVS
/// live alike; a no-op if the user never actually paused in PiP). The three seams ([isPlaying] /
/// [isInPiP] / [resume]) are injected closures with no Flutter widget / `BuildContext` dependency,
/// so every branch is unit-testable in isolation (`internal-testability`), same convention as
/// `PreviewPlaybackController` in `looping_video_view.dart`.
///
/// This behavior is **iOS-gated** — the container only constructs and drives this controller on
/// iOS. Android is N/A (no AVKit re-parent; ExoPlayer pauses/resumes honestly), so the frozen-frame
/// source does not exist there.
class ForegroundResumeController {
  ForegroundResumeController({
    required this.isPlaying,
    required this.isInPiP,
    required this.resume,
  });

  /// Was the player playing at background time (reads the container's latest `VIDEO_STATE_CHANGE`).
  final bool Function() isPlaying;

  /// Is the player CURRENTLY in real OS PiP (reads the container's `PIP_STATE_CHANGE`-fed flag).
  final bool Function() isInPiP;

  /// Idempotent resume — core `LivebuyPlayerController.play()`.
  final VoidCallback resume;

  bool _armed = false;
  bool _resumeOnPiPExit = false;

  /// Foreground → background edge. Capture whether we were playing (the resume gate).
  void appDidEnterBackground() {
    _armed = isPlaying();
  }

  /// Background → foreground edge. Fallback pause (not in PiP) → resume immediately; real PiP →
  /// record the intent and defer to [pipDidExit] (avoid racing AVKit's PiP restore). Either way,
  /// clear [_armed] (its intent is now carried by [_resumeOnPiPExit]). Not-playing-before-background
  /// (`_armed == false`) resumes nothing and sets no intent (respects the user's own pause).
  void appWillEnterForeground() {
    if (_armed) {
      if (isInPiP()) {
        _resumeOnPiPExit = true;
      } else {
        resume();
      }
    }
    _armed = false;
  }

  /// PiP truly ended (`PIP_STATE_CHANGE active→false`). Resume once iff the deferred intent was
  /// recorded in the foreground, then clear it (a second call does not double-resume).
  void pipDidExit() {
    if (_resumeOnPiPExit) {
      resume();
      _resumeOnPiPExit = false;
    }
  }
}

// MARK: - 領獎提交 seam（具名純函式 —— 讓「email 真的到得了 core」可被測試釘住）
//
// Spec: `reference-ui-rendering/spec.md`
//   § "Flutter turnkey 領獎 seam MUST 把使用者輸入的 email 帶到 core，且一次提交只呼叫 core 一次"
// Parity: RN `container/seams.ts` `buildAwardClaimInjection`（`rb-rn-win-claim-email-flow`）。

/// core 的領獎入口形狀（`LivebuyPlayerController.requestAwardClaim`）。`contact` 是
/// **具名選填**參數 —— 那正是本 seam 需要具名化的原因，見 [buildAwardClaimSubmit]。
typedef AwardClaimRequester = void Function(
  LBWinner winner, {
  LBAwardClaimInput? contact,
});

/// 🔴 建出 turnkey 容器的預設領獎提交 seam：把使用者在領獎 modal 輸入的 email 包成
/// `LBAwardClaimInput` 交給 core。
///
/// **改動前務必讀完這段。** 這個 seam 原本寫在容器裡、且不帶 contact：
/// `(winner) => _controller.requestAwardClaim(winner)`。core 的 `contact` 是**具名選填**
/// 參數，所以那一行**編譯完全通過卻恆送 `contact: null`**；而 core 預設（未被 host 攔截）
/// 的領獎路徑 `email` **必填**，缺 email 直接 fail-fast、**連 `POST /sdk/video/claim` 都不
/// 送**，於是 Flutter turnkey 的領獎必然失敗（第三方 host 回報的「中獎領取失敗」）。
///
/// 型別**抓不到**這種缺漏（少傳一個具名選填參數永遠合法），所以它被抽成這個具名純函式並
/// 有一條「core 端真的收到 contact」的行為釘樁 —— 整個 `LivebuyPlayer` 容器在測試環境無法
/// 建構（`LivebuyPlayerController` 走 MethodChannel、無 platform view），inline closure 無法
/// 被測，這正是此類 bug 得以存活的原因。
///
/// 🔴 這是本層**唯一**真的打領獎 API 的出口：`LivebuyUI.install()`（template 層）刻意
/// **不**注入 `claimContactSubmitter` / `claimSubmitter`。日後任何 template change 若要注入，
/// MUST 於同一個 change 移除容器的這條預設，否則同一次「確認領獎」會送出兩次
/// `POST /sdk/video/claim`（第二次後端回「已領過」→ `500 api.fail` → 使用者看到假失敗）。
void Function(LBWinner winner, String email) buildAwardClaimSubmit(
  AwardClaimRequester requestAwardClaim,
) {
  return (LBWinner winner, String email) => requestAwardClaim(
        winner,
        contact: LBAwardClaimInput(email: email),
      );
}

// MARK: - 加入活動送出 seam（具名純函式 —— 讓「加入真的到得了 core」可被測試釘住）
//
// Spec: `reference-ui-rendering/spec.md`
//   § "Flutter drop-in「加入活動」預設接到 core requestEventJoin（帶 keyword）"
// Parity: iOS / Android drop-in（其容器把「加入活動」接到 core `requestEventJoin`）。

/// core 的加入活動入口形狀（`LivebuyPlayerController.requestEventJoin`）。
typedef EventJoinRequester = void Function(int eid, String keyword);

/// 🔴 建出 turnkey 容器的預設「加入活動」送出 seam：把該 CTA 列的 `(eid, keyword)` 轉發給
/// core `requestEventJoin` —— 這是本層**唯一**真的打 core join 的地方（鏡像領獎的
/// [buildAwardClaimSubmit]）。
///
/// **改動前務必讀完這段。** Flutter drop-in 的「加入活動」原本只做樂觀翻轉、**從不打 core**：
/// `FeedWinModel.joinEvent` 走 `DefaultActivityFeed.markJoined`（純 UI flip），而
/// `template.joinEvent(eid, keyword)` 在 turnkey 路徑上也到不了 core —— 因為 Flutter 的
/// `DefaultPlayerTemplate` 持有不到 native player ref（Dart 無 `LBChannel`），且
/// `LivebuyUI.install()` **從未注入** template 的 `eventJoinRequester`（維持 inert no-op）。
/// 於是 Flutter turnkey 的「加入活動」是假的（第三方 host 會發現點了沒反應），與領獎 EMAIL-LESS
/// 陷阱同構。core 送出**只能在容器**經 `_controller.requestEventJoin` 打。
///
/// 抽成具名純函式並附「core 端真的收到 `(eid, keyword)`」的行為釘樁 —— 整個 `LivebuyPlayer`
/// 容器在測試環境無法建構（`LivebuyPlayerController` 走 MethodChannel、無 platform view），
/// inline closure 無法被測，這正是此類 bug 得以存活的原因（與 [buildAwardClaimSubmit] 同）。
///
/// `keyword` 空 → 不送（防禦：CTA 本就只在 keyword 非空時才畫；`FeedWinOverlayView._handleJoin`
/// 亦已 gate 樂觀翻轉與送出）。
///
/// 🔴 **雙送防線**：`LivebuyUI.install()`（template 層）刻意**不**注入 `eventJoinRequester`，
/// 所以本容器直呼是唯一真的打 core join 的地方。日後任何 template change 若要注入
/// `eventJoinRequester`，MUST 於同一個 change 移除本直呼，否則同一次「加入活動」會送出兩次
/// `requestEventJoin`（與領獎 seam 的雙送防線同一條紀律）。
void Function(int eid, String keyword) buildEventJoinSend(
  EventJoinRequester requestEventJoin,
) {
  return (int eid, String keyword) {
    if (keyword.isEmpty) return;
    requestEventJoin(eid, keyword);
  };
}

// MARK: - 右上角鈕直接關閉 seam（rb-flutter-player-direct-close-button）
//
// Spec: `reference-ui-rendering/spec.md`
//   § "Flutter LivebuyPlayerConfig.enableDirectCloseButton 旗標切換右上角鈕的直接關閉行為（Flutter）"
// Parity: iOS `LivebuyPlayerPresenter.resolvedEnableDirectCloseButton` (rb-ios-player-direct-close-button).

/// Resolves the per-instance `LivebuyPlayerConfig.enableDirectCloseButton` override against the
/// SDK-global `LivebuySDK.enableDirectCloseButton` preference (`configValue ?? globalValue`). Pure
/// / deterministic — no widget / SDK dependency of its own, so both call sites below hand it their
/// own already-read values.
///
/// **Why this MUST be the ONE decision point.** Two independent things need to agree on the SAME
/// resolved value or the UI lies about itself: [_LivebuyPlayerState._overlayContext] uses it to
/// pick the header's icon (`showCloseIcon`), while `CollapsibleLivebuyPlayer`'s `_composedConfig`
/// (in `collapsible_live_buy_player.dart`, which already imports this file) uses it to pick
/// `onMinimize`'s actual behavior (collapse-to-floating vs. direct full close). Two independent
/// copies of `configValue ?? globalValue` could drift the moment either caller changes shape —
/// sharing this one function makes that structurally impossible.
bool resolvedEnableDirectCloseButton({
  required bool? configValue,
  required bool globalValue,
}) =>
    configValue ?? globalValue;

/// Per-instance wiring for [LivebuyPlayer]. Every interaction callback is OPTIONAL with a
/// documented sensible default — a host that passes nothing still gets a working player
/// ("不 wire 也能跑"); passing a callback REPLACES that one default. Mirrors iOS
/// `LivebuyPlayerConfig` (adapted to the Flutter surfaces' callback shapes).
@immutable
class LivebuyPlayerConfig {
  /// The SDK-global event listener. If non-null the container installs it via
  /// `LivebuySDK.setListener`; if null the container does NOT touch the host's existing
  /// global listener (default: none — the host manages its own listener).
  final LBEventListener? eventListener;

  /// Top-right minimize tap. DEFAULT (D-3): forwards to core `controller.minimize()` — the
  /// architecturally-correct seam (today a safe no-op stub; activates when core ships the
  /// deferred in-app PiP). The in-app floating-preview collapse is a HOST presentation
  /// concern, so a host that wants it overrides `onMinimize`.
  final VoidCallback? onMinimize;

  /// Per-instance override of `LivebuySDK.enableDirectCloseButton`
  /// (rb-flutter-player-direct-close-button, parity iOS `LivebuyPlayerConfig
  /// .enableDirectCloseButton`). DEFAULT `null` — the resolved value falls back to the
  /// SDK-global preference (`resolvedEnableDirectCloseButton(configValue:
  /// enableDirectCloseButton, globalValue: LivebuySDK.enableDirectCloseButton)`, the SAME
  /// pure function both [_LivebuyPlayerState._overlayContext] (renders the header's icon)
  /// and `CollapsibleLivebuyPlayer._composedConfig` (decides `onMinimize`'s actual
  /// behavior) call).
  ///
  /// Only meaningful when this player is presented through `CollapsibleLivebuyPlayer` (the
  /// collapse-to-floating vs. direct-close distinction is that presenter's own collapsible
  /// semantics): `false` (resolved default) → the top-right button shows the minimize
  /// glyph and collapses to a floating preview, byte-identical to before this flag
  /// existed; `true` → it shows a close glyph and directly triggers the EXACT SAME close
  /// path the floating card's own close button uses, skipping the floating step entirely.
  /// A `LivebuyPlayer` used directly (not wrapped by `CollapsibleLivebuyPlayer`) still
  /// resolves this for the header's icon, but its `onMinimize` default
  /// (`config.onMinimize ?? _controller.minimize`) is unaffected — there is no floating
  /// widget concept to skip there.
  final bool? enableDirectCloseButton;

  /// Tap the video to (un)mute. DEFAULT: `template.toggleMute()` (flips the presentation
  /// `header.muted` / side-rail — the single mute-icon truth, via the public `toggleMute()`
  /// added by `flutter-player-toggle-mute-template`) THEN `controller.setMuted(header.muted)`
  /// (forwards the flipped truth to core so the active engine actually un/mutes — the Flutter
  /// template holds no native player ref, so audio is driven by the container's core controller).
  /// Parity iOS / Android `template.toggleMute()`. When `LivebuyUI` is not installed
  /// (`playerTemplate == null`, demo / golden) it falls back to a local `_muted` mirror.
  final VoidCallback? onToggleMute;

  /// Subscribe toggle. DEFAULT: `controller.videoInfoPanel.simulateSubscribeTap()`.
  final VoidCallback? onToggleSubscribe;

  /// Side-rail item tap (kind-routed). DEFAULT: routes each `LBSideRailKind` to its core
  /// `operationPanel.simulate*` exit (goods / chat / like / share / subtitle / serviceLink /
  /// guestNameEdit / more). 「留言…」comment is a separate seam (`onComment`).
  final ValueChanged<LBSideRailKind>? onTapRailItem;

  /// Pinned product card tap. DEFAULT: `controller.operationPanel.simulateGoodsTap()`
  /// (opens the goods surface — same intent as the rail「商品」).
  final VoidCallback? onTapPinnedProduct;

  /// LIVE「留言…」pill. DEFAULT: open + focus the on-demand chat composer.
  final VoidCallback? onComment;

  /// Product-row / overlay product tap. DEFAULT:
  /// `controller.productOverlay.simulateProductTap(product)`.
  final ValueChanged<LBProduct>? onProductTap;

  /// 頻道 / detail-footer 分享. DEFAULT (dropin-player-default-share-sheet-flutter): 以
  /// `channel.share_url`（`LivebuyUI.playerTemplate?.header.shareUrl`）經 `share_plus` `Share.share`
  /// 開系統分享；空 url → no-op；頻道級不附 `?t=`. host 設此 callback 完全覆蓋（自畫 sheet / 流程，零變更）。
  /// Flutter `performShare()` 同步回傳維持 DEFERRED（§3182）——drop-in 的分享攔截 seam 即此 `onShare`.
  final VoidCallback? onShare;

  /// 聯絡商家（`ContactMerchantModalView` 確認框「確定」之後的動作）
  /// (dropin-service-link-default-browser-flutter). host 設此 callback 完全覆蓋（自畫客服流程 /
  /// 開瀏覽器）。DEFAULT: 目前**無**智慧預設——`shop.serviceLink` 在 production reference-ui 拿不到值
  /// （`flutter-ui` 的 header/rail chrome 為 host-feeds 架構，`handleHeaderChrome()`/
  /// `handleRailEnablement()` 目前生產環境未接，跟分享功能的 `shareUrl` 面臨同樣的既有限制——見
  /// dropin-service-link-default-browser-flutter design.md）。未設此 callback 時 fall back 到既有
  /// `onTapRailItem?.call(LBSideRailKind.serviceLink)`（維持現況行為不變，非破壞）。
  final VoidCallback? onServiceLink;

  /// 商品列表列**縮圖**點擊 → 影片跳轉到該商品介紹時間（issue 5）. DEFAULT:
  /// `controller.seek(product.beginTime)`（`beginTime == null` 不 seek）. 收到該 [LBProduct]，
  /// host override 可改走自家章節跳轉。Mirrors iOS `onSeekToProductIntro`.
  final ValueChanged<LBProduct>? onSeekToProductIntro;

  /// 商品列表列**分享鈕**點擊 → 系統分享，連結帶該商品介紹時間 `?t=beginTime`（issue 6）.
  /// DEFAULT: `controller.operationPanel.simulateShareTap()`（channel-level 分享事件，由 host
  /// listener 呈現）——**Flutter reference-ui 不含 share_plus 等系統分享 plugin**（純 widget 層、
  /// 原生分享為 host 職責），故預設的 per-product `?t=beginTime` 系統分享需 host override（或用
  /// 套件提供的純函式 [productShareUrlString] 自組連結後分享）。收到該 [LBProduct]。
  final ValueChanged<LBProduct>? onShareProduct;

  /// Feed event-join entry. DEFAULT: no-op + host guidance (joining needs the event keyword,
  /// which is event-specific; the host wires `controller.requestEventJoin(eid, keyword)`).
  final ValueChanged<int>? onJoinEvent;

  /// 領獎提交（**帶使用者在領獎 modal 輸入的 email**，rb-flutter-win-claim-email-flow）。
  /// DEFAULT: `controller.requestAwardClaim(winner, contact: LBAwardClaimInput(email: email))`。
  ///
  /// 🔴 **BREAKING（編譯期）**：型別由 `ValueChanged<LBWinner>` 加寬為
  /// `void Function(LBWinner, String)`。Dart 不允許把少參數的 callback 指派給多參數函式
  /// 型別，故既有覆寫此 seam 的 host 會在升級時**編譯失敗**、被編譯器指著多接一個
  /// `String email`。這是刻意取捨：EMAIL-LESS 領獎在未被 host 攔截時**必然失敗**（core
  /// 預設領獎路徑 `email` 必填，缺 email 直接 fail-fast、連 `POST /sdk/video/claim` 都不
  /// 送），保留舊形狀只是把已知會壞的路徑留著；編譯期錯誤遠優於執行期靜默丟棄 email。
  final void Function(LBWinner winner, String email)? onSubmitClaim;

  /// End-screen「立即觀看」. DEFAULT: no-op + host guidance (the next video id comes from the
  /// bound template's auto-next, which is pending the template-read follow-up — R2).
  final VoidCallback? onWatchNext;

  /// 熱門卡 tap. DEFAULT: switch in place to that video (`controller.load(item.id)` +
  /// `onVideoSwitched`).
  final ValueChanged<LBEndHotItem>? onPickHot;

  /// 商品明細「更多商品」推薦卡播放圖示 tap → 換片
  /// (rb-flutter-product-detail-recommendations §4, design.md D3 of
  /// rb-ios-product-detail-recommendations). Carries the recommendation's `videoId`
  /// (already non-null by the time this fires — the sheet hides the button entirely
  /// for a null one). DEFAULT: the SAME in-place switch [_switchVideo] uses for
  /// [onPickHot] (`controller.load(videoId)` + `onVideoSwitched`) — but, UNLIKE
  /// [onPickHot], this does NOT close anything: the product-detail sheet stack MUST
  /// stay open (only the background video changes).
  final ValueChanged<String>? onSwitchRecommendationVideo;

  /// Start-screen 跳過. DEFAULT: `controller.skipStart()`.
  final VoidCallback? onSkip;

  /// End-screen 取消. DEFAULT: `controller.cancelAutoNext()` (stop the countdown, NOT dismiss).
  final VoidCallback? onCancel;

  /// Error 重試. DEFAULT: reload the current video (`controller.load(currentVideoId)`).
  final VoidCallback? onRetry;

  /// Moment dismiss. DEFAULT (R3): no-op + host guidance — a Flutter container is a widget in
  /// the host's tree and cannot pop the host's presenting route; a host overrides this.
  final VoidCallback? onDismiss;

  /// Rail「聊天」toggle. DEFAULT: no-op (the merged chat feed is composed always-on).
  final VoidCallback? onShowChatFeed;

  /// Auth-gate login. DEFAULT (R3): no-op + host guidance (host → `LivebuySDK.login(...)`).
  final VoidCallback? onLogin;

  /// 設定暱稱 modal submit. DEFAULT (turnkey, rb-flutter-nickname-taken-inline-error):
  /// `_controller.setGuestNicknameVerified(name)` (previously a fire-and-forget, unvalidated
  /// `LivebuySDK.setGuestNickname`) — awaits the native checkName-gated result; only on SUCCESS
  /// updates the local nickname mirror + dismisses the modal + (when entered from the 留言
  /// gating) opens the chat composer. On FAILURE (nickname 被取走 / other checkName error) it
  /// returns a user-facing error message INSTEAD — the modal stays open so the user can edit and
  /// retry. Sets the GUEST nickname, NEVER `setUser` (設名 ≠ 登入). An override REPLACES it — a
  /// host override owns its OWN `Future<String?>` success/failure contract (`null` = accepted,
  /// non-null = inline error message).
  final Future<String?> Function(String name)? onSubmitName;

  /// Fired when an in-place switch (hot-pick) changes the shown video, with the NEW id, so a
  /// host can keep its own "current video" state in sync. DEFAULT: null.
  final ValueChanged<String>? onVideoSwitched;

  /// Fired ALONGSIDE [onVideoSwitched] on an in-place switch, carrying the SWITCHED video as a full
  /// `LBVideoItem`. hot-pick carries the REAL `cover` / `title` (from the `LBEndHotItem` that drove
  /// the switch); swipe carries a `cover`-empty fallback with the correct `id` (Flutter reference-ui
  /// has no channel adjacency cover rows). The collapsible presenter (`CollapsibleLivebuyPlayer`)
  /// consumes it so a minimized floating preview shows the SWITCHED video, not the entry one.
  /// Additive, DEFAULT null; [onVideoSwitched] (id-only) still fires unchanged. Parity iOS /
  /// Android / RN `onVideoSwitchedItem` (rb-flutter-collapsible-player-track-switch). NOTE: Flutter
  /// nav/hot sources carry no `preview`, so the floating card shows a static cover (no preview loop).
  final ValueChanged<LBVideoItem>? onVideoSwitchedItem;

  /// Whether `PlayerShellView` paints its opaque background placeholder. Reserved for parity
  /// (the Flutter `PlayerShellView` exposes no such param yet). DEFAULT: false.
  final bool paintsBackgroundPlaceholder;

  /// Whether to show the one-time gesture hint. Reserved for parity (no Flutter shell param
  /// yet). DEFAULT: false.
  final bool showGestureHints;

  /// MERCHANT capability gate for the product sheet's「只剩庫存 N 組」caption
  /// (rb-flutter-show-stock-caption-toggle, parity iOS / Android / RN).
  ///
  /// Takes the RAW `extensions.show_stock` wire value the merchant set in
  /// `/admin/additional`. `extensions` is an OPAQUE RAW BAG the SDK never interprets, so
  /// this container does NOT read `sdkConfig` — the host does, and assigns it in one line
  /// with zero cast and zero home-grown default (Flutter core types `extensions` as
  /// `Map<String, Object?>`):
  ///
  /// ```dart
  /// LivebuyPlayerConfig(showStock: sdkConfig.extensions['show_stock'])
  /// ```
  ///
  /// The single fallback lives in `normalizeShowStock` (exported by this package): only
  /// `false`, numeric `0` and the verbatim string `'0'` turn the caption off; DEFAULT
  /// `null` ("the host injected nothing") shows it, so every existing host is unchanged.
  ///
  /// SCOPE: the stock NUMBER only. It does NOT touch the「已售完」treatment (driven by
  /// `qty.max == 0`) nor the restock sheet's「尚無庫存」(a sold-out status line).
  ///
  /// ⚠️ NAME CLASH, different signal: core `LBVideoItem.showStock` comes from
  /// `POST /sdk/widget` and is a DIFFERENT channel — this very file passes it as
  /// `showStock: false` inside `switchedVideoItem` below. The two are unrelated; this
  /// setting MUST NOT be wired to that field.
  final Object? showStock;

  /// Whether the header's subscribe badge (the small +/✓ affordance overlaid on the
  /// avatar) is shown (rb-flutter-subscribe-favorite-visibility-toggle, parity iOS /
  /// Android / RN). DEFAULT `false` — subscribe is now OFF/hidden unless a host
  /// explicitly opts in with `LivebuyPlayerConfig(showSubscribe: true)`. This is a
  /// DELIBERATE reversal of the sub-widgets' own `true` defaults (`PlayerHeaderBarView` /
  /// `PlayerShellView` / `PlayerOverlayContext` all default `showSubscribe` to `true` so
  /// they stay byte-identical for any test/host that constructs them directly) — ONLY
  /// this turnkey container's production default is `false`, matching the pattern
  /// `LivebuyPlayerConfig` already uses for other per-instance toggles (see [showStock]'s
  /// doc for the same "leaf defaults preserve, container default is the real production
  /// value" shape). Does NOT touch core / `sdkConfig` — the subscribe control itself
  /// (`simulateSubscribeTap()`) is unaffected; this only gates whether the affordance is
  /// drawn.
  final bool showSubscribe;

  /// Whether the product-detail sheet's INLINE 收藏鈕 (favorite / 到貨追蹤) row is shown
  /// (rb-flutter-subscribe-favorite-visibility-toggle, parity iOS / Android / RN). DEFAULT
  /// `false` — favorite is now OFF/hidden unless a host explicitly opts in with
  /// `LivebuyPlayerConfig(showFavorite: true)`. Same "leaf defaults `true`, container
  /// default `false`" shape as [showSubscribe] above. Does NOT touch core / `sdkConfig` —
  /// the favorite action itself (`goodsTracking.toggleAwait`) is unaffected; this only
  /// gates whether the row is drawn.
  final bool showFavorite;

  /// MERCHANT capability gate for the player top bar's title MARQUEE
  /// (rb-flutter-marquee-title-scroll, parity iOS / Android `titleScroll`).
  ///
  /// Takes the RAW `extensions.video_title_scroll` wire value the merchant set in
  /// `/admin/additional` (the backend setting item is named `video_title_display` — the
  /// wire key and the setting item deliberately do NOT share a name). `extensions` is an
  /// OPAQUE RAW BAG the SDK never interprets, so this container does NOT read
  /// `sdkConfig` — the host does, and assigns it in one line with zero cast and zero
  /// home-grown default (Flutter core types `extensions` as `Map<String, Object?>`):
  ///
  /// ```dart
  /// LivebuyPlayerConfig(titleScroll: sdkConfig.extensions['video_title_scroll'])
  /// ```
  ///
  /// The single fallback lives in `normalizeTitleScroll` (exported by this package):
  /// only `false`, numeric `0` and the verbatim string `'0'` turn scrolling off; DEFAULT
  /// `null` ("the host injected nothing") scrolls, matching the backend's own
  /// "unset ⇒ `1`" default, so every existing host is unchanged.
  ///
  /// ⚠️ NOT A VISIBILITY SWITCH. Per the backend contract
  /// (`openspec/specs/backend/sdk-config.md`), `video_title_scroll` says whether the
  /// title SCROLLS, never whether it SHOWS. Off ⇒ the title still renders, single-line
  /// with a tail ellipsis, at exactly the same height.
  ///
  /// SCOPE: the PLAYER top bar only. The widget video-card title is single-line
  /// truncated and never scrolled; design R15 records that there is NO evidence this
  /// setting covers it, so this flag MUST NOT be wired there.
  ///
  /// Same raw-`Object?` shape as the sibling `extensions` flag [showStock] — one raw
  /// value all the way down, one normalization point at the bottom.
  final Object? titleScroll;

  /// The design that composes the player overlay surface (granularity A). DEFAULT
  /// [MinimalDesign] — the verbatim minimal composition (behavior unchanged). A host injects a
  /// custom [ReferenceUIDesign] to lay the surfaces out differently. Mirrors iOS
  /// `LivebuyPlayerConfig.design`.
  final ReferenceUIDesign design;

  /// VOD/回放播放進度條的播放/暫停鈕 (rb-flutter-vod-playback-progress-bar). DEFAULT:
  /// `_controller.togglePlayPause()` — the container's own held `LivebuyPlayerController`,
  /// bypassing `DefaultPlayerTemplate.togglePlayPause()` (whose injection point,
  /// `LivebuyUI.install()`, never wires a real requester for it — see design.md).
  final VoidCallback? onTogglePlayPause;

  /// VOD/回放播放進度條的拖曳 seek (rb-flutter-vod-playback-progress-bar). DEFAULT:
  /// `_controller.seek(seconds, duration: duration)` — same container-controller-direct
  /// reasoning as [onTogglePlayPause]. `liveStatus` is deliberately never supplied (this
  /// container has no raw numeric `liveStatus` source wired; the progress bar's own display
  /// gate already guarantees the interaction only ever fires while non-live — see design.md).
  final void Function(double seconds, {double? duration})? onSeek;

  // -- rb-flutter-live-now-pill --------------------------------------------------------

  /// Shop ID whose ongoing OTHER live is polled to drive the「現正直播」提示鈕
  /// (`LiveNowPillView`, rb-flutter-live-now-pill). DEFAULT `null` — mirrors
  /// `LivebuyLiveEntry(shopId:)`'s existing precedent (the SDK has no getter to read back the
  /// `configure(shopId:)` value, the host must pass it again). `null` → the container builds NO
  /// `LiveNowPollController` at all (zero extra API calls, the pill never appears), aligning
  /// with the headless "no opt-in, no extra side effect" convention.
  final String? shopId;

  /// Tap on `LiveNowPillView`. DEFAULT: switch in place to the currently-detected other live
  /// (`_switchVideo(live.id)`, the SAME default `onPickHot` uses) — mirrors Android/RN's
  /// simpler shape (no extra player-controller parameter; the container closure already
  /// captures `_switchVideo`).
  final ValueChanged<LBVideoItem>? onGoLive;

  const LivebuyPlayerConfig({
    this.eventListener,
    this.onMinimize,
    this.enableDirectCloseButton,
    this.onToggleMute,
    this.onToggleSubscribe,
    this.onTapRailItem,
    this.onTapPinnedProduct,
    this.onComment,
    this.onProductTap,
    this.onShare,
    this.onServiceLink,
    this.onSeekToProductIntro,
    this.onShareProduct,
    this.onJoinEvent,
    this.onSubmitClaim,
    this.onWatchNext,
    this.onPickHot,
    this.onSwitchRecommendationVideo,
    this.onSkip,
    this.onCancel,
    this.onRetry,
    this.onDismiss,
    this.onShowChatFeed,
    this.onLogin,
    this.onSubmitName,
    this.onVideoSwitched,
    this.onVideoSwitchedItem,
    this.paintsBackgroundPlaceholder = false,
    this.showGestureHints = false,
    this.showStock,
    this.showSubscribe = false,
    this.showFavorite = false,
    this.titleScroll,
    this.design = const MinimalDesign(),
    this.onTogglePlayPause,
    this.onSeek,
    this.shopId,
    this.onGoLive,
  });

  /// Returns a copy with `onMinimize` / `onDismiss` overridden (all other seams passed through).
  /// Used by the collapsible presenter (`CollapsibleLivebuyPlayer`) to TAKE OVER the
  /// minimize-collapse / clear while leaving every other host seam intact (parity with iOS
  /// `LivebuyPlayerPresenter.composedConfig`).
  ///
  /// ⚠️ THIS METHOD ENUMERATES EVERY FIELD BY HAND. Adding a field to
  /// [LivebuyPlayerConfig] and forgetting to pass it through here produces **no compile
  /// error at all** — the copy silently falls back to that field's default, so the setting
  /// dies on the whole `CollapsibleLivebuyPlayer` path while the plain `LivebuyPlayer` path
  /// still works. Always update this method in the same change, and pin it with a test.
  LivebuyPlayerConfig copyWith({
    VoidCallback? onMinimize,
    VoidCallback? onDismiss,
    ValueChanged<LBVideoItem>? onVideoSwitchedItem,
  }) {
    return LivebuyPlayerConfig(
      eventListener: eventListener,
      onMinimize: onMinimize ?? this.onMinimize,
      // rb-flutter-player-direct-close-button — must survive the collapsible presenter's
      // re-composition (see the ⚠️ note above): dropping this would silently reset a
      // host's per-instance override back to `null` on the `CollapsibleLivebuyPlayer` path.
      enableDirectCloseButton: enableDirectCloseButton,
      onToggleMute: onToggleMute,
      onToggleSubscribe: onToggleSubscribe,
      onTapRailItem: onTapRailItem,
      onTapPinnedProduct: onTapPinnedProduct,
      onComment: onComment,
      onProductTap: onProductTap,
      onShare: onShare,
      onServiceLink: onServiceLink,
      onJoinEvent: onJoinEvent,
      onSubmitClaim: onSubmitClaim,
      onWatchNext: onWatchNext,
      onPickHot: onPickHot,
      onSwitchRecommendationVideo: onSwitchRecommendationVideo,
      onSkip: onSkip,
      onCancel: onCancel,
      onRetry: onRetry,
      onDismiss: onDismiss ?? this.onDismiss,
      onShowChatFeed: onShowChatFeed,
      onLogin: onLogin,
      onSubmitName: onSubmitName,
      onVideoSwitched: onVideoSwitched,
      onVideoSwitchedItem: onVideoSwitchedItem ?? this.onVideoSwitchedItem,
      paintsBackgroundPlaceholder: paintsBackgroundPlaceholder,
      showGestureHints: showGestureHints,
      // rb-flutter-show-stock-caption-toggle — the merchant stock-caption gate must
      // survive the collapsible presenter's re-composition (see the ⚠️ note above).
      showStock: showStock,
      // rb-flutter-subscribe-favorite-visibility-toggle — same "must survive the
      // collapsible presenter's re-composition" requirement as showStock above.
      showSubscribe: showSubscribe,
      showFavorite: showFavorite,
      // rb-flutter-marquee-title-scroll — the merchant title-marquee gate must likewise
      // survive the collapsible presenter's re-composition.
      titleScroll: titleScroll,
      design: design,
      // rb-flutter-vod-playback-progress-bar — must likewise survive the collapsible
      // presenter's re-composition (see the ⚠️ note above).
      onTogglePlayPause: onTogglePlayPause,
      onSeek: onSeek,
      // rb-flutter-live-now-pill — must likewise survive the collapsible presenter's
      // re-composition (see the ⚠️ note above).
      shopId: shopId,
      onGoLive: onGoLive,
    );
  }
}

/// Build the `LBVideoItem` reported via `LivebuyPlayerConfig.onVideoSwitchedItem` after an in-place
/// switch, from the switch target's display fields — the REAL `cover` / `title` taken from the hot
/// item (hot-pick) that drove the switch (swipe passes empty `cover` + the correct `id`, as Flutter
/// reference-ui has no channel adjacency cover rows). KIND is derived from `liveStatus` (`type == 2`
/// when live, else `1`); the rest is empty / 0. `preview` stays "" on Flutter (the `LBEndHotItem` /
/// `LBEndNavItem` sources carry no preview). Pure (no widget / I/O) so it is unit-testable. Parity
/// iOS / Android / RN `switchedVideoItem` (rb-flutter-collapsible-player-track-switch).
LBVideoItem switchedVideoItem({
  required String id,
  required String cover,
  required String title,
  required int duration,
  required int liveStatus,
  String preview = '',
}) {
  return LBVideoItem(
    id: id,
    type: liveStatus == 1 ? 2 : 1,
    title: title,
    cover: cover,
    preview: preview,
    duration: duration,
    publishAt: '',
    watchNum: 0,
    pvNum: 0,
    liveStatus: liveStatus,
    pin: 0,
    showPvNum: 0,
    liveurl: '',
    playbackurl: '',
    previewTime: '',
    showStock: false,
  );
}

/// Build the fallback `LBVideoItem` for the FOURTH in-place switch path — core 的 **VOD 自動接播**
/// （rb-flutter-collapsible-autoadvance-switch-sync；parity iOS / Android / RN `autoAdvanceSwitchedItem`）。
/// 沿用既有 [switchedVideoItem] builder 以 `id = to`、`cover = ''`、`title = ''`、`duration = 0`、
/// `liveStatus = 0`（VOD）組出——`switchedVideoItem` 據 `liveStatus == 1 ? 2 : 1` 衍生 `type = 1`（VOD）。
/// Pure（無 widget / native / I/O）→ 可單元測。
/// - **cover 空**：Flutter 的 headless `VIDEO_SWITCH` 事件只帶 `to_video_id`（無 cover / title，與 iOS / Android
///   core seam 帶完整 `LBNavItem` 不同）→ 浮卡顯示**正確 id、空 cover** 的 fallback，品質與 Flutter swipe fallback
///   一致（Dart 無 channel adjacency cover rows），非退步。
/// - **`liveStatus = 0`（VOD）為 switch-time guess**：自動接播只發生於 VOD / replay 語境（LIVE 走 poll `live_end`
///   → endScreen，不自動接播）。**注意勿沿用** swipe 路徑 [_LivebuyPlayerState._notifySwitchedVideo] 的
///   `liveStatus = 1`（那是相鄰影片的 guess）。Flutter 容器無 `onLiveStatusChange` 自校正 seam → 此 guess 為終值
///   （自動接播確為 VOD，無需自校正）。
LBVideoItem autoAdvanceSwitchedItem(String id) =>
    switchedVideoItem(id: id, cover: '', title: '', duration: 0, liveStatus: 0);

/// Turnkey drop-in player. Builds a [LivebuyPlayerCore] (native view) with a retained
/// [LivebuyPlayerController], composes all reference-ui surfaces into ONE `Stack`, wires each
/// seam to [config] (defaults where unset), and (via the native view's `videoId`) loads.
class LivebuyPlayer extends StatefulWidget {
  final String videoId;
  final LivebuyPlayerConfig config;

  const LivebuyPlayer({
    super.key,
    required this.videoId,
    this.config = const LivebuyPlayerConfig(),
  });

  @override
  State<LivebuyPlayer> createState() => _LivebuyPlayerState();
}

class _LivebuyPlayerState extends State<LivebuyPlayer>
    with WidgetsBindingObserver {
  late final LivebuyPlayerController _controller;
  late final ChatComposerController _composer;

  /// iOS PiP-pause → foreground-resume state machine (flutter-refui-pip-pause-foreground-resume,
  /// parity iOS `ios-refui-pip-pause-foreground-resume`). **iOS-gated**: non-null (and the lifecycle
  /// observer installed) ONLY on iOS; null on Android (N/A — no AVKit re-parent, ExoPlayer pauses
  /// honestly). When null every resume path below is an inert no-op.
  ForegroundResumeController? _resumeController;

  /// 「現正直播」poller (rb-flutter-live-now-pill). `null` when `config.shopId == null` — the
  /// caller (this State) decides whether to build it at all, mirroring [_resumeController]'s
  /// own "nullable field, built conditionally inside `initState`" convention (design.md
  /// Decision 1). Every use site short-circuits on `null` via `_liveNowController?.`.
  LiveNowPollController? _liveNowController;

  /// Latest player state seen via `VIDEO_STATE_CHANGE` (through the wrapping SDK listener). Feeds
  /// the controller's `isPlaying` seam (was-playing latch). Note IVS live stays stale `.playing`
  /// after a pause — intentional: the gate is "was playing before background", never live `.paused`.
  LBPlayerState _lastPlayerState = LBPlayerState.loading;

  /// Whether the wrapped core is CURRENTLY in real OS PiP (maintained from `PIP_STATE_CHANGE`
  /// `active`). Feeds the controller's `isInPiP` seam.
  bool _isInPiP = false;

  /// Edge-trigger latch for [didChangeAppLifecycleState]: Flutter emits several non-`resumed`
  /// states (`inactive` → `hidden` → `paused`) when leaving the foreground, but the was-playing
  /// capture must happen exactly once, on the FIRST leave (before the native background pause).
  bool _isForeground = true;

  /// On-demand 設定暱稱 modal controller (LIVE 暱稱 button + 留言 gating). parity iOS / Android / RN.
  late final NicknamePromptController _nickname;

  /// On-demand「請先登入」modal controller for the LIVE 留言 login gate (guest + guest_comment==0).
  /// parity iOS / Android / RN `LoginPromptController` (rb-flutter-live-comment-login-gate).
  late final LoginPromptController _login;

  /// Local mirror of the guest's picked nickname (R2-honest, like [_muted]): Flutter has no
  /// public per-player template read path (surfaces get `template: null`), so the 留言 gating
  /// reads this instead of the live identity. Set on a successful 設定暱稱 submit; '' until then.
  String _guestNickname = '';

  late String _currentVideoId;

  /// No-template FALLBACK mute mirror. The single mute truth is `template.header.muted`
  /// (`LivebuyUI.playerTemplate`, flipped by `template.toggleMute()` — the icon truth driving
  /// `PlayerShellView`'s mute glyph); `_toggleMute` reads that live truth whenever a template is
  /// installed. This local `_muted` is used ONLY on the demo / golden path where `LivebuyUI` is
  /// NOT installed (`playerTemplate == null`). Init `false` — aligned with the core's UNMUTED
  /// default (main playback starts with sound on); the old init `true` was PHASE-WRONG (it made
  /// the first tap resolve to `setMuted(false)`, an inert no-op against the already-unmuted core).
  bool _muted = false;

  /// Local mirror of `PlayerShellView`'s info-panel open state (parity iOS rb-ios-info-panel-not-
  /// covered-by-chat): the shell reports every open/close via `onInfoPanelOpenChange`, and we
  /// pass this down to `FeedWinOverlayView` (via the design context) to hide the chat feed while
  /// the panel is up. Default false (the panel opens only on a host-badge / `more` rail tap).
  bool _infoPanelOpen = false;

  /// Local mirror of `PlayerShellView`'s「乾淨模式」state (rb-flutter-gesture-clean-mode-
  /// rewrite): the shell reports every toggle via `onCleanModeChange`, and we pass this down
  /// to `FeedWinOverlayView` (via the design context) to hide the chat feed while it is up.
  /// Wiring copied verbatim from [_infoPanelOpen] above. Default false (off).
  bool _cleanMode = false;

  /// Local mirror of `PlayerShellView`'s closed-chat finished-replay rail「更多」sheet open state
  /// (rb-flutter-live-more-sheet-above-chat): the shell reports every open/close via
  /// `onMoreMenuOpenChange`, and we pass this down to `FeedWinOverlayView` (via the design
  /// context) to hide the chat feed while it is up. Wiring copied verbatim from [_cleanMode]
  /// above. Default false (off).
  bool _moreMenuOpen = false;

  /// Container-owned product LIST drawer open state (default CLOSED). The GOODS rail / bag tap
  /// opens it; the scrim / close button dismisses it (re-openable). Parity iOS
  /// `ProductSheetsModel.listPresented` (default false) — no longer auto-presents over the video.
  bool _productListPresented = false;

  /// Resolved core theme (`sdkConfig.theme`), fetched async in [initState]; null → minimal
  /// fallback (the resolver's default), the safe degradation until the fetch completes / if it
  /// fails. The whole `sdkConfig.theme > host options > minimal` order is preserved.
  LBSdkTheme? _coreTheme;

  @override
  void initState() {
    super.initState();
    _controller = LivebuyPlayerController();
    _composer = ChatComposerController();
    _nickname = NicknamePromptController();
    _login = LoginPromptController();
    _currentVideoId = widget.videoId;
    // 永遠安裝一個包裹 listener：攔 VIDEO_SWITCH 更新 swipe 基準 _currentVideoId（core 自動接續
    // 不經容器 → 否則過時 → swipe 上一支落到前前一支，rb-flutter-swipe-prev-after-autoadvance），
    // 再轉發 host listener（無則回 passthrough，回覆語意不變）。
    //
    // 第四條換片同步路徑（rb-flutter-collapsible-autoadvance-switch-sync）：core 自主的 VOD 自動接播
    // （bridge 內嵌 core 的 handleEngineEnded → load(next)）繞過 reference-ui 既有三條 in-place 換片
    // 同步（swipe / hot-pick / watch-next），故最小化浮卡縮圖 stale。這裡於**同一個既有訂閱點**多接一條：
    // 以 shouldSyncAutoAdvance gate 只在**真 core 接播**（to != _currentVideoId）時，把 to 走**既有**
    // config.onVideoSwitchedItem 出口（id 正確、cover 空的 fallback）→ CollapsibleLivebuyPlayer._shownVideo
    // 更新、浮卡顯示接播後影片。
    //   - 上游 skip：使用者互動換片（swipe / hot-pick）在同步 handler 內已把 _currentVideoId 推進到 to，
    //     非同步 VIDEO_SWITCH 抵達時 to == _currentVideoId → skip → 真 cover 不被空 cover 覆蓋、host 不重複呼叫。
    //   - 下游防禦縱深：CollapsibleLivebuyPlayer 既有 same-id guard（item.id != _shownVideo?.id）再擋一層。
    //   - swipe 基準等價保留：舊 `if (to != null) _currentVideoId = to`；新碼 to==current 時 skip（本就 no-op）、
    //     to!=null && to!=current 時一樣更新 _currentVideoId、to==null 一樣不動 → 基準行為完全等價。
    // Flutter 為 StatefulWidget，listener body 於被呼叫時讀 widget.config 永遠是最新（含 _composedConfig 的
    // onVideoSwitchedItem）→ 不需 RN 的 configRef。
    // iOS-gated PiP-pause → foreground-resume wiring (flutter-refui-pip-pause-foreground-resume).
    // Only iOS suffers the AVKit-PiP frozen-frame gap, so ONLY iOS installs the lifecycle observer
    // and the resume state machine. On Android these stay null / unattached (inert).
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      WidgetsBinding.instance.addObserver(this);
      _resumeController = ForegroundResumeController(
        isPlaying: () => _lastPlayerState == LBPlayerState.playing,
        isInPiP: () => _isInPiP,
        resume: _controller.play,
      );
    }
    final hostListener = widget.config.eventListener;
    LivebuySDK.setListener((event) async {
      final to = videoSwitchToId(event.eventName, event.params);
      if (shouldSyncAutoAdvance(to, _currentVideoId)) {
        _currentVideoId = to!;
        widget.config.onVideoSwitchedItem?.call(autoAdvanceSwitchedItem(to));
      }
      // iOS-gated (rc != null): track the latest player state for the was-playing latch, and drive
      // the deferred PiP-exit resume. Extends THIS existing wrapping listener rather than installing
      // a second `setListener` (a second call would REPLACE this one — livebuy_sdk.dart:382).
      final rc = _resumeController;
      if (rc != null) {
        if (event.eventName == LBEvent.videoStateChange) {
          final s = event.params['state'];
          if (s is String) _lastPlayerState = lbPlayerStateFromString(s);
        } else if (event.eventName == LBEvent.pipStateChange) {
          final active = event.params['active'] == true;
          _isInPiP = active;
          if (!active) rc.pipDidExit(); // PiP truly ended → deferred resume (iff intent recorded)
        }
      }
      final hostReply = await hostListener?.call(event);
      final templateReply = await LivebuyUI.forwardToTemplate(event);
      return resolveContainerEventReply(hostReply, templateReply);
    });
    _loadCoreTheme();
    // rb-flutter-live-now-pill: `config.shopId == null` → build NO controller at all (zero
    // extra API calls, the pill never appears) — see design.md Decision 1 for why this is a
    // caller-decides shape (mirrors [_resumeController] above), not iOS/RN's
    // nullable-ctor-internal-no-op.
    final shopId = widget.config.shopId;
    if (shopId != null) {
      _liveNowController = LiveNowPollController(shopId: shopId)
        ..addListener(_onLiveNowChanged)
        ..start();
    }
  }

  /// Bridges [LiveNowPollController] state changes into a rebuild (a `ChangeNotifier`, unlike
  /// iOS `@Published` / Android `mutableStateOf`, does not auto-trigger one) — mirrors
  /// `PlayerShellView`'s own `template?.subtitle.addListener(...)` bridge (design.md Decision 2).
  void _onLiveNowChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    // Symmetric with the iOS-gated addObserver in initState (no-op / never added on Android).
    if (_resumeController != null) {
      WidgetsBinding.instance.removeObserver(this);
    }
    _liveNowController
      ?..removeListener(_onLiveNowChanged)
      ..stop()
      ..dispose();
    _composer.dispose();
    _nickname.dispose();
    _login.dispose();
    super.dispose();
  }

  /// App lifecycle → foreground-resume edges (iOS-gated; inert when `_resumeController == null`).
  /// Edge-triggered on the `resumed` boundary so the was-playing latch is captured exactly once on
  /// the FIRST leave-foreground (`resumed → inactive`, which precedes the native background pause),
  /// not re-captured on the subsequent `hidden` / `paused` transitions (which could overwrite it
  /// with a now-paused AVPlayer VOD state).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final rc = _resumeController;
    if (rc == null) return;
    final nowForeground = state == AppLifecycleState.resumed;
    if (nowForeground == _isForeground) return;
    _isForeground = nowForeground;
    if (nowForeground) {
      rc.appWillEnterForeground();
    } else {
      rc.appDidEnterBackground();
    }
  }

  /// Fetch `sdkConfig.theme` for the theme resolver (best-effort; minimal fallback on failure).
  Future<void> _loadCoreTheme() async {
    try {
      final cfg = await LivebuySDK.getSdkConfig();
      if (mounted) setState(() => _coreTheme = cfg.theme);
    } catch (_) {
      // Keep the minimal fallback — theme degrades gracefully, never crashes.
    }
  }

  ReferenceUITheme _resolveTheme() =>
      ReferenceUIThemeResolver.resolve(coreTheme: _coreTheme);

  /// Switch the shown video in place (hot-pick): load + track + notify the host.
  void _switchVideo(String id) {
    _currentVideoId = id;
    _controller.load(id);
    widget.config.onVideoSwitched?.call(id);
  }

  /// Notify-only swipe in-place switch (swipe-video-switched-notify): track the shown id (so
  /// `onRetry` reloads the new video, parity [_switchVideo]'s first line) + notify the host. NO
  /// `_controller.load` — the swipe already loaded via `_model.navigateToNext()` → template
  /// forwarder ([_switchVideo] loads itself for hot-pick; this path MUST NOT load again).
  void _notifySwitchedVideo(String id) {
    _currentVideoId = id;
    widget.config.onVideoSwitched?.call(id);
    // Report the SWITCHED video as a full item so a bound floating preview shows the switched
    // video, NOT the entry one (rb-flutter-collapsible-player-track-switch). Flutter reference-ui
    // has no channel adjacency cover rows in JS/Dart → empty cover + the correct id (fallback,
    // parity iOS rare-case / RN swipe).
    widget.config.onVideoSwitchedItem?.call(
      switchedVideoItem(id: id, cover: '', title: '', duration: 0, liveStatus: 1),
    );
  }

  /// Tap-to-(un)mute default (flutter-player-toggle-mute-wire-reference-ui, parity iOS
  /// `LivebuyPlayer.swift` / Android `android-reference-ui-wire-toggle-mute`). Drives BOTH:
  ///   1. `template.toggleMute()` — flips the presentation `header.muted` / side-rail muted flag,
  ///      the SINGLE source of the mute icon (`PlayerShellModel.muted` reads `template.header.muted`).
  ///   2. `controller.setMuted(header.muted)` — forwards the POST-flip truth to core so the active
  ///      engine (IVS / AVPlayer) actually un/mutes. The Flutter `DefaultPlayerTemplate` holds no
  ///      native player ref, so audio is driven by the container's own core controller (not via the
  ///      template's injected `MutedSetter`, which the SDK-global `LivebuyUI.playerTemplate` leaves
  ///      as a no-op — the reference-ui has no ctor injection point on that global singleton).
  /// No-template fallback (demo / golden, `LivebuyUI` not installed): flip the local `_muted`
  /// mirror + drive core with it.
  void _toggleMute() {
    final t = LivebuyUI.playerTemplate;
    if (t != null) {
      t.toggleMute(); // icon single truth: flip header / side-rail muted
      _controller.setMuted(t.header.muted); // core audio: forward the flipped truth
    } else {
      _muted = !_muted;
      _controller.setMuted(_muted);
    }
  }

  /// Route a side-rail tap to its core `operationPanel.simulate*` exit (kind-routed default).
  void _routeRailItem(LBSideRailKind kind) {
    final op = _controller.operationPanel;
    switch (kind) {
      case LBSideRailKind.goods:
        // GOODS 購物袋 → 開啟容器持有的商品列表抽屜（parity iOS onOpenProductList / Android GOODS
        // 開抽屜）。抽屜即商品列表，不需 core simulateGoodsTap。
        setState(() => _productListPresented = true);
      case LBSideRailKind.chat:
        op.simulateChatToggleTap();
      case LBSideRailKind.like:
        op.simulateLikeTap();
      case LBSideRailKind.share:
        op.simulateShareTap();
      case LBSideRailKind.subtitle:
        op.simulateSubtitleToggleTap();
      case LBSideRailKind.serviceLink:
        op.simulateServiceLinkTap();
      case LBSideRailKind.guestNameEdit:
        op.simulateGuestNameEditTap();
      case LBSideRailKind.more:
        op.simulateMoreTap();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = _resolveTheme();
    return Stack(
      fit: StackFit.expand,
      children: [
        LivebuyPlayerCore(
          videoId: widget.videoId,
          controller: _controller,
          enablePiP: true,
          // VOD-2 playback-progress DATA plane (rb-flutter-vod-playback-progress-bar) — was
          // never wired before this change, so `template.playbackProgress` was dead in
          // production regardless of any consuming pixel surface. Null-safe (`?.`) so a
          // demo/golden run with no installed `LivebuyUI` template is a no-op, matching every
          // other `LivebuyUI.playerTemplate?.` call site in this file.
          onPlaybackProgressChange: (p) =>
              LivebuyUI.playerTemplate?.handlePlaybackProgress(
            position: p.position,
            duration: p.duration,
            isPlaying: p.isPlaying,
            isReplay: p.isReplay,
          ),
          // rb-flutter-subtitle-vtt-caption-display — per-channel VTT subtitle DATA plane. Was
          // never wired before this change (`rb-flutter-subtitle-template-wiring` built
          // `handleSubtitleChannelInfo` but nothing called it), so `template.subtitle.url` was
          // dead in production. Extracted to a top-level function ([forwardSubtitleChangeToTemplate])
          // rather than inlined so the forwarding itself is unit-testable without constructing
          // this platform-view widget.
          onSubtitleChange: (info) =>
              forwardSubtitleChangeToTemplate(info, LivebuyUI.playerTemplate),
        ),
        // The WHOLE overlay (shell / feed-win / product-sheets / moments / gap-surfaces /
        // composer) is composed by the resolved design (granularity A). Default MinimalDesign
        // = the verbatim minimal composition (behavior unchanged); a host injects its own.
        widget.config.design.playerOverlay(_overlayContext(theme)),
      ],
    );
  }

  /// Bundles the resolved theme + composer + every host-wired seam (`config.onX ?? <default>`,
  /// so a host override replaces just that one seam) for the design's `playerOverlay`. The
  /// previous inline `_buildShell` / `_buildOverlays` / `_buildComposer` defaults are preserved
  /// verbatim here.
  PlayerOverlayContext _overlayContext(ReferenceUITheme theme) {
    final c = widget.config;
    // Vertical swipe-to-switch-video: the drop-in NO LONGER injects a host-feed override
    // (`swipeFeed` removed — rb-flutter-swipe-always-channel-adjacency, parity iOS). With both
    // null, `PlayerShellView` drives the swipe via its built-in channel-adjacency fallback
    // (`navigateToNext()` / `navigateToPrev()`, reading the backend `/sdk/video` `prev`/`next`)
    // and raises `onCloseRequest` at the backend head / tail (swipe-nav-close-on-empty). The
    // host-override seam is retained for hosts wiring `PlayerShellView` directly.
    const VoidCallback? onSwipeUp = null;
    const VoidCallback? onSwipeDown = null;
    return PlayerOverlayContext(
      theme: theme,
      // Bind the LIVE per-player template (R2 read path) so every surface shows live state —
      // header / rail / merged feed / info panel — instead of the demo seeds. null when
      // `LivebuyUI` is not installed (demo / golden) → surfaces degrade to seeds.
      template: LivebuyUI.playerTemplate,
      composerController: _composer,
      nicknameController: _nickname,
      loginController: _login,
      // Parity: the inline overlays never set `ProductSheetsOverlayView.live` → default false.
      live: false,
      // 商品 sheet 庫存文案的商家能力閘（rb-flutter-show-stock-caption-toggle）：原樣帶 host 注入的
      // raw `extensions.show_stock`，容器**不**自行讀 `sdkConfig`、**不**正規化（由 sheet 端的
      // `normalizeShowStock` 單一入口負責）。null（預設）→ 顯示，既有 host 零改動。
      showStock: c.showStock,
      // 訂閱鈕 / 收藏鈕顯示/隱藏（rb-flutter-subscribe-favorite-visibility-toggle）：container 的
      // 真正生產預設是 `false`（隱藏），host 可用 `LivebuyPlayerConfig(showSubscribe: true, /
      // showFavorite: true)` 顯式開啟——不接觸 core / sdkConfig，純 client 端渲染開關。
      showSubscribe: c.showSubscribe,
      showFavorite: c.showFavorite,
      // 標題跑馬燈的商家能力閘（rb-flutter-marquee-title-scroll）：原樣帶 host 注入的 raw
      // `extensions.video_title_scroll`，容器**不**自行讀 `sdkConfig`、**不**正規化（由
      // `PlayerHeaderBarView` 的 `normalizeTitleScroll` 單一入口負責）。null（預設）→ 溢出即捲，
      // 既有 host 零改動。
      titleScroll: c.titleScroll,
      // 右上角按鈕圖示 minimize ↔ close（rb-flutter-player-direct-close-button）：由這裡單一入口
      // 解析（config 覆寫 ?? SDK-global 偏好），供 PlayerHeaderBarView 純呈現使用；`onMinimize`
      // 的實際行為切換發生在 `CollapsibleLivebuyPlayer._composedConfig`（同一個純函式，永不分歧）。
      showCloseIcon: resolvedEnableDirectCloseButton(
        configValue: c.enableDirectCloseButton,
        globalValue: LivebuySDK.enableDirectCloseButton,
      ),
      // Mirror the shell's info-panel open state so the chat feed hides while it's up (parity
      // iOS rb-ios-info-panel-not-covered-by-chat).
      infoPanelOpen: _infoPanelOpen,
      onInfoPanelOpenChange: (open) {
        if (open != _infoPanelOpen) setState(() => _infoPanelOpen = open);
      },
      // 乾淨模式（rb-flutter-gesture-clean-mode-rewrite）：接線比照上面既有 _infoPanelOpen。
      cleanMode: _cleanMode,
      onCleanModeChange: (v) {
        if (v != _cleanMode) setState(() => _cleanMode = v);
      },
      // 「更多」選單開合（rb-flutter-live-more-sheet-above-chat）：接線比照上面既有 _cleanMode。
      moreMenuOpen: _moreMenuOpen,
      onMoreMenuOpenChange: (v) {
        if (v != _moreMenuOpen) setState(() => _moreMenuOpen = v);
      },
      // Container-owned product LIST drawer open state (default closed; GOODS rail/bag tap opens
      // it via _routeRailItem; scrim/close dismisses) — parity iOS, no auto-present.
      productListPresented: _productListPresented,
      onDismissProductList: () {
        if (_productListPresented) setState(() => _productListPresented = false);
      },
      onMinimize: c.onMinimize ?? _controller.minimize,
      onToggleMute: c.onToggleMute ?? _toggleMute,
      // 訂閱鈕 → **登入閘**（rb-flutter-subscribe-login-gate，parity iOS / Android / RN）：Flutter 唯一
      // 可互動的訂閱入口是 PlayerHeader 頭像徽章（`PlayerShellView.onToggleSubscribe` → 徽章）；
      // VideoInfoPanel 的訂閱 pill 為純呈現、無 tap（`_subscribePill()` presentation only）。訪客先本地跳
      // 「請先登入」modal（AuthGateModalView(subscribe)），已登入才 simulateSubscribeTap。host 自訂
      // config.onToggleSubscribe 則完全接管、不套 gating（零改）。
      onToggleSubscribe: c.onToggleSubscribe ?? _gatedSubscribe,
      onTapRailItem: c.onTapRailItem ?? _routeRailItem,
      onTapPinnedProduct:
          c.onTapPinnedProduct ?? _controller.operationPanel.simulateGoodsTap,
      // LIVE「留言…」pill → 預設先判斷暱稱是否已設定（R2：讀容器本地鏡像 `_guestNickname`）：未設定
      // （訪客且尚未選名）→ 先呈現 設定暱稱 modal（composeAfter=true、送出後接 composer）；否則開
      // composer。host 自訂 config.onComment 則完全接管、不套 gating（parity iOS / Android / RN）。
      onComment: c.onComment ?? _gatedComment,
      // LIVE 底部 bar 暱稱按鈕 → 本地呈現 設定暱稱 modal（不走被 gating 的 core；parity）。送出後不接
      // composer（composeAfter=false）。**登入閘**（rb-flutter-nickname-login-gate / iOS 9d1048e /
      // Android 5e87816 / RN d1be462）：若該場直播留言需登入（訪客 + guest_comment==0 ⟺
      // chatEnabled==false）→ 點暱稱也比照留言先呈現「請先登入」modal（與 onComment 共用同一純函式
      // liveCommentRequiresLogin），MUST NOT 開暱稱 modal。
      onNickname: _gatedNickname,
      // 「現正直播」提示鈕（rb-flutter-live-now-pill）：`hasLiveNow` 讀輪詢結果是否非空；
      // `onGoLive` 讀出目前偵測到的 `LBVideoItem` → host override 或預設 `_switchVideo`
      // （比照 `onPickHot` 預設換片）。`_liveNowController == null`（`config.shopId == null`）
      // 時 `hasLiveNow` 恆 false、`onGoLive` 恆 no-op（鈕本就不會被組出，這裡的空值防禦僅為
      // 保守起見）。
      hasLiveNow: _liveNowController?.liveNow != null,
      onGoLive: () {
        final live = _liveNowController?.liveNow;
        if (live == null) return;
        final override = c.onGoLive;
        if (override != null) {
          override(live);
        } else {
          _switchVideo(live.id);
        }
      },
      onSwipeUp: onSwipeUp,
      onSwipeDown: onSwipeDown,
      // 滑向「無影片」方向（無 next / prev）→ 關閉播放器（swipe-nav-close-on-empty）：host
      // `config.onDismiss` wins，否則退回 core `controller.unload()`（停 poll/timer、暫停、清
      // video/channel、playerState=ended）。reference-ui 自身 NEVER 直接呼 unload。
      onCloseRequest: c.onDismiss ?? () => _controller.unload(),
      // Swipe in-place switch → notify-only (track shown id + raise config.onVideoSwitched);
      // NO load (swipe already loaded via template forwarder). swipe-video-switched-notify.
      onSwipeDidSwitchVideo: _notifySwitchedVideo,
      // 🔴 加入活動：`onJoinEvent`（收 eid）維持為 host **觀察** hook。真的打 core join 的預設
      // 走下面帶 keyword 的 `onJoinEventWithKeyword`（EMAIL-LESS 陷阱同構：Flutter template
      // 到不了 core，只能在容器經 _controller 直呼）。這裡是本層**唯一**真的打 core join 的出口；
      // 雙送防線見 buildEventJoinSend doc（日後注入 template eventJoinRequester 須同 change 移除本行）。
      onJoinEvent: c.onJoinEvent,
      onJoinEventWithKeyword: buildEventJoinSend(_controller.requestEventJoin),
      // 🔴 加入活動三層閘（rb-flutter-event-join-gate，parity iOS / Android / RN）：與留言 pill 共用
      // 同一組純函式（登入 → 暱稱 → 放行），永不分歧。攔截（登入 / 暱稱）→ 呈現對應 modal（暱稱記
      // pending join）、MUST NOT markJoined / 送出；設名成功後由 _submitGuestNickname 接續完成該次 join
      // 恰一次。turnkey 預設一律注入（Flutter 無 join host-takeover funnel override）。
      joinGate: _gateEventJoin,
      // 🔴 領獎預設 MUST 帶 email（EMAIL-LESS 已退役）——core 預設領獎路徑 `email` 必填，
      // 缺 email 直接 fail-fast、連 `POST /sdk/video/claim` 都不送。`contact` 在 core 是
      // **具名選填**參數，所以舊寫法 `(winner) => requestAwardClaim(winner)` 編譯完全通過
      // 卻恆送 `contact: null` —— 那正是「turnkey 領獎必然失敗」的物理位置。
      //
      // 🔴 這裡是本層**唯一**真的打領獎 API 的出口。`LivebuyUI.install()`（template 層）
      // 刻意**不**注入 `claimContactSubmitter` / `claimSubmitter`；日後任何 template change
      // 若要注入，MUST 於同一個 change 移除本行，否則同一次「確認領獎」會送出兩次
      // `POST /sdk/video/claim`（第二次後端回「已領過」→ 500 api.fail → 假失敗）。
      onSubmitClaim:
          c.onSubmitClaim ?? buildAwardClaimSubmit(_controller.requestAwardClaim),
      onProductTap: c.onProductTap ??
          (product) => _controller.productOverlay.simulateProductTap(product),
      // 頻道/footer 分享預設（dropin-player-default-share-sheet-flutter，B 等義）：host 設了 onShare →
      // 覆蓋；未設 → 以 channel.share_url（playerTemplate.header.shareUrl）經 share_plus 開系統分享。
      // 空 url → no-op（lbShouldPresentChannelShare）。頻道級不附 ?t=。已設 onShare 的 host 零變更。
      onShare: c.onShare ??
          () {
            final url = LivebuyUI.playerTemplate?.header.shareUrl ?? '';
            if (lbShouldPresentChannelShare(url)) Share.share(url);
          },
      // 聯絡商家 override（dropin-service-link-default-browser-flutter）：原樣傳遞，不加任何智慧預設
      // 運算（`shop.serviceLink` 生產環境拿不到值，見 design.md）。null → PlayerShellView 自己 fallback
      // 到既有 onTapRailItem(serviceLink)。
      onServiceLink: c.onServiceLink,
      // 列縮圖 → seek 到商品介紹時間（issue 5）：beginTime null 不 seek。
      onSeekToProductIntro: c.onSeekToProductIntro ??
          (product) {
            final begin = product.beginTime;
            if (begin != null) _controller.seek(begin.toDouble());
          },
      // 列分享 → 系統分享帶 ?t=（issue 6）。Flutter 無 share_plus → 預設退回 channel-level 分享事件
      // （simulateShareTap，host listener 呈現）；per-product ?t= 需 host override（用 productShareUrlString）。
      onShareProduct: c.onShareProduct ??
          (product) => _controller.operationPanel.simulateShareTap(),
      // 商品明細「更多商品」推薦卡播放圖示 → 換片（rb-flutter-product-detail-recommendations §4）：
      // 同 onPickHot 的 in-place switch 動作，但 MUST NOT 連動任何 dismiss —
      // ProductSheetsOverlayView 完全不呼叫這個 seam 以外的東西，sheet stack 自己維持開啟。
      onSwitchRecommendationVideo: c.onSwitchRecommendationVideo ?? _switchVideo,
      onSkip: c.onSkip ?? _controller.skipStart,
      onWatchNext: c.onWatchNext,
      onPickHot: c.onPickHot ??
          (item) {
            _switchVideo(item.id);
            // Carry the hot item's REAL cover / title so a minimized floating preview shows the
            // switched video (rb-flutter-collapsible-player-track-switch). `LBEndHotItem` carries
            // no preview → "" (static cover).
            widget.config.onVideoSwitchedItem?.call(
              switchedVideoItem(
                id: item.id,
                cover: item.cover,
                title: item.title,
                duration: item.duration,
                liveStatus: 1,
              ),
            );
          },
      onCancel: c.onCancel ?? _controller.cancelAutoNext,
      onRetry: c.onRetry ?? () => _controller.load(_currentVideoId),
      onDismiss: c.onDismiss,
      onLogin: c.onLogin,
      // 設定暱稱 modal 送出 → 呼叫 _controller.setGuestNicknameVerified 驗證式設定訪客留言暱稱
      // （rb-flutter-nickname-taken-inline-error；先前是無驗證、fire-and-forget 的
      // LivebuySDK.setGuestNickname；**不**用 setUser：設名 ≠ 登入，避免誤觸 logged_in 事件 /
      // PendingAuth 重放 / isGuest 翻 false；parity）。**成功**才更新本地鏡像（R2）、關閉 modal，
      // 並依進入意圖（composeAfter）決定是否接著開 composer；**失敗**（暱稱被取走 / 其他驗證錯誤）
      // 回傳錯誤文案、modal 留在畫面上讓使用者重試。host 自訂 config.onSubmitName 則完全接管（含
      // 自己的 Future<String?> 契約）。
      onSubmitName: c.onSubmitName ?? _submitGuestNickname,
      onSend: (message) => _controller.sendChat(message),
      // VOD/回放播放進度條控制平面 (rb-flutter-vod-playback-progress-bar) — DEFAULT bypasses
      // `template.togglePlayPause()` / `.seek()` entirely (their `LivebuyUI.install()` injection
      // point never wires a real requester, see design.md) and calls this container's OWN held
      // `LivebuyPlayerController` directly, mirroring `_toggleMute()` / `onSeekToProductIntro`'s
      // default. `liveStatus` deliberately never supplied to `seek()` — see design.md.
      onTogglePlayPause: c.onTogglePlayPause ?? _controller.togglePlayPause,
      onSeek: c.onSeek ??
          (seconds, {duration}) =>
              _controller.seek(seconds, duration: duration),
    );
  }

  /// LIVE「留言…」pill 預設三層 gating（rb-flutter-live-comment-login-gate，方案 A）：①登入閘優先——訪客且
  /// 該場 guest_comment==0（`operationRail.chatEnabled==false`，讀 LIVE template R2 read path）→ 先本地
  /// 呈現「請先登入」modal；②否則暱稱閘——未選名訪客 → 設定暱稱 modal（送出後接 composer）；③否則開 composer。
  void _gatedComment() {
    // chatEnabled 已含 isGuest（= live && !(isGuest && gc==0)），故傳 isLoggedIn:false 仍正確（與暱稱閘
    // 一致的 guest 假設）。無 LIVE template（demo / golden / LivebuyUI 未裝）→ 預設 true（不 login-gate）。
    final chatEnabled = LivebuyUI.playerTemplate?.operationRail.chatEnabled ?? true;
    if (liveCommentRequiresLogin(false, chatEnabled)) {
      _login.present();
    } else if (liveCommentRequiresNickname(false, _guestNickname)) {
      _nickname.present(true);
    } else {
      _composer.open();
    }
  }

  /// 「加入活動」三層閘（rb-flutter-event-join-gate，parity iOS / Android / RN）：與留言 pill 的
  /// [_gatedComment] **共用同一組訊號 + 同一組純函式**（`isLoggedIn: false` guest 假設、`chatEnabled`
  /// 讀 LIVE template R2 read path、`displayName` 讀本地鏡像 `_guestNickname`），委派 [applyEventJoinGate]
  /// 故兩入口永不分歧。①登入閘優先 → 本地呈現「請先登入」modal；②暱稱閘 → 設定暱稱 modal 並經
  /// [NicknamePromptController.presentForJoin] 記住這次 pending join（設名成功後 [_submitGuestNickname]
  /// 接續完成）；兩者皆回 `true`（已攔截 → `FeedWinOverlayView._handleJoin` MUST NOT markJoined / 送出）。
  /// ③放行 → 回 `false`，走 C1 既有送出。
  bool _gateEventJoin(int eid, String keyword) {
    final chatEnabled =
        LivebuyUI.playerTemplate?.operationRail.chatEnabled ?? true;
    return applyEventJoinGate(
      isLoggedIn: false,
      chatEnabled: chatEnabled,
      displayName: _guestNickname,
      eid: eid,
      keyword: keyword,
      presentLogin: () => _login.present(),
      presentNickname: (e, k) => _nickname.presentForJoin(e, k),
    );
  }

  /// LIVE 底部 bar 暱稱按鈕預設（rb-flutter-nickname-login-gate）：若該場直播留言需登入（訪客 +
  /// guest_comment==0 ⟺ `operationRail.chatEnabled==false`）→ 點暱稱也比照留言先呈現「請先登入」modal
  /// （與 [_gatedComment] 共用同一純函式 [liveCommentRequiresLogin]），不開暱稱 modal——非登入不可留言的
  /// 訪客不該先去設一個用不到的暱稱。否則維持 `_nickname.present(false)`（送出後不接 composer）。
  void _gatedNickname() {
    final chatEnabled = LivebuyUI.playerTemplate?.operationRail.chatEnabled ?? true;
    if (liveCommentRequiresLogin(false, chatEnabled)) {
      _login.present();
    } else {
      _nickname.present(false);
    }
  }

  /// 訂閱鈕預設**登入**閘（rb-flutter-subscribe-login-gate，parity iOS / Android / RN）：讀 LIVE template
  /// 的 identityLabel（與留言閘 / GapSurfacesModel 同一 `isLoggedIn` 來源；demo / golden / LivebuyUI 未裝 →
  /// 預設 false）。訪客（[subscribeRequiresLogin]）→ 先本地呈現「請先登入」modal
  /// （`_login.present(triggerAction: subscribe)` → `AuthGateModalView(subscribe)`），MUST NOT 訂閱；已登入 →
  /// `_controller.videoInfoPanel.simulateSubscribeTap()`（→ core `toggleSubscribe()` + `SUBSCRIBE_CHANGED`，
  /// 行為零改）。訂閱只看登入狀態、不看 chatEnabled。Flutter 唯一可互動訂閱入口=PlayerHeader 頭像徽章
  /// （走容器注入的 `onToggleSubscribe`）；VideoInfoPanel 訂閱 pill 純呈現、無 tap（parity RN）。host 自訂
  /// `config.onToggleSubscribe` 則完全接管、不套 gating。
  void _gatedSubscribe() {
    final isLoggedIn =
        LivebuyUI.playerTemplate?.identityLabel.current?.isLoggedIn ?? false;
    if (subscribeRequiresLogin(isLoggedIn)) {
      _login.present(triggerAction: LBAuthTriggerAction.subscribe);
    } else {
      _controller.videoInfoPanel.simulateSubscribeTap();
    }
  }

  /// 設定暱稱 modal 送出預設（turnkey，rb-flutter-nickname-taken-inline-error）：先呼叫
  /// `_controller.setGuestNicknameVerified(name)`（checkName 驗證式設定暱稱；native 端行為見
  /// `guest-nickname-checkname-on-set-flutter`）。**只有驗證成功**才執行既有（不變）的成功路徑——
  /// 設訪客暱稱鏡像（非 setUser）、關閉 modal、（若由留言 pill 進入）開 composer、續作 pending
  /// join；**驗證失敗**（`PlatformException(code:'GUEST_NAME_TAKEN')` 被取走 / 其他錯誤）則回傳
  /// [guestNicknameSubmitErrorText] 對應的使用者可讀訊息 —— **不** dismiss、**不**更新本地鏡像、
  /// **不**續作 pending join，modal 留在畫面上讓使用者改名重試（見
  /// `GuestNameEditModalView.onSubmit` 的 `Future<String?>` 契約）。
  ///
  /// rb-flutter-event-join-gate：若這次設名是為了一個被暱稱閘擋下的 pending「加入活動」，須先讀出該次
  /// `(eid, keyword)` 再 dismiss（`dismiss()` 會清 pending）；設名成功後自動接續完成該次 join、**恰一次**。
  /// ⚠️ 自 rb-flutter-nickname-taken-inline-error 起「在 dismiss 前讀」**已不足夠** —— 續作變非同步後
  /// 必須更早，見下方跨呈現污染防線（**在 `await` 之前**快照）。
  /// 續作 **bypass gate**（直接 markJoined + core 送出，不再跑 gate——比照留言 pill 設名後直接開 composer
  /// 的「直接接續」語意，避免任何 async 訊號未落地導致誤判暱稱未設而重開 modal）。pending 只在**非**
  /// login-required 情境（暱稱閘）記錄、keyword 非空（`_handleJoin` 已先 guard），故續作安全放行。
  ///
  /// flutter-event-join-gate-notify-host-on-resume：續作那次 join **真的發生了**，故亦 MUST 通知 host 的
  /// 觀察 hook `config.onJoinEvent`（帶原本的 `eid`）**恰一次** —— 補上前 host 會漏收一次真實發生的 join
  /// （`config.onJoinEvent` 的觸發條件因此收成 iff：有 forward ⟺ 有通知）。三路（樂觀 markJoined →
  /// host 觀察 → core 送出）的組合抽在 [completePendingEventJoinNotifyingHost]（容器不可建構 → 抽純函式
  /// 才測得到）。🔴 core 送出**只有** `_controller.requestEventJoin` 這一條，**MUST NOT** 再一併走
  /// `onJoinEventWithKeyword`（= `buildEventJoinSend(_controller.requestEventJoin)`），否則同一次續作
  /// 會送出兩次 —— 雙送防線見該函式 doc。
  ///
  /// 🔴 **跨呈現污染防線（rb-flutter-nickname-taken-inline-error）**：`composeAfter` / `pendingJoin`
  /// **MUST 在 `await` 之前**連同 `_nickname.generation` 一起快照 —— `_nickname` 比它驅動的 modal
  /// 長壽（容器持有、不隨 modal dispose），若在 await **之後**才讀，使用者「送出 → 取消 → 再開一次
  /// 加入活動」的序列會讓舊 continuation 讀到**新一次呈現**的 pending 並完成**別次** join。落地與否
  /// 由 [completeGuestNicknameSubmitIfCurrent] 的世代守門決定，見其 doc。
  Future<String?> _submitGuestNickname(String name) async {
    // 🔴 快照 MUST 在 await 之前（見上方跨呈現污染防線）。
    final submittedGeneration = _nickname.generation;
    final shouldCompose = _nickname.composeAfter;
    final pendingJoin = _nickname.pendingJoin;
    try {
      await _controller.setGuestNicknameVerified(name);
    } catch (e) {
      // 驗證失敗（被取走 / 其他錯誤）：MUST NOT 更新本地鏡像、MUST NOT dismiss、MUST NOT 續作
      // pending join —— 全部留給下一次成功的送出。錯誤文案的分辨邏輯抽成純函式，見其 doc。
      return guestNicknameSubmitErrorText(e);
    }
    // 暱稱**確實已被 core 持久化 + 廣播**（`setGuestNicknameVerified` 成功即代表這件事）——這是與呈現
    // 態無關的事實，故鏡像**無條件**更新，即使這次送出所屬的呈現早已被取消 / 換過（否則本地鏡像會與
    // core 的真實暱稱分歧，讓暱稱閘之後誤判「尚未設名」）。
    _guestNickname = name;
    completeGuestNicknameSubmitIfCurrent(
      submittedGeneration: submittedGeneration,
      currentGeneration: _nickname.generation,
      composeAfter: shouldCompose,
      pendingJoin: pendingJoin,
      dismissNicknamePrompt: _nickname.dismiss,
      openComposer: _composer.open,
      markJoined: (eid) => LivebuyUI.playerTemplate?.feed.markJoined(eid),
      notifyHostJoin: widget.config.onJoinEvent,
      requestEventJoin: _controller.requestEventJoin,
    );
    return null;
  }
}

/// 🔴 暱稱送出成功後的**續作三路 + 世代守門**（rb-flutter-nickname-taken-inline-error）。
///
/// Spec: `openspec/specs/reference-ui-rendering/spec.md`
///   § "Flutter drop-in 容器 LIVE 暱稱 modal + 留言 gating（parity）"
///   （「**只有驗證成功**才視為**該次** join 真的完成……三路同進同出、恰一次」）
///
/// **它修的缺陷（跨呈現污染 / 本 change 引入的 regression）**：`setGuestNicknameVerified` 讓續作變成
/// **非同步**，但 `NicknamePromptController` 是容器持有、**比 modal 長壽**的物件。若在 `await` 之後
/// 才讀 `composeAfter` / `pendingJoin`，下列**全可達**的序列會讓一次送出完成**別次**的 join：
///
/// ```
/// 1. 訪客點「加入活動」A → 暱稱閘擋下 → presentForJoin(11, 'JOIN-P1')
/// 2. 輸入暱稱、按送出 → 進入 await（慢網路 / checkName 往返）
/// 3. 使用者點 scrim 取消 → dismiss() 清掉 P1
/// 4. 改點「加入活動」B → presentForJoin(22, 'JOIN-P2') → 新 modal 開著、使用者還沒打字
/// 5. 舊請求這時才 resolve → 若此時才讀 controller：pendingJoin 讀到 (22,'JOIN-P2')
///    → 關掉使用者正在看的新 modal + markJoined(22) + onJoinEvent(22) + requestEventJoin(22,…)
/// ```
///
/// 使用者從未在新 modal 送出任何暱稱，活動 22 卻被標記已參加、口令留言真的送出去了；`composeAfter`
/// 同樣會被污染（舊送出讀到新一次呈現的 `true` → 開一個使用者沒要求的 composer）。改動前的續作是
/// **全同步**的（讀取與送出同一 tick、不可能交錯），這個時間窗是驗證式送出開出來的。
///
/// **守門規則**：[submittedGeneration]（送出當下拍下的 `NicknamePromptController.generation`）與
/// [currentGeneration]（continuation 恢復當下的值）**相等才落地**。不等 = 這次送出所屬的那次呈現已被
/// 取消或換掉 → 三路**全部**不做（不 dismiss 別人的 modal、不開 composer、不完成任何 join）。呼叫端
/// 仍應**無條件**更新暱稱鏡像 —— 「暱稱已被 core 持久化」是與呈現態無關的事實。
///
/// 快照的 [composeAfter] / [pendingJoin] 一律取送出當下的值：`dismiss()` **不重設** `composeAfter`
/// （sticky，見 `NicknamePromptController.dismiss` doc），所以「取消後舊請求才成功」若改讀當下值，
/// 連 composer 都會被誤開 —— 這是同一個缺陷的較輕變體，同樣由本守門擋住。
///
/// **為何是具名 top-level 函式**：與 [completePendingEventJoinNotifyingHost] / [buildEventJoinSend] /
/// [buildAwardClaimSubmit] 同一既定模式 —— 容器 `LivebuyPlayer` 在測試環境**不可建構**
/// （`LivebuyPlayerController` 走 MethodChannel、無 platform view），留在 State private method 裡的
/// 邏輯無法被測，而這正是本缺陷得以存活的物理位置。抽出後可用 capturing fake + **真實**的
/// `NicknamePromptController` 直接釘住「同世代恰一次落地 / 跨世代三路皆零」。
///
/// 三路本身（樂觀 markJoined → host 觀察 → core 送出）**委派**既有
/// [completePendingEventJoinNotifyingHost]，本函式只加世代守門 + dismiss / composer 兩個呈現副作用，
/// 不複製其「恰一次 / 無 pending 則零次」語意，也不新增第二條 core 出口（雙送防線見該函式 doc）。
///
/// 回傳「這次續作是否落地」（`false` = 被世代守門擋下）。
bool completeGuestNicknameSubmitIfCurrent({
  required int submittedGeneration,
  required int currentGeneration,
  required bool composeAfter,
  required ({int eid, String keyword})? pendingJoin,
  required void Function() dismissNicknamePrompt,
  required void Function() openComposer,
  required void Function(int eid) markJoined,
  required void Function(int eid)? notifyHostJoin,
  required EventJoinRequester requestEventJoin,
}) {
  // 世代已變 = 這次送出所屬的呈現已被取消 / 換掉 → 三路全部不做。
  if (submittedGeneration != currentGeneration) return false;
  dismissNicknamePrompt();
  if (composeAfter) openComposer();
  // 完成一次 join = 樂觀翻已參加（= _model.joinEvent 同效果）+ 通知 host 觀察 hook + core 送出
  // （bypass gate）—— 三路同進同出。
  completePendingEventJoinNotifyingHost(
    pending: pendingJoin,
    markJoined: markJoined,
    notifyHostJoin: notifyHostJoin,
    requestEventJoin: requestEventJoin,
  );
  return true;
}

/// 暱稱被取走時顯示的錯誤文案（`PlatformException(code: 'GUEST_NAME_TAKEN')`）—— 使用者應換一個
/// 名字重試。
const String _guestNicknameTakenErrorText = '此暱稱已被使用，請換一個名字';

/// checkName 遇到其他驗證錯誤時顯示的通用文案（`PlatformException(code: 'CHECKNAME_FAILED')`，或任
/// 何非 `GUEST_NAME_TAKEN` 的例外）—— 可重試。後端刻意不對外細分「其他錯誤」的原因（沿用
/// `guest-nickname-checkname-on-set-flutter` 的既有分類，本層不新造第三種文案）。
const String _guestNicknameCheckFailedErrorText = '發生錯誤，請稍後再試';

/// Map a caught `_controller.setGuestNicknameVerified` failure to the user-facing inline error
/// text [GuestNameEditModalView] shows (rb-flutter-nickname-taken-inline-error). Pure (no widget /
/// I/O) — independently unit-testable, sidestepping the pre-existing "container is
/// test-uninstantiable" constraint (`LivebuyPlayerController` rides a real per-view MethodChannel
/// backed by a platform view, which widget tests cannot construct — see the container doc at the
/// top of this file). `PlatformException(code: 'GUEST_NAME_TAKEN')` (the checkName call rejected
/// the name as taken) → the dedicated "pick another name" copy; anything else (`CHECKNAME_FAILED`,
/// a network failure, or any other exception) → the generic retryable copy.
String guestNicknameSubmitErrorText(Object error) {
  if (error is PlatformException && error.code == 'GUEST_NAME_TAKEN') {
    return _guestNicknameTakenErrorText;
  }
  return _guestNicknameCheckFailedErrorText;
}

// MARK: - VTT subtitle DATA plane wiring (rb-flutter-subtitle-vtt-caption-display)

/// Forward the core's per-channel [LBSubtitleInfo] (fired by `LivebuyPlayerCore.onSubtitleChange`,
/// once per genuine channel load) into the bound [template]'s `handleSubtitleChannelInfo` — the
/// single write path `template.subtitle.{available,url}` has. `template == null` (no `LivebuyUI`
/// installed — demo / golden / a host driving `LivebuyPlayerCore` bare) is a no-op.
///
/// Extracted as a standalone top-level function — same rationale as
/// [completeGuestNicknameSubmitIfCurrent] / [guestNicknameSubmitErrorText] above: the container
/// `LivebuyPlayer` cannot be constructed in a widget test (its `LivebuyPlayerController` rides a
/// real per-view `MethodChannel` backed by a platform view), so an inline closure body at the
/// `LivebuyPlayerCore(onSubtitleChange: ...)` call site would be unreachable by a unit test. This
/// function is that logic, pulled out to where it CAN be tested directly: construct a
/// `DefaultPlayerTemplate`, call this function, assert `template.subtitle.{available,url}`.
void forwardSubtitleChangeToTemplate(LBSubtitleInfo info, DefaultPlayerTemplate? template) {
  template?.handleSubtitleChannelInfo(available: info.available, url: info.url);
}
