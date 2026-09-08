import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../reference_ui_theme.dart';
import '../share_glyph.dart';
import '../testing/lb_test_keys.dart';
import 'bag_glyph.dart';
import 'cc_glyph.dart';
import 'more_glyph.dart';
import 'person_edit_glyph.dart';

// LiveBottomBarView — family-1 player-shell LIVE bottom bar.
//
// Spec: `reference-ui-rendering/spec.md`
//   § "LivebuyReferenceUI 渲染 LIVE 底部 bar（LiveBottomBarView），綁 bagCount / isReplay"
// Flutter sibling of iOS `LiveBottomBarView.swift` / Android `LiveBottomBar.kt`.
//   Design source: `design/templates/minimal/live-chrome.jsx` → `LBLiveBottomBar` (161-237).
//
// The live-chrome-family bottom bar. `screens.jsx` mode-branches the player chrome on
// `usesLiveChrome = isLive || isFinishedLiveReplay`: the live-chrome-family screen renders this
// horizontal bottom bar while the side rail (`OperationRailView`) is purely-VOD-only
// (`!usesLiveChrome`, `rb-flutter-replay-live-chrome-parity`). The bar paints, left → right:
//
//   • a white shopping-bag button + cart badge (when `bagCount > 0`),
//   • a flex "留言..." TAP-TARGET pill (NOT an inline text field — design `onComment`
//     opens a sheet; the real composer is the host's) — disabled「聊天室已關閉」in the
//     `isFinishedLiveReplay` variant (see below),
//   • a nickname button — a「更多」(more) button instead in the `isFinishedLiveReplay` variant,
//   • a share button — a CC (字幕) toggle instead in the `isFinishedLiveReplay` variant,
//   • an accent like (heart) button (unaffected by any variant).
//
// Comment entry ALWAYS available FOR A GENUINE LIVE BROADCAST (prerecorded-live-bottom-bar-
// comment, Flutter parity to iOS): this bar renders for BOTH a live broadcast (`isLive == true`,
// i.e. `liveStatus == 1`) and an already-finished live replay (`isFinishedLiveReplay == true`) —
// true 純 VOD uses the side rail. A live broadcast's chat is open regardless of playback
// position, so the "留言..." pill and nickname button are NEVER collapsed on `isReplay` (the
// narrower, behind-live-edge DVR heuristic that mis-flags a 預錄直播 — finite-length HLS routed
// to IVS — and would wrongly close chat if it drove this). `isFinishedLiveReplay` IS,
// deliberately, a real reason to collapse the comment area + swap the leading/trailing slots
// (`rb-flutter-replay-live-chrome-parity`, parity iOS `chatClosed`) — a genuinely-ended stream's
// backend `commentsub` 404s, so the chat really is closed. The two flags are orthogonal and MUST
// NOT be confused: `isReplay` (still `liveStatus == 1`, chat open) vs `isFinishedLiveReplay`
// (stream over, chat closed).
//
// SUB-VIEW INPUT PATTERN (D-1/D-4): theme FIRST → snapshot values BY VALUE →
// trailing optional callbacks (default no-op). Reads ONLY its passed-in values;
// never reaches back into the model / template; calls NO core `simulate*` (the
// shell forwards bag / share / like / nickname / CC through the existing
// `onTapItem` rail wiring by kind; 留言 raises a dedicated `onComment`). NO
// scrollable — a fixed `Row` so the golden renders deterministically. Material
// `Icons.*` + CJK render as tofu in goldens (a known limitation, parity with the
// other surfaces); the widget tests assert the actual content.
//
// The user-facing string ("留言...") is design-literal (the minimal design mockup is the
// source of truth); localization is a cross-layer follow-up.

// MARK: - Secondary design colors (lifted from live-chrome.jsx `LBLiveBottomBar`)

/// `rgba(20,20,24,0.6)` — translucent dark icon-button fill (iconBtn).
const Color _iconButtonBackground = Color(0x99141418);

/// `rgba(20,20,24,0.55)` — comment pill fill.
const Color _commentBackground = Color(0x8C141418);

// MARK: - Layout tokens (lifted from live-chrome.jsx)

const double _barGap = 8; // flex gap
const double _barHPadding = 10; // padding 8px 10px 16px
const double _barTopPadding = 8;
/// Bottom padding (rb-flutter-live-bottom-bar-16pt-align): aligned to the VOD floating bag
/// button's `bottom: 16` (`player_shell_view.dart`) — the outer `Align` wrapper for this bar has
/// no static offset to remove (unlike iOS), so this bottom value moves icon content directly.
const double _barBottomPadding = 16;
const double _iconSize = 36; // 36×36 round iconBtn
const double _iconGlyphSize = 18; // Icons size 18 (暱稱 / 分享 / 愛心 / CC — 共用 _IconButton helper)

/// Bag button glyph size, INDEPENDENT of [_iconGlyphSize] (rb-flutter-live-bottom-bar-bag-icon-enlarge).
/// `Icons.bag size={25}` in `LBLiveBottomBar` — 25/36 ≈ 70% of the 36×36 `_iconSize` button,
/// vs. the other icon buttons' 18/36 ≈ 50%. `_BagButton` renders its own `Icon` directly
/// (it does NOT go through the shared `_IconButton` helper), so this constant only affects
/// the bag glyph and MUST NOT be merged back into [_iconGlyphSize].
const double _bagIconGlyphSize = 25;
const double _badgeMinSize = 16; // cart badge minWidth / height
const double _badgeFontSize = 10; // fontSize 10, weight 800
const double _badgeBorderWidth = 1.5; // 1.5px solid #fff border
const double _commentFontSize = 13; // 留言... 13px left
const String _commentPlaceholder = '留言...';
/// 已結束直播回放 chat-closed 變體文字（design-literal，同 `_commentPlaceholder` 模式；
/// `rb-flutter-replay-live-chrome-parity`，parity iOS `chatClosedPlaceholder`）。
const String _chatClosedPlaceholder = '聊天室已關閉';

/// The family-1 LIVE bottom bar surface. Renders the horizontal bag / comment /
/// nickname / share / like row from `LBLiveBottomBar`. The comment entry is always
/// available for a live broadcast (prerecorded-live-bottom-bar-comment).
///
/// Renders correctly with the default no-op callbacks (golden / preview safe).
class LiveBottomBarView extends StatelessWidget {
  /// The resolved reference-ui theme (FIRST argument, always).
  final ReferenceUITheme theme;

  /// Cart badge count; `> 0` → draw the badge on the bag button.
  final int bagCount;

  /// Replay (behind-live-edge) flag. RETAINED for source compatibility; NO LONGER alters this
  /// bar's comment / nickname rendering (a live broadcast's chat is open regardless of playback
  /// position — prerecorded-live-bottom-bar-comment). Header LIVE-pill handling is a separate surface.
  final bool isReplay;

  /// Upcoming (直播預告) SLIM variant flag (rb-flutter-upcoming-intro-chrome, parity
  /// iOS 320d543 / Android `LiveBottomBar(isUpcoming)`): the comment area collapses
  /// to a flex `Spacer` and the nickname / CC button is dropped — only bag + share +
  /// like remain (the stream hasn't started, so there is no chat). Takes precedence
  /// over [isReplay]. Mirrors `LBLiveBottomBar({ upcoming: true })` (live-chrome.jsx).
  final bool isUpcoming;

  /// Bag-only variant flag (直播預告開場片頭 `introPlaying`): the bar collapses to JUST the
  /// shopping-bag + a trailing flex `Spacer` — comment / nickname / CC / share / like are ALL
  /// dropped. The minimal intro-MP4 chrome (rb-flutter parity to iOS `LiveBottomBarView(bagOnly:)`).
  /// Takes PRECEDENCE over [isUpcoming] / [isReplay] / [isFinishedLiveReplay].
  final bool bagOnly;

  /// Already-finished-live-replay flag (`rb-flutter-replay-live-chrome-parity`, parity iOS
  /// `LiveBottomBarView.chatClosed`). Default `false` keeps every existing (LIVE / isReplay /
  /// upcoming / bagOnly) call site byte-identical — this widget's existing 3 goldens
  /// (`live-bottom-bar-{live,replay,upcoming}.png`) do not set this flag.
  ///
  /// `true` (fed `PlayerShellModel.isFinishedLiveReplay` — NOT the narrower core DVR [isReplay],
  /// same call-site discipline as `showsPlaybackProgressBar`'s own `isReplay` parameter):
  ///   - the flex comment area becomes a DISABLED "聊天室已關閉" pill (non-interactive; tap does
  ///     NOT forward [onComment] — the finished stream's backend `commentsub` 404s, unlike an
  ///     [isReplay] behind-live-edge broadcast whose chat stays genuinely open).
  ///   - the leading slot (nickname's position) becomes a「更多」(more) button instead, forwarding
  ///     [onMore] (a fresh, independent intent — NOT routed through [onNickname]).
  ///   - the trailing slot (share's position) becomes a CC (字幕) toggle instead, forwarding the
  ///     EXISTING [onToggleCC] — that field / its `player_shell_view.dart` call-site wiring
  ///     already existed as pure source-compat dead weight (no `build()` branch ever rendered a
  ///     button reading it); this is its first real rendering consumer, not a new field.
  ///   - the like button is UNAFFECTED (still rendered, still forwards [onLike]) — a finished
  ///     replay retains the ability to like, mirrored from iOS ground truth.
  /// Takes precedence below [bagOnly] / [isUpcoming] (mirrors iOS `commentAreaKind` /
  /// `leadingSlotKind` / `trailingActionKind` precedence exactly).
  final bool isFinishedLiveReplay;

  /// Like-icon lit (accent) state (`rb-flutter-live-like-burst-restyle`, design R37
  /// `LBLiveBottomBar.liked` / `screens.jsx`'s `liked` state). Default `false` renders the like
  /// icon WHITE (was unconditionally `theme.accent` before R37); the call site sets this `true`
  /// for the duration of `resolveLiveLikeBurstPlan().likedDuration` after a tap, then reverts.
  final bool liked;

  final VoidCallback? onBag;
  final VoidCallback? onComment;
  final VoidCallback? onNickname;
  final VoidCallback? onShare;
  final VoidCallback? onLike;
  final VoidCallback? onToggleCC;

  /// 「更多」(⋯) tap → host opens the collapsed-more sheet (only reachable when
  /// [isFinishedLiveReplay] renders the leading slot as `MoreGlyph`; `rb-flutter-replay-live-
  /// chrome-parity`). A fresh seam — NOT routed through [onNickname] (the leading slot's other
  /// occupant) since the two are mutually exclusive by construction and carry unrelated intents.
  /// `null` → inert (demo / snapshot).
  final VoidCallback? onMore;

  const LiveBottomBarView({
    super.key,
    required this.theme,
    required this.bagCount,
    required this.isReplay,
    this.isUpcoming = false,
    this.bagOnly = false,
    this.isFinishedLiveReplay = false,
    this.liked = false,
    this.onBag,
    this.onComment,
    this.onNickname,
    this.onShare,
    this.onLike,
    this.onToggleCC,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(
        left: _barHPadding,
        right: _barHPadding,
        top: _barTopPadding,
        bottom: _barBottomPadding,
      ),
      // rb-flutter-live-chrome-gradient-removal: the bottom-up dark scrim gradient
      // (`linear-gradient(to top, rgba(0,0,0,0.55), transparent)`) is REMOVED, matching the
      // corrected design source (`live-chrome.jsx` `LBLiveBottomBar` no longer carries a
      // `background` gradient). `Container.decoration` is optional, so this is a plain property
      // removal — no restructuring needed.
      child: Row(
        children: [
          _BagButton(
            key: LbTestKeys.liveBagButton,
            theme: theme,
            bagCount: bagCount,
            onTap: onBag,
          ),
          const SizedBox(width: _barGap),
          // bag-only variant (introPlaying intro MP4) — JUST the bag + a trailing flex Spacer.
          // Takes precedence over every other variant: comment / nickname / CC / more / share /
          // like are all dropped.
          if (bagOnly)
            const Spacer()
          else ...[
            // Flex comment area — variant resolved by the pure `liveBottomBarCommentAreaKind`:
            //   • upcoming(slim) → a flex Spacer (no chat before the stream starts).
            //   • isFinishedLiveReplay(回放) → disabled「聊天室已關閉」(rb-flutter-replay-live-
            //     chrome-parity): the FINISHED live's chat room is closed (backend commentsub →
            //     404). Distinct from a behind-edge `isReplay` (still liveStatus==1, chat OPEN).
            //   • comment → the tap-target "留言..." (LIVE, incl. 預錄直播 mis-flagged isReplay).
            switch (liveBottomBarCommentAreaKind(
                bagOnly: bagOnly,
                isUpcoming: isUpcoming,
                isFinishedLiveReplay: isFinishedLiveReplay)) {
              LiveBottomBarCommentAreaKind.upcomingSpacer => const Spacer(),
              LiveBottomBarCommentAreaKind.chatClosed => Expanded(
                  child: _ChatClosedPill(key: LbTestKeys.liveCommentPill),
                ),
              LiveBottomBarCommentAreaKind.comment ||
              LiveBottomBarCommentAreaKind.bagOnlySpacer =>
                Expanded(
                  child: _CommentPill(
                    key: LbTestKeys.liveCommentPill,
                    onTap: onComment,
                  ),
                ),
            },
            const SizedBox(width: _barGap),
            // Leading slot — NICKNAME in the normal LIVE variant, 更多 (more) in
            // isFinishedLiveReplay (rb-flutter-replay-live-chrome-parity, design R32 parity iOS
            // `LiveBottomBarView.leadingSlotKind`: More occupies the nickname slot's position),
            // NOTHING in upcoming slim (design gates both on `!upcoming`) — resolved by the pure
            // `liveBottomBarLeadingSlotKind`.
            switch (liveBottomBarLeadingSlotKind(
                bagOnly: bagOnly,
                isUpcoming: isUpcoming,
                isFinishedLiveReplay: isFinishedLiveReplay)) {
              LiveBottomBarLeadingSlotKind.nickname => Row(children: [
                  // 設定暱稱 改設計稿自繪 person-edit（人頭 + 鉛筆 badge），不再用 Material
                  // Icons.person（rb-align-nickname-icon-person-edit）。
                  _IconButton(
                    key: LbTestKeys.livePersonEdit,
                    tint: Colors.white,
                    onTap: onNickname,
                    child: PersonEditGlyph(color: Colors.white, size: _iconGlyphSize),
                  ),
                  const SizedBox(width: _barGap),
                ]),
              LiveBottomBarLeadingSlotKind.more => Row(children: [
                  _IconButton(
                    key: LbTestKeys.liveMore,
                    tint: Colors.white,
                    onTap: onMore,
                    child: MoreGlyph(color: Colors.white, size: _iconGlyphSize),
                  ),
                  const SizedBox(width: _barGap),
                ]),
              LiveBottomBarLeadingSlotKind.none => const SizedBox.shrink(),
            },
            // Trailing slot — SHARE in every variant EXCEPT isFinishedLiveReplay, where design
            // R32 moves the CC (字幕) toggle into this position (share itself moves INTO the
            // 「更多」sheet instead — rb-flutter-replay-live-chrome-parity, parity iOS
            // `trailingActionKind`). CC reads the EXISTING `onToggleCC` callback (already wired
            // at the `player_shell_view.dart` call site as pure source-compat dead weight until
            // now — this is its first real rendering consumer).
            switch (liveBottomBarTrailingActionKind(
                bagOnly: bagOnly,
                isUpcoming: isUpcoming,
                isFinishedLiveReplay: isFinishedLiveReplay)) {
              LiveBottomBarTrailingActionKind.share => _IconButton(
                  key: LbTestKeys.liveShare,
                  tint: Colors.white,
                  onTap: onShare,
                  child: ShareGlyph(color: Colors.white, size: _iconGlyphSize),
                ),
              LiveBottomBarTrailingActionKind.cc => _IconButton(
                  key: LbTestKeys.liveCC,
                  tint: Colors.white,
                  onTap: onToggleCC,
                  child: CcGlyph(color: Colors.white, size: _iconGlyphSize),
                ),
            },
            const SizedBox(width: _barGap),
            _IconButton(
              key: LbTestKeys.liveHeart,
              icon: Icons.favorite,
              // rb-flutter-live-like-burst-restyle (design R37): accent only while `liked`,
              // white otherwise (was unconditionally accent before this change).
              tint: liked ? theme.accent : Colors.white,
              onTap: onLike,
            ),
          ],
        ],
      ),
    );
  }
}

// MARK: - Comment-area / leading-slot / trailing-slot variant (pure, unit-testable — no
// rendering; rb-flutter-replay-live-chrome-parity, parity iOS `LiveBottomBarView`'s
// `CommentAreaKind` / `LeadingSlotKind` / `TrailingActionKind` trio)

/// Which thing the flex comment area draws. Pure decision of the three variant flags, extracted
/// so the precedence is unit-testable without rendering (mirrors `PlayerShellView.resolveGestureEnd`
/// discipline). `bagOnlySpacer` is unreachable at the `build()` call site (the `if (bagOnly)`
/// branch is handled before this switch is ever consulted) but kept for a total, defensively-
/// complete switch — matches iOS's own `bagOnlySpacer` case shape.
enum LiveBottomBarCommentAreaKind { bagOnlySpacer, upcomingSpacer, chatClosed, comment }

/// Resolve the comment-area variant. Precedence: `bagOnly` > `isUpcoming` > `isFinishedLiveReplay`
/// > 正常留言. Pure (no I/O, no Flutter).
LiveBottomBarCommentAreaKind liveBottomBarCommentAreaKind({
  required bool bagOnly,
  required bool isUpcoming,
  required bool isFinishedLiveReplay,
}) {
  if (bagOnly) return LiveBottomBarCommentAreaKind.bagOnlySpacer;
  if (isUpcoming) return LiveBottomBarCommentAreaKind.upcomingSpacer;
  if (isFinishedLiveReplay) return LiveBottomBarCommentAreaKind.chatClosed;
  return LiveBottomBarCommentAreaKind.comment;
}

/// Which affordance the LEADING slot (nickname's position) draws. Pure (unit-testable, no
/// rendering) — mirrors `liveBottomBarCommentAreaKind`'s discipline.
enum LiveBottomBarLeadingSlotKind { nickname, more, none }

/// Resolve the leading slot's variant: `bagOnly` or `isUpcoming` → `none` (neither affordance
/// applies); `isFinishedLiveReplay` → `more`; otherwise → `nickname` (normal LIVE). Pure.
LiveBottomBarLeadingSlotKind liveBottomBarLeadingSlotKind({
  required bool bagOnly,
  required bool isUpcoming,
  required bool isFinishedLiveReplay,
}) {
  if (bagOnly || isUpcoming) return LiveBottomBarLeadingSlotKind.none;
  return isFinishedLiveReplay
      ? LiveBottomBarLeadingSlotKind.more
      : LiveBottomBarLeadingSlotKind.nickname;
}

/// Which affordance the TRAILING slot (share's position) draws. Pure (unit-testable, no
/// rendering) — mirrors the two decisions above.
enum LiveBottomBarTrailingActionKind { share, cc }

/// Resolve the trailing slot's variant: `isFinishedLiveReplay` (and not `bagOnly`/`isUpcoming` —
/// those two variants keep their own unrelated trailing affordance, `share`, unaffected by this
/// swap) → `cc`; every other combination → `share` (unchanged). Pure.
LiveBottomBarTrailingActionKind liveBottomBarTrailingActionKind({
  required bool bagOnly,
  required bool isUpcoming,
  required bool isFinishedLiveReplay,
}) =>
    (!bagOnly && !isUpcoming && isFinishedLiveReplay)
        ? LiveBottomBarTrailingActionKind.cc
        : LiveBottomBarTrailingActionKind.share;

// MARK: - Like-tap burst plan (rb-flutter-live-like-burst-restyle, design R37 `likeAnimation` /
// `doAnimation`)
//
// Pure resolution of ONE press of THIS bar's like button: how many burst glyphs to spawn (1-4,
// randomised unless [n] pins it — design `likeAnimation(n)`), how far apart to stagger them (300ms,
// design `setTimeout(doAnimation, 300*i)`), and how long the button's `liked` (accent) tint should
// hold before reverting to white (design `300*(count-1) + 2000`ms). Scoped to THIS bar's own
// tap-triggered burst — the VOD side rail's `heartBurstTick` OBSERVATION path (`OperationRailView`)
// is a DIFFERENT, unrelated call site that stays a strict "one tick increase → one burst" per its
// own Requirement and MUST NOT gain this randomised multi-spawn behavior.

/// One resolved like-tap burst plan.
class LiveLikeBurstPlan {
  /// Burst glyphs to spawn this tap, 1-4 (design `count = (n ?? random(0..3)) + 1`).
  final int count;

  /// Delay before each spawn — [count] entries, `300ms * index` (design
  /// `setTimeout(doAnimation, 300*i)`).
  final List<Duration> spawnDelays;

  /// How long the like icon's `liked` (accent) tint should hold before reverting to white
  /// (design `300*(count-1) + 2000`ms).
  final Duration likedDuration;

  const LiveLikeBurstPlan({
    required this.count,
    required this.spawnDelays,
    required this.likedDuration,
  });
}

const int _likeBurstMaxExtraCount = 3; // design `Math.floor(Math.random()*4)` → 0..3
const Duration _likeBurstSpawnInterval = Duration(milliseconds: 300);
const Duration _likeBurstBaseLikedDuration = Duration(milliseconds: 2000);

/// Resolve one like-tap's burst plan. [n] mirrors design `likeAnimation(n)`'s optional forced
/// count-minus-one (0-3, clamped); the real onLike call site always passes `null` (design's bare
/// `likeAnimation()`), which draws uniformly from [random] (default `math.Random()`) — inject a
/// seeded `math.Random(seed)` in tests for determinism.
LiveLikeBurstPlan resolveLiveLikeBurstPlan({int? n, math.Random? random}) {
  final raw = (n ?? (random ?? math.Random()).nextInt(_likeBurstMaxExtraCount + 1))
      .clamp(0, _likeBurstMaxExtraCount);
  final count = raw + 1;
  final spawnDelays = [for (var i = 0; i < count; i++) _likeBurstSpawnInterval * i];
  final likedDuration = _likeBurstSpawnInterval * (count - 1) + _likeBurstBaseLikedDuration;
  return LiveLikeBurstPlan(count: count, spawnDelays: spawnDelays, likedDuration: likedDuration);
}

// MARK: - Bag button (`LBLiveBottomBar` bag)

class _BagButton extends StatelessWidget {
  final ReferenceUITheme theme;
  final int bagCount;
  final VoidCallback? onTap;

  const _BagButton({super.key, required this.theme, required this.bagCount, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topRight,
        children: [
          Container(
            width: _iconSize,
            height: _iconSize,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: BagGlyph(
              color: theme.accent,
              size: _bagIconGlyphSize * theme.fontScale,
            ),
          ),
          if (bagCount > 0)
            Positioned(
              top: -2,
              right: -2,
              child: _CartBadge(theme: theme, count: bagCount),
            ),
        ],
      ),
    );
  }
}

class _CartBadge extends StatelessWidget {
  final ReferenceUITheme theme;
  final int count;

  const _CartBadge({required this.theme, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: _badgeMinSize, minHeight: _badgeMinSize),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.accent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white, width: _badgeBorderWidth),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: _badgeFontSize * theme.fontScale,
          fontWeight: FontWeight.w800,
          height: 1.0,
        ),
      ),
    );
  }
}

// MARK: - Comment area

/// Flex tap-target "留言..." pill (NOT an inline text field); tap forwards `onTap`.
class _CommentPill extends StatelessWidget {
  final VoidCallback? onTap;

  const _CommentPill({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: _iconSize,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.centerLeft,
        decoration: const BoxDecoration(
          color: _commentBackground,
          borderRadius: BorderRadius.all(Radius.circular(999)),
        ),
        child: const Text(
          _commentPlaceholder,
          style: TextStyle(color: Color(0xC7FFFFFF), fontSize: _commentFontSize),
        ),
      ),
    );
  }
}

/// Disabled「聊天室已關閉」flex pill for the already-finished-live-replay variant
/// (`rb-flutter-replay-live-chrome-parity`, parity iOS `chatClosedPill`) — a NON-interactive
/// `Container` (NOT a `GestureDetector`), so a tap does nothing (no `onComment` → no composer, no
/// backend `commentsub` 404 mis-fire). Dimmer than the active pill (text alpha 0x80 vs 0xC7,
/// fainter capsule fill) to read as disabled. Reuses the SAME `LbTestKeys.liveCommentPill` key as
/// the active pill (the two are mutually exclusive by construction — never both rendered at
/// once) so an E2E scenario can locate "the comment area" regardless of variant.
class _ChatClosedPill extends StatelessWidget {
  const _ChatClosedPill({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: _iconSize,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: _commentBackground.withValues(alpha: 0.6),
        borderRadius: const BorderRadius.all(Radius.circular(999)),
      ),
      child: const Text(
        _chatClosedPlaceholder,
        style: TextStyle(color: Color(0x80FFFFFF), fontSize: _commentFontSize),
      ),
    );
  }
}

// MARK: - Icon button (`LBLiveBottomBar` iconBtn)

class _IconButton extends StatelessWidget {
  final IconData? icon;
  final Color tint;
  final VoidCallback? onTap;

  /// Optional custom glyph (e.g. the self-drawn `ShareGlyph`) rendered INSTEAD of [icon]
  /// (rb-flutter-share-icon-design-align). Exactly one of [icon] / [child] is provided.
  final Widget? child;

  const _IconButton({super.key, this.icon, required this.tint, this.onTap, this.child});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: _iconSize,
        height: _iconSize,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: _iconButtonBackground,
          shape: BoxShape.circle,
        ),
        child: child ?? Icon(icon, size: _iconGlyphSize, color: tint),
      ),
    );
  }
}
