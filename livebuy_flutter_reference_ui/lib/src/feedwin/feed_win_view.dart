import 'package:flutter/widgets.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart'
    show LBActiveEvent, LBLegalLinks, LBURLOpenPolicy, LBURLOpenTarget, LBWinner;
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show DefaultPlayerTemplate;
import 'package:url_launcher/url_launcher.dart';

import '../reference_ui_theme.dart';
import 'activity_sheet_view.dart';
import 'chat_feed_view.dart';
import 'feed_win_model.dart';
import 'win_claim_sheet_view.dart';
import 'win_entry_view.dart';

// rb-flutter-live-announce-chat-clearance (問題4) — the merged chat feed and the bottom-left
// LBLiveAnnounce 公告橫幅 share the LIVE overlay's bottom space. The base anchor (96) already clears
// the LIVE bottom bar; when a 公告 is showing the chat lifts by the 公告橫幅's height so its lowest
// rows don't overlap.
/// Base chat-feed bottom anchor — clears the LIVE bottom bar (既有值，無公告時不變).
const double _liveChatBaseClearance = 96;

/// Extra bottom inset for the LBLiveAnnounce 公告橫幅 height (parity iOS `liveAnnounceClearance = 44`).
const double _liveAnnounceClearance = 44;

/// The chat feed's bottom inset on the LIVE overlay. `hasAnnounce == false` → the base
/// [_liveChatBaseClearance] (96, 既有 golden byte-identical); `true` → base + [_liveAnnounceClearance]
/// (96 + 44 = 140) so the lowest chat rows clear the bottom-left 公告橫幅. Pure — exported for unit
/// tests (parity iOS `liveChatBottomInset(hasAnnounce:)` 68/112 / RN 96/140).
double liveChatBottomInset(bool hasAnnounce) =>
    hasAnnounce ? _liveChatBaseClearance + _liveAnnounceClearance : _liveChatBaseClearance;

/// The win entry's (`WinEntryView`, default `variant: win`) vertical anchor
/// (rb-flutter-activity-entry-stack-reversal, R27 — reverses the stacking order
/// landed by `rb-flutter-live-activity-sheet`'s R26) — mirrors the design's
/// reversed conditional `winTop = showActivity ? 'calc(25% + 58px)' : '25%'`
/// (58 = the activity entry's 48 button height + 10 spacing). Pure —
/// unit-testable without a widget pump.
///
/// Formerly named `activityEntryTop` (with the roles swapped: it computed the
/// ACTIVITY entry's conditional anchor while the WIN entry was hardcoded to an
/// unconditional `top: 25%` at the call site) before this change flipped which
/// of the two entries gets the unconditional primary slot — see design.md D1.
/// The visibility gates themselves (`unclaimedCount > 0` for win,
/// `hasActiveEvent` for activity) are UNCHANGED; only which entry's `top` is
/// the constant vs. the conditional one swapped.
double winEntryTop(double containerHeight, {required bool activityEntryVisible}) =>
    containerHeight * 0.25 + (activityEntryVisible ? 58 : 0);

// FeedWinOverlayView — family-2 feed + win container (Flutter SKELETON).
//
// Spec: `reference-ui-rendering/spec.md` (family-2 feed-win, 3 surfaces).
// Flutter sibling of iOS `FeedWinOverlayView.swift` (rb-ios-feed-win) and Android
// `FeedWinOverlayView.kt` (rb-android-feed-win).
//
// The top-level family-2 container. It lays out the THREE family-2 surface widgets
// over the LIVE area:
//
//   1. ChatFeedView       — bottom-leading merged feed (`LBLiveChatStream` /
//                            `LBLiveChatOverlay` / `LBPChatOverlay`)
//   2. WinEntryView       — floating round entry + red badge (`LBWinEntry`)
//   3. WinClaimSheetView  — 四階段領獎 modal（含 email 輸入），shown when an entry is
//                            opened (`LBWinSheet`)
//
// rb-flutter-activity-toast (design 呈現位置改版, `moments.jsx` export 2026-07-03):
// Surface 1 gained a floating extension, `ActivityToastView` — mounted directly
// ABOVE `ChatFeedView` inside the SAME bottom-anchored `Align` + `Padding` (so both
// share one anchor and grow upward together, mirroring `LBLiveChatStream`'s child
// order: `LBActivityToast` → `LBPinnedMessage` → the scroll region). It reads the
// SAME `feedItems` snapshot `ChatFeedView` does and shows only the newest
// `LBFeedKind.activity` row (join/browse/purchase/intro/win) as a self-dismissing
// pill — that kind no longer renders inline inside `ChatFeedView` (see its own
// updated doc comment in `chat_feed.dart`). This does NOT introduce a 4th
// family-2 surface number; it stays a presentation extension of Surface 1 (both
// widgets read the identical activity-feed data source and share one mount point).
//
// This SKELETON owns the layout, a read-only [FeedWinModel], the resolved
// [ReferenceUITheme], and composes the three surface widgets BY TYPE NAME (the
// parallel Surfaces agents land those types after this skeleton — forward refs are
// fine within one Dart package). Until they exist this file will not compile on its
// own; that is expected. The container FIXES the call-site shapes so the agents
// converge on the SUB-VIEW INPUT PATTERN documented below.
//
// ─────────────────────────────────────────────────────────────────────────────
// SUB-VIEW INPUT PATTERN — the contract the 3 Surfaces agents MUST follow
// ─────────────────────────────────────────────────────────────────────────────
//
// Every family-2 surface widget is a `class …View extends StatelessWidget` whose
// constructor takes, IN THIS ORDER (named params):
//
//   1. `theme:` (ReferenceUITheme, required)  — FIRST, always.
//   2. its bound SNAPSHOT VALUE(S)            — read-only state, passed BY VALUE
//                                                from FeedWinModel (never the
//                                                model, never the template).
//   3. optional action callbacks             — trailing, EACH defaulting to a
//                                                no-op. The container owns NO
//                                                action; the host wires the
//                                                exits (win submit / event join).
//
// A surface widget reads ONLY its passed-in values — it MUST NOT reach back into
// FeedWinModel or DefaultPlayerTemplate (one-way data flow), MUST NOT hold a second
// copy of state, MUST render correctly with all callbacks null / omitted (so golden
// / widget tests construct it action-free), MUST NOT use any scrollable container
// (`ListView` / `GridView` / `SingleChildScrollView`) or network image
// (`Image.network` / `NetworkImage`).
//
// The three Surfaces agents implement EXACTLY these constructors (see the call
// sites in `build` below):
//
//   ChatFeedView({
//       required ReferenceUITheme theme,
//       required List<LBFeedItem> items,
//       required String hostName,
//       void Function(int eid)? onJoin })
//
//     Renders the merged feed (tail-retain 7, newest at the tail) as a plain
//     non-scrolling Column; dispatches each row by `LBFeedItem.kind`
//     (.chat → LBChatLine / .eventJoin → LBEventJoinLine / .activity → LBActivityLine
//     by `tier`). The ONLY interactive row is `.eventJoin` (its「加入活動」forwards
//     `onJoin(eid)`); `joined == true` draws the「已參加」state. `hostName`
//     (rb-flutter-loading-announce-restyle) feeds the `.eventJoin` row's restyled
//     header — always-present snapshot value, mirrors `PlayerShellModel.hostName`.
//
//   WinEntryView({
//       required ReferenceUITheme theme,
//       required int unclaimedCount, required List<LBWinner> unclaimedWinners,
//       void Function(LBWinner winner)? onOpen })
//
//     Floating round button + red count badge; drawn ONLY when `unclaimedCount > 0`
//     (badge number == count). Tapping forwards `onOpen(unclaimedWinners.first)`.
//
//   WinClaimSheetView({
//       required ReferenceUITheme theme,
//       required LBWinner winner, required LBClaimClassification classification,
//       LBClaimResultState? resultState, bool submitInFlight = false,
//       bool editable = true, String initialEmail = '',
//       int pageCount = 1, int pageIndex = 0,
//       void Function(String email)? onSubmit, VoidCallback? onDismiss,
//       ValueChanged<int>? onPage,
//       VoidCallback? onOpenTermsOfUse, VoidCallback? onOpenPrivacyPolicy })
//
//     四階段領獎 modal（含 email 輸入，rb-flutter-win-claim-email-flow —— EMAIL-LESS
//     已退役）：`claim`（恭喜中獎 + award.name + ✉ email 欄 +「確認領獎」+ footer，
//     `pageCount > 1` 時卡底追加分頁圓點）→ `confirmSubmit` alert → `submitting`（綁
//     view-model `submitInFlight`）→ `done` / `fail`（綁 `resultState`）。CTA 提交 forwards
//     `onSubmit(email)`；關閉（任何 stage 點外層 scrim，R27 關閉機制簡化——`confirmClose` 與
//     其三顆明確關閉按鈕已退役）forwards `onDismiss`（**純 dismiss**，不放棄中獎資格）；
//     換頁（滑動 / 點分頁圓點，rb-flutter-win-claim-pagination）forwards `onPage(index)`。
//     footer「使用條款 | 隱私政策」兩段文字 forwards `onOpenTermsOfUse` /
//     `onOpenPrivacyPolicy`（rb-flutter-win-claim-footer-links——本容器接到
//     [openLegalLink]，見下方新段落）。
// ─────────────────────────────────────────────────────────────────────────────
//
// 🔴 一次提交只得呼叫 core 一次（rb-flutter-win-claim-email-flow）
// ─────────────────────────────────────────────────────────────────────────────
// Flutter turnkey 的領獎有**兩條並行的線**：
//   (a) `FeedWinModel.submitClaimWithEmail` → `DefaultWinClaim.submitWithEmail`
//       —— 跑 view-model 狀態機（`submitInFlight` / `lastSubmittedWinnerId` /
//       guard），其注入的提交 seam 在 turnkey 路徑上是 inert（`LivebuyUI.install()`
//       刻意不注入 `claimContactSubmitter`）。
//   (b) 容器 seam `onSubmitClaim` → `LivebuyPlayer` 預設實作 → core
//       `requestAwardClaim(winner, contact: LBAwardClaimInput(email: ...))`
//       —— **唯一**真的打 `POST /sdk/video/claim` 的出口。
// 兩條都打 API 就會**送出兩次**（第二次後端回「已領過」→ `500 api.fail` → 使用者看到
// 假失敗）。故 `_handleSubmitClaim` 以 (a) 的回傳值當閘門，且日後任何 template change
// 若要在 `LivebuyUI.install()` 注入 claim seam，MUST 於同一個 change 移除 (b) 的直呼。
//
// ─────────────────────────────────────────────────────────────────────────────
// footer 法務連結路由（rb-flutter-win-claim-footer-links）
// ─────────────────────────────────────────────────────────────────────────────
// `WinClaimSheetView` footer 的「使用條款 | 隱私政策」兩段文字只轉發「使用者點了哪一段」
// （見其 doc comment），實際「開啟哪個連結、以何種方式開啟」由本容器決定。判斷面（純函式
// [legalLinkRoute]）與動作面（[openLegalLink]）刻意分開：前者只呼叫 core
// `LBURLOpenPolicy.decide`、對其 `target` 做窮盡 `switch`，可在 `flutter_test` 下直接單元測；
// 後者呼叫真正的 `url_launcher.launchUrl`，在無 platform channel mock 的測試環境下會丟
// `MissingPluginException`，故刻意不被任何測試直接呼叫（design.md D-F）。

/// A resolved legal-link route — [LBURLOpenPolicy.decide] 的三態壓平（`null` 併入
/// [LegalLinkNone]），供 [openLegalLink] 窮盡 `switch` 派工。`sealed`：新增子型別會讓既有
/// 窮盡 `switch` 變成編譯錯誤（已用 disposable probe 實測，見 design.md D-B），而非靜默漏未
/// 處理的分支。
sealed class LegalLinkRoute {
  const LegalLinkRoute();
}

/// Open [url] with the platform in-app browser (`LaunchMode.inAppBrowserView`).
class LegalLinkPresentInApp extends LegalLinkRoute {
  const LegalLinkPresentInApp(this.url);

  /// 已由 [LBURLOpenPolicy.decide] 解析的 URL。呼叫端 MUST 直接使用這個值，MUST NOT 對原始
  /// 字串另跑一次 parser（見 `LBURLOpenDecision.url` 的既有消費契約）。
  final Uri url;
}

/// Open [url] with the system URL router (`LaunchMode.externalApplication`).
class LegalLinkOpenExternally extends LegalLinkRoute {
  const LegalLinkOpenExternally(this.url);

  /// 同 [LegalLinkPresentInApp.url] 的既有消費契約。
  final Uri url;
}

/// Not openable — 呼叫端 MUST 安全 no-op。
class LegalLinkNone extends LegalLinkRoute {
  const LegalLinkNone();
}

/// 純函式：對 [rawUrl] 呼叫 [LBURLOpenPolicy.decide]，並對其 `target`（`LBURLOpenTarget`，
/// 2 值 enum）做窮盡 `switch`（MUST NOT 寫 `default`——core 日後新增 target 時本行 MUST 編譯
/// 錯而非靜默落入某分支）。`decide` 回傳 `null`（不可開）→ [LegalLinkNone]。
LegalLinkRoute legalLinkRoute(String rawUrl) {
  final decision = LBURLOpenPolicy.decide(rawUrl);
  if (decision == null) return const LegalLinkNone();
  switch (decision.target) {
    case LBURLOpenTarget.inApp:
      return LegalLinkPresentInApp(decision.url);
    case LBURLOpenTarget.external:
      return LegalLinkOpenExternally(decision.url);
  }
}

/// Action shell：對 [legalLinkRoute] 的回傳值窮盡 `switch`（3 子型別物件 pattern，MUST NOT 寫
/// `default`）並執行對應的開啟動作。刻意不被任何測試直接呼叫（見上方檔頭說明 + design.md
/// D-F）——正確性完全由 [legalLinkRoute] 的判斷覆蓋。
Future<void> openLegalLink(String rawUrl) async {
  switch (legalLinkRoute(rawUrl)) {
    case LegalLinkPresentInApp(url: final url):
      await launchUrl(url, mode: LaunchMode.inAppBrowserView);
    case LegalLinkOpenExternally(url: final url):
      await launchUrl(url, mode: LaunchMode.externalApplication);
    case LegalLinkNone():
      break;
  }
}

/// The family-2 feed-win container. Binds the relevant template `ChangeNotifier`s
/// (`feed` + `winClaim`) with `ListenableBuilder`, re-reads the read-only
/// [FeedWinModel] on each notify, and passes snapshot values BY VALUE to the three
/// surface widgets. Paints with the resolved [ReferenceUITheme].
///
/// `template == null` → the container uses the deterministic demo seeds (no
/// listenables to bind); the host normally supplies a live [DefaultPlayerTemplate].
class FeedWinOverlayView extends StatefulWidget {
  /// Live template (host-supplied). `null` → deterministic demo seeds.
  final DefaultPlayerTemplate? template;

  /// Resolved reference-ui theme.
  final ReferenceUITheme theme;

  // Host-wired interaction callbacks. The container owns NO action — each is
  // forwarded to the host (which wires it to the template exit). All optional.

  /// Host **OBSERVE** hook for an event-join tap, carrying ONLY the event id — the
  /// existing 1.3.0 public param, signature UNCHANGED. Fires alongside the core send
  /// (below) so a host can react to a join, but it CANNOT carry `keyword` and does
  /// NOT itself reach core. `null` (drop-in default) → nothing observes; the core
  /// send still happens via [onJoinEventWithKeyword]. (Optimistic `markJoined` is
  /// done locally in `_handleJoin`, not by this hook.)
  final void Function(int eid)? onJoinEvent;

  /// Keyword-carrying event-join core send (rb-flutter-event-join-reaches-core). The
  /// turnkey container wires this to core `requestEventJoin(eid, keyword)` — the ONLY
  /// place this layer actually reaches the core join API (parity iOS / Android drop-in;
  /// same container-direct mechanism the claim seam uses, because the Flutter template
  /// holds no native player ref and `LivebuyUI.install()` injects no `eventJoinRequester`).
  /// Additive / optional so [onJoinEvent]'s public signature stays unchanged. `null`
  /// (demo / golden / no live controller) → the send is a safe no-op.
  final void Function(int eid, String keyword)? onJoinEventWithKeyword;

  /// 「加入活動」三層閘（rb-flutter-event-join-gate，parity iOS / Android / RN）. container-internal
  /// seam（**非** host API）: [_handleJoin] runs this FIRST (after the `keyword.isEmpty` guard), BEFORE
  /// the optimistic `markJoined` / observe hook / core send. Returns `true` when the gate INTERCEPTED
  /// the intent (raised a 登入 / 暱稱 modal) → `_handleJoin` MUST NOT `markJoined` / observe / send.
  /// `null` (demo / golden / a custom `ReferenceUIDesign` composing this widget directly) → NO gating,
  /// `_handleJoin` proceeds with the C1 behaviour → baseline byte-identical.
  final bool Function(int eid, String keyword)? joinGate;

  /// Host-wired win-claim submit **carrying the user-entered email**
  /// (rb-flutter-win-claim-email-flow). The turnkey container wires it to core
  /// `requestAwardClaim(winner, contact: LBAwardClaimInput(email: email))` — the
  /// ONLY place this layer actually hits the claim API (see the 🔴 note above).
  ///
  /// 🔴 型別由 `ValueChanged<LBWinner>` **加寬**（Dart 不允許少參數 callback 指派給多參數
  /// 函式型別 → 對已覆寫此 seam 的 host 是編譯期 BREAKING；刻意取捨，見 change design D-4）。
  final void Function(LBWinner winner, String email)? onSubmitClaim;

  /// Scrollable chat variant (runtime): binds the deeper `feedHistory` so the user can
  /// scroll up to view history (parity #5b/#6). Default false → ambient feedItems +
  /// non-scrolling Column (golden byte-identical).
  final bool chatScrollable;

  /// Whether the family-1 info panel (VideoInfoPanel bottom sheet) is currently open. The chat
  /// feed (rendered ABOVE the shell layer) would otherwise occlude / swallow taps on the sheet,
  /// so it is hidden while the panel is up (parity iOS rb-ios-info-panel-not-covered-by-chat).
  /// Default false. The chat is ALSO LIVE-only — dropped in VOD (parity rb-ios-hide-chat-feed-
  /// in-vod): with no live template (`isLive` false / demo seeds) it is not drawn.
  final bool infoPanelOpen;

  /// Right-edge clearance (pt) reserved for the chat feed so it stays in the design's LEFT column
  /// (`live-chrome.jsx` `LBLiveChatOverlay` `right:152`) and does NOT extend under the side rail /
  /// floating bag / win entry on the right (parity iOS FeedWinOverlayView `chatTrailingInset` =
  /// MinimalDesign `liveChatTrailingClearance` 152). Default 0 (demo / golden keep the full width).
  final double chatTrailingInset;

  /// 乾淨模式（rb-flutter-gesture-clean-mode-rewrite）：`PlayerShellView`'s `_cleanMode`
  /// bubbled through the container (`onCleanModeChange` → `PlayerOverlayContext.cleanMode` →
  /// `MinimalDesign.playerOverlay` forward),比照既有 [infoPanelOpen] 冒泡管線（design.md D5）。
  /// `true` → hides this WHOLE widget (聊天 feed + 中獎 toast / 入口一起隱藏 — 刻意沿用
  /// [infoPanelOpen] 已建立的隱藏粒度，非本欄位新開更細的機制). Default `false` — every
  /// EXISTING call site keeps rendering unchanged.
  final bool cleanMode;

  const FeedWinOverlayView({
    super.key,
    this.template,
    required this.theme,
    this.chatScrollable = false,
    this.infoPanelOpen = false,
    this.chatTrailingInset = 0,
    this.onJoinEvent,
    this.onJoinEventWithKeyword,
    this.joinGate,
    this.onSubmitClaim,
    this.cleanMode = false,
  });

  @override
  State<FeedWinOverlayView> createState() => _FeedWinOverlayViewState();
}

class _FeedWinOverlayViewState extends State<FeedWinOverlayView> {
  /// Read-only snapshot bridge (re-read inside the ListenableBuilder on notify).
  late FeedWinModel _model = FeedWinModel(template: widget.template);

  /// Presentation-only: the winner whose claim sheet is currently open, or null
  /// (no sheet). Set when the entry is tapped, or when the user pages to a
  /// different winner (rb-flutter-win-claim-pagination — `onPage` resolves the new
  /// index against the live list and stores the resulting WINNER, not the index
  /// itself). Cleared on dismiss.
  ///
  /// 🔴 **Deliberately an identity reference, not a re-derived `unclaimedWinners[i]`
  /// lookup** — see `_buildContent`'s `claimWinner` derivation for why. design.md
  /// D-1 describes deriving the open winner purely as `unclaimedWinners[clampedIndex]`
  /// every render (closing the sheet whenever the list is empty); implemented
  /// literally, that breaks a PRE-EXISTING invariant this same file already relies
  /// on (`rb-flutter-win-claim-email-flow`'s "claimed 結果 → view-model 移除未領" test):
  /// `DefaultWinClaim.handleAwardClaimResult` removes the winner from `_unclaimed`
  /// in the SAME update that sets `resultState` to a success, so at the exact
  /// render where the `done` screen needs to appear, `unclaimedWinners` has
  /// ALREADY lost that winner — a pure list-index derivation would auto-close the
  /// sheet instead of showing the success screen. Holding the winner's own VALUE
  /// (immutable data — `LBWinner`/`LBAward` never mutate in place, so there is no
  /// "drift" risk in what gets displayed) sidesteps that, while `_buildContent`
  /// still re-locates this winner's LIVE position every render for the
  /// `pageIndex`/`pageCount` the pagination UI needs, and still closes the sheet
  /// when the winner has genuinely disappeared for an unrelated reason (design.md's
  /// Risk mitigation: the list shrinking while browsing a later page) — see
  /// `_buildContent`.
  LBWinner? _openClaimWinner;

  /// Presentation-only: whether the activity sheet (`ActivitySheetView`) is
  /// currently open (rb-flutter-live-activity-sheet). Set by `WinEntryView
  /// (variant: activity)`'s [WinEntryView.onOpenActivity]; cleared on dismiss.
  /// Unlike [_openClaimWinner] this does NOT capture an identity — the sheet
  /// always presents the LIVE `m.currentActiveEvent` (`DefaultActiveEvent`
  /// exposes only a single current event, so there is no "which one" to lose
  /// track of the way `unclaimedWinners` can shrink around a captured winner).
  bool _activitySheetOpen = false;

  @override
  void didUpdateWidget(covariant FeedWinOverlayView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.template != widget.template) {
      _model = FeedWinModel(template: widget.template);
      _openClaimWinner = null;
      _activitySheetOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.template;

    // Bind the relevant template ChangeNotifiers so a change re-reads the model.
    // With no live template (demo seeds) there is nothing to listen to — render the
    // seeds directly.
    final mergeable = <Listenable>[
      if (t != null) ...[t.feed, t.winClaim, t.activeEvent],
    ];

    Widget content = _buildContent(context);
    if (mergeable.isNotEmpty) {
      content = ListenableBuilder(
        listenable: Listenable.merge(mergeable),
        builder: (context, _) => _buildContent(context),
      );
    }
    return content;
  }

  Widget _buildContent(BuildContext context) {
    final theme = widget.theme;
    final m = _model;

    // The chat feed is LIVE-only (parity rb-ios-hide-chat-feed-in-vod) AND hidden while the info
    // panel is up (parity rb-ios-info-panel-not-covered-by-chat). VOD or info-panel-open → the
    // chat is dropped so it neither occludes the info-panel sheet nor swallows the VOD side rail's
    // taps. `isLive` reads the live template's header (false for demo seeds / no template).
    // 乾淨模式（rb-flutter-gesture-clean-mode-rewrite）追加 `&& !widget.cleanMode` —— 冒泡自
    // `PlayerShellView._cleanMode`（design.md D5），比照既有 infoPanelOpen 的同一個判斷式、同一個
    // 隱藏粒度（ActivityToastView + ChatFeedView 一起隱藏；WinEntryView / WinClaimSheetView 不受影響）。
    final chatVisible = (widget.template?.header.isLive ?? false) &&
        !widget.infoPanelOpen &&
        !widget.cleanMode;

    // rb-flutter-win-claim-pagination — re-derive Surface 3's presentation state every
    // render from `_openClaimWinner` (the captured identity, see its doc comment for why
    // a pure `unclaimedWinners[index]` derivation regresses the pre-existing "claimed →
    // done screen" behavior) + the LIVE `m.unclaimedWinners`:
    //   - `liveIndex` — the open winner's CURRENT position in the live list (`-1` if it
    //     is no longer there), recomputed every render so paging / external list
    //     mutations are always reflected — never a cached index.
    //   - `claimWinner` — `null` closes the sheet (implicit dismiss). Stays `_openClaimWinner`
    //     when it's still live (`liveIndex >= 0`) OR a submission for it just concluded /
    //     is in flight (`hasPendingResult` — the view-model's OWN removal-on-claim is
    //     expected there, not a reason to close). Becomes `null` only when the winner
    //     disappeared for an unrelated reason while merely browsing (design.md's Risk
    //     mitigation: re-clamp or close cleanly — this closes cleanly).
    final unclaimedForClaim = m.unclaimedWinners;
    final openWinner = _openClaimWinner;
    final liveIndex = openWinner == null
        ? -1
        : unclaimedForClaim.indexWhere((w) => w.id == openWinner.id);
    final hasPendingResult = m.resultState != null || m.submitInFlight;
    final LBWinner? claimWinner =
        (openWinner != null && (liveIndex >= 0 || hasPendingResult))
            ? openWinner
            : null;
    final claimPageIndex = liveIndex >= 0 ? liveIndex : 0;
    final claimPageCount = unclaimedForClaim.length;

    return Stack(
      children: [
        // Surface 1 — merged feed pinned to the bottom-leading LIVE region (the
        // overlay chrome stream). Newest at the tail; non-scrolling Column. LIVE-only +
        // hidden while the info panel is up (chatVisible).
        if (chatVisible)
          Align(
            alignment: Alignment.bottomLeft,
            child: Padding(
              // Right inset keeps the chat in the design's LEFT column (LBLiveChatOverlay
              // right:152) so it clears the side rail / floating bag / win entry (parity iOS).
              // bottom: 動態避讓 — 有公告（m.hasAnnounce）時往上讓出 LBLiveAnnounce 橫幅高度（96→140,
              // rb-flutter-live-announce-chat-clearance 問題4）；無公告 → 96（既有 baseline）。
              // left: 10 — 對齊 LIVE 底部 bar 購物袋鈕左側邊距（LiveBottomBarView._barHPadding = 10，
              // rb-flutter-live-chat-card-edge-align，parity iOS rb-ios-live-chat-card-edge-align；
              // 舊值 12 為既有平台間分歧，本次一併收斂）。
              padding: EdgeInsets.only(
                  left: 10,
                  bottom: liveChatBottomInset(m.hasAnnounce),
                  right: widget.chatTrailingInset),
              // ActivityToastView (rb-flutter-activity-toast) sits ABOVE the chat stream,
              // both anchored together (Column, mainAxisSize.min) so they grow upward as a
              // unit — mirrors design `LBLiveChatStream`'s child order.
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Surface 1 extension — floating newest-activity toast (rb-flutter-activity-
                  // toast). Reads the SAME ambient `feedItems` snapshot regardless of
                  // `chatScrollable` — the "newest activity" is identical in `feedItems` and
                  // `feedHistory` (the former is a tail slice of the latter, sharing element
                  // references), so there is no need to bind the deeper history here.
                  ActivityToastView(theme: theme, items: m.feedItems),
                  ChatFeedView(
                    theme: theme,
                    // Scrollable variant binds the deeper history (scroll up for history);
                    // the ambient / golden path keeps the N=7 feedItems. The bottom:96 anchor
                    // already clears the LIVE bottom bar (#2 satisfied by construction).
                    items: widget.chatScrollable ? m.feedHistory : m.feedItems,
                    hostScrollable: widget.chatScrollable,
                    // rb-flutter-loading-announce-restyle — restyled eventJoin header 主播名.
                    hostName: m.hostName,
                    // rb-flutter-event-join-reaches-core — wire the keyword-carrying
                    // line so the container reaches core `requestEventJoin(eid, keyword)`.
                    onJoinWithKeyword: _handleJoin,
                    // chat-message-taxonomy ⑤ — 置頂留言橫幅（無釘選 → null → 不出像素）。
                    pinned: m.pinned,
                  ),
                ],
              ),
            ),
          ),

        // Surface 2 — floating activity (抽獎) entry badge, RIGHT-side at the
        // UNCONDITIONAL primary top 25% slot (design `LBWinEntry(variant: activity)`
        // `top:'25%'`, trailing 12, rb-flutter-activity-entry-stack-reversal, R27 —
        // this is the PRIMARY slot as of R27; before this change it was the win
        // entry that held the unconditional slot, see `winEntryTop`'s doc comment).
        // Independent gate (`hasActiveEvent`); drawn ONLY when an activity is live.
        //
        // Surface 2b — the win-claim entry badge (`WinEntryView`, default
        // `variant: win`), now SECONDARY: stacked directly below the activity entry
        // (`winEntryTop` — same trailing 12, `top: 25% + 58` when the activity entry
        // is ALSO showing, or `top: 25%` alone when it is not — see the pure
        // function's doc comment). Drawn ONLY when `unclaimedCount > 0`. The two
        // entries are NOT mutually exclusive (design.md D2, carried over from
        // `rb-flutter-live-activity-sheet`) — either, both, or neither may be
        // showing at once; only which one gets the fixed primary anchor swapped.
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final activityEntryVisible = m.hasActiveEvent;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    top: constraints.maxHeight * 0.25,
                    right: 12,
                    child: WinEntryView(
                      theme: theme,
                      variant: WinEntryVariant.activity,
                      hasActiveEvent: m.hasActiveEvent,
                      currentEvent: m.currentActiveEvent,
                      onOpenActivity: _handleOpenActivity,
                    ),
                  ),
                  Positioned(
                    top: winEntryTop(constraints.maxHeight,
                        activityEntryVisible: activityEntryVisible),
                    right: 12,
                    child: WinEntryView(
                      theme: theme,
                      unclaimedCount: m.unclaimedCount,
                      unclaimedWinners: m.unclaimedWinners,
                      onOpen: _handleOpenClaim,
                    ),
                  ),
                ],
              );
            },
          ),
        ),

        // Surface 3 — 四階段領獎 modal（含 email 輸入），presented over the feed when an
        // entry has been opened (presentation-only open state; `submitInFlight` and the
        // RESULT are template-driven). `claimWinner` (computed above) is `null` whenever
        // there is nothing valid to show — the sheet simply is not mounted (an implicit
        // dismiss), never indexes out of bounds.
        if (claimWinner != null)
          Positioned.fill(
            child: WinClaimSheetView(
              theme: theme,
              winner: claimWinner,
              classification: m.classify(claimWinner),
              resultState: m.resultState,
              // 送出中的**唯一**真相（本層不自造第二份）。
              submitInFlight: m.submitInFlight,
              pageCount: claimPageCount,
              pageIndex: claimPageIndex,
              onSubmit: (email) => _handleSubmitClaim(claimWinner, email),
              onDismiss: _handleDismissClaim,
              // rb-flutter-win-claim-pagination — 換頁只更新容器的開啟中 winner，
              // presentation only（不觸碰 view-model / 未領清單本身）。`i` 越界（例如清單
              // 已縮短）安全 no-op，維持顯示現有內容不變。
              onPage: (i) {
                if (i < 0 || i >= unclaimedForClaim.length) return;
                setState(() => _openClaimWinner = unclaimedForClaim[i]);
              },
              // rb-flutter-win-claim-footer-links — footer 兩段文字的開啟路由，見檔頭
              // 「footer 法務連結路由」說明。
              onOpenTermsOfUse: () => openLegalLink(LBLegalLinks.termsOfUse),
              onOpenPrivacyPolicy: () => openLegalLink(LBLegalLinks.privacyPolicy),
            ),
          ),

        // Surface 4 — 抽獎活動彈窗 (`ActivitySheetView`, rb-flutter-live-activity-sheet),
        // presented when the activity entry has been opened. `m.currentActiveEvent`
        // (a LIVE getter) gates the mount — mirrors `WinClaimSheetView` only mounting
        // when a `winner` is selected; an activity that ends mid-sheet (the snapshot
        // going `null`) closes the sheet as an implicit dismiss rather than showing a
        // stale event.
        if (_activitySheetOpen && m.currentActiveEvent != null)
          Positioned.fill(
            child: ActivitySheetView(
              theme: theme,
              event: m.currentActiveEvent!,
              joined: m.activeEventJoined,
              // rb-flutter-activity-sheet-pagination — pageCount/pageIndex read
              // straight off the bound template (`DefaultActiveEvent.activities` /
              // `.currentActivityPageIndex`); `onPage` forwards to
              // `setActivityPageIndex`, which already clamps internally, so no
              // container-level bounds-check is needed here.
              pageCount: m.activities.length,
              pageIndex: m.activityPageIndex,
              onPage: m.setActivityPageIndex,
              onJoin: _handleJoinActivity,
              onClose: _handleCloseActivitySheet,
              onOpenTermsOfUse: () => openLegalLink(LBLegalLinks.termsOfUse),
              onOpenPrivacyPolicy: () => openLegalLink(LBLegalLinks.privacyPolicy),
            ),
          ),
      ],
    );
  }

  /// Handle an event-join「加入活動」tap, carrying the CTA row's real [keyword]
  /// (rb-flutter-event-join-reaches-core).
  ///
  /// Order is deliberate (mirrors the claim seam's single-source gating):
  ///   0. [keyword] empty → return early: MUST NOT flip「已參加」, MUST NOT send.
  ///      (The CTA is only drawn when keyword is non-empty, so this is defensive —
  ///      it also guarantees the optimistic flip only happens on a real send.)
  ///   0.5. [joinGate] (rb-flutter-event-join-gate) — the three-tier gate (登入 → 暱稱 →
  ///      放行), consulted BEFORE any side effect. `true` → the gate INTERCEPTED (raised a
  ///      登入 / 暱稱 modal; the 暱稱 branch also recorded this join as pending) → return:
  ///      MUST NOT `markJoined`, MUST NOT observe, MUST NOT send. `null` (demo / golden /
  ///      custom design) → `?? false` → proceed (baseline byte-identical).
  ///   1. `_model.joinEvent(eid)` — the OPTIMISTIC `markJoined` flip (a pure UI flip
  ///      on the live template; it does NOT reach core). No-op for demo instances.
  ///   2. `onJoinEvent?.call(eid)` — the host OBSERVE hook (eid only), fires alongside.
  ///   3. `onJoinEventWithKeyword?.call(eid, keyword)` — the ACTUAL core send: the
  ///      container wires it to `_controller.requestEventJoin(eid, keyword)` (the ONLY
  ///      place this layer reaches the core join API). `null` (demo / no controller)
  ///      → safe no-op. Exactly ONE core send per tap — the observe hook cannot cause
  ///      a second send (the host has no access to the container's core controller).
  void _handleJoin(int eid, String keyword) {
    if (keyword.isEmpty) return;
    if (widget.joinGate?.call(eid, keyword) ?? false) return;
    _model.joinEvent(eid);
    widget.onJoinEvent?.call(eid);
    widget.onJoinEventWithKeyword?.call(eid, keyword);
  }

  /// Open the claim sheet on the tapped (earliest unclaimed) winner — presentation
  /// only, no core call.
  void _handleOpenClaim(LBWinner winner) {
    setState(() => _openClaimWinner = winner);
  }

  /// Forward a claim submit **carrying the user-entered email**.
  ///
  /// 🔴 順序與閘門是刻意的（見檔頭「一次提交只得呼叫 core 一次」）：
  ///   1. 先走 view-model（`FeedWinModel.submitClaimWithEmail` →
  ///      `DefaultWinClaim.submitWithEmail`）跑 guard + in-flight 狀態機。
  ///   2. **只有它回傳 `true`（真的被接受）時**，才呼叫 host / turnkey 的 `onSubmitClaim`
  ///      —— 那是唯一真的打 core 領獎 API 的地方。
  ///
  /// 這樣「view-model 願不願意送」與「API 有沒有真的被送」永遠一致：double-tap 時
  /// view-model 的 re-entrancy guard 回 `false`，第二次就**不會**打出 `POST /sdk/video/claim`
  /// （否則後端回「已領過」→ `500 api.fail` → 使用者看到假失敗）。
  ///
  /// demo / 未綁定 template 的實例回 `false` → 兩者皆為安全 no-op。sheet 維持開啟，讓
  /// template 驅動的 `submitInFlight` / `resultState` 渲染送出中 / 結果。
  void _handleSubmitClaim(LBWinner winner, String email) {
    final accepted = _model.submitClaimWithEmail(winner, email);
    if (accepted) widget.onSubmitClaim?.call(winner, email);
  }

  /// Close the claim modal（任何 stage 點外層 scrim —— R27 關閉機制簡化，claim/fail 卡的
  /// 明確關閉按鈕與 `confirmClose` 二次確認皆已退役，見 `WinClaimSheetView` 檔頭說明）。
  ///
  /// 🔴 **純 dismiss**：先讓 view-model 清掉本次領獎的暫態（`DefaultWinClaim.dismissClaim()`
  /// 只清 `resultState` + `submitInFlight`），再清掉容器自己的呈現綁定。MUST NOT 從
  /// `unclaimedWinners` 移除該 winner、MUST NOT 呼叫任何 API、MUST NOT 遞減未領徽章 ——
  /// 設計稿的「放棄資格、此動作無法復原」是刻意的 UX 摩擦文案（R27 已隨關閉機制簡化退役該
  /// 文案，但行為本身延續不變），行為不跟隨（權威：
  /// `design/contract/claude-design-sync.md` R13 刻意分歧 1/2）。
  void _handleDismissClaim() {
    _model.dismissClaim();
    setState(() => _openClaimWinner = null);
  }

  /// Open the activity sheet (`WinEntryView(variant: activity)`'s tap intent) —
  /// presentation only, no core call. The tapped [event] itself is not captured
  /// (unlike [_handleOpenClaim]'s winner) — the sheet always re-reads the LIVE
  /// `m.currentActiveEvent` every render (`DefaultActiveEvent` exposes only a
  /// single current event, so there is nothing to disambiguate).
  void _handleOpenActivity(LBActiveEvent event) {
    setState(() => _activitySheetOpen = true);
  }

  /// Handle the activity sheet's「立即參加」CTA tap
  /// (rb-flutter-activity-entry-cta-gate-and-close).
  ///
  /// Order mirrors [_handleJoin]'s existing gating discipline (same shared
  /// [widget.joinGate] seam, consulted BEFORE any side effect):
  ///   0. No current event, or its `keyword` empty/absent → return early. The
  ///      real CTA is only wired to this handler when
  ///      `activitySheetCtaKind(keyword, joined) == .join` (keyword non-empty,
  ///      not yet joined — see `activity_sheet.dart`), so this is defensive,
  ///      same posture as [_handleJoin]'s own `keyword.isEmpty` guard.
  ///   1. [widget.joinGate] (rb-flutter-event-join-gate three-tier gate: 登入 →
  ///      暱稱 → 放行) consulted with the open event's `(id, keyword)`. `true` →
  ///      the gate INTERCEPTED (raised a 登入 / 暱稱 modal) → return: MUST NOT
  ///      join, MUST NOT close the sheet (the user still needs to see it while
  ///      handling that modal — closing here would leave them unsure which
  ///      activity the login/nickname flow was for). `null` (demo / golden /
  ///      no host gate) → `?? false` → proceed, existing behaviour.
  ///   2. `_model.joinActiveEvent()` — forwards to the bound template
  ///      (`DefaultActiveEvent.join()` — the view-model handles dedupe-by-id,
  ///      this layer does not repeat that check). No-op for demo instances (no
  ///      bound template).
  ///   3. Close the sheet (`_activitySheetOpen = false`) — ONLY reached on an
  ///      actual join. Before this change the sheet never auto-closed on
  ///      success; the user had to tap the separate close affordance even
  ///      after「已參加」took effect.
  void _handleJoinActivity() {
    final event = _model.currentActiveEvent;
    if (event == null) return;
    final keyword = event.keyword ?? '';
    if (keyword.isEmpty) return;
    if (widget.joinGate?.call(event.id, keyword) ?? false) return;
    _model.joinActiveEvent();
    setState(() => _activitySheetOpen = false);
  }

  /// Close the activity sheet. 🔴 **純 dismiss** (design.md D4): closing the
  /// sheet is NOT "gave up the activity" — MUST NOT call any view-model method,
  /// only clear the container's own local open/closed state (there is no
  /// R13-style confirm-dismiss dialog for this sheet).
  void _handleCloseActivitySheet() {
    setState(() => _activitySheetOpen = false);
  }
}
