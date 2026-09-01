import 'package:flutter/material.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart' show LBProduct;

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
//   • LBLiveAnnounce    — announcement banner (bottom-left, yellow).
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
//       VoidCallback? onTapPinnedProduct })      // 3. action callback (last, default no-op)
//
// The announce / caption / gesture hints carry no tap intent. The ONLY action is
// the pinned card's tap, which is a host-wired core exit (`simulateProductTap`,
// NOT owned by the shell — the host wires it to core). The surface forwards it via
// [onTapPinnedProduct] and renders correctly with every callback left null.
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

  /// Host-wired pinned-card tap → core `simulateProductTap`. `null` → no-op
  /// (snapshot-safe).
  final VoidCallback? onTapPinnedProduct;

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

        // Centered static gesture hints (`LBPGestureHint`).
        if (showGestureHints)
          IgnorePointer(child: Center(child: _gestureHints())),

        // Bottom row: announce banner (left) + pinned card (right).
        // `live-chrome.jsx`: announce `left:8 right:152 bottom:70`,
        // pinned card `right:8 bottom:64 width:132`. Pinned card `right` is now 10 (not 8) —
        // aligned to the LIVE bottom bar's heart-icon right edge (LiveBottomBarView._barHPadding
        // = 10, rb-flutter-live-chat-card-edge-align, parity iOS rb-ios-live-chat-card-edge-align).
        // Announce banner `left` stays 8 (unaffected; its maxWidth: 233 calc is independent of
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

  /// Bottom-left yellow announcement banner with a red icon badge and single-line
  /// truncated copy. Mirrors `LBLiveAnnounce` (`#FFE08A` bg, `#F03246` icon badge,
  /// `#15131A` dark text). The iOS `MarqueeText` first frame is offset 0 — the
  /// static truncated line is the deterministic baseline (no animation here).
  Widget _announceBanner() {
    return Container(
      // design LBLiveAnnounce left:8 right:152 on the 393 frame = 393 − 8 − 152 = 233
      // (iOS / Android parity). The left:8 inset comes from the overlay bottom Align padding.
      constraints: const BoxConstraints(maxWidth: 233),
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
  /// to [onTapPinnedProduct] (host-wired core exit `simulateProductTap`); the close chip forwards to
  /// [onDismissPinnedProduct] and consumes its own tap so it does NOT open the detail.
  Widget _pinnedCard(LBProduct product) {
    return GestureDetector(
      key: LbTestKeys.pinnedCard,
      onTap: onTapPinnedProduct,
      child: Container(
        width: 132,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image area (design height 92). Themed placeholder so the golden
            // baseline is deterministic without a network image; the REAL product photo
            // loads OVER it at runtime (`live` + a non-blank URL) via `liveProductImage`
            // (live-pinned-card-image-radius). live == false / blank → placeholder only.
            SizedBox(
              height: 92,
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
                  // Narrate tag (accent) — shown for the narrating product.
                  if (_isNarrating(product))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bar_chart, size: 11, color: theme.accent),
                          const SizedBox(width: 3),
                          Text(
                            _narrateTagText,
                            style: TextStyle(
                              color: theme.accent,
                              fontSize: 11 * theme.fontScale,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  // Product name (1-line clamp, design dark text).
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 11 * theme.fontScale,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  // Live price (accent). `priceShow` is the pre-formatted string.
                  Text(
                    _livePriceText(product),
                    style: TextStyle(
                      color: theme.accent,
                      fontSize: 13 * theme.fontScale,
                      fontWeight: FontWeight.w800,
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

  /// Three centered dark hint pills (`LBPGestureHint`): tap-to-mute,
  /// long-press-pause, swipe-to-switch. Pure static localized copy.
  Widget _gestureHints() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _gestureHintPill(Icons.touch_app, _hintTap),
        const SizedBox(height: 8),
        _gestureHintPill(Icons.pan_tool, _hintHold),
        const SizedBox(height: 8),
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

  /// The pinned product is "narrating" when `narrateStatus == 2` (core
  /// convention). Pure.
  bool _isNarrating(LBProduct product) => product.narrateStatus == 2;

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
//    iOS / Android). These are DECORATIVE (yellow announce banner) — NOT the
//    resolved theme accent — so they stay constant across themes. ─────────────

/// Announce banner background (`#FFE08A`).
final Color _announceBgColor = colorFromHex('#FFE08A') ?? const Color(0xFFFFE08A);

/// Announce icon badge (`#F03246` — brand red used decoratively here).
final Color _announceBadgeColor = colorFromHex('#F03246') ?? const Color(0xFFF03246);

/// Announce text color (`#15131A` — fixed design dark text on yellow).
final Color _announceTextColor = colorFromHex('#15131A') ?? const Color(0xFF15131A);

/// Pinned-card image placeholder fill (`#EFEFF2`).
final Color _pinnedImagePlaceholder =
    colorFromHex('#EFEFF2') ?? const Color(0xFFEFEFF2);

/// Pinned-card image glyph color (`#C7C7CC`).
final Color _pinnedImageGlyph = colorFromHex('#C7C7CC') ?? const Color(0xFFC7C7CC);

// Static localized copy (matching iOS `LiveOverlayChromeView` + `LBPGestureHint`).
/// Host caption label ("主持人").
const String _hostCaptionLabel = '主持人';

/// Narrate-tag copy shown on the pinned card ("介紹中").
const String _narrateTagText = '介紹中';

/// Gesture-hint copy (static localized presentation strings).
const String _hintTap = '點擊畫面 = 切換靜音';
const String _hintHold = '長按畫面 = 切換乾淨模式';
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
