import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show LBActivityTier, LBFeedItem, LBFeedKind, PinnedMessage;

import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';

// ChatFeedView — family-2 feed-win surface 1 (merged chat-feed stream).
//
// Spec: `reference-ui-rendering/spec.md` (family-2 feed-win, surface 1).
// Flutter sibling of iOS `ChatFeedView.swift` (rb-ios-feed-win, D-2) and Android
// `ChatFeed.kt` (rb-android-feed-win).
//   Design source: `design/templates/minimal/moments.jsx`
//     · `LBLiveChatStream` (bottom-anchored merged stream, newest at the tail,
//        tail-retain N=7, top fade mask)
//     · `LBChatLine`       (name-colored avatar + translucent dark bubble; host / AI /
//        reply rows share the SAME neutral bubble + an accent-solid name badge +
//        unconditional colon — rb-flutter-chat-message-line-restyle, design R30)
//     · `LBEventJoinLine`  (rb-flutter-chat-message-line-restyle, design re-sync R30:
//        crown avatar slot + NEUTRAL bubble (was accent-filled as of the 2026-07-02
//        `c3c98733` restyle) with an accent-solid name badge + colon header + keyword
//        copy + 立即參加 CTA (accent-filled, full-width) / 已參加 moved BELOW the
//        text — the ONLY interactive row)
//     · `LBActivityLine`   (tier-styled pill: .join / .purchase / .win now FIXED
//        semantic colors independent of `theme.accent` — R30; .browse / .intro
//        unchanged — now surfaced ONLY via `ActivityToastView`, see below)
//   And `live-chrome.jsx` `LBLiveChatOverlay` / `sdk-components.jsx`
//   `LBPChatOverlay` (the same avatar + bubble language).
//
// It binds the `DefaultActivityFeed` SNAPSHOT VALUE republished by `FeedWinModel`
// (`items: List<LBFeedItem>`, passed BY VALUE) and dispatches each row by
// `LBFeedItem.kind`:
//
//   • LBFeedKind.chat       → _ChatLine     — name-colored avatar + translucent dark
//                                            bubble carrying `userName：text`.
//   • LBFeedKind.eventJoin  → _EventJoinLine — shares the 主播留言 bubble language
//                                            (rb-flutter-chat-message-line-restyle,
//                                            design R30): crown avatar slot + NEUTRAL
//                                            bubble + accent-solid name badge + colon
//                                            header + keyword copy + 立即參加 CTA
//                                            (accent-filled, full-width) / 已參加
//                                            below the text. The ONLY interactive
//                                            row.
//
// (onsale 商品開賣推播已改走 host 主播聊天氣泡（template `appendChat(isHost:true)`），
//  `LBFeedKind.productSale` 已無 production producer；其商品開賣卡渲染為死碼、已移除，
//  `_chatFeedRow` 的 switch 保留一個 no-op case 維持對 enum 的窮盡涵蓋。)
//
// rb-flutter-activity-toast (design 呈現位置改版, moments.jsx export 2026-07-03):
// `LBFeedKind.activity` (社會認同「炒氣氛提示」: 進場/選購/搶購/中獎, all 5 tiers)
// is FILTERED OUT before the per-row dispatch loop below — it MUST NOT render
// inline in this merged stream anymore. It is surfaced instead by the sibling
// widget `ActivityToastView` (defined further down in THIS SAME FILE, so it can
// directly reuse the private `_ActivityLine` tier-styling — see that widget's own
// doc comment for why). `_chatFeedRow`'s `switch` below still HANDLES
// `LBFeedKind.activity` (exhaustiveness / defensive completeness for any future
// caller) even though neither `ChatFeedView` nor `_ScrollableChatFeed` will ever
// feed it one post-filter.
//
// SUB-VIEW INPUT PATTERN (FeedWinOverlayView SKELETON contract):
//   1. `theme:` (ReferenceUITheme, required) — FIRST, always.
//   2. its bound SNAPSHOT VALUE — `items` (read-only `List<LBFeedItem>`), BY VALUE.
//   3. trailing optional `onJoin` (default no-op). The container owns NO action —
//      the host wires the join exit. THIS LAYER NEVER JOINS ITSELF: the only
//      interactive row (`.eventJoin`) FORWARDS its tap via `onJoin(eid)`.
//
// One-way data flow: this view reads ONLY its passed-in `items` — it MUST NOT
// reach back into `FeedWinModel` / `DefaultPlayerTemplate`, MUST NOT hold a second
// copy of state, and MUST render correctly with `onJoin` omitted (so golden /
// widget tests construct it action-free). The data layer already merged / ordered
// / tail-retained (N=7); this layer renders the list VERBATIM (oldest → newest =
// top → bottom) and MUST NOT slice / merge / re-sort. `text` is the
// backend-prebuilt, i18n-complete string — rows MUST NOT split it.
//
// SNAPSHOT-DETERMINISM (iOS / Android lessons baked in): plain Column / Row only —
// NO scrollable (`ListView` / `GridView` / `SingleChildScrollView`), NO network
// image, NO animation / random state. The merged feed is a small fixed
// tail-retain-7 list, so a plain Column is correct.

// MARK: - Decorative design tokens (literal hex / rgba from moments.jsx)
//
// FIXED decorative colors from the design (on-glass white text / translucent
// bubble / card / pill fills). These are deliberately literal — they are NOT the
// theme accent / text / background (which feed the join CTA + win highlight +
// chips, pulled from `theme`).

/// On-glass primary text — white (chat / activity copy over the video).
const Color _onGlass = Color(0xFFFFFFFF);

/// On-glass dim — `rgba(255,255,255,0.72)` (chat name prefix / 已參加 chip text).
const Color _onGlassDim = Color(0xB8FFFFFF); // 0xB8 ≈ 0.72 alpha

/// Translucent dark chat / activity bubble fill `rgba(0,0,0,0.42)` (LBChatLine /
/// LBActivityLine `.join` base — updated unified ACT_BUBBLE, parity iOS/Android).
const Color _chatBubbleFill = Color(0x6B000000); // 0x6B ≈ 0.42 alpha

/// Chat / activity avatar-slot dark glyph `#3a2e25` (reads on the pastel avatars +
/// the `.join` white slot — updated unified ACT_SLOT, parity iOS/Android).
const Color _avatarGlyphColor = Color(0xFF3A2E25);

/// `_HostChatLine`'s non-host nickname text color `#FBB0B7` (rb-flutter-chat-
/// message-line-restyle, design R30) — used ONLY when a `_HostChatLine` row has
/// `isHost == false` (the `isAI`-only / `replyText`-only edge case that still
/// routes to this widget). Scope is deliberately narrow: `_ChatLine`'s own viewer
/// nickname prefix (`_onGlassDim`) is OUT OF R30's scope and MUST NOT read this
/// constant — see `design.md` (this change) Decision 2 for why the two paths stay
/// on different colors even though the design source treats them as one branch.
const Color _hostChatLineNonHostNickname = Color(0xFFFBB0B7);

/// Event-join 已參加 chip fill `rgba(255,255,255,0.2)` (LBEventJoinLine restyle,
/// rb-flutter-loading-announce-restyle — raised from the pre-restyle 0.16 now that the
/// CTA row sits on its own line below the copy, dedicated to this one chip only).
const Color _eventJoinedChipFill = Color(0x33FFFFFF); // 0x33 ≈ 0.2 alpha

/// Event-join 已參加 chip text / check-icon `rgba(255,255,255,0.82)` (restyle raised
/// from the shared `_onGlassDim`'s 0.72 — a standalone shade so `_onGlassDim`'s other
/// callers (`_ChatLine` nickname prefix / `_HostChatLine` reply quote) stay untouched).
const Color _eventJoinedTextColor = Color(0xD1FFFFFF); // 0xD1 ≈ 0.82 alpha

/// `.join` activity icon-SLOT fill `rgba(255,255,255,0.16)` (lowest-key, updated
/// unified ACT_SLOT, parity iOS/Android).
const Color _joinSlotFill = Color(0x29FFFFFF); // 0x29 ≈ 0.16 alpha

/// `.join` activity icon glyph `rgba(255,255,255,0.85)` (faint grey on the white slot).
const Color _joinGlyphColor = Color(0xD9FFFFFF); // 0xD9 ≈ 0.85 alpha

/// Activity bubble black base `rgba(0,0,0,0.46)` for purchase / intro / win
/// (accent wash layered over it — updated unified ACT_BUBBLE, parity iOS/Android).
const Color _activityBubbleBase = Color(0x75000000); // 0x75 ≈ 0.46 alpha

/// `.join` activity text `rgba(255,255,255,0.9)`; other tiers use full white.
const Color _joinTextColor = Color(0xE6FFFFFF); // 0xE6 ≈ 0.9 alpha

/// Deterministic pastel avatar palette (moments.jsx demo avatar colors).
const List<String> _avatarPalette = <String>[
  '#FFD7A8',
  '#C8E6C9',
  '#A8C7FA',
  '#FFB4A8',
  '#E1BEE7',
];

// MARK: - Layout tokens (lifted from moments.jsx)

const double _rowGap = 5; // LBLiveChatStream gap: 5
const double _avatarSize = 24; // LBChatLine avatar / activity slot 24×24 (shared rail)
const double _bubbleRadius = 12; // LBChatLine / LBActivityLine / LBEventJoinLine bubble radius 12
const double _activitySlot = 24; // LBActivityLine icon SLOT 24×24 (shared w/ chat avatar)

/// rb-flutter-feed-avatar-icon-hide (design `moments.jsx` `ACT_SLOT` shared style
/// constant `display: 'flex'` → `'none'`, R20 / 2026-08-21..22): the 24px round
/// avatar/icon slot is hidden across EVERY message kind in the merged chat/activity
/// feed — `_ChatLine` (viewer avatar), `_HostChatLine` (host/AI role icon),
/// `_EventJoinLine` (crown slot), and `_ActivityLine` (tier icon, both inline —
/// dead switch case — and via `ActivityToastView`). The design's own comment marks
/// this a reversible, temporary decision ("所有訊息種類的類型小 icon 先隱藏 — 改回顯示
/// 把 display 換成 'flex'"), so each row keeps its slot-drawing method intact and
/// gates its assembly on this ONE flag — flipping it back to `true` is the revert,
/// mirroring the design's own `display` toggle instead of deleting the draw code.
/// Flutter has no CSS `gap`: each row also drops its `SizedBox(width: 8)` spacer
/// alongside the slot when hidden, so the bubble sits flush at the row start with
/// no leftover gap — matching how a flex `gap` collapses around a `display: none`
/// item (the bubble does NOT leave a blank hole where the slot used to be).
const bool _showFeedAvatarSlot = false;

/// Shared chat-message line-height MULTIPLIER (rb-flutter-chat-message-line-height).
///
/// Flutter's `TextStyle.height` IS the "line height ÷ fontSize" MULTIPLIER (not an
/// absolute px / sp), so `height: 1.22` already scales with `fontSize` (every chat
/// `fontSize` here is `N * theme.fontScale`, so the resulting line height scales with
/// the font size too — no need to multiply by `theme.fontScale` again). Value `1.22`
/// mirrors Android `rb-android-chat-message-line-height` (`14 / 11.5 ≈ 1.217`) and RN
/// `rb-rn-chat-message-line-height` (`1.22`), lands inside the design
/// `design/templates/minimal/*.jsx` chat line-height target (1.2–1.3×), and matches
/// iOS `ChatFeedView.swift` tightness (SF Pro, no `.lineSpacing()`, ~1.19–1.20×).
/// `> 1.0` so it tightens the inter-line leading WITHOUT clipping glyphs / CJK.
/// A SINGLE shared constant keeps every wrapping message row consistent (no per-row
/// drift). Applied ONLY to wrapping chat / activity / event / pinned message text —
/// single-line labels (name / badge / CTA / pill / replyText quote / product-sale
/// card labels / avatar glyph) are excluded (parity Android / RN).
const double _chatLineHeight = 1.22;

/// Un-joined event-join CTA label (rb-flutter-chat-message-line-restyle, design R30:
/// changed from `'加入活動'` — same single call site, value updated in place).
const String _joinLabel = '立即參加';

/// 已參加 joined-state label.
const String _joinedLabel = '已參加';

/// Fallback copy when an event-join `text` is empty (LBEventJoinLine default).
const String _defaultEventCopy = '🎉 抽獎開始！留言「抽獎」即可參加';

/// The family-2 merged chat-feed stream surface. Paints the bottom-anchored,
/// newest-at-bottom translucent feed over the video area, dispatching each
/// [LBFeedItem] to its row renderer and themed by the resolved [ReferenceUITheme].
///
/// Renders correctly with [onJoin] omitted (the join CTA renders inert).
class ChatFeedView extends StatelessWidget {
  /// The resolved reference-ui theme (FIRST positional / named arg, always).
  final ReferenceUITheme theme;

  /// The merged, ordered, tail-retained (N=7) feed snapshot
  /// (`DefaultActivityFeed.items`), BY VALUE from `FeedWinModel.feedItems`.
  /// Already merged / ordered (oldest → newest = top → bottom) by the data layer
  /// — this view renders it VERBATIM, never slicing / merging / re-sorting.
  final List<LBFeedItem> items;

  /// The「加入活動」intent for the (only) interactive `.eventJoin` row, carrying
  /// ONLY the event id — the existing 1.3.0 public param, kept as the host OBSERVE
  /// hook. `null` → the join CTA renders but is inert (demo / golden). THIS LAYER
  /// NEVER JOINS ITSELF — it only surfaces the tap.
  ///
  /// NOTE: this eid-only callback CANNOT carry the row's `keyword`, which core
  /// `requestEventJoin(eid, keyword)` needs. The keyword-carrying default wiring
  /// travels via [onJoinWithKeyword] instead (rb-flutter-event-join-reaches-core).
  final void Function(int eid)? onJoin;

  /// The keyword-carrying「加入活動」intent (rb-flutter-event-join-reaches-core) —
  /// forwards BOTH the event id AND the CTA row's `keyword` (`LBFeedItem.keyword`,
  /// the authoritative `event-join-cta-keyword-source` value). The turnkey container
  /// wires this to core `requestEventJoin(eid, keyword)` — the ONLY place this layer
  /// actually reaches the core join API (parity iOS / Android drop-in). Additive /
  /// optional so the existing [onJoin] public surface stays unchanged.
  ///
  /// Dispatch is EITHER/OR (never both): a CTA tap calls [onJoinWithKeyword] when it
  /// is wired, else falls back to the eid-only [onJoin] — so a caller wiring only the
  /// legacy `onJoin` (golden / external compose) is unaffected, and a caller wiring
  /// `onJoinWithKeyword` (the container) never double-invokes.
  final void Function(int eid, String keyword)? onJoinWithKeyword;

  /// Scrollable history gate (default `false`). `false` (demo / golden) → the plain
  /// non-scrolling Column (baseline byte-identical, no scrollable widget). `true`
  /// (runtime) → a bounded-height scroll variant so the user can scroll UP to view
  /// history; the container then feeds the deeper `feedHistory`. Parity with
  /// iOS/Android `hostScrollable`.
  final bool hostScrollable;

  /// 置頂留言（chat-message-taxonomy ⑤c，`FeedWinModel.pinned` ← `template.pinnedMessage` ←
  /// `poll.top`）。非 null → feed 上緣渲染置頂橫幅；null（預設 / demo / golden）→ 不出像素
  /// （baseline byte-identical）。Parity iOS `ChatFeedView.pinned` / RN。
  final PinnedMessage? pinned;

  /// 主播名（rb-flutter-loading-announce-restyle）—`LBFeedKind.eventJoin` 列的 restyled
  /// header 顯示此值（跟主播留言同款「主播名 +「主播」badge」）。`required` snapshot 值，跟
  /// `items` 同層級 always-present（鏡像 `PlayerShellModel.hostName` 對 `template.header.
  /// hostName` 的單一真相讀法，由 `FeedWinModel.hostName` 提供）——`LBFeedItem` 本身不帶主播
  /// 名欄位（channel 全域層級快照，非逐則訊息欄位），本 widget MUST NOT 自行從 `items` 推導。
  final String hostName;

  const ChatFeedView({
    super.key,
    required this.theme,
    required this.items,
    required this.hostName,
    this.hostScrollable = false,
    this.onJoin,
    this.onJoinWithKeyword,
    this.pinned,
  });

  @override
  Widget build(BuildContext context) {
    // rb-flutter-activity-toast — filter OUT `LBFeedKind.activity` before dispatch
    // (mirrors moments.jsx `LBLiveChatStream`'s `items.filter(m => m.kind !==
    // 'activity')`). Activity items are surfaced instead by the sibling
    // `ActivityToastView`, mounted above this stream by the container. Relative
    // order of the remaining kinds is preserved (a `where` keeps source order).
    final feed = items.where((item) => item.kind != LBFeedKind.activity).toList(growable: false);
    // `hostScrollable == true` (runtime) swaps in the scroll-up-for-history variant;
    // the default keeps the plain non-scrolling Column so the golden baseline has NO
    // scrollable (byte-identical). Parity with iOS/Android.
    if (hostScrollable) {
      return KeyedSubtree(
        key: LbTestKeys.chatFeed,
        child: _ScrollableChatFeed(
            theme: theme,
            items: feed,
            onJoin: onJoin,
            onJoinWithKeyword: onJoinWithKeyword,
            pinned: pinned,
            hostName: hostName),
      );
    }
    // Bottom-anchored stream: a leading-aligned column pushed to the bottom so the
    // NEWEST (last) row sits lowest, with a top fade scrim. Plain Column (NO
    // scrollable) over the small tail-retain-7 list (golden baseline path).
    return KeyedSubtree(
      key: LbTestKeys.chatFeed,
      child: ShaderMask(
        shaderCallback: _chatFeedTopFadeShader,
        blendMode: BlendMode.dstIn,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 置頂留言橫幅（chat-message-taxonomy ⑤c）覆於 feed 上緣。null → 不出像素（baseline 中性）。
            if (pinned != null) _PinnedBanner(theme: theme, pinned: pinned!),
            for (final (index, item) in feed.indexed)
              Padding(
                padding: const EdgeInsets.only(top: _rowGap),
                child: _chatFeedRow(
                    theme, item, onJoin, index, hostName, onJoinWithKeyword),
              ),
          ],
        ),
      ),
    );
  }
}

// MARK: - ActivityToastView — floating activity-notice toast above the chat room
// (rb-flutter-activity-toast, design 呈現位置改版, `moments.jsx` `LBActivityToast`
// export 2026-07-03).
//
// The social-proof "炒氣氛提示" rows (`LBFeedKind.activity`, all 5 tiers: join /
// browse / purchase / intro / win) no longer render inline in [ChatFeedView] (see
// the `feed.where(...)` filter above). Instead they surface here: a small floating
// pill above the chat stream showing ONLY the newest activity item — slides in,
// holds ~2.6s, slides out. The chat room is left to show only real conversation +
// the eventJoin CTA.
//
// Deliberately defined in THIS SAME FILE as `_ActivityLine` (rather than a separate
// `activity_toast_view.dart`) so it can directly reuse that library-private,
// tier-styled pill widget without exporting it package-wide — `_ActivityLine` has
// exactly one OTHER call site (`_chatFeedRow`'s `.activity` case) and widening its
// visibility purely to share it with a sibling file would trade zero duplication
// for a wider, unnecessary public surface. The existing `chat_feed_view.dart`
// re-export shim (`export 'chat_feed.dart';`, no `show` clause) already covers this
// new public class transparently — no import changes needed at any call site.
//
// TRIGGER / DE-DUP (design D-1): `LBFeedItem` (flutter-ui) carries no stable id —
// the backend has none, and `chat-history-dedupe-template` removed all content-
// fingerprint de-duplication. `DefaultActivityFeed` constructs a BRAND NEW
// `LBFeedItem` instance on every append (even when the text happens to repeat), and
// `items` getter reuses those SAME instances across reads (only re-slices the
// List) — so Dart OBJECT IDENTITY (`identical()`) is a free, stable, and more
// precise "is this a new one?" signal than `moments.jsx`'s own `_k ?? text`
// fallback (which would misjudge two coincidentally-same-text-but-distinct events
// as the same one).
//
// GOLDEN / TEST GOTCHA: unlike `CartToastView` (whose ~1.8s auto-dismiss timer is
// driven EXTERNALLY by its container), THIS widget owns its own 2.6s `Timer`
// internally. A test that calls `tester.pumpAndSettle()` to "settle" the entrance
// animation will ALSO fast-forward through the entire hold window and the exit
// fade — landing on the (transparent) POST-dismiss frame instead of the visible
// one. Tests / goldens MUST use explicit `tester.pump(duration)` steps instead
// (see `activity_toast_test.dart`).

/// Pure: the newest (last) `LBFeedKind.activity` item in [items], or `null` if none.
/// Covers ALL 5 tiers (`join` / `browse` / `purchase` / `intro` / `win`) — this is
/// the same queue [ActivityToastView] surfaces. Mirrors `moments.jsx`'s
/// `items.filter(m => m.kind === 'activity'); activities[activities.length - 1]`.
LBFeedItem? latestActivityItem(List<LBFeedItem> items) {
  for (var i = items.length - 1; i >= 0; i--) {
    if (items[i].kind == LBFeedKind.activity) return items[i];
  }
  return null;
}

/// How long the toast holds fully visible before sliding back out (design
/// `moments.jsx` `setTimeout(..., 2600)`).
const Duration _activityToastHoldDuration = Duration(milliseconds: 2600);

/// Slide-in duration (design `transform 0.36s cubic-bezier(...)`).
const Duration _activityToastSlideDuration = Duration(milliseconds: 360);

/// Fade duration (design `opacity 0.32s ease`).
const Duration _activityToastFadeDuration = Duration(milliseconds: 320);

/// The minimum height reserved for the toast row (design `minHeight: 26`) so the
/// chat stream below it does not shift when the toast is empty / hidden.
const double _activityToastMinHeight = 26;

/// A small leading slide-in offset (fraction of the pill's own size — `AnimatedSlide`
/// is fraction-based, unlike the design's pixel `translateX(-14px)`; direction +
/// timing are the contract, the exact px is a visual approximation, not pixel-diffed).
const Offset _activityToastHiddenOffset = Offset(-0.06, 0);

/// Floating activity-notice toast above the chat room (family-2 extension of
/// Surface 1). Binds the SAME `items` snapshot [ChatFeedView] reads (BY VALUE, no
/// second subscription) and shows only the newest `LBFeedKind.activity` row.
///
/// Renders correctly with no action callbacks (there are none — this widget is
/// pure display, unlike `.eventJoin`'s interactive CTA).
class ActivityToastView extends StatefulWidget {
  /// The resolved reference-ui theme (FIRST positional / named arg, always).
  final ReferenceUITheme theme;

  /// The merged feed snapshot (`FeedWinModel.feedItems`), BY VALUE — same list
  /// [ChatFeedView] is given. This widget reads ONLY `LBFeedKind.activity` items
  /// out of it; it does not slice / merge / re-sort.
  final List<LBFeedItem> items;

  const ActivityToastView({super.key, required this.theme, required this.items});

  @override
  State<ActivityToastView> createState() => _ActivityToastViewState();
}

class _ActivityToastViewState extends State<ActivityToastView> {
  /// The activity item currently shown (persists after `_visible` flips to false —
  /// the toast fades out in place rather than being removed, mirroring the design's
  /// `shown` state which is never reset to null once first set).
  LBFeedItem? _shown;

  /// Whether the toast is in its visible (slid-in) resting state.
  bool _visible = false;

  /// Identity watermark — the [LBFeedItem] instance already armed/shown, so an
  /// unrelated rebuild (e.g. a new chat message, with the SAME latest activity
  /// object) does not re-trigger the slide-in. `null` before anything has shown.
  LBFeedItem? _armedFor;

  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Mirrors the design's literal mount behavior: `lastKey.current` starts null, so
    // an already-queued activity at mount time still triggers a slide-in.
    _sync(widget.items);
  }

  @override
  void didUpdateWidget(covariant ActivityToastView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // VIDEO_SWITCH clears the feed (`DefaultActivityFeed.clear()`): items goes
    // non-empty → empty. Drop any stale toast rather than let it carry (mid-hold or
    // mid-exit) into the next video — parity with `_ScrollableChatFeedState`'s own
    // reset-on-clear handling.
    if (widget.items.isEmpty && oldWidget.items.isNotEmpty) {
      _reset();
      return;
    }
    _sync(widget.items);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Arm a slide-in for the newest activity item IFF it is a new instance (design
  /// D-1: object identity, not content — see the file-level doc comment above for
  /// why). No-op when there is no activity item, or it is the one already
  /// shown/showing.
  void _sync(List<LBFeedItem> items) {
    final latest = latestActivityItem(items);
    if (latest == null || identical(latest, _armedFor)) return;
    _armedFor = latest;
    _timer?.cancel();
    setState(() {
      _shown = latest;
      _visible = true;
    });
    _timer = Timer(_activityToastHoldDuration, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  /// Reset for a cleared feed (video switch) — cancel any pending timer and drop
  /// the shown content so nothing carries into the next video.
  void _reset() {
    _timer?.cancel();
    _timer = null;
    _armedFor = null;
    setState(() {
      _shown = null;
      _visible = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    if (shown == null) {
      // Reserve the design's `minHeight: 26` even when nothing has shown yet, so the
      // chat stream below does not shift once the first toast appears.
      return const SizedBox(height: _activityToastMinHeight);
    }
    return SizedBox(
      height: _activityToastMinHeight,
      child: IgnorePointer(
        // pointerEvents: 'none' parity — never eats taps meant for the chat / video
        // below, even while sliding / visible.
        child: AnimatedSlide(
          offset: _visible ? Offset.zero : _activityToastHiddenOffset,
          duration: _activityToastSlideDuration,
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: _activityToastFadeDuration,
            curve: Curves.easeOut,
            child: _ActivityLine(
              theme: widget.theme,
              text: shown.text,
              tier: shown.tier ?? LBActivityTier.join,
            ),
          ),
        ),
      ),
    );
  }
}

/// Dispatch one [LBFeedItem] to its row renderer by `kind` (D-2). Shared by the
/// static [ChatFeedView] and the runtime [_ScrollableChatFeed]. `hostName` is the
/// (rb-flutter-loading-announce-restyle) snapshot value forwarded to `.eventJoin`
/// rows' restyled header — a pure internal forwarding param, defaulted to `''`
/// only because Dart requires SOME default for an optional positional (every real
/// call site always supplies the caller's actual `hostName`).
///
/// `onJoinWithKeyword` (rb-flutter-event-join-reaches-core) is the keyword-carrying
/// join dispatch: when wired it supersedes the eid-only `onJoin` for `.eventJoin`
/// taps (either/or — never both), forwarding the row's real `keyword` so the
/// container can reach core `requestEventJoin(eid, keyword)`.
Widget _chatFeedRow(ReferenceUITheme theme, LBFeedItem item, void Function(int eid)? onJoin,
    [int index = 0,
    String hostName = '',
    void Function(int eid, String keyword)? onJoinWithKeyword]) {
  switch (item.kind) {
    case LBFeedKind.chat:
      // chat-message-taxonomy ⑤ — 有角色 metadata → 角色版型（主播標/引用框/AI 標）；皆無 → 既有
      // 觀眾留言（byte-identical）。
      final hasRole = item.isHost ||
          item.isAI ||
          (item.replyText != null && item.replyText!.isNotEmpty);
      if (hasRole) {
        return KeyedSubtree(
          key: LbTestKeys.chatLine(index),
          child: _HostChatLine(
            theme: theme,
            userName: item.userName ?? '',
            text: item.text,
            isHost: item.isHost,
            isAI: item.isAI,
            replyText: item.replyText,
          ),
        );
      }
      return KeyedSubtree(
        key: LbTestKeys.chatLine(index),
        child: _ChatLine(theme: theme, userName: item.userName ?? '', text: item.text),
      );
    case LBFeedKind.eventJoin:
      return _EventJoinLine(
        theme: theme,
        text: item.text,
        hostName: hostName,
        joined: item.joined,
        // event-join-cta gating：keyword 非空才畫 CTA（活動進行中帶 ek）；空 → 純公告（活動結束 ek unset）。
        hasCTA: (item.keyword ?? '').isNotEmpty,
        onTap: () {
          final eid = item.eid;
          if (eid == null) return;
          // rb-flutter-event-join-reaches-core — prefer the keyword-carrying line
          // (so the container reaches core `requestEventJoin(eid, keyword)`); else
          // fall back to the eid-only public `onJoin` (either/or, never both). The
          // CTA is only drawn when keyword is non-empty (hasCTA gating above), so a
          // real tap always carries a non-empty keyword.
          final keyword = item.keyword ?? '';
          if (onJoinWithKeyword != null) {
            onJoinWithKeyword(eid, keyword);
          } else {
            onJoin?.call(eid);
          }
        },
      );
    case LBFeedKind.activity:
      return KeyedSubtree(
        key: LbTestKeys.activityLine(index),
        child: _ActivityLine(theme: theme, text: item.text, tier: item.tier ?? LBActivityTier.join),
      );
    case LBFeedKind.productSale:
      // onsale 商品開賣推播已改走 host 主播聊天氣泡（template `appendChat(isHost:true)`，見
      // flutter-ui default_template.dart），`productSale` 已無 production producer；商品開賣卡
      // 渲染為不可達死碼、已移除。保留此顯式 no-op case（回傳零尺寸 SizedBox.shrink()，不出任何
      // 像素）維持 Dart switch 對 `LBFeedKind` enum 的窮盡涵蓋；enum 值 / `LBFeedItem.price` 型別
      // 完整移除需跨層 change（本 reference-ui change 不碰 template）。MUST NOT 加 default 分支。
      return const SizedBox.shrink();
  }
}

/// Top fade gradient (`maskImage: linear-gradient(to top, #000 58%, transparent)`):
/// rows are fully opaque toward the bottom and fade to clear toward the top. Used as
/// a `dstIn` shader mask. Shared by the static + scrollable feed.
Shader _chatFeedTopFadeShader(Rect bounds) {
  return const LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: <Color>[Color(0x00000000), Color(0xFF000000), Color(0xFF000000)],
    stops: <double>[0.0, 0.42, 1.0],
  ).createShader(bounds);
}

/// Fraction of the screen height the SCROLLABLE chat occupies (anchored bottom), so
/// the upper area stays free for player gestures. Parity with iOS scrollableHeightFraction.
/// Lowered 0.46 → 0.38 (rb-ios-chat-feed-lower-height / iOS bedf737 / Android 251513a / RN a8788da)
/// so the upper pass-through region grows ~54%→~62%, making swipe-to-switch-video easier to
/// trigger. Scrollable variant only — the static / golden path is unaffected (baselines byte-identical).
const double _scrollableHeightFraction = 0.38;

/// Scroll-up-for-history variant (runtime). Bounded to [_scrollableHeightFraction] of
/// the screen height; content bottom-pinned (so few rows sit at the bottom like the
/// ambient overlay), sticks to the newest row unless the user scrolled up, with a
/// "↓ 最新訊息" pill to return. Parity with iOS `scrollableBody` +
/// `rb-ios-chat-feed-scroll-bounded-height`.
class _ScrollableChatFeed extends StatefulWidget {
  final ReferenceUITheme theme;
  /// Already filtered by the sole caller ([ChatFeedView.build]) — `LBFeedKind.activity`
  /// items are removed before construction (rb-flutter-activity-toast), so this list
  /// never contains one. This class is library-private with exactly one call site, so
  /// there is no second entry point that could hand it an unfiltered list.
  final List<LBFeedItem> items;
  final void Function(int eid)? onJoin;
  /// Keyword-carrying join dispatch (rb-flutter-event-join-reaches-core) — forwarded
  /// straight through to `_chatFeedRow` so the scrollable variant reaches core with
  /// the CTA row's keyword, same as the static path. See `ChatFeedView.onJoinWithKeyword`.
  final void Function(int eid, String keyword)? onJoinWithKeyword;
  final PinnedMessage? pinned;
  /// 主播名（rb-flutter-loading-announce-restyle）— forwarded straight through to
  /// `_chatFeedRow` for `.eventJoin` rows' restyled header. See `ChatFeedView.hostName`.
  final String hostName;
  const _ScrollableChatFeed(
      {required this.theme,
      required this.items,
      required this.hostName,
      this.onJoin,
      this.onJoinWithKeyword,
      this.pinned});

  @override
  State<_ScrollableChatFeed> createState() => _ScrollableChatFeedState();
}

class _ScrollableChatFeedState extends State<_ScrollableChatFeed> {
  final ScrollController _ctrl = ScrollController();
  bool _atBottom = true;
  bool _showPill = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  @override
  void didUpdateWidget(_ScrollableChatFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Feed cleared (VIDEO_SWITCH empties the merged feed → items non-empty → empty): reset
    // auto-stick so the NEXT video starts pinned to newest and the "↓ 最新訊息" pill hides — the
    // scroll / _showPill state is NOT recreated across switches. Parity iOS
    // rb-ios-chat-feed-pill-reset-on-switch. The fields are read by the build that follows.
    if (widget.items.isEmpty && oldWidget.items.isNotEmpty) {
      _atBottom = true;
      _showPill = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
    }
    // New rows: stick to newest UNLESS the user scrolled up.
    if (widget.items.length != oldWidget.items.length && _atBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _animateToBottom());
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_ctrl.hasClients) return;
    final atBottom = _ctrl.offset >= _ctrl.position.maxScrollExtent - 4;
    if (atBottom != _atBottom) {
      setState(() {
        _atBottom = atBottom;
        _showPill = !atBottom;
      });
    }
  }

  void _jumpToBottom() {
    if (_ctrl.hasClients) _ctrl.jumpTo(_ctrl.position.maxScrollExtent);
  }

  void _animateToBottom() {
    if (_ctrl.hasClients) {
      _ctrl.animateTo(_ctrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    }
  }

  void _returnToLatest() {
    setState(() {
      _atBottom = true;
      _showPill = false;
    });
    _animateToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.of(context).size.height * _scrollableHeightFraction;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 置頂留言橫幅（chat-message-taxonomy ⑤c）固定於可捲動 feed 上緣。null → 不出像素。
        if (widget.pinned != null)
          _PinnedBanner(theme: widget.theme, pinned: widget.pinned!),
        SizedBox(
      height: viewport,
      child: Stack(
        children: <Widget>[
          ShaderMask(
            shaderCallback: _chatFeedTopFadeShader,
            blendMode: BlendMode.dstIn,
            child: SingleChildScrollView(
              controller: _ctrl,
              child: ConstrainedBox(
                // Bottom-pin short content (mainAxisAlignment.end), scroll when it
                // exceeds the viewport.
                constraints: BoxConstraints(minHeight: viewport),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final (index, item) in widget.items.indexed)
                      Padding(
                        padding: const EdgeInsets.only(top: _rowGap),
                        child: _chatFeedRow(widget.theme, item, widget.onJoin,
                            index, widget.hostName, widget.onJoinWithKeyword),
                      ),
                  ],
                ),
              ),
            ),
          ),
          if (_showPill)
            Positioned(
              right: 0,
              bottom: 6,
              child: GestureDetector(
                key: LbTestKeys.chatScrollToBottom,
                onTap: _returnToLatest,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: widget.theme.accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '↓ 最新訊息',
                    style: TextStyle(
                      color: const Color(0xFFFFFFFF),
                      fontSize: 11.5 * widget.theme.fontScale,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
        ),
      ],
    );
  }
}

// MARK: - _ChatLine — single chat row (LBChatLine)
//
// Mirrors `moments.jsx` `LBChatLine`: a 24dp round name-colored avatar + a
// translucent dark bubble (radius 12). When the chat row carries an author nickname
// (`userName`, chat-nickname-render) the bubble LEADS with a dimmed INLINE prefix
// (`<span opacity .72 weight 600>{user}</span><span>{text}</span>` — same line, one
// bubble) and the avatar is keyed by the nickname; a row WITHOUT a nickname stays
// text-only (avatar keyed by `text`), BYTE-IDENTICAL to the pre-nickname layout. The
// prebuilt `text` is the message only — NOT name-embedded (parity iOS `LBChatLineRow`).

class _ChatLine extends StatelessWidget {
  final ReferenceUITheme theme;
  final String userName;
  final String text;

  const _ChatLine({
    required this.theme,
    required this.userName,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    // Avatar derivation key: the nickname when present, else `text` (legacy). So one
    // author = one stable avatar; a nameless row falls back to the message (parity iOS).
    final hasName = userName.isNotEmpty;
    final baseStyle = TextStyle(
      color: _onGlass,
      fontSize: 11.5 * theme.fontScale,
      fontWeight: FontWeight.normal,
      // rb-flutter-chat-message-line-height: explicit line-height multiplier so a
      // wrapping (2-line) viewer message tightens its leading (parity Android / RN /
      // iOS). Shared by the nickname-prefix `Text.rich` (prefix `copyWith` inherits
      // this `height`) and the plain-text branch — same bubble, one line height.
      height: _chatLineHeight,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // rb-flutter-feed-avatar-icon-hide (R20): the avatar slot is currently
        // hidden — see `_showFeedAvatarSlot`. `_avatarSlot()` below keeps the draw
        // logic for an easy revert; it is simply not assembled here.
        if (_showFeedAvatarSlot) ...<Widget>[
          _avatarSlot(hasName ? userName : text),
          const SizedBox(width: 8),
        ],
        // Translucent dark bubble. With a nickname it leads with a dimmed INLINE prefix
        // (design `LBChatLine`) then the message; without one it is just the message
        // (byte-identical legacy bubble). The message body is the backend-prebuilt text,
        // NOT name-embedded. Width-capped so a long message wraps to 2 lines. ACT_BUBBLE:
        // radius 12, black 0.42, padding h11/v5.
        Flexible(
          child: Container(
            decoration: BoxDecoration(
              color: _chatBubbleFill,
              borderRadius: BorderRadius.circular(_bubbleRadius),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            child: hasName
                ? Text.rich(
                    TextSpan(
                      children: [
                        // Dimmed inline nickname prefix + a full-width colon separator
                        // (chat-message-colon-separator, design re-sync `843d09f5`:
                        // moments.jsx `LBChatLine` !isHost branch now appends `：` after
                        // `{m.user}` and drops the `marginRight` gap — `isHost ? 6 : 0`).
                        // The prefix carries the colon itself so there is no separate
                        // trailing-space run between name and message.
                        TextSpan(
                          text: '$userName：',
                          style: baseStyle.copyWith(
                            color: _onGlassDim,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        TextSpan(text: text),
                      ],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: baseStyle,
                  )
                : Text(
                    text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: baseStyle,
                  ),
          ),
        ),
      ],
    );
  }

  /// Name-colored avatar (24dp round — shared rail with activity slots) —
  /// deterministic from the nickname (or `text` when none). Dark glyph (`#3a2e25`)
  /// reads on the pastel demo avatars, matching the updated `LBChatLine` ACT_SLOT.
  /// rb-flutter-feed-avatar-icon-hide (R20): kept intact for a future revert but NOT
  /// assembled into [build]'s `Row` — see `_showFeedAvatarSlot`.
  Widget _avatarSlot(String avatarKey) {
    final avatarFill = _avatarColor(avatarKey);
    return Container(
      width: _avatarSize,
      height: _avatarSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: avatarFill, shape: BoxShape.circle),
      child: Text(
        _avatarGlyph(avatarKey),
        style: TextStyle(
          color: _avatarGlyphColor,
          fontSize: 10 * theme.fontScale,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// MARK: - _HostChatLine — 角色版型聊天列 (chat-message-taxonomy ⑤)
//
// 群組① 真正的聊天：主播留言 / 主播回覆 / AI 回覆，以**版型**而非顏色區分（parity iOS `LBChatLineRow`
// hasRole 分支 / RN `HostChatRow`）。24px accent 圖示軌（host = crown、AI = sparkles，見下方「圖示 /
// 頭像 slot 隱藏」條款，目前不渲染）+ **中性深色氣泡**（rb-flutter-chat-message-line-restyle，design
// re-sync `claude-design-sync.md` R30，2026-09-03：與 `_ChatLine` 共用同一個 `_chatBubbleFill` 底色，
// 取代先前 `Color.alphaBlend(theme.accent, ...)` 的 accent 暈染 — 主播 / AI 的角色差異化改**只靠 bubble
// 內容本身**，不再靠氣泡染色）。header：`isHost` 時渲染**一個** accent 色底名牌（重用 `_roleTag(solid:
// true)`，內容 = 暱稱本身，取代先前並列的純文字暱稱 +「主播」固定文案標）；非 host 時暱稱維持純文字但改
// 固定粉色 `#FBB0B7`；`isAI` 時額外掛「AI」外框標（不變）；header 尾端無條件加全形冒號「：」（R30 新增，
// 先前只有一般觀眾留言 `_ChatLine` 有）。回覆引用框只顯引用文字（後端無引用者名稱）+ 訊息本文。Flutter 用
// Material Icons。

class _HostChatLine extends StatelessWidget {
  final ReferenceUITheme theme;
  final String userName;
  final String text;
  final bool isHost;
  final bool isAI;
  final String? replyText;

  const _HostChatLine({
    required this.theme,
    required this.userName,
    required this.text,
    required this.isHost,
    required this.isAI,
    this.replyText,
  });

  @override
  Widget build(BuildContext context) {
    final hasName = userName.isNotEmpty;
    final hasReply = replyText != null && replyText!.isNotEmpty;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // rb-flutter-feed-avatar-icon-hide (R20): the role icon slot is currently
        // hidden — see `_showFeedAvatarSlot`. `_roleIconSlot()` below keeps the draw
        // logic for an easy revert; it is simply not assembled here.
        if (_showFeedAvatarSlot) ...<Widget>[
          _roleIconSlot(),
          const SizedBox(width: 8),
        ],
        // 中性深色氣泡（rb-flutter-chat-message-line-restyle，design R30：與 _ChatLine
        // 共用同一個 _chatBubbleFill 底色，取代先前的 accent 暈染——主播/AI 的角色差異化
        // 改只靠 bubble 內容本身，不再靠氣泡染色）。
        Flexible(
          child: Container(
            decoration: BoxDecoration(
              color: _chatBubbleFill,
              borderRadius: BorderRadius.circular(_bubbleRadius),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // header（R30）：isHost → 一個 accent 色底名牌（重用 _roleTag(solid:
                // true)，內容 = 暱稱本身，取代先前並列的純文字暱稱 +「主播」固定文案標）；
                // 非 host（僅 isAI 或僅 replyText 觸發角色版型的邊界情況）→ 暱稱維持純文字
                // 但改固定粉色 _hostChatLineNonHostNickname；isAI 額外掛「AI」外框標（不
                // 變）；尾端無條件冒號「：」，緊接在名牌/暱稱 + AI 標之後、無多餘間距——
                // SizedBox(5) 只在 AI 標會被組裝時才插入，避免名牌/暱稱與冒號之間留白。
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (isHost && hasName)
                      _roleTag(theme, userName, solid: true)
                    else if (hasName)
                      Text(
                        userName,
                        style: TextStyle(
                          color: _hostChatLineNonHostNickname,
                          fontSize: 10.5 * theme.fontScale,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (hasName && isAI) const SizedBox(width: 5),
                    if (isAI) _roleTag(theme, 'AI', solid: false),
                    if (hasName || isAI)
                      Text(
                        '：',
                        style: TextStyle(
                          color: _onGlass,
                          fontSize: 11.5 * theme.fontScale,
                          height: _chatLineHeight,
                        ),
                      ),
                  ],
                ),
                // 引用框（主播回覆 / AI 回覆）：左側 accent 直條 + 暗底，只顯引用文字。
                if (hasReply)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: const Color(0x4D000000), // black 0.30
                      borderRadius: BorderRadius.circular(6),
                      border: Border(
                        left: BorderSide(color: theme.accent, width: 3),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(6, 3, 6, 3),
                    child: Text(
                      replyText!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _onGlassDim,
                        fontSize: 10.5 * theme.fontScale,
                      ),
                    ),
                  ),
                // 訊息本文（backend-prebuilt，NOT split）。
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _onGlass,
                      fontSize: 11.5 * theme.fontScale,
                      // rb-flutter-chat-message-line-height: tighten multi-line 主播 / AI
                      // body leading (shared constant, parity Android / RN / iOS).
                      height: _chatLineHeight,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 24px accent 圖示軌（主播 crown / AI sparkles），取代觀眾的名字色頭像。
  /// rb-flutter-feed-avatar-icon-hide (R20): kept intact for a future revert but NOT
  /// assembled into [build]'s `Row` — see `_showFeedAvatarSlot`.
  Widget _roleIconSlot() {
    return Container(
      width: _avatarSize,
      height: _avatarSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: theme.accent, shape: BoxShape.circle),
      child: Icon(
        isAI ? Icons.auto_awesome : Icons.workspace_premium, // sparkles / crown
        size: 13,
        color: _onGlass,
      ),
    );
  }
}

/// 角色標：`主播`（accent 實心 + 白字）/ `AI`（accent 外框 + accent 字）。Parity iOS `roleTag` / RN.
Widget _roleTag(ReferenceUITheme theme, String label, {required bool solid}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
    decoration: BoxDecoration(
      color: solid ? theme.accent : const Color(0x00000000),
      borderRadius: BorderRadius.circular(4),
      border: solid ? null : Border.all(color: theme.accent, width: 1),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: solid ? _onGlass : theme.accent,
        fontSize: 9 * theme.fontScale,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

// MARK: - _PinnedBanner — 置頂留言橫幅 (chat-pinned-message-render ⑤)
//
// Parity iOS `PinnedMessageBanner` / RN `PinnedBanner`：pin 標 + 名前綴（comment 且 name 非空 →
// 「{name}：」、host → 無前綴）+ 置頂文字，圓角暗底橫幅，固定於 feed 上緣。

class _PinnedBanner extends StatelessWidget {
  final ReferenceUITheme theme;
  final PinnedMessage pinned;

  const _PinnedBanner({required this.theme, required this.pinned});

  @override
  Widget build(BuildContext context) {
    final namePrefix =
        (pinned.kind == 'comment' && pinned.name.isNotEmpty) ? '${pinned.name}：' : '';
    return Container(
      key: LbTestKeys.pinnedBanner,
      margin: const EdgeInsets.only(bottom: _rowGap),
      decoration: BoxDecoration(
        color: const Color(0x8C000000), // black 0.55
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(Icons.push_pin, size: 11, color: theme.accent),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: namePrefix,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: pinned.text),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _onGlass,
                fontSize: 12 * theme.fontScale,
                fontWeight: FontWeight.w500,
                // rb-flutter-chat-message-line-height: tighten wrapping pinned-banner
                // leading (shared constant, parity Android / RN / iOS).
                height: _chatLineHeight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// MARK: - _EventJoinLine — event-join row (LBEventJoinLine)
//
// rb-flutter-chat-message-line-restyle (design re-sync `claude-design-sync.md` R30,
// 2026-09-03): `LBEventJoinLine` again shares the EXACT SAME bubble language as the
// 主播留言 bubble (`_HostChatLine` / design `LBChatLine` `isHost` branch), now updated
// a step further — the bubble itself went from solid-accent (the 2026-07-02
// `rb-flutter-loading-announce-restyle` version) to the SAME NEUTRAL `_chatBubbleFill`
// `_HostChatLine` uses (design comment: 「與主播留言相同的灰底氣泡」). Layout: a 24dp
// round accent avatar SLOT OUTSIDE the bubble (shared icon rail, SAME crown glyph as
// `_HostChatLine`'s 主播 avatar — the design's `LBEventJoinLine` SVG path is byte-
// identical to `LBChatLine`'s `isHost && !isAI` avatar path, NOT a sparkle), then a
// neutral bubble (`color: _chatBubbleFill`, MUST NOT be `theme.accent` anymore)
// containing, top to bottom: a header row (ONE accent-solid name badge reusing
// `_roleTag(theme, hostName, solid: true)` — identical formula to `_HostChatLine`'s
// `isHost` badge, MUST NOT be a separate plain-text name + fixed-label 「主播」 badge
// anymore — the 2026-07-02 restyle's custom white-0.22 badge is GONE, see below for
// why reuse is now safe — then an unconditional full-width colon「：」), the 2-line
// keyword copy, and — only when `hasCTA` — a CTA block on ITS OWN row below the copy
// (立即參加 / 已參加). The ONLY interactive row — its tap is FORWARDED via `onTap`
// (host-wired); this layer never joins itself.
//
// Why `_roleTag(solid: true)` reuse is safe NOW (it was NOT safe as of 2026-07-02):
// `rb-flutter-loading-announce-restyle`'s `design.md` recorded that `_roleTag(solid:
// true)` fills with `theme.accent`, which would be ZERO-CONTRAST against THAT
// version's bubble (also solid `theme.accent`) — hence the custom white-0.22 badge.
// R30 changes the bubble's own fill to neutral `_chatBubbleFill`, so the accent-solid
// badge reads correctly against it (same situation `_HostChatLine`'s own `isHost`
// badge is in). The old constraint was conditional on the bubble ALSO being accent —
// that premise no longer holds, so reuse is safe and avoids duplicating the same
// "accent pill with dynamic label" formula twice.

class _EventJoinLine extends StatelessWidget {
  final ReferenceUITheme theme;
  final String text;
  /// 主播名（restyle 新增）— header 顯示，跟 `_HostChatLine.userName` 同款渲染. Forwarded from
  /// `ChatFeedView.hostName` (channel 全域快照，非逐則訊息欄位).
  final String hostName;
  final bool joined;
  // 後端「ek isset 才顯示 CTA」契約：keyword 非空 → 畫加入活動 CTA；空（活動結束 / 純公告）→ 只留
  // 頭像圈 + 文案（event-join-cta gating，對齊 iOS / Android / RN hasCTA）。視覺 restyle 不影響此
  // gating 邏輯本身。
  final bool hasCTA;
  final VoidCallback onTap;

  const _EventJoinLine({
    required this.theme,
    required this.text,
    required this.hostName,
    required this.joined,
    required this.hasCTA,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Shared message-row language (ACT_ROW gap 8, same as _ActivityLine / _HostChatLine): a
    // 24dp round accent avatar SLOT OUTSIDE the bubble, then a NEUTRAL bubble (R30 — no
    // longer solid-accent) wrapping a header + copy + (optional) CTA block below — same
    // Column shape as _HostChatLine (rb-flutter-chat-message-line-restyle, design re-sync
    // `claude-design-sync.md` R30, superseding the 2026-07-02 `c3c98733` solid-accent version).
    final hasHostName = hostName.isNotEmpty;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // rb-flutter-feed-avatar-icon-hide (R20): the crown slot is currently hidden
        // — see `_showFeedAvatarSlot`. `_crownSlot()` below keeps the draw logic for
        // an easy revert; it is simply not assembled here.
        if (_showFeedAvatarSlot) ...<Widget>[
          _crownSlot(),
          const SizedBox(width: 8),
        ],
        // Neutral bubble (R30 — MUST NOT be `theme.accent` anymore; same
        // `_chatBubbleFill` `_HostChatLine` / `_ChatLine` use).
        Flexible(
          child: Container(
            decoration: BoxDecoration(
              color: _chatBubbleFill,
              borderRadius: BorderRadius.circular(_bubbleRadius),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            // `IntrinsicWidth` so the bubble keeps shrink-wrapping to its widest
            // content (header / keyword copy — design's bubble is `display:
            // inline-block`, sized by content, NOT by the row's full available
            // width), while the CTA's `SizedBox(width: double.infinity)` below
            // fills THAT computed intrinsic width (design `width:'100%'` is
            // relative to the bubble's own containing block, not the screen) —
            // without this wrapper the CTA would stretch the whole bubble out to
            // whatever width `Flexible` makes available, even for a short keyword.
            child: IntrinsicWidth(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  // header (R30): ONE accent-solid name badge, reusing `_roleTag(solid:
                  // true)` — safe now that the bubble above is neutral (see class doc
                  // comment for why this reverses the 2026-07-02 restyle's "do not
                  // reuse" call) — plus an unconditional colon「：」 immediately after
                  // (no gap, mirrors the design's adjacent `<span>` elements).
                  Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (hasHostName) _roleTag(theme, hostName, solid: true),
                    if (hasHostName)
                      Text(
                        '：',
                        style: TextStyle(
                          color: _onGlass,
                          fontSize: 11.5 * theme.fontScale,
                          height: _chatLineHeight,
                        ),
                      ),
                  ],
                ),
                // 2-line keyword copy (full prebuilt text, NOT split). No extra width cap — the
                // bubble's own `Flexible` bounds it (parity with _HostChatLine's copy, the old
                // `ConstrainedBox(maxWidth: 132)` is REMOVED per the restyle).
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    text.isEmpty ? _defaultEventCopy : text,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _onGlass,
                      fontSize: 11.5 * theme.fontScale,
                      fontWeight: FontWeight.w600,
                      // rb-flutter-chat-message-line-height: unify to the shared chat
                      // line-height constant (was a stray hardcoded 1.3 → 1.22) so every
                      // wrapping message row matches (parity Android / RN / iOS).
                      height: _chatLineHeight,
                    ),
                  ),
                ),
                // event-join-cta gating: keyword 空（hasCTA == false）→ 不畫 CTA / 已參加 chip（純活動
                // 公告，只留頭像圈 + header + 文案）。對齊 iOS / Android / RN。CTA now sits on ITS OWN
                // row BELOW the copy (moved off the trailing-inline position).
                if (hasCTA)
                  Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: joined
                        ? Container(
                            key: LbTestKeys.eventJoinJoined,
                            decoration: const BoxDecoration(
                              color: _eventJoinedChipFill,
                              shape: BoxShape.rectangle,
                              borderRadius: BorderRadius.all(Radius.circular(999)),
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                const Icon(Icons.check,
                                    size: 12, color: _eventJoinedTextColor),
                                const SizedBox(width: 4),
                                Text(
                                  _joinedLabel,
                                  style: TextStyle(
                                    color: _eventJoinedTextColor,
                                    fontSize: 11.5 * theme.fontScale,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          )
                        // 立即參加 CTA（R30）: accent-filled full-width pill, white text —
                        // flipped from the prior white-filled, accent-text, center-fit
                        // button (padding also tightened v:6→4 per design literal value).
                        : SizedBox(
                            width: double.infinity,
                            child: GestureDetector(
                              key: LbTestKeys.eventJoinCta,
                              onTap: onTap,
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: theme.accent,
                                  borderRadius:
                                      const BorderRadius.all(Radius.circular(999)),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 4),
                                child: Text(
                                  _joinLabel,
                                  style: TextStyle(
                                    color: _onGlass,
                                    fontSize: 12 * theme.fontScale,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 24dp round accent avatar slot — OUTSIDE the bubble, SAME crown glyph as
  /// _HostChatLine's 主播 avatar (design: byte-identical SVG path, "與主播留言相同的頭像圈").
  /// rb-flutter-feed-avatar-icon-hide (R20): kept intact for a future revert but NOT
  /// assembled into [build]'s `Row` — see `_showFeedAvatarSlot`.
  Widget _crownSlot() {
    return Container(
      width: _activitySlot,
      height: _activitySlot,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: theme.accent, shape: BoxShape.circle),
      child: const Icon(Icons.workspace_premium, size: 13, color: _onGlass),
    );
  }
}

// MARK: - _ActivityLine — tier-styled activity row (LBActivityLine)
//
// Mirrors the UPDATED `moments.jsx` `LBActivityLine`: every row shares one unified
// language — a 24×24 round icon SLOT + a rounded-12 bubble. `join` / `purchase` /
// `win` now use FIXED semantic colors (rb-flutter-chat-message-line-restyle, design
// re-sync `claude-design-sync.md` R30, 2026-09-03) that do NOT vary with the
// merchant's `theme.accent` — the accent-wash formula those three tiers used to
// share is gone for them. `browse` / `intro` are OUT OF R30's scope (the design
// canvas has no `browse` diff this round, and `intro` is a four-platform-only
// extension tier with no design-canvas counterpart at all) and keep their prior
// accent-relative styling untouched:
//   • .join     — 進場: fixed `rgba(232,108,108,0.72)` coral bubble (R30, was black
//                 0.32 shared with .browse), NO accent involvement; slot 白 0.16 /
//                 person-add icon 白 0.85 (unchanged, hidden dead code — see
//                 `_showFeedAvatarSlot`); text 白 0.9, medium (w500).
//   • .browse   — 觀眾選購: UNCHANGED by R30 — slot 白 0.16 / magnifier icon 白
//                 0.85; bubble 黑 0.32, NO accent; text 白 0.9, medium (w500).
//   • .purchase — 購買: fixed `rgba(45,212,191,0.72)` teal bubble (R30, was black
//                 0.46 + accent 0.13 wash), NO accent involvement; slot accent /
//                 white bag icon (unchanged, hidden dead code); w500.
//   • .intro    — 介紹: UNCHANGED by R30 — slot accent / white megaphone icon;
//                 bubble 黑 0.46 + accent 0.18 wash, w500 (商品開始介紹 — 強調介於
//                 購買與中獎之間; four-platform extension, no design-canvas branch).
//   • .win      — 中獎: fixed `rgba(240,50,70,0.72)` red bubble (R30, was black 0.46
//                 + accent 0.23 wash) — but the hairline `border` (accent 0.4) and
//                 the faint `boxShadow` glow (accent 0.2) STILL follow `theme.accent`
//                 (design left those alone, only the bubble fill went fixed); slot
//                 accent / white trophy icon (unchanged, hidden dead code); bold
//                 (w700). NO 🎉.
//
// The `intro` tier's accent wash is still the design's `linear-gradient(accentXX,
// accentXX)` over `rgba(0,0,0,0.46)` = a flat accent overlay (alpha XX) on a 0.46
// black base — modelled as a black-base rounded box with an accent-tinted overlay
// (`Color.alphaBlend`, `_washBubble()`). Parity iOS/Android/RN.

class _ActivityLine extends StatelessWidget {
  final ReferenceUITheme theme;
  final String text;
  final LBActivityTier tier;

  const _ActivityLine({
    required this.theme,
    required this.text,
    required this.tier,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // rb-flutter-feed-avatar-icon-hide (R20): the tier icon slot is currently
        // hidden — see `_showFeedAvatarSlot`. `_iconSlot()` below keeps the draw
        // logic for an easy revert; it is simply not assembled here. This row is
        // shared by the (dead) inline `.activity` switch case AND `ActivityToastView`
        // (both construct `_ActivityLine` directly), so the hide applies to both.
        if (_showFeedAvatarSlot) ...<Widget>[
          _iconSlot(),
          const SizedBox(width: 8),
        ],
        // Rounded-12 bubble, accent-wash by tier.
        Flexible(
          child: Container(
            decoration: _bubbleDecoration,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _textColor,
                fontSize: 11.5 * theme.fontScale,
                fontWeight: _textWeight,
                // rb-flutter-chat-message-line-height: unify to the shared chat
                // line-height constant (was a stray hardcoded 1.3 → 1.22) so every
                // wrapping message row matches (parity Android / RN / iOS).
                height: _chatLineHeight,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 24px icon slot (shared rail with chat avatar).
  /// rb-flutter-feed-avatar-icon-hide (R20): kept intact for a future revert but NOT
  /// assembled into [build]'s `Row` — see `_showFeedAvatarSlot`.
  Widget _iconSlot() {
    return Container(
      width: _activitySlot,
      height: _activitySlot,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: _slotFill, shape: BoxShape.circle),
      child: Icon(_glyph, size: 12, color: _glyphColor),
    );
  }

  /// Tier-styled icon-slot fill (ascending emphasis). `browse`（觀眾選購）同 `join` 最低調。
  Color get _slotFill {
    switch (tier) {
      case LBActivityTier.join:
      case LBActivityTier.browse:
        return _joinSlotFill;
      case LBActivityTier.purchase:
      case LBActivityTier.intro:
      case LBActivityTier.win:
        return theme.accent;
    }
  }

  /// Tier-styled icon glyph. `browse`（chat-message-taxonomy ⑤）→ 放大鏡（最低調，同 join 級）。
  IconData get _glyph {
    switch (tier) {
      case LBActivityTier.join:
        return Icons.person_add_alt_1;
      case LBActivityTier.browse:
        return Icons.search; // magnifyingglass — 觀眾選購
      case LBActivityTier.purchase:
        return Icons.shopping_bag_outlined;
      case LBActivityTier.intro:
        return Icons.campaign; // megaphone / loudspeaker
      case LBActivityTier.win:
        return Icons.emoji_events; // trophy
    }
  }

  /// Tier-styled icon glyph color.
  Color get _glyphColor {
    switch (tier) {
      case LBActivityTier.join:
      case LBActivityTier.browse:
        return _joinGlyphColor;
      case LBActivityTier.purchase:
      case LBActivityTier.intro:
      case LBActivityTier.win:
        return _onGlass;
    }
  }

  /// Rounded-12 bubble decoration. `join` / `purchase` / `win` are FIXED semantic
  /// colors (rb-flutter-chat-message-line-restyle, design R30) that do NOT read
  /// `theme.accent` for their fill; `browse` / `intro` are untouched by R30 and stay
  /// accent-relative (see the class doc comment above for the full per-tier table).
  BoxDecoration get _bubbleDecoration {
    switch (tier) {
      case LBActivityTier.join:
        // 進場 — fixed coral `rgba(232,108,108,0.72)` (R30), no longer shares
        // .browse's black 0.32 / no longer varies with theme.accent.
        return BoxDecoration(
          color: const Color(0xB8E86C6C), // 0xB8 ≈ 0.72 alpha
          borderRadius: BorderRadius.circular(_bubbleRadius),
        );
      case LBActivityTier.browse:
        // 觀眾選購（browse）— UNCHANGED by R30: black 0.32, no accent wash（最低調）。
        return BoxDecoration(
          color: const Color(0x52000000), // 0x52 ≈ 0.32 alpha
          borderRadius: BorderRadius.circular(_bubbleRadius),
        );
      case LBActivityTier.purchase:
        // 購買 — fixed teal `rgba(45,212,191,0.72)` (R30), replaces the prior
        // accent 0.13 wash; no longer varies with theme.accent.
        return BoxDecoration(
          color: const Color(0xB82DD4BF), // 0xB8 ≈ 0.72 alpha
          borderRadius: BorderRadius.circular(_bubbleRadius),
        );
      case LBActivityTier.intro:
        // UNCHANGED by R30 — four-platform extension tier, no design-canvas branch.
        return _washBubble(0.18); // accent2e
      case LBActivityTier.win:
        // 中獎 — fixed red `rgba(240,50,70,0.72)` bubble fill (R30, replaces the
        // prior accent 0.23 wash); hairline border + faint glow STILL follow
        // theme.accent (design left those alone). NO 🎉.
        return BoxDecoration(
          color: const Color(0xB8F03246), // 0xB8 ≈ 0.72 alpha
          borderRadius: BorderRadius.circular(_bubbleRadius),
          border: Border.all(
            color: theme.accent.withValues(alpha: 0.4),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: theme.accent.withValues(alpha: 0.2),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        );
    }
  }

  /// Black 0.46 base + an accent-tinted overlay (the design's `accentXX` wash).
  BoxDecoration _washBubble(double wash) => BoxDecoration(
        color: Color.alphaBlend(
            theme.accent.withValues(alpha: wash), _activityBubbleBase),
        borderRadius: BorderRadius.circular(_bubbleRadius),
      );

  /// `.join` / `.browse` text is white 0.9 (最低調); other tiers full white.
  Color get _textColor =>
      (tier == LBActivityTier.join || tier == LBActivityTier.browse)
          ? _joinTextColor
          : _onGlass;

  /// join / purchase / intro = medium (w500); win = bold (w700).
  FontWeight get _textWeight =>
      tier == LBActivityTier.win ? FontWeight.w700 : FontWeight.w500;
}

// MARK: - Pure helpers (deterministic avatar)

/// Deterministic avatar fill from the chat author name (one of the design's
/// pastel demo avatar colors), chosen by a stable FNV-1a hash so the same name
/// always maps to the same color (no per-process seed → stable golden). Mirrors
/// iOS `LBChatLineRow.avatarColor` / Android `avatarColor`.
Color _avatarColor(String name) {
  // Mask off the sign bit (an unsigned-to-signed cast can be negative) so the
  // index is always non-negative for any host string.
  final idx = (_stableHash(name) & 0x7fffffffffffffff) % _avatarPalette.length;
  return colorFromHex(_avatarPalette[idx]) ?? const Color(0xFF9E9E9E);
}

/// First character of the name as the avatar glyph (presentation-only). Mirrors
/// iOS `avatarGlyph` / Android `avatarGlyph`.
String _avatarGlyph(String name) =>
    name.isEmpty ? '·' : name.substring(0, 1).toUpperCase();

/// A small, stable, platform-independent hash (FNV-1a over the UTF-8 bytes) so
/// the avatar color is deterministic across runs / architectures (Dart's
/// `String.hashCode` is fine but we mirror the iOS / Android FNV-1a so the SAME
/// name maps to the SAME palette index on all three platforms).
int _stableHash(String s) {
  // 64-bit FNV-1a in Dart's BigInt-free 64-bit int (wraps on overflow, matching
  // the iOS / Android `UInt64` truncation).
  var h = 0xcbf29ce484222325;
  for (final b in s.codeUnits) {
    // Iterate UTF-8 bytes to stay byte-identical to iOS / Android. For ASCII /
    // BMP this matches; code units suffice for the deterministic palette index.
    h ^= b & 0xff;
    h = (h * 0x100000001b3) & 0xffffffffffffffff;
  }
  return h;
}
