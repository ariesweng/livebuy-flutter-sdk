// widget_data — pure, injectable data-driving helpers for the drop-in
// `LivebuyWidget` container (introduce-dropin-widget-container-flutter).
//
// Parity source: iOS `LivebuyWidget.swift` pure guards
// (`lbWidgetShouldUseDemoFallback` / `lbWidgetShouldAutoRefreshTick`) + the RN
// `widgetData.ts`. On Flutter the widget data is HOST-WIRED (design D7): the
// container fetches each page itself via core `LivebuySDK.fetchWidget` and feeds
// the result into `DefaultWidgetTemplate.handleWidgetSnapshot` / `handleWidgetColors`.
// Flutter is SIMPLER than RN — `handleWidgetSnapshot` reads the snake_case wire
// itself (no `decodeWidgetSnapshot` step). The snapshot fed to it is nevertheless
// HAND-BUILT here (accumulated `videos` + the container-chosen `mode` + pagination +
// the response's raw `product_card`), NOT the response forwarded wholesale, because
// grid load-more has to accumulate video maps across pages. Consequence: every wire
// key the view-model reads must be listed explicitly in `loadWidgetPage` — see the
// warning on that function. These helpers isolate that logic from widgets so it is
// unit-testable with a fake fetcher + a real template.

import 'package:livebuy_flutter/livebuy_flutter.dart' show LBVideoItem, LBWidgetColors;
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart' show DefaultWidgetTemplate;

import '../widget/widget_model.dart' show WidgetSeeds;

/// Container layout mode. carousel / grid only (floating / minimized need a single live).
enum WidgetContainerMode { carousel, grid }

/// Wire string for a container mode (`DefaultWidgetContent.handleWidgetSnapshot`
/// reads `params['mode']`).
String widgetModeWire(WidgetContainerMode mode) =>
    mode == WidgetContainerMode.grid ? 'grid' : 'carousel';

/// One-shot widget content fetcher (injected so tests can fake it). Matches
/// `LivebuySDK.fetchWidget(shopId, page: page)`.
typedef WidgetFetcher = Future<Map<String, Object?>> Function(String shopId, int page);

/// Demo-fallback decision: show fixtures only when the live fetch is empty AND the
/// host opted in. Pure (parity with iOS `lbWidgetShouldUseDemoFallback`).
bool lbWidgetShouldUseDemoFallback(bool videosEmpty, bool enabled) =>
    videosEmpty && enabled;

/// Auto-refresh tick guard: skip while showing demo fixtures, and skip once a grid
/// has paged forward (`currentPage > 1`) — re-fetching page 1 would collapse the
/// accumulated pages. Pure (parity with iOS `lbWidgetShouldAutoRefreshTick`).
bool lbWidgetShouldAutoRefreshTick(bool usingDemo, int currentPage) =>
    !usingDemo && currentPage <= 1;

/// Non-external card-tap routing (dropin-widget-default-open-player-flutter, parity iOS
/// `effectiveOnTapVideo` / Android / RN `lbWidgetEffectiveTap`): the host's [hostTap] when wired
/// (full override — the default never runs), else [openDefaultPlayer] (opens the in-app player). A
/// host wanting tap to be a true no-op passes `onTapVideo: (_) {}`. Pure so the container and tests
/// share one implementation. External-platform lives never reach here (handled by the enclosing
/// `externalLiveAwareTap`, highest precedence).
void Function(LBVideoItem) lbWidgetEffectiveTap(
  void Function(LBVideoItem)? hostTap,
  void Function(LBVideoItem) openDefaultPlayer,
) =>
    hostTap ?? openDefaultPlayer;

/// Grid pagination accumulation at the raw video-map level. `append` → concat the
/// new page onto the prior accumulated maps (grid load-more); else → replace
/// (first load / carousel / refresh).
List<Object?> accumulateVideoMaps(
  List<Object?> prev,
  List<Object?> next, {
  required bool append,
}) =>
    append ? [...prev, ...next] : List<Object?>.from(next);

/// Build the host-bindable [LBWidgetColors] from a raw `fetchWidget` map. Returns
/// `null` when NEITHER color key is present (nothing to forward — the template keeps
/// its core defaults). Raw passthrough — semantics NOT interpreted.
LBWidgetColors? widgetColorsFromMap(Map<String, Object?> raw) {
  final color = raw['widget_color'];
  final bg = raw['widget_bgcolor'];
  final hasColor = color is num;
  final hasBg = bg is String;
  if (!hasColor && !hasBg) return null;
  return LBWidgetColors(
    widgetColor: hasColor ? color.toInt() : 1,
    widgetBgcolor: hasBg ? bg : null,
  );
}

/// The deterministic demo snapshot params fed (via `handleWidgetSnapshot`) when the
/// live fetch is empty AND the host opted in. Built from [WidgetSeeds] for the
/// chosen `mode` (parity with iOS `demoModel(for:)`). Seed videos are serialized to
/// camelCase maps so the snake_case `handleWidgetSnapshot` wire path decodes them.
Map<String, Object?> lbWidgetDemoSnapshotParams(WidgetContainerMode mode) => {
      'videos': WidgetSeeds.videos.map(_videoToWireMap).toList(),
      'mode': widgetModeWire(mode),
      'current_page': WidgetSeeds.gridCurrentPage,
      'last_page': WidgetSeeds.gridLastPage,
    };

/// Serialize an [LBVideoItem] back into the camelCase wire map that
/// `DefaultWidgetContent.handleWidgetSnapshot` reads (via `LBVideoItem.fromMap`).
/// The Flutter core `LBVideoItem` has no `toMap`, so the demo path builds it here.
Map<String, Object?> _videoToWireMap(LBVideoItem v) => {
      'id': v.id,
      'type': v.type,
      'title': v.title,
      'sessionName': v.sessionName,
      'cover': v.cover,
      'preview': v.preview,
      'duration': v.duration,
      'publishAt': v.publishAt,
      'watchNum': v.watchNum,
      'pvNum': v.pvNum,
      'liveStatus': v.liveStatus,
      'pin': v.pin,
      'showPvNum': v.showPvNum,
      'liveurl': v.liveurl,
      'playbackurl': v.playbackurl,
      'previewTime': v.previewTime,
      'showStock': v.showStock,
    };

/// Decoded pagination result the container stores to drive load-more / refresh.
class LoadWidgetPageResult {
  final List<Object?> videoMaps;
  final int currentPage;
  final int lastPage;
  const LoadWidgetPageResult(this.videoMaps, this.currentPage, this.lastPage);
}

List<Object?> _videoMapsFrom(Object? raw) =>
    raw is List ? List<Object?>.from(raw) : const <Object?>[];

/// Fetch ONE page of widget content and feed it into the template:
/// `fetchWidget` → accumulate raw video maps → inject `mode` →
/// `handleWidgetSnapshot`; raw colors → `handleWidgetColors`. Returns the decoded
/// pagination so the container updates its page / accumulated state. Pure of widgets
/// (the fetcher + template are injected) so it is unit-testable with fakes.
///
/// ⚠️ The snapshot map below is HAND-BUILT, not the response forwarded wholesale: every
/// wire key the view-model reads must be listed here EXPLICITLY, or it is silently lost.
/// `product_card` was exactly that (rb-flutter-widget-product-card-modes) — its failure
/// shape is nasty because nothing looks broken: `LBWidgetContent.productCard` just stays
/// `null` on the drop-in path forever, so the card layer falls back to `inside` and
/// renders perfectly. Adding a wire key to `DefaultWidgetContent.handleWidgetSnapshot`
/// therefore ALWAYS means adding it here too.
Future<LoadWidgetPageResult> loadWidgetPage({
  required WidgetFetcher fetchWidget,
  required DefaultWidgetTemplate template,
  required String shopId,
  required WidgetContainerMode mode,
  required List<Object?> accumulated,
  required int page,
  required bool append,
}) async {
  final raw = await fetchWidget(shopId, page);
  final videos = accumulateVideoMaps(accumulated, _videoMapsFrom(raw['videos']), append: append);
  final currentPage = (raw['current_page'] as num?)?.toInt() ?? page;
  final lastPage = (raw['last_page'] as num?)?.toInt() ?? currentPage;
  template.handleWidgetSnapshot(<String, Object?>{
    'videos': videos,
    'mode': widgetModeWire(mode),
    'current_page': currentPage,
    'last_page': lastPage,
    // `product_card` (root, String — `inside` / `below` / `hidden`) forwarded RAW, with
    // NO type check of our own: `DefaultWidgetContent.productCardFrom` (`raw is String ?
    // raw : null`) is the single authority for that, and a second copy here would only
    // be a copy that can drift. A missing key reads as `null` → "the backend sent
    // nothing", which the view-model keeps distinct from an explicit `"inside"`.
    // Substituting the backend default is the CARD layer's job
    // (`normalizeProductCardMode`), never this one.
    'product_card': raw['product_card'],
  });
  final colors = widgetColorsFromMap(raw);
  if (colors != null) template.handleWidgetColors(colors);
  return LoadWidgetPageResult(videos, currentPage, lastPage);
}
