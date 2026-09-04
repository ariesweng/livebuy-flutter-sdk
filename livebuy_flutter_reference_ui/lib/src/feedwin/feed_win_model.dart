import 'package:livebuy_flutter/livebuy_flutter.dart'
    show LBActiveEvent, LBAward, LBWinner;
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show
        DefaultPlayerTemplate,
        LBClaimClassification,
        LBClaimResultState,
        LBFeedItem,
        PinnedMessage;

// FeedWinModel — family-2 feed + win read-only snapshot bridge (Flutter).
//
// Spec: `reference-ui-rendering/spec.md` (family-2 feed-win, 3 surfaces).
// Flutter sibling of iOS `FeedWinModel.swift` (rb-ios-feed-win D-1..D-4) and
// Android `FeedWinModel.kt` (rb-android-feed-win).
//
// It bridges the headless template view-models exposed by `DefaultPlayerTemplate`
// (obtained at runtime by the host; tests take `LivebuyUI.attachedTemplateForTesting`)
// into a read-only snapshot the three family-2 Flutter surface widgets read. It is
// a pure read-only MIRROR — IDENTICAL pattern to family-1 `PlayerShellModel`:
//
//   - It owns NO second copy of authoritative state. Every getter reads the
//     template's own public getter each call (`feed.items` /
//     `winClaim.unclaimedCount` / `winClaim.unclaimedWinners` /
//     `winClaim.resultState`), so there is nothing to drift from the template (D-1).
//   - It adds NO pixels and adds NO accessor / view-model to `livebuy_flutter_ui`
//     (that would be a template-layer concern, out of scope here — D-4).
//   - The data layer already merged / ordered / tail-retained (N=7) the feed; this
//     layer MUST NOT slice / merge / re-sort it.
//
// Flutter observes via ChangeNotifier; the container [FeedWinOverlayView] binds the
// relevant `ChangeNotifier`s (`feed` (`DefaultActivityFeed`) + `winClaim`
// (`DefaultWinClaim`)) with `ListenableBuilder` and RE-READS these getters on each
// notify — so this holder keeps NO Flutter state of its own (no `extends
// ChangeNotifier`); it just centralizes the read mapping + deterministic demo seeds.
// Mirrors the iOS / Android `FeedWinModel` intent.
//
// No Flutter-framework dependency here — pure reads + plain-literal demo seeds, so
// it stays unit-testable (see `docs/unit-test-discipline.md`).

/// Read-only snapshot bridge for the family-2 feed-win surfaces. Wraps a live
/// [DefaultPlayerTemplate]; every accessor reads the template's public getter each
/// call (no stored mirror). For demos / previews / golden tests, construct with
/// `template: null` and the accessors return the deterministic [FeedWinSeeds]
/// defaults instead.
class FeedWinModel {
  /// The bound template, or `null` for demo / golden instances.
  final DefaultPlayerTemplate? template;

  /// Bridge a live template (host-supplied) — or `null` for the deterministic demo
  /// seeds (previews / golden tests).
  const FeedWinModel({this.template});

  // -- Surface 1: ChatFeedView ← merged activity + chat feed -------------------

  /// The merged, ordered, tail-retained (N=7) feed (`DefaultActivityFeed.items`).
  /// Already merged / ordered by the data layer (newest at the tail) — this layer
  /// MUST NOT slice / merge / re-sort (a second copy would violate single-truth).
  List<LBFeedItem> get feedItems =>
      template?.feed.items ?? FeedWinSeeds.feedItems;

  /// 置頂留言（chat-message-taxonomy ⑤，`template.pinnedMessage`，來自 `poll.top`）。非 null →
  /// ChatFeed 上緣渲染置頂橫幅；無釘選 → null（demo 預設 [FeedWinSeeds.pinned] = null）。
  PinnedMessage? get pinned => template?.pinnedMessage ?? FeedWinSeeds.pinned;

  /// 主播名（rb-flutter-loading-announce-restyle）— `LBFeedKind.eventJoin` restyled 列的 header
  /// 顯示此值。鏡像既有 `PlayerShellModel.hostName` 的單一真相讀法（同一顆 `template.header.
  /// hostName`，channel 全域快照，非逐則訊息欄位——`LBFeedItem` 本身不帶主播名欄位，本 getter 不
  /// 新增第二份狀態）。demo / unbound → [FeedWinSeeds.hostName]。
  String get hostName => template?.header.hostName ?? FeedWinSeeds.hostName;

  /// Whether the LIVE 公告橫幅 (`LBLiveAnnounce`) is currently showing — the bound template's
  /// notice-tab `notice` is non-empty (the SAME single source as `PlayerShellModel.announceText`,
  /// kept current by `flutter-notice-poll-ingest`). The chat feed reads this to add the 公告橫幅
  /// height to its bottom inset so the lowest chat rows don't overlap the bottom-left 公告橫幅
  /// (問題4, rb-flutter-live-announce-chat-clearance). demo / unbound → `false` (no extra clearance →
  /// golden byte-identical).
  bool get hasAnnounce => (template?.noticeTab.current.notice ?? '').isNotEmpty;

  /// The deeper scrollable history buffer (`DefaultActivityFeed.history`, cap 50) —
  /// bound by the SCROLLABLE [ChatFeedView] so the user can scroll up to view recent
  /// history (parity with iOS `feedHistory`). Demo instances reuse the same seed.
  List<LBFeedItem> get feedHistory =>
      template?.feed.history ?? FeedWinSeeds.feedItems;

  // -- Surface 2: WinEntryView ← unclaimed win entry --------------------------

  /// Distinct unclaimed-win count (`DefaultWinClaim.unclaimedCount`); the entry
  /// badge is drawn only when `> 0`, with the badge number == this count. For demo
  /// instances returns the seed winners' count.
  int get unclaimedCount =>
      template?.winClaim.unclaimedCount ?? FeedWinSeeds.unclaimedWinners.length;

  /// Unclaimed winners, insertion-ordered, deduped by `winner.id`
  /// (`DefaultWinClaim.unclaimedWinners`). The entry opens the claim sheet on the
  /// EARLIEST unclaimed winner ([nextUnclaimedWinner]). For demo instances returns
  /// [FeedWinSeeds.unclaimedWinners].
  List<LBWinner> get unclaimedWinners =>
      template?.winClaim.unclaimedWinners ?? FeedWinSeeds.unclaimedWinners;

  // -- Surface 3: WinClaimSheetView ← claim result feedback -------------------

  /// Latest mapped claim-result feedback (`DefaultWinClaim.resultState`); `null`
  /// until a result arrives (`.successProduct` / `.successDiscount(awardCode)` /
  /// `.failure`). On a claimed result the template removes the winner and
  /// `unclaimedCount` decrements — both re-read here via the container's
  /// `ListenableBuilder`. For demo instances always `null` (the pre-submit prompt).
  LBClaimResultState? get resultState => template?.winClaim.resultState;

  /// 領獎「送出中」旗標（`DefaultWinClaim.submitInFlight`），驅動 `WinClaimSheetView` 的
  /// `submitting` 階段（scrim + spinner +「送出中…」）。
  ///
  /// **這是唯一的 in-flight 真相** —— reference-ui MUST NOT 自造第二份（否則 view-model 的
  /// guard 擋下提交時畫面會卡住，host 攔截 `awardClaimIntent` 時也會與 view-model 分歧）。
  /// 每次讀取直接讀 view-model getter（不存鏡像）；demo / 未綁定 template → `false`，使各
  /// stage 的 golden 可決定式重現。
  bool get submitInFlight => template?.winClaim.submitInFlight ?? false;

  /// CTA classification for `winner` (`DefaultWinClaim.classify(winner)`:
  /// `.product`→「查看獎品」, `.discount`→「立即使用」, `.other`→ host 退場文案). For demo
  /// instances derives the SAME classification from the public `winner.award.type`
  /// via [LBClaimClassification.fromAwardType] (the single rule the template's
  /// classifier applies), so the claim sheet still classifies correctly in
  /// previews / golden tests.
  LBClaimClassification classify(LBWinner winner) =>
      template?.winClaim.classify(winner) ??
      LBClaimClassification.fromAwardType(winner.award.type);

  // -- Surface: WinEntryView(variant: activity) / ActivitySheetView ----------
  // (rb-flutter-live-activity-sheet, binds `live-activity-entry-flutter-template`'s
  // `DefaultActiveEvent`.)
  //
  // 🔴 rb-flutter-activity-sheet-cta-repeatable REMOVED the `activeEventJoined`
  // getter that used to live here (`template?.activeEvent.joined ?? false`) —
  // `ActivitySheetView`'s CTA no longer reads any "already joined" signal (the
  // reported bug: the CTA used to lock into a disabled「已參加」state after one
  // join). `DefaultActiveEvent.joined` itself is untouched in `flutter-ui` — this
  // reference-ui layer simply stopped being one of its consumers.

  /// Whether there is a currently active live event
  /// (`DefaultActiveEvent.hasActiveEvent`). `WinEntryView(variant: activity)` is
  /// drawn ONLY when this is `true`. For demo instances always `true`
  /// ([FeedWinSeeds.activeEvent] is always non-null), so the demo / golden path
  /// exercises BOTH entries stacked together.
  bool get hasActiveEvent => template?.activeEvent.hasActiveEvent ?? true;

  /// The currently active event snapshot (`DefaultActiveEvent.current`), passed
  /// BY VALUE to `WinEntryView(variant: activity)` / `ActivitySheetView`. For
  /// demo instances returns [FeedWinSeeds.activeEvent].
  LBActiveEvent? get currentActiveEvent =>
      template?.activeEvent.current ?? FeedWinSeeds.activeEvent;

  /// Full list of currently-active events (`DefaultActiveEvent.activities`,
  /// rb-flutter-activity-sheet-pagination) — `ActivitySheetView`'s pagination reads
  /// `.length` as `pageCount`. For demo instances returns a single-element list
  /// built from [FeedWinSeeds.activeEvent] (non-null) — this keeps the demo/golden
  /// path's `pageCount == 1` (no pagination dots) consistent with
  /// [hasActiveEvent]'s own demo default of `true` (one active event, not zero).
  List<LBActiveEvent> get activities =>
      template?.activeEvent.activities ?? [FeedWinSeeds.activeEvent];

  /// The page index [currentActiveEvent] is derived from
  /// (`DefaultActiveEvent.currentActivityPageIndex`, rb-flutter-activity-sheet-pagination).
  /// For demo instances always `0`.
  int get activityPageIndex => template?.activeEvent.currentActivityPageIndex ?? 0;

  // -- Read-only host intents (pass-through to the bound template) ------------
  //
  // The feed-win layer does NOT carry actions. These are thin forwarders for the
  // template-owned intents the family-2 surfaces need that have no direct core
  // `simulate*` reachable here. They are no-ops for demo instances (no template).

  /// Forward a win claim **carrying the user-entered [email]** to the bound template
  /// (template exit `DefaultWinClaim.submitWithEmail(winner, email)`).
  ///
  /// Returns `true` when the view-model actually accepted the submit (past its
  /// re-entrancy + `isValidEmail` guards, and now `submitInFlight`); `false` when a
  /// guard rejected it — or when there is no bound template (demo / golden).
  ///
  /// 🔴 **容器 MUST 以此回傳值當閘門**再決定要不要呼叫 `onSubmitClaim`（= 打 core 領獎
  /// API）。否則 double-tap 會在 view-model 已拒絕的情況下仍打出第二次
  /// `POST /sdk/video/claim`，後端回「已領過」→ `500 api.fail` → 使用者看到**假失敗**。
  /// 見 `feed_win_view.dart` `_handleSubmitClaim`。
  ///
  /// The result then arrives via the template's `notifyListeners` → the container's
  /// `ListenableBuilder` re-read.
  ///
  /// NAME: iOS / Android / RN 皆拼成「同名多一個參數」（`submitClaim(for:email:)` /
  /// `submitClaim(winner, email)`）。**Dart 沒有方法多載**，且既有的 [submitClaim] 是本
  /// 套件 barrel 匯出的公開 API（就地換簽章＝源碼 BREAKING），故 Flutter 的 parity 名是
  /// `submitClaimWithEmail` —— 鏡像 template 自己的 `submit` → `submitWithEmail` 決定，
  /// 不發明第二種命名風格。
  bool submitClaimWithEmail(LBWinner winner, String email) =>
      template?.winClaim.submitWithEmail(winner, email) ?? false;

  /// Forward「關閉領獎畫面」to the bound template (`DefaultWinClaim.dismissClaim()` —
  /// clears `resultState` + `submitInFlight`).
  ///
  /// 🔴 這是**純 dismiss**：MUST NOT 從 `unclaimedWinners` 移除該 winner、MUST NOT 呼叫任何
  /// API、MUST NOT 遞減未領徽章 —— 使用者可以再次開啟領取。設計稿的「放棄資格、此動作無法
  /// 復原」是**刻意的 UX 摩擦文案**，行為不跟隨（權威：`design/contract/claude-design-sync.md`
  /// R13 刻意分歧 1/2）。No-op for demo instances (no bound template).
  void dismissClaim() => template?.winClaim.dismissClaim();

  /// EMAIL-LESS 領獎轉發 —— **DEPRECATED**，只為源碼相容保留（簽章刻意不變）。
  ///
  /// 它走 `DefaultWinClaim.submit(winner)`（contact 恆 null），而 core 預設領獎路徑 `email`
  /// 必填，故未被 host 攔截時**必然失敗**（core fail-fast、連 `POST /sdk/video/claim` 都不
  /// 送）。請改用 [submitClaimWithEmail]。**本層生產路徑已不再呼叫本入口。**
  ///
  /// （標為 deprecated 亦使其內部對 deprecated template 入口的呼叫不再產生警告。）
  @Deprecated(
    'EMAIL-LESS 領獎未被 host 攔截時必然失敗（core 預設領獎路徑 email 必填）。'
    '改用 submitClaimWithEmail(winner, email)。',
  )
  void submitClaim(LBWinner winner) =>
      // ignore: deprecated_member_use
      template?.winClaim.submit(winner);

  /// Apply the OPTIMISTIC「已參加」flip for an event-join feed row
  /// (`DefaultActivityFeed.markJoined(eid)`). No-op for demo instances.
  ///
  /// 🔴 This is a **pure UI flip only** — `markJoined` does NOT reach core (an
  /// earlier doc here wrongly said it "internally calls `requestEventJoin`"; it does
  /// not, and that wrong belief is part of why the Flutter drop-in join never reached
  /// core). The ACTUAL core send is done by the turnkey CONTAINER via
  /// `_controller.requestEventJoin(eid, keyword)` (rb-flutter-event-join-reaches-core),
  /// because the Flutter template holds no native player ref and `LivebuyUI.install()`
  /// injects no `eventJoinRequester` (inert). See `FeedWinOverlayView._handleJoin`.
  void joinEvent(int eid) => template?.feed.markJoined(eid);

  /// Forward「參加活動」to the bound template (`DefaultActiveEvent.join()` —
  /// view-model handles the `keyword`-forwarding + dedupe-by-id; this layer does
  /// not repeat either check). No-op for demo instances (no bound template).
  void joinActiveEvent() => template?.activeEvent.join();

  /// Forward「換頁」to the bound template (`DefaultActiveEvent.setActivityPageIndex`,
  /// rb-flutter-activity-sheet-pagination) — the view-model handles clamping
  /// (`clampActivityPageIndex`), this layer does not repeat that check. No-op for
  /// demo instances (no bound template).
  void setActivityPageIndex(int index) =>
      template?.activeEvent.setActivityPageIndex(index);

  // -- Convenience reads (surface helpers, pure) ------------------------------

  /// The earliest unclaimed winner the entry should open the sheet on, or `null`
  /// when there is nothing to claim (`unclaimedCount == 0`).
  LBWinner? get nextUnclaimedWinner =>
      unclaimedWinners.isEmpty ? null : unclaimedWinners.first;
}

// MARK: - Deterministic demo seeds (previews / golden tests)

/// Plain-literal deterministic seeds for the family-2 surfaces' previews + the
/// per-surface golden / widget tests. Constructed via the public template / core
/// ctors (`LBFeedItem.chat` / `.eventJoin` / `.join` / `.purchase` / `.win` /
/// `LBWinner` / `LBAward`) so a snapshot does NOT depend on a live player. Mirrors
/// the iOS demo seeds (`ChatFeedView.demoFeed` / `WinEntryView.demoUnclaimedWinners`
/// / `WinClaimSheetView.demoDiscountWinner`) and the Android `FeedWinSeeds`.
class FeedWinSeeds {
  FeedWinSeeds._();

  /// Demo pinned message — `null` (no 置頂橫幅; existing ChatFeed goldens byte-identical).
  static const PinnedMessage? pinned = null;

  /// Demo host name for the restyled event-join bubble header (rb-flutter-loading-
  /// announce-restyle) — same literal as `PlayerShellSeeds.hostName` so the demo /
  /// golden shows ONE consistent host identity across the header AND the merged feed's
  /// event-join row.
  static const String hostName = 'BeautyTown 官方';

  // -- Surface 1: merged chat-feed demo --------------------------------------

  /// Deterministic demo feed (oldest → newest, tail at end), covering all row shapes
  /// the merged feed produces: `LBFeedItem.chat`, an UN-joined `LBFeedItem.eventJoin`
  /// (the only interactive row), and all FOUR `LBFeedItem.activity` tiers
  /// (`LBActivityTier.join` / `.purchase` / `.intro` / `.win`). `text` is the
  /// backend-prebuilt full string — surfaces MUST NOT split it. Mirrors iOS
  /// `ChatFeedView.demoFeed` + Android `FeedWinSeeds.feedItems`. The win-tier row
  /// carries the win winner so the feed stays self-contained.
  static final List<LBFeedItem> feedItems = [
    LBFeedItem.chat('Boa', '博士心動 💛'),
    LBFeedItem.join('王小明 剛剛加入'),
    LBFeedItem.eventJoin(
      eid: 8821,
      keyword: '抽獎',
      text: '🎉 抽獎開始!留言「抽獎」即可參加',
    ),
    LBFeedItem.intro('開始介紹「玫瑰精華水 150ml」'),
    LBFeedItem.chat('CoCo', '這個顏色好美 😍'),
    LBFeedItem.purchase('Mia 購買了「絲絨唇釉 #04 焦糖」'),
    LBFeedItem.win('boacat77 中獎了!', _winWinner),
  ];

  // -- Surface 2: unclaimed win entry demo -----------------------------------

  /// Deterministic unclaimed-win set: two winners (a discount award + a product
  /// award), insertion-ordered, so a `count == 2` badge renders and the entry opens
  /// the sheet on the first (discount). Built ONLY from real public `LBWinner` /
  /// `LBAward` ctor fields. Mirrors iOS `WinEntryView.demoUnclaimedWinners` +
  /// Android `FeedWinSeeds.unclaimedWinners` (order: discount then product so the
  /// demo sheet shows the「立即使用」+ awardCode path, matching the
  /// `win-claim-sheet-discount` baseline).
  static final List<LBWinner> unclaimedWinners = [
    discountWinner,
    LBWinner(
      id: 'demo-win-product-001',
      eventId: 4201,
      title: '週年慶限定抽獎',
      award: LBAward(
        type: 'product',
        code: 'SKU-AURORA-LIP',
        name: 'Aurora 霧面唇釉 #03 珊瑚橘',
      ),
    ),
  ];

  // -- Surface 3: discount winner for the win-claim sheet --------------------

  /// The deterministic demo DISCOUNT winner (CTA「立即使用」+ awardCode) — the same
  /// winner the entry opens the sheet on first, driving the `win-claim-sheet-discount`
  /// golden. Mirrors iOS `WinClaimSheetView.demoDiscountWinner` + Android
  /// `FeedWinSeeds.discountWinner`.
  static final LBWinner discountWinner = LBWinner(
    id: 'demo-win-discount-001',
    eventId: 4202,
    title: '整點快閃抽獎',
    award: LBAward(
      type: 'discount',
      code: 'LIVE5OFF',
      name: '全館 5 折優惠券',
    ),
  );

  /// The win-tier feed row's winner (a product award) — kept distinct from the
  /// unclaimed entry winners so the feed demo stays self-contained.
  static final LBWinner _winWinner = LBWinner(
    id: 'demo-feed-win-001',
    eventId: 4203,
    title: '直播限定抽獎',
    award: LBAward(
      type: 'product',
      code: 'SKU-FEED-WIN',
      name: '限定週邊禮盒',
    ),
  );

  // -- Surface: WinEntryView(variant: activity) / ActivitySheetView demo -----

  /// Deterministic demo active event (rb-flutter-live-activity-sheet) —
  /// non-null so the demo / golden path exercises BOTH `WinEntryView` variants
  /// stacked together (parity with [unclaimedWinners] being non-empty by
  /// default). Carries a `keyword` so the demo/golden also exercises the「立即
  /// 參加」CTA path (the keyword-less path is covered by dedicated test cases,
  /// not this shared demo seed).
  static final LBActiveEvent activeEvent = LBActiveEvent(
    id: 615,
    title: '週年慶抽獎',
    keyword: '168',
    duration: 300,
    surplus: 180,
    award: [LBAward(type: 'discount', code: 'LIVE168', name: '咖啡券')],
  );
}
