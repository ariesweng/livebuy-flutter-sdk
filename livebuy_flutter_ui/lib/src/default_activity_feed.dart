import 'package:flutter/foundation.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart';

// reconcile-activity-notification-contract-template §1 — Activity + chat merged
// feed (behaviour / view-model layer; NO pixels).
//
// The Default template subscribes to the core activity deliveries
// (`showJoin` / `showPurchase` / `showWin`) and chat messages (push + comments)
// and merges them into ONE ordered feed model — newest at the tail — matching
// the delivered design `moments.jsx` (`LBLiveChatStream`). Each activity item
// carries a visual-tier marker (join < purchase < win) so the host can decide
// emphasis. The template draws NO rows; the host binds [items] and renders.
//
// DATA-LAYER merge ONLY: activity events are merged here, but MUST NOT be
// double-written into the ChatView chat data source (push / comments). The
// single `text: String` per item is preserved as-is (already i18n'd by the
// backend) and MUST NOT be split into userName + goodsName.

/// Visual emphasis tier for an activity feed item (join < purchase < intro <
/// win). The host binds [LBFeedItem.tier] to decide styling; the template ranks
/// them numerically so cross-platform parity is unambiguous.
/// `intro`（商品開始介紹）來源為商品推播 push（`#66F796`），強調介於購買與中獎之間
/// (parity iOS rawValue join=0 / purchase=1 / intro=2 / win=3).
enum LBActivityTier {
  join,
  purchase,
  intro,
  win,
  /// 觀眾選購（chat-message-taxonomy ⑤，來源 `kind == narrate` / `#66F796`）——與 `join` 同級的
  /// 最低調社會認同（非主播訊息、非購買、非介紹中）。
  browse;

  /// Numeric rank (入場 / 觀眾選購 < 購買 < 介紹 < 中獎) for host emphasis decisions.
  /// `browse` 與 `join` 同為最低調 → rank 0。
  int get rank {
    switch (this) {
      case LBActivityTier.join:
        return 0;
      case LBActivityTier.browse:
        return 0;
      case LBActivityTier.purchase:
        return 1;
      case LBActivityTier.intro:
        return 2;
      case LBActivityTier.win:
        return 3;
    }
  }
}

/// Whether a merged feed item is an activity notice, a chat message, or an
/// event-join row (core event-begin push; host draws `LBEventJoinLine`).
enum LBFeedKind { activity, chat, eventJoin, productSale }

/// One row in the merged activity + chat feed (view-model only; no pixels).
///
/// Activity items carry [tier] (and, for win, the [winner]); chat items carry
/// [userName]. Every item keeps the backend-composed single [text] string —
/// the template MUST NOT split it into name + goods fields (§1, design D1).
class LBFeedItem {
  final LBFeedKind kind;

  /// Tier marker; non-null only for activity items.
  final LBActivityTier? tier;

  /// Backend pre-composed, already-i18n'd string. Single field by contract.
  final String text;

  /// Chat author display name; non-null only for chat items.
  final String? userName;

  /// Winner payload; non-null only for win-tier activity items.
  final LBWinner? winner;

  /// Core event id; non-null only for event-join items (`> 0`).
  final int? eid;

  /// Core event keyword (`ek`); non-null only for event-join items.
  final String? keyword;

  /// Template-OPTIMISTIC join flag (event-join items only). false on surface;
  /// the template flips it to true once the host triggers the join intent (core
  /// has NO "join succeeded" callback). Ignored for non-eventJoin rows.
  final bool joined;

  // chat-message-taxonomy ⑤ — 群組① 真正的聊天的角色 metadata（chat items only）。
  /// 主播留言 / 主播回覆（`kind == host` / `host_reply` / `ai_reply`）。`false` for viewer
  /// (`comment`)。供 reference-ui 依**版型**畫「主播」標 + accent 氣泡（非以顏色區分）。預設 false。
  final bool isHost;

  /// AI 自動回覆（`kind == ai_reply`）。`true` 在主播回覆版型上加「AI」標。預設 false。
  final bool isAI;

  /// 主播回覆 / AI 回覆的被回覆引用內容（backend `LBPushMsg.reply`），獨立字串（NOT split from
  /// `text`）。null → 無引用框。後端無「引用者名稱」欄，故只帶引用文字。預設 null。
  final String? replyText;

  /// 已格式化開賣價（chat-message-taxonomy ⑤ 群組① onsale）；non-null only for productSale items
  /// （`text` = 商品名、[price] = `push.price`，權威輸出欄非上游 `p`）。供 reference-ui 渲染
  /// `LBProductSaleCard`。預設 null。
  final String? price;

  const LBFeedItem._({
    required this.kind,
    required this.text,
    this.tier,
    this.userName,
    this.winner,
    this.eid,
    this.keyword,
    this.joined = false,
    this.isHost = false,
    this.isAI = false,
    this.replyText,
    this.price,
  });

  /// Build a join-tier activity item.
  factory LBFeedItem.join(String text) =>
      LBFeedItem._(kind: LBFeedKind.activity, tier: LBActivityTier.join, text: text);

  /// Build a purchase-tier activity item.
  factory LBFeedItem.purchase(String text) => LBFeedItem._(
      kind: LBFeedKind.activity, tier: LBActivityTier.purchase, text: text);

  /// Build an intro-tier activity item (商品開始介紹 / 商品推播 `#66F796`).
  factory LBFeedItem.intro(String text) => LBFeedItem._(
      kind: LBFeedKind.activity, tier: LBActivityTier.intro, text: text);

  /// Build a browse-tier activity item — 觀眾選購（chat-message-taxonomy ⑤ `kind == narrate`，
  /// `#66F796`）。**性質同 join、非主播訊息、非介紹中**，以最低調 browse tier 呈現。
  factory LBFeedItem.narrate(String text) => LBFeedItem._(
      kind: LBFeedKind.activity, tier: LBActivityTier.browse, text: text);

  /// Build a win-tier activity item (carries the [winner] for the entry/sheet).
  factory LBFeedItem.win(String text, LBWinner winner) => LBFeedItem._(
        kind: LBFeedKind.activity,
        tier: LBActivityTier.win,
        text: text,
        winner: winner,
      );

  /// Build a chat-message item. `isHost` / `isAI` / `replyText` 為角色 metadata
  /// （chat-message-taxonomy ⑤）；皆預設 → 既有觀眾留言呼叫點 byte-identical。
  factory LBFeedItem.chat(
    String userName,
    String text, {
    bool isHost = false,
    bool isAI = false,
    String? replyText,
  }) =>
      LBFeedItem._(
        kind: LBFeedKind.chat,
        text: text,
        userName: userName,
        isHost: isHost,
        isAI: isAI,
        replyText: replyText,
      );

  /// Build a product-sale card item (chat-message-taxonomy ⑤ 群組① onsale). [name] = 商品名
  /// （沿用共用 `text` 欄，parity iOS `LBFeedItem.text`）、[price] = 已格式化開賣價（`push.price`）。
  factory LBFeedItem.productSale(String name, String price) =>
      LBFeedItem._(kind: LBFeedKind.productSale, text: name, price: price);

  /// Build an event-join item (core event-begin push). [joined] starts false.
  factory LBFeedItem.eventJoin({
    required int eid,
    required String keyword,
    String text = '',
    bool joined = false,
  }) =>
      LBFeedItem._(
        kind: LBFeedKind.eventJoin,
        text: text,
        eid: eid,
        keyword: keyword,
        joined: joined,
      );

  bool get isActivity => kind == LBFeedKind.activity;

  /// True when this row is an event-join row (host draws `LBEventJoinLine`).
  bool get isEventJoin => kind == LBFeedKind.eventJoin;

  /// Internal: copy of this event-join item with a new [joined] flag (the feed
  /// is immutable per-item, so optimistic marking rebuilds the row).
  LBFeedItem _copyWithJoined(bool joined) => LBFeedItem._(
        kind: kind,
        text: text,
        tier: tier,
        userName: userName,
        winner: winner,
        eid: eid,
        keyword: keyword,
        joined: joined,
        isHost: isHost,
        isAI: isAI,
        replyText: replyText,
        price: price,
      );
}

/// Merged activity + chat feed view-model for the Default template (§1).
///
/// Maintains a single ordered list (newest at the tail) and retains only the
/// last [tailRetain] items — the shared Default-template constant N = 7, taken
/// from `moments.jsx`'s `LBLiveChatStream` `items.slice(-7)` (tasks 0.3). The
/// host binds [items] and draws the rows. Stay / fade timings are host pixels,
/// not part of this behaviour layer.
///
/// Observability (expose-default-template-bindable-state, design D1):
/// implements [ChangeNotifier] so the host can bind via `ListenableBuilder` /
/// `AnimatedBuilder` and re-read [items] on change. A COALESCED notification
/// ("something changed", no diff payload) fires EXACTLY ONCE after each single
/// state change — every merged append (join / purchase / win / chat) and
/// [clear]. When the host adds no listener the behaviour is unchanged (purely
/// additive). [notifyListeners] dispatches on the platform/UI thread (the
/// Default template wiring consumes core events on that thread already).
class DefaultActivityFeed extends ChangeNotifier {
  /// Shared Default-template tail-retain constant (N = 7) across all 4 platforms.
  static const int tailRetainDefault = 7;

  /// Chat-row retention cap — the SCROLLABLE history keeps up to this many chat rows
  /// (`kind == LBFeedKind.chat`: viewer / host / host-reply / AI-reply + `onSystemNotice`
  /// system notices). Chat is trimmed INDEPENDENTLY from activity rows (separate retention),
  /// so a busy activity stream can NEVER evict chat — the core guarantee of this model.
  /// = 500 (carried over from the prior single shared cap) so chat protection only gets
  /// BETTER (chat alone can still fill 500, and is no longer diluted by activity). Maintained
  /// once per platform; Flutter = 500 aligns with iOS (`activityFeedChatRetain`) / Android
  /// (`DefaultFeedConstants.CHAT_RETAIN`) / RN (`DEFAULT_FEED_CHAT_RETAIN`) — 4-platform parity
  /// finale (all = 500).
  static const int chatRetainDefault = 500;

  /// Activity-row retention cap — the SCROLLABLE history keeps up to this many non-chat rows
  /// (activity join / purchase / browse / intro / win + `eventJoin` + `productSale`). Trimmed
  /// INDEPENDENTLY from chat rows, so activity stays bounded WITHOUT eating chat's quota.
  /// = 200: the ambient overlay only shows newest 7, and 200 scrollback rows of social-proof
  /// activity is ample context; 200 also far exceeds `tailRetainDefault=7` / `dedupeWindowDefault=64`.
  /// Memory upper bound = `chatRetainDefault + activityRetainDefault` = 700 lightweight `LBFeedItem`.
  /// Maintained once per platform; Flutter = 200 aligns with iOS (`activityFeedActivityRetain`) /
  /// Android (`DefaultFeedConstants.ACTIVITY_RETAIN`) / RN (`DEFAULT_FEED_ACTIVITY_RETAIN`) —
  /// 4-platform parity finale (all = 200).
  static const int activityRetainDefault = 200;

  /// DEPRECATED single shared FIFO cap (chat + activity combined). Flutter no longer trims by a
  /// single total cap — trim is now per-type (see [chatRetainDefault] / [activityRetainDefault])
  /// so real chat is never evicted by an activity flood. The value (500) is retained for source
  /// compatibility (a downstream reader won't break); it is NOT used for trimming any more.
  @Deprecated(
      'Flutter now uses per-type separate retention: use chatRetainDefault (500) + activityRetainDefault (200). '
      'This single shared cap no longer drives trimming (value kept = 500 for source compatibility).')
  static const int historyRetainDefault = 500;

  /// Recent-seen signature window for de-duplicating ACTIVITY / EVENT-JOIN rows (chat
  /// is never deduped). Bounded so a re-sent poll item (no stable id) is not appended
  /// twice across several poll cycles. Shared across all 4 platforms.
  static const int dedupeWindowDefault = 64;

  /// Backend "product push" message color (spec §PollManager fan-out). A poll `push[]` row
  /// carrying this `color` is a 商品推播 / 開賣 notification that only surfaces in the chat feed.
  /// Used to route such system notices through the DE-DUPED chat path so an adjacent-poll re-send
  /// isn't shown twice (free user chat stays un-deduped). Shared across all 4 platforms.
  static const String productPushColor = '#66F796';

  final int tailRetain;

  /// Chat-row retention cap for this instance (default [chatRetainDefault]). Chat rows are
  /// trimmed independently of activity rows — real chat is never evicted by an activity flood.
  final int chatRetain;

  /// Activity-row retention cap for this instance (default [activityRetainDefault]). Non-chat
  /// rows (activity / eventJoin / productSale) are trimmed independently of chat rows.
  final int activityRetain;

  final int dedupeWindow;

  /// Bounded recent-seen signatures for ACTIVITY / EVENT-JOIN rows so a backend
  /// re-send on an adjacent poll (no stable id) is not appended twice. Chat rows are
  /// NEVER recorded / deduped (identical chat text from two users is legitimate).
  final List<String> _recentSignatures = [];

  /// When the host installs its own activity listener and takes over, set this
  /// so the template excludes activity events from the merged feed (reusing the
  /// existing event-interceptor rule; §1 / design D5). Chat messages are
  /// unaffected. Default `false` → Default template owns the feed.
  bool hostOwnsActivity;

  // The deep scrollable history buffer, deeper than the N=7 ambient slice, newest at the
  // tail. Trimmed per-type (chat cap [chatRetain] + activity cap [activityRetain]) so real
  // chat is never evicted by an activity flood. The reference-ui SCROLLABLE chat feed binds
  // [history] so the user can scroll up to view recent history.
  final List<LBFeedItem> _items = [];

  DefaultActivityFeed({
    this.tailRetain = tailRetainDefault,
    int chatRetain = chatRetainDefault,
    int activityRetain = activityRetainDefault,
    this.dedupeWindow = dedupeWindowDefault,
    this.hostOwnsActivity = false,
  })  : chatRetain = chatRetain < tailRetain ? tailRetain : chatRetain,
        activityRetain = activityRetain < 1 ? 1 : activityRetain;

  /// Immutable AMBIENT slice — the newest [tailRetain] (N=7) rows of [history].
  /// UNCHANGED contract; derived from [history] (single source of truth).
  List<LBFeedItem> get items => List.unmodifiable(
      _items.length <= tailRetain ? _items : _items.sublist(_items.length - tailRetain));

  /// Immutable full scrollable history buffer (per-type caps [chatRetain] / [activityRetain],
  /// newest at the tail) — bound by the SCROLLABLE reference-ui chat feed (scroll up for history).
  List<LBFeedItem> get history => List.unmodifiable(_items);

  /// Convenience: how many items the host would draw in the ambient slice (≤ N=7).
  int get length => _items.length <= tailRetain ? _items.length : tailRetain;

  /// Ingest a join-tier activity notice (core `showJoin`). Excluded when the
  /// host owns activity.
  void onJoin(String text) => _appendActivity(LBFeedItem.join(text));

  /// Ingest a purchase-tier activity notice (core `showPurchase`).
  void onPurchase(String text) => _appendActivity(LBFeedItem.purchase(text));

  /// Ingest an intro-tier activity notice — 商品推播（`push[]` 帶商品推播色 `#66F796`，
  /// 例如「商品開賣 / 開始介紹」）→ feed activity row, tier = intro（強調介於購買與中獎
  /// 之間）。商品推播 push 無 stable id，故與 join / purchase 同樣走 activity 去重
  /// （簽名涵蓋 tier）。Routed here by `DefaultPlayerTemplate.handlePush`.
  void onIntro(String text) => _appendActivity(LBFeedItem.intro(text));

  /// 觀眾選購（chat-message-taxonomy ⑤ `kind == narrate`，`#66F796`）→ feed 社會認同 activity row
  /// （「{觀眾名} 正在選購商品～」），以低調 `browse` tier（與 join 同級）呈現。**性質同 join /
  /// purchase、非主播訊息、非介紹中**。push 無 stable id → 走 activity 去重（簽名涵蓋 tier + text）。
  void onNarrate(String text) => _appendActivity(LBFeedItem.narrate(text));

  /// Ingest a win-tier activity notice (core `showWin`). The win feed item is
  /// INDEPENDENT from the unclaimed entry state (§2): this is "中獎發生".
  void onWin(String text, LBWinner winner) =>
      _appendActivity(LBFeedItem.win(text, winner));

  /// Ingest a chat message (push / comments). Always merged — chat is never
  /// excluded by the activity host-takeover flag. `isHost` / `isAI` / `replyText` 為角色
  /// metadata（chat-message-taxonomy ⑤）；`replyText` blank → null（無引用框）。皆預設 → 既有
  /// 觀眾留言 byte-identical。
  void onChat(
    String userName,
    String text, {
    bool isHost = false,
    bool isAI = false,
    String? replyText,
  }) {
    final trimmedReply = replyText?.trim();
    final reply = (trimmedReply != null && trimmedReply.isNotEmpty) ? trimmedReply : null;
    _append(LBFeedItem.chat(userName, text,
        isHost: isHost, isAI: isAI, replyText: reply));
  }

  /// Ingest a SYSTEM / 商品推播 notice (e.g.「商品開賣」) as a chat row but DE-DUPED. The poll
  /// `push[]` bucket has no stable id, so a backend re-send on an adjacent poll would otherwise
  /// appear twice. Unlike free user chat (which legitimately repeats and is NEVER deduped), an
  /// identical system notice (signature `cs|<text>`) within the window is dropped. Routed here by
  /// `DefaultPlayerTemplate.handlePush` for product/event/promo pushes.
  void onSystemNotice(String text) =>
      // chat-history-dedupe-template — NO dedupeKey. 後台刻意重送的相同系統通知是真實訊息（cursor 分流
      // 已在 TemplateAttachment 攔機制性 backlog 重放），內容去重會誤殺。對齊 iOS/Android/RN。
      _append(LBFeedItem.chat('', text));

  /// Surface a core event-begin push as an INDEPENDENT event-join item (host
  /// draws `LBEventJoinLine`). `joined` starts false. Always merged (it derives
  /// from a chat push, not an activity notice). event-END pushes MUST NOT reach
  /// here — they stay plain chat rows (see `DefaultPlayerTemplate.handlePush`).
  void onEventJoin({required int eid, required String keyword, String text = ''}) =>
      _append(LBFeedItem.eventJoin(eid: eid, keyword: keyword, text: text));

  /// Template-optimistic join mark: flip every still-unjoined event-join item
  /// for [eid] to `joined = true`. Fires one coalesced notification iff anything
  /// changed. Public so a host that takes over `eventJoinIntent` can set the
  /// flag via this hook (design D2).
  void markJoined(int eid) {
    var changed = false;
    for (var i = 0; i < _items.length; i++) {
      final it = _items[i];
      if (it.kind == LBFeedKind.eventJoin && it.eid == eid && !it.joined) {
        _items[i] = it._copyWithJoined(true);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  void _appendActivity(LBFeedItem item) {
    if (hostOwnsActivity) return; // host took over — exclude from feed.
    _append(item);
  }

  void _append(LBFeedItem item, {String? dedupeKey}) {
    // Defensive de-dup for ACTIVITY / EVENT-JOIN rows (and SYSTEM-notice chat rows that pass an
    // explicit [dedupeKey]): a re-sent poll item would otherwise show the same join / system
    // notice twice. An ORDINARY chat row has no key (_dedupeSignature == null) → never deduped.
    final signature = dedupeKey ?? _dedupeSignature(item);
    if (signature != null) {
      if (_recentSignatures.contains(signature)) return;
      _recentSignatures.add(signature);
      if (_recentSignatures.length > dedupeWindow) {
        _recentSignatures.removeRange(0, _recentSignatures.length - dedupeWindow);
      }
    }
    // Append to the deep history buffer, then trim PER-TYPE (chat cap [chatRetain] + activity
    // cap [activityRetain], independent) so real chat is never evicted by an activity flood
    // (separate-retention core guarantee). [items] derives newest N=7 from the trimmed buffer.
    // This is Flutter's ONLY trim site (no restore / batchIngest; backlog dispatch is gated by
    // `DefaultPlayerTemplate.shouldIngestPoll` which only decides whether to ingest, not trim —
    // every ingested row funnels through here for per-row convergence).
    _items.add(item);
    final trimmed = trimmedByType(_items, chatRetain, activityRetain);
    if (trimmed.length != _items.length) {
      _items
        ..clear()
        ..addAll(trimmed); // keep the same `final List` reference for items / history getters.
    }
    notifyListeners(); // coalesced "feed changed" — exactly once per append (D1).
  }

  /// De-dup signature for a feed row. **所有 kind 現在皆回 null（不做內容指紋去重）**：chat 一向 null
  /// （兩人同字合法）；activity / productSale 於 chat-history-dedupe-template 移除；eventJoin 於
  /// chat-event-message-no-dedupe-template 移除（活動公告會被直播主刻意重播，每筆都顯示——`e<eid>|<text>`
  /// 內容指紋去重會誤殺真實重播）。機制性 backlog 重放的防重複改由 cursor (`is_backlog`) 分流
  /// （TemplateAttachment 的 shouldIngestPoll gate + 原生 PollManager 跨重入 cursor 保存）。對齊 iOS/Android/RN。
  String? _dedupeSignature(LBFeedItem item) {
    switch (item.kind) {
      case LBFeedKind.chat:
        return null;
      case LBFeedKind.activity:
        return null;
      case LBFeedKind.eventJoin:
        return null;
      case LBFeedKind.productSale:
        return null;
    }
  }

  /// Reset the whole feed history (e.g. on video reload / `VIDEO_SWITCH`). Also
  /// resets the de-dup window so a new session can re-show same-text activity. Fires
  /// one change notification so a bound host re-reads the now-empty [items] (D1).
  void clear() {
    _items.clear();
    _recentSignatures.clear();
    notifyListeners();
  }
}

/// Trim a merged feed by SEPARATE per-type retention: chat rows (`kind == LBFeedKind.chat`) keep
/// up to [chatCap]; all other rows (activity / eventJoin / productSale — the "activity bucket")
/// keep up to [activityCap]. The two buckets are trimmed INDEPENDENTLY — evicting the oldest of one
/// type NEVER affects the other's count — so real chat is never evicted by an activity flood
/// (the core separate-retention guarantee). Survivors keep their original chronological interleaved
/// order (newest at the tail). O(n), stable, no sort. Pure function → unit-testable.
///
/// Bucket parity (4-platform finale, zero divergence): chat bucket == iOS `.chat` / Android
/// `FeedItem.Chat` / RN `kind === 'chat'` (incl. `onSystemNotice` → `LBFeedItem.chat('', text)`);
/// activity bucket == iOS `.activity`/`.eventJoin`/`.productSale`, and the Android / RN equivalents.
@visibleForTesting
List<LBFeedItem> trimmedByType(List<LBFeedItem> items, int chatCap, int activityCap) {
  var chatCount = 0;
  var activityCount = 0;
  for (final it in items) {
    if (it.kind == LBFeedKind.chat) {
      chatCount++;
    } else {
      activityCount++;
    }
  }
  var chatToDrop = chatCount - chatCap;
  if (chatToDrop < 0) chatToDrop = 0;
  var activityToDrop = activityCount - activityCap;
  if (activityToDrop < 0) activityToDrop = 0;

  // Fast path: both buckets within cap → nothing to trim, return the input unchanged.
  if (chatToDrop == 0 && activityToDrop == 0) return items;

  // Walk oldest → newest; drop the oldest of a bucket while it still has a quota to drop.
  final result = <LBFeedItem>[];
  for (final it in items) {
    if (it.kind == LBFeedKind.chat) {
      if (chatToDrop > 0) {
        chatToDrop--;
        continue;
      }
    } else {
      if (activityToDrop > 0) {
        activityToDrop--;
        continue;
      }
    }
    result.add(it);
  }
  return result;
}
