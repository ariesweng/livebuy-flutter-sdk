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
//   • a KIND BADGE top-left:
//       - LIVE → a red「LIVE」tag (static pulse dot) when the item is live
//                (`WidgetModel.isLive` — `liveStatus == 1`),
//       - VOD  → a「▶ mm:ss」duration pill (from `LBVideoItem.duration` seconds)
//                otherwise,
//   • a PRODUCT CARD whose placement depends on `product_card` (see below), drawn from
//     a reference-ui `WidgetGoods` value (Flutter core `LBVideoItem` has NO `goods`
//     field; supplied BY VALUE): thumb chip + `goods.name` +「NT$ price」(+ an optional
//     struck-through `goods.originalPrice` in `below` mode),
//   • the `LBVideoItem.title` BELOW the thumbnail (gated by `showTitle`, see below).
//
// (That is an ELEMENT LIST, not a vertical order — where the product card lands is
// decided by the mode below, and in `below` it lands UNDER the title.)
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
// PLACEMENT then reversed by R17 / rb-flutter-widget-product-card-below-slot-reposition —
// `design/templates/minimal/widgets.jsx` `normalizeProductCardMode` / `LBPCardProductRow`
// / `LBPCardProductOverlay`). `POST /sdk/widget` carries a root `product_card` String
// (`inside` / `below` / `hidden`, backend default `inside`), raw-passed through the Flutter
// bridge (`fetchWidget` map) → `LBWidgetContent.productCard` → `WidgetModel.productCard`
// → this card's `productCard` parameter (`String?`):
//
//     inside (default)  the dark-glass overlay INSIDE the 9:16 thumbnail (the historical,
//                       unconditional rendering — pixels unchanged). `goods == null` → the
//                       whole block is not drawn.
//     below             the product card moves OUTSIDE the thumbnail, landing UNDER THE
//                       TITLE — the very bottom of the card (design R17, which reversed
//                       the earlier "between the thumbnail and the title" placement).
//                       Off the dark video backdrop it switches to the design's surface
//                       vocabulary (bgElev fill + stroke border + `theme.text` name +
//                       sale price + textFaint struck-through original price).
//                       `goods == null` → an EQUAL-HEIGHT TRANSPARENT SPACER so cards in
//                       the same row / grid cell stay the same height.
//     hidden            no product card at all (neither overlay nor row, and NO spacer —
//                       every card in the surface is equally card-less).
//
// The LIVE tag / duration pill / upcoming veil / title are IDENTICAL in all three modes.
// Equal height comes from the FIXED constant `belowRowHeight` (design `LB_BELOW_ROW_H = 44`),
// NOT from the content. In `inside` / `hidden` the below slot is not present in the widget
// tree AT ALL (not a zero-height node), so the `inside` layout is byte-identical to before
// this mode existed.
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
//   `liveStatus == 1`                       → LIVE (red LIVE tag, NO duration pill).
//   `liveStatus == 0` && future `publishAt` → UPCOMING (直播預告): rgba(0,0,0,0.25)
//                                             mask + centred date + big time (the
//                                             design's upcoming treatment, replacing
//                                             the duration pill).
//   otherwise (incl. liveStatus==0 with     → VOD  (duration pill from `duration`).
//      empty/past publishAt, or replay)
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
  /// Dark-glass overlay INSIDE the 9:16 thumbnail (backend default, and the fallback
  /// for everything unrecognized).
  inside('inside'),

  /// A surface-styled product row OUTSIDE the thumbnail, under the title (the very
  /// bottom of the card).
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
  /// title uses `theme.text`; the badges / overlay use FIXED design colors (the
  /// dark-glass treatment over the dark thumbnail).
  final ReferenceUITheme theme;

  /// The video this card renders (read-only — `title` / `duration` / `liveStatus` /
  /// `cover`). When [live] is false (demo / golden) `cover` is NOT fetched (the
  /// deterministic placeholder draws). This layer never mutates / re-fetches.
  final LBVideoItem item;

  /// Optional product overlay (reference-ui `WidgetGoods` — Flutter core
  /// `LBVideoItem` has no `goods` field). When non-null the bottom dark-glass
  /// overlay is drawn; null → no overlay (a live `LBVideoItem` carries none).
  final WidgetGoods? goods;

  /// Card width (logical px). Defaults to the design's `132`. The thumbnail height
  /// is derived 9:16. The minimized surface passes a smaller width (e.g. 96).
  final double width;

  /// Whether to load the real cover photo over the placeholder. `false` (DEFAULT —
  /// demo / golden) → ONLY the deterministic placeholder draws (no network →
  /// byte-stable goldens). `true` (host runtime) → when `item.cover` is a non-empty
  /// http(s) URL, `Image.network(item.cover)` overlays the placeholder (loading /
  /// error fall back to the placeholder). Parity with iOS `CarouselCardView.live`
  /// gating `item.cover` (rb-ios-product-real-images / widget `live` flag).
  final bool live;

  /// RAW `product_card` wire value (`WidgetModel.productCard`), carried verbatim — this
  /// card does NOT expect a pre-normalized value, so every call site is a plain hand-off
  /// and the fallback stays in ONE place ([normalizeProductCardMode]).
  ///
  /// `null` (the DEFAULT, and what every pre-existing call site passes) → `inside`, i.e.
  /// the historical unconditional dark-glass overlay, pixel-for-pixel unchanged.
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

  /// `inside` → the dark-glass overlay is drawn inside the 9:16 thumbnail.
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
          // gap, so the `below` card grows by exactly `belowRowHeight + 8` — the increment
          // `CarouselView` adds to its height bound. `inside` / `hidden` contribute
          // NOTHING here (the slot is absent from the tree, not a zero-height node), so
          // the `Column` lays out exactly as it did before this mode existed. When
          // `showTitle == false` (floating only), this slot lands directly under the
          // thumbnail instead of under the title — floating never sets `productCard`
          // though, so this combination is exercised by tests but not by any real caller.
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

  // MARK: - Thumbnail (9:16, placeholder + kind badge + product overlay)

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
            else
              // Kind badge top-left: LIVE red tag, else VOD「▶ mm:ss」duration pill.
              Positioned(top: 6, left: 6, child: _kindBadge()),
            // Bottom dark-glass product overlay — `inside` mode ONLY (`below` draws the
            // row outside the thumbnail, `hidden` draws nothing), and only when
            // goods != null (an unbound card keeps a clean thumbnail).
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

  // MARK: - Kind badge (LIVE tag / VOD duration pill)

  Widget _kindBadge() =>
      KeyedSubtree(key: LbTestKeys.cardKindBadge, child: _isLive ? _liveTag() : _durationPill());

  /// LIVE red tag (LBPCarouselCard 180-191): a static pulse dot +「LIVE」on the
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

  /// VOD「▶ mm:ss」duration pill (LBPCarouselCard 193-207) over a translucent dark
  /// capsule. `LBVideoItem.duration` is `int` SECONDS — formatted to `mm:ss`.
  Widget _durationPill() {
    return Container(
      key: LbTestKeys.cardDurationPill,
      padding: const EdgeInsets.fromLTRB(4, 2, 6, 2),
      decoration: BoxDecoration(
        color: const Color(0xFF000000).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(_playGlyph, size: 8, color: Color(0xFFFFFFFF)),
          const SizedBox(width: 4),
          Text(
            formatSeconds(item.duration),
            style: TextStyle(
              fontSize: 10 * theme.fontScale,
              fontWeight: FontWeight.w600,
              color: const Color(0xFFFFFFFF),
            ),
          ),
        ],
      ),
    );
  }

  // MARK: - Bottom dark-glass product overlay (goods != null)

  /// Dark-glass product overlay (LBPCardProductOverlay 107-131): a 24×24 thumb chip + the
  /// product name (1-line) +「NT$ {price}」, on a translucent dark surface.
  /// `WidgetGoods.price` is a `String` (raw) — prefixed verbatim with「NT$ 」.
  Widget _productOverlay(WidgetGoods goods) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: _productGlass,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.10),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          // 24×24 product chip: gradient placeholder + (live) the real goods.pic over it
          // (parity iOS productThumb). live==false (demo/golden) → placeholder only.
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              width: 24,
              height: 24,
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
                    color: const Color(0xFFFFFFFF),
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
                    color: const Color(0xFFFFFFFF),
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

  /// The `below` slot: the surface-styled product row, or — when the card has no bound
  /// goods — an EQUAL-HEIGHT TRANSPARENT SPACER. The spacer (the design's `aria-hidden`
  /// empty div) is what keeps cards in the same carousel row / grid cell the same height
  /// without drawing an empty frame. A fixed-size `SizedBox`, NOT a `Spacer` (which would
  /// absorb the enclosing `Column`'s free space).
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

  /// Surface-styled product row (`LBPCardProductRow`, widgets.jsx 66-103): a 32×32
  /// product thumb + the product name (1-line) + the sale price + an optional
  /// struck-through original price, on an elevated surface with a hairline border.
  /// Off the dark video backdrop the dark-glass + white-text vocabulary no longer holds,
  /// so this row uses the design's surface tokens instead (see the token constants
  /// below). Height is the FIXED [belowRowHeight] — never content-driven.
  Widget _belowProductRow(WidgetGoods goods) {
    return Container(
      key: LbTestKeys.cardBelowProductRow,
      width: width,
      height: belowRowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: belowRowBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: belowRowStroke, width: 1),
      ),
      child: Row(
        children: [
          // 32×32 product chip: gradient placeholder + (live) the real goods.pic over it
          // — the SAME `live` gate as the `inside` overlay's 24×24 chip.
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              width: 32,
              height: 32,
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
                    // The RESOLVED theme text (the design's `theme.surface.text`) —
                    // the same source the card's own `title` is painted with.
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
        style: TextStyle(
          fontSize: 12 * theme.fontScale,
          fontWeight: FontWeight.w600,
          color: theme.text,
        ),
      ),
    );
  }

  // MARK: - Helpers

  /// Format `int` seconds → zero-padded `mm:ss` (`08:02`), or `hh:mm:ss` (`01:24:36`)
  /// when ≥ 1h, for `LBVideoItem.duration` (which IS seconds). Mirrors the design's
  /// `LB_CAROUSEL_DEMO` / `LB_SHOP_POOL` duration copy and the iOS / Android
  /// `formatSeconds` — long replays carry an hours component (so `5076s` reads
  /// `01:24:36`, not `84:36`); minutes are always 2-digit.
  static String formatSeconds(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = sec.toString().padLeft(2, '0');
    if (h > 0) return '${h.toString().padLeft(2, '0')}:$mm:$ss';
    return '$mm:$ss';
  }

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

  /// Dark-glass product overlay surface (`rgba(20,20,24,0.78)`, LBPCardProductOverlay 111).
  static const Color _productGlass = Color(0xC7141418); // 0.78 alpha over #141418.

  // `below` row tokens. Flutter's `ReferenceUITheme` is the same 5-token thin palette as
  // iOS / Android / RN (accent / background / text / cornerRadius / fontScale) with no
  // surface / sale entries, so — exactly like the decorative tokens above — the design's
  // tokens are pinned here as LIGHT-MODE literals from `design/brands/livebuy/tokens.jsx`.
  // The four values are BYTE-IDENTICAL to the iOS `CarouselCardView.swift`, Android
  // `CarouselCardView.kt` and RN `CarouselCardView.tsx` constants. The product NAME
  // deliberately uses the RESOLVED `theme.text` (the design's `theme.surface.text`),
  // matching how the card's own `title` is painted.
  //
  // NOTE: `ProductListView` carries an older sale red (`#E0334B`); the value below is the
  // one `tokens.jsx` currently defines for `theme.sale`. Converging the two is a separate
  // token-drift question and is NOT done here (it would move existing family-3 goldens).

  /// Fixed height of the `below` product row AND of its no-goods transparent spacer
  /// (design `LB_BELOW_ROW_H = 44`). Equal card height comes from THIS constant, not
  /// from how much content the row happens to hold (product-name length / presence of an
  /// original price never change it).
  static const double belowRowHeight = 44;

  /// `theme.surface.bgElev` — the `below` row's elevated fill (light mode).
  static const Color belowRowBackground = Color(0xFFFAFAFA);

  /// `theme.surface.stroke` — the `below` row's hairline border (light mode).
  static const Color belowRowStroke = Color(0xFFECECEF);

  /// `theme.sale` — the `below` row's sale price.
  static const Color saleColor = Color(0xFFF03246);

  /// `theme.surface.textFaint` — the `below` row's struck-through original price.
  static const Color textFaint = Color(0xFF9A9BA5);

  /// Play glyph for the VOD duration pill (▶). `Icons.play_arrow` codepoint —
  /// declared inline to avoid a material import in a widgets-only file.
  static const IconData _playGlyph =
      IconData(0xe037, fontFamily: 'MaterialIcons');

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
