import 'package:flutter/widgets.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart' show LBVideoItem;

import '../reference_ui_theme.dart';
import 'video_shop_grid.dart';
import 'widget_model.dart' show WidgetGoods;

// scrollable_video_shop_view — family-5 wrapper tier (Flutter, lazy-load drop-in).
//
// Spec: `reference-ui-rendering/spec.md` (Flutter wrapper 子層 — 捲到底自動載入).
// Parity: iOS `ScrollableVideoShopView.swift` + Android `ScrollableVideoShopView.kt`
//          (rb-*-widget-grid-lazy-load) — the drop-in scrolling video-shop grid that
//          AUTO-LOADS on scroll-to-bottom (no manual「載入更多」button). Four-platform parity.
//
// A thin, ZERO-new-pixel wrapper: it composes the existing golden-baselined
// `VideoShopGridView` (in its `maxCards: null` render-ALL + `autoLoadOnScroll: true` mode)
// inside a `SingleChildScrollView` and watches a `NotificationListener<ScrollNotification>`.
// When the user scrolls near the bottom (within a prefetch margin) AND there is a next page it
// AUTO-fires the host-wired `onLoadMore` (→ core `requestLoadMore`), per-page debounced (keyed
// on `currentPage`).
//
// WRAPPER TIER RULES (mirrors iOS / Android): MAY own the scroll container; ZERO new pixels
// (all pixels come from `VideoShopGridView`); interactions pass through as host-wired
// callbacks; the auto-load decision is covered by the pure [shouldAutoLoadMore] unit test +
// the surface's own goldens — the wrapper is NEVER golden-snapshotted.

/// Auto-load prefetch margin (logical px) from the bottom — fire before the very bottom.
const double _prefetchMargin = 300;

/// PURE auto-load decision (extracted for unit testing — the wrapper is never
/// golden-snapshotted). Auto-load iff there is a next page (`currentPage < lastPage`), this
/// page hasn't already triggered (`currentPage != lastTriggeredPage`), and the scroll is within
/// `prefetch` of the bottom (`pixels >= maxScrollExtent - prefetch`). Mirrors iOS / Android
/// `shouldAutoLoadMore`.
bool shouldAutoLoadMore({
  required int currentPage,
  required int lastPage,
  required int lastTriggeredPage,
  required double pixels,
  required double maxScrollExtent,
  required double prefetch,
}) {
  if (currentPage >= lastPage) return false; // hasMore
  if (currentPage == lastTriggeredPage) return false; // this page already triggered
  return pixels >= maxScrollExtent - prefetch; // near the bottom
}

/// The drop-in scrolling video-shop grid (wrapper tier — zero new pixels): a
/// `SingleChildScrollView` around `VideoShopGridView(maxCards: null, autoLoadOnScroll: true)`
/// that auto-loads the next page when the user scrolls near the bottom. Host wires `onTapVideo`
/// / `onLoadMore`; no manual「載入更多」button is shown. Never golden-baselined.
class ScrollableVideoShopView extends StatefulWidget {
  final ReferenceUITheme theme;
  final List<LBVideoItem> videos;
  final int currentPage;
  final int lastPage;
  final WidgetGoods? Function(LBVideoItem item)? goodsFor;

  /// Whether the wrapped grid cells load their real cover photo. `false` (DEFAULT —
  /// demo / golden) → placeholder ONLY; `true` (host runtime) → forwarded to the wrapped
  /// `VideoShopGridView` so each cell overlays `item.cover`.
  final bool live;

  /// RAW `product_card` wire value — a PASS-THROUGH parameter: this wrapper draws no
  /// card itself, but it is `WidgetOverlayView`'s ONLY upstream in grid mode, so without
  /// it the grid's mode chain would break here. Forwarded verbatim to the wrapped
  /// [VideoShopGridView]. rb-flutter-widget-product-card-modes.
  final String? productCard;

  /// RAW `widget_color` — a PASS-THROUGH parameter, exactly like [productCard]: this
  /// wrapper paints nothing of its own, but it is `WidgetOverlayView`'s ONLY upstream in
  /// grid mode, so without it the grid's embed-color chain would break here. Forwarded
  /// VERBATIM to the wrapped [VideoShopGridView], which owns the single derivation point.
  /// This wrapper MUST NOT derive. rb-flutter-widget-embed-colors.
  final int widgetColor;

  /// RAW `widget_bgcolor` — same pass-through contract as [widgetColor].
  final String? widgetBgcolor;

  final void Function(LBVideoItem item)? onTapVideo;
  final VoidCallback? onLoadMore;

  const ScrollableVideoShopView({
    super.key,
    required this.theme,
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
  });

  @override
  State<ScrollableVideoShopView> createState() => _ScrollableVideoShopViewState();
}

class _ScrollableVideoShopViewState extends State<ScrollableVideoShopView> {
  /// The `currentPage` we last auto-loaded for, so the same page only triggers ONE
  /// `onLoadMore` (per-page debounce). Re-armed when a new page loads (`currentPage`
  /// increments) → the next bottom-reach is eligible again.
  int _lastTriggeredPage = -1;

  bool _onScroll(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (shouldAutoLoadMore(
      currentPage: widget.currentPage,
      lastPage: widget.lastPage,
      lastTriggeredPage: _lastTriggeredPage,
      pixels: metrics.pixels,
      maxScrollExtent: metrics.maxScrollExtent,
      prefetch: _prefetchMargin,
    )) {
      _lastTriggeredPage = widget.currentPage;
      widget.onLoadMore?.call();
    }
    return false; // let the notification continue to bubble
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: SingleChildScrollView(
        child: VideoShopGridView(
          theme: widget.theme,
          videos: widget.videos,
          currentPage: widget.currentPage,
          lastPage: widget.lastPage,
          goodsFor: widget.goodsFor,
          live: widget.live,
          productCard: widget.productCard,
          // Embed colors forwarded RAW — the wrapped grid owns the single derivation
          // point (rb-flutter-widget-embed-colors FD4).
          widgetColor: widget.widgetColor,
          widgetBgcolor: widget.widgetBgcolor,
          onTapVideo: widget.onTapVideo,
          onLoadMore: widget.onLoadMore,
          // Render ALL videos (no fixed cap) + drop the manual footer button — the wrapper
          // drives the load on scroll.
          maxCards: null,
          autoLoadOnScroll: true,
        ),
      ),
    );
  }
}
