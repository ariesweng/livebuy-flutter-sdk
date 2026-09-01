// LivebuyWidget — turnkey drop-in widget-list container
// (introduce-dropin-widget-container-flutter, reference-ui layer).
//
// Parity source: iOS `LivebuyWidget.swift` + RN `LivebuyWidget` container. The
// Flutter reference-ui ships only loose family-5 widget surfaces
// (`WidgetOverlayView` + carousel/grid/floating/minimized) with NO live data
// consumer (and no container/ dir at all). To SEE a list a host had to build a
// `DefaultWidgetTemplate`, fetch each page via `LivebuySDK.fetchWidget`, feed
// `handleWidgetSnapshot`, and manage pagination + refresh. `LivebuyWidget` PROMOTES
// that assembly into the package so a host gets a working list in ONE line:
//
//     LivebuyWidget(shopId: 'Pw8PJ99J')                              // turnkey carousel
//     LivebuyWidget(shopId: 'Pw8PJ99J', mode: WidgetContainerMode.grid, config: …)
//
// `LivebuyWidget` is the GOLDEN NAME, freed by the prerequisite core change
// `rename-bare-widget-to-core-flutter` (bare data source → `LivebuyWidgetCore`).
//
// Flutter vs RN (drives this design): RN needs a separate `decodeWidgetSnapshot`;
// Flutter's `DefaultWidgetContent.handleWidgetSnapshot(Map)` reads the snake_case
// wire itself, so the container injects `mode` into the `fetchWidget` map and feeds
// it DIRECTLY (colors go via `handleWidgetColors`). Widget data is HOST-WIRED
// (design D7): the container plays the host — it fetches each page via
// `LivebuySDK.fetchWidget` (the prerequisite `fetch-widget-content-flutter-core`)
// and manages page accumulation (grid load-more appends).
//
// PURE ASSEMBLY (governance): it only composes the existing `WidgetOverlayView`
// surface + the existing `DefaultWidgetTemplate` handle + core
// `LivebuySDK.fetchWidget`. It adds NO view-model and NO pixels. Dependency stays
// one-way `reference-ui → template (flutter-ui) → core (flutter)`.

import 'dart:async';

import 'package:flutter/material.dart' show MaterialPageRoute;
import 'package:flutter/widgets.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart'
    show LBVideoItem, LivebuySDK, SDKConfig;
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show DefaultWidgetTemplate, LBUIOptions;

import '../reference_ui_theme.dart';
import '../widget/external_live.dart' show externalLiveAwareTap;
import '../widget/widget_model.dart' show WidgetGoods, WidgetSeeds;
import 'live_buy_player.dart' show LivebuyPlayer, LivebuyPlayerConfig;
import 'reference_ui_design.dart';
import 'widget_data.dart';

export 'widget_data.dart' show WidgetContainerMode;

/// Per-instance wiring for [LivebuyWidget]. All callbacks optional; each has a
/// documented built-in default. Mirrors the iOS / RN `LivebuyWidgetConfig`.
class LivebuyWidgetConfig {
  /// The merchant SDKConfig used to build the widget template + resolve the theme.
  /// Omitted → the container fetches it via `LivebuySDK.getSdkConfig()` (falling
  /// back to `SDKConfig.fallback` if not configured yet).
  final SDKConfig? sdkConfig;

  /// Host UI options forwarded into the template + theme resolver. Default: none
  /// (Flutter has no public `LivebuyUI.hostOptions` getter, unlike RN — the host
  /// passes options here).
  final LBUIOptions? hostOptions;

  /// Card tap (carousel / grid). Default: `null` → inert (the container NEVER opens
  /// the player — a host wires this to open its own full-screen player for `item.id`).
  final void Function(LBVideoItem item)? onTapVideo;

  /// Carousel「查看更多 ›」header link. Default: `null` → inert.
  final VoidCallback? onSeeMore;

  /// Called after the first load with the ordered video feed (e.g. to drive a
  /// player swipe feed). Default: none.
  final void Function(List<LBVideoItem> videos)? onVideosChanged;

  /// Per-card product overlay resolver. The Flutter core `LBVideoItem` has NO
  /// `goods` field, so a real overlay can only come from the host here. Default:
  /// live cards show NO overlay; the opted-in demo fixtures use the seed overlays.
  final WidgetGoods? Function(LBVideoItem item)? goodsFor;

  /// When the live `/sdk/widget` fetch returns nothing, show demo fixtures + a
  /// 「示範資料」caption. Default: `false` (PRODUCTION-SAFE — never show fake data).
  final bool showsDemoFallbackWhenEmpty;

  /// Host-policy list auto-refresh interval. Default: 30s (zero / negative =
  /// disabled). Re-fetches page 1; skipped while showing demo and once a grid pages
  /// forward.
  final Duration listRefreshInterval;

  /// The design that composes the widget surface (carousel / grid). Default
  /// [MinimalDesign] — the verbatim minimal `WidgetOverlayView` (behavior unchanged). A host
  /// injects a custom [ReferenceUIDesign] to lay the cards out differently. Mirrors iOS
  /// `LivebuyWidgetConfig.design`.
  final ReferenceUIDesign design;

  /// Whether the widget cards load their REAL cover photo (`item.cover`) over the
  /// deterministic placeholder. Default `true` (runtime turnkey host — show real
  /// photos). The demo / golden surface tests construct the surfaces directly with the
  /// default `live: false`, so this flag does NOT affect goldens. Mirrors iOS
  /// `LivebuyWidgetConfig.live`.
  final bool live;

  const LivebuyWidgetConfig({
    this.sdkConfig,
    this.hostOptions,
    this.onTapVideo,
    this.onSeeMore,
    this.onVideosChanged,
    this.goodsFor,
    this.showsDemoFallbackWhenEmpty = false,
    this.listRefreshInterval = const Duration(seconds: 30),
    this.design = const MinimalDesign(),
    this.live = true,
  });
}

/// Turnkey drop-in widget list. Builds a `DefaultWidgetTemplate`, resolves the
/// theme, fetches `/sdk/widget` content itself (host-wired, D7) and feeds it into
/// the template, then renders the existing `WidgetOverlayView`. Self-manages the
/// load lifecycle: first page → optional demo fallback → grid pagination →
/// host-policy 30s list refresh.
class LivebuyWidget extends StatefulWidget {
  /// Shop ID (base-62 short code) whose `/sdk/widget` list to fetch + render.
  final String shopId;

  /// Layout mode. Default [WidgetContainerMode.carousel].
  final WidgetContainerMode mode;

  /// Optional per-instance wiring. Omitting it gives a fully-defaulted list.
  final LivebuyWidgetConfig config;

  const LivebuyWidget({
    super.key,
    required this.shopId,
    this.mode = WidgetContainerMode.carousel,
    this.config = const LivebuyWidgetConfig(),
  });

  @override
  State<LivebuyWidget> createState() => _LivebuyWidgetState();
}

class _LivebuyWidgetState extends State<LivebuyWidget> {
  DefaultWidgetTemplate? _template;
  late ReferenceUITheme _theme;
  List<Object?> _accumulated = const <Object?>[];
  int _page = 1;
  int _lastPage = 1;
  bool _usingDemo = false;
  bool _loading = false;
  Timer? _refreshTimer;

  Future<Map<String, Object?>> _fetchWidget(String shopId, int page) =>
      LivebuySDK.fetchWidget(shopId, page: page);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final cfg = widget.config.sdkConfig ?? await _safeSdkConfig();
    if (!mounted) return;
    final template = DefaultWidgetTemplate(
      sdkConfig: cfg,
      hostOptions: widget.config.hostOptions,
    );
    setState(() {
      _template = template;
      _theme = ReferenceUIThemeResolver.resolve(
        coreTheme: cfg.theme,
        hostOptions: widget.config.hostOptions,
      );
    });
    await _firstLoad(template);
    _startRefresh(template);
  }

  Future<SDKConfig> _safeSdkConfig() async {
    try {
      return await LivebuySDK.getSdkConfig();
    } catch (_) {
      // Not configured yet — render with defaults; the fetch below will fail and
      // the list stays empty (never fake data) rather than throwing.
      return SDKConfig.fallback;
    }
  }

  Future<void> _firstLoad(DefaultWidgetTemplate template) async {
    if (_loading) return;
    _loading = true;
    try {
      final r = await loadWidgetPage(
        fetchWidget: _fetchWidget,
        template: template,
        shopId: widget.shopId,
        mode: widget.mode,
        accumulated: const <Object?>[],
        page: 1,
        append: false,
      );
      if (!mounted) return;
      _accumulated = r.videoMaps;
      _page = r.currentPage;
      _lastPage = r.lastPage;
      if (lbWidgetShouldUseDemoFallback(
          r.videoMaps.isEmpty, widget.config.showsDemoFallbackWhenEmpty)) {
        final demo = lbWidgetDemoSnapshotParams(widget.mode);
        template.handleWidgetSnapshot(demo);
        _accumulated = (demo['videos'] as List).cast<Object?>();
        setState(() => _usingDemo = true);
      }
      widget.config.onVideosChanged?.call(template.content.current.videos);
    } catch (_) {
      // keep the list empty on fetch failure
    } finally {
      _loading = false;
    }
  }

  void _startRefresh(DefaultWidgetTemplate template) {
    final interval = widget.config.listRefreshInterval;
    if (interval <= Duration.zero) return;
    _refreshTimer = Timer.periodic(interval, (_) async {
      if (_loading) return;
      if (!lbWidgetShouldAutoRefreshTick(_usingDemo, _page)) return;
      _loading = true;
      try {
        final r = await loadWidgetPage(
          fetchWidget: _fetchWidget,
          template: template,
          shopId: widget.shopId,
          mode: widget.mode,
          accumulated: const <Object?>[],
          page: 1,
          append: false,
        );
        _accumulated = r.videoMaps;
        _page = r.currentPage;
        _lastPage = r.lastPage;
      } catch (_) {
        // keep prior content on refresh failure
      } finally {
        _loading = false;
      }
    });
  }

  void _onLoadMore() {
    final template = _template;
    if (template == null || _usingDemo || widget.mode != WidgetContainerMode.grid) return;
    if (_page >= _lastPage || _loading) return;
    _loading = true;
    loadWidgetPage(
      fetchWidget: _fetchWidget,
      template: template,
      shopId: widget.shopId,
      mode: widget.mode,
      accumulated: _accumulated,
      page: _page + 1,
      append: true,
    ).then((r) {
      _accumulated = r.videoMaps;
      _page = r.currentPage;
      _lastPage = r.lastPage;
    }).catchError((_) {
      // keep accumulated content on load-more failure
    }).whenComplete(() {
      _loading = false;
    });
  }

  /// Default-open player (dropin-widget-default-open-player-flutter): push a full-screen
  /// `LivebuyPlayer` route. `Navigator.push` (a top-level route) — not an in-tree widget — so the
  /// player is full-screen regardless of how small the widget is embedded (design D1). `onDismiss` /
  /// `onMinimize` pop the route (the default has no floating-preview target; design D1 tradeoff).
  /// Only reached when the host did NOT wire `config.onTapVideo` (lbWidgetEffectiveTap).
  void _openDefaultPlayer(BuildContext context, LBVideoItem item) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (routeCtx) => LivebuyPlayer(
        videoId: item.id,
        config: LivebuyPlayerConfig(
          design: widget.config.design,
          onDismiss: () => Navigator.of(routeCtx).pop(),
          onMinimize: () => Navigator.of(routeCtx).pop(),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final template = _template;
    if (template == null) return const SizedBox.shrink();

    // The Flutter core `LBVideoItem` has no `goods` field: live cards show NO
    // overlay unless the host supplies `goodsFor`; the opted-in demo uses the seeds.
    final WidgetGoods? Function(LBVideoItem item)? goodsFor = widget.config.goodsFor ??
        (_usingDemo ? WidgetSeeds.goodsFor : (LBVideoItem _) => null);

    // The design composes the widget surface (granularity A). Default MinimalDesign = the
    // verbatim `WidgetOverlayView` (which dispatches by the bound template content mode, so
    // both carousel / grid builders resolve to it — behavior unchanged); a host injects its own.
    final surfaceContext = WidgetSurfaceContext(
      template: template,
      theme: _theme,
      goodsFor: goodsFor,
      // Runtime turnkey host → load real cover photos (config.live default true). The
      // demo fallback also loads real covers when the host opts into live; demo seeds
      // carry no cover URL so the placeholder shows regardless.
      live: widget.config.live,
      // Tap routing (dropin-widget-default-open-player-flutter): external-platform live → open URL
      // (externalLiveAwareTap, highest precedence); non-external → host `onTapVideo` if wired, else the
      // DEFAULT that pushes a full-screen LivebuyPlayer route (lbWidgetEffectiveTap).
      onTapVideo: externalLiveAwareTap(
        lbWidgetEffectiveTap(
          widget.config.onTapVideo,
          (item) => _openDefaultPlayer(context, item),
        ),
      ),
      onSeeMore: widget.config.onSeeMore,
      onLoadMore: _onLoadMore,
    );
    final design = widget.config.design;
    final overlay = widget.mode == WidgetContainerMode.grid
        ? design.widgetGrid(surfaceContext)
        : design.widgetCarousel(surfaceContext);

    if (!_usingDemo) return overlay;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        overlay,
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(
            '（示範資料 — 未取得 widget 列表）',
            style: TextStyle(fontSize: 11, color: _theme.text.withValues(alpha: 0.6)),
          ),
        ),
      ],
    );
  }
}
