import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart' show LBProduct;

import '../productsheets/equalizer_glyph.dart';
import '../productsheets/product_status_badge.dart';
import '../productsheets/sheet_scaffold.dart' show liveProductImage;
import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';
import 'now_introducing_carousel.dart' show PageDots;

/// Horizontal swipe velocity (px/s) that commits a pinned-card page flip (parity now-introducing).
const double _pinnedSwipeVelocity = 80;

// LiveOverlayChromeView — family-1 surface 4 (LIVE overlay chrome, Flutter).
//
// Spec: `reference-ui-rendering/spec.md` (family-1 player-shell, surface 4)
// Design: `design/templates/minimal/live-chrome.jsx` (LBLiveAnnounce /
// LBLivePinnedCard / LBLiveHostCaption) + `sdk-components.jsx` (LBPGestureHint /
// LBPMarqueeText). Flutter sibling of iOS `LiveOverlayChromeView.swift`
// (rb-ios-player-shell D-2 #4) and Android `LiveOverlayChrome.kt`
// (rb-android-player-shell).
//
// The full-bleed LIVE overlay chrome, layered ABOVE the video and BELOW the
// pinned chrome (top bar / side rail / info sheet — those are surfaces 1/2/3,
// owned by their own widgets). This surface renders ONLY the overlay affordances
// the design's `live-chrome.jsx` paints over the stream:
//
//   • LBLiveAnnounce    — announcement banner (bottom-left, translucent dark glass).
//   • LBLivePinnedCard  — pinned narrating-product card (bottom-right, white).
//   • LBLiveHostCaption — centered host caption overlay (~46% height).
//   • LBPGestureHint    — centered static gesture-hint pills (tap / hold / swipe).
//
// SCOPE FENCE (do NOT cross): this surface renders overlay affordances only. It
// MUST NOT render the product LIST / sheet (that is rb-flutter-product-sheets) nor
// the chat feed / win toasts (that is rb-flutter-feed-win). The `LBLiveChatOverlay`
// from `live-chrome.jsx` is therefore intentionally NOT rendered here.
//
// ─────────────────────────────────────────────────────────────────────────────
// SUB-VIEW INPUT PATTERN (matches PlayerShellView.dart's documented contract)
// ─────────────────────────────────────────────────────────────────────────────
//
//   LiveOverlayChromeView({
//       required ReferenceUITheme theme,         // 1. resolved theme (first)
//       required String announceText,            // 2. bound snapshot value(s)
//       LBProduct? pinnedProduct,                //    (by value, from PlayerShellModel)
//       String hostCaption = '',                 //    host-supplied static copy (GAP NOTE)
//       bool showGestureHints = true,            //    static presentation toggle
//       ValueChanged<LBProduct>? onTapPinnedProduct })  // 3. action callback (last, default no-op)
//
// The announce / caption / gesture hints carry no tap intent. The ONLY action is
// the pinned card's tap, which carries the tapped product and is host-wired (turnkey
// container default: opens that product's detail sheet — NOT owned by the shell). The
// surface forwards it via [onTapPinnedProduct] and renders correctly with every callback
// left null.
//
// One-way data flow: this widget reads ONLY its passed-in values and NEVER reaches
// back into PlayerShellModel or DefaultPlayerTemplate (D-1 / D-4).
//
// SNAPSHOT DETERMINISM (parity to the iOS "no ScrollView/Lazy" rule + the Roborazzi
// gotchas): plain `Stack` / `Column` / `Row` only — NO `ListView` / `GridView` /
// `SingleChildScrollView`, NO network image (`Image.network` / `NetworkImage`). The
// announce copy renders as a single-line truncated `Text` (the iOS `MarqueeText`
// first frame is offset 0, so the static truncated line IS the deterministic
// baseline — no animation state here). No randomness.
// ─────────────────────────────────────────────────────────────────────────────

/// The family-1 LIVE overlay chrome surface. Paints the announcement banner,
/// pinned narrating-product card, host caption, and static gesture hints over the
/// (host-supplied) video area, themed by the resolved [ReferenceUITheme].
///
/// Renders correctly with all callbacks null (golden / widget tests construct it
/// action-free).
class LiveOverlayChromeView extends StatelessWidget {
  /// The resolved reference-ui theme (first positional argument, always).
  final ReferenceUITheme theme;

  /// Announcement banner copy (`LBLiveAnnounce`). Source: `PlayerShellModel
  /// .announceText` (← `noticeTab.notice`). Empty → the banner is omitted.
  final String announceText;

  /// The LIVE pinned narrating product(s) (`LBLivePinnedCard`). Source:
  /// `PlayerShellModel.livePinnedProducts` (← template `liveActiveProducts`, ALL
  /// `narrate_status == 2`; ELSE the single `pinnedProduct` = `activeProduct`, as a 1-element
  /// list). Empty → no card; exactly 1 → single card (現狀, golden byte-identical); > 1 → 目前卡 +
  /// 分頁點 carousel (問題 7, rb-flutter-live-now-introducing-carousel).
  final List<LBProduct> pinnedProducts;

  /// Host caption copy (`LBLiveHostCaption`). There is NO public host-caption
  /// view-model on the template (see `PlayerShellModel` GAP NOTE) — host-supplied
  /// STATIC string. Empty → the caption overlay is omitted.
  final String hostCaption;

  /// Whether to draw the static gesture-hint pills (`LBPGestureHint`). Pure
  /// presentation copy — no view-model binding.
  final bool showGestureHints;

  /// Live-runtime image gate (parity iOS/Android `live` — `!paintsBackgroundPlaceholder`).
  /// `true` → the pinned card loads the real product photo via `liveProductImage`;
  /// `false` (demo / golden — DEFAULT) → the deterministic placeholder (no network image,
  /// baseline byte-stable). live-pinned-card-image-radius.
  final bool live;

  /// Host-wired pinned-card tap → carries the tapped [LBProduct] (multi-product carousel:
  /// the CURRENTLY displayed page's product, not always index 0). `null` → no-op (snapshot-safe).
  /// `rb-flutter-pinned-card-tap-opens-detail`: type widened from `VoidCallback?` (no product
  /// param) — the turnkey container's default now forwards to `_defaultOnProductTap` (→
  /// `DefaultPlayerTemplate.handleProductTap`, opens that product's DETAIL sheet), the same
  /// already-tested default `onProductTap` uses — NOT a new `simulateProductTap` round-trip
  /// (that path is a confirmed Flutter-bridge dead end, see
  /// `flutter-product-tap-diversion-wiring-reference-ui`).
  final ValueChanged<LBProduct>? onTapPinnedProduct;

  /// Host-wired pinned-card CLOSE (the right-top X chip). `null` → no-op → the close chip is
  /// inert (snapshot-safe). Carries the dismissed product id so the call site records a
  /// per-product-id local hide (`PlayerShellView._dismissedLivePinnedIds`). The close chip is a
  /// nested `GestureDetector` (`behavior: opaque`) that intercepts / consumes the tap so it does
  /// NOT bubble to the outer card `GestureDetector` (`onTapPinnedProduct` / open-detail) — the same
  /// nested-`GestureDetector` intercept as the VOD `MiniCartPeek._closeButton` (design
  /// `e.stopPropagation()`). Parity iOS / Android / RN rb-*-live-pinned-card-dismiss
  /// (LIVE 釘選卡 close 四端收官). live-pinned-card-dismiss.
  final void Function(String id)? onDismissPinnedProduct;

  /// Host-wired announce-banner tap → opens the VideoInfoPanel notice tab (PlayerShellView wires
  /// `selectInfoTab(notice)` + `_setInfoPanel(true)`). `null` → the banner is inert (snapshot-safe).
  /// live-announce-tap-open-info-panel.
  final VoidCallback? onTapAnnounce;

  /// LIVE vs already-finished-live-replay flag (`rb-flutter-replay-live-chrome-parity`, parity
  /// iOS `LiveOverlayChromeView.isLive`). Default `true` — this widget was ORIGINALLY only ever
  /// composed while `PlayerShellModel.isLive == true` (a genuinely-live broadcast); the default
  /// keeps every existing call site / golden byte-identical when it is omitted. Now that
  /// `PlayerShellView` also composes this widget for an already-finished live replay
  /// (`isFinishedLiveReplay == true`, `isLive == false`), the call site feeds `isLive: m.isLive`
  /// so this widget can tell the two live-chrome-family sub-states apart:
  ///   - [_isNarrating] uses `product.narrateStatus == 2` ONLY when `isLive == true` (a real live
  ///     source); when `isLive == false` the pinned card's source is already the time-window-
  ///     filtered `vodActiveProducts` (see `PlayerShellView`'s call site), so every product fed in
  ///     is already "currently narrating" by construction — `narrateStatus` carries no such
  ///     signal for a replay.
  ///   - [_gestureHints] shows a THIRD hold-hint line ("長按畫面 = 2倍速快轉") ONLY when
  ///     `isLive == false` — a long-press has no effect at all while genuinely live (see
  ///     `PlayerShellView.isSeekable` / `_handleLongPressStart`: `isSeekable` is structurally
  ///     `false` whenever `isLive == true`, so showing that hint there would describe an
  ///     unreachable gesture), but DOES trigger a real 2×-speed hold for a finished replay
  ///     (`isSeekable == true` there).
  final bool isLive;

  /// Whether the gesture-hint pill group (`_gestureHints()`) SHALL auto-fade to fully
  /// transparent 3.5s after it appears, via a 0.6s ease-out animation
  /// (`autoFadeGestureHints-gesture-hint-fade`, parity iOS
  /// `LiveOverlayChromeView.swift:124,189,216-224` / Android
  /// `LiveOverlayChrome.kt:179,247,626-639`). New parameter, default `false` — source-compatible,
  /// non-BREAKING; every existing call site / golden stays byte-identical when omitted (no
  /// `Timer` / `AnimatedOpacity` is constructed on the default path, see `_FadingGestureHints`).
  /// Orthogonal to [isLive]'s two-vs-three-row hint split (`rb-flutter-replay-live-chrome-parity`)
  /// and to [showGestureHints]'s own display gate — this only controls whether an ALREADY-shown
  /// hint group fades away, never whether it is drawn at all. The driving value at the
  /// `PlayerShellView` call site is `widget.live` (NOT `isLive` — see that call site's own
  /// doc comment for why the two are semantically distinct).
  final bool autoFadeGestureHints;

  const LiveOverlayChromeView({
    super.key,
    required this.theme,
    required this.announceText,
    this.pinnedProducts = const [],
    this.hostCaption = '',
    this.showGestureHints = true,
    this.live = false,
    this.onTapPinnedProduct,
    this.onDismissPinnedProduct,
    this.onTapAnnounce,
    this.isLive = true,
    this.autoFadeGestureHints = false,
  });

  @override
  Widget build(BuildContext context) {
    // Full-bleed overlay. Affordances are positioned with explicit padding so the
    // layout matches `live-chrome.jsx`'s absolute placement (parity to the iOS
    // ZStack / Android Box). The caption + gesture hints carry no tap intent
    // (design: pointerEvents: none) so they are wrapped in IgnorePointer.
    return Stack(
      fit: StackFit.expand,
      children: [
        // Centered host caption (~46% from the top — `LBLiveHostCaption`).
        if (hostCaption.isNotEmpty)
          IgnorePointer(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: const Alignment(0, -0.08), // ~46% height, centered
                child: _hostCaptionOverlay(),
              ),
            ),
          ),

        // Centered static gesture hints (`LBPGestureHint`). Wrapped in `_FadingGestureHints` so
        // `autoFadeGestureHints` can fade the WHOLE group to fully transparent 3.5s after it
        // appears (autoFadeGestureHints-gesture-hint-fade) — orthogonal to the `isLive`
        // two/three-row split baked into `_gestureHints()` itself.
        if (showGestureHints)
          IgnorePointer(
            child: Center(
              child: _FadingGestureHints(
                autoFade: autoFadeGestureHints,
                child: _gestureHints(),
              ),
            ),
          ),

        // Bottom row: announce banner (left) + pinned card (right).
        // `live-chrome.jsx`: announce `left:8 right:120 bottom:70`,
        // pinned card `right:8 bottom:64 width:100` (was `width:132` — see `_pinnedCard`,
        // rb-flutter-vod-live-product-card-restyle). Pinned card `right` is now 10 (not 8) —
        // aligned to the LIVE bottom bar's heart-icon right edge (LiveBottomBarView._barHPadding
        // = 10, rb-flutter-live-chat-card-edge-align, parity iOS rb-ios-live-chat-card-edge-align).
        // Announce banner `left` stays 8 (unaffected; its maxWidth: 265 calc is independent of
        // this `right` value).
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(left: 8, right: 10, bottom: 64),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (announceText.isNotEmpty)
                  // Tappable → host-wired navigation that opens the VideoInfoPanel notice tab
                  // (live-announce-tap-open-info-panel); inert when onTapAnnounce is null.
                  GestureDetector(
                    key: LbTestKeys.announceBanner,
                    onTap: onTapAnnounce,
                    behavior: HitTestBehavior.opaque,
                    child: _announceBanner(),
                  ),
                const Spacer(),
                if (pinnedProducts.isNotEmpty)
                  _LivePinnedCardCarousel(
                    key: LbTestKeys.pinnedCarousel,
                    theme: theme,
                    products: pinnedProducts,
                    cardBuilder: _pinnedCard,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── LBLiveAnnounce — announcement banner ─────────────────────────────────

  /// Bottom-left translucent-dark-glass announcement banner with a red icon badge
  /// and single-line truncated copy. Mirrors `LBLiveAnnounce` (`rgba(0,0,0,0.42)`
  /// bg, `#F03246` icon badge, white text — 2026-09-03 design recolor,
  /// `design/contract/claude-design-sync.md` R30; was yellow `#FFE08A` bg / dark
  /// `#15131A` text). The iOS `MarqueeText` first frame is offset 0 — the static
  /// truncated line is the deterministic baseline (no animation here).
  Widget _announceBanner() {
    return Container(
      // design LBLiveAnnounce left:8 right:120 on the 393 frame = 393 − 8 − 120 = 265
      // (iOS / Android parity). The left:8 inset comes from the overlay bottom Align padding.
      constraints: const BoxConstraints(maxWidth: 265),
      decoration: BoxDecoration(
        color: _announceBgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Red icon badge (`#F03246`, 22×22, radius 5).
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: _announceBadgeColor,
              borderRadius: BorderRadius.circular(5),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.campaign, size: 13, color: Colors.white),
          ),
          const SizedBox(width: 8),
          // Announce copy (single-line truncated — `LBPMarqueeText` static frame).
          Flexible(
            child: Text(
              announceText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.start,
              style: TextStyle(
                color: _announceTextColor,
                fontSize: 10.5 * theme.fontScale,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── LBLivePinnedCard — pinned narrating-product card ─────────────────────

  /// Bottom-right white product card for the single narrating product. Mirrors
  /// `LBLivePinnedCard`: image area + a tappable close chip (dismisses this product locally),
  /// accent narrate tag (when narrating), 1-line name, accent live price. A card-body tap forwards
  /// [product] to [onTapPinnedProduct] (host-wired, opens that product's detail sheet by default);
  /// the close chip forwards to [onDismissPinnedProduct] and consumes its own tap so it does NOT
  /// open the detail.
  Widget _pinnedCard(LBProduct product) {
    // rb-flutter-vod-live-product-card-restyle (2026-09-03): 132×92 → 100×88. Current
    // values (132 container width / 92 thumbnail height) were verified to match the
    // design's assumed prior baseline exactly (see `design.md` Context), so the new
    // design literals apply directly — no ratio re-derivation needed (unlike the
    // `rb-*-vod-bag-icon-ratio-restore` case where the live values had drifted).
    //
    // rb-flutter-product-detail-image-gallery (R34, `design/contract/claude-design-sync.md`):
    // the thumbnail area's height goes 88 → 100 (below), matching the unchanged `width: 100` —
    // a non-equal-aspect rectangle becomes a square. This is a SECOND adjustment layered on
    // top of the restyle above (only the aspect ratio changes; it does NOT revert the R31
    // shrink from 132×92 down to 100×wide).
    return GestureDetector(
      key: LbTestKeys.pinnedCard,
      onTap: () => onTapPinnedProduct?.call(product),
      child: Container(
        width: 100,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image area (design height 100, R34 — square with the 100-wide card; was 88).
            // Themed placeholder so the golden baseline is deterministic without a network
            // image; the REAL product photo loads OVER it at runtime (`live` + a non-blank
            // URL) via `liveProductImage` (live-pinned-card-image-radius). live == false /
            // blank → placeholder only.
            SizedBox(
              height: 100,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: liveProductImage(
                      live: live,
                      url: _imageUrl(product),
                      placeholder: ColoredBox(
                        color: _pinnedImagePlaceholder,
                        child: Center(
                          child: Icon(
                            Icons.image_outlined,
                            size: 22,
                            color: _pinnedImageGlyph,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Narrate ("介紹中") banner — MOVED from the content-padding text row below
                  // the thumbnail to a full-width strip overlaid on the thumbnail's bottom edge
                  // (rb-flutter-vod-live-product-card-restyle; was `theme.accent` icon+text under
                  // the image). Fixed coral fill (design `rgba(240,50,70,.7)`), unifying the
                  // vocabulary with `ProductRow`'s「介紹中」badge. Render condition
                  // (`_isNarrating(product, isLive)`, rb-flutter-replay-live-chrome-parity — was
                  // `_isNarrating(product)` reading only `narrateStatus`).
                  if (_isNarrating(product, isLive))
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        color: _introducingBadgeFill,
                        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.max,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const EqualizerGlyph(size: 9, color: Color(0xFFFFFFFF)),
                            const SizedBox(width: 3),
                            Text(
                              _narrateTagText,
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: TextStyle(
                                color: const Color(0xFFFFFFFF),
                                fontSize: 12 * theme.fontScale,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Close affordance chip — a tappable per-product dismiss. Its OWN nested
                  // GestureDetector (behavior: opaque) intercepts / consumes the tap so it does
                  // NOT bubble to the outer card GestureDetector (onTapPinnedProduct / open-detail)
                  // — the same nested-GestureDetector intercept as the VOD MiniCartPeek._closeButton
                  // (design e.stopPropagation()). The visual subtree (Container + Icon) is carried
                  // over verbatim; a GestureDetector paints nothing and `behavior` only affects hit
                  // testing, so the golden stays byte-identical. live-pinned-card-dismiss.
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      key: LbTestKeys.pinnedCardClose,
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onDismissPinnedProduct?.call(product.id),
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.close, size: 11, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 8, top: 6, bottom: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product name (design fontSize 10, up to 2 lines — was fontSize 11 / 1
                  // line; rb-flutter-vod-live-product-card-restyle). The narrate tag row
                  // that used to live here (accent icon+text) is REMOVED — see the coral
                  // banner overlaid on the thumbnail above.
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 10 * theme.fontScale,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  // Live price (accent), or dim「已售完」when sold out — single source of
                  // truth via ProductStatusBadge, matching MiniCartPeek / ProductRow's
                  // existing sold-out treatment (rb-flutter-live-pinned-card-soldout-label,
                  // parity iOS rb-ios-live-pinned-card-soldout-label). `priceShow` is the
                  // pre-formatted string.
                  Text(
                    _isSoldOut(product) ? _soldOutLabel : _livePriceText(product),
                    style: TextStyle(
                      color: _isSoldOut(product) ? _soldOutColor : theme.accent,
                      fontSize: 13 * theme.fontScale,
                      fontWeight:
                          _isSoldOut(product) ? FontWeight.w600 : FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── LBLiveHostCaption — centered host caption overlay ────────────────────

  /// Centered white-on-dark host caption (`LBLiveHostCaption`). Translucent dark
  /// card with a "主持人" label + the host caption copy (2-line clamp).
  Widget _hostCaptionOverlay() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _hostCaptionLabel,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 11 * theme.fontScale,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            hostCaption,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.start,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12 * theme.fontScale,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ── LBPGestureHint — centered static gesture hints ───────────────────────

  /// Two OR three centered dark hint pills (`LBPGestureHint`): tap-to-toggle-clean-mode,
  /// [optionally] hold-for-2x-speed, swipe-to-switch.
  ///
  /// `rb-flutter-replay-live-chrome-parity` RESTORES the hold-hint pill for `isLive == false`
  /// (already-finished-live replay), correcting the prior `rb-flutter-gesture-clean-mode-v2`-era
  /// removal: that removal's reasoning was CORRECT at the time (this widget was ONLY ever
  /// composed while `PlayerShellModel.isLive == true`, a genuinely-live broadcast, where a
  /// long-press structurally has no action under R29 — see `isSeekable(isLive:isUpcoming:
  /// isFinishedLiveReplay:)`, which is `false` whenever `isLive == true`), but the PREMISE
  /// changed: `PlayerShellView._buildContent` now also composes this widget for `usesLiveChrome`
  /// (`isLive || isFinishedLiveReplay`), so the previously-unreachable `isLive == false` render
  /// path is real — and for THAT sub-state `isSeekable` is structurally `true` (a finished
  /// replay IS seekable, same as VOD), so a long-press really does trigger the 2×-speed hold
  /// (`_handleLongPressStart` / `_startSpeedMode` in `player_shell_view.dart`) and deserves the
  /// hint. `isLive == true` (genuinely live) still shows only the two original rows — no
  /// structural change there, byte-identical to the pre-this-change render. Pure static
  /// localized copy.
  Widget _gestureHints() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _gestureHintPill(Icons.touch_app, _hintTap),
        const SizedBox(height: 8),
        if (!isLive) ...[
          _gestureHintPill(Icons.back_hand, _hintHold),
          const SizedBox(height: 8),
        ],
        _gestureHintPill(Icons.swap_vert, _hintSwipe),
      ],
    );
  }

  Widget _gestureHintPill(IconData icon, String text) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: 11 * theme.fontScale,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── Design tokens / derived copy (pure) ──────────────────────────────────

  /// The pinned product is "narrating" when `isLive == true` (a genuinely-live source, its
  /// pinned card comes from `PlayerShellModel.livePinnedProducts`, ALL of which may or may not
  /// currently be narrating) AND `narrateStatus == 2` (core convention). For a finished-live
  /// replay (`isLive == false`), `pinnedCard(_:)`'s caller only ever feeds
  /// `PlayerShellModel.vodActiveProducts` — already time-window-filtered `[beginTime, endTime)`
  /// against the current playhead — so being IN that list IS the "narrating" signal;
  /// re-checking the stale `narrateStatus` on top of it would be redundant and wrong (a replay
  /// has no live `narrateStatus == 2` signal at all), so this unconditionally returns `true`
  /// there (`rb-flutter-replay-live-chrome-parity`, parity iOS `isNarrating(_:isLive:)`). Pure.
  bool _isNarrating(LBProduct product, bool isLive) =>
      isLive ? product.narrateStatus == 2 : true;

  /// Sold-out state for the pinned card's price line — single source of truth via
  /// `ProductStatusBadge` (rb-flutter-live-pinned-card-soldout-label, parity iOS
  /// `LiveOverlayChromeView.isSoldOut(_:)`). MUST NOT gate whether the card itself
  /// appears or whether the「介紹中」badge shows — both stay orthogonal to sold-out. Pure.
  bool _isSoldOut(LBProduct product) =>
      ProductStatusBadge.resolve(product) == ProductStatusBadge.soldOut;

  /// The pinned card's product image URL (`photos.first ?? pic`). `liveProductImage`
  /// trims it and gates on emptiness, so this only picks the first photo or falls back
  /// to `pic`. Parity iOS `LiveOverlayChromeView.imageURL`. Pure.
  String _imageUrl(LBProduct product) =>
      product.photos.isNotEmpty ? product.photos.first : product.pic;

  /// The live-price label. Prefers the pre-formatted `priceShow`; falls back to
  /// `NT$ <price>` when the show string is empty. Pure.
  String _livePriceText(LBProduct product) {
    final show = product.priceShow.trim();
    if (show.isNotEmpty) return show;
    final price = product.price ?? 0;
    return 'NT\$ ${price.toInt()}';
  }
}

// ── LBPGestureHint auto-fade wrapper ──────────────────────────────────────

/// Locally-scoped fade-out timer / animation for the gesture-hint pill group
/// (`autoFadeGestureHints`, parity iOS `LiveOverlayChromeView.swift:124,189,216-224` / Android
/// `LiveOverlayChrome.kt:179,247,626-639`). `LiveOverlayChromeView` itself stays a
/// `StatelessWidget` — this private `StatefulWidget` carries the transient opacity state,
/// mirroring this file's existing `HeartBurst` precedent (`heart_burst.dart`) for localizing
/// short-lived animation state to the smallest necessary scope instead of upgrading the whole
/// surface to Stateful.
///
/// `autoFade == false` (default) returns [child] UNCHANGED — no `Timer`, no `AnimatedOpacity` is
/// ever constructed — so the widget-tree SHAPE (and therefore every existing byte-identical
/// golden) is unaffected. `autoFade == true` starts a one-shot 3.5s `Timer`; once it fires,
/// [child] fades to fully transparent over 0.6s with an ease-out curve (`AnimatedOpacity`),
/// matching iOS `.easeOut(duration: 0.6).delay(3.5)` and Android
/// `tween(durationMillis = 600, easing = LinearOutSlowInEasing)` + `delay(3500)` 1:1.
class _FadingGestureHints extends StatefulWidget {
  final bool autoFade;
  final Widget child;

  const _FadingGestureHints({required this.autoFade, required this.child});

  @override
  State<_FadingGestureHints> createState() => _FadingGestureHintsState();
}

class _FadingGestureHintsState extends State<_FadingGestureHints> {
  double _opacity = 1;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.autoFade) {
      _timer = Timer(const Duration(milliseconds: 3500), () {
        if (mounted) setState(() => _opacity = 0);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // MUST NOT construct an AnimatedOpacity on the default (false) path — even a
    // permanently-opacity-1 AnimatedOpacity inserts an extra Opacity/FadeTransition
    // RenderObject into the tree, which would needlessly widen the byte-identical-golden
    // surface area (see design.md D1).
    if (!widget.autoFade) return widget.child;
    return AnimatedOpacity(
      opacity: _opacity,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      child: widget.child,
    );
  }
}

/// PURE: filter the LIVE pinned products by the locally-dismissed product-id set
/// (rb-flutter-live-pinned-card-dismiss). When [dismissedIds] is empty this returns [products]
/// UNCHANGED (guarantees the default path is a zero-behaviour, golden-safe change); otherwise it
/// drops every product whose `id ∈ dismissedIds`, preserving the surviving products' relative order.
///
/// Expresses the「依 dismissed set 過濾釘選商品」decision as a top-level pure function so it is
/// unit-testable without rendering a widget (per `docs/unit-test-discipline.md`) and is shared by
/// the `PlayerShellView` call site. Mirrors iOS `LiveOverlayChromeView.visiblePinnedProducts` /
/// Android / RN `visiblePinnedProducts`, and the VOD now-introducing close semantics
/// (`PlayerShellView._dismissedVodProductIds` filter). Uses `Set<String>` to mirror Flutter's
/// existing VOD `_dismissedVodProductIds` (iOS also uses `Set<String>`; RN uses an array only
/// because its own VOD dismiss state is an array).
List<LBProduct> visiblePinnedProducts(
  List<LBProduct> products,
  Set<String> dismissedIds,
) =>
    dismissedIds.isEmpty
        ? products
        : products.where((p) => !dismissedIds.contains(p.id)).toList();

// ── Fixed decorative design hexes lifted from `live-chrome.jsx` (parity with
//    iOS / Android). These are DECORATIVE (announce banner / icon badge) — NOT
//    the resolved theme accent — so they stay constant across themes. ─────────

/// Announce banner background — translucent black `rgba(0,0,0,0.42)` (2026-09-03
/// design recolor, `design/contract/claude-design-sync.md` R30 — was yellow
/// `#FFE08A`). The design pairs this with `backdropFilter: blur(6px)`; per this
/// package's whole-file convention (see `floating_widget.dart`'s `_closeGlass`),
/// backdrop blur is NOT implemented — drawn as a flat translucent solid instead.
final Color _announceBgColor = const Color(0xFF000000).withValues(alpha: 0.42);

/// Announce icon badge (`#F03246` — brand red used decoratively here).
final Color _announceBadgeColor = colorFromHex('#F03246') ?? const Color(0xFFF03246);

/// Announce text color — white (2026-09-03 design recolor, R30 — was dark
/// `#15131A` on the old yellow background).
final Color _announceTextColor = Colors.white;

/// Pinned-card image placeholder fill (`#EFEFF2`).
final Color _pinnedImagePlaceholder =
    colorFromHex('#EFEFF2') ?? const Color(0xFFEFEFF2);

/// Pinned-card image glyph color (`#C7C7CC`).
final Color _pinnedImageGlyph = colorFromHex('#C7C7CC') ?? const Color(0xFFC7C7CC);

/// The narrate ("介紹中") banner fill — fixed coral `rgba(240,50,70,.7)` = `#F03246` @
/// alpha 0.7 (rb-flutter-vod-live-product-card-restyle, 2026-09-03). Literally the same
/// hex as [_announceBadgeColor] but kept as an INDEPENDENT constant — that one is a
/// fully-opaque decorative icon-badge red, this one a 0.7-alpha banner fill; the two
/// uses are unrelated despite sharing a hex (see `design.md` Decisions).
final Color _introducingBadgeFill =
    (colorFromHex('#F03246') ?? const Color(0xFFF03246)).withValues(alpha: 0.7);

// Static localized copy (matching iOS `LiveOverlayChromeView` + `LBPGestureHint`).
/// Host caption label ("主持人").
const String _hostCaptionLabel = '主持人';

/// Narrate-tag copy shown on the pinned card ("介紹中").
const String _narrateTagText = '介紹中';

/// Sold-out price-line color (`#9A96A3`), matching this package's existing sold-out-specific
/// treatment (`ProductRow._soldOutColor` / `MiniCartPeek._soldOutColor`,
/// rb-flutter-live-pinned-card-soldout-label; color corrected by
/// rb-flutter-live-pinned-card-soldout-label-color-fix — the original landing mistakenly used
/// `#6B6775`, this package's general dim-text token (`ProductRow._textDim`, used for
/// struck-through original price etc), not the sold-out-specific color).
final Color _soldOutColor = colorFromHex('#9A96A3') ?? const Color(0xFF9A96A3);

/// Sold-out price-line copy ("已售完"), matching `MiniCartPeek` / `ProductRow`.
const String _soldOutLabel = '已售完';

/// Gesture-hint copy (static localized presentation strings). `_hintTap` updated by
/// rb-flutter-gesture-clean-mode-v2 (was '點擊畫面 = 切換靜音' — R23's tap-to-mute gesture is
/// retired, replaced by tap-to-toggle-clean-mode). `_hintHold` is a FRESH constant
/// (`rb-flutter-replay-live-chrome-parity`) — NOT the old R23-era `_hintHold` ('長按畫面 =
/// 切換乾淨模式', hold-to-clean-mode) that a prior pass at this file removed as unreachable; this
/// is R29's distinct hold-for-2x-speed copy, parity iOS/Android `hintHold`, shown only for
/// `isLive == false` (see `_gestureHints()`'s own doc comment for the full reachability
/// derivation).
const String _hintTap = '點擊畫面 = 切換乾淨模式';
const String _hintHold = '長按畫面 = 2倍速快轉';
const String _hintSwipe = '上下滑動 = 切換影片';

// ── LBLivePinnedCard carousel — single card OR multi-product carousel + 分頁點 ──

/// The bottom-right pinned narrating-product carousel. `products`:
///   • 0   → renders nothing (`SizedBox.shrink`).
///   • 1   → the single card (NO 分頁點 / swipe wrapper — the rendered pixels match the prior
///           single-`pinnedProduct` card so golden baselines stay byte-identical).
///   • > 1 → 分頁點 (above the card) + the current card + horizontal swipe to change page.
///
/// Swipe direction gate: only a horizontal drag flips the page; a vertical drag falls through to
/// the outer prev/next video swipe. Tapping a page dot jumps to it. Mirrors iOS
/// `LiveOverlayChromeView.pinnedCardCarousel` / Android `PinnedProductCarousel` / RN
/// `PinnedCardCarousel` (問題 7, rb-flutter-live-now-introducing-carousel).
class _LivePinnedCardCarousel extends StatefulWidget {
  final ReferenceUITheme theme;
  final List<LBProduct> products;
  final Widget Function(LBProduct product) cardBuilder;

  const _LivePinnedCardCarousel({
    super.key,
    required this.theme,
    required this.products,
    required this.cardBuilder,
  });

  @override
  State<_LivePinnedCardCarousel> createState() => _LivePinnedCardCarouselState();
}

class _LivePinnedCardCarouselState extends State<_LivePinnedCardCarousel> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final products = widget.products;
    if (products.isEmpty) return const SizedBox.shrink();
    final i = _index.clamp(0, products.length - 1);
    final product = products[i];

    // Exactly one product → the single card, NO carousel wrapper (golden byte-identical to the
    // prior single-`pinnedProduct` render).
    if (products.length == 1) return widget.cardBuilder(product);

    // > 1 → 分頁點 (above, trailing-aligned over the card) + current card + horizontal swipe.
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -_pinnedSwipeVelocity) {
          setState(() => _index = (i + 1).clamp(0, products.length - 1));
        } else if (v > _pinnedSwipeVelocity) {
          setState(() => _index = (i - 1).clamp(0, products.length - 1));
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          PageDots(
            theme: widget.theme,
            count: products.length,
            current: i,
            onSelect: (idx) => setState(() => _index = idx),
            dotKeyPrefix: 'live-pinned-dot',
          ),
          const SizedBox(height: 6),
          widget.cardBuilder(product),
        ],
      ),
    );
  }
}
