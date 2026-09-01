import 'package:flutter/widgets.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart' show LBVideoItem;
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show DefaultWidgetTemplate, LBWidgetContentMode;

import '../reference_ui_theme.dart';
import 'external_live.dart';
import 'widget_model.dart';
// Surface widgets — landed by the parallel Surfaces agents. The container fixes the
// call-site shapes; the file names match the imports EXACTLY (no shim files). Per
// the family file-naming discipline: carousel.dart (CarouselView) / video_shop_grid
// .dart (VideoShopGridView) / floating_widget.dart (FloatingWidgetView) /
// minimized_widget.dart (MinimizedWidgetView). The shared card primitive
// carousel_card.dart (CarouselCardView) is landed by this skeleton. It is re-exported
// below (the container references no CarouselCardView TYPE directly — the surfaces do
// — so it needs only the export, not an import).
import 'carousel.dart';
import 'scrollable_video_shop_view.dart';
import 'floating_widget.dart';
import 'minimized_widget.dart';

// Re-export the shared card primitive + the four embedded widget surface widgets so
// they are publicly reachable through the package barrel (`CarouselCardView` /
// `CarouselView` / `VideoShopGridView` / `FloatingWidgetView` /
// `MinimizedWidgetView`), parity with the family-1..4 export convention.
export 'carousel_card.dart';
export 'carousel.dart';
export 'video_shop_grid.dart';
export 'floating_widget.dart';
export 'minimized_widget.dart';

// WidgetOverlayView — family-5 embedded-widget container (Flutter SKELETON).
//
// Spec: `reference-ui-rendering/spec.md` (family-5 widget — 1 shared card primitive
// + 4 embedded widget surfaces). Flutter sibling of iOS `WidgetOverlayView.swift`
// (rb-ios-widget) and Android `WidgetOverlayView.kt` (rb-android-widget). (The
// proposal calls this the `WidgetSurfacesView` role; the type name is
// `WidgetOverlayView` to read as a host-embedded widget surface, mirroring
// `MomentsOverlayView` / `ProductSheetsOverlayView`. The barrel re-exports it.)
//
// The top-level family-5 container. It binds the WIDGET template's host-bindable
// content (`DefaultWidgetTemplate.content`, a `DefaultWidgetContent extends
// ChangeNotifier`) with `ListenableBuilder`, re-reads the immutable snapshot
// (`content.current` → `LBWidgetContent`) on every notify via [WidgetModel], and
// DISPATCHES the matching surface by `content.current.mode`:
//
//   • carousel  → CarouselView         (header row + a plain Row of cards)
//   • grid      → VideoShopGridView    (2-col plain Column-of-Row grid + load-more footer)
//   • floating  → FloatingWidgetView   (single live card + close; null liveVideo → nothing)
//   • minimized → MinimizedWidgetView  (96-wide pill + LIVE tag + close)
//
// ── widget host-bindable entry (DIFFERENT from player) ───────────────────────────
//   The host obtains the bound `DefaultWidgetTemplate` via
//   `LivebuyUI.widgetTemplate(LivebuyWidgetController controller) -> DefaultWidgetTemplate?`
//   and passes it here. `template == null` → the container uses the deterministic
//   [WidgetSeeds] (no listenable to bind), so the demo / golden / widget tests
//   render without a live widget.
//
// ─────────────────────────────────────────────────────────────────────────────
// HOST-WIRED ACTION CALLBACKS (Model is PURE read-only — NO template forwarders)
// ─────────────────────────────────────────────────────────────────────────────
// The widget exits (cardTap / tapVideo / loadMore / floating close / minimized
// expand / minimized close) are NOT template methods — mirrors iOS / Android widget
// surfaces (pure read-only, NO mutating forwarder). So they are HOST-WIRED CONTAINER
// callbacks. The host wires them to the core widget exits it owns, e.g.:
//   • onTapVideo(item) → host → core open full-screen Player for item.id
//                        (NOT this layer — reference-ui NEVER opens the player)
//   • onLoadMore       → host → core `LivebuyWidget.requestLoadMore()` (NOT here)
//   • onClose          → host → core `LivebuyWidget.simulateClose()` / dismiss
//                        (host self-manages re-mount; this layer NEVER re-mounts)
//   • onExpand         → host → core restore full-screen from the minimized pill
//
// Every callback is null-defaulted, so the container renders correctly action-free
// (demo / golden / widget tests construct it without host wiring). This layer NEVER
// calls core `simulate*` (`simulateCardTap` / `simulateClose`) / `requestLoadMore`,
// and [WidgetModel] carries NO mutating forwarder. `widgetColor` / `widgetBgcolor` pass
// through this container RAW: it reads them off [WidgetModel] and hands them to the two
// card-bearing surfaces (which own the single derivation point), and it MUST NOT derive
// them itself — its local `theme` is shared with the floating / minimized branches
// (rb-flutter-widget-embed-colors FD3).
//
// ─────────────────────────────────────────────────────────────────────────────
// SUB-VIEW INPUT PATTERN — the contract the 4 Surfaces agents MUST follow
// ─────────────────────────────────────────────────────────────────────────────
// Every family-5 surface widget is a `class … extends StatelessWidget` whose
// constructor takes, IN THIS ORDER (named params — identical convention to
// families 1-4):
//
//   1. `theme:` (ReferenceUITheme, required)  — FIRST, always.
//   2. its bound SNAPSHOT VALUE(S)            — read-only state, passed BY VALUE from
//                                                WidgetModel (never the model / template).
//   3. optional action callbacks             — trailing, EACH defaulting to null.
//
// A surface widget reads ONLY its passed-in values — it MUST NOT reach back into
// WidgetModel / DefaultWidgetTemplate (one-way data flow), MUST NOT hold a second
// copy of state, MUST NOT call core `simulate*` / `requestLoadMore`, MUST render
// correctly with all callbacks null (so golden / widget tests construct it action-free),
// and
// MUST NOT use any scrollable container (`ListView` / `GridView` /
// `SingleChildScrollView`) or network image (`Image.network` / `NetworkImage`). The
// card rows / grids are PLAIN `Row` / `Column` FIXED SMALL sets.
//
// The four Surfaces agents implement EXACTLY these constructors (see the call sites
// in `build` below):
//
//   CarouselView({
//       required ReferenceUITheme theme,
//       required List<LBVideoItem> videos,
//       String title = '精選影片',
//       String? subtitle,
//       WidgetGoods? Function(LBVideoItem item)? goodsFor,  // per-card overlay (demo: WidgetSeeds.goodsFor)
//       String? productCard,                                // raw product_card mode (null → inside)
//       void Function(LBVideoItem item)? onTapVideo,        // → host (open player)
//       VoidCallback? onSeeMore })                          // header「查看更多 ›」→ host
//
//   VideoShopGridView({
//       required ReferenceUITheme theme,
//       required List<LBVideoItem> videos,
//       required int currentPage,
//       required int lastPage,
//       WidgetGoods? Function(LBVideoItem item)? goodsFor,
//       String? productCard,                                // raw product_card mode (null → inside)
//       void Function(LBVideoItem item)? onTapVideo,        // → host (open player)
//       VoidCallback? onLoadMore })                         // footer / 觸底 → host (core requestLoadMore)
//
//   FloatingWidgetView({
//       required ReferenceUITheme theme,
//       required LBVideoItem? liveVideo,                    // null → render NOTHING (SizedBox.shrink)
//       WidgetGoods? goods,
//       void Function(LBVideoItem item)? onTap,             // whole-card tap → host (open player)
//       VoidCallback? onClose })                            // top-right close → host (self-manages re-mount)
//
//   MinimizedWidgetView({
//       required ReferenceUITheme theme,
//       required bool isLive,                               // derived from liveVideo?.liveStatus (no isLive field)
//       VoidCallback? onExpand,                             // pill tap → host (restore full-screen)
//       VoidCallback? onClose })                            // top-right close → host
//
// (The sketches above are ABBREVIATED — they predate later additions such as
// `cardWidth` / `live` / `scrollable` / `maxCards` and the two embed colors. Read the
// real constructors.) The two card-bearing surfaces additionally take
// `int widgetColor = 1` / `String? widgetBgcolor` (RAW `/sdk/widget` embed colors, read
// off [WidgetModel] by this container) and derive the theme INTERNALLY; `FloatingWidgetView`
// / `MinimizedWidgetView` deliberately take neither (rb-flutter-widget-embed-colors).
//
// The container passes the deterministic per-card goods overlay via
// `WidgetSeeds.goodsFor` (Flutter core `LBVideoItem` has no `goods` field). The host
// path supplies its own `goodsFor` (or null → no overlay).

/// The top-level family-5 embedded-widget container. Binds the WIDGET template's
/// host-bindable `content` (`DefaultWidgetContent`) and dispatches the matching
/// surface by `content.current.mode`. `template == null` → deterministic
/// [WidgetSeeds] (demo / golden / widget tests).
class WidgetOverlayView extends StatefulWidget {
  /// Live WIDGET template (host-supplied via `LivebuyUI.widgetTemplate(controller)`).
  /// `null` → deterministic demo seeds.
  final DefaultWidgetTemplate? template;

  /// Resolved reference-ui theme.
  final ReferenceUITheme theme;

  /// Optional per-card product overlay resolver (reference-ui `WidgetGoods` — Flutter
  /// core `LBVideoItem` has no `goods` field). Defaults to [WidgetSeeds.goodsFor]
  /// (deterministic demo overlays). Pass `(_) => null` for no overlay.
  final WidgetGoods? Function(LBVideoItem item)? goodsFor;

  /// Whether the dispatched surface's cards load their real cover photo. `false`
  /// (DEFAULT — demo / golden) → placeholder ONLY (byte-stable goldens); `true` (host
  /// runtime) → forwarded to the carousel / grid / floating surface so each card
  /// overlays `item.cover`. Parity with iOS `WidgetOverlayView` `live` flow.
  final bool live;

  // Host-wired interaction callbacks. The container owns NO core action — each is
  // forwarded to the host (which wires it to the core widget exit). All optional;
  // a null callback means an inert exit. The Model carries NO forwarder for these
  // (widget actions are NOT template methods — mirrors iOS / Android widget surfaces).

  /// Card tap (carousel / grid / floating) → host → core open full-screen Player for
  /// the tapped video. This layer NEVER opens the player itself.
  final void Function(LBVideoItem item)? onTapVideo;

  /// Grid load-more footer / 觸底 intent → host → core `requestLoadMore()`. This
  /// layer NEVER paginates / fetches the next page itself.
  final VoidCallback? onLoadMore;

  /// Carousel header「查看更多 ›」link → host (navigate to the full video list).
  final VoidCallback? onSeeMore;

  /// Floating / minimized close → host → core `simulateClose()` / dismiss. The host
  /// self-manages re-mount; this layer NEVER re-mounts itself.
  final VoidCallback? onClose;

  /// Minimized pill tap → host → core restore full-screen from the minimized state.
  final VoidCallback? onExpand;

  const WidgetOverlayView({
    super.key,
    this.template,
    required this.theme,
    this.goodsFor,
    this.live = false,
    this.onTapVideo,
    this.onLoadMore,
    this.onSeeMore,
    this.onClose,
    this.onExpand,
  });

  @override
  State<WidgetOverlayView> createState() => _WidgetOverlayViewState();
}

class _WidgetOverlayViewState extends State<WidgetOverlayView> {
  /// Read-only snapshot bridge (re-read inside the ListenableBuilder on notify).
  late WidgetModel _model = WidgetModel(template: widget.template);

  @override
  void didUpdateWidget(covariant WidgetOverlayView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.template != widget.template) {
      _model = WidgetModel(template: widget.template);
    }
  }

  /// Per-card goods overlay resolver (host-supplied or the deterministic demo).
  WidgetGoods? _goodsFor(LBVideoItem item) =>
      (widget.goodsFor ?? WidgetSeeds.goodsFor)(item);

  @override
  Widget build(BuildContext context) {
    final t = widget.template;
    // Bind the widget content ChangeNotifier so any change re-reads the model. With
    // no live template (demo seeds) there is nothing to listen to — render directly.
    if (t == null) {
      return _buildSurface(context);
    }
    return ListenableBuilder(
      listenable: t.content,
      builder: (context, _) => _buildSurface(context),
    );
  }

  /// Dispatch the matching surface by `content.current.mode`. Mutually exclusive —
  /// the widget is in exactly one mode at a time.
  Widget _buildSurface(BuildContext context) {
    // ⚠️ EMBED COLORS (rb-flutter-widget-embed-colors FD3): this local is handed to ALL
    // FOUR mode branches — including `floating` / `minimized`. It MUST stay the UNDERIVED
    // resolver output. Deriving `widgetColor` / `widgetBgcolor` here is a one-line
    // shortcut that silently tints the floating card and the minimized pill, which the
    // scope boundary forbids (`widget-embed-colors` § 浮動與最小化表面不受 widget 顏色
    // 影響). The derivation belongs INSIDE `CarouselView` / `VideoShopGridView`.
    final theme = widget.theme;
    final m = _model;
    // Redirect external-platform lives (Facebook) out to their platform on tap instead of
    // opening the in-app player (external-live-watch); non-external lives forward to the host
    // `onTapVideo` unchanged. The container `LivebuyWidget` uses this surface, so the drop-in
    // path is covered too.
    final routedTapVideo = externalLiveAwareTap(widget.onTapVideo);
    switch (m.mode) {
      case LBWidgetContentMode.carousel:
        return CarouselView(
          theme: theme,
          videos: m.videos,
          goodsFor: _goodsFor,
          live: widget.live,
          // product_card mode — read ONCE off the model here and fed to BOTH card-bearing
          // surfaces (carousel + grid). Raw passthrough; the `inside` fallback lives in
          // `CarouselCardView.normalizeProductCardMode`, never here.
          productCard: m.productCard,
          // Embed colors — read ONCE off the model here (same shape as `productCard`) and
          // fed to BOTH card-bearing surfaces. Raw passthrough; the surface owns the
          // single derivation point (`ReferenceUIWidgetEmbedTheme.derive`), never here.
          widgetColor: m.widgetColor,
          widgetBgcolor: m.widgetBgcolor,
          // Turnkey carousel SCROLLS horizontally over ALL videos (parity iOS
          // ScrollableCarouselView); the embedded/golden CarouselView default stays windowed.
          scrollable: true,
          onTapVideo: routedTapVideo,
          onSeeMore: widget.onSeeMore,
        );
      case LBWidgetContentMode.grid:
        // Grid mode uses the lazy-load wrapper (rb-flutter-widget-grid-lazy-load): it scrolls
        // + AUTO-loads the next page on scroll-to-bottom (no manual button).
        return ScrollableVideoShopView(
          theme: theme,
          videos: m.videos,
          currentPage: m.currentPage,
          lastPage: m.lastPage,
          goodsFor: _goodsFor,
          live: widget.live,
          productCard: m.productCard,
          // Embed colors — forwarded through the scroll wrapper to the grid it wraps,
          // which owns the single derivation point.
          widgetColor: m.widgetColor,
          widgetBgcolor: m.widgetBgcolor,
          onTapVideo: routedTapVideo,
          onLoadMore: widget.onLoadMore,
        );
      case LBWidgetContentMode.floating:
        // liveVideo == null → FloatingWidgetView renders NOTHING (SizedBox.shrink).
        // NO `productCard` here (four-platform decision): the floating card is bound to
        // `content.liveVideo`, whose data comes from `/sdk/widget/live` — a response that
        // does NOT carry `product_card`. It stays at the default → `inside`.
        // NO `widgetColor` / `widgetBgcolor` here either, for the same reason plus the
        // scope boundary: the floating card keeps the UNDERIVED theme
        // (rb-flutter-widget-embed-colors). `FloatingWidgetView` has no such parameter.
        final liveVideo = m.liveVideo;
        return FloatingWidgetView(
          theme: theme,
          liveVideo: liveVideo,
          goods: liveVideo == null ? null : _goodsFor(liveVideo),
          live: widget.live,
          onTap: routedTapVideo,
          onClose: widget.onClose,
        );
      case LBWidgetContentMode.minimized:
        // Same exclusion as `floating`: the minimized pill keeps the UNDERIVED theme.
        // NOTE it consumes only `theme.fontScale`, so a theme leak here would have NO
        // pixel signature — the guard is a theme-object assertion, not a golden.
        return MinimizedWidgetView(
          theme: theme,
          isLive: m.minimizedIsLive,
          onExpand: widget.onExpand,
          onClose: widget.onClose,
        );
    }
  }
}
