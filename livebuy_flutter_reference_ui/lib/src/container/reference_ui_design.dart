import 'package:flutter/widgets.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart'
    show LBProduct, LBVideoItem, LBWinner;
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show DefaultPlayerTemplate, DefaultWidgetTemplate, LBSideRailKind, LBEndHotItem;

import '../reference_ui_theme.dart';
import '../playershell/player_shell_view.dart';
import '../feedwin/feed_win_view.dart';
import '../productsheets/product_sheets_view.dart';
import '../moments/moments_view.dart';
import '../gapsurfaces/gap_surfaces_view.dart';
import '../widget/widget_model.dart' show WidgetGoods;
import '../widget/widget_overlay_view.dart' show WidgetOverlayView;
import '../widget/floating_widget.dart';
import 'chat_composer_bar.dart';

// MARK: - ReferenceUIDesign — the design seam (Flutter parity of iOS
//         `LivebuyReferenceUI/Container/ReferenceUIDesign.swift`, granularity A)
//
// The three turnkey containers (`LivebuyPlayer` / `LivebuyWidget` /
// `CollapsibleLivebuyPlayer`) used to HARD-CODE the concrete `minimal` surfaces at the
// assembly point: `LivebuyPlayer.build` composed `PlayerShellView` + `FeedWinOverlayView` +
// `ProductSheetsOverlayView` + `MomentsOverlayView` + `GapSurfacesOverlayView` +
// `ChatComposerBar` directly in one `Stack`; `LivebuyWidget` rendered `WidgetOverlayView`;
// the collapsible presenter drew `FloatingWidgetView`.
//
// The container is already decoupled from THEME (`_resolveTheme()` resolves a
// `ReferenceUITheme` 5-token palette and passes it down), but it was hard-bound to the
// `minimal` DESIGN (which surfaces, in what layout). A whole different design — different
// component shapes + layout structure + color system, beyond what the thin `ReferenceUITheme`
// palette can express — had no seam to plug into.
//
// `ReferenceUIDesign` is that seam (decision D1: granularity A — the WHOLE overlay / widget
// surface / floating card is one builder, so a design can change the LAYOUT, not just swap
// surfaces). It is an ABSTRACT CLASS, not an enum switch (D2): the container holds the
// abstraction and knows NOTHING about any concrete design (no `switch design { … }`). That
// also forward-fits an externally-hosted design (the container MUST NOT import any concrete
// design). Builders return `Widget` — Dart has no `some View` / associatedtype concern, so the
// type erasure iOS needs (`AnyView`) is moot here; a plain `Widget` is the natural return.
//
// This is a PURE DECOUPLING seam: `MinimalDesign` (below) wraps the existing minimal
// composition VERBATIM and is the default conformer; behavior is pixel-for-pixel unchanged
// (existing golden baselines stay byte-identical). The container does NOT接後台
// `sdkConfig.design` here — backend-selectable design is a follow-up change.

// MARK: - Per-surface context value types
//
// Each builder receives a context value type that bundles the resolved `ReferenceUITheme` +
// the host-wired interaction closures the surface needs. Mirroring the Flutter surfaces
// (which are TEMPLATE-bound and driven by callbacks — the container resolves `config.onX ??
// <default>` before composing), the contexts carry the ALREADY-RESOLVED closures, not raw
// view-models. The context holds NO state of its own. All fields are public so a host-supplied
// `ReferenceUIDesign` (via `config.design`) can read them.

/// Inputs for the WHOLE player overlay (granularity A: the entire `Stack` of shell + feed-win
/// + product-sheets + moments + gap-surfaces + on-demand composer is one seam). The fields are
/// the resolved theme + composer controller + every host-wired interaction closure the minimal
/// surfaces consume; a design decides how to lay them out.
@immutable
class PlayerOverlayContext {
  final ReferenceUITheme theme;

  /// The live per-player [DefaultPlayerTemplate] (from `LivebuyUI.playerTemplate`), or `null`
  /// for demo / golden composition. Bound into every surface so the overlay shows LIVE state
  /// (header / rail / merged feed / info panel) instead of the deterministic seeds. `null` →
  /// surfaces degrade to their seeds (golden byte-identical).
  final DefaultPlayerTemplate? template;

  final ChatComposerController composerController;

  /// On-demand 設定暱稱 modal controller (LIVE 暱稱 button + 留言 gating). Drives the
  /// guest-name modal's visibility + runtime editability in `GapSurfacesOverlayView`. parity.
  final NicknamePromptController nicknameController;

  /// On-demand「請先登入」(commentSend) modal controller for the LIVE 留言 login gate. Drives the
  /// login modal in `GapSurfacesOverlayView` (rb-flutter-live-comment-login-gate). parity.
  final LoginPromptController loginController;

  /// Whether the product sheets load real (live) product photos vs deterministic placeholders.
  final bool live;

  /// MERCHANT capability gate for the product sheet's「只剩庫存 N 組」caption
  /// (rb-flutter-show-stock-caption-toggle). RAW `sdkConfig.extensions['show_stock']` wire
  /// value, carried verbatim from `LivebuyPlayerConfig.showStock` to
  /// `ProductSheetsOverlayView` — this DTO does not interpret it and the design layer does
  /// not normalize it (the consuming sheet owns the single `normalizeShowStock` fallback).
  ///
  /// ⚠️ The field has to EXIST here — it is not redundant plumbing. Flutter's
  /// `PlayerOverlayContext` carries resolved closures + a few by-value flags rather than the
  /// whole `LivebuyPlayerConfig`, so adding the setting only to the config would be a broken
  /// chain. (It is nevertheless an OPTIONAL named parameter, not a Dart `required` one, so
  /// every existing `PlayerOverlayContext(...)` call site keeps compiling.) `null`
  /// (default) = "the backend sent nothing" → caption shown.
  final Object? showStock;

  /// Whether the header's subscribe badge is drawn at all
  /// (rb-flutter-subscribe-favorite-visibility-toggle, parity iOS / Android / RN), carried
  /// verbatim from `LivebuyPlayerConfig.showSubscribe` to `PlayerShellView.showSubscribe`.
  /// Default `true` — same reasoning as [showStock]: this DTO's own default keeps every
  /// existing `PlayerOverlayContext(...)` call site unaffected; the turnkey container is
  /// the one that actually flips it off by default.
  final bool showSubscribe;

  /// Whether the product-detail sheet's INLINE 收藏鈕 row is drawn at all
  /// (rb-flutter-subscribe-favorite-visibility-toggle, parity iOS / Android / RN), carried
  /// verbatim from `LivebuyPlayerConfig.showFavorite` to
  /// `ProductSheetsOverlayView.showFavorite`. Default `true`, same reasoning as
  /// [showSubscribe].
  final bool showFavorite;

  /// MERCHANT capability gate for the top-bar title marquee — the RAW
  /// `extensions.video_title_scroll` wire value (rb-flutter-marquee-title-scroll, parity
  /// iOS / Android `titleScroll`), carried verbatim from
  /// `LivebuyPlayerConfig.titleScroll` to `PlayerShellView.titleScroll`. Typed `Object?`
  /// for the same reason as [showStock]: the SDK never interprets `extensions`, so the
  /// raw value travels untouched (no cast, no local default) and is normalized ONCE, at
  /// the very bottom of the chain (`normalizeTitleScroll`, inside `PlayerHeaderBarView`).
  /// `null` (default) = "the backend sent nothing" → the title scrolls when it overflows.
  final Object? titleScroll;

  // Shell seams.
  final VoidCallback onMinimize;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleSubscribe;
  final ValueChanged<LBSideRailKind> onTapRailItem;
  final VoidCallback onTapPinnedProduct;
  final VoidCallback onComment;

  /// LIVE 底部 bar 暱稱按鈕 → 容器本地呈現 設定暱稱 modal（`nickname.present(false)`；parity）。
  final VoidCallback onNickname;

  /// Whether another live broadcast is CURRENTLY detected (rb-flutter-live-now-pill), carried
  /// verbatim from the container's `LiveNowPollController.liveNow != null` to
  /// `PlayerShellView.hasLiveNow`. Default `false` — same reasoning as [showSubscribe] /
  /// [showStock]: this DTO's own default keeps every existing `PlayerOverlayContext(...)` call
  /// site unaffected; the turnkey container resolves the real value.
  final bool hasLiveNow;

  /// Host-wired tap on `LiveNowPillView` (rb-flutter-live-now-pill), resolved by the container
  /// (reads `LiveNowPollController.liveNow` → host `LivebuyPlayerConfig.onGoLive` override or
  /// the default in-place switch). Default `null` → `PlayerShellView`'s own inert default, same
  /// reasoning as [onTogglePlayPause] / [onSwipeUp].
  final VoidCallback? onGoLive;

  /// Whether the info panel (VideoInfoPanel bottom sheet) is currently open — mirrored from
  /// `PlayerShellView` via [onInfoPanelOpenChange] so the higher-layer chat feed can be hidden
  /// while the panel is up (parity iOS rb-ios-info-panel-not-covered-by-chat). Default false.
  final bool infoPanelOpen;

  /// Reports the info panel open/closed state from `PlayerShellView` up to the container (which
  /// mirrors it into [infoPanelOpen] to hide the chat feed). null → no report.
  final ValueChanged<bool>? onInfoPanelOpenChange;

  /// Whether「乾淨模式」is currently on — mirrored from `PlayerShellView` via
  /// [onCleanModeChange] so the higher-layer合流聊天 feed (`FeedWinOverlayView`) can be hidden
  /// while it is up (rb-flutter-gesture-clean-mode-rewrite, bubble pattern copied verbatim from
  /// [infoPanelOpen] / rb-ios-info-panel-not-covered-by-chat). Default `false`.
  final bool cleanMode;

  /// Reports the「乾淨模式」open/closed state from `PlayerShellView` up to the container (which
  /// mirrors it into [cleanMode] to hide the chat feed). null → no report.
  final ValueChanged<bool>? onCleanModeChange;

  /// Whether the product LIST drawer is open. Container-owned single source (default false); the
  /// GOODS rail/bag tap opens it, the scrim/close dismisses it. Parity iOS `listPresented`.
  final bool productListPresented;

  /// Dismiss the product LIST drawer (scrim / close) — container sets open state false.
  final VoidCallback? onDismissProductList;

  /// Optional host swipe overrides (rb-player-shell swipe-override seam). The turnkey
  /// container always passes null (host-feed `swipeFeed` removed → swipe uses the shell's
  /// built-in channel-adjacency + close-on-empty); the shell calls these INSTEAD of its
  /// built-in navigation only when a host wiring `PlayerShellView` directly supplies them.
  /// Mirrors iOS `PlayerOverlayContext.onSwipeUp` / `onSwipeDown`.
  final VoidCallback? onSwipeUp;
  final VoidCallback? onSwipeDown;

  /// Swipe toward an EMPTY direction (no next / prev video) → close the player
  /// (swipe-nav-close-on-empty). Only on the built-in (no host override) fallback path.
  /// null → swipe-to-empty is a no-op. The container wires this from
  /// `config.onDismiss ?? controller.unload`. Mirrors iOS `PlayerOverlayContext.onCloseRequest`.
  final VoidCallback? onCloseRequest;

  /// Reports the NEW video id after a vertical-swipe in-place switch (swipe-video-switched-notify,
  /// parity iOS / Android / RN). The container wires this to a notify-only callback (records the
  /// shown id + raises `config.onVideoSwitched(id)`) so a host-bound video mirror (the minimized
  /// floating preview) tracks the shown video after a swipe. null → no report.
  final ValueChanged<String>? onSwipeDidSwitchVideo;

  // Feed-win seams.
  /// Host OBSERVE hook for an event-join tap (eid only). Existing public field,
  /// signature unchanged.
  final ValueChanged<int>? onJoinEvent;

  /// Keyword-carrying event-join core send (rb-flutter-event-join-reaches-core). The
  /// container wires it to `buildEventJoinSend(_controller.requestEventJoin)` — the
  /// ONLY place this layer reaches core `requestEventJoin(eid, keyword)` (parity iOS /
  /// Android drop-in; same container-direct mechanism as the claim seam). Optional /
  /// nullable (NOT required) so it is additive / non-breaking for the container (sole
  /// constructor caller) and for any custom `ReferenceUIDesign` that consumes this DTO.
  final void Function(int eid, String keyword)? onJoinEventWithKeyword;

  /// 「加入活動」三層閘（rb-flutter-event-join-gate，parity iOS / Android / RN）。container-internal
  /// seam（**非** host API）：容器注入一個能讀 `_guestNickname` / `chatEnabled` + present `_login` /
  /// `_nickname`（暱稱閘記 pending join）的 closure，`FeedWinOverlayView._handleJoin` 在 markJoined /
  /// 觀察 / 送出**之前**先問它——回 `true`（登入 / 暱稱閘攔截）→ 呈現對應 modal 後 return，MUST NOT
  /// markJoined / 送出；回 `false`（放行）→ 走 C1 既有三步。`null`（demo / golden / 自訂 design 直接用
  /// `FeedWinOverlayView`）→ 無 gating、baseline byte-identical。
  final bool Function(int eid, String keyword)? joinGate;
  /// 領獎提交（**帶使用者輸入的 email**，rb-flutter-win-claim-email-flow）。容器把它接到
  /// core `requestAwardClaim(winner, contact: LBAwardClaimInput(email: email))` —— 這是本層
  /// **唯一**真的打領獎 API 的地方（見 `feed_win_view.dart` 檔頭「一次提交只得呼叫 core 一次」）。
  /// 型別由 `ValueChanged<LBWinner>` 加寬（EMAIL-LESS 已退役）。
  final void Function(LBWinner winner, String email) onSubmitClaim;

  // Product-sheet seams.
  final ValueChanged<LBProduct> onProductTap;
  final VoidCallback onShare;

  /// Host-wired「聯絡商家」override（dropin-service-link-default-browser-flutter），原樣沿自
  /// `LivebuyPlayerConfig.onServiceLink` 傳給 `PlayerShellView.onServiceLink`。null（DEFAULT）→
  /// `PlayerShellView` fallback 到既有 `onTapRailItem(serviceLink)`；容器 MUST NOT 為此欄位計算
  /// 任何智慧預設。
  final VoidCallback? onServiceLink;

  /// 商品列表列縮圖點擊 → 影片跳轉到該商品介紹時間（`LBProduct.beginTime`）。issue 5。
  final ValueChanged<LBProduct> onSeekToProductIntro;

  /// 商品列表列分享鈕 → 系統分享，連結帶該商品介紹時間 `?t=beginTime`。issue 6。
  final ValueChanged<LBProduct> onShareProduct;

  /// 商品明細「更多商品」推薦卡播放圖示 → 換片 (rb-flutter-product-detail-recommendations §4,
  /// design.md D3). The container wires this to the SAME `_switchVideo` default
  /// `onPickHot` uses (load + track + notify), NOT a dismiss — the product-detail sheet
  /// stack MUST stay open. Optional (like [onServiceLink] / [onWatchNext]) so every
  /// existing `PlayerOverlayContext(...)` call site (this file's sole production one +
  /// `show_stock_caption_test.dart`) keeps compiling unchanged; `null` → the play icon
  /// simply forwards nothing (demo / an unwired custom design).
  final ValueChanged<String>? onSwitchRecommendationVideo;

  // Moments seams.
  final VoidCallback onSkip;
  final VoidCallback? onWatchNext;
  final ValueChanged<LBEndHotItem> onPickHot;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback? onDismiss;

  // Gap-surfaces seams.
  final VoidCallback? onLogin;
  // rb-flutter-nickname-taken-inline-error: `Future<String?>` — `null` = the host accepted +
  // persisted the name (dismisses the modal separately); non-null = a user-facing error message
  // the modal shows inline (nickname 被取走 / other checkName failure), staying open for retry.
  final Future<String?> Function(String name)? onSubmitName;

  // Composer send.
  final ValueChanged<String> onSend;

  /// Playback-progress-bar play/pause (rb-flutter-vod-playback-progress-bar). The turnkey
  /// `LivebuyPlayer` always resolves this to a non-null closure (the held
  /// `LivebuyPlayerController.togglePlayPause()`, bypassing the template — see design.md) before
  /// constructing this context; `null` (unwired demo / golden / a custom `ReferenceUIDesign`
  /// caller) → `PlayerShellView`'s own inert default. Optional (not `required`) so every
  /// pre-existing `PlayerOverlayContext(...)` call site (this file's production one + 3 existing
  /// test call sites unrelated to this feature) keeps compiling unchanged — same reasoning as
  /// [onServiceLink] / [onSwipeUp].
  final VoidCallback? onTogglePlayPause;

  /// Playback-progress-bar seek (rb-flutter-vod-playback-progress-bar). The turnkey
  /// `LivebuyPlayer` always resolves this to `_controller.seek(seconds, duration: duration)`
  /// (`liveStatus` deliberately never supplied, see design.md) before constructing this context;
  /// `null` → `PlayerShellView`'s own inert default. Optional for the same reason as
  /// [onTogglePlayPause].
  final void Function(double seconds, {double? duration})? onSeek;

  const PlayerOverlayContext({
    required this.theme,
    this.template,
    required this.composerController,
    required this.nicknameController,
    required this.loginController,
    required this.live,
    this.showStock,
    this.showSubscribe = true,
    this.showFavorite = true,
    this.titleScroll,
    this.infoPanelOpen = false,
    this.onInfoPanelOpenChange,
    this.cleanMode = false,
    this.onCleanModeChange,
    this.productListPresented = false,
    this.onDismissProductList,
    required this.onMinimize,
    required this.onToggleMute,
    required this.onToggleSubscribe,
    required this.onTapRailItem,
    required this.onTapPinnedProduct,
    required this.onComment,
    required this.onNickname,
    this.hasLiveNow = false,
    this.onGoLive,
    this.onSwipeUp,
    this.onSwipeDown,
    this.onCloseRequest,
    this.onSwipeDidSwitchVideo,
    required this.onJoinEvent,
    this.onJoinEventWithKeyword,
    this.joinGate,
    required this.onSubmitClaim,
    required this.onProductTap,
    required this.onShare,
    this.onServiceLink,
    required this.onSeekToProductIntro,
    required this.onShareProduct,
    this.onSwitchRecommendationVideo,
    required this.onSkip,
    required this.onWatchNext,
    required this.onPickHot,
    required this.onCancel,
    required this.onRetry,
    required this.onDismiss,
    required this.onLogin,
    required this.onSubmitName,
    required this.onSend,
    this.onTogglePlayPause,
    this.onSeek,
  });
}

/// Inputs for a widget surface (carousel or grid). The same context drives both — the design
/// picks the layout per builder. The Flutter widget surface is template-bound: the bound
/// `DefaultWidgetTemplate` dispatches the matching surface by `content.current.mode`, so the
/// context carries the template + resolved per-card overlay resolver + the host-wired exits.
@immutable
class WidgetSurfaceContext {
  final DefaultWidgetTemplate? template;
  final ReferenceUITheme theme;
  final WidgetGoods? Function(LBVideoItem item)? goodsFor;

  /// Whether the widget cards load real (live) cover photos vs deterministic
  /// placeholders. The turnkey `LivebuyWidget` passes `config.live` (default true at
  /// runtime); the demo / golden path leaves it false. Mirrors iOS
  /// `WidgetSurfaceContext.live`.
  final bool live;

  final void Function(LBVideoItem item)? onTapVideo;
  final VoidCallback? onSeeMore;
  final VoidCallback onLoadMore;

  const WidgetSurfaceContext({
    required this.template,
    required this.theme,
    required this.goodsFor,
    this.live = false,
    required this.onTapVideo,
    required this.onSeeMore,
    required this.onLoadMore,
  });
}

/// Inputs for the minimize floating-preview card.
@immutable
class FloatingCardContext {
  final ReferenceUITheme theme;
  final LBVideoItem video;

  /// Whether the floating preview card loads the real `video.cover` photo vs the
  /// deterministic placeholder. The collapsible presenter passes true (a genuine live
  /// session — parity with iOS `LivebuyPlayerPresenter` `FloatingCardContext(live:
  /// true)`); the demo / golden path leaves it false.
  final bool live;

  final ValueChanged<LBVideoItem> onTap;
  final VoidCallback onClose;

  const FloatingCardContext({
    required this.theme,
    required this.video,
    this.live = false,
    required this.onTap,
    required this.onClose,
  });
}

// MARK: - The design seam

/// A `ReferenceUIDesign` composes a WHOLE container surface from the resolved theme + host
/// closures it is handed (granularity A). The turnkey containers delegate to it and know
/// nothing about any concrete design (D2: abstract class, not enum switch). [MinimalDesign] is
/// the default; a host overrides via `LivebuyPlayerConfig.design` / `LivebuyWidgetConfig.design`
/// / `CollapsibleLivebuyPlayer`'s config.
abstract class ReferenceUIDesign {
  /// Const-friendly base ctor so concrete designs (e.g. [MinimalDesign]) can be `const`.
  const ReferenceUIDesign();

  /// The whole player overlay (chrome + feed/win + product sheets + moments + gap-surfaces +
  /// on-demand chat composer), composed however this design lays it out. Returns a single
  /// `Widget` placed in the container's root `Stack` above the native player view.
  Widget playerOverlay(PlayerOverlayContext context);

  /// The widget carousel surface (header row + a row of cards).
  Widget widgetCarousel(WidgetSurfaceContext context);

  /// The widget video-shop grid surface (2-column grid + lazy load-more).
  Widget widgetGrid(WidgetSurfaceContext context);

  /// The minimize floating-preview card.
  Widget floatingPlayerCard(FloatingCardContext context);
}

// MARK: - MinimalDesign — the default ReferenceUIDesign conformer
//
// `MinimalDesign` wraps the existing `minimal` surface composition VERBATIM (decision D5):
// the same surfaces, the same `Stack` order / template-null demo seeds, the same
// `WidgetOverlayView` / `FloatingWidgetView`. It is the default design for the turnkey
// containers (`resolveDesign()` returns it when the host does not override). Because the
// composition is unchanged, behavior is pixel-for-pixel identical and the existing golden
// baselines stay byte-identical — that byte-identity is the acceptance gate for this
// pure-decoupling change.
//
// This is the ONLY place the concrete minimal surface widgets are instantiated; the containers
// themselves only see the [ReferenceUIDesign] abstraction.
class MinimalDesign extends ReferenceUIDesign {
  const MinimalDesign();

  /// The whole player overlay: the existing `PlayerShellView` + `FeedWinOverlayView` +
  /// `ProductSheetsOverlayView` + moments + `GapSurfacesOverlayView` + `ChatComposerBar`,
  /// composed exactly as the container did inline — only the inputs now arrive bundled in a
  /// [PlayerOverlayContext]. Returned as one `Stack` (the container puts it over the native
  /// view, so empty / transparent areas pass touches through via each surface's hit-test).
  @override
  Widget playerOverlay(PlayerOverlayContext c) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // The shell rebuilds when the 留言 composer toggles so it can hide the LIVE bottom bar
        // while the opaque composer is up (parity iOS rb-ios-chat-composer-opaque-hide-bottom-bar).
        ListenableBuilder(
          listenable: c.composerController,
          builder: (context, _) => PlayerShellView(
            template: c.template,
            theme: c.theme,
            onMinimize: c.onMinimize,
            onToggleMute: c.onToggleMute,
            onToggleSubscribe: c.onToggleSubscribe,
            // 訂閱鈕顯示/隱藏（rb-flutter-subscribe-favorite-visibility-toggle）— raw hand-off.
            showSubscribe: c.showSubscribe,
            // 標題跑馬燈的商家能力閘（rb-flutter-marquee-title-scroll）：原樣帶 host 注入的
            // raw `extensions.video_title_scroll`，design seam **不**正規化、**不**讀 sdkConfig
            // （由 `PlayerHeaderBarView` 的 `normalizeTitleScroll` 單一入口負責）。
            titleScroll: c.titleScroll,
            onTapRailItem: c.onTapRailItem,
            onTapPinnedProduct: c.onTapPinnedProduct,
            // 頻道分享（rb-flutter-player-share-default-sheet）：LIVE / 回放底部 bar + 純 VOD 側欄 rail
            // 分享鈕改走與商品詳情分享同一條 c.onShare fallback（= config.onShare ?? Share.share
            // (channel.share_url) 系統分享），不再只派 VIDEO_SHARE_REQUEST 事件（unwired host = 死按鈕）。
            onShare: c.onShare,
            // 聯絡商家 override（dropin-service-link-default-browser-flutter）：原樣傳遞，null →
            // PlayerShellView 自己 fallback 到既有 onTapRailItem(serviceLink)。
            onServiceLink: c.onServiceLink,
            // VOD 介紹卡輪播某張卡開明細 → core simulateProductTap（與商品列同出口）。
            onTapNowIntroducingProduct: c.onProductTap,
            // Header avatar loads the real shop logo at runtime (rb-flutter-player-header-
            // real-shop-logo parity). Targeted to the shell header; product images keep
            // the container's placeholder posture (`c.live`). At demo/golden the model's
            // shopLogo is empty → liveProductImage falls back to the monogram (no network).
            live: true,
            onComment: c.onComment,
            // 暱稱鈕 → 容器本地呈現 設定暱稱 modal（parity iOS / Android / RN）。
            onNickname: c.onNickname,
            // 「現正直播」提示鈕（rb-flutter-live-now-pill）：原樣轉發容器已解析好的
            // hasLiveNow / onGoLive。
            hasLiveNow: c.hasLiveNow,
            onGoLive: c.onGoLive,
            // Swipe overrides — turnkey container always passes null (host-feed swipeFeed
            // removed; swipe uses the shell's built-in channel-adjacency + close-on-empty).
            onSwipeUp: c.onSwipeUp,
            onSwipeDown: c.onSwipeDown,
            // Swipe toward an empty direction (no next/prev) → close (swipe-nav-close-on-empty).
            onCloseRequest: c.onCloseRequest,
            // Report the switched video id after a swipe in-place switch (swipe-video-switched-notify).
            onDidSwitchVideo: c.onSwipeDidSwitchVideo,
            // Report info-panel open/close up so the container hides the chat feed while it's up.
            onInfoPanelOpenChange: c.onInfoPanelOpenChange,
            // 乾淨模式（rb-flutter-gesture-clean-mode-rewrite）：把翻轉冒泡給容器（design.md D5）。
            onCleanModeChange: c.onCleanModeChange,
            // Hide the LIVE bottom bar while the opaque 留言 composer is up (avoid overlap).
            composerPresented: c.composerController.isPresented,
            // Playback-progress-bar control plane (rb-flutter-vod-playback-progress-bar) —
            // straight pass-through, both nullable (see PlayerOverlayContext doc comments).
            onTogglePlayPause: c.onTogglePlayPause,
            onSeek: c.onSeek,
          ),
        ),
        FeedWinOverlayView(
          template: c.template,
          theme: c.theme,
          // Runtime: scrollable chat (binds deeper feedHistory) so the user can scroll
          // up to view history (rb-flutter-chat-feed-scrollable parity #5b/#6).
          chatScrollable: true,
          // Hide the chat feed while the info panel is up (parity rb-ios-info-panel-not-covered-
          // by-chat); FeedWinOverlayView also drops it entirely in VOD (LIVE-only).
          infoPanelOpen: c.infoPanelOpen,
          // Keep the chat in the design's LEFT column (LBLiveChatOverlay right:152) so it clears
          // the side rail / floating bag / win entry on the right (parity iOS liveChatTrailingClearance).
          chatTrailingInset: 152,
          // 乾淨模式（rb-flutter-gesture-clean-mode-rewrite）：轉發自容器（design.md D5）。
          cleanMode: c.cleanMode,
          onJoinEvent: c.onJoinEvent,
          // rb-flutter-event-join-reaches-core — the keyword-carrying default that
          // actually reaches core `requestEventJoin` (the container's only join send).
          onJoinEventWithKeyword: c.onJoinEventWithKeyword,
          // rb-flutter-event-join-gate — the container-injected three-tier gate (登入 → 暱稱 →
          // 放行); null (demo / golden) → no gating, baseline byte-identical.
          joinGate: c.joinGate,
          onSubmitClaim: c.onSubmitClaim,
        ),
        ProductSheetsOverlayView(
          template: c.template,
          theme: c.theme,
          // Product LIST drawer is container-driven (default closed; GOODS rail/bag tap opens it),
          // NOT self-opening — parity iOS onOpenProductList.
          presented: c.productListPresented,
          onDismissList: c.onDismissProductList,
          // Stock-caption merchant gate (`extensions.show_stock`, host-injected via
          // `LivebuyPlayerConfig.showStock`) — forwarded RAW; the sheet owns the single
          // `normalizeShowStock` fallback. It reaches ONLY the product detail /
          // add-to-cart sheets: the restock sheet's「尚無庫存」is a sold-out status line
          // and stays inert (rb-flutter-show-stock-caption-toggle).
          showStock: c.showStock,
          // 收藏鈕顯示/隱藏（rb-flutter-subscribe-favorite-visibility-toggle）— raw hand-off.
          showFavorite: c.showFavorite,
          onProductTap: c.onProductTap,
          onShare: c.onShare,
          onSeekToProductIntro: c.onSeekToProductIntro,
          onShareProduct: c.onShareProduct,
          // 加購「需登入」gate's 前往登入 → host login flow (`config.onLogin`), the SAME host hook the
          // comment login-gate uses (cart-needs-login-gate). reference-ui NEVER logs in itself.
          onRequestLogin: c.onLogin,
          // 商品明細「更多商品」推薦卡播放圖示 → 換片 (rb-flutter-product-detail-recommendations §4).
          onSwitchRecommendationVideo: c.onSwitchRecommendationVideo,
        ),
        MomentsOverlayView(
          template: c.template,
          theme: c.theme,
          // Turnkey container composes over a real video surface → the end-screen
          // recommended / watch-next cards load real `cover` images (parity the shell's
          // live: true above, :337). rb-flutter-endscreen-recommended-video-cover.
          live: true,
          onSkip: c.onSkip,
          onWatchNext: c.onWatchNext,
          onPickHot: c.onPickHot,
          onCancel: c.onCancel,
          onRetry: c.onRetry,
          onDismiss: c.onDismiss,
        ),
        GapSurfacesOverlayView(
          template: c.template,
          theme: c.theme,
          // 設定暱稱 modal 由容器本地呈現（parity）：controller 驅動可見性 + runtime editable；
          // submit / scrim 經 gap 出口（onSubmitName turnkey → setGuestNicknameVerified；
          // rb-flutter-nickname-taken-inline-error 起改為 Future<String?> 三態契約）。
          nicknameController: c.nicknameController,
          // 「請先登入」modal 由容器本地呈現（rb-flutter-live-comment-login-gate）：controller 驅動可見性；
          // 前往登入經 onLogin（host config.onLogin）。
          loginController: c.loginController,
          onLogin: c.onLogin,
          onDismiss: c.onDismiss,
          onSubmitName: c.onSubmitName,
        ),
        ChatComposerBar(
          controller: c.composerController,
          theme: c.theme,
          onSend: c.onSend,
        ),
      ],
    );
  }

  /// The widget carousel — the existing `WidgetOverlayView` (template-bound; it dispatches by
  /// `content.current.mode`, so carousel content is supplied by the bound template / seeds,
  /// exactly as the `LivebuyWidget` container did before).
  @override
  Widget widgetCarousel(WidgetSurfaceContext c) => _widgetOverlay(c);

  /// The widget grid — the SAME existing `WidgetOverlayView`; the bound template's content mode
  /// selects the grid surface (parity with the pre-seam container, which always rendered one
  /// `WidgetOverlayView` and let the template content pick the surface).
  @override
  Widget widgetGrid(WidgetSurfaceContext c) => _widgetOverlay(c);

  Widget _widgetOverlay(WidgetSurfaceContext c) => WidgetOverlayView(
        template: c.template,
        theme: c.theme,
        goodsFor: c.goodsFor,
        live: c.live,
        onTapVideo: c.onTapVideo,
        onSeeMore: c.onSeeMore,
        onLoadMore: c.onLoadMore,
      );

  /// The minimize floating-preview card — the existing family-5 `FloatingWidgetView`.
  @override
  Widget floatingPlayerCard(FloatingCardContext c) => FloatingWidgetView(
        theme: c.theme,
        liveVideo: c.video,
        live: c.live,
        onTap: c.onTap,
        onClose: c.onClose,
      );
}
