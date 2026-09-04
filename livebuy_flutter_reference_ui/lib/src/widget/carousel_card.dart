import 'package:flutter/widgets.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart' show LBVideoItem;

import '../playershell/upcoming_countdown_view.dart' show scheduledDate, scheduledTime;
import '../productsheets/sheet_scaffold.dart' show liveProductImage;
import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';
import 'looping_video_view.dart';
import 'widget_model.dart' show WidgetGoods, WidgetModel;

// CarouselCardView — family-5 shared 9:16 widget card primitive (LBPCarouselCard).
//
// Spec: `reference-ui-rendering/spec.md` (family-5 widget surfaces — "渲染 Flutter
// 共用 CarouselCardView 卡片 primitive，綁 LBVideoItem"). Flutter parity of iOS
// `CarouselCardView.swift` (rb-ios-widget) + Android `CarouselCardView.kt`
// (rb-android-widget). Design: `design/templates/minimal/widgets.jsx`
// `LBPCarouselCard` (lines 135-227).
//
// The single 9:16 thumbnail card shared by ALL four family-5 widget surfaces
// (carousel row, video-shop grid, floating live card, and — at a smaller scale —
// the minimized pill). It reproduces `LBPCarouselCard`'s structure:
//
//   • a 9:16 thumbnail placeholder (deterministic gradient chip — NO Image.network /
//     NetworkImage; the design's <ProductMock> becomes a LinearGradient + monogram),
//   • a KIND BADGE top-left, LIVE cards ONLY (`WidgetModel.isLive` — `liveStatus ==
//     1`): a red「LIVE」tag (static pulse dot) + an optional VIEWER-COUNT pill (see
//     below). VOD draws NO kind badge at all (rb-flutter-carousel-card-pin-viewers-
//     duration-removal, design R33 — the prior「▶ mm:ss」duration pill is REMOVED,
//     not replaced by anything),
//   • a VIEWER-COUNT pill, appended to the LIVE tag ONLY when `item.showPvNum == 1`:
//     a small person glyph + `item.watchNum` on a translucent-dark capsule (design
//     `LBPCarouselCard` 196-210, rb-flutter-carousel-card-pin-viewers-duration-removal),
//   • a PIN badge top-right, independent of the kind badge — drawn whenever
//     `item.pin == 1`, in ALL THREE kind states (LIVE / UPCOMING / VOD) simultaneously
//     with whatever else is on the thumbnail (design `LBPCarouselCard` 214-226,
//     rb-flutter-carousel-card-pin-viewers-duration-removal): a white pushpin/thumbtack
//     glyph, deliberately NOT the map-pin "balloon" marker shape used elsewhere in the
//     design system,
//   • a PRODUCT CARD whose placement depends on `product_card` (see below), drawn from
//     a reference-ui `WidgetGoods` value (Flutter core `LBVideoItem` has NO `goods`
//     field; supplied BY VALUE): thumb chip + `goods.name` +「NT$ price」(+ an optional
//     struck-through `goods.originalPrice` in `below` mode) — since design R33 a WHITE
//     card (`rgba(255,255,255,0.9)`, no border), not the historical dark-glass surface,
//   • the `LBVideoItem.title` BELOW the thumbnail (gated by `showTitle`, see below).
//
// (That is an ELEMENT LIST, not a vertical order — where the product card lands is
// decided by the mode below, and in `below` it lands UNDER the title.)
//
// PIN / VIEWER-COUNT FIELDS ARE NOT A PARITY DELTA (unlike `goods`, see below): Flutter
// core `LBVideoItem` (`/flutter/lib/src/models.dart`) already carries `pin: int` (0/1),
// `watchNum: int` and `showPvNum: int` (0/1) — the SAME three fields iOS / Android read
// off their own `LBVideoItem`. This primitive reads them DIRECTLY off the passed-in
// `item`, with no reference-ui-owned stand-in value type (unlike `WidgetGoods`, which
// exists ONLY because Flutter core has no `goods` field).
//
// TITLE VISIBILITY FLAG (`showTitle`, rb-flutter-floating-widget-hide-title): the title
// below the thumbnail is gated by a `showTitle: bool` constructor parameter (default
// `true` — carousel row / video-shop grid never pass it, so their pixels are unchanged).
// `FloatingWidgetView` passes `showTitle: false`, because the design source
// `LBPFloatingWidget` (`sdk-components.jsx` 590-712) draws NO title element at all — the
// floating surface's title was purely an artifact of reusing this shared card, not
// something the design ever asked for. `showTitle == false` removes the title AND its
// leading vertical gap from the widget tree entirely (not a blank placeholder — the
// card's intrinsic height genuinely shrinks). This flag is INDEPENDENT of the cover
// placeholder's monogram (`_monogram(item.title)`, drawn inside the thumbnail
// regardless of `showTitle` — an unrelated, always-rendered element).
//
// PRODUCT-CARD MODES (rb-flutter-widget-product-card-modes, design R14; the `below`
// PLACEMENT then reversed by R17 / rb-flutter-widget-product-card-below-slot-reposition;
// the COLOR of both `inside` and `below` then changed by R33 /
// rb-flutter-carousel-card-pin-viewers-duration-removal —
// `design/templates/minimal/widgets.jsx` `normalizeProductCardMode` / `LBPCardProductRow`
// / `LBPCardProductOverlay`). `POST /sdk/widget` carries a root `product_card` String
// (`inside` / `below` / `hidden`, backend default `inside`), raw-passed through the Flutter
// bridge (`fetchWidget` map) → `LBWidgetContent.productCard` → `WidgetModel.productCard`
// → this card's `productCard` parameter (`String?`):
//
//     inside (default)  a WHITE card overlay INSIDE the 9:16 thumbnail
//                       (`rgba(255,255,255,0.9)`, no border — design R33 retired the
//                       historical dark-glass treatment). `goods == null` → the whole
//                       block is not drawn.
//     below             the product card moves OUTSIDE the thumbnail, landing UNDER THE
//                       TITLE — the very bottom of the card (design R17, which reversed
//                       the earlier "between the thumbnail and the title" placement).
//                       It uses the SAME white-card vocabulary as `inside` since R33
//                       (`rgba(255,255,255,0.9)`, no border, `theme.text` name /
//                       `theme.sale` price / a faint struck-through original price).
//                       `goods == null` → an EQUAL-HEIGHT TRANSPARENT SPACER so cards in
//                       the same row / grid cell stay the same height — this spacer is
//                       the ONLY thing still pinned to the fixed `belowRowHeight`
//                       constant (see the note below).
//     hidden            no product card at all (neither overlay nor row, and NO spacer —
//                       every card in the surface is equally card-less).
//
// The LIVE tag / kind badge / pin badge / upcoming veil / title are IDENTICAL in all
// three modes.
//
// `below` ROW HEIGHT SINCE R33 (rb-flutter-carousel-card-pin-viewers-duration-removal):
// design R33 DROPPED the R14 "a BOUND (`goods != null`) row is ALSO pinned to the fixed
// `belowRowHeight` constant, regardless of content" invariant — a bound row now sizes to
// its OWN content (bounded below by its 36px thumb chip), and is NO LONGER forced to
// `belowRowHeight`. Only the NO-GOODS SPACER (`goods == null`) still uses the fixed
// constant — it has no content to size to, and dropping its fixed height would remove
// the very thing it exists for (equal-height placeholding). A bound row and its sibling
// unbound spacer MAY therefore now differ in height; this is the accepted design
// decision (see `design/contract/claude-design-sync.md` R33), not a rendering bug. In
// `inside` / `hidden` the below slot is not present in the widget tree AT ALL (not a
// zero-height node), so the `inside` layout is byte-identical to before this mode
// existed.
//
// FALLBACK IS THIS LAYER'S JOB: core deliberately does NOT substitute the backend default
// (`null` means "the backend sent nothing", which is a DIFFERENT fact from `"inside"`), and
// neither does the view-model layer. [normalizeProductCardMode] is the SINGLE pure entry
// point that maps anything that is not exactly `'below'` / `'hidden'` (including `null`,
// `''`, whitespace-padded and differently-cased spellings, and any unknown string) to
// `inside`. It MUST NOT be duplicated in the build body, and the normalized value MUST NOT
// be written back into `WidgetModel` / `LBWidgetContent` / core.
//
// THREE-WAY KIND DERIVATION (LIVE → UPCOMING → VOD): the core `LBVideoItem` carries
// `liveStatus: int` + `publishAt: String` (UTC+8), which is enough to render LIVE /
// UPCOMING / VOD (Flutter parity of iOS / Android `CarouselCardView`):
//   `liveStatus == 1`                       → LIVE (red LIVE tag + optional viewer-
//                                             count pill, NO duration pill).
//   `liveStatus == 0` && future `publishAt` → UPCOMING (直播預告): rgba(0,0,0,0.25)
//                                             mask + centred date + big time (the
//                                             design's upcoming treatment, replacing
//                                             the top-left kind badge).
//   otherwise (incl. liveStatus==0 with     → VOD  (NO kind badge at all — design R33
//      empty/past publishAt, or replay)                retired the duration pill without
//                                             replacing it).
// `live_status == 0` is the backend upcoming signal; requiring a FUTURE `publishAt`
// (`publishAtInFuture`, reused from the template module) keeps every existing VOD card
// (past / empty publishAt) on the VOD path. The `replay` nuance still collapses into VOD.
//
// SUB-VIEW INPUT PATTERN (parity with families 1-4): theme FIRST → snapshot values
// by value (`item`, optional `goods`, optional `width`) → interaction callback
// (`onTap`) trailing with a no-op default. One-way data flow: this primitive reads
// ONLY its passed-in values; it never reaches back into `WidgetModel` /
// `DefaultWidgetTemplate`, holds NO second copy of state, calls NO core `simulate*`,
// uses NO `ListView` / `GridView` / `SingleChildScrollView`. It draws the real cover
// (`Image.network`) ONLY on the live runtime path (`live == true`, gated by
// `liveProductImage`); the demo / golden path (`live == false`, default) draws the
// deterministic placeholder ONLY (no network → byte-stable goldens). The tap exit is
// host-wired (`onTap`); the card NEVER opens the player itself.

// MARK: - LBProductCardMode — the single fallback entry point (normalizeProductCardMode)

/// Where (and whether) the widget card draws its product card. The Flutter counterpart
/// of the design's `LB_PRODUCT_CARD_MODES` + `normalizeProductCardMode`
/// (`design/templates/minimal/widgets.jsx`), of iOS `LBProductCardMode` and of Android
/// `LBProductCardMode`.
///
/// A Dart ENHANCED ENUM: the wire value lives on the enum itself ([wire]), exactly like
/// iOS's `String` raw value and Android's `wireValue`, so the raw `product_card` string
/// has ONE home. The wire value (`product_card`) is a raw passthrough `String?` all the
/// way from core; this type is where it becomes a closed set, so the view can `switch`
/// exhaustively and the compiler flags every unhandled site if the domain ever grows.
enum LBProductCardMode {
  /// A WHITE card overlay INSIDE the 9:16 thumbnail (backend default, and the fallback
  /// for everything unrecognized) — `rgba(255,255,255,0.9)`, no border (design R33; the
  /// historical dark-glass treatment is retired).
  inside('inside'),

  /// A white product row OUTSIDE the thumbnail, under the title (the very bottom of the
  /// card) — the SAME white-card vocabulary as `inside` since design R33.
  below('below'),

  /// No product card at all.
  hidden('hidden');

  const LBProductCardMode(this.wire);

  /// The backend wire spelling of this mode (`product_card` value).
  final String wire;
}

/// THE ONLY place a raw `product_card` value becomes a mode. Mirrors the design's
/// `normalizeProductCardMode(raw)` (`raw === 'below' || raw === 'hidden' ? raw :
/// 'inside'`) EXACTLY — the comparison is STRICT, with NO trimming and NO case folding,
/// so `' below '` / `'BELOW'` fall back to [LBProductCardMode.inside] just like any other
/// unknown string. Being deliberately as strict as the design keeps the four platforms'
/// fallback boundary identical precisely when the backend emits something malformed,
/// which is when a divergence would be hardest to spot.
///
/// `null` (the backend sent nothing — absent key / JSON null / `/sdk/widget/live` /
/// nothing loaded yet) also lands on [LBProductCardMode.inside], WITHOUT that default
/// ever being written back into the view-model (core's `null` semantics are preserved).
LBProductCardMode normalizeProductCardMode(String? raw) {
  if (raw == LBProductCardMode.below.wire) return LBProductCardMode.below;
  if (raw == LBProductCardMode.hidden.wire) return LBProductCardMode.hidden;
  return LBProductCardMode.inside;
}

/// The shared family-5 widget card (`LBPCarouselCard`): a 9:16 thumbnail
/// placeholder + LIVE / VOD kind badge + a product card placed per `product_card`
/// (`inside` overlay / `below` row / `hidden`) + the title below. `onTap` is a host-wired
/// exit (the card never opens the player itself); it renders correctly with `onTap` null
/// (demo / golden).
class CarouselCardView extends StatelessWidget {
  /// The resolved reference-ui theme (FIRST — SUB-VIEW INPUT PATTERN). The card's
  /// title AND (since design R33) the product-card overlays use `theme.text` /
  /// `theme.sale`; the LIVE tag / viewer pill / pin badge / upcoming mask use FIXED
  /// design colors independent of the theme.
  final ReferenceUITheme theme;

  /// The video this card renders (read-only — `title` / `duration` / `liveStatus` /
  /// `cover` / `pin` / `watchNum` / `showPvNum`). Unlike `goods` (below), these three
  /// last fields ARE present on the Flutter core `LBVideoItem`
  /// (`/flutter/lib/src/models.dart`) — NOT a parity delta, read directly off `item`
  /// (rb-flutter-carousel-card-pin-viewers-duration-removal). When [live] is false
  /// (demo / golden) `cover` is NOT fetched (the deterministic placeholder draws). This
  /// layer never mutates / re-fetches.
  final LBVideoItem item;

  /// Optional product overlay (reference-ui `WidgetGoods` — Flutter core
  /// `LBVideoItem` has no `goods` field). When non-null the bottom white-card
  /// overlay is drawn; null → no overlay (a live `LBVideoItem` carries none).
  final WidgetGoods? goods;

  /// Card width (logical px). Defaults to the design's `132`. The thumbnail height
  /// is derived 9:16. The minimized surface passes a smaller width (e.g. 96).
  final double width;

  /// Whether to load the real cover photo over the placeholder. `false` (DEFAULT —
  /// demo / golden) → ONLY the deterministic placeholder draws (no network → byte-
  /// stable goldens). `true` (host runtime) → when `item.cover` is a non-empty
  /// http(s) URL, `Image.network(item.cover)` overlays the placeholder (loading /
  /// error fall back to the placeholder). Parity with iOS `CarouselCardView.live`
  /// gating `item.cover` (rb-ios-product-real-images / widget `live` flag).
  final bool live;

  /// RAW `product_card` wire value (`WidgetModel.productCard`), carried verbatim — this
  /// card does NOT expect a pre-normalized value, so every call site is a plain hand-off
  /// and the fallback stays in ONE place ([normalizeProductCardMode]).
  ///
  /// `null` (the DEFAULT, and what every pre-existing call site passes) → `inside`, i.e.
  /// the historical unconditional white-card overlay, pixel-for-pixel unchanged (bar the
  /// R33 recolor described on [LBProductCardMode.inside]).
  /// `'below'` moves the product card outside the thumbnail, under the title (the very
  /// bottom of the card); `'hidden'` draws none at all. Anything else falls back to
  /// `inside`.
  ///
  /// The normalized value is NEVER written back into `WidgetModel` / `LBWidgetContent` /
  /// core (the `null` there means "the backend sent nothing", a DIFFERENT fact from the
  /// backend sending `'inside'`).
  final String? productCard;

  /// Whether to render the title below the thumbnail (rb-flutter-floating-widget-hide-
  /// title). `true` (the DEFAULT, and what `CarouselView` / `VideoShopGridView` both
  /// implicitly pass by omission) → the title renders exactly as before this flag
  /// existed, including its leading vertical gap. `false` (used ONLY by
  /// `FloatingWidgetView`) → the title AND its leading gap are absent from the widget
  /// tree entirely — not a blank / zero-content placeholder, the card's intrinsic
  /// height genuinely shrinks. Independent of the cover placeholder's monogram (which is
  /// always derived from `item.title`'s first character regardless of this flag).
  final bool showTitle;

  /// Card tap → host-wired exit (→ host → core open player for `item.id`). null for
  /// demo / golden instances — the card is inert. NEVER opens the player / calls
  /// core `simulate*` itself.
  final VoidCallback? onTap;

  const CarouselCardView({
    super.key,
    required this.theme,
    required this.item,
    this.goods,
    this.width = 132,
    this.live = false,
    this.productCard,
    this.showTitle = true,
    this.onTap,
  });

  /// The resolved product-card mode. The ONE call of [normalizeProductCardMode] in this
  /// widget — every branch below switches on this, never on the raw string.
  LBProductCardMode get _productCardMode => normalizeProductCardMode(productCard);

  // Both gates below switch EXHAUSTIVELY over [LBProductCardMode] via a Dart 3 switch
  // EXPRESSION, so growing the domain is a COMPILE ERROR here rather than a silently
  // unhandled mode (the Dart equivalent of iOS's `default`-less `switch` / Kotlin's
  // `else`-less `when` expression). The raw wire string is never compared outside
  // [normalizeProductCardMode].

  /// `inside` → the white card overlay is drawn inside the 9:16 thumbnail.
  bool get _drawsInsideOverlay => switch (_productCardMode) {
        LBProductCardMode.inside => true,
        LBProductCardMode.below => false,
        LBProductCardMode.hidden => false,
      };

  /// `below` → a product row (or its equal-height transparent spacer) is drawn under the
  /// title, at the very bottom of the card.
  bool get _drawsBelowRow => switch (_productCardMode) {
        LBProductCardMode.inside => false,
        LBProductCardMode.below => true,
        LBProductCardMode.hidden => false,
      };

  /// Whether this card is LIVE (shared single source — `WidgetModel.isLive`,
  /// `liveStatus == 1`).
  bool get _isLive => WidgetModel.isLive(item);

  /// Whether this card is UPCOMING (直播預告): `liveStatus == 0` AND the backend's
  /// canonical scheduled-live signal **`type == 2`** AND `publishAt` is parseable (so a
  /// date can be shown). Mirrors iOS / Android `CarouselCardView.isUpcoming`
  /// (rb-flutter-widget-upcoming-type，問題 6): the prior future-`publishAt` heuristic is
  /// REPLACED by `type == 2` — a scheduled live whose start time has PASSED but is not yet
  /// live (`liveStatus == 0`, `type == 2`) stays upcoming, and a regular VOD (`type == 1`)
  /// never misclassifies. Also drops the `DateTime.now()` dependency → deterministic.
  bool get _isUpcoming =>
      !_isLive && item.type == 2 && scheduledDate(item.publishAt).isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final card = SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _thumbnail(),
          // `showTitle` ONLY (rb-flutter-floating-widget-hide-title) — the title AND its
          // leading gap are gated TOGETHER in one collection-if (mirroring the `below`
          // slot's own shape immediately below), so `showTitle == false` leaves NO dead
          // space where the gap would otherwise sit. `true` (the default) renders exactly
          // as before this flag existed.
          if (showTitle) ...[
            const SizedBox(height: 8),
            _title(),
          ],
          // `below` ONLY — the product card sits UNDER THE TITLE, at the very bottom of
          // the card (design `LBPCarouselCard` 223-224: thumbnail → title → product row;
          // ledger R17, 2026-08-11 — this REVERSES the 2026-08-05 decision that put the
          // row between the thumbnail and the title). The slot carries its own leading
          // gap, so the `below` card grows by exactly `<slot height> + 8` — no longer a
          // fixed increment for a BOUND row since design R33 (see the file-header note on
          // `below` ROW HEIGHT SINCE R33). `inside` / `hidden` contribute NOTHING here
          // (the slot is absent from the tree, not a zero-height node), so the `Column`
          // lays out exactly as it did before this mode existed. When `showTitle ==
          // false` (floating only), this slot lands directly under the thumbnail instead
          // of under the title — floating never sets `productCard` though, so this
          // combination is exercised by tests but not by any real caller.
          if (_drawsBelowRow) ...[
            const SizedBox(height: 8),
            _belowProductSlot(),
          ],
        ],
      ),
    );
    // Tap is host-wired (no-op when null). GestureDetector keeps the inert demo /
    // golden path pixel-identical (no ripple / focus chrome).
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: card,
    );
  }

  // MARK: - Thumbnail (9:16, placeholder + kind/pin badges + product overlay)

  Widget _thumbnail() {
    final h = width * 16.0 / 9.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width,
        height: h,
        child: Stack(
          children: [
            // 9:16 media layer, priority preview → cover → placeholder, parity iOS
            // `mediaThumbnail` / Android / RN `CarouselCardView`. rb-flutter-widget-card-
            // looping-preview: `live == true` + non-empty `item.preview` → a muted, looping
            // `LoopingVideoView` (animated preview) over the placeholder. Otherwise the existing
            // `liveProductImage`: `live == true` + non-empty cover URL → real cover; `live ==
            // false` (demo / golden) → placeholder ONLY (no network / no video controller →
            // byte-stable goldens).
            Positioned.fill(
              child: (live && item.preview.isNotEmpty)
                  ? LoopingVideoView(uri: item.preview)
                  : liveProductImage(
                      live: live,
                      url: item.cover,
                      placeholder: _coverPlaceholder(),
                      // Whole cover visible (letterbox) — iOS RemoteStillImageView default scaleAspectFit.
                      fit: BoxFit.contain,
                    ),
            ),
            // UPCOMING (直播預告): a full-bleed rgba(0,0,0,0.25) dark mask + a centred
            // date (small) + big time, REPLACING the top-left kind badge (the centre
            // overlay IS the indicator). Date / time are pure string reformats of
            // publishAt (shared with UpcomingCountdownView) → deterministic.
            if (_isUpcoming)
              Positioned.fill(child: _upcomingOverlay())
            else if (_isLive)
              // Kind badge top-left: LIVE red tag (+ optional viewer-count pill). VOD
              // draws NO kind badge at all since design R33
              // (rb-flutter-carousel-card-pin-viewers-duration-removal retired the
              // historical「▶ mm:ss」duration pill without a replacement).
              Positioned(top: 6, left: 6, child: _kindBadge()),
            // PIN badge top-right (`item.pin == 1`) — independent of the kind badge /
            // upcoming overlay above: all THREE kind states (LIVE / UPCOMING / VOD) can
            // carry it simultaneously (design R33,
            // rb-flutter-carousel-card-pin-viewers-duration-removal).
            if (item.pin == 1) Positioned(top: 6, right: 6, child: _pinBadge()),
            // Bottom WHITE product overlay (design R33 retired the historical dark-glass
            // treatment) — `inside` mode ONLY (`below` draws the row outside the
            // thumbnail, `hidden` draws nothing), and only when goods != null (an
            // unbound card keeps a clean thumbnail).
            if (_drawsInsideOverlay && goods != null)
              Positioned(
                left: 6,
                right: 6,
                bottom: 6,
                child: _productOverlay(goods!),
              ),
          ],
        ),
      ),
    );
  }

  /// 9:16 deterministic cover placeholder — gradient + monogram of the title (no
  /// remote image; host can swap in a real cover). Mirrors the design's
  /// `<ProductMock>` rounded media chip.
  Widget _coverPlaceholder() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A3A44), Color(0xFF111118)],
        ),
      ),
      child: Center(
        child: Text(
          _monogram(item.title),
          style: TextStyle(
            fontSize: 28 * theme.fontScale,
            fontWeight: FontWeight.w900,
            color: const Color(0xFFFFFFFF).withValues(alpha: 0.85),
          ),
        ),
      ),
    );
  }

  // MARK: - Upcoming overlay (直播預告: dark mask + centre date + big time)

  /// The upcoming (直播預告) treatment for the card thumbnail (design `LBPCarouselCard`
  /// upcoming): a full-bleed `rgba(0,0,0,0.25)` dark mask over the thumbnail + a
  /// centred「scheduled DATE」(small) +「scheduled TIME」(big), REPLACING the VOD
  /// duration pill. NO「即將開播」label and NO ticking countdown — date / time are pure
  /// string reformats of `publishAt` (shared with `UpcomingCountdownView`) →
  /// deterministic. Flutter parity of iOS / Android `CarouselCardView` upcoming overlay.
  Widget _upcomingOverlay() {
    final date = scheduledDate(item.publishAt);
    return ColoredBox(
      key: LbTestKeys.cardUpcomingOverlay,
      color: const Color(0x40000000), // black @ 0.25
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (date.isNotEmpty)
                Text(
                  date,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11 * theme.fontScale,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFFFFFFFF),
                  ),
                ),
              if (date.isNotEmpty) const SizedBox(height: 8),
              Text(
                scheduledTime(item.publishAt),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26 * theme.fontScale,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFFFFFFF),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // MARK: - Kind badge (LIVE tag + optional viewer-count pill; VOD/UPCOMING have none)

  /// LIVE-only: the red LIVE tag, plus an optional viewer-count pill when
  /// `item.showPvNum == 1` (design `LBPCarouselCard` 183-212). Only reached from the
  /// `_isLive` branch in [_thumbnail] — VOD / UPCOMING never call this (design R33
  /// retired the VOD duration pill without a top-left replacement).
  Widget _kindBadge() {
    return KeyedSubtree(
      key: LbTestKeys.cardKindBadge,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _liveTag(),
          if (_showsViewerBadge) ...[
            const SizedBox(width: 6),
            _viewerBadge(),
          ],
        ],
      ),
    );
  }

  /// LIVE red tag (LBPCarouselCard 184-196): a static pulse dot +「LIVE」on the
  /// brand-red surface. The pulse animation is drawn statically (golden-safe).
  Widget _liveTag() {
    return Container(
      key: LbTestKeys.cardLiveBadge,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _liveRed,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: const BoxDecoration(
              color: Color(0xFFFFFFFF),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            liveLabel,
            style: TextStyle(
              fontSize: 10 * theme.fontScale,
              fontWeight: FontWeight.w900,
              color: const Color(0xFFFFFFFF),
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  // MARK: - Viewer-count pill (LIVE only, gated by `item.showPvNum`)

  /// Whether the viewer-count pill is shown next to the LIVE tag: `item.showPvNum ==
  /// 1` (the CLAUDE.md Bool-as-Int convention — core encodes bool flags as 0/1 ints).
  /// Only meaningful when [_isLive] (the sole caller, [_kindBadge], is only reached on
  /// the LIVE branch). The design's own demo leaves `item.viewers` ungated (a plain
  /// truthy check); this reference-ui layer instead gates on the backend's own
  /// visibility flag, per the brief's guidance to mirror the main player header's
  /// `viewerCountVisible`-style convention (`design/contract/claude-design-sync.md`
  /// R33 leaves the flag deliberately unwired in its own demo).
  bool get _showsViewerBadge => item.showPvNum == 1;

  /// Viewer-count pill (LBPCarouselCard 199-211): a small person glyph + `item.watchNum`
  /// on a translucent-black, rounded capsule. Renders the raw count verbatim (no
  /// compact "12.3K" formatting — the design shows the bare number).
  ///
  /// The design's capsule also carries a `backdropFilter: blur(6px)` — this file has NO
  /// existing `BackdropFilter` precedent (the `below`/`inside` "glass" treatments were
  /// always a translucent solid color, never a real blur), so this pill follows the
  /// same established simplification rather than introducing the file's first
  /// `BackdropFilter` (which would also need a `ClipRRect` wrapper and is not practical
  /// to hand-verify pixel-for-pixel in a golden here).
  Widget _viewerBadge() {
    return Container(
      key: LbTestKeys.cardViewerBadge,
      padding: const EdgeInsets.fromLTRB(5, 2, 7, 2),
      decoration: BoxDecoration(
        color: const Color(0xFF000000).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(_personGlyph, size: 9, color: Color(0xFFFFFFFF)),
          const SizedBox(width: 3),
          Text(
            '${item.watchNum}',
            style: TextStyle(
              fontSize: 10 * theme.fontScale,
              fontWeight: FontWeight.w700,
              color: const Color(0xFFFFFFFF),
            ),
          ),
        ],
      ),
    );
  }

  // MARK: - Pin badge (top-right, ALL kind states, `item.pin == 1`)

  /// 置頂 badge (LBPCarouselCard 214-226): a white pushpin/thumbtack glyph, top-right,
  /// independent of the kind badge / upcoming overlay — LIVE / UPCOMING / VOD can all
  /// carry it simultaneously. Deliberately NOT the map-pin "balloon" marker shape used
  /// elsewhere in the design system (Material's `Icons.location_on` / the design's own
  /// separately-defined `pinFill` icon — see `claude-design-sync.md` R33 for why the
  /// design itself keeps this as an inline SVG path rather than reusing `pinFill`). See
  /// [_PinIconPainter] for why this is a hand-transcribed `CustomPainter` path rather
  /// than a Material `Icon`.
  Widget _pinBadge() {
    return const KeyedSubtree(
      key: LbTestKeys.cardPinBadge,
      child: SizedBox(
        width: 16,
        height: 16,
        child: CustomPaint(painter: _PinIconPainter()),
      ),
    );
  }

  // MARK: - Bottom white product overlay (`inside` mode, goods != null)

  /// White product overlay (LBPCardProductOverlay, design R33): a 44×44 thumb chip + the
  /// product name (1-line) +「NT$ {price}」, on a `rgba(255,255,255,0.9)` card with no
  /// border. `WidgetGoods.price` is a `String` (raw) — prefixed verbatim with「NT$ 」.
  Widget _productOverlay(WidgetGoods goods) {
    return Container(
      padding: const EdgeInsets.fromLTRB(0, 0, 7, 0),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          // 44×44 product chip (grown from 24×24 by design R33): gradient placeholder +
          // (live) the real goods.pic over it (parity iOS productThumb). live==false
          // (demo/golden) → placeholder only.
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 44,
              height: 44,
              child: liveProductImage(
                live: live,
                url: goods.pic,
                fit: BoxFit.contain,
                placeholder: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFFD7A8), Color(0xFFE27D5A)],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  goods.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10 * theme.fontScale,
                    fontWeight: FontWeight.w600,
                    // The RESOLVED theme text (the design's `#1a1a1a`) — white card
                    // since R33, no longer white text on dark glass. Same source the
                    // `below` row's name and the card's own `title` use.
                    color: theme.text,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _displayPrice(goods.price),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10 * theme.fontScale,
                    fontWeight: FontWeight.w900,
                    // `theme.sale` — since R33 the price is no longer plain white.
                    color: saleColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // MARK: - Under-title product row (`below` mode, LBPCardProductRow)

  /// The `below` slot: the white product row, or — when the card has no bound goods —
  /// a TRANSPARENT SPACER fixed to [belowRowHeight]. The spacer (the design's
  /// `aria-hidden` empty div) is what keeps NO-GOODS cards in the same carousel row /
  /// grid cell the same height without drawing an empty frame. A fixed-size `SizedBox`,
  /// NOT a `Spacer` (which would absorb the enclosing `Column`'s free space).
  ///
  /// Since design R33 this is NO LONGER also true of a BOUND row: `_belowProductRow`
  /// sizes to its own content now, so a card WITH goods and a sibling card WITHOUT
  /// goods may differ in height — an accepted design decision
  /// (`design/contract/claude-design-sync.md` R33), not a regression of this spacer's
  /// own fixed-height guarantee.
  Widget _belowProductSlot() {
    final g = goods;
    if (g == null) {
      return SizedBox(
        key: LbTestKeys.cardBelowProductSpacer,
        width: width,
        height: belowRowHeight,
      );
    }
    return _belowProductRow(g);
  }

  /// White product row (`LBPCardProductRow`, widgets.jsx 70-106, design R33): a 36×36
  /// product thumb + the product name (1-line) + the sale price + an optional
  /// struck-through original price, on a `rgba(255,255,255,0.9)` card with no border.
  /// Height is CONTENT-DRIVEN since R33 — no longer the fixed [belowRowHeight] (see the
  /// file-header note on `below` ROW HEIGHT SINCE R33 / [_belowProductSlot]'s doc).
  Widget _belowProductRow(WidgetGoods goods) {
    return Container(
      key: LbTestKeys.cardBelowProductRow,
      width: width,
      // NO fixed `height` any more (design R33 dropped the R14 "a bound row is ALSO
      // pinned to belowRowHeight" invariant) — this Container now sizes to its own
      // content, bounded below by the 36px thumb chip. Only the no-goods SPACER (see
      // `_belowProductSlot`) still uses `belowRowHeight`.
      padding: const EdgeInsets.fromLTRB(0, 0, 7, 0),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          // 36×36 product chip (grown from 32×32 by design R33): gradient placeholder +
          // (live) the real goods.pic over it — the SAME `live` gate as the `inside`
          // overlay's chip.
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              width: 36,
              height: 36,
              child: liveProductImage(
                live: live,
                url: goods.pic,
                fit: BoxFit.contain,
                placeholder: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFFFD7A8), Color(0xFFE27D5A)],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  goods.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11 * theme.fontScale,
                    fontWeight: FontWeight.w600,
                    // The RESOLVED theme text (the design's `theme.surface.text` /
                    // `#1a1a1a`) — the same source the card's own `title` is painted
                    // with, and (since R33) the SAME source the `inside` overlay's name
                    // now uses too.
                    color: theme.text,
                  ),
                ),
                const SizedBox(height: 1),
                _belowPriceLine(goods),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The `below` row's price line: sale price + optional struck-through original price,
  /// baseline-aligned like the design. Both run through the same `_displayPrice`
  /// de-duplication; an empty `originalPrice` draws nothing.
  ///
  /// The sale price is NOT shrinkable: at the design's 132pt card width the two prices
  /// together can exceed the text column, and if BOTH could shrink they would both
  /// truncate to「NT$…」and the card would show no readable figure at all. Only the
  /// secondary struck-through original price absorbs the squeeze (parity iOS
  /// `.layoutPriority(1)` / Android `weight(1f, fill = false)` / RN `flexShrink: 1`).
  Widget _belowPriceLine(WidgetGoods goods) {
    final struck = strikePrice(goods.originalPrice);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          _displayPrice(goods.price),
          maxLines: 1,
          style: TextStyle(
            fontSize: 11 * theme.fontScale,
            fontWeight: FontWeight.w900,
            color: saleColor,
          ),
        ),
        if (struck != null) ...[
          const SizedBox(width: 4),
          Flexible(
            fit: FlexFit.loose,
            child: Text(
              struck,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10 * theme.fontScale,
                fontWeight: FontWeight.w600,
                color: textFaint,
                decoration: TextDecoration.lineThrough,
                decorationColor: textFaint,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // MARK: - Title (below thumbnail)

  /// The video title below the thumbnail (LBPCarouselCard 215-221), 1-line clamp,
  /// painted with `theme.text` (the card sits on the host surface).
  Widget _title() {
    return SizedBox(
      width: width,
      child: Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        // `_cardHeight` (carousel.dart) measures this line's real height with a
        // `TextPainter` laid out against [titleTextStyle] (rb-flutter-carousel-
        // card-height-cjk-overflow-fix) — this `Text()` MUST keep using the same
        // style so the measurement stays byte-identical to what actually paints.
        // Without pinning textScaler here, a host device / app's environment
        // text-scale (MediaQuery.textScalerOf) stacks on top of that
        // measurement and can push the rendered title taller than the
        // fixed-height sizer allows, overflowing the card's Column (RenderFlex
        // "BOTTOM OVERFLOWED" debug-only warning; content is still clipped in
        // release). `theme.fontScale` itself still scales the title normally —
        // only the host environment's own scaling is excluded.
        textScaler: TextScaler.noScaling,
        style: titleTextStyle(theme),
      ),
    );
  }

  /// The title's `TextStyle` — THE SINGLE SOURCE OF TRUTH shared by [_title]'s
  /// `Text()` and `CarouselView._titleLineHeight`'s `TextPainter` measurement
  /// (rb-flutter-carousel-card-height-cjk-overflow-fix). Both call sites MUST
  /// use byte-identical styles or the measurement is meaningless — this static
  /// helper is the one place the style is spelled out, mirroring this file's
  /// own established discipline elsewhere (e.g. [belowRowHeight]'s "SHALL 引用
  /// 同一個常數，MUST NOT 在此另寫字面值").
  static TextStyle titleTextStyle(ReferenceUITheme theme) {
    return TextStyle(
      fontSize: 12 * theme.fontScale,
      fontWeight: FontWeight.w600,
      color: theme.text,
    );
  }

  // MARK: - Helpers

  /// First non-whitespace character of a title, uppercased, for the placeholder
  /// monogram. Falls back to a play glyph stand-in when empty.
  static String _monogram(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return '▶';
    return trimmed.substring(0, 1).toUpperCase();
  }

  // MARK: - Decorative design tokens (literal widgets.jsx colors)

  /// Brand-red LIVE tag surface (`#F03246`, LBPCarouselCard 185).
  static const Color _liveRed = Color(0xFFF03246);

  // Product-card tokens (design R33, rb-flutter-carousel-card-pin-viewers-duration-
  // removal). `inside` and `below` now share ONE white-card vocabulary — the historical
  // dark-glass overlay and the `below` row's separate elevated-surface tokens
  // (`theme.surface.bgElev` fill / `theme.surface.stroke` border) are RETIRED; both
  // surfaces now paint `rgba(255,255,255,0.9)` with NO border, pinned inline at each
  // usage site (`const Color(0xFFFFFFFF).withValues(alpha: 0.9)`, matching this file's
  // existing translucent-literal pattern) rather than named here. The product NAME on
  // BOTH surfaces uses the RESOLVED `theme.text` (the design's `theme.surface.text` /
  // `#1a1a1a`), matching how the card's own `title` is painted; the price on BOTH
  // surfaces uses [saleColor] (`theme.sale`) — `inside`'s price is no longer plain white.
  //
  // NOTE: `ProductListView` carries an older sale red (`#E0334B`); the value below is the
  // one `tokens.jsx` currently defines for `theme.sale`. Converging the two is a separate
  // token-drift question and is NOT done here (it would move existing family-3 goldens).

  /// Fixed height of the `below` row's NO-GOODS transparent spacer (design
  /// `LB_BELOW_ROW_H = 44`). Design R33 dropped the R14 invariant that a BOUND
  /// (`goods != null`) row is ALSO forced to this constant — a bound row now sizes to
  /// its own content, so this constant is ONLY still authoritative for the spacer.
  static const double belowRowHeight = 44;

  /// `theme.sale` — both product-card surfaces' sale price (since design R33, `inside`
  /// included — it used to be plain white).
  static const Color saleColor = Color(0xFFF03246);

  /// `theme.surface.textFaint` — the `below` row's struck-through original price.
  static const Color textFaint = Color(0xFF9A9BA5);

  /// Person glyph for the LIVE-only viewer-count pill. `Icons.person` codepoint —
  /// declared inline to avoid a material import in a widgets-only file (the same
  /// discipline this file's now-removed VOD duration pill's play glyph followed).
  static const IconData _personGlyph =
      IconData(0xe491, fontFamily: 'MaterialIcons');

  /// De-duplicate the currency prefix on a raw wire price (parity iOS `displayPrice`): trim;
  /// empty → `''`; prefix「NT$ 」ONLY when the first char is a digit (a bare number) — otherwise
  /// the value already carries a currency symbol (e.g. `NT$590`) → render verbatim (never
  /// `NT$ NT$590`).
  static String _displayPrice(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final int first = trimmed.codeUnitAt(0);
    final bool isDigit = first >= 0x30 && first <= 0x39;
    return isDigit ? pricePrefix + trimmed : trimmed;
  }

  /// The `below` row's struck-through ORIGINAL price, or `null` when there is nothing to
  /// strike. Reuses [_displayPrice] (same currency de-duplication) and maps the
  /// "trimmed to empty" case (including the `WidgetGoods.originalPrice` default `''`) to
  /// `null`, so the caller draws NO struck-through label at all rather than an empty one.
  /// Only the `below` row shows an original price — the `inside` overlay never has
  /// (design `LBPCardProductOverlay` has no `was`). Parity iOS / Android / RN
  /// `strikePrice`.
  static String? strikePrice(String raw) {
    final shown = _displayPrice(raw);
    return shown.isEmpty ? null : shown;
  }

  // MARK: - Fixed presentation strings

  static const String liveLabel = 'LIVE';
  static const String pricePrefix = 'NT\$ ';
}

// MARK: - Pin icon painter (`CarouselCardView._pinBadge`'s CustomPainter — top-level,
// Dart does not nest classes)

/// Draws the design's exact pushpin/thumbtack glyph (`design/templates/minimal/
/// widgets.jsx` `LBPCarouselCard`'s inline `<svg viewBox="0 0 384 512">`, a Font
/// Awesome "thumbtack"-style solid path) for [CarouselCardView._pinBadge]. The path
/// below is a 1:1 mechanical transcription of the design's SVG path data (its `M` / `L`
/// / `H` / `V` / `C` / `c` / `h` / `v` / `l` / `a` commands, resolved to ABSOLUTE
/// coordinates and rasterized offline to confirm it draws a pushpin, not garbage) —
/// chosen over an "equivalent" Material icon (which the brief also permits) because the
/// design hands over an exact path and a hand-picked lookalike risks silently drifting
/// from it. This is deliberately NOT a map-pin "balloon" marker (Material's
/// `Icons.location_on` / `Icons.place`, or the design system's own separately-defined
/// `pinFill` icon) — see `design/contract/claude-design-sync.md` R33 for why the design
/// itself keeps this as an inline path rather than reusing `pinFill`.
///
/// Scaled UNIFORMLY into the widget's box using the HEIGHT ratio (the 384×512 viewBox
/// is taller than wide) and horizontally centered — mirroring the SVG default
/// `preserveAspectRatio="xMidYMid meet"` behavior for a square 16×16 viewport (the
/// drawn width becomes `16 * 384/512 = 12`, centered with a 2px margin either side).
class _PinIconPainter extends CustomPainter {
  const _PinIconPainter();

  static const double _viewW = 384;
  static const double _viewH = 512;

  static Path _path() {
    final path = Path();
    path.moveTo(298.028, 214.267);
    path.lineTo(285.793, 96);
    path.lineTo(328, 96);
    path.cubicTo(341.255, 96, 352, 85.255, 352, 72);
    path.lineTo(352, 24);
    path.cubicTo(352, 10.745, 341.255, 0, 328, 0);
    path.lineTo(56, 0);
    path.cubicTo(42.745, 0, 32, 10.745, 32, 24);
    path.lineTo(32, 72);
    path.cubicTo(32, 85.255, 42.745, 96, 56, 96);
    path.lineTo(98.207, 96);
    path.lineTo(85.972, 214.267);
    path.cubicTo(37.465, 236.82, 0, 277.261, 0, 328);
    path.cubicTo(0, 341.255, 10.745, 352, 24, 352);
    path.lineTo(160, 352);
    path.lineTo(160, 456.007);
    path.cubicTo(160, 457.249, 160.289, 458.474, 160.845, 459.585);
    path.lineTo(184.845, 507.585);
    path.cubicTo(187.786, 513.467, 196.209, 513.478, 199.156, 507.585);
    path.lineTo(223.156, 459.585);
    path.arcToPoint(
      const Offset(224.001, 456.007),
      radius: const Radius.circular(8.008),
      rotation: 0,
      largeArc: false,
      clockwise: false,
    );
    path.lineTo(224.001, 352);
    path.lineTo(360.001, 352);
    path.cubicTo(373.256, 352, 384.001, 341.255, 384.001, 328);
    path.cubicTo(384, 276.817, 346.018, 236.58, 298.028, 214.267);
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.height / _viewH;
    final dx = (size.width - _viewW * scale) / 2;
    canvas.save();
    canvas.translate(dx, 0);
    canvas.scale(scale);
    canvas.drawPath(
      _path(),
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.fill,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PinIconPainter oldDelegate) => false;
}
