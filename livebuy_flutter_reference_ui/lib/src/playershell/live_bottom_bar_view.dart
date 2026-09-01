import 'package:flutter/material.dart';

import '../reference_ui_theme.dart';
import '../share_glyph.dart';
import '../testing/lb_test_keys.dart';
import 'person_edit_glyph.dart';

// LiveBottomBarView — family-1 player-shell LIVE bottom bar.
//
// Spec: `reference-ui-rendering/spec.md`
//   § "LivebuyReferenceUI 渲染 LIVE 底部 bar（LiveBottomBarView），綁 bagCount / isReplay"
// Flutter sibling of iOS `LiveBottomBarView.swift` / Android `LiveBottomBar.kt`.
//   Design source: `design/templates/minimal/live-chrome.jsx` → `LBLiveBottomBar` (161-237).
//
// The LIVE-mode bottom bar. `screens.jsx` mode-branches the player chrome on
// `isLive`: the LIVE screen renders this horizontal bottom bar while the side rail
// (`OperationRailView`) is VOD-only (`!isLive`). The bar paints, left → right:
//
//   • a white shopping-bag button + cart badge (when `bagCount > 0`),
//   • a flex "留言..." TAP-TARGET pill (NOT an inline text field — design `onComment`
//     opens a sheet; the real composer is the host's),
//   • a nickname button,
//   • a share button,
//   • an accent like (heart) button.
//
// Comment entry ALWAYS available (prerecorded-live-bottom-bar-comment, Flutter parity to iOS):
// this bar renders ONLY for a live broadcast (`isLive == true`, i.e. `liveStatus == 1`) — true
// 回放/VOD uses the side rail. A live broadcast's chat is open regardless of playback position,
// so the "留言..." pill and nickname button are NEVER collapsed on `isReplay`. The prior "replay
// variant" (disabled "聊天室已關閉" + CC swap) is removed: `isReplay` was a playback-position
// heuristic that mis-flags a 預錄直播 (finite-length HLS routed to IVS) and wrongly closed chat.
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
  /// Takes PRECEDENCE over [isUpcoming] / [isReplay].
  final bool bagOnly;

  final VoidCallback? onBag;
  final VoidCallback? onComment;
  final VoidCallback? onNickname;
  final VoidCallback? onShare;
  final VoidCallback? onLike;
  final VoidCallback? onToggleCC;

  const LiveBottomBarView({
    super.key,
    required this.theme,
    required this.bagCount,
    required this.isReplay,
    this.isUpcoming = false,
    this.bagOnly = false,
    this.onBag,
    this.onComment,
    this.onNickname,
    this.onShare,
    this.onLike,
    this.onToggleCC,
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
          // Takes precedence over every other variant: comment / nickname / CC / share / like
          // are all dropped.
          if (bagOnly)
            const Spacer()
          else ...[
            // Flex comment area. Upcoming (slim) → just a flex Spacer (no chat before the
            // stream starts); otherwise (LIVE — INCLUDING 預錄直播 where isReplay is mis-flagged
            // true) → tap-target "留言...". The LIVE bottom bar only renders for a live broadcast
            // (liveStatus == 1), whose chat is open regardless of playback position — so the comment
            // entry is ALWAYS available and MUST NOT collapse to "聊天室已關閉" on isReplay
            // (prerecorded-live-bottom-bar-comment). True 回放/VOD uses the side rail.
            if (isUpcoming)
              const Spacer()
            else
              Expanded(
                child: _CommentPill(
                  key: LbTestKeys.liveCommentPill,
                  onTap: onComment,
                ),
              ),
            const SizedBox(width: _barGap),
            // Nickname button is dropped entirely in the upcoming variant (design gates it on
            // `!upcoming`). Otherwise it ALWAYS shows — no longer swapped for a CC toggle on
            // isReplay (a live broadcast's chat is open — prerecorded-live-bottom-bar-comment).
            if (!isUpcoming) ...[
              // 設定暱稱 改設計稿自繪 person-edit（人頭 + 鉛筆 badge），不再用 Material
              // Icons.person（rb-align-nickname-icon-person-edit）。
              _IconButton(
                key: LbTestKeys.livePersonEdit,
                tint: Colors.white,
                onTap: onNickname,
                child: PersonEditGlyph(color: Colors.white, size: _iconGlyphSize),
              ),
              const SizedBox(width: _barGap),
            ],
            // 分享 icon 統一改設計稿自繪三節點 ShareGlyph（rb-flutter-share-icon-design-align，問題 8）。
            _IconButton(
              key: LbTestKeys.liveShare,
              tint: Colors.white,
              onTap: onShare,
              child: ShareGlyph(color: Colors.white, size: _iconGlyphSize),
            ),
            const SizedBox(width: _barGap),
            _IconButton(
              key: LbTestKeys.liveHeart,
              icon: Icons.favorite,
              tint: theme.accent,
              onTap: onLike,
            ),
          ],
        ],
      ),
    );
  }
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
            child: Icon(
              Icons.shopping_bag_outlined,
              size: _bagIconGlyphSize * theme.fontScale,
              color: theme.accent,
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
