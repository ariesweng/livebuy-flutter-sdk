import 'package:flutter/material.dart';
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show LBSideRailItem, LBSideRailKind;

import '../reference_ui_theme.dart';
import '../share_glyph.dart';
import '../testing/lb_test_keys.dart';

// OperationRailView — family-1 player-shell surface 2 (side rail).
//
// Spec: `reference-ui-rendering/spec.md` (family-1 player-shell, surface 2)
// Flutter sibling of iOS `OperationRailView.swift` (rb-ios-player-shell D-2 #2)
// and Android `OperationRail.kt` (rb-android-player-shell).
//   Design source: `design/templates/minimal/sdk-components.jsx`
//     · `LBPSideRail`   (right-side vertical pill stack)
//     · `LBPBagButton`  (floating bag affordance + cart badge)
//     · `LBPHeartBurst` (floating hearts, played off a like — runtime only)
//
// The trailing side-rail. It binds the `DefaultOperationRail` SNAPSHOT VALUES
// republished by `PlayerShellModel` (`items: List<LBSideRailItem>` + `bagCount` +
// `heartBurstTick` + `muted`, all passed BY VALUE) and paints:
//
//   • one round pill per ENABLED action item (goods is the larger bag button),
//   • a cart badge on the goods item when `bagCount > 0`,
//   • a heart affordance for the like item (the actual burst animation is a
//     runtime concern — observed off `heartBurstTick`; the static surface /
//     golden draws only the buttons, parity with Android's omission).
//
// SUB-VIEW INPUT PATTERN (D-1/D-4): theme FIRST → snapshot values BY VALUE →
// trailing optional `onTapItem` (default no-op). This view reads ONLY its
// passed-in values — it NEVER reaches back into `PlayerShellModel` /
// `DefaultPlayerTemplate`, holds NO second copy of state, and calls NO core
// `simulate*`. Taps surface a single `onTapItem` intent (each kind), which the
// shell / host wires to the matching core exit.
//
// RENDERING CONSTRAINTS (inherited from iOS / Android — CRITICAL): NO scrollable
// (`ListView` / `GridView` / `SingleChildScrollView`) — a fixed small `Column`
// so the rail renders deterministically in the golden. NO network image. Glyphs
// are deterministic `Icons.*` (Material) so the baseline is stable.

// MARK: - Secondary design colors (lifted from sdk-components.jsx)
//
// `ReferenceUITheme` carries accent / background / text only; the rail's
// translucent dark pill fill is a reference-ui-local design token (mirrors how
// the iOS / Android surfaces lift it as a private constant).

/// `rgba(20,20,24,0.55)` — the translucent dark pill fill (`LBPSideRail` railBtn).
const Color _railPillBackground = Color(0x8C141418); // 0x8C ≈ 0.55 alpha

// MARK: - Layout tokens (lifted from sdk-components.jsx)

const double _railGap = 10; // flex gap between pills (`LBPSideRail`)
const double _pillSize = 40; // 40×40 round pill
const double _pillGlyphSize = 18; // Icons size 18
const double _bagSize = 48; // 48×48 floating bag (`LBPBagButton`)
const double _bagGlyphSize = 34; // Icons.bag size 34 (design `LBPBagButton`: 34/48 ≈ 70% of the button)
const double _badgeMinSize = 20; // count chip minWidth / height
const double _badgeFontSize = 11; // fontSize 11, weight 800
const double _badgeBorderWidth = 2; // 2px solid #fff border

/// The family-1 trailing side-rail surface. Renders only the ENABLED
/// [LBSideRailItem]s as themed round pills (goods as the larger bag button with a
/// cart badge when `bagCount > 0`), painting over whatever (dark video) backdrop
/// the host supplies behind it.
///
/// Renders correctly with the default no-op [onTapItem] (snapshot / preview safe).
class OperationRailView extends StatelessWidget {
  /// The resolved reference-ui theme (FIRST argument, always).
  final ReferenceUITheme theme;

  /// Ordered side-rail action items. Only `enabled` items are drawn.
  final List<LBSideRailItem> items;

  /// Shopping-bag badge count. `> 0` → draw the badge on the goods button.
  final int bagCount;

  /// Monotonic heart-burst tick. Carried for shape parity; the burst animation is
  /// a runtime concern observed off this value (the static surface draws none).
  final int heartBurstTick;

  /// Mute gesture state (shared with the header). Carried so the surface matches
  /// the documented initializer shape; informational for the rail today.
  final bool muted;

  /// Tap intent for a side-rail kind. The rail does NOT own the action — the
  /// shell / host forwards to the matching core `simulate*` (D-4). Defaults to a
  /// no-op so demo / golden instances construct action-free.
  final ValueChanged<LBSideRailKind>? onTapItem;

  const OperationRailView({
    super.key,
    required this.theme,
    required this.items,
    required this.bagCount,
    required this.heartBurstTick,
    required this.muted,
    this.onTapItem,
  });

  /// Fixed side-rail presentation order (design `LBPSideRail`: CC / share / contact). Each kind is
  /// drawn ONLY when enabled in `items` (parity iOS `presentationOrder` + `isEnabled`). GOODS（袋）
  /// / LIKE / MORE / CHAT / GUEST_NAME_EDIT are NOT rail kinds: the bag is a SEPARATE floating
  /// affordance ([FloatingBagButton]); the others are not in the design rail.
  static const List<LBSideRailKind> _presentationOrder = [
    LBSideRailKind.subtitle,
    LBSideRailKind.share,
    LBSideRailKind.serviceLink,
  ];

  @override
  Widget build(BuildContext context) {
    // Fixed presentation order, each pill drawn ONLY when its kind is enabled in `items`. The bag
    // is NOT here — it is the separate FloatingBagButton composed lower by the shell.
    final visible = _presentationOrder
        .where((k) => items.any((it) => it.kind == k && it.enabled))
        .toList(growable: false);

    return Column(
      key: LbTestKeys.operationRail,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const SizedBox(height: _railGap),
          _PillButton(
            key: railKeyFor(visible[i]),
            theme: theme,
            kind: visible[i],
            onTap: () => onTapItem?.call(visible[i]),
          ),
        ],
      ],
    );
  }
}

/// The floating shopping-bag affordance (design `LBPBagButton`, iOS `FloatingBagButtonView`): a
/// 48×48 white circle + accent bag glyph + cart badge. Composed by the shell SEPARATELY from the
/// side rail (so it sits lower, next to the mini-cart strip — design `bottom 16` vs rail `bottom 80`).
class FloatingBagButton extends StatelessWidget {
  final ReferenceUITheme theme;
  final int bagCount;
  final VoidCallback? onTap;

  const FloatingBagButton({
    super.key,
    required this.theme,
    required this.bagCount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => KeyedSubtree(
        key: LbTestKeys.playerBag,
        child: _BagButton(theme: theme, bagCount: bagCount, onTap: () => onTap?.call()),
      );
}

// MARK: - Pill button (`LBPSideRail` railBtn)

/// A standard round pill: 40×40, fully-rounded, translucent dark fill, white
/// glyph. The active (white fill + accent glyph) style is not fed for any kind
/// today, so pills render in the inactive style (parity with iOS / Android).
class _PillButton extends StatelessWidget {
  final ReferenceUITheme theme;
  final LBSideRailKind kind;
  final VoidCallback onTap;

  const _PillButton({
    super.key,
    required this.theme,
    required this.kind,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: _pillSize,
        height: _pillSize,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: _railPillBackground,
          shape: BoxShape.circle,
        ),
        // 分享 改設計稿自繪三節點 ShareGlyph（rb-flutter-share-icon-design-align，問題 8）；
        // 其餘 kind 維持 Material glyph。
        child: kind == LBSideRailKind.share
            ? ShareGlyph(
                color: Colors.white,
                size: _pillGlyphSize * theme.fontScale,
              )
            : Icon(
                railIconFor(kind),
                size: _pillGlyphSize * theme.fontScale,
                color: Colors.white,
              ),
      ),
    );
  }
}

// MARK: - Bag button (`LBPBagButton`)

/// The bag button: a larger 48×48 white circle with the accent-tinted bag glyph,
/// plus the cart badge when `bagCount > 0` (accent fill, white text, 2px white
/// border, top-trailing). The iOS drop shadow is omitted (deterministic golden;
/// `debugDisableShadows` is on for tests) — shape + colors match.
class _BagButton extends StatelessWidget {
  final ReferenceUITheme theme;
  final int bagCount;
  final VoidCallback onTap;

  const _BagButton({
    required this.theme,
    required this.bagCount,
    required this.onTap,
  });

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
            width: _bagSize,
            height: _bagSize,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(
              railIconFor(LBSideRailKind.goods),
              size: _bagGlyphSize * theme.fontScale,
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

// MARK: - Cart badge (`LBPBagButton` count chip)

/// Cart count badge: accent capsule, white heavy text, 2px white border.
class _CartBadge extends StatelessWidget {
  final ReferenceUITheme theme;
  final int count;

  const _CartBadge({required this.theme, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minWidth: _badgeMinSize,
        minHeight: _badgeMinSize,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.accent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white, width: _badgeBorderWidth),
      ),
      child: Text(
        badgeText(count),
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

// MARK: - Kind → icon mapping
//
// The design's `LBPSideRail` only draws cc / share / chat; the view-model carries
// the wider reachable kind set. Each kind maps to the Material icon that matches
// its design glyph intent (bag is handled by `_BagButton`). Built-in `Icons.*`
// keep the baseline deterministic across renderer versions.

/// Map a side-rail kind to its deterministic Material glyph. Mirrors the iOS SF
/// Symbol mapping and the Android text-glyph mapping (same design intent).
IconData railIconFor(LBSideRailKind kind) {
  switch (kind) {
    case LBSideRailKind.goods:
      return Icons.shopping_bag_outlined; // handled by _BagButton
    case LBSideRailKind.chat:
      return Icons.chat_bubble; // bubble.left.fill
    case LBSideRailKind.like:
      return Icons.favorite; // heart.fill
    case LBSideRailKind.share:
      return Icons.ios_share; // square.and.arrow.up
    case LBSideRailKind.subtitle:
      return Icons.closed_caption; // captions.bubble / CC
    case LBSideRailKind.serviceLink:
      return Icons.chat_bubble; // bubble.left.fill / chat bubble (contact)
    case LBSideRailKind.guestNameEdit:
      return Icons.edit; // pencil / edit display name
    case LBSideRailKind.more:
      return Icons.more_horiz; // ellipsis / more menu
  }
}

// MARK: - Kind → E2E test key mapping
//
// Maps a rail kind to its INERT E2E [Key] for the harness (parity with the iOS
// LBAccessibilityID / Android LBTestTags / RN LBTestIDs per-kind values). Only the
// kinds the design rail actually renders (`_presentationOrder`: subtitle / share /
// serviceLink) have keys; the others return null (no key — the pill never renders
// in the rail anyway, the bag/like live elsewhere). A null key is a layout no-op.

/// The E2E test key for a rail kind (null when the kind has no rail pill).
Key? railKeyFor(LBSideRailKind kind) {
  switch (kind) {
    case LBSideRailKind.subtitle:
      return LbTestKeys.railSubtitle;
    case LBSideRailKind.share:
      return LbTestKeys.railShare;
    case LBSideRailKind.serviceLink:
      return LbTestKeys.railService;
    case LBSideRailKind.like:
      return LbTestKeys.railLike;
    case LBSideRailKind.chat:
      return LbTestKeys.railComment;
    case LBSideRailKind.goods:
      return LbTestKeys.railGoods;
    case LBSideRailKind.guestNameEdit:
    case LBSideRailKind.more:
      return null;
  }
}

// MARK: - Badge text

/// Clamp very large counts so the badge stays compact (design badge is a small
/// chip). Caps past 99 as `99+` — matches typical cart-badge convention + iOS /
/// Android.
String badgeText(int count) => count > 99 ? '99+' : '$count';
