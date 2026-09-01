import 'package:flutter/foundation.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart';

// widget-content-template — Default widget template 內容 view-model
// (behaviour / view-model layer; NO pixels).
//
// Spec ref: ui-template-foundation/spec.md
//   § "Default Template Widget 內容 view-model 暴露"
//   (+ MODIFIED "Default Template Bindable State 變更通知").
// Design: design.md D2 / D3 / D4 / D7.
//
// core stays headless: it owns the widget state machine (`videos` / `mode` /
// `currentPage` / `lastPage` / `liveVideo` / `isClosed`), `loadFirstPage` /
// `requestLoadMore`, and POST `/sdk/widget`. This model MIRRORS that state into a
// host-bindable snapshot so the host / reference-ui can draw `widgets.jsx`
// (`LBPCarousel` / `LBPCarouselCard` / `LBPVideoShop` / `LBPFloatingWidget`). The
// template draws NO cards / rows / floating window / minimized bubble.
//
// Flutter wiring note (design D7 — bridge): on Flutter the core `LivebuyWidget`
// is a native platform view; its content is delivered over the per-view widget
// bridge, NOT held in a Dart-readable state. So the widget content is HOST-WIRED:
// the host feeds the content snapshot via [handleWidgetSnapshot] reading the
// snake_case wire keys (`videos` / `current_page` / `last_page` / `mode` /
// `is_closed` / `product_card`), and feeds the web-embed colors via
// [handleWidgetColors] off the
// core `LivebuyWidgetController.onWidgetResponse` (LBWidgetColors — supplied by
// widget-bridge-color-core). `minimized` is DERIVED here from
// `mode == floating && isClosed` (NO new core enum). Missing colors fall back to
// the core DTO defaults (`widget_color = 1` / `widget_bgcolor = null`); a missing
// `product_card` is `null` and is NEVER defaulted to `inside`
// (widget-product-card-content-template). View-model
// SHAPE + notification behaviour are four-platform identical; only ingestion
// differs (inherent to Flutter's bridge architecture).

/// Host-bindable widget layout mode for `widgets.jsx`. `carousel` / `grid` /
/// `floating` map one-to-one to the core `WidgetMode`; `minimized` is a
/// TEMPLATE-DERIVED state (core floating widget `isClosed == true`, aligning the
/// design `LBPMinimizedWidget` bubble — core has NO `minimized` enum value).
enum LBWidgetContentMode {
  carousel,
  grid,
  floating,
  minimized,
}

/// One immutable host-bindable widget content snapshot. Mirrors the core
/// `LivebuyWidget` read surface plus the `/sdk/widget` response-root settings —
/// the web-embed colors and the product-card display mode (all raw passthrough).
/// The view-model does NOT hold a second source of truth — it reflects the
/// bridged snapshot + colors only.
@immutable
class LBWidgetContent {
  /// Card-row data (carousel / grid). Mirrors core `LivebuyWidget.videos`.
  final List<LBVideoItem> videos;

  /// Layout mode. `carousel` / `grid` / `floating` mirror the core `WidgetMode`;
  /// `minimized` is derived from `mode == floating && isClosed` (D3).
  final LBWidgetContentMode mode;

  /// Pagination cursor — current page. Mirrors core `LivebuyWidget.currentPage`.
  final int currentPage;

  /// Pagination cursor — last page. Mirrors core `LivebuyWidget.lastPage`.
  final int lastPage;

  /// The single floating live card (floating mode). Mirrors core
  /// `LivebuyWidget.liveVideo`; null when not floating / no live card.
  final LBVideoItem? liveVideo;

  /// Web-embed text color (raw passthrough; 1=black / 2=white — NOT interpreted
  /// here). Source: `widget-bridge-color-core` (LBWidgetColors); missing → 1.
  final int widgetColor;

  /// Web-embed background color (raw passthrough; Int 1=transparent normalised to
  /// `"1"`, otherwise hex — NOT interpreted here). Source:
  /// `widget-bridge-color-core` (LBWidgetColors); missing → null.
  final String? widgetBgcolor;

  /// Carousel card's product-card display mode (`product_card`) — raw
  /// passthrough. Backend domain `below` / `inside` / `hidden`, backend default
  /// `inside`; an unrecognized value is kept verbatim, never normalised.
  ///
  /// `null` means THE BACKEND SENT NOTHING (the linetv branch omits it,
  /// `/sdk/widget/live` does not carry it, and nothing has loaded yet) — a
  /// DIFFERENT fact from the backend sending `inside`, so this layer never
  /// substitutes the backend default. Applying a default is the reference-ui
  /// layer's job (widget-product-card-content-template D2). Source:
  /// `widget-product-card-bridge-flutter` (the snake_case `product_card` key on
  /// the `fetchWidget` map fed to [DefaultWidgetContent.handleWidgetSnapshot]).
  final String? productCard;

  const LBWidgetContent({
    this.videos = const [],
    this.mode = LBWidgetContentMode.carousel,
    this.currentPage = 0,
    this.lastPage = 0,
    this.liveVideo,
    this.widgetColor = 1,
    this.widgetBgcolor,
    this.productCard,
  });

  LBWidgetContent copyWith({
    List<LBVideoItem>? videos,
    LBWidgetContentMode? mode,
    int? currentPage,
    int? lastPage,
    Object? liveVideo = _sentinel,
    int? widgetColor,
    Object? widgetBgcolor = _sentinel,
    Object? productCard = _sentinel,
  }) =>
      LBWidgetContent(
        videos: videos ?? this.videos,
        mode: mode ?? this.mode,
        currentPage: currentPage ?? this.currentPage,
        lastPage: lastPage ?? this.lastPage,
        liveVideo: identical(liveVideo, _sentinel)
            ? this.liveVideo
            : liveVideo as LBVideoItem?,
        widgetColor: widgetColor ?? this.widgetColor,
        widgetBgcolor: identical(widgetBgcolor, _sentinel)
            ? this.widgetBgcolor
            : widgetBgcolor as String?,
        // `_sentinel` (not `??`) so a caller can set productCard back to null —
        // "this response carried no product_card" must be expressible.
        productCard: identical(productCard, _sentinel)
            ? this.productCard
            : productCard as String?,
      );

  static const Object _sentinel = Object();

  @override
  bool operator ==(Object other) =>
      other is LBWidgetContent &&
      listEquals(other.videos, videos) &&
      other.mode == mode &&
      other.currentPage == currentPage &&
      other.lastPage == lastPage &&
      identical(other.liveVideo, liveVideo) &&
      other.widgetColor == widgetColor &&
      other.widgetBgcolor == widgetBgcolor &&
      other.productCard == productCard;

  @override
  int get hashCode => Object.hash(
        Object.hashAll(videos),
        mode,
        currentPage,
        lastPage,
        liveVideo,
        widgetColor,
        widgetBgcolor,
        productCard,
      );
}

/// Widget content view-model. A [ChangeNotifier] so the host binds with
/// `ListenableBuilder` and re-reads [current] on change (Flutter's coalesced
/// notification mechanism, parity with the other Default view-models). Each
/// mutator is diff-then-notify: a real change fires EXACTLY ONE notification; an
/// unchanged snapshot does NOT notify.
///
/// The view-model owns NO data source of truth (single source = core
/// `LivebuyWidget` + the `widget-bridge-color-core` color snapshot); it only
/// mirrors / adapts the bridged values, deriving `minimized` from
/// `mode == floating && isClosed` (D2 / D3).
class DefaultWidgetContent extends ChangeNotifier {
  LBWidgetContent _current = const LBWidgetContent();

  /// Current widget content snapshot. Defaults to an empty carousel snapshot
  /// (no videos / page 0 / color fallback) until the first bridge feed.
  LBWidgetContent get current => _current;

  /// Pure mapping: a core `WidgetMode` wire string + `isClosed` → the host-bindable
  /// [LBWidgetContentMode]. `floating` + `isClosed == true` → `minimized` (D3);
  /// unknown / inapplicable mode strings fall back to `carousel` (MUST NOT throw,
  /// MUST NOT break the state model). Accepts the snake_case-ish wire forms the
  /// bridge may emit (`carousel` / `grid` / `floating`, case-insensitive).
  static LBWidgetContentMode modeFrom(String? wireMode, {bool isClosed = false}) {
    switch ((wireMode ?? '').toLowerCase()) {
      case 'grid':
        return LBWidgetContentMode.grid;
      case 'floating':
        return isClosed
            ? LBWidgetContentMode.minimized
            : LBWidgetContentMode.floating;
      case 'carousel':
      default:
        return LBWidgetContentMode.carousel;
    }
  }

  /// Ingest a host-fed widget content snapshot read from the snake_case bridge
  /// wire (D7). Reads `videos` (a list of `LBVideoItem` maps), `current_page` /
  /// `last_page` (Int), `mode` (String) + `is_closed` (Bool → `minimized`
  /// derivation), `live_video` (an `LBVideoItem` map; null when absent), and
  /// `product_card` (String; the carousel card's display mode — raw passthrough).
  /// The web-embed colors are NOT read here — they arrive via [handleWidgetColors]
  /// (different bridge call, `onWidgetResponse`). Diff-then-notify: an identical
  /// snapshot does NOT notify. Tolerant of the dynamic shapes
  /// `StandardMessageCodec` produces.
  ///
  /// `product_card` rides THIS call rather than [handleWidgetColors] because
  /// `LBWidgetColors` deliberately carries no such field on Flutter
  /// (widget-product-card-bridge-flutter adds no Dart type); the value reaches
  /// Dart on the raw snake_case `LivebuySDK.fetchWidget` map, which is exactly
  /// this method's input. A missing `product_card` key is `null` — the same
  /// "absent → default" group as `videos` / `mode` / `live_video`, NOT the
  /// "absent → keep previous" group `current_page` / `last_page` belongs to,
  /// because the argument is one response's complete root snapshot rather than a
  /// patch (design D4). The backend default `inside` is NEVER substituted.
  @internal
  void handleWidgetSnapshot(Map<String, Object?> params) {
    final videos = _videosFrom(params['videos']);
    final mode = modeFrom(
      params['mode'] as String?,
      isClosed: params['is_closed'] == true,
    );
    final liveVideo = _videoItemFrom(params['live_video']);
    final next = _current.copyWith(
      videos: videos,
      mode: mode,
      currentPage: (params['current_page'] as num?)?.toInt() ?? _current.currentPage,
      lastPage: (params['last_page'] as num?)?.toInt() ?? _current.lastPage,
      liveVideo: liveVideo,
      productCard: productCardFrom(params['product_card']),
    );
    _apply(next);
  }

  /// Pure decode of the `product_card` wire value: a String passes through
  /// VERBATIM (whitelist values and unrecognized ones alike — no normalisation);
  /// anything else (missing key, JSON null, or a non-String the bridge somehow
  /// produced) becomes `null`. MUST NOT throw and MUST NOT substitute the backend
  /// default `inside` (widget-product-card-content-template D2).
  static String? productCardFrom(Object? raw) => raw is String ? raw : null;

  /// Ingest the web-embed colors off the core widget controller's
  /// `onWidgetResponse` (LBWidgetColors — widget-bridge-color-core). Raw
  /// passthrough: the colors are NOT interpreted. When colors are absent the host
  /// simply never calls this and the snapshot keeps the core defaults
  /// (`widgetColor = 1` / `widgetBgcolor = null`). Diff-then-notify.
  @internal
  void handleWidgetColors(LBWidgetColors colors) {
    _apply(_current.copyWith(
      widgetColor: colors.widgetColor,
      widgetBgcolor: colors.widgetBgcolor,
    ));
  }

  /// Update just the floating `isClosed` derivation (host echoes `simulateClose`
  /// / a re-expand). Re-derives `mode` from the CURRENT base mode: when the base
  /// is floating, `isClosed` toggles between `floating` and `minimized`. No-op
  /// when not floating-derived. Diff-then-notify.
  @internal
  void handleFloatingClosed(bool isClosed) {
    if (_current.mode != LBWidgetContentMode.floating &&
        _current.mode != LBWidgetContentMode.minimized) {
      return;
    }
    _apply(_current.copyWith(
      mode: isClosed
          ? LBWidgetContentMode.minimized
          : LBWidgetContentMode.floating,
    ));
  }

  /// Reset on teardown / new shop. Notifies iff it actually cleared a non-default
  /// snapshot (parity with the other view-models' `clear`).
  void clear() {
    if (_current == const LBWidgetContent()) return;
    _current = const LBWidgetContent();
    notifyListeners();
  }

  void _apply(LBWidgetContent next) {
    if (next == _current) return;
    _current = next;
    notifyListeners();
  }

  /// Decode a `videos` wire value into a list of [LBVideoItem]. Tolerant of the
  /// dynamic shapes the bridge produces (List of Map); non-map entries dropped.
  static List<LBVideoItem> _videosFrom(Object? raw) {
    if (raw is! List) return const [];
    final out = <LBVideoItem>[];
    for (final e in raw) {
      final item = _videoItemFrom(e);
      if (item != null) out.add(item);
    }
    return out;
  }

  /// Decode a single `LBVideoItem` wire map (or null). Tolerant of dynamic maps.
  static LBVideoItem? _videoItemFrom(Object? raw) {
    if (raw is! Map) return null;
    return LBVideoItem.fromMap(Map<Object?, Object?>.from(raw));
  }
}
