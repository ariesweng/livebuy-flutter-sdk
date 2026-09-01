/// Livebuy Flutter reference-UI (drop-in default pixel) layer.
///
/// This is the Flutter parity of the iOS `LivebuyReferenceUI` SPM product and
/// the Android `:livebuy-reference-ui` Gradle module — the ONLY Flutter layer
/// that contains widget pixels. It binds the existing `livebuy_flutter_ui`
/// (template) host-bindable view-models and paints them; the template / core
/// layers stay zero-pixel headless.
///
/// Dependency direction is strictly unidirectional:
///   livebuy_flutter_reference_ui -> livebuy_flutter_ui -> livebuy_flutter
library livebuy_flutter_reference_ui;

export 'src/reference_ui_theme.dart';
// rb-flutter-widget-embed-colors — the widget-scope `/sdk/widget` embed-color derivation
// (`widget_color` / `widget_bgcolor` → `text` / `background`, widget surfaces ONLY). A
// pure function that runs AFTER `ReferenceUIThemeResolver`; the resolver itself still
// never sees these two values. Exported so a host-supplied `ReferenceUIDesign` composing
// the bare surfaces can reproduce the same derivation.
export 'src/reference_ui_widget_embed_theme.dart';
export 'src/livebuy_reference_ui_smoke.dart';

// family-1 player-shell (rb-flutter-player-shell). The read-only snapshot bridge
// + container are landed by this skeleton; the four surface widgets
// (PlayerHeaderBarView / OperationRailView / VideoInfoPanelView /
// LiveOverlayChromeView) are landed by the parallel Surfaces agents — until then
// the container's surface imports are unresolved (expected skeleton state, parity
// with iOS / Android: the skeleton fixes call-sites, surfaces land the types).
export 'src/playershell/player_shell_model.dart';
export 'src/playershell/player_shell_view.dart';
// rb-flutter-upcoming-intro-chrome — 直播預告 (upcoming) 倒數背景 surface + 純函式
// scheduledDate / scheduledTime (shared with the widget CarouselCardView upcoming overlay).
export 'src/playershell/upcoming_countdown_view.dart';

// family-2 feed-win (rb-flutter-feed-win). The read-only snapshot bridge +
// container are landed by this skeleton; the three surface widgets (ChatFeedView /
// WinEntryView / WinClaimSheetView) are landed by the parallel Surfaces agents —
// until then the container's surface imports are unresolved (expected skeleton
// state, parity with iOS / Android: the skeleton fixes call-sites, surfaces land
// the types).
export 'src/feedwin/feed_win_model.dart';
export 'src/feedwin/feed_win_view.dart';

// family-3 product-sheets (rb-flutter-product-sheets). The read-only snapshot
// bridge + container plus the four surface widgets (ProductListSheet /
// ProductDetailSheet / MiniCartPeek / NotifyRestockSheet, incl. the reconciled
// 收藏鈕 on the product-detail sheet) are all landed; the container binds the
// template product sheet-stack view-models and paints them.
export 'src/productsheets/product_row_overlay.dart';
export 'src/productsheets/product_status_badge.dart';
export 'src/productsheets/product_sheets_model.dart';
export 'src/productsheets/product_sheets_view.dart';
// The cohesive shared bottom-sheet presenter (scrim + slide + bottom-pinned card),
// Flutter parity of iOS `LivebuyReferenceUI/SheetKit/BottomSheetPresenter.swift`. Every
// grab-handle sheet (ProductDetail / AddToCart / NotifyRestock + the player-shell
// VideoInfoPanel) presents through it so the scrim BLOCKS the host content below +
// dismisses on a background tap, and the card slides up / down consistently.
export 'src/productsheets/bottom_sheet_presenter.dart';

// family-4 moments (rb-flutter-moments). The read-only snapshot bridge
// (`MomentsModel`, NO mutating forwarder) + demo seeds (`MomentsSeeds`) +
// host-wired container (`MomentsOverlayView`, whose moment-exit actions —
// skip / watchNext / pickHot / cancel / retry / dismiss — are host-wired
// callbacks, NOT template methods) plus the three full-screen surface widgets
// (StartScreenView / EndScreenView / ErrorScreenView, reached transitively via
// the container) are all landed; the container binds the template start / end /
// error moment view-models (startScreen.phase / endScreen.{next,hot,countdown}
// / errorState.current) and paints them.
export 'src/moments/moments_model.dart';
export 'src/moments/moments_view.dart';

// family-5 widget (rb-flutter-widget). The read-only snapshot bridge (`WidgetModel`,
// NO mutating forwarder) + reference-ui product-overlay value (`WidgetGoods`) + demo
// seeds (`WidgetSeeds`) + host-wired container (`WidgetOverlayView`, whose widget
// exits — tapVideo / loadMore / seeMore / close / expand — are host-wired callbacks,
// NOT template methods) + the shared 9:16 card primitive (`CarouselCardView`) are
// landed by this skeleton; the four embedded widget surface widgets (CarouselView /
// VideoShopGridView / FloatingWidgetView / MinimizedWidgetView) are landed by the
// parallel Surfaces agents — until then the container's surface imports are
// unresolved (expected skeleton state, parity with iOS / Android: the skeleton fixes
// call-sites, surfaces land the types). The container binds the WIDGET template's
// host-bindable content (`DefaultWidgetTemplate.content`, entry
// `LivebuyUI.widgetTemplate(controller)`) and dispatches by `content.current.mode`.
export 'src/widget/widget_model.dart';
export 'src/widget/widget_overlay_view.dart';
// flutter-refui-widget-host-visibility-pause — opt-in host -> SDK bridge letting the host declare
// its widget-hosting screen COVERED (e.g. a full-screen player overlay) so the covered LoopingVideoView
// previews pause (the "tab-cover" residual gap of flutter-refui-widget-preview-lifecycle-pause; Dart
// parity of Android LivebuyWidgetVisibility). Exported so hosts can call setWidgetsCovered(...).
export 'src/widget/live_buy_widget_visibility.dart';
// External-platform live redirect (external-live-watch): hosts composing the bare
// FloatingWidgetView surface use these to detect + route an external (e.g. Facebook)
// live's tap out to the platform instead of the in-app player.
export 'src/widget/external_live.dart';

// family-6 gap-surfaces (rb-flutter-gap-surfaces) — the FINAL Flutter family. The
// read-only snapshot bridge (`GapSurfacesModel`, NO mutating forwarder) + demo seeds
// (`GapSurfacesSeeds`) + host-wired container (`GapSurfacesOverlayView`, whose
// login / dismiss / submit-name exits are host-wired callbacks and whose lone core
// exit is `template.requestGuestNameEdit()`) are landed by this skeleton; the two
// NEW modal surface widgets (AuthGateModalView / GuestNameEditModalView) are landed
// by the parallel Surfaces agents — until then the container's surface imports are
// unresolved (expected skeleton state, parity with iOS / Android: the skeleton fixes
// call-sites, surfaces land the types). PURELY ADDITIVE (2 ADDED, 0 MODIFIED): the
// Flutter family-1 公告 notice-tab + family-3 收藏鈕 already landed post-reconcile, so
// this family touches NEITHER `video_info_panel.dart` NOR `product_detail_sheet.dart`.
// The container binds the template auth-gate / identity view-models
// (`authGate.current` / `identityLabel.current`) and shows the single active modal
// (auth-gate > guest-name-edit).
export 'src/gapsurfaces/gap_surfaces_model.dart';
export 'src/gapsurfaces/gap_surfaces_view.dart';

// introduce-dropin-widget-container-flutter — the turnkey drop-in widget-list
// CONTAINER (integration / assembly layer, parallel to iOS/Android/RN
// `LivebuyWidget`). Takes the GOLDEN NAME (the bare bridge was renamed
// `LivebuyWidgetCore` by `rename-bare-widget-to-core-flutter`). It assembles the
// existing `WidgetOverlayView` surface + a `DefaultWidgetTemplate` and drives the
// host-wired data path itself via core `LivebuySDK.fetchWidget`
// (`fetch-widget-content-flutter-core`) — carousel / grid, with sensible defaults
// for every interaction (`LivebuyWidgetConfig`, all callbacks optional). PURE
// assembly — zero new view-models, zero family-pixel changes, one-way dep intact.
export 'src/container/live_buy_widget.dart';

// introduce-dropin-live-entry-container-flutter — the turnkey drop-in「現正直播」floating
// ENTRY container (integration / assembly layer, parallel to LivebuyWidget / LivebuyPlayer;
// Flutter parity of iOS / Android / RN). `LivebuyLiveEntry` auto-detects the shop's current
// `liveStatus == 1` live (polling core `LivebuySDK.fetchLatestLive`) and floats a single
// entry card, reusing the existing `FloatingWidgetView` surface + the pure
// `clampFloatingOffset` drag clamp. The state machine is the immutable `LiveEntryState` +
// pure transitions. PURE assembly — zero new pixel surfaces, zero view-models, one-way dep
// intact. live-end immediate-hide rides a host-provided `Stream<void> liveEndedSignal`
// (Flutter's core event listener is a single host-owned interceptor).
export 'src/container/live_buy_live_entry.dart';

// rb-flutter-floating-entry-position-timing — the floating entry's INITIAL CORNER and
// APPEARANCE TIMING (`extensions.floating_setting`'s `position` / `timing` / `delay`, injected
// by the host). Pure, zero-pixel: the two wire-value enums (`LBFloatingEntryPosition` /
// `LBFloatingEntryTiming`), their STRICT-equality normalizers, the single corner+drag geometry
// function `lbLiveEntryEdgeInset` (where the sign flip between corners lives), the appearance
// gate helpers, and the design's `lbp-float-in` entrance constants. Also feeds
// `clampFloatingOffset`'s optional `position` parameter.
export 'src/container/live_entry_position_timing.dart';

// introduce-dropin-player-container-flutter — the turnkey drop-in PLAYER container
// (integration / assembly layer, parallel to iOS `LivebuyPlayer`). Takes the GOLDEN
// NAME (the bare native view was renamed `LivebuyPlayerCore` by
// `rename-bare-player-livebuyplayercore-flutter`). It composes the existing player
// surfaces (shell / feed-win / product-sheets / moments / gap-surfaces) + an on-demand
// chat composer over `LivebuyPlayerCore` in ONE `Stack`, with sensible defaults for
// every interaction (`LivebuyPlayerConfig`, all callbacks optional). PURE assembly —
// zero new view-models, zero family-pixel changes, one-way dep intact.
export 'src/container/live_buy_player.dart';
// Collapsible player presenter (rb-flutter-collapsible-player): full-screen player +
// minimize → bottom-right floating preview (keep-alive, draggable). Parity with iOS
// `livebuyPlayer(video:)`.
export 'src/container/collapsible_live_buy_player.dart';
export 'src/container/chat_composer_bar.dart';
// The design seam (granularity A): `ReferenceUIDesign` + per-surface context value types +
// the default `MinimalDesign` conformer. The three turnkey containers delegate their surface
// assembly to the resolved design; a host injects a custom design via the containers' configs.
// Parity with iOS `LivebuyReferenceUI/Container/ReferenceUIDesign.swift` + `MinimalDesign.swift`.
export 'src/container/reference_ui_design.dart';

// rb-flutter-e2e-test-keys — centralized E2E test-key registry. Every E2E `Key` on a
// production reference-ui widget comes from here (CI greps for hardcoded E2E key
// literals; only `lb_test_keys.dart` may contain them). Values are 1:1 identical to the
// Android `LBTestTags` / iOS `LBAccessibilityID` / RN `LBTestIDs` strings so the same
// E2E scenario id names carry across all four platforms. Exported so the QA harness
// references the same keys instead of magic strings.
export 'src/testing/lb_test_keys.dart';
