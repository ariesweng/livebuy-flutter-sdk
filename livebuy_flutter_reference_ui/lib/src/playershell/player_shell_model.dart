import 'package:livebuy_flutter/livebuy_flutter.dart' show LBProduct;
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show
        DefaultPlayerTemplate,
        LBInfoPanelTab,
        LBInfoTabFields,
        LBPStartPhase,
        LBSideRailItem,
        LBSideRailKind;

// PlayerShellModel — family-1 player-shell read-only snapshot bridge (Flutter).
//
// Spec: `reference-ui-rendering/spec.md` (family-1 player-shell, 4 surfaces).
// Flutter sibling of iOS `PlayerShellModel.swift` (rb-ios-player-shell D-1 / D-4)
// and Android `PlayerShellModel.kt` (rb-android-player-shell).
//
// It bridges the headless template view-models exposed by `DefaultPlayerTemplate`
// (obtained at runtime by the host; tests take `LivebuyUI.attachedTemplateForTesting`)
// into a read-only snapshot the four family-1 Flutter surface widgets read. It is
// a pure read-only MIRROR:
//
//   - It owns NO second copy of authoritative state. Every getter reads the
//     template's own public getter each call (`header.title` / `operationRail.items`
//     / `infoTab.fields` / `noticeTab.current` / `productOverlay.activeProduct`),
//     so there is nothing to drift from the template (D-1).
//   - It adds NO pixels and adds NO accessor / view-model to `livebuy_flutter_ui`
//     (that would be a template-layer concern, out of scope — D-4).
//   - Interactions stay in core's existing `simulate*` exits; this layer only
//     reads. The single thin forwarder ([selectInfoTab]) targets a template-owned
//     NAVIGATION intent (`selectTab` only flips presentation state, no API). Every
//     other interaction (mute / like / share / 訂閱 / product-tap) is host-wired
//     to core `simulate*`, NOT here.
//
// Compose / SwiftUI observe via ChangeNotifier / ObservableObject; on Flutter the
// container [PlayerShellView] binds the relevant `ChangeNotifier`s with
// `ListenableBuilder` and RE-READS these getters on each notify — so this holder
// keeps NO Flutter state of its own (no `extends ChangeNotifier`), it just
// centralizes the read mapping + deterministic demo seeds. Mirrors the Android
// `PlayerShellModel` intent.
//
// No Flutter-framework dependency here — pure reads + plain-literal demo seeds, so
// it stays unit-testable (see `docs/unit-test-discipline.md`).

/// Read-only snapshot bridge for the family-1 player-shell. Wraps a live
/// [DefaultPlayerTemplate]; every accessor reads the template's public getter each
/// call (no stored mirror). For demos / previews / golden tests, construct with
/// `template: null` and the accessors return the deterministic [PlayerShellSeeds]
/// defaults instead.
class PlayerShellModel {
  /// The bound template, or `null` for demo / golden instances.
  final DefaultPlayerTemplate? template;

  /// Bridge a live template (host-supplied) — or `null` for the deterministic
  /// demo seeds (previews / golden tests).
  const PlayerShellModel({this.template});

  // -- Surface 1 (+ shared mute): PlayerHeaderBar ← header chrome -------------

  /// Top-bar host-pill title (`DefaultPlayerHeaderState.title`).
  String get title => template?.header.title ?? PlayerShellSeeds.title;

  /// Host / shop name (`DefaultPlayerHeaderState.hostName`).
  String get hostName => template?.header.hostName ?? PlayerShellSeeds.hostName;

  /// Host pill / top-bar logo URL (`DefaultPlayerHeaderState.shopLogo`).
  String get shopLogo => template?.header.shopLogo ?? PlayerShellSeeds.shopLogo;

  /// Live viewer count (`DefaultPlayerHeaderState.viewerCount`).
  int get viewerCount =>
      template?.header.viewerCount ?? PlayerShellSeeds.viewerCount;

  /// Subscribe-badge state (`DefaultPlayerHeaderState.isSubscribed`). Single
  /// truth — the same value the info-tab reads (`infoTab.isSubscribed`).
  bool get isSubscribed =>
      template?.header.isSubscribed ?? PlayerShellSeeds.isSubscribed;

  /// Share-action context URL (`DefaultPlayerHeaderState.shareUrl`).
  String get shareUrl => template?.header.shareUrl ?? PlayerShellSeeds.shareUrl;

  /// Mute gesture state (single truth — `header.muted` == `operationRail.muted`,
  /// both fed from the template's same `handleMuted`). Auto-muted (true) at start.
  bool get muted => template?.header.muted ?? PlayerShellSeeds.muted;

  /// LIVE/VOD flag (`DefaultPlayerHeaderState.isLive` — `channel.liveStatus == 1`,
  /// host-fed). Gates the LIVE bottom bar (LIVE) vs the side rail (VOD). For demo
  /// instances returns [PlayerShellSeeds.isLive].
  bool get isLive => template?.header.isLive ?? PlayerShellSeeds.isLive;

  /// Replay variant flag (`DefaultPlaybackProgressState.isReplay`, VOD-2) — a LIVE
  /// stream scrubbed behind the live edge. Drives the LIVE bottom bar's
  /// "聊天室已關閉" variant. For demo instances returns [PlayerShellSeeds.isReplay].
  bool get isReplay =>
      template?.playbackProgress.isReplay ?? PlayerShellSeeds.isReplay;

  /// VOD-2 playback position in seconds (`DefaultPlaybackProgressState.position`,
  /// rb-flutter-vod-playback-progress-bar). Read by `PlaybackProgressBarView`'s idle-state
  /// fill ratio (via [playbackDuration]) and its non-dragging `HH:MM:SS` numerator. For demo
  /// instances returns [PlayerShellSeeds.playbackPosition].
  double get playbackPosition =>
      template?.playbackProgress.position ?? PlayerShellSeeds.playbackPosition;

  /// VOD-2 total duration in seconds (`DefaultPlaybackProgressState.duration`,
  /// rb-flutter-vod-playback-progress-bar). For demo instances returns
  /// [PlayerShellSeeds.playbackDuration].
  double get playbackDuration =>
      template?.playbackProgress.duration ?? PlayerShellSeeds.playbackDuration;

  /// VOD-2 play/pause state (`DefaultPlaybackProgressState.isPlaying`,
  /// rb-flutter-vod-playback-progress-bar) — drives the transport bar's play/pause glyph. For
  /// demo instances returns [PlayerShellSeeds.isPlaybackPlaying].
  bool get isPlaybackPlaying =>
      template?.playbackProgress.isPlaying ?? PlayerShellSeeds.isPlaybackPlaying;

  /// 已結束直播回放旗標（`DefaultPlayerHeaderState.isFinishedLiveReplay`,
  /// rb-flutter-vod-playback-progress-bar）：`type == 3 || (type == 2 && liveStatus == 3)`，與
  /// [isLive] 互斥。This is the flag `PlayerShellView.showsPlaybackProgressBar`'s `isReplay`
  /// argument MUST be fed — NOT [isReplay] above (the narrower core DVR concept, a stream
  /// still actively live and scrubbed behind the live edge; `vodScrubAllowed` rejects any seek
  /// while `liveStatus == 1` regardless, so a bar gated on that flag would visually drag but
  /// every seek would silently no-op). For demo instances returns
  /// [PlayerShellSeeds.isFinishedLiveReplay].
  bool get isFinishedLiveReplay =>
      template?.header.isFinishedLiveReplay ?? PlayerShellSeeds.isFinishedLiveReplay;

  /// 會員等級限定軟閘門（restriction-mask ②），鏡像自 `DefaultPlayerTemplate.isRestricted`
  /// （統一 `VIDEO_OPEN` 事件 `is_restriction == 1`）。`true` → `PlayerShellView` 在播放畫面疊升級
  /// 遮罩。core 不擋播放（軟性顯示閘門）。For demo instances returns
  /// [PlayerShellSeeds.isRestricted]（false → 不出像素，golden byte-identical）。
  bool get isRestricted =>
      template?.isRestricted ?? PlayerShellSeeds.isRestricted;

  /// Subtitle (CC) toggle state (`DefaultSubtitleState.enabled`, rb-flutter-subtitle-vtt-caption
  /// -display) — gates the VOD caption overlay alongside a non-empty resolved caption text. Does
  /// NOT itself carry the caption TEXT (core exposes no active-caption text source) — see
  /// `PlayerShellView`'s `_subtitleCues` / `VTTSubtitleParser.activeCue` for that. For demo
  /// instances returns [PlayerShellSeeds.subtitleEnabled] (`false`).
  bool get subtitleEnabled =>
      template?.subtitle.enabled ?? PlayerShellSeeds.subtitleEnabled;

  // -- Upcoming (直播預告 awaitingLive) chrome state (DefaultUpcomingState) ----
  //
  // Read-only mirror of the template's upcoming view-model (`upcoming`, active /
  // introPlaying / scheduledStartAt / cover). `PlayerShellView` reads `isUpcoming`
  // to compose the upcoming LIVE chrome (cover + date/time background + slim bottom
  // bar) instead of the LIVE / VOD chrome (priority upcoming > live > vod). Flutter
  // parity of iOS / Android `PlayerShellModel.{isUpcoming, upcomingStartAt,
  // upcomingCover, introPlaying}`.

  /// Whether the player is in the awaiting-live sub-state
  /// (`DefaultUpcomingState.active`). `true` → the shell composes the upcoming LIVE
  /// chrome. For demo instances returns [PlayerShellSeeds.isUpcoming].
  bool get isUpcoming =>
      template?.upcoming.active ?? PlayerShellSeeds.isUpcoming;

  /// Scheduled start (`DefaultUpcomingState.scheduledStartAt` / backend
  /// `publish_at`), parsed by the upcoming surface for the date + big-time display.
  /// For demo instances returns [PlayerShellSeeds.upcomingStartAt].
  String get upcomingStartAt =>
      template?.upcoming.scheduledStartAt ?? PlayerShellSeeds.upcomingStartAt;

  /// Video cover URL (`DefaultUpcomingState.cover` / backend `channel.cover`) — the
  /// upcoming surface's full-bleed background (runtime only; the golden path paints a
  /// deterministic placeholder). For demo instances returns
  /// [PlayerShellSeeds.upcomingCover].
  String get upcomingCover =>
      template?.upcoming.cover ?? PlayerShellSeeds.upcomingCover;

  /// Whether the intro (開場影片) MP4 preroll is playing
  /// (`DefaultUpcomingState.introPlaying`). The intro wears the LIVE chrome (its
  /// background is the actual intro video, not the countdown); exposed for parity.
  /// `false` for demo instances.
  bool get introPlaying => template?.upcoming.introPlaying ?? false;

  /// Start-lifecycle phase (`DefaultPlayerTemplate.startScreen.phase`), mirrored here so
  /// `PlayerShellView` can gate the VOD side rail off during the start sequence
  /// (`startPhase != done`) while keeping the header — parity to iOS `PlayerShellModel
  /// .startPhase`. Demo default `LBPStartPhase.loading`.
  LBPStartPhase get startPhase =>
      template?.startScreen.phase ?? LBPStartPhase.loading;

  // -- Surface 2: OperationRail ← side-rail ----------------------------------

  /// Ordered side-rail action items (`DefaultOperationRail.items`).
  List<LBSideRailItem> get railItems =>
      template?.operationRail.items ?? PlayerShellSeeds.railItems;

  /// Shopping-bag badge count (`DefaultOperationRail.bagCount`); >0 → draw badge.
  int get bagCount =>
      template?.operationRail.bagCount ?? PlayerShellSeeds.bagCount;

  /// Monotonic heart-burst tick (`DefaultOperationRail.heartBurstTick`); observe
  /// its INCREASE to play the heart-burst — this layer never calls like.
  int get heartBurstTick =>
      template?.operationRail.heartBurstTick ?? PlayerShellSeeds.heartBurstTick;

  // -- Surface 3: VideoInfoPanel ← info-tab + notice-tab ----------------------

  /// Info-tab field snapshot (`DefaultInfoTab.fields` — `LBInfoTabFields`). Does
  /// NOT carry `isSubscribed` (read [isSubscribed], single truth via header).
  LBInfoTabFields get infoFields =>
      template?.infoTab.fields ?? PlayerShellSeeds.infoFields;

  /// Currently selected info-panel tab (`DefaultInfoTab.activeTab`).
  LBInfoPanelTab get activeTab =>
      template?.infoTab.activeTab ?? PlayerShellSeeds.activeTab;

  /// Whether the 公告 (notice) tab is selectable (`DefaultNoticeTab.current.canOpen`
  /// == `DefaultInfoTab.noticeSelectable` — same source). `false` → notice tab
  /// disabled + empty-state placeholder.
  bool get noticeCanOpen =>
      template?.noticeTab.current.canOpen ?? PlayerShellSeeds.noticeCanOpen;

  /// System-notice text (`DefaultNoticeTab.current.systemNotice`, textDim).
  String get systemNotice =>
      template?.noticeTab.current.systemNotice ?? PlayerShellSeeds.systemNotice;

  /// Shop / video notice text (`DefaultNoticeTab.current.notice`, accent). Also
  /// feeds the LIVE-overlay announce marquee (surface 4) per the iOS/Android bridge.
  String get notice =>
      template?.noticeTab.current.notice ?? PlayerShellSeeds.notice;

  // -- Surface 4: LiveOverlayChrome ← moment + chrome -------------------------

  /// Pinned narrating-product source — the single active product
  /// (`DefaultProductOverlayState.activeProduct`). `null` → no pinned card.
  /// demo seed ONLY for an unbound (demo / golden) instance; a BOUND template with no
  /// `narrate_status == 2` product → `null` (the `??` must NOT leak the demo product into
  /// a real live session, rb-flutter-player-demo-seed-leak). Parity iOS / Android / RN.
  LBProduct? get pinnedProduct => template == null
      ? PlayerShellSeeds.activeProduct
      : template!.productOverlay.activeProduct;

  /// VOD「正在介紹中的商品」清單（rb-flutter-now-introducing parity，問題 9/10）：鏡射
  /// `DefaultPlayerTemplate.vodActiveProducts`（[beginTime,endTime) 涵蓋 playhead、beginTime 升冪）。
  /// VOD-main 的介紹中卡輪播讀此清單（真實圖 + 滿寬 + 多商品輪播）。demo（無 template）→ 以
  /// [PlayerShellSeeds.activeProduct] 退回單卡（既有 VOD-card golden 仍 → 一張卡）。
  List<LBProduct> get vodActiveProducts {
    final t = template;
    if (t != null) return t.vodActiveProducts;
    return [PlayerShellSeeds.activeProduct]; // demo → single seed card
  }

  /// LIVE「正在介紹中」商品清單（rb-flutter-live-now-introducing-carousel，問題 7）：鏡射
  /// `DefaultPlayerTemplate.liveActiveProducts`（所有 `narrate_status == 2`，資料層順序）。後端 LIVE
  /// **可同時多件**。demo（無 bound template）→ `[]`（單一 [pinnedProduct] seed 仍經 [livePinnedProducts]
  /// 退回單卡）。Mirrors iOS / Android / RN `PlayerShellModel.liveActiveProducts`.
  List<LBProduct> get liveActiveProducts =>
      template == null ? const [] : template!.liveActiveProducts;

  /// LIVE 釘選卡輪播來源：非空 [liveActiveProducts]（多商品輪播 + 分頁點）；ELSE 單一 [pinnedProduct]
  /// （`activeProduct` ?? demo seed）一元清單。皆空 → 無卡。純 computed。Mirrors iOS / RN
  /// `PlayerShellModel.livePinnedProducts`.
  List<LBProduct> get livePinnedProducts {
    final active = liveActiveProducts;
    if (active.isNotEmpty) return active;
    final single = pinnedProduct;
    return single == null ? const [] : [single];
  }

  /// Announce-marquee copy for the LIVE overlay (`LBLiveAnnounce`). REACHABLE
  /// source is the notice-tab `notice` text — mirrors the iOS/Android bridge's
  /// `announceText = noticeTab.notice`. Empty → the banner is omitted.
  String get announceText => notice;

  // -- Read-only host intent (template-owned navigation, NOT a core simulate*) --

  /// Forward an info-panel tab switch to the bound template (`DefaultInfoTab
  /// .selectTab` via `DefaultPlayerTemplate.handleSelectInfoTab`). `info` is always
  /// honoured; `notice` is honoured by the template only when `noticeTab.canOpen`.
  /// No-op for demo instances (no bound template). `selectTab` only flips
  /// presentation state — it does NOT call any API (so this stays a navigation
  /// intent, not a core `simulate*`).
  void selectInfoTab(LBInfoPanelTab tab) =>
      template?.handleSelectInfoTab(tab);

  // -- Adjacent-video navigation (swipe-navigate) ----------------------------
  //
  // Republishes the template's read-only navigation ids and exposes thin
  // forwarders so `PlayerShellView`'s vertical-drag gesture can drive prev/next.
  // Parity of iOS `PlayerShellModel.{prevVideoId, nextVideoId, navigateToPrev,
  // navigateToNext}` / Android / RN. Read-only mirror: the getters read
  // `template.navigation` each call (no stored second copy); `null` template
  // (demo / golden) → null ids + no-op forwarders.

  /// Previous adjacent video id (`navigation.prevVideoId`), or `null` when there
  /// is no previous video / no bound template (demo / golden).
  String? get prevVideoId => template?.navigation.prevVideoId;

  /// Next adjacent video id (`navigation.nextVideoId`), or `null` when there is no
  /// next video / no bound template (demo / golden).
  String? get nextVideoId => template?.navigation.nextVideoId;

  /// Whether there is a next / previous adjacent video to switch to. Derived from
  /// [nextVideoId] / [prevVideoId] (swipe-nav-close-on-empty): a swipe toward a
  /// direction with NO video closes the player instead of no-op'ing. NO new state
  /// source — single source of truth stays core channel → template navigation. Parity
  /// iOS / Android / RN `PlayerShellModel.hasNextVideo` / `hasPrevVideo`.
  bool get hasNextVideo => nextVideoId != null;

  bool get hasPrevVideo => prevVideoId != null;

  /// Switch to the previous adjacent video — forwards to the bound template's
  /// `navigateToPrev()` (→ core `load(videoId)`). No-op when there is no previous
  /// video (`prevVideoId == null`) or no bound template (demo / golden).
  void navigateToPrev() => template?.navigateToPrev();

  /// Switch to the next adjacent video — forwards to the bound template's
  /// `navigateToNext()` (→ core `load(videoId)`). No-op when there is no next
  /// video (`nextVideoId == null`) or no bound template (demo / golden).
  void navigateToNext() => template?.navigateToNext();
}

// GAP NOTES (reachability of family-1 surfaces — parity with iOS / Android)
//
// Per D-4 this layer ONLY reads what `DefaultPlayerTemplate` exposes publicly. It
// MUST NOT add pixels or add accessors to `livebuy_flutter_ui`. These family-1
// surface inputs are NOT reachable from the template's public read surface today;
// the surfaces treat them as host-supplied static copy:
//
//   • LiveOverlayChrome — host caption (`LBLiveHostCaption`): there is NO public
//     host-caption / subtitle-text view-model on `DefaultPlayerTemplate`. The model
//     exposes `announceText` (← notice) + `pinnedProduct` (← activeProduct); the
//     host caption + gesture-hint copy stay STATIC sub-view inputs (not publishes).
//   • PlayerHeaderBar — PiP affordance: no public PiP-state mirror; the mute icon
//     binds `muted`, the PiP control (if drawn) is a static affordance whose action
//     goes through the host's wiring.

/// Deterministic demo seeds for the family-1 surfaces' previews + the per-surface
/// golden / widget tests. Plain-literal so a snapshot does NOT depend on a live
/// player. Mirrors the iOS demo seeds (`PlayerHeaderBarView` / `OperationRailView`
/// / `VideoInfoPanelView` / pinned card) and the Android `PlayerShellSeeds`.
class PlayerShellSeeds {
  PlayerShellSeeds._();

  // -- Surface 1 (+ shared mute): header chrome ------------------------------

  /// Demo header title (live-looking top bar). Mirrors Android `header.title`.
  static const String title = '夏日彩妝特賣';

  /// Demo host / shop name.
  static const String hostName = 'BeautyTown 官方';

  /// Demo shop logo URL — empty so the surface draws a deterministic placeholder
  /// (NO network image).
  static const String shopLogo = '';

  /// Demo running viewer count.
  static const int viewerCount = 12345;

  /// Not subscribed at the demo seed (subscribe badge off).
  static const bool isSubscribed = false;

  /// Demo share-context URL.
  static const String shareUrl = 'https://livebuy.tv/s/demo';

  /// Auto-muted on start (CLAUDE.md Player States) — both header + rail mirror it.
  static const bool muted = true;

  /// Demo LIVE/VOD flag — `false` so demo / existing player-shell goldens keep
  /// showing the side rail (unchanged). The LIVE bottom bar is exercised by its
  /// OWN golden / widget test constructing `LiveBottomBarView` directly.
  static const bool isLive = false;

  /// Demo replay flag — `false` (normal LIVE bar, not the "聊天室已關閉" variant).
  static const bool isReplay = false;

  /// Demo playback position — `0` (rb-flutter-vod-playback-progress-bar demo/golden seed).
  static const double playbackPosition = 0;

  /// Demo playback duration — `0` (matches `PlayerShellSeeds.startPhase`'s implicit `.loading`
  /// default, which already gates `showsPlaybackProgressBar` off for a `template: null`
  /// instance — see `isMain`'s `startPhase != .loading` clause).
  static const double playbackDuration = 0;

  /// Demo playback play/pause state — `false`.
  static const bool isPlaybackPlaying = false;

  /// Demo finished-live-replay flag — `false` (rb-flutter-vod-playback-progress-bar; mutually
  /// exclusive with [isLive], both default `false` for the demo seed).
  static const bool isFinishedLiveReplay = false;

  /// Demo restriction flag — `false` (no upgrade mask; existing player-shell goldens
  /// byte-identical). The restriction-mask golden constructs the shell with a stub
  /// template whose `isRestricted == true` directly (restriction-mask ②).
  static const bool isRestricted = false;

  /// Demo subtitle-enabled (CC) flag — `false` (no caption line; existing player-shell goldens
  /// byte-identical, rb-flutter-subtitle-vtt-caption-display).
  static const bool subtitleEnabled = false;

  // -- Upcoming (直播預告) demo seeds (player-shell-upcoming golden) -----------

  /// Demo upcoming flag — `false` (the default chrome is LIVE / VOD; existing
  /// player-shell goldens are unchanged). The upcoming golden constructs the shell
  /// with `isUpcoming = true` directly (parity with Android `PlayerShellSeeds`).
  static const bool isUpcoming = false;

  /// Demo scheduled start (`publish_at`, UTC+8) → the upcoming surface shows
  /// 「6月20日」/「20:00」. Deterministic for the golden.
  static const String upcomingStartAt = '2026-06-20 20:00:00';

  /// Demo upcoming cover URL — empty for the golden (the surface paints the
  /// deterministic placeholder / solid background, no remote load).
  static const String upcomingCover = '';

  // -- Surface 2: side-rail ---------------------------------------------------

  /// The side-rail items as they appear pre-channel (matches `DefaultOperationRail`'s
  /// default order: goods / chat / like / share / subtitle / serviceLink /
  /// guestNameEdit / more; conditional kinds disabled). Parity with iOS
  /// `defaultRailItems` / Android `defaultRailItems`.
  // Demo / golden seed only (runtime rail = template.operationRail). Aligned to the design's VOD
  // side rail (CC / share / contact): subtitle/share/serviceLink enabled; like/more/chat/
  // guestNameEdit not in the VOD rail (OperationRailView renders only its presentationOrder).
  // goods enabled feeds bagCount / the separate floating bag (the rail no longer renders it).
  static const List<LBSideRailItem> railItems = [
    LBSideRailItem(kind: LBSideRailKind.goods, enabled: true),
    LBSideRailItem(kind: LBSideRailKind.chat, enabled: false),
    LBSideRailItem(kind: LBSideRailKind.like, enabled: false),
    LBSideRailItem(kind: LBSideRailKind.share, enabled: true),
    LBSideRailItem(kind: LBSideRailKind.subtitle, enabled: true),
    LBSideRailItem(kind: LBSideRailKind.serviceLink, enabled: true),
    LBSideRailItem(kind: LBSideRailKind.guestNameEdit, enabled: false),
    LBSideRailItem(kind: LBSideRailKind.more, enabled: false),
  ];

  /// Demo bag badge of 3 (so the badge renders in the golden).
  static const int bagCount = 3;

  /// Demo heart-burst tick (static first-frame in the golden).
  static const int heartBurstTick = 0;

  // -- Surface 3: info-tab + notice-tab --------------------------------------

  /// Demo info-tab fields (a 點播 show with title / publishAt / shop / intro).
  /// `LBInfoTabFields` carries NO `isSubscribed` (single truth via header —
  /// the seed value [isSubscribed] above). Mirrors Android `infoTab`.
  static const LBInfoTabFields infoFields = LBInfoTabFields(
    title: '夏日通勤彩妝 LIVE 精選',
    publishAt: '點播影片 · Feb 04, 2026',
    shopName: 'BeautyToYou',
    shopIntro:
        '這場直播主推夏日通勤彩妝。整理出 8 款熱銷商品,觀眾可一邊看示範一邊下單,精選色號限時 5 折。',
    shopLogo: '',
  );

  /// Demo active info-panel tab (info first).
  static const LBInfoPanelTab activeTab = LBInfoPanelTab.info;

  /// Demo notice tab is selectable (both notices present). The notice-tab golden
  /// exercises the `canOpen == true` two-段 path; the disabled path is covered by
  /// the widget test with an empty seed override.
  static const bool noticeCanOpen = true;

  /// Demo system-notice copy (textDim段). Mirrors iOS / Android `systemNotice`.
  static const String systemNotice =
      '系統公告:本場次將於 21:00 開始,敬請準時收看。';

  /// Demo shop-notice copy (accent段) — also the announce-marquee source.
  /// Mirrors iOS / Android `notice`.
  static const String notice =
      '本場直播限定:單筆滿 NT\$999 免運,結帳輸入折扣碼 LIVE5 享 5 折。';

  // -- Surface 4: pinned narrating product ------------------------------------

  /// Demo pinned narrating product (`narrateStatus == 2` → 介紹中 tag, `isHot == 1`
  /// → 熱銷 tag). Flutter `LBProduct.id` is a `String` (cross-platform parity) —
  /// note this differs from Android's `Int` id. Mirrors the iOS / Android pinned
  /// card demo product. `pic` empty → surface draws a deterministic placeholder.
  static const LBProduct activeProduct = LBProduct(
    id: '90001',
    goodsNo: 'DEMO-90001',
    goodsGpn: '90001',
    name: '保濕亮顏精華液 30ml',
    price: 690.0,
    priceShow: 'NT\$ 690',
    originalPrice: 1280.0,
    originalPriceShow: 'NT\$ 1,280',
    stock: 42,
    pic: '',
    photos: [],
    brief: '限時直播價,熱銷補貨到。',
    soldOut: 0,
    isHot: 1,
    isOutSoon: 0,
    narrateStatus: 2, // narrating → pinned card shows the 介紹中 tag
    isAwait: 0,
    isAwaitNotice: 0,
    diversionUrl: '',
    specifications: [],
    specOptions: [],
  );
}
