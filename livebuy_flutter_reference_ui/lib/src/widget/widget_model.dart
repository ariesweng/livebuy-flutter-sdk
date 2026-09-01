import 'package:livebuy_flutter/livebuy_flutter.dart' show LBVideoItem;
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show DefaultWidgetTemplate, LBWidgetContent, LBWidgetContentMode;

import 'widget_visibility.dart';

// WidgetModel — family-5 embedded-widget read-only snapshot bridge (Flutter).
//
// Spec: `reference-ui-rendering/spec.md` (family-5 widget, 1 shared card primitive
// + 4 embedded widget surfaces). Flutter sibling of iOS `WidgetModel.swift`
// (rb-ios-widget) and Android `WidgetModel.kt` (rb-android-widget).
//
// It bridges the headless template widget content view-model exposed by
// `DefaultWidgetTemplate.content` (`DefaultWidgetContent extends ChangeNotifier`,
// `/flutter-ui/lib/src/default_widget_content.dart`) into a read-only snapshot the
// family-5 Flutter surface widgets read. It is a pure read-only MIRROR — IDENTICAL
// pattern to family-1 `PlayerShellModel` / family-2 `FeedWinModel` / family-3
// `ProductSheetsModel` / family-4 `MomentsModel`:
//
//   - It owns NO second copy of authoritative state. Every getter reads the
//     template's own public snapshot (`content.current`, an immutable
//     `LBWidgetContent`) each call, so there is nothing to drift from the template.
//   - It adds NO pixels and adds NO accessor / view-model to `livebuy_flutter_ui`
//     (that would be a template-layer concern, out of scope here).
//
// ── widget host-bindable entry (DIFFERENT from player — family-5 binds the WIDGET
//    template, NOT the player template) ─────────────────────────────────────────
//   The host obtains the bound `DefaultWidgetTemplate` via
//   `LivebuyUI.widgetTemplate(LivebuyWidgetController controller) -> DefaultWidgetTemplate?`
//   (`/flutter-ui/lib/src/livebuy_ui.dart`; null when not installed / no attachment,
//   symmetric with iOS `LivebuyUI.widgetTemplate(for:)` / Android
//   `LivebuyUI.widgetTemplate(widget)` / RN attach handle), then passes it to the
//   container `WidgetOverlayView`, which constructs this model. The model reads
//   `template.content.current` (`LBWidgetContent`):
//     videos / mode / currentPage / lastPage / liveVideo / widgetColor / widgetBgcolor.
//
// ── CRITICAL: NO mutating forwarders (mirrors family-4) ──────────────────────────
//   The widget exits (cardTap / tapVideo / loadMore / floating close / minimized
//   expand / minimized close) are NOT template methods — they are HOST-WIRED
//   CONTAINER closures (mirrors iOS / Android widget surfaces: pure read-only, NO
//   mutating forwarder). So this model is a PURE read-only snapshot; it carries NO
//   mutating methods. The container (`WidgetOverlayView`) holds the host-wired exits
//   (`onTapVideo` / `onLoadMore` / `onTap` / `onClose` / `onExpand`). This layer MUST
//   NOT call core `simulate*` (`simulateCardTap` / `simulateClose`) / `requestLoadMore`.
//
// ── widgetColor / widgetBgcolor / productCard are RAW PASSTHROUGH ────────────────
//   `widgetColor` / `widgetBgcolor` are mirrored VERBATIM here — this model NEVER
//   normalizes or interprets them. Since rb-flutter-widget-embed-colors they DO drive
//   pixels, but only after the widget surfaces' single derivation entry point
//   (`ReferenceUIWidgetEmbedTheme.derive`, `widget-embed-colors`), which overlays them
//   onto the resolved `ReferenceUITheme` for THAT surface only. `ReferenceUIThemeResolver`
//   still never sees them, and the floating / minimized cards + the player + every sheet
//   keep the underived theme.
//
//   `productCard` (`product_card`) is the SAME KIND of raw passthrough: mirrored as a
//   plain getter, NEVER normalized / rewritten here (`null` means "the backend sent
//   nothing", a DIFFERENT fact from the backend sending `'inside'`). UNLIKE the two
//   colors it DOES drive pixels — but only after `CarouselCardView`'s single pure
//   fallback entry point (`normalizeProductCardMode`) turns it into a mode; this model
//   just hands the raw value down. rb-flutter-widget-product-card-modes.
//
// ── goods overlay (Flutter core delta) ───────────────────────────────────────────
//   The design's `LBPCarouselCard` carries a bottom dark-glass product overlay
//   (`item.product` → name / price). On iOS / Android the core `LBVideoItem` exposes
//   `goods: LBFeaturedGood?`; the Flutter core `LBVideoItem` (`/flutter/lib/src/
//   models.dart`) has NO `goods` field and there is NO Dart `LBFeaturedGood`. To
//   honour the spec's product-overlay requirement WITHOUT touching core, this
//   reference-ui layer carries a tiny READ-ONLY value type [WidgetGoods]
//   (`name` / `pic` / `price`) supplied BY VALUE for demo / golden cards. A live
//   template `LBVideoItem` carries no goods, so the live path renders the overlay
//   only when the host explicitly supplies a [WidgetGoods] (it never reaches back
//   into core / template). This is the Flutter analogue of the Android delta
//   ("`LBWidgetContent` has no `isLive` field → derive it").
//
// No Flutter-framework dependency here — pure reads + plain-literal demo seeds, so
// it stays unit-testable (see `docs/unit-test-discipline.md`).

/// A tiny read-only product-overlay value for the shared `CarouselCardView`'s
/// bottom dark-glass overlay (`LBPCarouselCard` `item.product`). Mirrors the
/// iOS / Android `LBFeaturedGood` overlay fields (`name` / `pic` / `price`) WITHOUT
/// depending on a core type the Flutter `LBVideoItem` does not carry. `price` is a
/// raw `String` (rendered verbatim after the「NT$ 」prefix); `pic` is a URL the
/// reference-ui never fetches (deterministic placeholder only). Supplied BY VALUE.
class WidgetGoods {
  /// Product name (1-line clamp in the overlay).
  final String name;

  /// Product thumbnail URL — NEVER fetched here (deterministic placeholder chip).
  final String pic;

  /// Raw price string, rendered verbatim after the「NT$ 」prefix.
  final String price;

  /// OPTIONAL raw original price — the source for the struck-through「was」price the
  /// `product_card == 'below'` product row draws (design `LBPCardProductRow`'s
  /// `product.was`). It is the Flutter stand-in for the iOS / Android
  /// `LBFeaturedGood.originalPrice`, which the Flutter core `LBVideoItem` has no
  /// equivalent of; since [WidgetGoods] is a reference-ui-owned by-value type, carrying
  /// it here needs NO core / view-model change. Defaults to `''` (so every pre-existing
  /// construction site is unchanged) → empty after trim → NO struck-through price is
  /// drawn at all. The `inside` overlay never draws one (the design's
  /// `LBPCardProductOverlay` has no `was`). Raw passthrough — it runs through the same
  /// currency de-duplication as [price].
  final String originalPrice;

  const WidgetGoods({
    required this.name,
    this.pic = '',
    required this.price,
    this.originalPrice = '',
  });
}

/// Read-only snapshot bridge for the family-5 widget surfaces. Wraps a live
/// [DefaultWidgetTemplate]; every accessor reads `template.content.current`
/// (`LBWidgetContent`) each call (no stored mirror). For demos / previews / golden
/// tests, construct with `template: null` — the getters then return the
/// deterministic [WidgetSeeds] values (a fully-populated content snapshot), so a
/// snapshot does NOT depend on a live widget.
class WidgetModel {
  /// The bound widget template, or `null` for demo / golden instances.
  final DefaultWidgetTemplate? template;

  /// Bridge a live widget template (host-supplied via
  /// `LivebuyUI.widgetTemplate(controller)`) — or `null` for the deterministic demo
  /// seeds (previews / golden / widget tests).
  const WidgetModel({this.template});

  /// The current host-bindable widget content snapshot
  /// (`template.content.current`). For the demo path (`template == null`) it returns
  /// the deterministic [WidgetSeeds.content]. Read-only; never mutated here.
  LBWidgetContent get content => template?.content.current ?? WidgetSeeds.content;

  // -- Surface-bound projections (read each call off [content]) -----------------

  /// Card-row data for carousel / grid (`content.videos`). Demo default: a mixed
  /// VOD + LIVE set ([WidgetSeeds.videos]).
  ///
  /// Hides in-app-unplayable lives (`type==2 && liveStatus==1 && liveurl==''`) on
  /// the live template path only (rb-flutter-widget-hide-urlless-live); the demo
  /// seeds (whose LIVE cards are type 2 / empty `liveurl`) render unchanged so the
  /// goldens stay byte-identical (parity iOS D4).
  List<LBVideoItem> get videos =>
      template != null ? visibleVideos(content.videos) : content.videos;

  /// Layout mode (`content.mode`): carousel / grid / floating / minimized.
  LBWidgetContentMode get mode => content.mode;

  /// Pagination cursor — current page (`content.currentPage`).
  int get currentPage => content.currentPage;

  /// Pagination cursor — last page (`content.lastPage`).
  int get lastPage => content.lastPage;

  /// The single floating live card (`content.liveVideo`); null when not floating /
  /// no live card. Same in-app-unplayable-live hiding (live path only): a urlless
  /// live resolves to null (floating renders nothing; minimized reports not-live).
  /// rb-flutter-widget-hide-urlless-live.
  LBVideoItem? get liveVideo =>
      template != null ? visibleLive(content.liveVideo) : content.liveVideo;

  /// Web-embed text color — RAW PASSTHROUGH (`content.widgetColor`;「預設色彩」`1` /
  /// 「色彩反轉」`2`, missing → `1`). NOT interpreted here: `WidgetOverlayView` reads it and
  /// hands it to the two card-bearing surfaces, which derive via
  /// `ReferenceUIWidgetEmbedTheme.derive` (rb-flutter-widget-embed-colors).
  int get widgetColor => content.widgetColor;

  /// Web-embed background color — RAW PASSTHROUGH (`content.widgetBgcolor`; a hex string,
  /// or the empty string `""` which is the backend's「透明」representation — NOT an Int).
  /// NOT interpreted here; same single derivation entry point as [widgetColor], which
  /// treats `""` / `null` / unparseable alike as "leave `background` alone".
  String? get widgetBgcolor => content.widgetBgcolor;

  /// The carousel card's product-card display mode (`content.productCard`) — the SAME
  /// kind of RAW PASSTHROUGH as [widgetColor] / [widgetBgcolor]: mirrored verbatim, NOT
  /// normalized here. `null` means "the backend sent nothing", a DIFFERENT fact from the
  /// backend sending `'inside'`, so this layer MUST NOT substitute the backend default —
  /// the `inside` fallback belongs to `CarouselCardView`
  /// (`normalizeProductCardMode`). Demo path (`template == null`) → `null`.
  /// rb-flutter-widget-product-card-modes.
  String? get productCard => content.productCard;

  // -- Shared LIVE derivation (single source for ALL family-5 surfaces) ----------

  /// Whether an [LBVideoItem] is a LIVE card. Core `LBVideoItem` carries only
  /// `liveStatus: int` (no distinct upcoming / replay flag). Parity with iOS
  /// `CarouselCardView.isLive` (`liveStatus == 1`) — any other value → VOD. This is
  /// the SINGLE source of LIVE truth shared by `CarouselCardView` (kind badge),
  /// `FloatingWidgetView`, and `MinimizedWidgetView` (which has no `isLive` field
  /// and derives it from `liveVideo?.liveStatus`, per the Android delta). Documented
  /// approximation (spec §family-5): upcoming / replay collapse into VOD.
  static bool isLive(LBVideoItem item) => item.liveStatus == 1;

  /// The minimized pill's derived LIVE flag (`liveVideo?.liveStatus` indicates
  /// live). `LBWidgetContent` has NO `isLive` field — derive it from `liveVideo`
  /// (same source as the `CarouselCardView` kind badge). Null `liveVideo` → false.
  bool get minimizedIsLive {
    final v = liveVideo;
    return v != null && isLive(v);
  }
}

// MARK: - Deterministic demo seeds (previews / golden / widget tests)

/// Plain-literal deterministic seeds for the family-5 surfaces' previews + the
/// per-surface golden / widget tests. Constructed via the public core `LBVideoItem`
/// init + the reference-ui [WidgetGoods] overlay value, so a snapshot does NOT
/// depend on a live widget. Mirrors the iOS demo data (the `LBVideoItem.demo`
/// fixtures) and the Android `WidgetSeeds`.
///
/// The golden baselines each drive ONE surface from these seeds (names parity with
/// iOS / Android):
///   • [vodWithGoods] (+ its [vodWithGoodsGoods]) — `carousel-card-vod-with-goods`.
///   • [videos] — `carousel-header-and-row` (the carousel row).
///   • [videos] + [gridCurrentPage] / [gridLastPage] — `video-shop-grid-load-more`.
///   • [liveVideo] — `floating-widget-live-preview`.
///   • [liveVideo] (minimized) — `minimized-widget-live`.
class WidgetSeeds {
  WidgetSeeds._();

  /// `liveStatus == 1` is the LIVE sentinel (parity with iOS / Android
  /// `CarouselCardView.isLive` — `liveStatus == 1` → LIVE; any other value → VOD).
  /// VOD cards use `liveStatus == 0`.
  static const int liveSentinel = 1;
  static const int vodSentinel = 0;

  /// A deterministic VOD card with a product overlay (`liveStatus == 0`,
  /// `duration == 28` → formatted `00:28`). Drives `carousel-card-vod-with-goods`.
  static final LBVideoItem vodWithGoods = _demoVideo(
    id: 'widget-vod-001',
    title: '週五美妝直播・新品開箱',
    live: false,
    duration: 28,
  );

  /// The product card paired with [vodWithGoods] (drawn by `CarouselCardView` — the
  /// bottom dark-glass overlay in `inside`, the surface-styled row in `below`).
  /// Reference-ui value (NOT a core type).
  ///
  /// `originalPrice` is exercised ONLY by the `below` product row (the `inside` overlay
  /// never draws a struck-through「was」price — design `LBPCardProductOverlay` has none),
  /// so seeding it here gives the `below` goldens a struck-through price WITHOUT moving
  /// any pre-existing `inside` baseline.
  static const WidgetGoods vodWithGoodsGoods = WidgetGoods(
    name: '玫瑰精萃保濕水',
    pic: '',
    price: '880',
    originalPrice: '1180',
  );

  /// A deterministic mixed VOD + LIVE card set for the carousel row / grid
  /// (`carousel-header-and-row` / `video-shop-grid-load-more`). FIXED SMALL set —
  /// the surfaces draw the visible first N in a plain `Row` / `Column` (NO lazy /
  /// scroll). All carry a goods overlay via [goodsFor] (deterministic).
  static final List<LBVideoItem> videos = [
    _demoVideo(
        id: 'widget-vod-001',
        title: '週五美妝直播・新品開箱',
        live: false,
        duration: 28),
    _demoVideo(
        id: 'widget-live-002',
        title: '早春保養 LIVE 開賣',
        live: true,
        duration: 0),
    _demoVideo(
        id: 'widget-vod-003',
        title: '主廚私房快煮鍋具',
        live: false,
        duration: 754),
    _demoVideo(
        id: 'widget-live-004',
        title: '週年慶必囤清單 LIVE',
        live: true,
        duration: 0),
  ];

  /// The single floating live card (`floating-widget-live-preview` /
  /// `minimized-widget-live`). `liveStatus == 1` → drawn as LIVE; carries a goods
  /// overlay via [goodsFor].
  static final LBVideoItem liveVideo = _demoVideo(
    id: 'widget-live-100',
    title: '今晚 8 點 · 春季新品快閃',
    live: true,
    duration: 0,
  );

  /// The UPCOMING (直播預告) fixture for the shared `CarouselCardView` golden
  /// (`carousel-card-upcoming`): NOT live (`liveStatus == 0`) + a FAR-FUTURE
  /// `publishAt` (`2099-01-01 20:00:00`, always parses as future → golden-stable) so
  /// the card renders the UPCOMING treatment (dark mask + centred「1月1日」/「20:00」).
  /// Pairs with [vodWithGoodsGoods] for the bottom product overlay (the upcoming mask
  /// sits above it).
  static final LBVideoItem upcomingVideo = _demoVideo(
    id: 'widget-upcoming-001',
    title: '週五美妝直播・新品開箱',
    live: false,
    duration: 0,
    type: 2, // 後端 scheduled-live 訊號（rb-flutter-widget-upcoming-type，問題 6）。
    publishAt: '2099-01-01 20:00:00',
  );

  /// Pagination seed: current page (`video-shop-grid-load-more` shows the
  /// 「載入更多影片…」footer because `currentPage < lastPage`).
  static const int gridCurrentPage = 1;

  /// Pagination seed: last page.
  static const int gridLastPage = 3;

  /// The deterministic demo widget content snapshot returned for the demo path
  /// (`WidgetModel(template: null)`). A carousel snapshot by default; the container
  /// / surfaces select the relevant fields per `mode`. Built from the seed videos +
  /// pagination + live card.
  static final LBWidgetContent content = LBWidgetContent(
    videos: videos,
    mode: LBWidgetContentMode.carousel,
    currentPage: gridCurrentPage,
    lastPage: gridLastPage,
    liveVideo: liveVideo,
  );

  /// A deterministic goods overlay keyed off a card's `id` (so the carousel row /
  /// grid cards each show a stable, distinct product overlay in goldens without a
  /// core `goods` field). Pure mapping — NO network, NO randomness.
  static WidgetGoods goodsFor(LBVideoItem item) {
    switch (item.id) {
      case 'widget-vod-001':
        return vodWithGoodsGoods;
      case 'widget-live-002':
        return const WidgetGoods(name: '輕透氣墊粉餅', pic: '', price: '1,280');
      case 'widget-vod-003':
        return const WidgetGoods(name: '不沾深炒鍋', pic: '', price: '1,680');
      case 'widget-live-004':
        return const WidgetGoods(name: '保暖羊毛圍巾', pic: '', price: '990');
      case 'widget-live-100':
        return const WidgetGoods(name: '限量春季禮盒', pic: '', price: '2,180');
      default:
        return const WidgetGoods(name: '精選好物', pic: '', price: '680');
    }
  }

  /// Build a deterministic demo `LBVideoItem` via the verified 18-param core init
  /// (`/flutter/lib/src/models.dart`). `live` toggles `liveStatus` (1 vs 0); the
  /// goods overlay is supplied separately via [WidgetGoods] (Flutter core
  /// `LBVideoItem` has no `goods` field).
  /// An EXTERNAL (Facebook) floating live fixture (external-live-watch): a live whose
  /// `liveurl` host is `www.facebook.com`, so a tap routes out to Facebook (not the
  /// in-app player).
  static final LBVideoItem externalLiveVideo = _demoVideo(
    id: 'widget-live-fb-001',
    title: 'Facebook 直播・現正開賣',
    live: true,
    duration: 0,
    liveurl: 'https://www.facebook.com/870374236326161/videos/1024740573341806',
  );

  static LBVideoItem _demoVideo({
    required String id,
    required String title,
    required bool live,
    required int duration,
    String publishAt = '2026-06-06 20:00:00',
    int? type,
    // 外部平台直播 liveurl（預設 ''，使既有種子 byte-identical；external-live-watch）。
    String liveurl = '',
  }) =>
      LBVideoItem(
        id: id,
        // 後端 type：live / scheduled-live（upcoming）→ 2、一般 VOD → 1
        // （rb-flutter-widget-upcoming-type，問題 6）。upcoming 種子明確傳 type: 2。
        type: type ?? (live ? 2 : 1),
        title: title,
        sessionName: null,
        cover: '',
        preview: '',
        duration: duration,
        publishAt: publishAt,
        watchNum: 0,
        pvNum: 0,
        liveStatus: live ? liveSentinel : vodSentinel,
        pin: 0,
        showPvNum: 0,
        liveurl: liveurl,
        playbackurl: '',
        previewTime: '',
        showStock: false,
      );
}
