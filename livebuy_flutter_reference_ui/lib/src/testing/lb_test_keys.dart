import 'package:flutter/widgets.dart';

/// Centralized registry of E2E test [Key]s for the Flutter reference-ui.
///
/// Every E2E `Key` used by a production reference-ui widget MUST come from here
/// (CI greps `flutter-reference-ui/lib` for `ValueKey('lb_` / `Key('lb_` literals —
/// only this file may contain them). Keys are INERT: a [ValueKey] / [KeyedSubtree]
/// creates no `RenderObject`, so the painted pixels (golden PNG baselines) stay
/// byte-identical and all gesture / callback behavior is unchanged.
///
/// NOTE the distinction from FUNCTIONAL keys: animation / identity keys such as
/// `ValueKey('lb-sheet-scrim-on')` (hyphenated `lb-`) or `ValueKey('info-open')` are
/// NOT E2E keys and are out of scope — the CI lint only flags the underscore `lb_`
/// E2E form.
///
/// The string VALUES are a stable cross-platform contract: 1:1 identical to the
/// Android `LBTestTags`, iOS `LBAccessibilityID`, and RN `LBTestIDs` values, so the
/// same E2E scenario id names carry across iOS / Android / RN / Flutter. The Dart
/// member name is camelCase; the underlying [ValueKey] string is the shared snake_case
/// `lb_*` token. Renaming a value is a breaking change — update the harness scenarios
/// in the same change.
abstract final class LbTestKeys {
  // ── Family 1 — player shell + chrome ──────────────────────────────────────
  static const Key playerShell = ValueKey('lb_player_shell');
  static const Key playerVideoSurface = ValueKey('lb_player_video_surface');
  static const Key playerHeader = ValueKey('lb_player_header');
  static const Key playerHeaderHostPill = ValueKey('lb_player_header_host_pill');
  static const Key subscribeBadge = ValueKey('lb_subscribe_badge');
  static const Key playerMinimize = ValueKey('lb_player_minimize');
  static const Key playerBag = ValueKey('lb_player_bag');

  static const Key operationRail = ValueKey('lb_operation_rail');
  static const Key railLike = ValueKey('lb_rail_like');
  static const Key railComment = ValueKey('lb_rail_comment');
  static const Key railShare = ValueKey('lb_rail_share');
  static const Key railSubtitle = ValueKey('lb_rail_subtitle');
  static const Key railService = ValueKey('lb_rail_service');
  static const Key railGoods = ValueKey('lb_rail_goods');

  /// 「更多」收合 pill (rb-flutter-live-replay-more-menu-and-video-info-live-copy):
  /// shown by [OperationRailView] INSTEAD of the direct `share` / `serviceLink` pills
  /// when `isFinishedLiveReplay == true` (a closed-chat finished live replay — the
  /// Flutter surface that actually renders that state, NOT `LiveBottomBarView`; see
  /// this change's `design.md`).
  static const Key railMore = ValueKey('lb_rail_more');

  /// The「更多」bottom sheet root (`player_shell_view.dart`'s `_RailMoreMenuSheet`).
  static const Key railMoreSheet = ValueKey('lb_rail_more_sheet');

  /// 「分享」slot inside the「更多」sheet.
  static const Key railMoreShare = ValueKey('lb_rail_more_share');

  /// 「客服」slot inside the「更多」sheet.
  static const Key railMoreContact = ValueKey('lb_rail_more_contact');

  static const Key liveBagButton = ValueKey('lb_live_bag_button');
  static const Key liveCommentPill = ValueKey('lb_live_comment_pill');
  static const Key livePersonEdit = ValueKey('lb_live_person_edit');
  static const Key liveShare = ValueKey('lb_live_share');
  static const Key liveHeart = ValueKey('lb_live_heart');
  static const Key announceBanner = ValueKey('lb_announce_banner');
  static const Key pinnedCard = ValueKey('lb_pinned_card');
  static const Key pinnedCardClose = ValueKey('lb_pinned_card_close');
  static const Key pinnedCarousel = ValueKey('lb_pinned_carousel');
  static const Key nowIntroCarousel = ValueKey('lb_now_intro_carousel');
  static const Key nowIntroducingCard = ValueKey('lb_now_introducing_card');

  static const Key infoPanel = ValueKey('lb_info_panel');
  static const Key infoTabDetail = ValueKey('lb_info_tab_detail');
  static const Key infoTabNotice = ValueKey('lb_info_tab_notice');
  static const Key infoFooterContact = ValueKey('lb_info_footer_contact');
  static const Key contactModal = ValueKey('lb_contact_modal');
  static const Key contactCancel = ValueKey('lb_contact_cancel');
  static const Key contactConfirm = ValueKey('lb_contact_confirm');
  static const Key contactScrim = ValueKey('lb_contact_scrim');
  static const Key momentCountdownRoot = ValueKey('lb_moment_countdown_root');

  /// VOD/回放播放進度條 (rb-flutter-vod-playback-progress-bar). The idle thin-line + expanded
  /// transport-bar share ONE root key (idle vs expanded is a presentation state, not a
  /// different component).
  static const Key playbackProgressBar = ValueKey('lb_playback_progress_bar');

  /// Transport-bar play/pause icon button (expanded state only).
  static const Key playbackProgressPlayPause =
      ValueKey('lb_playback_progress_play_pause');

  /// Transport-bar draggable seek track (expanded state only) — also the idle state's
  /// invisible drag hit-area, since both are the SAME structurally-stable gesture carrier.
  static const Key playbackProgressTrack = ValueKey('lb_playback_progress_track');

  /// Drag-time `HH:MM:SS / HH:MM:SS` timestamp readout (shown only while scrubbing).
  static const Key playbackProgressTimestamp =
      ValueKey('lb_playback_progress_timestamp');

  /// 「現正直播」右緣提示鈕 (rb-flutter-live-now-pill). String value 1:1 identical to iOS
  /// `LBAccessibilityID.liveNowPill` / Android `LBTestTags.LIVE_NOW_PILL` / RN
  /// `LBTestIDs.liveNowPill`.
  static const Key liveNowPill = ValueKey('lb_live_now_pill');

  /// 暫停覆蓋層靜音切換鈕 (rb-flutter port of `player-gesture-feedback-overlays-flutter`). String
  /// value 1:1 identical to iOS `LBAccessibilityID.pausedOverlayMuteButton` / Android
  /// `LBTestTags.PAUSED_OVERLAY_MUTE_BUTTON`.
  ///
  /// RETIRED — `rb-flutter-gesture-clean-mode-v2` 起不再被 `PlayerShellView` 組合
  /// （`PlaybackPausedOverlayView` 仍是可獨立建構/測試的 widget，只是不再出現在
  /// `PlayerShellView` 的渲染子樹中）。id 本身保留、不刪除。
  static const Key pausedOverlayMuteButton =
      ValueKey('lb_paused_overlay_mute_button');

  /// 暫停覆蓋層播放恢復鈕. String value 1:1 identical to iOS
  /// `LBAccessibilityID.pausedOverlayResumeButton` / Android
  /// `LBTestTags.PAUSED_OVERLAY_RESUME_BUTTON`.
  ///
  /// RETIRED — `rb-flutter-gesture-clean-mode-v2` 起不再被 `PlayerShellView` 組合，理由同上。
  static const Key pausedOverlayResumeButton =
      ValueKey('lb_paused_overlay_resume_button');

  /// 播放器頂列乾淨模式限定靜音切換鈕 (rb-flutter-gesture-clean-mode-v2). String value 1:1
  /// identical to iOS `LBAccessibilityID.playerHeaderMuteButton`.
  static const Key playerHeaderMuteButton =
      ValueKey('lb_player_header_mute_button');

  /// 「退出乾淨模式」小圓鈕 (rb-flutter-gesture-clean-mode-v2). String value 1:1 identical to
  /// iOS `LBAccessibilityID.cleanModeExitButton`.
  static const Key cleanModeExitButton = ValueKey('lb_clean_mode_exit_button');

  // ── Family 2 — feed + win ─────────────────────────────────────────────────
  static const Key chatFeed = ValueKey('lb_chat_feed');
  static const Key eventJoinCta = ValueKey('lb_event_join_cta');
  static const Key eventJoinJoined = ValueKey('lb_event_join_joined');
  static const Key pinnedBanner = ValueKey('lb_pinned_banner');
  static const Key chatScrollToBottom = ValueKey('lb_chat_scroll_to_bottom');
  static const Key winEntry = ValueKey('lb_win_entry');

  /// `WinEntryView(variant: activity)` root (rb-flutter-live-activity-sheet, R26) —
  /// distinct from [winEntry] so both entries can be found independently when they
  /// are mounted simultaneously (design.md D2 — the two entries are NOT mutually
  /// exclusive).
  static const Key activityEntry = ValueKey('lb_activity_entry');
  static const Key winClaimSheet = ValueKey('lb_win_claim_sheet');
  static const Key winClaimPrimary = ValueKey('lb_win_claim_primary');
  static const Key winClaimResultBanner = ValueKey('lb_win_claim_result_banner');
  static const Key winClaimScrim = ValueKey('lb_win_claim_scrim');
  // rb-flutter-win-claim-email-flow — 四階段領獎 modal 的新元件（EMAIL-LESS 退役）。既有 key
  // 語意不變（`winClaimSheet` 仍是底卡、`winClaimResultBanner` 仍是結果內容列）。字串值
  // 1:1 對齊 iOS `LBAccessibilityID` / RN `LBTestIDs`（`winClaimAlertScrim` 為 Flutter + RN
  // 才有 —— Flutter 的 alert scrim 是可點的 `GestureDetector`，widget test 需要 key 才點得到）。
  //
  // rb-flutter-win-claim-pagination（R27）—— `winClaimSecondary`（claim 卡「關閉視窗」/ fail
  // 卡「關閉視窗」共用）與 `winClaimClose`（claim 卡右上角 ✕）兩個 key 隨對應按鈕整顆退役，
  // 已移除（生產程式碼再無任何 widget 會掛這兩個 key）。
  /// `claim` 階段的 email 輸入欄（runtime `TextField` / golden 靜態佔位共用同一 key）。
  static const Key winClaimEmailField = ValueKey('lb_win_claim_email_field');
  /// `confirmSubmit` / `confirmClose` 的 alert 卡。
  static const Key winClaimAlert = ValueKey('lb_win_claim_alert');
  /// alert 自身的 scrim（點擊只收起 alert，MUST NOT 關閉整個 modal）。
  static const Key winClaimAlertScrim = ValueKey('lb_win_claim_alert_scrim');
  /// alert 的「取消」。
  static const Key winClaimAlertCancel = ValueKey('lb_win_claim_alert_cancel');
  /// alert 的「確定」。
  static const Key winClaimAlertConfirm = ValueKey('lb_win_claim_alert_confirm');
  /// 送出中疊層（scrim + spinner +「送出中…」）。
  static const Key winClaimSubmitting = ValueKey('lb_win_claim_submitting');
  /// `done`（discount）的折扣碼「複製」鈕。
  static const Key winClaimCopyCode = ValueKey('lb_win_claim_copy_code');
  /// `fail` 卡的通用錯誤提示列（**不含**任何錯誤代碼，見 R13 刻意分歧 2/2）。
  static const Key winClaimFailNotice = ValueKey('lb_win_claim_fail_notice');
  /// 卡底 footer「使用條款 | 隱私政策」外層共用 key。
  static const Key winClaimFooter = ValueKey('lb_win_claim_footer');
  // rb-flutter-win-claim-footer-links — footer 兩段文字各自可點擊，字串值與 iOS
  // `LBAccessibilityID` / Android `LBTestTags` / RN `LBTestIDs` 逐字對齊。
  /// footer「使用條款」文字段（可點擊）。
  static const Key winClaimFooterTerms = ValueKey('lb_win_claim_footer_terms');
  /// footer「隱私政策」文字段（可點擊）。
  static const Key winClaimFooterPrivacy = ValueKey('lb_win_claim_footer_privacy');

  /// 分頁圓點列外層容器（rb-flutter-win-claim-pagination，R27）——`pageCount > 1` 時才畫，
  /// 僅出現在 `claim` 卡。個別圓點的可點擊 key 見 [winClaimPageDot]。
  static const Key winClaimPageDots = ValueKey('lb_win_claim_page_dots');

  // rb-flutter-live-activity-sheet (R26) — `ActivitySheetView`，鏡射
  // `WinClaimSheetView` 的置中 modal 卡 key 慣例（scrim / 卡本體 / CTA / footer 兩段）。
  /// `ActivitySheetView` 底卡本體。
  static const Key activitySheet = ValueKey('lb_activity_sheet');
  /// 外層 scrim（點擊關閉彈窗，純 dismiss）。
  static const Key activitySheetScrim = ValueKey('lb_activity_sheet_scrim');
  /// 主 CTA（三態文案：「立即參加」/「已參加」disabled /「知道了」）。
  static const Key activitySheetCta = ValueKey('lb_activity_sheet_cta');
  /// 卡底 footer「使用條款 | 隱私政策」外層共用 key。
  static const Key activitySheetFooter = ValueKey('lb_activity_sheet_footer');
  /// footer「使用條款」文字段（可點擊）。
  static const Key activitySheetFooterTerms =
      ValueKey('lb_activity_sheet_footer_terms');
  /// footer「隱私政策」文字段（可點擊）。
  static const Key activitySheetFooterPrivacy =
      ValueKey('lb_activity_sheet_footer_privacy');

  // rb-flutter-activity-sheet-pagination — `ActivitySheetView` 分頁圓點，鏡射
  // `WinClaimSheetView` 的 `winClaimPageDots` / `winClaimPageDot` key 慣例。
  /// 分頁圓點列外層容器（`pageCount > 1` 時才畫）。個別圓點的可點擊 key 見
  /// [activitySheetPageDot]。
  static const Key activitySheetPageDots =
      ValueKey('lb_activity_sheet_page_dots');

  // ── Family 3 — product + sheets ───────────────────────────────────────────
  static const Key productList = ValueKey('lb_product_list');
  static const Key sheetSearchField = ValueKey('lb_sheet_search_field');
  static const Key sheetSearchClear = ValueKey('lb_sheet_search_clear');
  static const Key sheetSearchCancel = ValueKey('lb_sheet_search_cancel');
  static const Key productSearchButton = ValueKey('lb_product_search_button');
  static const Key cartCtaFooter = ValueKey('lb_cart_cta_footer');
  static const Key productDetail = ValueKey('lb_product_detail');
  static const Key qtyPlus = ValueKey('lb_qty_plus');
  static const Key qtyMinus = ValueKey('lb_qty_minus');
  static const Key favButton = ValueKey('lb_fav_button');
  static const Key shareButton = ValueKey('lb_share_button');
  static const Key variantPrompt = ValueKey('lb_variant_prompt');
  static const Key variantPromptScrim = ValueKey('lb_variant_prompt_scrim');
  static const Key variantPromptAck = ValueKey('lb_variant_prompt_ack');
  static const Key addToCartSheet = ValueKey('lb_add_to_cart_sheet');
  static const Key addToCartCta = ValueKey('lb_add_to_cart_cta');
  static const Key addToCartRetry = ValueKey('lb_add_to_cart_retry');
  static const Key zoomBadge = ValueKey('lb_zoom_badge');
  static const Key zoomOverlay = ValueKey('lb_zoom_overlay');
  static const Key imageZoomImage = ValueKey('lb_image_zoom_image');
  static const Key zoomClose = ValueKey('lb_zoom_close');
  static const Key notifyRestockSheet = ValueKey('lb_notify_restock_sheet');
  static const Key restockNoticeCta = ValueKey('lb_restock_notice_cta');
  static const Key minicartPeek = ValueKey('lb_minicart_peek');
  static const Key minicartPeekClose = ValueKey('lb_minicart_peek_close');
  static const Key cartToast = ValueKey('lb_cart_toast');
  static const Key sheetHeaderClose = ValueKey('lb_sheet_header_close');

  /// The sheet-header close button's「返回」variant (rb-flutter-product-detail-
  /// recommendations §5.4): shown INSTEAD of `sheetHeaderClose`'s ✕ glyph while a
  /// nested-recommendation `detailBreadcrumb` is non-empty.
  static const Key sheetHeaderBack = ValueKey('lb_sheet_header_back');

  /// 商品明細「商品介紹」文字區塊 (rb-flutter-product-detail-recommendations §2).
  static const Key productIntroSection = ValueKey('lb_product_intro_section');

  /// 商品明細「更多商品」2×2 推薦格 (rb-flutter-product-detail-recommendations §3).
  static const Key recommendationsSection =
      ValueKey('lb_recommendations_section');

  // ── Family 4 — moments ────────────────────────────────────────────────────
  static const Key momentRoot = ValueKey('lb_moment_root');
  static const Key momentError = ValueKey('lb_moment_error');
  static const Key momentErrorRetry = ValueKey('lb_moment_error_retry');
  static const Key momentErrorBack = ValueKey('lb_moment_error_back');
  static const Key momentEnd = ValueKey('lb_moment_end');
  static const Key momentEndWatch = ValueKey('lb_moment_end_watch');
  static const Key momentEndCancel = ValueKey('lb_moment_end_cancel');
  static const Key momentEndReshuffle = ValueKey('lb_moment_end_reshuffle');
  static const Key momentEndHotRow = ValueKey('lb_moment_end_hot_row');
  static const Key momentStart = ValueKey('lb_moment_start');
  static const Key momentStartSkip = ValueKey('lb_moment_start_skip');
  static const Key momentLoading = ValueKey('lb_moment_loading');

  // ── Family 5 — widget ─────────────────────────────────────────────────────
  static const Key widgetCarousel = ValueKey('lb_widget_carousel');
  static const Key widgetGrid = ValueKey('lb_widget_grid');
  static const Key widgetSeeMore = ValueKey('lb_widget_see_more');
  static const Key gridLoadMoreFooter = ValueKey('lb_grid_load_more_footer');
  static const Key gridEndLabel = ValueKey('lb_grid_end_label');
  static const Key cardKindBadge = ValueKey('lb_card_kind_badge');
  static const Key cardLiveBadge = ValueKey('lb_card_live_badge');
  static const Key cardUpcomingOverlay = ValueKey('lb_card_upcoming_overlay');

  /// 置頂 badge (`item.pin == 1`, rb-flutter-carousel-card-pin-viewers-duration-removal,
  /// design R33): top-right pushpin/thumbtack icon, independent of the LIVE/UPCOMING/VOD
  /// kind badge — all three kind states may carry it simultaneously.
  static const Key cardPinBadge = ValueKey('lb_card_pin_badge');

  /// LIVE-only viewer-count pill (`item.watchNum`, gated by `item.showPvNum == 1`,
  /// rb-flutter-carousel-card-pin-viewers-duration-removal, design R33): sits to the
  /// right of the LIVE tag inside [cardKindBadge].
  static const Key cardViewerBadge = ValueKey('lb_card_viewer_badge');

  /// `product_card == 'below'` — the surface-styled product row drawn UNDER THE TITLE,
  /// at the very bottom of the card (rb-flutter-widget-product-card-modes; placement
  /// reversed by rb-flutter-widget-product-card-below-slot-reposition / design R17).
  static const Key cardBelowProductRow = ValueKey('lb_card_below_product_row');

  /// `product_card == 'below'` with NO bound goods — the equal-height transparent
  /// spacer that keeps same-row / same-cell cards the same height.
  static const Key cardBelowProductSpacer =
      ValueKey('lb_card_below_product_spacer');
  static const Key floatingWidget = ValueKey('lb_floating_widget');
  static const Key floatingClose = ValueKey('lb_floating_close');
  static const Key minimizedWidget = ValueKey('lb_minimized_widget');
  static const Key minimizedClose = ValueKey('lb_minimized_close');
  static const Key minimizedExpand = ValueKey('lb_minimized_expand');
  static const Key loopingPreview = ValueKey('lb_looping_preview');

  // ── Family 6 — gap-surfaces ───────────────────────────────────────────────
  static const Key authGateModal = ValueKey('lb_auth_gate_modal');
  static const Key authGateLogin = ValueKey('lb_auth_gate_login');
  static const Key authGateLater = ValueKey('lb_auth_gate_later');
  static const Key authGateScrim = ValueKey('lb_auth_gate_scrim');
  static const Key guestNameModal = ValueKey('lb_guest_name_modal');
  static const Key guestNameField = ValueKey('lb_guest_name_field');
  static const Key guestNameSubmit = ValueKey('lb_guest_name_submit');
  static const Key guestNameError = ValueKey('lb_guest_name_error');
  static const Key guestNameScrim = ValueKey('lb_guest_name_scrim');

  // ── Family 7 — container + sheetkit (shared chrome) ───────────────────────
  static const Key bottomSheetScrim = ValueKey('lb_bottom_sheet_scrim');
  /// `LBSheetScaffold`'s grab-handle drag-resize/drag-to-dismiss target
  /// (rb-flutter-sheetkit-resize-dismiss-unify — supersedes the opt-in
  /// `draggable`/rb-flutter-product-sheet-resize-fav-inline era). Present on EVERY
  /// `LBSheetScaffold` presentation now (`ProductDetailSheet` both presentations,
  /// `NotifyRestockSheet`, `ProductListSheet`, `VideoInfoPanelView`) — there is no longer a
  /// non-draggable `LBSheetScaffold`.
  static const Key sheetDragHandle = ValueKey('lb_sheet_drag_handle');
  static const Key chatComposer = ValueKey('lb_chat_composer');
  static const Key chatSend = ValueKey('lb_chat_send');
  static const Key chatComposerDismiss = ValueKey('lb_chat_composer_dismiss');

  // ── Per-item (index-addressable) helpers ──────────────────────────────────
  // Each helper's value is 1:1 identical to the matching Android / iOS / RN helper.

  /// Per-item chat line key, e.g. `chatLine(0) == const ValueKey('lb_chat_line_0')`.
  static Key chatLine(int index) => ValueKey('lb_chat_line_$index');

  /// Per-item activity line key.
  static Key activityLine(int index) => ValueKey('lb_activity_line_$index');

  /// Per-item carousel card key.
  static Key carouselCard(int index) => ValueKey('lb_carousel_card_$index');

  /// Per-item grid card key.
  static Key gridCard(int index) => ValueKey('lb_grid_card_$index');

  /// Per-item product-row key.
  static Key productRow(int index) => ValueKey('lb_product_row_$index');

  /// Per-item product-row thumbnail (seek-to-intro) key.
  static Key productRowThumb(int index) => ValueKey('lb_product_row_thumb_$index');

  /// Per-item ProductDetailSheet main-photo gallery thumbnail-selector key
  /// (rb-flutter-product-detail-image-gallery).
  static Key productGalleryThumb(int index) => ValueKey('lb_product_gallery_thumb_$index');

  /// Root of ProductDetailSheet's `.detail` main-photo gallery (INERT — a `KeyedSubtree`,
  /// paints nothing) — lets tests target the swipeable main-image area directly (e.g. for a
  /// horizontal drag gesture) without depending on the private gallery widget's type
  /// (rb-flutter-product-detail-image-gallery).
  static const Key productGallery = ValueKey('lb_product_gallery');

  /// The gallery's MAIN (currently selected) photo specifically (INERT — a `KeyedSubtree`,
  /// paints nothing) — disambiguates it from the thumbnail row's own `Image` widgets, which
  /// would otherwise be indistinguishable by `find.byType(Image)` alone
  /// (rb-flutter-product-detail-image-gallery).
  static const Key productGalleryMainImage = ValueKey('lb_product_gallery_main_image');

  /// Per-item product-row name/detail-open key.
  static Key productRowDetail(int index) => ValueKey('lb_product_row_detail_$index');

  /// Per-item product-row share key.
  static Key productRowShare(int index) => ValueKey('lb_product_row_share_$index');

  /// Per-item product-row add-to-cart / restock key.
  static Key productRowCart(int index) => ValueKey('lb_product_row_cart_$index');

  /// Per-item「更多商品」推薦卡 key (`.grid` layout, rb-flutter-product-detail-recommendations).
  static Key recommendationCard(int index) => ValueKey('lb_recommendation_card_$index');

  /// Per-item recommendation card play (換片) button key.
  static Key recommendationPlay(int index) => ValueKey('lb_recommendation_play_$index');

  /// Per-item recommendation card cart (加購) button key.
  static Key recommendationCart(int index) => ValueKey('lb_recommendation_cart_$index');

  /// Per-(group, option) variant chip key,
  /// e.g. `variantChip(1, 2) == const ValueKey('lb_variant_chip_1_2')`.
  static Key variantChip(int group, int option) =>
      ValueKey('lb_variant_chip_${group}_$option');

  /// Per-item end-screen hot card key.
  static Key momentHotCard(int index) => ValueKey('lb_moment_hot_card_$index');

  /// Per-item live pinned-product carousel page dot key.
  static Key livePinnedDot(int index) => ValueKey('lb_live_pinned_dot_$index');

  /// Per-item now-introducing carousel page dot key.
  static Key nowIntroducingDot(int index) => ValueKey('lb_now_introducing_dot_$index');

  /// Per-item win-claim pagination dot key (rb-flutter-win-claim-pagination, R27),
  /// e.g. `winClaimPageDot(0) == const ValueKey('lb_win_claim_page_dot_0')`.
  static Key winClaimPageDot(int index) => ValueKey('lb_win_claim_page_dot_$index');

  /// Per-item activity-sheet pagination dot key (rb-flutter-activity-sheet-pagination),
  /// e.g. `activitySheetPageDot(0) == const ValueKey('lb_activity_sheet_page_dot_0')`.
  static Key activitySheetPageDot(int index) =>
      ValueKey('lb_activity_sheet_page_dot_$index');
}
