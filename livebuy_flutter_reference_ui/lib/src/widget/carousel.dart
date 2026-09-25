import 'package:flutter/widgets.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart' show LBVideoItem;
import 'package:visibility_detector/visibility_detector.dart';

import '../moments/loading_mark_animation_view.dart';
import '../reference_ui_theme.dart';
import '../reference_ui_widget_embed_theme.dart';
import '../testing/lb_test_keys.dart';
import 'carousel_card.dart';
import 'widget_model.dart' show WidgetGoods, WidgetSeeds;

// CarouselView — family-5 widget surface 1 (LBPCarousel, horizontal card row).
//
// Spec: `reference-ui-rendering/spec.md` (family-5 widget surfaces — "渲染 Flutter
// Carousel widget"). Flutter parity of iOS `CarouselView.swift` (rb-ios-widget) +
// Android `CarouselView.kt` (rb-android-widget). Design:
// `design/templates/minimal/widgets.jsx` `LBPCarousel` (lines 230-325).
//
// The first of the four family-5 widget surfaces dispatched by `WidgetOverlayView`
// (selected when `content.current.mode == carousel`). It reproduces `LBPCarousel`'s
// structure:
//
//   • a HEADER ROW (widgets.jsx 283-294): the section `title` (heavy) with an
//     optional `subtitle` (dim) on the leading side, and a「查看更多 ›」accent link
//     on the trailing side — shown only when `title` is non-empty OR a `subtitle`
//     exists (mirrors `LBPCarousel`'s `(title || subtitle) && (...)`),
//   • a single ROW of shared `CarouselCardView`s (widgets.jsx 295-322) built from
//     the passed-in `videos`.
//
// ── NO scrollable (the verified family rule) ─────────────────────────────────────
//   The design's row is HORIZONTALLY SCROLLABLE (`overflowX: 'auto'`, drag-to
//   -scroll). The Flutter golden path renders into a fixed surface, and the family
//   rule forbids any scrollable container. So this surface lays a FIXED SMALL SET
//   (the visible first [maxCards]) of cards in a PLAIN `Row` (NO ListView /
//   SingleChildScrollView / Lazy*). The real horizontal scroll / full-list
//   navigation is a HOST concern — the「查看更多 ›」link forwards via the host-wired
//   `onSeeMore` exit, and each card tap forwards via `onTapVideo`. This layer NEVER
//   scrolls / paginates / opens the player itself.
//
// ── CARD REUSE ───────────────────────────────────────────────────────────────────
//   Every card is the SHARED `CarouselCardView` primitive (the family-5
//   `LBPCarouselCard`) — this surface MUST NOT re-draw a card from scratch. The card
//   owns the 9:16 thumbnail placeholder + LIVE / VOD kind badge + product overlay +
//   title; this surface only arranges a `Row` of them under a header.
//
// SUB-VIEW INPUT PATTERN (parity with families 1-4): theme FIRST → bound snapshot
// value(s) by value (`videos`, `title`, `subtitle`, `cardWidth`, per-card `goodsFor`,
// the two raw embed colors) → interaction callbacks (`onTapVideo` / `onSeeMore`)
// trailing, each defaulting to null. One-way data flow: this surface reads ONLY its
// passed-in values — it never reaches back into `WidgetModel` / `DefaultWidgetTemplate`,
// holds NO second copy of state, calls NO core `simulate*` / `requestLoadMore`, uses NO
// `ListView` / `GridView` (the `scrollable` turnkey mode's `SingleChildScrollView` is the
// one sanctioned exception) / network image, and renders correctly with all callbacks
// null (demo / golden / widget tests).
//
// ── EMBED COLORS (rb-flutter-widget-embed-colors + rb-flutter-carousel-bgcolor) ──
//   This IS one of the widget surfaces that interpret `widgetColor` / `widgetBgcolor` —
//   see the [theme] getter below, which overlays them onto the caller-supplied
//   [resolvedTheme] via `ReferenceUIWidgetEmbedTheme.derive`. The scope is strictly this
//   surface: `ReferenceUIThemeResolver` still never sees these two values, and the player
//   / sheets / floating / minimized cards keep the underived theme. `widget_color` IS
//   visible here (the header title / subtitle and every card title read `theme.text`);
//   `widget_bgcolor` IS ALSO visible here — the root `Container` in [build] paints
//   `theme.background` (rb-flutter-carousel-bgcolor), parity with `VideoShopGridView`'s
//   pre-existing background paint. Missing / `null` / unparseable stay on the resolved
//   theme's background — no new default is introduced.
//
// ── SCROLL-END VISIBILITY REFRESH (rb-flutter-widget-preview-scroll-end-visibility-refresh) ──
//   The turnkey `scrollable` mode's `SingleChildScrollView` is wrapped in a
//   `NotificationListener<ScrollNotification>` ([_flushVisibilityOnScrollEnd]) so a card
//   scrolling back into view does not wait out the `visibility_detector` package's
//   `VisibilityDetectorController.instance.updateInterval` (500 ms by default) before its
//   `LoopingVideoView` (Android `release` policy, `rb-flutter-widget-preview-offscreen-decoder-
//   release`) re-creates its controller. See that change's mount-time flush
//   (`LoopingVideoView._flushFirstVisibilityReport`) for the analogous first-frame case; this is
//   the SAME fix applied to the "scrolled away and back" case, which the mount-time flush does not
//   cover. `notifyNow()` is process-global (flushes every pending `VisibilityDetector` report, not
//   just this row's), so the effect is a harmless synchronous no-op when nothing is pending.

/// The family-5 `LBPCarousel` surface: a header row (title + optional subtitle +
/// 「查看更多 ›」accent link) above a PLAIN `Row` of a FIXED SMALL set of shared
/// `CarouselCardView`s built from `videos`. Card tap forwards via the host-wired
/// `onTapVideo` exit, the header link via `onSeeMore`; this layer never scrolls /
/// paginates / opens the player itself.
class CarouselView extends StatelessWidget {
  /// The theme AS SUPPLIED by the caller (`ReferenceUIThemeResolver` output), BEFORE
  /// this surface overlays the `/sdk/widget` embed colors. Read [theme], NOT this —
  /// every paint site goes through the derived value.
  final ReferenceUITheme resolvedTheme;

  /// The theme this surface actually paints with (FIRST — SUB-VIEW INPUT PATTERN, taken
  /// as the `theme:` constructor argument). The header title uses `theme.text`, the
  /// subtitle a dim variant, the「查看更多 ›」link `theme.accent`.
  ///
  /// Derived per read from [resolvedTheme] + [widgetColor] / [widgetBgcolor]
  /// (`widget-embed-colors`). A GETTER rather than a stored field so EVERY paint site
  /// reaches the derived value — including the ones outside `build()` (`_header()` /
  /// `_cardRow()` / `_cardHeight`) that a `build()`-local shadow would silently miss
  /// (design FD1). When nothing is configured this EQUALS [resolvedTheme], keeping the
  /// existing goldens byte-identical.
  ReferenceUITheme get theme => ReferenceUIWidgetEmbedTheme.derive(
        resolvedTheme,
        widgetColor,
        widgetBgcolor,
      );

  /// The card-row source (read-only — passed BY VALUE from `WidgetModel.videos`).
  /// Only the visible first [maxCards] are drawn (the row is a FIXED SMALL set, NOT
  /// scrollable). This surface never mutates / re-fetches.
  final List<LBVideoItem> videos;

  /// Section title (heavy, leading). Defaults to the design's「精選影片」. An empty
  /// title AND a null subtitle hide the entire header row (mirrors widgets.jsx 283).
  final String title;

  /// Optional section subtitle (dim, below the title). null → no subtitle line.
  final String? subtitle;

  /// Card width (logical px) forwarded to every `CarouselCardView`. Defaults to the
  /// design's `132`; the 9:16 height is derived by the card.
  final double cardWidth;

  /// Per-card product overlay resolver (reference-ui `WidgetGoods` — Flutter core
  /// `LBVideoItem` has no `goods` field). null → no overlay; demo / golden pass
  /// [WidgetSeeds.goodsFor].
  final WidgetGoods? Function(LBVideoItem item)? goodsFor;

  /// Whether the cards load their real cover photo. `false` (DEFAULT — demo / golden)
  /// → placeholder ONLY (byte-stable goldens); `true` (host runtime) → each card
  /// overlays `item.cover` over the placeholder. Forwarded verbatim to every
  /// [CarouselCardView]. Parity with iOS `CarouselRowView.live`.
  final bool live;

  /// Card tap → host-wired exit (`onTapVideo(item)` → host → core open player for
  /// `item.id`). null for demo / golden instances — the row is inert. This layer
  /// NEVER opens the player itself.
  final void Function(LBVideoItem item)? onTapVideo;

  /// Header「查看更多 ›」link → host-wired exit (navigate to the full video list).
  /// null → inert link. This layer NEVER navigates itself.
  final VoidCallback? onSeeMore;

  /// Turnkey scroll mode (parity iOS `ScrollableCarouselView`). `false` (DEFAULT — embedded /
  /// demo / golden) → a FIXED windowed clipped Row of the first [maxCards] (golden-safe, NO
  /// scroll). `true` (turnkey `WidgetOverlayView`) → a horizontal `SingleChildScrollView` over
  /// ALL `videos` (uncapped), so the user can scroll through every video.
  final bool scrollable;

  /// HOST-FACING opt-out: whether the header row (title + subtitle + 查看更多 link) is allowed
  /// to render at all (`rb-flutter-widget-carousel-header-visibility`). `true` (DEFAULT — every
  /// pre-existing caller / demo / golden) leaves the pre-existing content-driven rule
  /// ([_hasHeaderContent]) as the sole gate, so existing baselines stay byte-identical. `false` →
  /// the header never renders regardless of `title` / `subtitle` content — the card row moves up
  /// to occupy the space. Distinct from [_hasHeaderContent] (whether there IS header content to
  /// show); the two AND together in [build] (`showsHeader && _hasHeaderContent`).
  final bool showsHeader;

  /// RAW `product_card` wire value (`WidgetModel.productCard`), forwarded VERBATIM to
  /// every [CarouselCardView] in the row — the fallback stays in the card's single pure
  /// entry point (`normalizeProductCardMode`). `null` (the DEFAULT) → `inside`, i.e. the
  /// historical rendering. This surface also feeds it to [_belowSlotExtent] so the row's
  /// height bound grows with the `below` slot. rb-flutter-widget-product-card-modes.
  final String? productCard;

  /// RAW `widget_color` wire value (`POST /sdk/widget` root; `1`=預設色彩 / `2`=色彩反轉),
  /// sourced from `WidgetModel.widgetColor`. `1` (the DEFAULT — every pre-existing caller
  /// / demo / golden) leaves `theme.text` untouched, so existing baselines stay
  /// byte-identical. Interpreted ONLY through [ReferenceUIWidgetEmbedTheme.derive].
  final int widgetColor;

  /// RAW `widget_bgcolor` wire value (hex, or the empty string meaning「透明」on web),
  /// sourced from `WidgetModel.widgetBgcolor`. `null` (the DEFAULT) / `""` / an
  /// unparseable string all leave `theme.background` untouched (`widget-embed-colors` —
  /// native has no third-party page to show through). Painted by the root `Container` in
  /// [build] (rb-flutter-carousel-bgcolor), parity with `VideoShopGridView`.
  final String? widgetBgcolor;

  /// Whether the widget content's FIRST page fetch is currently in flight
  /// (`WidgetModel.isInitialLoading`, widget-loading-placeholder,
  /// rb-flutter-widget-loading-placeholder). `true` → the header (if shown) renders
  /// unchanged, but the card row is replaced by a fixed-height loading placeholder
  /// (see [_loadingRow]) instead of real cards. Default `false` (every pre-existing
  /// caller / demo / golden) keeps existing baselines byte-identical.
  final bool isInitialLoading;

  const CarouselView({
    super.key,
    required ReferenceUITheme theme,
    required this.videos,
    this.title = defaultTitle,
    this.subtitle,
    this.cardWidth = 132,
    this.goodsFor,
    this.live = false,
    this.productCard,
    this.widgetColor = 1,
    this.widgetBgcolor,
    this.onTapVideo,
    this.onSeeMore,
    this.scrollable = false,
    this.isInitialLoading = false,
    this.showsHeader = true,
  }) : resolvedTheme = theme;

  /// Whether there IS header content to show — `title` non-empty OR a `subtitle` exists
  /// (mirrors `LBPCarousel`'s `(title || subtitle) && (...)`, widgets.jsx 283). Renamed from
  /// `_showsHeader` (`rb-flutter-widget-carousel-header-visibility` D2) to free that name for the
  /// new HOST-FACING [showsHeader] opt-out — this getter is a pure CONTENT judgement, distinct
  /// from the host's "do I want a header at all" decision.
  bool get _hasHeaderContent =>
      title.isNotEmpty || (subtitle != null && subtitle!.isNotEmpty);

  /// The visible first N cards (FIXED SMALL set — the row is NOT scrollable). The
  /// real horizontal scroll is a host concern; this golden-safe surface caps at
  /// [maxCards] (parity with iOS / Android, which cap the static row likewise).
  List<LBVideoItem> get _visible =>
      videos.length <= maxCards ? videos : videos.sublist(0, maxCards);

  @override
  Widget build(BuildContext context) {
    // Three-state dispatch (widget-loading-placeholder, rb-flutter-widget-loading-
    // placeholder — design D4): first-load placeholder takes priority; then a
    // confirmed-empty list hides the ENTIRE widget (including the header — a
    // deliberate behavior change from the prior "empty list still shows a header /
    // empty shell"); otherwise the pre-existing rendering is unchanged.
    if (!isInitialLoading && videos.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      key: LbTestKeys.widgetCarousel,
      width: double.infinity,
      color: theme.background,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showsHeader && _hasHeaderContent) _header(),
          isInitialLoading ? _loadingRow(context) : _cardRow(context),
        ],
      ),
    );
  }

  // MARK: - Header row (title + subtitle + 查看更多 ›)
  //
  // Mirrors `LBPCarousel`'s header block (widgets.jsx 283-294): the title / subtitle
  // stack leading and the「查看更多 ›」accent link trailing, baseline-aligned.

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title (+ optional subtitle) stack — leading.
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16 * theme.fontScale,
                    fontWeight: FontWeight.w800,
                    color: theme.text,
                    letterSpacing: -0.2,
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11 * theme.fontScale,
                      fontWeight: FontWeight.w400,
                      // `theme` carries no dim token — derive a dim variant of the
                      // primary text (matches the design's `textDim`).
                      color: theme.text.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // 「查看更多 ›」accent link — trailing, host-wired (onSeeMore). Rendered ONLY when
          // host-wired (`onSeeMore != null`) — an un-wired link is a dead button
          // (dropin-hide-unwired-affordances-flutter). The leading 8-gap is part of the
          // conditional so the header has no trailing gap when hidden.
          if (onSeeMore != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              key: LbTestKeys.widgetSeeMore,
              onTap: onSeeMore,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  seeMoreLabel,
                  style: TextStyle(
                    fontSize: 12 * theme.fontScale,
                    fontWeight: FontWeight.w600,
                    color: theme.accent,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // MARK: - Loading placeholder (widget-loading-placeholder,
  // rb-flutter-widget-loading-placeholder)
  //
  // Mirrors the design's `LBPCarouselLoadingRow` (widgets.jsx 258-273): a real
  // `CarouselCardView` laid out but painted invisible (`Opacity(opacity: 0)`, the
  // Flutter analogue of CSS `visibility: hidden` — the child still occupies its
  // full layout box, only painting is suppressed) establishes the placeholder's
  // size, and a `LoadingMarkAnimationView` is centered over that box. The
  // placeholder's HEIGHT is taken from the existing [_cardHeight] formula (the
  // SAME one the windowed card row's sizer already reads) fed a single
  // deterministic placeholder card — not re-derived / hand-picked — so a future
  // change to the card's own layout (title line height / below-slot height /
  // thumbnail aspect ratio) keeps both call sites in sync automatically.

  /// A single deterministic placeholder card (`WidgetSeeds.vodWithGoods`) used ONLY
  /// to size the loading placeholder — its `goods` is deliberately `null` (the
  /// placeholder is never actually seen, `Opacity(opacity: 0)`), so
  /// `CarouselCardView`'s existing null-goods `below`-slot handling already gives a
  /// correct height regardless of `productCard` mode.
  static final List<LBVideoItem> _loadingPlaceholderCards = [
    WidgetSeeds.vodWithGoods,
  ];

  Widget _loadingRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: SizedBox(
        width: cardWidth,
        height: _cardHeight(context, _loadingPlaceholderCards),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Opacity(
              opacity: 0,
              child: CarouselCardView(
                theme: theme,
                item: WidgetSeeds.vodWithGoods,
                width: cardWidth,
                productCard: productCard,
              ),
            ),
            const LoadingMarkAnimationView(),
          ],
        ),
      ),
    );
  }

  // MARK: - Card row (plain Row of shared CarouselCardViews — NO scrollable)

  /// A single PLAIN `Row` of the visible first N shared `CarouselCardView`s
  /// (widgets.jsx 295-322), gap 12, leading padding 16 (mirrors the design's
  /// `padding: '0 16 6'`). NO ListView / SingleChildScrollView / Lazy*.
  ///
  /// The design's row is horizontally scrollable, so its full intrinsic width
  /// exceeds the host width — laying that in a plain `Row` under a width-bounded
  /// parent would overflow the `Flex`. To stay golden-safe WITHOUT a scrollable, the
  /// row is laid at its FULL intrinsic width inside an `OverflowBox` (unbounded
  /// width, top-leading) and CLIPPED to the host width by a `ClipRect` — so the first
  /// cards that fit are shown and the overflow is cleanly clipped (the off-screen
  /// cards live behind the host's REAL horizontal scroll). Same hidden-sizer + clip
  /// approach as the iOS over-wide card-row lesson; NO RenderFlex overflow, fully
  /// deterministic.
  Widget _cardRow(BuildContext context) {
    // Turnkey (`scrollable`) → ALL videos; windowed (default) → the first [maxCards].
    final cards = scrollable ? videos : _visible;
    // No videos → no row (defensive; the live / seed path always has cards).
    if (cards.isEmpty) return const SizedBox.shrink();
    final children = <Widget>[];
    for (var i = 0; i < cards.length; i++) {
      if (i > 0) children.add(const SizedBox(width: 12));
      final item = cards[i];
      children.add(CarouselCardView(
        key: LbTestKeys.carouselCard(i),
        theme: theme,
        item: item,
        goods: goodsFor?.call(item),
        width: cardWidth,
        live: live,
        productCard: productCard,
        onTap: onTapVideo == null ? null : () => onTapVideo!(item),
      ));
    }
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
    // Turnkey: ALL cards in a horizontal SingleChildScrollView (parity iOS ScrollableCarouselView).
    // Wrapped in a NotificationListener so a card scrolling back into view (rb-flutter-widget-
    // preview-scroll-end-visibility-refresh) does not wait out the `visibility_detector`'s
    // `updateInterval` — see [_flushVisibilityOnScrollEnd].
    if (scrollable) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: SizedBox(
          height: _cardHeight(context, cards),
          child: NotificationListener<ScrollNotification>(
            onNotification: _flushVisibilityOnScrollEnd,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: row,
            ),
          ),
        ),
      );
    }
    // A fixed-height sizer supplies the row's HEIGHT to the parent `Column` (the
    // off-screen `OverflowBox` reports zero height upward, so without a sizer the row
    // would collapse). It carries NO text (a bare `SizedBox`) so it never pollutes
    // `find.text` — the card titles / badges appear EXACTLY once (the visible row).
    // The visible row is laid at its full intrinsic width in an `OverflowBox`
    // (unbounded width, top-leading) and CLIPPED to the host width — first cards
    // shown, overflow cleanly clipped (off-screen cards live behind the host's REAL
    // horizontal scroll). Same hidden-sizer + clip approach as the iOS over-wide
    // card-row lesson; NO RenderFlex overflow, fully deterministic.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: SizedBox(
        // Span the full host width so the clipped row reveals as many cards as fit
        // (the `Stack` would otherwise shrink to the sizer's card width and clip to a
        // single card). Height-bounded by the text-free sizer below.
        width: double.infinity,
        child: Stack(
          children: [
            // Text-free height sizer — drives the row height only (= card height).
            SizedBox(height: _cardHeight(context, cards), width: cardWidth),
            // The clipped full-width row on top.
            Positioned.fill(
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: 0,
                  maxWidth: double.infinity,
                  child: row,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The full card height (thumbnail 9:16 + the gap + the single title line + the
  /// optional `below` product slot). It is the height bound for BOTH render branches —
  /// the turnkey `scrollable` branch's `SizedBox` and the windowed branch's text-free
  /// sizer (whose `OverflowBox` reports zero height upward) — so it MUST track what the
  /// card actually lays out. Mirrors `CarouselCardView`'s `Column`: `width*16/9` thumb +
  /// 8 gap + the title line's REAL measured height ([_titleLineHeight]) (+ its 8 gap +
  /// the below slot, which sits UNDER the title — design R17). [cards] is the exact list
  /// of items this row is about to render (`_cardRow`'s own `cards` local — turnkey
  /// `scrollable` → all `videos`, windowed → the capped `_visible` slice) — [_titleLineHeight]
  /// needs the REAL titles, not just the theme (see that method's doc for why).
  double _cardHeight(BuildContext context, List<LBVideoItem> cards) =>
      cardWidth * 16.0 / 9.0 +
      8 +
      _belowSlotExtent +
      _titleLineHeight(context, cards);

  /// The title line's REAL rendered height — the MAX, across every [cards] item this row
  /// is about to render, of a `TextPainter` measurement laid out against the item's OWN
  /// real `item.title` text, with the EXACT SAME effective style + `maxLines` / `ellipsis`
  /// / width constraint `CarouselCardView._title()` paints with. Supersedes the
  /// rb-flutter-carousel-card-height-cjk-overflow-fix approach of measuring a FIXED
  /// synthetic 2-glyph probe string (`'字A'`) instead of each row's own real content
  /// (rb-flutter-carousel-card-title-height-overflow-followup).
  ///
  /// **Why the fixed-probe approach (the prior fix) was still not sound, found by a real
  /// repro**: that fix's own reasoning — "a mixed CJK+ASCII probe captures the taller of
  /// whatever font this app/device selects for CJK text vs. the Latin font" — assumed a
  /// line's tallest font run is always one of exactly two candidates (Latin, or THE ONE
  /// CJK fallback font `字` happens to resolve to). A real backend title
  /// (`舉杯低卡蒟蒻凍☺︎`, `bsuqqM`, verified 2026-09-05 against a real `/sdk/widget` shop)
  /// disproved that assumption: it mixes CJK ideographs (which `字` DOES represent) with a
  /// trailing pictograph/symbol codepoint (`☺` + a variation selector) that Flutter's font
  /// fallback resolves to a DIFFERENT actual font than the probe ever exercises — so on a
  /// real device that font's line-height metric can still exceed the 2-glyph probe's
  /// measurement, even though the probe already "covers CJK." Reproduced live in
  /// `flutter/example` on an iOS Simulator: `RenderFlex#... A RenderFlex overflowed by
  /// 1.00 pixels on the bottom` on EXACTLY this item's `CarouselCardView`'s `Column`
  /// (`carousel_card.dart:318`) — the 2nd visible card in the row, matching the field
  /// report — while every OTHER card in the SAME row, sharing the SAME formula-derived
  /// row height, did NOT overflow. That per-card asymmetry is the tell: the gap is not
  /// "this app's ambient font is CJK-taller than Latin" (which would affect every card in
  /// the row identically, since they all share one row-height constant) — it is "THIS
  /// SPECIFIC card's specific title glyphs happen to select a font the probe's fixed
  /// glyph set never includes." No FIXED probe string, however cleverly chosen, can rule
  /// this out for every future title / script / symbol / emoji a shop might type — the
  /// only measurement that is provably always tall enough is one taken against each row's
  /// OWN actual titles.
  ///
  /// **The fix**: measure every VISIBLE card's real `item.title` (not a stand-in) and take
  /// the max — this is no longer an estimate that could, in principle, miss some future
  /// glyph/font combination; it is the literal same measurement `RenderParagraph` performs
  /// for that exact string, so it is definitionally never wrong for content this row is
  /// actually about to paint. The only class of mismatch this fix cannot see coming is a
  /// LATER content swap onto the SAME already-built row without a rebuild — which cannot
  /// happen here, because `CarouselView` is a `StatelessWidget` and `_cardHeight` recomputes
  /// from the current `videos`/`cards` on every rebuild the host causes (a new page loaded,
  /// a model update, etc.), never leaving a stale sizer paired with fresh content.
  ///
  /// EFFECTIVE, not merely byte-identical `TextStyle` VALUES: `Text()` resolves its
  /// painted style as `DefaultTextStyle.of(context).style.merge(style)` (Flutter's own
  /// `Text.build`) — `CarouselCardView.titleTextStyle(theme)` deliberately leaves
  /// `fontFamily` unset so it inherits whatever font the host/ambient `DefaultTextStyle`
  /// provides, exactly like every other `Text()` in this file. A raw `TextPainter` given
  /// that SAME style object with no context merge does NOT get that ambient font
  /// (empirically confirmed during the original apply — see git history). So this method
  /// merges with `DefaultTextStyle.of(context).style` first, mirroring `Text.build` exactly,
  /// before measuring.
  ///
  /// `maxLines: 1` + `ellipsis: '…'`, laid out at `maxWidth: cardWidth` — mirrors
  /// `_title()`'s own `Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, ...)`
  /// inside its `SizedBox(width: width, ...)` exactly (`RichText`/`Text.build` sets these
  /// same two `TextPainter` params whenever `overflow: TextOverflow.ellipsis` is given), so
  /// a title long enough to actually truncate is measured under the SAME constraint it will
  /// really be painted under, not an unconstrained single line.
  ///
  /// `textScaler: TextScaler.noScaling` is pinned here — the SAME isolation the title
  /// `Text()` pins (rb-flutter-carousel-card-title-height-overflow) — so this
  /// measurement stays immune to the host environment's ambient `MediaQuery` text
  /// scale, just like the real title paint.
  double _titleLineHeight(BuildContext context, List<LBVideoItem> cards) {
    final TextStyle effectiveStyle = DefaultTextStyle.of(context)
        .style
        .merge(CarouselCardView.titleTextStyle(theme));
    double maxHeight = 0;
    for (final item in cards) {
      // Defensive: substitute a single space for an empty title so this measurement
      // never depends on whether a zero-length TextSpan reports a font-metric-driven
      // line box on every engine/version (this repo's own test harness DOES report a
      // normal non-zero height for an empty TextSpan, so this has not been observed to
      // matter here — it costs nothing and removes the question).
      final String probe = item.title.isEmpty ? ' ' : item.title;
      final painter = TextPainter(
        text: TextSpan(text: probe, style: effectiveStyle),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: cardWidth);
      if (painter.height > maxHeight) {
        maxHeight = painter.height;
      }
    }
    return maxHeight;
  }

  /// Extra vertical extent contributed by the `product_card == 'below'` slot: the row's
  /// FIXED height plus the `Column` gap the card adds in front of that row (which sits
  /// under the title — design R17). Zero in every other mode, so `inside` / `hidden` /
  /// omitted keep the pre-existing bound.
  ///
  /// This is the Flutter analogue of the iOS hidden MEASURING CARD (`rb-ios-widget-
  /// product-card-modes` D8): the mode changes the card's height but the surface computes
  /// that height from a FORMULA, so forgetting this term does not shrink the card — it
  /// clips the `below` product row out of the row's viewport while the card itself looks
  /// fine in isolation. The `44` is read from `CarouselCardView.belowRowHeight` (never
  /// re-spelt here) so the two cannot drift apart.
  double get _belowSlotExtent =>
      normalizeProductCardMode(productCard) == LBProductCardMode.below
          ? CarouselCardView.belowRowHeight + 8
          : 0;

  // MARK: - Fixed presentation strings / caps

  /// Default section title (the design's `LBPCarousel` default,「精選影片」).
  static const String defaultTitle = '精選影片';

  /// Header「查看更多 ›」accent link label (widgets.jsx 292).
  static const String seeMoreLabel = '查看更多 ›';

  /// Max cards drawn in the FIXED static row (the rest live behind the host's real
  /// horizontal scroll). Parity with iOS / Android's capped static row.
  static const int maxCards = 6;
}

// MARK: - _flushVisibilityOnScrollEnd (rb-flutter-widget-preview-scroll-end-visibility-refresh)

/// `NotificationListener<ScrollNotification>.onNotification` for the turnkey `scrollable` row's
/// `SingleChildScrollView`: the instant the horizontal scroll settles, flush every pending
/// `VisibilityDetector` report (`VisibilityDetectorController.instance.notifyNow()`) instead of
/// waiting up to the package's `updateInterval` (500 ms by default). A card that scrolls back into
/// view therefore does not sit on a stale off-screen cover for that long before its
/// `LoopingVideoView` (Android `release` policy) re-creates its controller. A top-level function
/// (not a method) so it needs no `CarouselView` instance; returns `false` so the notification
/// keeps bubbling to any ancestor listener.
bool _flushVisibilityOnScrollEnd(ScrollNotification notification) {
  if (notification is ScrollEndNotification) {
    VisibilityDetectorController.instance.notifyNow();
  }
  return false;
}
