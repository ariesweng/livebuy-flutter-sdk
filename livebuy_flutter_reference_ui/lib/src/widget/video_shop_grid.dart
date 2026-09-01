import 'package:flutter/widgets.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart' show LBVideoItem;

import '../reference_ui_theme.dart';
import '../reference_ui_widget_embed_theme.dart';
import '../testing/lb_test_keys.dart';
import 'carousel_card.dart';
import 'widget_model.dart' show WidgetGoods;

// VideoShopGridView — family-5 widget surface 2 (影音商城 / LBPVideoShop).
//
// Spec: `reference-ui-rendering/spec.md` (family-5 widget surfaces — the Android
// family-5 requirement "渲染 … Video-Shop Grid widget"). Flutter parity of iOS
// `VideoShopGridView.swift` (rb-ios-widget) + Android `VideoShopGridView.kt`
// (rb-android-widget). Design: `design/templates/minimal/widgets.jsx` `LBPVideoShop`
// (lines 357-424).
//
// The 影音商城 widget surface: a 2-COLUMN grid of shared `CarouselCardView` cells
// plus a centered load-more / end-of-list footer. It is the second of the four
// family-5 widget surfaces composed by `WidgetOverlayView` (selected when
// `content.mode == LBWidgetContentMode.grid`). It implements the frozen SUB-VIEW
// INPUT PATTERN documented verbatim in `widget_overlay_view.dart`:
//
//   VideoShopGridView({
//       required ReferenceUITheme theme,     // 1. theme FIRST, always.
//       required List<LBVideoItem> videos,   // 2. bound SNAPSHOT VALUES by value.
//       required int currentPage,
//       required int lastPage,
//       WidgetGoods? Function(LBVideoItem item)? goodsFor,  // per-card overlay.
//       void Function(LBVideoItem item)? onTapVideo,        // 3. action callbacks
//       VoidCallback? onLoadMore })                         //    LAST, each null.
//
// REUSED PRIMITIVE: every grid cell is a shared `CarouselCardView` (the family-5
// 9:16 card — LBPCarouselCard). This surface NEVER re-draws a card from scratch; it
// only arranges `CarouselCardView`s into rows of TWO + draws the footer. The cell
// width is a fixed half-column ([_cellWidth]) so the two columns split the fixed
// snapshot canvas evenly (the design passes `width="100%"` to the card inside a
// `repeat(2, 1fr)` grid). `CarouselCardView` takes an explicit `width`, so each cell
// is handed the resolved half-column rather than a flexible cell (a flexible cell +
// a fixed card width would fight / overflow), parity with the Android `cellWidth`.
//
// ⚠️ NO ListView / GridView / SingleChildScrollView in rendered content — the
// reference-ui golden path renders lazy / scroll containers inconsistently (the
// verified family-1..4 + iOS / Android lesson). The design's `LBPVideoShop` is an
// INFINITE-SCROLL grid inside an `overflowY: auto` container; here it is drawn as a
// PLAIN `Column` of `Row` rows (TWO cards per row) over a FIXED SMALL set of
// `videos` (capped at [_maxGridCards]). The real scroll / pagination is NOT
// implemented at this layer — the load-more intent is forwarded to the host-wired
// `onLoadMore`.
//
// FOOTER (LBPVideoShop 413-420): a centered footer row. When more pages remain
// (`currentPage < lastPage`) it shows the「載入更多影片...」load-more affordance (a
// host-wired exit → `onLoadMore`); when the last page has been reached
// (`currentPage >= lastPage`, inclusive — Key Invariant: the widget list uses
// `current_page == last_page`) it shows the terminal「已顯示全部影片」label (inert).
// The design auto-loads via an `IntersectionObserver` sentinel; this layer instead
// forwards the intent through the host-wired `onLoadMore` (no auto-scroll / no
// pagination here).
//
// One-way data flow: this surface reads ONLY its passed-in `videos` / `currentPage`
// / `lastPage` snapshot + `theme`; it never reaches back into `WidgetModel` /
// `DefaultWidgetTemplate`, holds NO second copy of the list, and NEVER loads /
// paginates / opens the player itself. Card tap → `onTapVideo(item)` (host-wired);
// footer load-more → `onLoadMore` (host-wired). It renders correctly with all actions
// null (so demo / golden / widget tests construct it action-free).
//
// ── EMBED COLORS (rb-flutter-widget-embed-colors) ────────────────────────────────
//   This IS one of the widget surfaces that interpret `widgetColor` / `widgetBgcolor` —
//   see the `theme` getter below, which overlays them onto the caller-supplied
//   `resolvedTheme` via `ReferenceUIWidgetEmbedTheme.derive`. The scope is strictly this
//   surface: `ReferenceUIThemeResolver` still never sees these two values, and the player
//   / sheets / floating / minimized cards keep the underived theme. This surface paints
//   `theme.background` on its root `Container` — since rb-flutter-carousel-bgcolor,
//   `CarouselView` does too (its root `Container` also paints `theme.background`), so
//   `widget_bgcolor` is now visible on both card-bearing widget surfaces.

// MARK: - Layout tokens (LBPVideoShop literal spacing)

/// Outer grid padding (`padding: '12px 12px 8px'`, LBPVideoShop 401).
const double _gridPadding = 12;

/// Inter-cell gap (`gap: 10`, LBPVideoShop 399).
const double _gridGap = 10;

/// FIXED SMALL grid cap — a PLAIN `Column` of a bounded N (NEVER lazy / scroll). The
/// real infinite scroll is host-driven via `onLoadMore`.
const int _maxGridCards = 6;

/// The per-cell half-column width. `CarouselCardView` uses a FIXED `width`, so we pin
/// a concrete half-column rather than a flexible cell (a flexible cell + a fixed card
/// width would fight). On the fixed 393-wide golden canvas the usable half-column is
/// `(393 - _gridPadding*2 - _gridGap) / 2 ≈ 179.5` — parity with Android `cellWidth =
/// 179.dp` / iOS `cellWidth(forContainerWidth:)`.
const double _cellWidth = 179;

// MARK: - Fixed presentation strings

const String _loadMoreLabel = '載入更多影片...';
const String _endOfListLabel = '已顯示全部影片';

/// The family-5 影音商城 widget surface (`LBPVideoShop`): a 2-column grid of shared
/// [CarouselCardView]s over a FIXED SMALL set of [videos], plus a centered footer
/// that shows「載入更多影片...」(host-wired [onLoadMore]) while more pages remain, else
/// the terminal「已顯示全部影片」. Card tap forwards `onTapVideo(item)`; this layer
/// never scrolls / paginates / opens the player itself.
///
/// SUB-VIEW INPUT PATTERN: `theme` first → bound snapshot values by value
/// ([videos] / [currentPage] / [lastPage] + the per-card [goodsFor] resolver) →
/// trailing action callbacks, each defaulting to null.
class VideoShopGridView extends StatelessWidget {
  /// The theme AS SUPPLIED by the caller (`ReferenceUIThemeResolver` output), BEFORE
  /// this surface overlays the `/sdk/widget` embed colors. Read [theme], NOT this —
  /// every paint site goes through the derived value.
  final ReferenceUITheme resolvedTheme;

  /// The theme this surface actually paints with (FIRST — SUB-VIEW INPUT PATTERN, taken
  /// as the `theme:` constructor argument). The footer end-of-list label uses dimmed
  /// `theme.text`; the load-more affordance uses `theme.accent`; cards paint their own
  /// theme-driven title color (via [CarouselCardView]). The grid sits on
  /// `theme.background` — this is the ONE widget surface where `widget_bgcolor` shows.
  ///
  /// Derived per read from [resolvedTheme] + [widgetColor] / [widgetBgcolor]
  /// (`widget-embed-colors`). A GETTER rather than a stored field so EVERY paint site
  /// reaches the derived value — including the ones outside `build()` (`_gridRows()` /
  /// `_footer()` / the label helpers) that a `build()`-local shadow would silently miss
  /// (design FD1). When nothing is configured this EQUALS [resolvedTheme], keeping the
  /// existing goldens byte-identical.
  ReferenceUITheme get theme => ReferenceUIWidgetEmbedTheme.derive(
        resolvedTheme,
        widgetColor,
        widgetBgcolor,
      );

  /// The republished read-only widget video snapshot (the grid cells —
  /// `content.videos`). This layer MUST NOT slice / merge / re-sort beyond the
  /// [_maxGridCards] snapshot cap. Read-only.
  final List<LBVideoItem> videos;

  /// Current page (`content.currentPage`). Combined with [lastPage] it gates the
  /// footer copy.
  final int currentPage;

  /// Last page (`content.lastPage`). `currentPage < lastPage` →「載入更多影片...」else
  /// →「已顯示全部影片」.
  final int lastPage;

  /// Optional per-card product overlay resolver (reference-ui `WidgetGoods` — Flutter
  /// core `LBVideoItem` has no `goods` field; supplied BY VALUE). null → no overlay on
  /// any card. The container passes `WidgetSeeds.goodsFor` for the demo / golden path.
  final WidgetGoods? Function(LBVideoItem item)? goodsFor;

  /// Whether the grid cells load their real cover photo. `false` (DEFAULT — demo /
  /// golden) → placeholder ONLY (byte-stable goldens); `true` (host runtime) → each
  /// cell overlays `item.cover` over the placeholder. Forwarded verbatim to every
  /// [CarouselCardView]. Parity with iOS `VideoShopGridView.live`.
  final bool live;

  /// RAW `product_card` wire value (`WidgetModel.productCard`), forwarded VERBATIM to
  /// every grid cell's [CarouselCardView] — the fallback stays in the card's single pure
  /// entry point (`normalizeProductCardMode`). `null` (the DEFAULT) → `inside`, i.e. the
  /// historical rendering. Unlike the carousel row this grid needs NO height-bound term:
  /// it is a plain `Column` of `Row`s and grows with its cells.
  /// rb-flutter-widget-product-card-modes.
  final String? productCard;

  /// Card tap → host-wired exit (→ host → core open player for `item.id`). null for
  /// demo / golden instances. This layer NEVER opens the player itself.
  final void Function(LBVideoItem item)? onTapVideo;

  /// Footer「載入更多影片...」→ host-wired exit (→ host → core `requestLoadMore()`).
  /// null for demo / golden instances — the affordance is inert. This layer NEVER
  /// loads / paginates itself.
  final VoidCallback? onLoadMore;

  /// LAZY-LOAD wrapper support (rb-flutter-widget-grid-lazy-load): `_maxGridCards`
  /// (default) bounds the PLAIN Column to a fixed golden-stable set; `null` renders ALL
  /// videos (used by the scroll wrapper, which is never golden-snapshotted).
  final int? maxCards;

  /// `true` (the scroll wrapper drives auto-load on scroll) → the footer drops its
  /// tappable button for a dim caption. `false` (default) keeps the existing pixels /
  /// goldens / callers.
  final bool autoLoadOnScroll;

  /// RAW `widget_color` wire value (`POST /sdk/widget` root; `1`=預設色彩 / `2`=色彩反轉),
  /// sourced from `WidgetModel.widgetColor`. `1` (the DEFAULT — every pre-existing caller
  /// / demo / golden) leaves `theme.text` untouched, so existing baselines stay
  /// byte-identical. Interpreted ONLY through [ReferenceUIWidgetEmbedTheme.derive].
  final int widgetColor;

  /// RAW `widget_bgcolor` wire value (hex, or the empty string meaning「透明」on web),
  /// sourced from `WidgetModel.widgetBgcolor`. `null` (the DEFAULT) / `""` / an
  /// unparseable string all leave `theme.background` untouched (`widget-embed-colors` —
  /// native has no third-party page to show through, and the backend writes `""`
  /// unconditionally, so it is the majority state rather than a rare one).
  final String? widgetBgcolor;

  const VideoShopGridView({
    super.key,
    required ReferenceUITheme theme,
    required this.videos,
    required this.currentPage,
    required this.lastPage,
    this.goodsFor,
    this.live = false,
    this.productCard,
    this.widgetColor = 1,
    this.widgetBgcolor,
    this.onTapVideo,
    this.onLoadMore,
    this.maxCards = _maxGridCards,
    this.autoLoadOnScroll = false,
  }) : resolvedTheme = theme;

  /// Whether more pages remain (LBPVideoShop's `hasMore`). Mirrors the widget list's
  /// inclusive `current_page == last_page` terminal convention (Key Invariant:
  /// `POST /sdk/widget` uses `current_page == last_page`) — more pages remain only
  /// while `currentPage < lastPage`. Parity with iOS / Android `hasMore`.
  bool get _hasMore => currentPage < lastPage;

  /// The FIXED SMALL set of videos chunked into rows of TWO. Bounded to
  /// [_maxGridCards] so the PLAIN `Column` stays golden-stable (the design's infinite
  /// scroll is host-driven via [onLoadMore], not rendered here). Parity with iOS
  /// `rows` / Android `videos.take(maxGridCards).chunked(2)`.
  List<List<LBVideoItem>> get _rows {
    final cap = maxCards ?? videos.length;
    final capped = videos.length > cap ? videos.sublist(0, cap) : videos;
    final out = <List<LBVideoItem>>[];
    for (var i = 0; i < capped.length; i += 2) {
      out.add(capped.sublist(i, i + 2 > capped.length ? capped.length : i + 2));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: LbTestKeys.widgetGrid,
      width: double.infinity,
      color: theme.background,
      padding: const EdgeInsets.fromLTRB(_gridPadding, _gridPadding, _gridPadding, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 2-column grid: PLAIN Column of Row rows (TWO cards per row) — NEVER
          // GridView. Each cell is handed the fixed half-column [_cellWidth] so the
          // two columns split the canvas evenly; CarouselCardView fills its cell.
          ..._gridRows(),
          // Footer (載入更多影片... / 已顯示全部影片) — centered.
          _footer(),
        ],
      ),
    );
  }

  // MARK: - 2-column grid (PLAIN Column of Row rows — NEVER GridView)
  //
  // Mirrors LBPVideoShop's `repeat(2, 1fr)` grid (widgets.jsx 398-412), but built as
  // a PLAIN `Column` of `Row` rows (TWO cards per row) over a FIXED SMALL set — the
  // lazy/scroll blank-render trap forbids `GridView`. REUSES the shared
  // `CarouselCardView` primitive (never re-draws a card).

  List<Widget> _gridRows() {
    final rows = _rows;
    final widgets = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      // Each row holds up to TWO cells; the global (flat) card index of the row's
      // first cell is `i * 2` (so the per-cell E2E `gridCard(index)` keys are flat).
      widgets.add(_gridRow(rows[i], i * 2));
      // Inter-row gap (gridGap) between rows — NOT after the last row (the footer
      // owns its own top padding).
      if (i < rows.length - 1) {
        widgets.add(const SizedBox(height: _gridGap));
      }
    }
    return widgets;
  }

  /// One grid row: up to TWO shared `CarouselCardView` cells side by side, each taking
  /// the fixed half-column [_cellWidth]. A trailing odd cell keeps the 2-col rhythm
  /// with an invisible fixed spacer of the same half-column width. REUSES the shared
  /// `CarouselCardView` primitive (never re-draws a card). Parity with iOS `gridRow`
  /// / Android `GridRow`.
  Widget _gridRow(List<LBVideoItem> row, int baseIndex) {
    final children = <Widget>[];
    for (var i = 0; i < row.length; i++) {
      final item = row[i];
      if (i > 0) children.add(const SizedBox(width: _gridGap));
      children.add(CarouselCardView(
        key: LbTestKeys.gridCard(baseIndex + i),
        theme: theme,
        item: item,
        goods: goodsFor?.call(item),
        width: _cellWidth,
        live: live,
        productCard: productCard,
        onTap: onTapVideo == null ? null : () => onTapVideo!(item),
      ));
    }
    // Keep the 2-col grid rhythm when the final row has a single (odd) cell.
    if (row.length == 1) {
      children.add(const SizedBox(width: _gridGap));
      children.add(const SizedBox(width: _cellWidth));
    }
    return Row(
      mainAxisSize: MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  // MARK: - Footer (載入更多影片... / 已顯示全部影片)
  //
  // Mirrors LBPVideoShop's footer row (widgets.jsx 413-420): a centered footer. While
  // more pages remain → a host-wired「載入更多影片...」load-more affordance (→
  // onLoadMore); once the last page is reached → the terminal「已顯示全部影片」label
  // (inert). The design auto-loads via a scroll sentinel; this layer forwards the
  // intent to the host-wired closure (no auto-scroll / pagination here).

  Widget _footer() {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 18),
      child: SizedBox(
        width: double.infinity,
        child: Center(
          child: _hasMore
              // Lazy-load drop-in (the scroll wrapper auto-loads): a NON-interactive dim
              // caption — no manual button (onLoadMore is fired by the wrapper's scroll
              // detection, not a tap here).
              ? (autoLoadOnScroll ? _dimLoadMoreCaption() : _loadMoreAffordance())
              : _endOfListLabelWidget(),
        ),
      ),
    );
  }

  /// The「載入更多影片...」load-more affordance — a host-wired exit to [onLoadMore]
  /// (→ host → `requestLoadMore()`). Drawn with `theme.accent` to read as an
  /// actionable link (the design uses a dim caption; here it is an explicit host-wired
  /// tap target since the reference-ui has no auto-scroll sentinel). Parity with iOS
  /// `loadMoreAffordance` / Android footer.
  /// Lazy-load dim caption (non-interactive) — shown while more pages remain when the
  /// scroll wrapper drives auto-load (`autoLoadOnScroll == true`), replacing the manual button.
  Widget _dimLoadMoreCaption() {
    return Text(
      _loadMoreLabel,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 12 * theme.fontScale,
        color: theme.text.withValues(alpha: 0.5),
      ),
    );
  }

  Widget _loadMoreAffordance() {
    return GestureDetector(
      key: LbTestKeys.gridLoadMoreFooter,
      onTap: onLoadMore,
      behavior: HitTestBehavior.opaque,
      child: Text(
        _loadMoreLabel,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12 * theme.fontScale,
          fontWeight: FontWeight.w600,
          color: theme.accent,
        ),
      ),
    );
  }

  /// The terminal「已顯示全部影片」label (inert) shown once the last page is reached.
  /// Dimmed `theme.text` (0.5 alpha), parity with iOS / Android end-of-list label.
  Widget _endOfListLabelWidget() {
    return Text(
      _endOfListLabel,
      key: LbTestKeys.gridEndLabel,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 12 * theme.fontScale,
        color: theme.text.withValues(alpha: 0.5),
      ),
    );
  }
}
