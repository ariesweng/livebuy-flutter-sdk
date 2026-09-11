import 'dart:async';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart' show Colors;
import 'package:flutter/widgets.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart' show LBProduct;
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show DefaultPlayerTemplate, LBInfoPanelTab, LBMiniCartPeek, LBPStartPhase, LBSideRailKind;

import '../productsheets/bottom_sheet_presenter.dart';
import '../productsheets/sheet_scaffold.dart';
import '../sheet_slide_transition.dart';
import '../testing/lb_test_keys.dart';
import 'now_introducing_carousel.dart';
import '../reference_ui_theme.dart';
import 'caption_overlay_view.dart';
import 'contact_glyph.dart';
import 'contact_merchant_modal.dart';
import 'detail_glyph.dart';
import 'heart_burst.dart';
import 'live_bottom_bar_view.dart';
import 'live_now_pill_view.dart';
import 'live_overlay_chrome_view.dart';
import 'operation_rail_view.dart';
import 'playback_progress_bar_view.dart';
import 'player_header_bar_view.dart';
import 'player_shell_model.dart';
import 'product_image_prefetch.dart';
import 'share_fill_glyph.dart';
import 'subtitle_vtt_pipeline.dart';
import 'upcoming_countdown_view.dart';
import 'video_info_panel_view.dart';
import 'vtt_subtitle_parser.dart';

// rb-flutter-marquee-title-scroll — the pure entry point for the
// `extensions.video_title_scroll` merchant gate lives next to the surface that consumes
// it (`player_header_bar_view.dart`, the same placement iOS / Android chose). It is
// re-exported HERE, by name only, because this container file is already in the package
// barrel while `player_header_bar_view.dart` is NOT — a host composing its own
// `ReferenceUIDesign` can then resolve the raw wire value EXACTLY the way reference-ui
// does. Deliberately a `show` re-export (the same idiom `product_sheets_view.dart` uses
// for the sibling `extensions` helper `normalizeShowStock`) rather than adding the whole
// header library to the barrel, which would publish an unrelated set of widget types.
export 'player_header_bar_view.dart' show normalizeTitleScroll;

// PlayerShellView — family-1 player-shell container (Flutter SKELETON).
//
// Spec: `reference-ui-rendering/spec.md` (family-1 player-shell, 4 surfaces).
// Flutter sibling of iOS `PlayerShellView.swift` (rb-ios-player-shell D-1 / D-2)
// and Android `PlayerShellView.kt` (rb-android-player-shell).
//
// The top-level family-1 container. It lays out the FOUR family-1 surface widgets
// over a video area:
//
//   1. PlayerHeaderBarView   — pinned TOP        (`LBPTopBar` / `LBPHostBadge`)
//   2. OperationRailView     — pinned TRAILING   (`LBPSideRail`)
//   3. VideoInfoPanelView    — bottom sheet      (`LBPBottomSheet` / `VideoInfoSheet`)
//   4. LiveOverlayChromeView — full-bleed overlay (`live-chrome.jsx`)
//
// This SKELETON owns the layout, a read-only [PlayerShellModel], the resolved
// [ReferenceUITheme], and composes the four surface widgets BY TYPE NAME (the four
// parallel Surfaces agents land those types after this skeleton — forward refs are
// fine within one Dart package). Until they exist this file will not compile on its
// own; that is expected. The container FIXES the call-site shapes so the agents
// converge on the SUB-VIEW INPUT PATTERN documented below.
//
// ─────────────────────────────────────────────────────────────────────────────
// SUB-VIEW INPUT PATTERN — the contract the 4 Surfaces agents MUST follow
// ─────────────────────────────────────────────────────────────────────────────
//
// Every family-1 surface widget is a `class …View extends StatelessWidget` whose
// constructor takes, IN THIS ORDER (named params):
//
//   1. `theme:` (ReferenceUITheme, required)  — FIRST, always.
//   2. its bound SNAPSHOT VALUE(S)            — read-only state, passed BY VALUE
//                                                from PlayerShellModel (never the
//                                                model, never the template).
//   3. optional action callbacks             — trailing, EACH defaulting to a
//                                                no-op (`VoidCallback? onX`). The
//                                                shell does NOT own actions; the
//                                                host wires taps to core `simulate*`.
//
// A surface widget reads ONLY its passed-in values — it MUST NOT reach back into
// PlayerShellModel or DefaultPlayerTemplate (one-way data flow, D-1/D-4), MUST NOT
// hold a second copy of state, MUST render correctly with all callbacks null /
// omitted (so golden / widget tests construct it action-free), MUST NOT use any
// scrollable container (`ListView` / `GridView` / `SingleChildScrollView`) or
// network image (`Image.network` / `NetworkImage`).
//
// The four Surfaces agents implement EXACTLY these constructors (see the call
// sites in `build` below):
//
//   PlayerHeaderBarView({
//       required ReferenceUITheme theme,
//       required String title, required String hostName, required String shopLogo,
//       required int viewerCount, required bool isSubscribed,
//       VoidCallback? onMinimize, VoidCallback? onToggleSubscribe })
//   (top-right = a single minimize button → onMinimize; mute / share / info / close
//    are NOT header controls — mute is the tap-to-mute gesture, share / info the rail.)
//
//   OperationRailView({
//       required ReferenceUITheme theme,
//       required List<LBSideRailItem> items, required int bagCount,
//       required int heartBurstTick, required bool muted,
//       ValueChanged<LBSideRailKind>? onTapItem })
//
//   VideoInfoPanelView({
//       required ReferenceUITheme theme,
//       required LBInfoTabFields fields, required bool isSubscribed,
//       required LBInfoPanelTab activeTab, required bool noticeCanOpen,
//       required String systemNotice, required String notice,
//       ValueChanged<LBInfoPanelTab>? onSelectTab })
//
//   LiveOverlayChromeView({
//       required ReferenceUITheme theme,
//       required String announceText, LBProduct? pinnedProduct,
//       String hostCaption = '', bool showGestureHints = true,
//       ValueChanged<LBProduct>? onTapPinnedProduct })
//
// NOTE: Flutter's `LBInfoTabFields` carries NO `isSubscribed` (single truth lives
// on the header) — VideoInfoPanelView takes `isSubscribed` as a SEPARATE arg (the
// shell passes `model.isSubscribed`). This differs from iOS, whose `LBInfoTabState`
// bundles `isSubscribed`. Same rendered result, different view-model shape.
// ─────────────────────────────────────────────────────────────────────────────

/// The template-nav FALLBACK swipe action for a committed swipe toward one direction
/// (swipe-nav-close-on-empty).
enum SwipeNavFallbackAction { navigate, close }

/// PURE: classify the template-nav fallback swipe (no host override) toward a direction by
/// its adjacency flag — `hasAdjacentVideo` true → [SwipeNavFallbackAction.navigate] (go to
/// that adjacent video), false → [SwipeNavFallbackAction.close] (close the player; the list is
/// at its head / tail). Unit-testable without a gesture (per unit-test discipline). The swipe
/// DIRECTION is resolved in the gesture and the host-override-vs-fallback split in
/// `_handleSwipeEnded`, so this keys only on the relevant direction's adjacency flag — the
/// navigate-vs-close half of iOS `resolveSwipeNav`. Parity Android / RN `resolveSwipeNavFallback`.
SwipeNavFallbackAction resolveSwipeNavFallback(bool hasAdjacentVideo) =>
    hasAdjacentVideo ? SwipeNavFallbackAction.navigate : SwipeNavFallbackAction.close;

/// The header top-right button's resolved presentation + action
/// (fix-flutter-endscreen-close-button-blocked).
typedef HeaderCloseButtonResolution = ({bool showCloseIcon, VoidCallback? onMinimize});

/// PURE: resolve the header's top-right button state given whether the family-4 end
/// screen is currently active (`PlayerShellModel.isEndScreenActive`). The user's
/// decision: while the end screen is showing, the button is ALWAYS "close the whole
/// player" — [onCloseRequest] — overriding the global [showCloseIcon] / [onMinimize]
/// resolution for that window only (there is no meaningful "minimize into the
/// floating widget" affordance once the broadcast has ended). Outside that window
/// this is a no-op passthrough of the given [showCloseIcon] / [onMinimize].
///
/// PURE / State-independent (per `docs/unit-test-discipline.md`'s "extract pure
/// functions" rule, mirrors the [resolveSwipeNavFallback] precedent above) so both
/// `_buildContent`'s main LIVE/VOD branch AND `_buildUpcoming`'s 直播預告 branch can
/// share ONE tested computation instead of two independent inline ternaries that
/// could silently drift apart — the same risk this file's own [titleScroll] /
/// [showCloseIcon] "MUST forward at both call sites" doc comments already call out.
HeaderCloseButtonResolution resolveHeaderCloseButton({
  required bool endScreenActive,
  required bool showCloseIcon,
  required VoidCallback? onMinimize,
  required VoidCallback? onCloseRequest,
}) {
  if (endScreenActive) {
    return (showCloseIcon: true, onMinimize: onCloseRequest);
  }
  return (showCloseIcon: showCloseIcon, onMinimize: onMinimize);
}

/// PURE: whether a committed vertical swipe on the player video area is allowed to trigger
/// the switch-video action (rb-flutter-live-swipe-gesture-gating, design `screens.jsx`
/// `liveInProgress = effectiveState === 'live_main' && !isUpcoming && !isReplay`, `screens.jsx:223`).
/// `= !isLive` — [isLive] is [PlayerShellModel.isLive] (`channel.liveStatus == 1`, covers both
/// streaming-live and prerecorded-live), which is mutually exclusive with `isUpcoming`
/// (`liveStatus == 0`) and `isFinishedLiveReplay` (`type == 3 || (type == 2 && liveStatus == 3)`).
/// So `isLive == true` already precisely means "live in progress, not upcoming, not a
/// finished-live replay" — no extra combination is needed. NOTE: design's own `isReplay`
/// (`state === 'replay_main'`, a discrete top-level screen the demo groups with `upcoming_main`
/// as "wears the LIVE chrome") maps to `isFinishedLiveReplay` here, NOT the differently-named
/// `PlayerShellModel.isReplay` (`DefaultPlaybackProgressState.isReplay` — a stream scrubbed
/// behind the live edge WHILE STILL `isLive == true`, VOD-2). Excluding that second flag is
/// deliberately NOT done here: it can only be true when `isLive` already is, so it changes
/// nothing, and there is no design signal calling for a separate carve-out. Parity to the
/// established precedent `allowsHoldToPause(isLive:)` (iOS `rb-ios-live-hold-pause-suppress`,
/// Android `allowsHoldToPause`) — gate on the strict `isLive`, MUST NOT use a broader flag
/// that also covers `isFinishedLiveReplay`. Unit-testable without a gesture.
///
/// [sheetsPresented] (rb-flutter-block-swipe-nav-when-sheet-open) is an ADDITIONAL,
/// independently-ANDed exclusion — `= !isLive && !sheetsPresented` — added on top of the
/// original `isLive`-only gate: a swipe over the video area MUST NOT switch/close the video
/// while the sibling `ProductSheetsOverlayView` is covering it with ANY product sheet/modal
/// (list drawer / detail-or-restock / zoom lightbox / cart-needs-login gate / variant-select
/// prompt — see `anyProductSheetPresented` in `product_sheets_view.dart`), mirroring this
/// gate's own established "swipe still fully consumed by the enclosing `GestureDetector`, just
/// never dispatched" shape (see `_handleSwipeEnded`'s doc comment). Purely additive: the two
/// conditions are ORed at the call site (`!isLive || sheetsPresented` blocks), neither
/// replaces the other. Default `false` keeps this function's SOLE existing call site
/// (`_handleSwipeEnded`, before this change) — and any other caller — byte-identical unless it
/// opts in. This is a DEFENSIVE gate, not a fix for a confirmed reproducible bug: none of the
/// five sheet/modal surfaces' own `GestureDetector`s register a vertical-drag recognizer (nor
/// does `BottomSheetPresenter`'s full-bleed scrim, which only wires `onTap`), so a vertical
/// swipe starting over one of them is not itself claimed and could otherwise still be won by
/// this file's `VerticalDragGestureRecognizer` underneath.
bool allowsSwipeNav(bool isLive, {bool sheetsPresented = false}) =>
    !isLive && !sheetsPresented;

/// Which half of the video area a video-area gesture landed in (rb-flutter-gesture-clean-mode-v2,
/// design `screens.jsx:256`'s `zone = x < rect.width/2 ? 'rw' : 'ff'`). Drives both the
/// double-tap-seek direction and (structurally, per [isSeekable]) whether a long-press may start
/// the 2x-speed hold — though the hold itself deliberately does NOT read the zone (see
/// [_PlayerShellViewState._scheduleNextSpeedModeTick]'s doc comment: R29 keeps the upstream demo's
/// own direction bug, "always fast-forward regardless of side", verbatim).
enum TapZone { rewind, fastForward }

/// PURE: whether a video-area press may enter the delayed double-tap-seek judgment (short tap)
/// and the long-press-driven 2x-speed hold (rb-flutter-gesture-clean-mode-v2, design `screens.jsx`
/// `seekable = isReplay || !isLive`, R29 — SUPERSEDES the retired `tapTogglesPlayPause` /
/// `allowsDoubleTapLike` decision points, which decided a DIFFERENT pair of gestures that no
/// longer exist). `= isFinishedLiveReplay || !(isLive || isUpcoming)` — kept as a 3-argument
/// mirror of the design formula (parity iOS `isSeekable(isLive:isUpcoming:isFinishedLiveReplay:)`),
/// even though [isUpcoming] is always `false` at `PlayerShellView`'s own gesture call site
/// (`_buildUpcoming` composes no gesture detector at all, same established precedent as
/// [allowsSwipeNav] / [showsPlaybackProgressBar] in this file) — 1:1 fidelity with the design
/// formula costs nothing.
///
/// NOT seekable (a real live broadcast in progress, or its upcoming preview) → a short tap
/// toggles `_cleanMode` IMMEDIATELY (no double-tap outcome to protect on this branch — LIVE has
/// no double-tap reaction at all under R29), and the long-press 2x-speed hold NEVER starts (see
/// [_PlayerShellViewState._handleLongPressStart] — this is a STRUCTURAL no-op: the app-level
/// speed-mode tick `Timer` is simply never scheduled, not "scheduled then gated"). SEEKABLE
/// (VOD / a finished-live replay) → the short tap defers by [kDoubleTapSeekWindowMs] (see
/// [isDoubleTapSeekHit]) and the long-press starts the 2x-speed hold. Unit-testable without a
/// widget.
bool isSeekable({
  required bool isLive,
  required bool isUpcoming,
  required bool isFinishedLiveReplay,
}) =>
    isFinishedLiveReplay || !(isLive || isUpcoming);

/// PURE: which [TapZone] a video-area press landed in, given its horizontal offset from the
/// video area's own left edge and the area's total width (rb-flutter-gesture-clean-mode-v2,
/// design `screens.jsx:256`). A [containerWidth] of `0` (defensive — should not occur once the
/// area has been laid out at least once) falls through to [TapZone.fastForward], the same side a
/// literal `startX < 0` comparison would land any non-negative [startX] on. Unit-testable without
/// a widget.
TapZone tapZone({required double startX, required double containerWidth}) =>
    startX < containerWidth / 2 ? TapZone.rewind : TapZone.fastForward;

/// Double-tap-seek time window in milliseconds AND the delay a SEEKABLE short tap defers its
/// `_cleanMode` toggle by (rb-flutter-gesture-clean-mode-v2, design `screens.jsx:306`'s
/// `onPointerUp` formula `(now - last.t) < 320`). The value is carried over UNCHANGED from the
/// retired `kLiveDoubleTapWindowMs` (same number, entirely new semantics — R29 retires
/// double-tap-LIKE for double-tap-SEEK) — this is a fresh named constant, not the old symbol
/// repurposed. Parity iOS `doubleTapSeekWindow = 0.32`s.
const int kDoubleTapSeekWindowMs = 320;

/// PURE: whether a SEEKABLE video-area tap completes a double-tap-seek, given the elapsed
/// milliseconds since the previous SEEKABLE tap (`null` → none tracked yet / after a miss →
/// always `false`) and whether that previous tap landed in the SAME [TapZone] (design
/// `screens.jsx:306`'s `(now - last.t) < 320 && ... last.zone === ps.zone`). BOTH conditions
/// must hold — a same-time-but-different-zone tap does NOT complete a double-tap; it starts its
/// own independently tracked pair instead (see [_PlayerShellViewState._handleSeekableTap]).
/// STRICT `<` (matches the retired `isLiveDoubleTap`'s own boundary choice, NOT `<=`). Parity
/// iOS `PlayerShellView.isDoubleTapSeekHit(elapsedSinceLastSeekTap:sameZone:window:)`.
/// Unit-testable without a gesture.
bool isDoubleTapSeekHit({
  required int? elapsedMs,
  required bool sameZone,
  int windowMs = kDoubleTapSeekWindowMs,
}) =>
    elapsedMs != null && elapsedMs < windowMs && sameZone;

/// Seek step for a double-tap-seek hit, in seconds (rb-flutter-gesture-clean-mode-v2, design
/// `screens.jsx`'s `deltaSec = ps.zone === 'ff' ? 10 : -10`). [TapZone.fastForward] → `+`,
/// [TapZone.rewind] → `-`.
const double kSeekStepSeconds = 10;

/// Long-press 2x-speed hold's tick interval (rb-flutter-gesture-clean-mode-v2, design / iOS
/// `speedModeTickInterval = 0.5s`). Each tick adds [kSpeedModeExtraSeekPerTick] on top of the
/// engine's own normal 1x advance, so the NET effect over real time approximates 2x playback.
const Duration kSpeedModeTickInterval = Duration(milliseconds: 500);

/// Extra seconds a single 2x-speed tick adds (rb-flutter-gesture-clean-mode-v2, design / iOS
/// `speedModeExtraSeekPerTick = 0.5`).
const double kSpeedModeExtraSeekPerTick = 0.5;

/// PURE: whether `PlaybackProgressBarView` should be composed (rb-flutter-vod-playback-progress-
/// bar, design `screens.jsx` `LBPPlayerScreen` "Playback progress bar — VOD and replay only").
/// `= isMain && !isUpcoming && (!isLive || isReplay)` — a literal 4-argument mirror of the design
/// formula (matching iOS `showsPlaybackProgressBar(isMain:isUpcoming:isLive:isReplay:)`), kept
/// generic rather than simplified even though [isUpcoming] is always `false` at this call site
/// (`_buildUpcoming` early-returns before `_buildContent` composes this) and [isLive] /
/// [isReplay] are mutually exclusive (so the formula reduces to `isMain && !isLive` in practice)
/// — 1:1 fidelity with the design formula costs nothing and matches the iOS precedent's own
/// documented reasoning for keeping the redundant parameter.
///
/// The call site in `_buildContent` MUST feed `isReplay: model.isFinishedLiveReplay` (已結束直播
/// 回放，`type == 3 || (type == 2 && liveStatus == 3)`) — **MUST NOT** feed `model.isReplay`
/// (`playbackProgress.isReplay`, the narrower core DVR concept: a stream STILL actively live,
/// scrubbed behind the live edge). Core's `vodScrubAllowed` rejects any seek while
/// `liveStatus == 1` regardless, so gating on the narrower flag would show a bar that visually
/// drags but every `seek` call silently no-ops — the exact wiring bug iOS's own design.md records
/// as caught and fixed before archive; this Flutter port starts from the corrected wiring.
/// Unit-testable without a widget.
bool showsPlaybackProgressBar({
  required bool isMain,
  required bool isUpcoming,
  required bool isLive,
  required bool isReplay,
}) =>
    isMain && !isUpcoming && (!isLive || isReplay);

/// PURE: the extra bottom inset for the `PlaybackProgressBarView`'s outer `Positioned` slot
/// (rb-flutter-player-shell-bottom-safearea; MODIFIED by fix-flutter-player-shell-bottom-safearea-
/// gaps, BREAKING). Both the EXPANDED transport bar AND the IDLE thin line now clear the system
/// bottom safe area (home indicator / Android gesture bar) with the SAME formula —
/// `screens.jsx:420-424`'s `Math.max(0, safeArea.bottom - (platform==='android'?8:0))`.
///
/// This OVERTURNS the prior idle carve-out (idle used to always return `0`, matching the design's
/// idle-line formula `screens.jsx:387-394`, which omits any safe-area term). Rationale: a real
/// iOS device test showed the idle line has no home-indicator problem there — traced to SwiftUI's
/// default automatic safe-area avoidance for any view not explicitly `.ignoresSafeArea()`, which
/// iOS's `PlaybackProgressBarView.swift` and its call site never opt out of (idle and expanded
/// share the same layout there, with zero explicit safe-area code). Flutter's `Stack`/`Positioned`
/// has no such platform default, so this aligns Flutter to iOS's *actual observed device
/// behavior* rather than to the design mockup's literal formula.
///
/// [expanded] is now UNUSED by the formula itself (kept in the signature for call-site and test
/// parity — both states compute the identical result for the same [safeAreaBottom]/[isAndroid]).
/// [isAndroid] MUST feed `defaultTargetPlatform == TargetPlatform.android` (a device/OS fact, not
/// `Theme.of(context).platform`, which a host app could override for unrelated gesture-convention
/// reasons). Result is never negative. Scope: this slot ONLY — the other bottom-pinned
/// player-shell chrome (clean-mode exit button, floating bag, VOD side rail, LIVE bottom bar) is
/// unaffected and out of scope for this function (see design.md Non-Goals). Unit-testable without
/// a widget.
double progressBarBottomSafeAreaInset(
  double safeAreaBottom, {
  required bool expanded,
  required bool isAndroid,
}) {
  final adjusted = safeAreaBottom - (isAndroid ? 8.0 : 0.0);
  return adjusted < 0 ? 0 : adjusted;
}

/// PURE: the「退出乾淨模式」小圓鈕的完整 `bottom` offset (rb-flutter-player-shell-bottom-chrome-
/// safearea), closing the first of the 4 bottom-pinned chrome gaps `rb-flutter-player-shell-bottom-
/// safearea`'s own design.md Non-Goals deliberately deferred. Design `screens.jsx:426`/`:614`:
/// `bottom: 16 + safeArea.bottom + ((scrubVisible || cleanMode) ? 36 : 0)` — this button only ever
/// renders while `cleanMode == true`, so the ternary collapses to the file's existing fixed base
/// values (`isLive ? 16 : 52` — same base values as iOS's sibling `PlayerShellView.
/// cleanModeExitButtonBaseBottomInset(isLive:)`) plus `safeAreaBottom` verbatim (no Android
/// correction — unlike the progress bar, none of this
/// change's 4 formulas carry one). [isLive] MUST feed `PlayerShellModel.isLive`. Result is never
/// negative (both base values and `safeAreaBottom` are non-negative). Unit-testable without a
/// widget.
double cleanModeExitButtonBottomInset(
  double safeAreaBottom, {
  required bool isLive,
}) =>
    (isLive ? 16 : 52) + safeAreaBottom;

/// PURE: the floating bag button (`FloatingBagButton`)'s full `bottom` offset
/// (rb-flutter-player-shell-bottom-chrome-safearea). Design `sdk-components.jsx:832`
/// (`LBPBagButton`): `bottom: 16 + safeBottom`, where the call site's own `safeBottom` local
/// already bundles `safeArea.bottom + (scrubVisible ? 36 : 0)` — [lift] MUST feed the SAME
/// `_scrubBarExpanded ? _scrubChromeLift : 0.0` expression already passed at this call site (no
/// change to that existing logic, only to how `bottom` is assembled from it). Unit-testable
/// without a widget.
double floatingBagButtonBottomInset(
  double safeAreaBottom, {
  required double lift,
}) =>
    16 + safeAreaBottom + lift;

/// PURE: the VOD side rail (`OperationRailView`)'s full `bottom` offset
/// (rb-flutter-player-shell-bottom-chrome-safearea). Design `sdk-components.jsx:811`
/// (`LBPSideRail`): `bottom: 68 + safeBottom`, same `safeBottom` bundling as
/// [floatingBagButtonBottomInset]. [lift] MUST feed the SAME `_scrubBarExpanded ? _scrubChromeLift
/// : 0.0` expression already passed at this call site. Unit-testable without a widget.
double vodSideRailBottomInset(
  double safeAreaBottom, {
  required double lift,
}) =>
    68 + safeAreaBottom + lift;

/// PURE: the LIVE bottom bar (`LiveBottomBarView`)'s outer wrapper `bottom` offset
/// (rb-flutter-player-shell-bottom-chrome-safearea), shared by BOTH of its call sites (main
/// live-chrome branch AND `_buildUpcoming`'s slim variant). Design `live-chrome.jsx:183`
/// (`LBLiveBottomBar`): `padding-bottom: 16 + safeBottom`, call site `screens.jsx:590` resolves
/// `safeBottom = safeArea.bottom` (no `+36` term — the LIVE bottom bar's scrub-hold lift is a
/// SEPARATE `lift` prop in the design, orthogonal to `safeBottom`). The `16` base itself is
/// `LiveBottomBarView`'s OWN internal `_barBottomPadding`, already baked into that untouched
/// widget — NOT part of this function's job, hence no base constant here. [lift] MUST feed
/// `_scrubBarExpanded ? _scrubChromeLift : 0.0` at the main live-chrome call site, and `0.0` at the
/// upcoming slim call site (no scrub bar exists there). Unit-testable without a widget.
double liveBottomBarBottomInset(
  double safeAreaBottom, {
  required double lift,
}) =>
    safeAreaBottom + lift;

/// PURE: whether `LiveNowPillView` should be composed (rb-flutter-live-now-pill, design
/// `claude-design-sync.md` R28 / `components.md` `LBLiveNowPill`). Parity iOS `showsLiveNowPill`
/// (post `fix-ios-live-now-pill-active-live-leak`) / Android (post round-2 correction) / RN —
/// Flutter starts from the ALREADY-corrected formula: the `isLive` exclusion is present from
/// day one, not bolted on after an independent verifier caught the leak (see design.md Decision
/// 3 for the two-platform round-1 incident history this avoids).
///
/// `= hasLiveNow && (isMain || isFinishedLiveReplay) && !isUpcoming && !cleanMode && !isScrubbing
///    && (!isLive || isFinishedLiveReplay)` — the LAST clause is independently ANDed onto the
/// existing formula, NOT substituted for the `isMain` term: `showsPlaybackProgressBar`'s own
/// `isLive` exclusion works because its second term is a bare `isMain`, but this formula's
/// second term is `(isMain || isFinishedLiveReplay)` (using `||`), so the exclusion cannot be
/// folded into it — see design.md Decision 3 for the full derivation.
///
/// [isMain] MUST feed the SAME `isMainPlaybackPhase` value `showsPlaybackProgressBar` uses — it
/// only excludes the opening MP4 / cold-start loading / splash sequence, and is `true`
/// throughout an ACTUALLY-live broadcast, which is exactly why the independent [isLive]
/// exclusion is required. [isFinishedLiveReplay] MUST feed `model.isFinishedLiveReplay` — MUST
/// NOT feed core's narrower DVR `model.isReplay` (same call-site discipline as
/// `showsPlaybackProgressBar`'s own `isReplay` parameter). The design's `!isMinimized` condition
/// is deliberately NOT a parameter here — `CollapsibleLivebuyPlayer` is a KEEP-ALIVE design (an
/// ancestor hides the collapsed player via `Opacity`/`IgnorePointer`, it does not unmount it),
/// so that exclusion is satisfied by an ancestor further up the tree, not by this function.
/// Unit-testable without a widget.
bool showsLiveNowPill({
  required bool hasLiveNow,
  required bool isMain,
  required bool isUpcoming,
  required bool isLive,
  required bool isFinishedLiveReplay,
  required bool cleanMode,
  required bool isScrubbing,
}) =>
    hasLiveNow &&
    (isMain || isFinishedLiveReplay) &&
    !isUpcoming &&
    !cleanMode &&
    !isScrubbing &&
    (!isLive || isFinishedLiveReplay);

/// PURE: whether `CaptionOverlayView` should be mounted (rb-flutter-subtitle-vtt-caption-display,
/// design `sdk-components.jsx` `LBPCaptionOverlay`). `= !isLive && !introPlaying && subtitleEnabled
/// && captionText.isNotEmpty`. [isLive] MUST be fed the narrow `m.isLive` at the call site, NOT
/// the union `usesLiveChrome = m.isLive || m.isFinishedLiveReplay` (`PlayerShellView.usesLiveChrome`,
/// used by the genuinely-LIVE-chrome-related gates elsewhere in this file) — captions and "does
/// this state wear LIVE chrome" are independent concerns, so an already-finished live replay
/// still gets captions (like VOD) even though it also wears the LIVE bottom bar / overlay chrome.
/// `rb-flutter-subtitle-vtt-caption-display` (archived 2026-08-31) deliberately chose the narrow
/// `m.isLive` here (design.md Decision 2) and its own Risks/Trade-offs explicitly predicted that
/// a future `usesLiveChrome` unification would make captions follow it automatically.
/// `rb-flutter-replay-live-chrome-parity` (archived 2026-09-06) was exactly that predicted
/// unification — retargeting this call site to `usesLiveChrome` was an explicit, itemized goal
/// of that change (its own proposal.md/design.md list it by name), not an accidental sweep; the
/// effect was that finished-live-replay videos stopped showing captions, matching iOS/Android at
/// the time. `rb-flutter-replay-caption-overlay-fix` (2026-09-09) deliberately REVERSES that
/// unification back to `m.isLive`, per a user report + a four-platform sibling product decision
/// — this is a new product decision, not a regression fix. The caller additionally ANDs
/// `!_isScrubbing && !_cleanMode` at the `_buildContent` call site
/// (mirrors Android's own `shouldShowCaptionOverlay(...) && !isScrubbing` call-site split) —
/// those two are NOT baked into this function. Unit-testable without a widget.
bool shouldShowSubtitleCaption({
  required bool isLive,
  required bool introPlaying,
  required bool subtitleEnabled,
  required String captionText,
}) =>
    !isLive && !introPlaying && subtitleEnabled && captionText.isNotEmpty;

/// PURE: the caption overlay's trailing (right) inset, in logical pixels
/// (rb-flutter-caption-overlay-align-hide-chat, parity design `sdk-components.jsx`
/// `LBPCaptionOverlay`). The overlay centers inside a box that reserves this much space on the
/// right for whichever chrome shares the bottom-right corner — NOT the full screen width.
/// `shouldShowSubtitleCaption`'s `!isLive` gate means the only two states that ever reach
/// `_buildSubtitleCaption` are pure VOD (`isFinishedLiveReplay == false`) and an already-finished
/// live replay (`isFinishedLiveReplay == true`), so this only needs to choose between the two:
/// pure VOD → `68` (clears `OperationRailView`, the VOD side rail, parity `screens.jsx` L533's
/// `LBPCaptionOverlay` call omitting `right` → the component's own default `right=68`);
/// already-finished replay → `120` (clears the LIVE bottom bar / pinned-card column, parity
/// `screens.jsx` L576 `<LBPCaptionOverlay right={120} .../>`). Unit-testable without a widget.
double captionOverlayRightInset({required bool isFinishedLiveReplay}) =>
    isFinishedLiveReplay ? 120.0 : 68.0;

/// The explicit safety clearance (logical pixels) kept between the caption overlay's bottom edge
/// and `LiveBottomBarView`'s top edge in the already-finished-live-replay branch of
/// [captionOverlayBottomInset] (`rb-flutter-caption-overlay-bottom-bar-clearance-fix`). An
/// engineering judgment call, not a design-mockup-derived value — parity iOS sibling fix's own
/// `bottomBarClearanceGap` (same `12`, same rationale: give a comfortable, explicitly-named
/// buffer beyond the bar's real height rather than hugging it exactly).
const double captionOverlayBottomBarClearanceGap = 12;

/// PURE: the caption overlay's `bottom` offset (`rb-flutter-caption-overlay-bottom-bar-clearance-
/// fix` established this function; `rb-flutter-vod-caption-reserve-card-space` MODIFIED the pure-
/// VOD base below; `fix-flutter-player-shell-bottom-safearea-gaps` MODIFIED the pure-VOD base
/// again to fold in [safeAreaBottom]). Pure VOD (`isFinishedLiveReplay == false` — the only other
/// state that ever reaches `_buildSubtitleCaption`, per `shouldShowSubtitleCaption`'s `!isLive`
/// gate) now uses `safeAreaBottom + 92 + lift`, matching the design authority
/// (`design/templates/minimal/screens.jsx:533` `LBPCaptionOverlay`'s `safeBottom = safeArea.bottom
/// + (scrubVisible ? 36 : 0) + 92`) EXACTLY — this OVERTURNS the prior rule that `safeAreaBottom`
/// MUST NOT be folded in here (the stated reason, "this branch never shares the screen with
/// `LiveBottomBarView`, so there is nothing to clear against it", was true but conflated two
/// separate concerns: not needing extra clearance against a specific sibling bar is not the same
/// as not needing to clear the system safe area at all — a real device with a non-trivial home
/// indicator / gesture nav still needs this branch's caption pinned above it). The `92` unconditionally
/// reserves the vertical space `NowIntroducingCarousel` (the VOD "now introducing" product card,
/// built by `_buildNowIntroducing`) occupies via its own independent `Positioned(bottom: 0)` +
/// `padding.bottom = 12 + lift` — the caption and the card are two separate `Positioned` widgets
/// in the same `Stack` with zero awareness of each other, so without this fixed reservation the
/// card's content can render directly on top of the caption whenever it appears. This mirrors the
/// design's own unconditional reservation (parity `LBPMiniCart`,
/// `design/templates/minimal/sdk-components.jsx:908`, `bottom: 12 + safeBottom`) rather than
/// conditionally sizing the gap only when the card happens to be mounted — same fix as the RN
/// sibling change (`rb-rn-vod-caption-reserve-card-space`), which has the identical zero-coupling
/// two-widget structure. This supersedes the previous fixed `8 + lift` base, which pre-dates this
/// requirement and never accounted for the product card at all.
///
/// Already-finished live replay (`isFinishedLiveReplay == true`) ALSO wears `LiveBottomBarView`
/// (`usesLiveChrome` branch), whose own outer wrapper sits at
/// `liveBottomBarBottomInset(safeAreaBottom, lift: lift) == safeAreaBottom + lift` and occupies
/// [LiveBottomBarView.barHeight] above that. The caption's OLD fixed `8 + lift` base ignored both
/// terms entirely (zero coupling to the real bar position) — on any device with a non-trivial
/// `safeAreaBottom` (home indicator / gesture nav) the caption box's bottom edge sat INSIDE the
/// bar's occupied band, guaranteeing visual overlap regardless of caption text length (parity root
/// cause: iOS `rb-ios-caption-overlay-bottom-bar-clearance-fix` — `64` decoupled from
/// `LiveBottomBarView.swift`'s real height; Flutter's case was structurally worse because
/// `safeAreaBottom` was an extra unaccounted-for term). Fix: derive from the SAME `safeAreaBottom +
/// lift` base the real bar uses, plus its real height, plus an explicit clearance gap
/// ([captionOverlayBottomBarClearanceGap]) — this guarantees a fixed minimum clearance regardless
/// of `safeAreaBottom`'s actual value. This branch is NOT touched by
/// `rb-flutter-vod-caption-reserve-card-space` — out of scope, already correct. [lift] MUST feed
/// the SAME `_scrubBarExpanded ? _scrubChromeLift : 0.0` expression already passed at the call
/// site (existing lift-on-release behavior is preserved, not baked separately into this function).
/// Unit-testable without a widget.
double captionOverlayBottomInset(
  double safeAreaBottom, {
  required bool isFinishedLiveReplay,
  required double lift,
}) =>
    isFinishedLiveReplay
        ? safeAreaBottom +
            lift +
            LiveBottomBarView.barHeight +
            captionOverlayBottomBarClearanceGap
        : safeAreaBottom + 92 + lift;

/// Run a vertical-swipe in-place NAVIGATE then report the switched video id (swipe-video-switched-
/// notify, parity iOS / Android / RN). Forwards [navigate] (→ template → core `load`) FIRST, then —
/// when the resolved [adjacentId] is non-null — reports it via [onDidSwitchVideo] so the container
/// can record the shown id + raise `config.onVideoSwitched(id)` (parity with the watch-next /
/// hot-pick paths). The NAVIGATE branch only runs when `hasNextVideo` / `hasPrevVideo` is true, so
/// [adjacentId] is non-null there; the null-guard is defensive. PURE (no widget / gesture) →
/// unit-testable, parity iOS `PlayerShellModel.navigateToNext` fire.
///
/// [onLoadVideo] (flutter-swipe-video-load-requester-wiring-reference-ui, additive / optional):
/// fired ALONGSIDE [onDidSwitchVideo] with the SAME non-null [adjacentId] — see
/// [PlayerShellView.onSwipeVideoLoad]'s doc comment for why a SEPARATE, container-controller-
/// direct reload seam is needed ([navigate] alone no longer reliably reloads the native player in
/// production). `null` (demo / golden / a host not wiring it) → no-op, byte-identical to before
/// this parameter existed.
void navigateAndNotifySwitch(
  String? adjacentId,
  VoidCallback navigate,
  ValueChanged<String>? onDidSwitchVideo, [
  ValueChanged<String>? onLoadVideo,
]) {
  navigate();
  if (adjacentId != null) {
    onDidSwitchVideo?.call(adjacentId);
    onLoadVideo?.call(adjacentId);
  }
}

/// The family-1 player-shell container. Binds the relevant template
/// `ChangeNotifier`s with `ListenableBuilder`, re-reads the read-only
/// [PlayerShellModel] on each notify, and passes snapshot values BY VALUE to the
/// four surface widgets. Paints with the resolved [ReferenceUITheme].
///
/// `template == null` → the container uses the deterministic demo seeds (no
/// listenables to bind); the host normally supplies a live [DefaultPlayerTemplate].
class PlayerShellView extends StatefulWidget {
  /// Live template (host-supplied). `null` → deterministic demo seeds.
  final DefaultPlayerTemplate? template;

  /// Resolved reference-ui theme.
  final ReferenceUITheme theme;

  // Host-wired interaction callbacks. The shell owns NO action — each is forwarded
  // to the host (which wires it to core `simulate*`). All optional; default no-op.

  /// Host-wired minimize → host collapses the player into the bottom-right floating
  /// widget.
  final VoidCallback? onMinimize;

  /// Host-wired mute toggle, fired by the tap-to-mute gesture on the video area
  /// (NOT a header button). host → core `simulate*`.
  final VoidCallback? onToggleMute;

  /// Host-wired subscribe toggle (host → core `simulate*`).
  final VoidCallback? onToggleSubscribe;

  /// Whether the header's subscribe badge is drawn at all
  /// (rb-flutter-subscribe-favorite-visibility-toggle, parity iOS / Android / RN). Forwarded
  /// verbatim to both `PlayerHeaderBarView` call sites below (LIVE/VOD + upcoming). Default
  /// `true` — this WIDGET's own default keeps existing call sites unchanged; the turnkey
  /// container flips it off by default via `LivebuyPlayerConfig.showSubscribe`.
  final bool showSubscribe;

  /// Whether the PlayerHeader viewer-count badge is drawn at all
  /// (rb-flutter-viewer-count-visibility-toggle, parity iOS / Android `showViewerCount`).
  /// Forwarded verbatim to BOTH `PlayerHeaderBarView` call sites below (LIVE/VOD main
  /// branch AND the upcoming/直播預告 branch), same forwarding discipline as
  /// [titleScroll] / [showSubscribe] — even though the upcoming branch's `isLive` is
  /// always `false` (so the badge gate is always inert there), omitting the forward
  /// would leave that call site silently depending on `PlayerHeaderBarView`'s own
  /// default rather than this widget's resolved value. Default `true` — matches
  /// iOS/Android's own default exactly (a pure host opt-OUT, unlike [showSubscribe]'s
  /// opt-in reversal).
  final bool showViewerCount;

  /// Whether the LIVE overlay chrome's gesture-hint pills (tap / long-press / swipe) are
  /// drawn at all (rb-flutter-gesture-hint-plumb, parity iOS `showGestureHints`). Forwarded
  /// to `LiveOverlayChromeView(showGestureHints:)` ANDed with the widget's own `_cleanMode`
  /// state (`widget.showGestureHints && !_cleanMode`) — parity iOS
  /// `showGestureHints && !cleanMode`, NOT Android's "cleanMode never affects
  /// showGestureHints" (that is Android's own deliberate, narrower scope choice, see
  /// design.md D1). Default `true` — this WIDGET's own default keeps existing call sites /
  /// goldens unchanged; the turnkey container's `LivebuyPlayerConfig.showGestureHints`
  /// defaults to `false` and is the value a host actually sees.
  final bool showGestureHints;

  /// MERCHANT capability gate for the top-bar title marquee — the RAW
  /// `extensions.video_title_scroll` wire value (rb-flutter-marquee-title-scroll, parity
  /// iOS / Android `titleScroll`). Passed through UNCHANGED (no cast, no local default);
  /// the single normalization point is `normalizeTitleScroll`, inside
  /// `PlayerHeaderBarView`. Forwarded verbatim to BOTH `PlayerHeaderBarView` call sites
  /// below (LIVE/VOD main branch AND the upcoming/countdown branch) — the upcoming branch
  /// draws, measures and scrolls the title just like the main one, so skipping it would
  /// silently drop the merchant setting on 直播預告 videos. Default `null` → scrolls
  /// (matching the backend's own "unset ⇒ `1`"). NOT a visibility switch.
  final Object? titleScroll;

  /// Whether the header's top-right button shows a "close" (✕) glyph instead of the
  /// default "minimize" (pip) glyph — a pure BY-VALUE presentation flag
  /// (rb-flutter-player-direct-close-button, parity iOS / Android). Forwarded verbatim
  /// to BOTH `PlayerHeaderBarView` call sites below (LIVE/VOD main branch AND the
  /// upcoming/直播預告 branch), same forwarding discipline as [titleScroll] /
  /// [showSubscribe] — omitting either would let that branch silently fall back to the
  /// header's own default. Default `false` — every EXISTING call site / golden baseline
  /// is unaffected; the collapsible presenter (`CollapsibleLivebuyPlayer`, via
  /// `LivebuyPlayer._overlayContext()` → `PlayerOverlayContext.showCloseIcon` →
  /// `MinimalDesign.playerOverlay`) is what resolves the real value.
  final bool showCloseIcon;

  /// Host-wired side-rail item tap, by kind (share / chat / like / … → core
  /// `simulate*`).
  final ValueChanged<LBSideRailKind>? onTapRailItem;

  /// Host-wired pinned-product tap — carries the tapped [LBProduct] (turnkey container
  /// default: opens that product's detail sheet). `rb-flutter-pinned-card-tap-opens-detail`:
  /// type widened from `VoidCallback?`.
  final ValueChanged<LBProduct>? onTapPinnedProduct;

  /// Host-wired 頻道分享（rb-flutter-player-share-default-sheet, parity iOS rb-ios-live-share /
  /// rb-ios-vod-rail-share）。容器（`LivebuyPlayer` → `MinimalDesign`）注入的預設**含系統分享 fallback**
  /// （`PlayerOverlayContext.onShare` = `config.onShare ?? Share.share(channel.share_url)`）。非 null →
  /// LIVE / 回放底部 bar 分享鈕與純 VOD 側欄 rail 分享鈕皆走此（而非只派 `VIDEO_SHARE_REQUEST` 事件、
  /// unwired host = 死按鈕的舊 rail 路由）；null（非容器 / snapshot / golden）→ 退回既有 `_handleRailTap`
  /// → `onTapRailItem`（只派事件、headless、像素不變）。比照同檔既有 `onNickname` 的 nil-fallback 慣例。
  final VoidCallback? onShare;

  /// Host-wired「聯絡商家」（`ContactMerchantModalView`「確定」之後的動作，
  /// dropin-service-link-default-browser-flutter）。非 null → `_confirmContactMerchant()` 呼叫它、
  /// **不**呼叫 `onTapRailItem`；null（DEFAULT，現有 host / demo / snapshot）→ fallback 到既有
  /// `onTapRailItem?.call(LBSideRailKind.serviceLink)`（現況行為不變）。跟 [onShare] 刻意不對稱：
  /// 容器組裝處 MUST NOT 為此欄位注入任何智慧預設（`shop.serviceLink` 在目前生產環境的 Flutter
  /// reference-ui 拿不到值——host-feeds 架構的既有限制，見 design.md）。
  final VoidCallback? onServiceLink;

  /// VOD 介紹中卡輪播某張卡的開明細（rb-flutter-now-introducing，問題 9/10）。host 接 core
  /// `simulateProductTap`（與商品列 onProductTap 同出口）。Default null → inert（demo / golden）。
  final ValueChanged<LBProduct>? onTapNowIntroducingProduct;

  /// host runtime（真實影片在後）→ VOD 介紹卡輪播疊真實商品圖。Default false（demo / golden 走
  /// placeholder、baseline 確定）。對齊 iOS carousel `live: !paintsBackgroundPlaceholder`。
  final bool live;

  /// LIVE bottom bar 留言 tap → host opens its comment composer (the bar's other
  /// buttons route through [onTapRailItem] by kind). Default null → inert.
  final VoidCallback? onComment;

  /// LIVE bottom bar 暱稱 tap → the container presents the 設定暱稱 modal locally (parity
  /// iOS / Android / RN). Unlike the other bar buttons (routed through [onTapRailItem] by kind,
  /// where the 暱稱 rail tap hits the gated core `simulateGuestNameEditTap()` → silent no-op),
  /// the container wires this to `nickname.present(false)`. Default null → falls back to the
  /// rail route (demo / standalone).
  final VoidCallback? onNickname;

  /// Optional host override for the swipe-UP gesture (rb-player-shell swipe-override
  /// seam). Non-null → called INSTEAD of the shell's built-in `model.navigateToNext()`.
  /// The turnkey `LivebuyPlayer` always passes null (host-feed `swipeFeed` removed → swipe
  /// uses backend `prev`/`next`); the seam is retained for hosts wiring `PlayerShellView`
  /// directly. null (DEFAULT) → falls back to the built-in channel-adjacency navigation +
  /// close-on-empty. Flutter parity of iOS `PlayerShellView.onSwipeUp`.
  final VoidCallback? onSwipeUp;

  /// Optional host override for the swipe-DOWN gesture. Symmetric to [onSwipeUp]:
  /// non-null → called INSTEAD of `model.navigateToPrev()`; null → built-in fallback.
  final VoidCallback? onSwipeDown;

  /// Swipe toward an EMPTY direction (no next / prev video) → close the player
  /// (swipe-nav-close-on-empty). Only on the built-in (no host override) fallback path:
  /// when the swiped direction has an adjacent video the shell navigates, else it raises
  /// this instead of the prior silent no-op (the list is at its head / tail). null /
  /// default → swipe-to-empty is a no-op (demo / golden). The container wires this from
  /// `config.onDismiss ?? controller.unload`. Parity iOS / Android / RN `onCloseRequest`.
  final VoidCallback? onCloseRequest;

  /// Reports the NEW video id after a vertical-swipe in-place switch resolves a non-null adjacent
  /// target (swipe-video-switched-notify, parity iOS / Android / RN). The container wires this to a
  /// notify-only callback (records the shown id + raises `config.onVideoSwitched(id)`) so a
  /// host-bound video mirror (the minimized floating preview) tracks the shown video after a swipe —
  /// parity with the hot-pick path. Empty-direction swipe (close-on-empty) does NOT report. null
  /// (demo / golden) → no report.
  final ValueChanged<String>? onDidSwitchVideo;

  /// Fired ALONGSIDE [onDidSwitchVideo] with the SAME resolved adjacent video id
  /// (flutter-swipe-video-load-requester-wiring-reference-ui). The built-in swipe fallback's
  /// "official" reload path — `model.navigateToNext()`/`navigateToPrev()` → `DefaultPlayerTemplate
  /// .navigateToNext()`/`navigateToPrev()` → the injected `VideoLoadRequester` — is a DEAD no-op in
  /// production: `LivebuyUI.install()` (`flutter-ui/lib/src/livebuy_ui.dart`) never wires that
  /// requester (unlike `guestNameEditRequester` / `viewCartRequester`, which it DOES wire), so
  /// `navigate()` above does nothing observable. The turnkey `LivebuyPlayer` container wires this
  /// SEPARATE seam to `_controller.load(id)` DIRECTLY — the SAME container-held core controller
  /// [PlayerShellView.onToggleMute]'s default already bypasses the template with — then re-applies
  /// its currently-known mute truth to the freshly-(re)loaded engine (real-device report: manually
  /// mute → swipe → sound returns). null (demo / golden / a host wiring `PlayerShellView` directly
  /// without a container) → no-op, byte-identical to before this seam existed.
  final ValueChanged<String>? onSwipeVideoLoad;

  /// Reports the info panel (VideoInfoPanel bottom sheet) open/closed state to the container so
  /// it can hide the higher-layer chat feed while the panel is up (parity iOS rb-ios-info-panel-
  /// not-covered-by-chat). null → no report. The panel's own state / dismiss paths are unchanged.
  final ValueChanged<bool>? onInfoPanelOpenChange;

  /// Reports the「乾淨模式」(`_cleanMode`) open/closed state to the container so it can hide the
  /// higher-layer LIVE合流聊天 feed (`FeedWinOverlayView`) while it is up
  /// (rb-flutter-gesture-clean-mode-rewrite, bubble pattern copied verbatim from
  /// [onInfoPanelOpenChange] / rb-ios-info-panel-not-covered-by-chat). Fires on EVERY toggle. null
  /// → no report (demo / golden / a custom `ReferenceUIDesign` not wiring it).
  final ValueChanged<bool>? onCleanModeChange;

  /// Reports the closed-chat finished-replay rail's「更多」sheet (`_moreMenuOpen`) open/closed
  /// state to the container so it can hide the higher-layer LIVE合流聊天 feed
  /// (`FeedWinOverlayView`) while it is up (rb-flutter-live-more-sheet-above-chat, bubble pattern
  /// copied verbatim from [onCleanModeChange] / rb-flutter-gesture-clean-mode-rewrite). Fires on
  /// EVERY open/close. null → no report (demo / golden / a custom `ReferenceUIDesign` not wiring
  /// it). The sheet's own content / two actions / `BottomSheetPresenter` presentation are unchanged.
  final ValueChanged<bool>? onMoreMenuOpenChange;

  /// Reports every transition of the playback-progress transport bar's NARROW active-drag state
  /// (`_isScrubbing`: finger down until finger up) — rb-flutter-scrub-expanded-chrome-lift,
  /// bubble pattern copied verbatim from [onCleanModeChange] / [onMoreMenuOpenChange], parity
  /// iOS `onScrubbingChange` / Android `onScrubbingChange`. Fires from [_handleScrubStart] /
  /// [_handleScrubEnd]. null (demo / golden / a custom `ReferenceUIDesign` not wiring it) → no
  /// report — existing behavior unaffected.
  final ValueChanged<bool>? onScrubbingChange;

  /// Reports every transition of the transport bar's WIDE `_scrubBarExpanded` state (touch-down
  /// through the [_scrubHoldDuration] post-release hold window, NOT just the active drag) —
  /// rb-flutter-scrub-expanded-chrome-lift, parity iOS `onScrubBarExpandedChange` / Android
  /// `onScrubBarExpandedChange`. So the container can lift the SIBLING `FeedWinOverlayView`
  /// (composed outside this shell) the same amount `_buildContent` already lifts the in-shell
  /// `LiveOverlayChromeView` pinned card / announce banner via its own `bottomInset`. null → no
  /// report.
  final ValueChanged<bool>? onScrubBarExpandedChange;

  /// Whether the on-demand 留言 composer bar is currently presented over the shell. When true the
  /// LIVE bottom bar is hidden so the opaque composer does not overlap it (parity iOS
  /// rb-ios-chat-composer-opaque-hide-bottom-bar — `PlayerShellView(composerPresented:)`). Default
  /// false. The composer only opens in LIVE (the 留言 pill lives on the LIVE bottom bar), so the
  /// upcoming SLIM bar is unaffected.
  final bool composerPresented;

  /// Whether ANY product sheet/modal is currently presented by the sibling
  /// `ProductSheetsOverlayView` (rb-flutter-block-swipe-nav-when-sheet-open) — list drawer /
  /// detail-or-restock / zoom lightbox / cart-needs-login gate / variant-select prompt (see
  /// `anyProductSheetPresented` in `product_sheets_view.dart`). Fed into [allowsSwipeNav]'s
  /// `sheetsPresented` argument at `_handleSwipeEnded`'s call site — `true` blocks the vertical
  /// swipe-to-switch-video / close-on-empty gesture (both directions), mirroring the existing
  /// `isLive`-in-progress gate's shape (the swipe is still fully consumed by the enclosing
  /// `GestureDetector`, just never dispatched). Container-mirrored (`MinimalDesign.playerOverlay`
  /// forwards `PlayerOverlayContext.productSheetsPresented`, itself mirrored from
  /// `ProductSheetsOverlayView.onPresentationChange` — see that container's own doc comment).
  /// Default `false` → every existing call site / golden baseline (which never sets this)
  /// unaffected.
  final bool sheetsPresented;

  /// Whether another live broadcast is CURRENTLY detected (rb-flutter-live-now-pill) — feeds
  /// [showsLiveNowPill]'s `hasLiveNow` argument. Container-resolved (`LivebuyPlayerConfig
  /// .shopId`-driven `LiveNowPollController.liveNow != null`); the shell itself does not poll.
  /// Default `false` → the pill never composes (demo / golden / existing call sites unchanged).
  final bool hasLiveNow;

  /// Host-wired tap on `LiveNowPillView` (rb-flutter-live-now-pill). The shell only reports the
  /// tap — it does not resolve or hold the target video (see `LiveNowPillView`'s own doc
  /// comment). Default `null` → inert (demo / golden).
  final VoidCallback? onGoLive;

  /// Host-wired play/pause toggle for `PlaybackProgressBarView`'s transport-bar button
  /// (rb-flutter-vod-playback-progress-bar). Host → the container's own held
  /// `LivebuyPlayerController.togglePlayPause()` — deliberately NOT routed through
  /// `PlayerShellModel`/`DefaultPlayerTemplate.togglePlayPause()`, whose injection point
  /// (`LivebuyUI.install()`) never wires a real requester (see design.md). Default null → inert
  /// (demo / golden).
  final VoidCallback? onTogglePlayPause;

  /// Host-wired seek for `PlaybackProgressBarView`'s draggable track
  /// (rb-flutter-vod-playback-progress-bar). Fired on every drag position change with the
  /// resolved absolute seconds AND the current [PlayerShellModel.playbackDuration] (so the host
  /// can opt into core's `vodScrubAllowed` gate — this shell never supplies `liveStatus`, see
  /// design.md). Host → the container's own held `LivebuyPlayerController.seek(...)`, same
  /// bypass-the-template reasoning as [onTogglePlayPause]. Default null → inert (demo / golden).
  final void Function(double seconds, {double? duration})? onSeek;

  /// Test-only VTT fetcher override (rb-flutter-subtitle-vtt-caption-display,
  /// `docs/unit-test-discipline.md` `*ForTesting` naming convention). `null` (production default)
  /// → [defaultSubtitleVttFetcher] (real `dart:io HttpClient`). A widget test injects a capturing
  /// fake here to drive the fetch pipeline deterministically without a real network call.
  @visibleForTesting
  final SubtitleVttFetcher? subtitleVttFetcherForTesting;

  /// Test-only seed for the initial `_cleanMode` value (player-gesture-feedback-overlays-flutter,
  /// retargeted by rb-flutter-gesture-clean-mode-v2 from a long-press trigger to a short-tap one;
  /// `docs/unit-test-discipline.md` `*ForTesting` naming convention — parity iOS
  /// `PlayerShellView.cleanModeForTesting` / Android `PlayerShellScaffold.cleanModeForTesting`).
  /// `false` (production default) → unchanged existing behavior, `_cleanMode` starts `false` and
  /// only flips via a real short tap (immediately when NOT `isSeekable`, deferred by
  /// `kDoubleTapSeekWindowMs` when it IS). A widget/golden test that needs a `_cleanMode == true`
  /// render seeds this directly instead of driving a real gesture at the video-area's geometric
  /// center + waiting out the seekable branch's defer window — cheaper and keeps golden captures
  /// synchronous. iOS/Android hit the identical "SwiftUI/Compose gestures cannot be reliably
  /// driven from tests" limitation and resolved it the same way (a ctor-seeded test-only initial
  /// value, bypassing gesture simulation entirely) — this mirrors that established, verified
  /// pattern.
  @visibleForTesting
  final bool cleanModeForTesting;

  const PlayerShellView({
    super.key,
    this.template,
    required this.theme,
    this.onMinimize,
    this.onToggleMute,
    this.onToggleSubscribe,
    this.showSubscribe = true,
    this.showViewerCount = true,
    this.showGestureHints = true,
    this.titleScroll,
    this.showCloseIcon = false,
    this.onTapRailItem,
    this.onTapPinnedProduct,
    this.onShare,
    this.onServiceLink,
    this.onTapNowIntroducingProduct,
    this.live = false,
    this.onComment,
    this.onNickname,
    this.onSwipeUp,
    this.onSwipeDown,
    this.onCloseRequest,
    this.onDidSwitchVideo,
    this.onSwipeVideoLoad,
    this.onInfoPanelOpenChange,
    this.onCleanModeChange,
    this.onMoreMenuOpenChange,
    this.onScrubbingChange,
    this.onScrubBarExpandedChange,
    this.composerPresented = false,
    this.sheetsPresented = false,
    this.hasLiveNow = false,
    this.onGoLive,
    this.onTogglePlayPause,
    this.onSeek,
    this.subtitleVttFetcherForTesting,
    this.cleanModeForTesting = false,
  });

  @override
  State<PlayerShellView> createState() => _PlayerShellViewState();
}

class _PlayerShellViewState extends State<PlayerShellView> {
  /// Read-only snapshot bridge (re-read inside the ListenableBuilder on notify).
  late PlayerShellModel _model = PlayerShellModel(template: widget.template);

  /// Local presentation-only state for the bottom info panel (open/closed). The
  /// panel CONTENT (tabs / fields / notices) is driven by the model; this only
  /// governs the sheet affordance. Default open so the panel renders in the
  /// container layout (the standalone surface goldens render it directly).
  bool _infoPanelOpen = false;

  /// Pending delayed bubble for the info-panel CLOSE transition
  /// (rb-flutter-chat-reveal-sheet-dismiss-timing) — see [_setInfoPanel].
  Timer? _infoPanelDismissTimer;

  /// Set the info-panel open state AND report it up via [PlayerShellView.onInfoPanelOpenChange]
  /// (parity iOS rb-ios-info-panel-not-covered-by-chat) so the container can hide the chat feed
  /// while the panel is up. All open/close paths (host-badge toggle / scrim / header close) funnel
  /// through here. Default CLOSED — the panel opens only on an explicit host-badge / `more` tap
  /// (parity iOS/Android/RN; the prior `true` default opened it on load).
  ///
  /// rb-flutter-chat-reveal-sheet-dismiss-timing: OPENING stays fully synchronous — local state
  /// flips and [PlayerShellView.onInfoPanelOpenChange] fires in the SAME frame, unchanged. CLOSING
  /// also flips the local `_infoPanelOpen` immediately (so the [BottomSheetPresenter] card starts
  /// its `kSheetSlideDuration` slide-down animation right away, unchanged visual timing), but the
  /// bubble to the container is DEFERRED by `kSheetSlideDuration` — the sibling
  /// `FeedWinOverlayView`'s `chatVisible` gate is a hard boolean fed by that bubble with no
  /// transition of its own, so bubbling `false` synchronously made the chat feed reappear at full
  /// opacity while the sheet was still visibly sliding away underneath it (real-device report).
  /// Reopening before the deferred close fires cancels the pending stale `false` (same
  /// cancel-and-reschedule shape as [_scrubCollapseTimer] / [_pendingCleanModeToggleTimer]).
  void _setInfoPanel(bool open) {
    if (open == _infoPanelOpen) return;
    setState(() => _infoPanelOpen = open);
    _infoPanelDismissTimer?.cancel();
    if (open) {
      widget.onInfoPanelOpenChange?.call(true);
      return;
    }
    _infoPanelDismissTimer = Timer(kSheetSlideDuration, () {
      _infoPanelDismissTimer = null;
      if (!mounted) return;
      widget.onInfoPanelOpenChange?.call(false);
    });
  }

  /// 「乾淨模式」(rb-flutter-gesture-clean-mode-rewrite, retargeted by
  /// rb-flutter-gesture-clean-mode-v2) — presentation-only local state hiding most of the
  /// floating chrome. R23 toggled this via a long-press; R29 SUPERSEDES that — a short tap now
  /// toggles it instead (immediately when NOT [isSeekable], deferred by
  /// [kDoubleTapSeekWindowMs] when it IS — see [_handleVideoTap] / [_handleSeekableTap]). Long
  /// press is now reserved for the 2x-speed hold (see [_handleLongPressStart]) and no longer
  /// touches `_cleanMode` at all. Default `false`. Does NOT auto-reset across an in-place video
  /// switch (parity
  /// `_infoPanelOpen`'s own persistence — see design.md D7): there is no "new video loaded"
  /// signal to hang a reset on (`didUpdateWidget` only rebuilds `_model` on a `template`
  /// REFERENCE change, which production in-place switches never trigger).
  ///
  /// Seeded from [PlayerShellView.cleanModeForTesting] in [initState] (player-gesture-feedback-
  /// overlays-flutter) — a plain `= false` field initializer cannot reference `widget` (it runs
  /// before this `State` is attached), so this is `late` and assigned in [initState] instead.
  late bool _cleanMode;

  /// Toggle `_cleanMode` and report every flip up via [PlayerShellView.onCleanModeChange]
  /// (bubble pattern copied verbatim from [_setInfoPanel] / rb-ios-info-panel-not-covered-
  /// by-chat) so the container can hide the higher-layer LIVE合流聊天 feed while it is up.
  void _toggleCleanMode() {
    setState(() => _cleanMode = !_cleanMode);
    widget.onCleanModeChange?.call(_cleanMode);
  }

  /// Video-area single-tap dispatch (rb-flutter-gesture-clean-mode-v2, design R29 — SUPERSEDES
  /// the retired `_handleLiveTap` / `_handleReplayTap` / `_registerLikeableTap` trio and the
  /// double-tap-to-like feature they protected). Every short tap toggles `_cleanMode` — the only
  /// question is WHEN:
  ///
  /// - **NOT [isSeekable]** (a real live broadcast in progress, or its upcoming preview):
  ///   toggles `_cleanMode` IMMEDIATELY via [_toggleCleanMode]. There is no double-tap outcome to
  ///   protect against on this branch (LIVE has no double-tap reaction at all under R29), so no
  ///   defer is needed.
  /// - **[isSeekable]** (VOD / a finished-live replay): routes to [_handleSeekableTap], which
  ///   DEFERS the toggle by [kDoubleTapSeekWindowMs] so a fast follow-up tap in the SAME
  ///   [TapZone] can cancel it and seek instead — this is the exact "delay-commit + double-tap
  ///   cancels it" shape the retired `_handleLiveTap` / `_handleReplayTap` already used to
  ///   protect double-tap-to-LIKE; R29 reuses the same shape to protect double-tap-SEEK instead.
  ///
  /// [tapX] is the tap's horizontal offset from the video area's own left edge
  /// (`TapUpDetails.localPosition.dx`, read at the `GestureDetector.onTapUp` call site) — only
  /// consulted on the seekable branch (see [_handleSeekableTap] / [tapZone]).
  void _handleVideoTap(double tapX) {
    final isLive = _model.isLive;
    final isFinishedLiveReplay = _model.isFinishedLiveReplay;
    if (!isSeekable(isLive: isLive, isUpcoming: false, isFinishedLiveReplay: isFinishedLiveReplay)) {
      _toggleCleanMode();
      return;
    }
    _handleSeekableTap(tapZone(startX: tapX, containerWidth: _videoAreaWidth));
  }

  /// SEEKABLE-branch tap dispatch (VOD / finished-live replay, rb-flutter-gesture-clean-mode-v2)
  /// — "delay the `_cleanMode` toggle, cancel-and-seek on a same-zone double-tap within
  /// [kDoubleTapSeekWindowMs]" (design `screens.jsx:306`). A hit ([isDoubleTapSeekHit]) cancels
  /// [_pendingCleanModeToggleTimer] (so `_cleanMode` never actually flips for either tap) and
  /// commits a seek via [_commitSeek]; a miss (re)schedules the deferred toggle and remembers
  /// this tap's time/zone as the new pairing candidate.
  void _handleSeekableTap(TapZone zone) {
    final now = DateTime.now();
    final lastAt = _lastSeekTapAt;
    final elapsedMs = lastAt == null ? null : now.difference(lastAt).inMilliseconds;
    if (isDoubleTapSeekHit(elapsedMs: elapsedMs, sameZone: zone == _lastSeekTapZone)) {
      _lastSeekTapAt = null;
      _lastSeekTapZone = null;
      _pendingCleanModeToggleTimer?.cancel();
      _pendingCleanModeToggleTimer = null;
      _commitSeek(zone == TapZone.fastForward ? kSeekStepSeconds : -kSeekStepSeconds);
      return;
    }
    _lastSeekTapAt = now;
    _lastSeekTapZone = zone;
    _pendingCleanModeToggleTimer?.cancel();
    _pendingCleanModeToggleTimer =
        Timer(const Duration(milliseconds: kDoubleTapSeekWindowMs), () {
      _pendingCleanModeToggleTimer = null;
      _toggleCleanMode();
    });
  }

  /// Commit a one-shot seek by [deltaSeconds] relative to the model's CURRENT
  /// `playbackPosition` (rb-flutter-gesture-clean-mode-v2, double-tap-seek). Forwards the
  /// resulting ABSOLUTE target through the existing host-wired [PlayerShellView.onSeek] seam
  /// (`rb-flutter-vod-playback-progress-bar` — the same seam `PlaybackProgressBarView`'s
  /// draggable track already uses), clamped to `[0, playbackDuration]`. Flutter's `onSeek`
  /// signature is absolute-seconds-plus-duration, unlike iOS's delta-based
  /// `PlayerShellModel.seekBy(_:)` — this is the Flutter-side equivalent computation.
  void _commitSeek(double deltaSeconds) {
    final duration = _model.playbackDuration;
    final target = (_model.playbackPosition + deltaSeconds).clamp(0.0, duration);
    widget.onSeek?.call(target, duration: duration);
  }

  /// Video-area long-press dispatch (rb-flutter-gesture-clean-mode-v2). The framework
  /// `LongPressGestureRecognizer` stays UNCONDITIONALLY wired (see the `GestureDetector` call
  /// site) so the gesture arena keeps resolving a genuine long-press away from `onTapUp` exactly
  /// as before (parity the existing "a completed long-press does NOT ALSO dispatch a tap"
  /// guarantee) — but this callback's OWN body is what decides whether anything actually
  /// happens: NOT [isSeekable] (a real live broadcast in progress, or its upcoming preview) MUST
  /// `return` WITHOUT starting [_startSpeedMode] — this is a STRUCTURAL no-op, the app-level
  /// 2x-speed tick `Timer` this Requirement introduces is simply never scheduled for this branch,
  /// not "scheduled then gated inside the tick". [isSeekable] (VOD / finished-live replay) starts
  /// the 2x-speed hold.
  void _handleLongPressStart(LongPressStartDetails details) {
    if (!isSeekable(
        isLive: _model.isLive, isUpcoming: false, isFinishedLiveReplay: _model.isFinishedLiveReplay)) {
      return;
    }
    _startSpeedMode();
  }

  /// Begin the long-press 2x-speed hold (rb-flutter-gesture-clean-mode-v2). Captures the
  /// playback position AT THE MOMENT the hold starts as [_speedModeBaseline] — every subsequent
  /// tick adds on top of this LOCAL baseline rather than re-reading `_model.playbackPosition`
  /// (see [_scheduleNextSpeedModeTick]'s own doc comment for why), then kicks off the recurring
  /// tick via [_scheduleNextSpeedModeTick].
  void _startSpeedMode() {
    _speedModeBaseline = _model.playbackPosition;
    _speedModeTickCount = 0;
    _speedMode = true;
    _scheduleNextSpeedModeTick();
  }

  /// Recurring 2x-speed tick (rb-flutter-gesture-clean-mode-v2, parity iOS
  /// `scheduleSpeedModeTick()`). Re-schedules itself every [kSpeedModeTickInterval] for as long
  /// as [_speedMode] stays `true`; each firing bumps [_speedModeTickCount] and forwards
  /// `_speedModeBaseline + _speedModeTickCount * kSpeedModeExtraSeekPerTick` through
  /// [PlayerShellView.onSeek] — a MONOTONICALLY INCREASING absolute target computed purely from
  /// the LOCAL baseline + tick count, deliberately NOT `_model.playbackPosition` re-read fresh
  /// each tick: a real host's playback position is not guaranteed to have caught up with the
  /// PREVIOUS tick's `onSeek` call by the time this one fires, and a widget test's static
  /// template never updates it at all — re-reading would risk seeking to the SAME target
  /// repeatedly instead of advancing. **MUST NOT read [TapZone] / the press position** — a
  /// long-press hold is ALWAYS fast-forward (positive delta) regardless of which half of the
  /// video area it started in, deliberately preserving the upstream design demo's own direction
  /// bug ("long-press never rewinds") verbatim, per the user's explicit instruction after three
  /// rounds of back-and-forth clarification (see design.md).
  void _scheduleNextSpeedModeTick() {
    _speedModeTickTimer = Timer(kSpeedModeTickInterval, () {
      if (!_speedMode) return;
      _speedModeTickCount++;
      final duration = _model.playbackDuration;
      final target =
          (_speedModeBaseline + _speedModeTickCount * kSpeedModeExtraSeekPerTick)
              .clamp(0.0, duration);
      widget.onSeek?.call(target, duration: duration);
      _scheduleNextSpeedModeTick();
    });
  }

  /// End the long-press 2x-speed hold — release or cancel (rb-flutter-gesture-clean-mode-v2).
  /// Safe no-op when [_speedMode] is already `false` (the NOT-seekable branch of
  /// [_handleLongPressStart] never started it in the first place).
  void _stopSpeedMode() {
    if (!_speedMode) return;
    _speedMode = false;
    _speedModeTickTimer?.cancel();
    _speedModeTickTimer = null;
  }

  /// LIVE 底部 bar 愛心 burst tick（rb-flutter-live-bottom-heart-burst，問題 5）：愛心點擊遞增 →
  /// 即時飄心回饋。靜止態（tick 不變）→ HeartBurst 不畫 → golden byte-identical。
  int _liveHeartTick = 0;

  /// LIVE 底部 bar 讚鈕 liked（accent 亮色）狀態（`rb-flutter-live-like-burst-restyle`，design R37
  /// `LBLiveBottomBar.liked` / `screens.jsx` 的 `liked` state）：`true` 短暫持續於
  /// `resolveLiveLikeBurstPlan().likedDuration` 期間，過後自動回到 `false`（白色，`liked` 預設值）。
  bool _liveLiked = false;

  /// Pending liked→false revert timer（`rb-flutter-live-like-burst-restyle`）。每次點讚重新排程
  /// （design `clearTimeout(likeActiveTimerRef.current)` 後重新 `setTimeout`），讓連續快速點讚延長
  /// 亮色窗口，而非疊加多個 revert。
  Timer? _likeLikedTimer;

  /// 一次 LIVE 底部 bar 讚鈕點擊（`rb-flutter-live-like-burst-restyle`，design R37
  /// `likeAnimation()`）：解析隨機 1-4 顆 burst 計畫（`resolveLiveLikeBurstPlan`），依
  /// `spawnDelays` 錯開觸發 `_liveHeartTick` 遞增（每次遞增讓 `HeartBurst` 多飛一顆），並點亮讚鈕
  /// （`_liveLiked`）`likedDuration` 之後自動熄滅。主分支 / upcoming-slim 分支的兩個 `onLike` 呼叫
  /// 點共用這個單一入口（比照設計稿單一 `onLike={() => likeAnimation()}` 呼叫點）。
  void _triggerLiveLikeBurst() {
    final plan = resolveLiveLikeBurstPlan();
    for (final delay in plan.spawnDelays) {
      Future.delayed(delay, () {
        if (!mounted) return;
        setState(() => _liveHeartTick++);
      });
    }
    setState(() => _liveLiked = true);
    _likeLikedTimer?.cancel();
    _likeLikedTimer = Timer(plan.likedDuration, () {
      if (!mounted) return;
      setState(() => _liveLiked = false);
    });
  }

  /// Timestamp of the previous SEEKABLE video-area tap (rb-flutter-gesture-clean-mode-v2).
  /// Feeds [isDoubleTapSeekHit] together with [_lastSeekTapZone]. `null` initially / after a
  /// video-area tap that misses the double-tap-seek window. Only read/written inside
  /// [_handleSeekableTap] — a long-press or a non-seekable tap never touches it. Deliberately
  /// NOT reset on a video switch (mirrors [_cleanMode]'s own no-reset precedent).
  DateTime? _lastSeekTapAt;

  /// Which [TapZone] the previous SEEKABLE video-area tap landed in — paired with
  /// [_lastSeekTapAt]; both must match for [isDoubleTapSeekHit] to fire.
  TapZone? _lastSeekTapZone;

  /// Cancellable pending `_cleanMode`-toggle timer for a SEEKABLE short tap
  /// (rb-flutter-gesture-clean-mode-v2). Non-null ⟺ a single seekable tap is currently waiting
  /// out [kDoubleTapSeekWindowMs] before its `_cleanMode` toggle actually commits. `null` once
  /// fired / cancelled (by a same-zone double-tap-seek hit) / never scheduled (NOT-seekable
  /// branch toggles immediately, bypassing this field entirely).
  Timer? _pendingCleanModeToggleTimer;

  /// True while a long-press-driven 2x-speed hold is active (VOD / finished-live replay only —
  /// see [_handleLongPressStart] for why it structurally never becomes `true` for a genuinely-
  /// live broadcast). Gates whether [_scheduleNextSpeedModeTick]'s recurring `Timer` keeps
  /// firing `onSeek`; carries NO visual representation (design R29 shows no indicator during the
  /// hold), so this is plain instance state, not `setState`-driven.
  bool _speedMode = false;

  /// The playback position (seconds) captured the MOMENT the current 2x-speed hold started (see
  /// [_startSpeedMode]). Every tick's absolute seek target is computed relative to this fixed
  /// baseline, not a freshly-read `_model.playbackPosition` — see
  /// [_scheduleNextSpeedModeTick]'s own doc comment for why.
  double _speedModeBaseline = 0;

  /// Ticks elapsed since the current 2x-speed hold started. Multiplied by
  /// [kSpeedModeExtraSeekPerTick] against [_speedModeBaseline] to compute each tick's target.
  int _speedModeTickCount = 0;

  /// The recurring 2x-speed tick timer (see [_scheduleNextSpeedModeTick]). A plain `Timer` — the
  /// `flutter_test` binding advances real `Timer`s deterministically via `tester.pump(duration)`,
  /// so no dependency-injection seam is needed here (unlike iOS's injected `cleanModeTapSchedule`
  /// closure), matching this file's existing convention for its other timer-driven state.
  Timer? _speedModeTickTimer;

  /// The video area's current laid-out width (rb-flutter-gesture-clean-mode-v2), captured by the
  /// `LayoutBuilder` wrapping the video-area `GestureDetector` at the `_buildContent` call site.
  /// Feeds [tapZone] so a tap's horizontal offset can be classified into a [TapZone]. `0` before
  /// the first layout pass — [tapZone] defensively falls back to [TapZone.fastForward] for a
  /// zero-width container.
  double _videoAreaWidth = 0;

  /// VOD 介紹卡輪播本地關閉的商品 id（rb-flutter-now-introducing，問題 9/10）：關掉某張介紹卡 → 加入
  /// 此集合、輪播略過；playhead 前進該商品重新命中時會再出現（iOS/Android 同行為）。
  final Set<String> _dismissedVodProductIds = {};

  /// LIVE 釘選卡本地關閉的商品 id（rb-flutter-live-pinned-card-dismiss，LIVE 釘選卡 close 四端收官）：
  /// 點釘選卡右上角 X → 加入此集合、`visiblePinnedProducts` 過濾後不再顯示該卡；換成不同釘選商品
  /// （不同 id，真直播 narrate_status==2 換人）時正常重新顯示。鏡像 VOD 的 [_dismissedVodProductIds]。
  final Set<String> _dismissedLivePinnedIds = {};

  /// VOD WebVTT 字幕 cue 清單（rb-flutter-subtitle-vtt-caption-display）。**非** template 衍生值——
  /// `_maybeFetchSubtitleCues` 抓取 + 解析 `widget.template!.subtitle.url`（WebVTT）灌入，比照 iOS
  /// `PlayerShellModel.subtitleCues` / Android `PlayerOverlayContext.subtitleCues` 的「非 template
  /// 衍生、容器外部設定」精神——差別是 Flutter 沒有一層獨立容器，這個 state 直接活在
  /// `_PlayerShellViewState`（design.md Decision 3）。`_buildContent` 用它 + `_model.playbackPosition`
  /// 經 `VTTSubtitleParser.activeCue` 現算目前命中的字幕文字。預設 `[]`（無字幕 / 尚未抓取完成）。
  List<VTTCue> _subtitleCues = const [];

  /// 上次已處理（成功 fetch 或明確清空）過的 `subtitle.url`，換片防呆鍵（design.md Decision 4，
  /// `shouldRefetchSubtitleCues`）。`null` = 尚未處理過任何 url。
  String? _lastFetchedSubtitleUrl;

  /// Whether the「聯絡商家」confirm modal is presented (parity rb-*-contact-merchant-modal).
  /// The rail serviceLink tap and the info-panel「與商家一對一對話」now present this confirm
  /// FIRST; only its「確定」proceeds to the existing serviceLink host exit. Default false →
  /// modal not drawn → existing goldens unchanged.
  bool _contactMerchantPresented = false;

  /// Whether the closed-chat finished-replay「更多」sheet is presented (originally
  /// rb-flutter-live-replay-more-menu-and-video-info-live-copy, design R32). Opened by
  /// `LiveBottomBarView.onMore` (only reachable when `m.isFinishedLiveReplay` renders that
  /// variant's leading「更多」slot — `rb-flutter-replay-live-chrome-parity` moved the trigger
  /// here from the now-component-level-only `OperationRailView.onTapMore`; the sheet's own
  /// mechanism is unchanged). Its two actions each close this THEN forward to the existing
  /// `_handleRailTap(share / serviceLink)` — same pattern as [_contactMerchantPresented] /
  /// [_infoPanelOpen]. Default `false` → sheet not drawn → existing goldens unchanged.
  bool _moreMenuOpen = false;

  /// Pending delayed bubble for the「更多」sheet CLOSE transition
  /// (rb-flutter-chat-reveal-sheet-dismiss-timing) — see [_setMoreMenuOpen].
  Timer? _moreMenuDismissTimer;

  /// Set the「更多」sheet open state AND report it up via
  /// [PlayerShellView.onMoreMenuOpenChange] (rb-flutter-live-more-sheet-above-chat, bubble
  /// pattern copied verbatim from [_setInfoPanel] / [_toggleCleanMode]) so the container can
  /// hide the higher-layer合流聊天 feed while the sheet is up. All open/close paths (rail「更多」
  /// tap / scrim dismiss / 分享 / 客服) funnel through here.
  ///
  /// rb-flutter-chat-reveal-sheet-dismiss-timing: same delayed-bubble shape as [_setInfoPanel] —
  /// OPENING stays fully synchronous; CLOSING flips the local `_moreMenuOpen` immediately (the
  /// [BottomSheetPresenter] card starts sliding down right away) but defers the bubble to the
  /// container by `kSheetSlideDuration` so the chat feed does not reappear until the sheet has
  /// actually finished sliding away. Reopening before the deferred close fires cancels the
  /// pending stale `false`.
  void _setMoreMenuOpen(bool open) {
    if (open == _moreMenuOpen) return;
    setState(() => _moreMenuOpen = open);
    _moreMenuDismissTimer?.cancel();
    if (open) {
      widget.onMoreMenuOpenChange?.call(true);
      return;
    }
    _moreMenuDismissTimer = Timer(kSheetSlideDuration, () {
      _moreMenuDismissTimer = null;
      if (!mounted) return;
      widget.onMoreMenuOpenChange?.call(false);
    });
  }

  /// Accumulated vertical drag distance for the swipe-to-switch-video gesture
  /// (rb-player-shell-swipe). Reset on drag start; on drag end a magnitude past
  /// [_swipeThreshold] fires prev/next.
  double _swipeDy = 0;
  static const double _swipeThreshold = 60;

  /// Playback-progress-bar scrub state (rb-flutter-vod-playback-progress-bar). [_isScrubbing] is
  /// true from touch-down until touch-up — gates hiding the VOD side rail / floating bag / now-
  /// introducing carousel AND the bar's own drag-time timestamp readout. [_scrubBarExpanded] is
  /// true from touch-down until [_scrubHoldDuration] AFTER touch-up — gates the bar's idle-line-
  /// vs-transport-bar visual AND the ~36px chrome-lift padding while released-but-still-held.
  /// Two separate booleans (not one) because the design wants the readout to disappear
  /// immediately on release while the transport bar itself stays expanded for the hold window —
  /// mirrors iOS `PlayerShellView`'s own `isScrubbing`/`scrubBarExpanded` split.
  bool _isScrubbing = false;
  bool _scrubBarExpanded = false;
  Timer? _scrubCollapseTimer;
  static const Duration _scrubHoldDuration = Duration(milliseconds: 2800);

  /// Extra bottom inset applied to the VOD side rail / floating bag / now-introducing carousel
  /// while `_scrubBarExpanded && !_isScrubbing` (released, still within the hold window) so they
  /// clear the still-expanded transport bar (rb-flutter-vod-playback-progress-bar).
  static const double _scrubChromeLift = 36;

  /// Touch-down in the progress bar's hit area / track — cancels any pending collapse (a fresh
  /// touch mid-hold-window restarts scrubbing) and expands immediately. Reports both transitions
  /// (rb-flutter-scrub-expanded-chrome-lift, parity iOS `handleScrubStarted`): [onScrubbingChange]
  /// unconditionally (the narrow drag state always starts here); [onScrubBarExpandedChange] only
  /// when the WIDE state was not already expanded (a fresh touch mid-hold-window, see
  /// [_scrubCollapseTimer]'s cancel above, stays already-expanded — no redundant re-report).
  void _handleScrubStart() {
    _scrubCollapseTimer?.cancel();
    final wasExpanded = _scrubBarExpanded;
    setState(() {
      _isScrubbing = true;
      _scrubBarExpanded = true;
    });
    widget.onScrubbingChange?.call(true);
    if (!wasExpanded) widget.onScrubBarExpandedChange?.call(true);
  }

  /// Touch-up (or cancel) — the readout hides immediately (`_isScrubbing = false`,
  /// [onScrubbingChange] reports `false` right away so a lifted sibling surface can reappear);
  /// the transport bar itself stays expanded for [_scrubHoldDuration] before collapsing, at which
  /// point [onScrubBarExpandedChange] reports `false` (rb-flutter-scrub-expanded-chrome-lift,
  /// parity iOS `handleScrubEnded`).
  void _handleScrubEnd() {
    setState(() => _isScrubbing = false);
    widget.onScrubbingChange?.call(false);
    _scrubCollapseTimer?.cancel();
    _scrubCollapseTimer = Timer(_scrubHoldDuration, () {
      if (!mounted) return;
      setState(() => _scrubBarExpanded = false);
      widget.onScrubBarExpandedChange?.call(false);
    });
  }

  // -- VOD WebVTT subtitle fetch pipeline (rb-flutter-subtitle-vtt-caption-display) -------------
  //
  // Two SEPARATE reactions to `widget.template!.subtitle` changing (design.md Decision 3):
  //   1. Pure REDRAW — `t.subtitle` is in `build()`'s `mergeable` list (below), so a change
  //      re-runs `_buildContent` and re-reads `_model.subtitleEnabled` / `_subtitleCues`.
  //   2. The FETCH side effect — this dedicated `addListener` (registered in [initState] /
  //      [didUpdateWidget], removed in [dispose]), mirrors Android `template.addObserver`'s own
  //      separation between Compose's declarative recomposition and a side-effecting callback.
  // In-place video switches do NOT change `widget.template`'s IDENTITY (see `_cleanMode`'s doc
  // comment above — `didUpdateWidget` only rebuilds on a template REFERENCE change) — they flow
  // entirely through reaction 2, keyed on `subtitle.url` itself (design.md Decision 4).

  /// URLs already handed to [_precacheProductImage] THIS `PlayerShellView` presentation
  /// (rb-flutter-product-image-loading-polish) — de-dupes a repeat `productOverlay`
  /// notify whose resolved URL set is unchanged (design.md Risk 2) so it costs one
  /// cheap `Set` diff and prefetches nothing new, never a duplicate `precacheImage`
  /// call for the same URL.
  final Set<String> _prefetchedProductImageUrls = {};

  @override
  void initState() {
    super.initState();
    _cleanMode = widget.cleanModeForTesting;
    widget.template?.subtitle.addListener(_onSubtitleStateChanged);
    _maybeFetchSubtitleCues();
    // rb-flutter-product-image-loading-polish — SEPARATE side-effect listener from the
    // declarative `ListenableBuilder` in `build()` (same split as `subtitle` above):
    // `precacheImage` needs a stable, mounted `BuildContext` and MUST NOT run as a
    // side effect of `build()` itself. Runs once immediately too, so products already
    // present at the first build (no notify needed) still get prefetched.
    widget.template?.productOverlay.addListener(_onProductOverlayChanged);
    _maybePrefetchProductImages();
  }

  void _onSubtitleStateChanged() => _maybeFetchSubtitleCues();

  void _onProductOverlayChanged() => _maybePrefetchProductImages();

  /// Background-prefetch every product-image URL in the FULL (unfiltered) product
  /// list (`_model.allProducts`) into Flutter's own `ImageCache` via
  /// [_precacheProductImage] (rb-flutter-product-image-loading-polish, design.md
  /// Decisions 1/2/4), so by the time a product's own `[beginTime,endTime)` /
  /// `narrate_status==2` window opens and the now-introducing carousel actually mounts
  /// its `Image.network`, the image is already decoded — no placeholder flash.
  /// `widget.live == false` (demo / golden) is a NO-OP — no network, matching every
  /// other `live`-gated real-image path in this package (byte-stable baselines).
  /// Skips URLs already in [_prefetchedProductImageUrls] so a repeat notify for an
  /// unchanged list schedules nothing new.
  void _maybePrefetchProductImages() {
    if (!widget.live) return;
    final urls = productImageUrlsToPrefetch(_model.allProducts)
        .where((url) => !_prefetchedProductImageUrls.contains(url))
        .toList();
    if (urls.isEmpty) return;
    _prefetchedProductImageUrls.addAll(urls);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final url in urls) {
        _precacheProductImage(url, context);
      }
    });
  }

  /// TEST SEAM indirection — [productImagePrecacheForTesting] (null in production) →
  /// [defaultProductImagePrecache] (the real `precacheImage`). Kept as a tiny getter
  /// so [_maybePrefetchProductImages] reads a single call site.
  Future<void> Function(String url, BuildContext context) get _precacheProductImage =>
      productImagePrecacheForTesting ?? defaultProductImagePrecache;

  /// Re-check `widget.template?.subtitle.url` against [_lastFetchedSubtitleUrl]
  /// ([shouldRefetchSubtitleCues]) and, when it genuinely changed, fetch + parse the new URL (or
  /// clear [_subtitleCues] when the new url is blank). Marks [_lastFetchedSubtitleUrl] BEFORE the
  /// async fetch starts (parity Android `refreshSubtitleCuesIfChannelChanged`) so a repeated
  /// notification for the SAME still-in-flight url doesn't spawn a duplicate concurrent fetch.
  /// Never called synchronously from `build()` — `setState` inside a build pass is illegal;
  /// this only runs from [initState] / [didUpdateWidget] / the [_onSubtitleStateChanged] listener.
  void _maybeFetchSubtitleCues() {
    final url = widget.template?.subtitle.url ?? '';
    if (!shouldRefetchSubtitleCues(url: url, lastFetchedUrl: _lastFetchedSubtitleUrl)) return;
    _lastFetchedSubtitleUrl = url;
    if (url.isEmpty) {
      if (_subtitleCues.isNotEmpty) setState(() => _subtitleCues = const []);
      return;
    }
    fetchAndParseSubtitleCues(
      url: subtitleVttUrl(url),
      fetcher: widget.subtitleVttFetcherForTesting ?? defaultSubtitleVttFetcher,
    ).then((cues) {
      if (!mounted) return;
      // Stale-fetch guard (design.md Decision 4): only apply when the template's CURRENT url is
      // still the one this fetch was for — a belated fetch for a video the viewer already
      // switched away from MUST NOT clobber the newer state.
      if (widget.template?.subtitle.url != url) return;
      setState(() => _subtitleCues = cues);
    });
  }

  @override
  void dispose() {
    widget.template?.subtitle.removeListener(_onSubtitleStateChanged);
    widget.template?.productOverlay.removeListener(_onProductOverlayChanged);
    _scrubCollapseTimer?.cancel();
    // rb-flutter-gesture-clean-mode-v2 — cancel any pending deferred-clean-mode-toggle / 2x-speed
    // tick timers so a fired callback never touches this unmounted state.
    _pendingCleanModeToggleTimer?.cancel();
    _speedModeTickTimer?.cancel();
    // rb-flutter-live-like-burst-restyle — cancel the pending liked→false revert timer so a
    // fired callback never touches this unmounted state.
    _likeLikedTimer?.cancel();
    // rb-flutter-chat-reveal-sheet-dismiss-timing — cancel any pending deferred close-bubble
    // timers so a fired callback never touches this unmounted state.
    _infoPanelDismissTimer?.cancel();
    _moreMenuDismissTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PlayerShellView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.template != widget.template) {
      oldWidget.template?.subtitle.removeListener(_onSubtitleStateChanged);
      widget.template?.subtitle.addListener(_onSubtitleStateChanged);
      _model = PlayerShellModel(template: widget.template);
      _subtitleCues = const [];
      _lastFetchedSubtitleUrl = null;
      _maybeFetchSubtitleCues();
      // rb-flutter-product-image-loading-polish — re-wire the productOverlay listener
      // to the NEW template reference (mirrors the subtitle re-wiring immediately
      // above) and forget URLs prefetched under the OLD template, then re-check the
      // new one's already-known products.
      oldWidget.template?.productOverlay.removeListener(_onProductOverlayChanged);
      widget.template?.productOverlay.addListener(_onProductOverlayChanged);
      _prefetchedProductImageUrls.clear();
      _maybePrefetchProductImages();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.template;

    // Bind the relevant template ChangeNotifiers so a change re-reads the model.
    // With no live template (demo seeds) there is nothing to listen to — render
    // the seeds directly.
    final mergeable = <Listenable>[
      if (t != null) ...[
        t.header,
        t.operationRail,
        t.infoTab,
        t.noticeTab,
        t.productOverlay,
        t.playbackProgress,
        // restriction-mask ② — `isRestricted` 變更（VIDEO_OPEN）→ 重建疊遮罩。
        t.restriction,
        // rb-flutter-subtitle-vtt-caption-display — `subtitle.enabled` 變更（CC 開關）需要重繪；
        // `subtitle.url` 變更（換片）的 FETCH 側效果由獨立的 `addListener` 驅動（見上方 initState /
        // didUpdateWidget / dispose），這裡只負責重繪語意。
        t.subtitle,
        // fix-flutter-endscreen-close-button-blocked — `endScreen` 變更（進出
        // `endScreenShown` / 倒數 tick）需要重繪，讓 header 右上角鈕的強制關閉覆寫
        // （`PlayerShellModel.isEndScreenActive` → `resolveHeaderCloseButton`）與
        // 結束畫面的顯示/隱藏同步，而不是等其他被合併的 listener 剛好一起觸發重建。
        t.endScreen,
      ],
    ];

    Widget content = _buildContent(context);
    if (mergeable.isNotEmpty) {
      content = ListenableBuilder(
        listenable: Listenable.merge(mergeable),
        builder: (context, _) => _buildContent(context),
      );
    }
    // INERT E2E key on the player-shell build root (KeyedSubtree → no RenderObject,
    // golden byte-identical).
    return KeyedSubtree(key: LbTestKeys.playerShell, child: content);
  }

  Widget _buildContent(BuildContext context) {
    final theme = widget.theme;
    final m = _model;

    // rb-flutter-player-shell-bottom-chrome-safearea: shared by the 4 bottom-pinned chrome call
    // sites this change closes (clean-mode exit button / floating bag / VOD side rail / LIVE
    // bottom bar, both branches) — a single read, reused below and threaded into `_buildUpcoming`
    // (a plain method, not a widget, so it cannot read `MediaQuery` itself). The pre-existing
    // `PlaybackProgressBarView` slot (`rb-flutter-player-shell-bottom-safearea`) keeps its OWN
    // separate inline `MediaQuery.of(context).padding.bottom` read further below — deliberately
    // not unified with this local, see design.md Decision 4.
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;

    // UPCOMING (直播預告 awaitingLive) wears the design's LIVE chrome instead of the
    // LIVE / VOD chrome. Priority upcoming > live > vod — early-return so the
    // live / vod composition below is never reached for upcoming. Background is the
    // UpcomingCountdownView (cover + dark mask + date + big time, promoted from a
    // top-most moment to the shell background); chrome = header (LIVE pill / viewer
    // already hidden since isLive == false) + the SLIM LIVE bottom bar. NO VOD side
    // rail / floating bag / mini-cart / LiveOverlayChrome / info panel. Flutter
    // parity of iOS PlayerShellView's upcoming branch / Android UpcomingScaffold.
    if (m.isUpcoming) return _buildUpcoming(theme, m, safeAreaBottom);

    // rb-flutter-vod-playback-progress-bar display gate — `isMain` reuses the SAME expression
    // that already gates the VOD side rail / floating bag / now-introducing carousel (not
    // upcoming here — that already early-returned above — but kept as an explicit argument for
    // 1:1 fidelity with the design formula, see `showsPlaybackProgressBar`'s doc comment).
    final isMainPlaybackPhase = !m.introPlaying &&
        m.startPhase != LBPStartPhase.loading &&
        m.startPhase != LBPStartPhase.splash;
    final showsProgressBar = showsPlaybackProgressBar(
      isMain: isMainPlaybackPhase,
      isUpcoming: m.isUpcoming,
      isLive: m.isLive,
      isReplay: m.isFinishedLiveReplay,
    );

    // rb-flutter-player-shell-bottom-safearea: shared by BOTH the progress-bar slot's `bottom`
    // inset (`progressBarBottomSafeAreaInset`) and `PlaybackProgressBarView.scrubBarExpanded`
    // below — declared once here so the two call sites can never drift out of sync.
    final progressBarExpanded = _scrubBarExpanded || _cleanMode;

    // rb-flutter-live-now-pill display gate — reuses the SAME `isMainPlaybackPhase` local as
    // `showsProgressBar` above (see `showsLiveNowPill`'s doc comment for why an independent
    // `isLive` exclusion is still required on top of it).
    final showsLiveNowPillNow = showsLiveNowPill(
      hasLiveNow: widget.hasLiveNow,
      isMain: isMainPlaybackPhase,
      isUpcoming: m.isUpcoming,
      isLive: m.isLive,
      isFinishedLiveReplay: m.isFinishedLiveReplay,
      cleanMode: _cleanMode,
      isScrubbing: _isScrubbing,
    );

    // live-chrome 家族 — 真直播（`isLive`）或已結束直播回放（`isFinishedLiveReplay`）。兩者套用
    // 相同的 LIVE 版型（LIVE 疊層 chrome + LIVE 底部 bar + 聊天 feed）；純 VOD 點播（兩旗標皆
    // false）走 VOD 版型（side rail + 浮動袋 + now-introducing 輪播）。回放版型對齊直播當下
    // （rb-flutter-replay-live-chrome-parity，parity iOS `PlayerShellView.usesLiveChrome` /
    // Android `usesLiveChrome`）。純 VOD（兩旗標皆 false）與純 LIVE（`isLive == true`,
    // `isFinishedLiveReplay == false`，兩者互斥）下 `usesLiveChrome` 與先前窄義 `m.isLive` 逐位元
    // 相等 — 這是本 change 對既有純 VOD / 純 LIVE golden 零回歸的數學基礎。
    final usesLiveChrome = m.isLive || m.isFinishedLiveReplay;

    // fix-flutter-endscreen-close-button-blocked: while the family-4 end screen is
    // showing, the header's top-right button is forced to "direct close" (user
    // decision), overriding the global showCloseIcon/onMinimize at the
    // `PlayerHeaderBarView` call site below. See `resolveHeaderCloseButton`'s own
    // doc comment; the SAME computation is repeated verbatim in `_buildUpcoming`
    // below (that method has no closure over this local).
    final headerCloseButton = resolveHeaderCloseButton(
      endScreenActive: m.isEndScreenActive,
      showCloseIcon: widget.showCloseIcon,
      onMinimize: widget.onMinimize,
      onCloseRequest: widget.onCloseRequest,
    );

    return Stack(
      children: [
        // Themed background placeholder painted ONLY in demo/golden (`live == false`). In host
        // runtime (`live == true`) the real `LivebuyPlayerCore` surface sits BEHIND this overlay
        // (the container's Stack puts the native view at the bottom), so painting an opaque
        // `theme.background` here would cover the playing video — gate it off so the video shows
        // through (rb-flutter-player-shell-live-video-passthrough; parity iOS
        // `paintsBackgroundPlaceholder` / Android `!live` / RN). Golden uses `live == false`
        // (default) → the placeholder is still painted → baselines unchanged.
        if (!widget.live)
          Positioned.fill(child: ColoredBox(color: theme.background)),

        // Tap over the video area — dispatched by `_handleVideoTap` (rb-flutter-gesture-clean-
        // mode-v2, design R29, SUPERSEDES the retired `tapTogglesPlayPause`/`allowsDoubleTapLike`
        // dispatch): every short tap toggles `_cleanMode`, immediately when NOT `isSeekable`
        // (a real live broadcast, or its upcoming preview), deferred by `kDoubleTapSeekWindowMs`
        // when it IS seekable (VOD / finished-live replay) — see `_handleVideoTap` /
        // `_handleSeekableTap`'s own doc comments. A `LayoutBuilder` wraps this detector to
        // capture the video area's laid-out width into `_videoAreaWidth`, feeding `tapZone`'s
        // left/right-half classification for the seekable branch's double-tap-seek judgment. The
        // callback switched from `onTap` to `onTapUp` so it can read `TapUpDetails.localPosition`
        // — a transparent, full-bleed tap target placed BELOW the chrome so header / rail /
        // info-panel / pinned-card taps win. Transparent → golden baselines unchanged; a no-op
        // host callback makes it inert.
        //
        // Long-press on the SAME detector now drives the 2x-speed hold (`_handleLongPressStart`,
        // seekable-only — a genuinely-live broadcast is a STRUCTURAL no-op, see that method's own
        // doc comment) instead of R23's `_cleanMode` toggle. The framework's own gesture arena
        // (`LongPressGestureRecognizer`, `GestureDetector.onLongPressStart`) still arbitrates it
        // against the vertical-drag and tap recognizers below EXACTLY as before — kept
        // unconditionally wired (not nulled out for the non-seekable branch) so a genuine
        // long-press still never ALSO dispatches `onTapUp` on release, no hand-rolled `Timer` /
        // state machine needed for that part.
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _videoAreaWidth = constraints.maxWidth;
              return GestureDetector(
                key: LbTestKeys.playerVideoSurface,
                behavior: HitTestBehavior.translucent,
                onTapUp: (details) => _handleVideoTap(details.localPosition.dx),
                onLongPressStart: _handleLongPressStart,
                onLongPressEnd: (_) => _stopSpeedMode(),
                onLongPressCancel: _stopSpeedMode,
                // Vertical-swipe → adjacent-video navigation (rb-player-shell-swipe).
                // The SAME detector keeps the tap dispatch above and the vertical drag —
                // Flutter's gesture arena routes a pure tap to onTapUp and a committed
                // vertical drag to the drag callbacks (parity to iOS .simultaneousGesture).
                // Accumulate dy and decide on end: swipe-UP → next, swipe-DOWN → prev.
                onVerticalDragStart: (_) => _swipeDy = 0,
                onVerticalDragUpdate: (details) => _swipeDy += details.delta.dy,
                onVerticalDragEnd: (_) => _handleSwipeEnded(_swipeDy),
              );
            },
          ),
        ),

        // Surface 4 — now-introducing surface. live-chrome 家族（真直播 OR 已結束直播回放，
        // usesLiveChrome） → the full-bleed LiveOverlayChromeView (announce / pinned card /
        // host caption / gesture hints). 純 VOD → the now-introducing carousel (below) instead.
        // intro 片頭 (introPlaying) → neither (the opening MP4 is not yet live). Parity
        // iOS/Android: usesLiveChrome → LiveOverlayChromeView, VOD → NowIntroducingCarousel
        // (mutually exclusive branches, rb-flutter-replay-live-chrome-parity — was narrow
        // `m.isLive`, now the two-flag union so an already-finished live replay also wears the
        // LIVE overlay chrome instead of being misrouted into the VOD branch below).
        if (usesLiveChrome)
          Positioned.fill(
            child: LiveOverlayChromeView(
              theme: theme,
              // 乾淨模式（rb-flutter-gesture-clean-mode-rewrite）：重用既有「空字串 → 不畫該
              // banner」渲染閘 + 既有 showGestureHints 參數，widget 本體不動（design.md D4）。
              // fix-flutter-scrub-hide-announce-chat-pinned：拖曳播放進度條期間（_isScrubbing）
              // 額外隱藏，parity iOS `isScrubbing ? "" : model.announceText` / Android
              // `if (isScrubbing) "" else announce`——讓出畫面給 transport bar，跟既有的
              // 「放開手指後 lift」（_scrubBarExpanded && !_isScrubbing，見下方 bottomInset）是兩件
              //獨立的事、彼此不衝突：拖曳中先隱藏，放開後才重新出現並上移。
              announceText: (_cleanMode || _isScrubbing) ? '' : m.announceText,
              // host config（widget.showGestureHints，parity iOS `showGestureHints &&
              // !cleanMode`）與乾淨模式疊加：兩者皆須成立手勢提示才顯示
              // （rb-flutter-gesture-hint-plumb，取代先前只看 !_cleanMode、完全無視 host
              // config 的舊寫法）。
              showGestureHints: widget.showGestureHints && !_cleanMode,
              // 釘選卡來源依窄義 m.isLive 分流（rb-flutter-replay-live-chrome-parity，parity iOS）：
              //   真直播（m.isLive） → livePinnedProducts（多件 narrate_status==2 輪播 + 分頁點；
              //     空時 fallback 單一 pinnedProduct 一元清單，問題 7,
              //     rb-flutter-live-now-introducing-carousel）。
              //   已結束直播回放（!m.isLive，此時 usesLiveChrome 已保證 isFinishedLiveReplay）→
              //     vodActiveProducts（時間軸窗格 [beginTime,endTime) 含 playhead，與 VOD
              //     now-introducing 輪播同一資料源；回放無即時 narrate_status==2，改用後端介紹
              //     時間窗）。
              // 再依本地已關閉的釘選商品 id 過濾（rb-flutter-live-pinned-card-dismiss，鏡像 VOD 的
              // _dismissedVodProductIds 過濾；_dismissedLivePinnedIds 預設空 → 原樣、golden 不變），
              // 同一個 dismiss set 涵蓋兩個來源分支。fix-flutter-scrub-hide-announce-chat-pinned：
              // 拖曳期間改回傳空清單（parity iOS `isScrubbing ? [] : ...` / Android
              // `if (isScrubbing) emptyList() else ...`），理由同上方 announceText。
              pinnedProducts: _isScrubbing
                  ? const []
                  : visiblePinnedProducts(
                      m.isLive ? m.livePinnedProducts : m.vodActiveProducts,
                      _dismissedLivePinnedIds),
              // live-pinned-card-image-radius: load the real product photo only over a
              // live video surface (false / demo → placeholder, golden byte-stable).
              live: widget.live,
              // autoFadeGestureHints-gesture-hint-fade: 手勢提示出現 3.5 秒後自動淡出，僅在真實內容
              // （非 demo / snapshot 佔位）時啟用。驅動值同源同值 widget.live（**不是** m.isLive —
              // 兩者語意不同，parity Android `PlayerShellView.kt` 的 `autoFadeGestureHints = live`）。
              autoFadeGestureHints: widget.live,
              // 真直播 vs 已結束直播回放的視覺子分流（rb-flutter-replay-live-chrome-parity，parity
              // iOS `LiveOverlayChromeView.isLive`）：釘選卡「介紹中」徽章判斷（isLive==false 時一律
              // 視為介紹中）與長按 2 倍速快轉手勢提示（僅 isLive==false 時顯示，見
              // `_handleLongPressStart` / `isSeekable` — 回放 isSeekable 恆為 true，真直播恆為
              // false）皆依此分流，預設 true 保證省略時既有呼叫端 byte-identical。
              isLive: m.isLive,
              onTapPinnedProduct: widget.onTapPinnedProduct,
              // 釘選卡右上角 X → 逐商品本地隱藏（rb-flutter-live-pinned-card-dismiss，鏡像 VOD 的
              // onDismiss → _dismissedVodProductIds.add）。close chip 的巢狀 GestureDetector 消費點擊、
              // 不冒泡到卡身 onTapPinnedProduct（開明細），parity iOS/Android/RN。
              onDismissPinnedProduct: (id) =>
                  setState(() => _dismissedLivePinnedIds.add(id)),
              // 公告橫幅 tap → 切到 VideoInfoPanel 公告分頁並開啟資訊面板（重用 host pill tap 的同一
              // _infoPanelOpen 狀態）。公告顯示中 ⇒ noticeCanOpen ⇒ selectInfoTab(notice) 生效
              // (live-announce-tap-open-info-panel，parity iOS)。
              onTapAnnounce: () {
                m.selectInfoTab(LBInfoPanelTab.notice);
                _setInfoPanel(true);
              },
              // 放開手指到 2.8 秒收回這段期間（_scrubBarExpanded && !_isScrubbing），釘選卡 / 公告
              // banner 重新出現時上移，讓出底部 transport bar 空間（rb-flutter-scrub-expanded-
              // chrome-lift，parity iOS/Android — 與這個 build 其他既有 `_scrubBarExpanded ?
              // _scrubChromeLift : 0.0` 用法同一慣例）。預設 0 對既有呼叫點無影響。
              // safeAreaBottom 項無條件疊加、不受 scrub 狀態影響（fix-flutter-player-shell-bottom-
              // safearea-gaps，補齊系統底部安全區——比照 liveBottomBarBottomInset 等既有慣例）。
              bottomInset: safeAreaBottom +
                  ((_scrubBarExpanded && !_isScrubbing) ? _scrubChromeLift : 0.0),
            ),
          )
        else if (!m.introPlaying)
          // VOD-main now-introducing carousel — real image (live) + full width + page dots over
          // ALL products whose [beginTime,endTime) window contains the playhead
          // (`m.vodActiveProducts`), minus locally dismissed. Anchored bottom-leading; trailing
          // inset clears the bottom-anchored side rail (rb-flutter-now-introducing，問題 9/10/1).
          ..._buildNowIntroducing(m, theme, safeAreaBottom),

        // VOD closed-caption line (rb-flutter-subtitle-vtt-caption-display). Independent Stack
        // sibling of the now-introducing carousel above, bottom-centered, lifted the same
        // `_scrubChromeLift` amount while released-but-still-held (rb-flutter-vod-playback
        // -progress-bar precedent). `effectiveCaption` is resolved HERE (not cached in state) —
        // it is a cheap synchronous lookup over `_subtitleCues`, recomputed every rebuild from
        // the current `m.playbackPosition`, parity iOS/Android `activeCue(cues, at: position)`.
        //
        // rb-flutter-replay-caption-overlay-fix: this call site MUST feed the narrow `m.isLive`,
        // NOT `usesLiveChrome` (= m.isLive || m.isFinishedLiveReplay). VTT/CC captions and "does
        // this state wear LIVE chrome" are independent concerns — an already-finished live
        // replay is still, mechanically, playing back a recorded file (like VOD), so it deserves
        // captions same as VOD even though it also wears the LIVE bottom bar / overlay chrome.
        // `rb-flutter-subtitle-vtt-caption-display` (archived 2026-08-31) deliberately chose
        // `m.isLive` here (design.md Decision 2) and its own Risks/Trade-offs explicitly
        // predicted a future `usesLiveChrome` unification would make captions follow it.
        // `rb-flutter-replay-live-chrome-parity` (archived 2026-09-06) was exactly that
        // predicted unification: it retargeted this call site to `usesLiveChrome` along with the
        // genuinely-LIVE-chrome-related ones (side rail / floating bag / now-introducing
        // carousel / LiveOverlayChromeView / LiveBottomBarView / merged chat feed) as an
        // explicit, itemized goal of that change (its own proposal.md/design.md list this call
        // site by name) — not an accidental sweep. `rb-flutter-replay-caption-overlay-fix`
        // (2026-09-09) deliberately REVERSES that unification for captions only, per a user
        // report + a four-platform sibling product decision — a new product decision, not a
        // regression fix. As a result the caption gate no longer shares a branch with
        // `_buildNowIntroducing` (`!usesLiveChrome`) — they diverge exactly when
        // `isFinishedLiveReplay == true` (caption shows, carousel doesn't).
        //
        // `safeAreaBottom` (rb-flutter-caption-overlay-bottom-bar-clearance-fix): threaded through
        // so the vertical `bottom` position can correctly clear `LiveBottomBarView` in the
        // `isFinishedLiveReplay` branch — same local this `_buildContent` scope already computes
        // and feeds to every other bottom-pinned chrome element's own inset function.
        ..._buildSubtitleCaption(m, theme, m.isLive, safeAreaBottom),

        // Surfaces 1 + 2 — top bar pinned top, side rail pinned trailing.
        Column(
          children: [
            // rb-flutter-player-header-safearea: the header MUST avoid the system top
            // safe-area (status bar / notch / Dynamic Island) — Flutter has no implicit
            // safe-area inheritance the way SwiftUI does, so without this the header
            // painted from `top: 0` and collided with the system status bar on devices
            // with a real inset. `bottom: false` — only the TOP inset is relevant here;
            // this Column's other content (the VOD side rail Row below) must not be
            // affected. `PlayerHeaderBarView` itself is NOT modified — the wrap lives
            // ONLY at this call site. See the SAME wrap in `_buildUpcoming` below; both
            // MUST stay identical.
            SafeArea(
              bottom: false,
              child: PlayerHeaderBarView(
                theme: theme,
                title: m.title,
                hostName: m.hostName,
                shopLogo: m.shopLogo,
                viewerCount: m.viewerCount,
                isSubscribed: m.isSubscribed,
                // live-chrome 家族（真直播 OR 已結束直播回放）皆餵 isLive: usesLiveChrome → header
                // 畫 viewer-count（回放套 LIVE 版型，rb-flutter-replay-live-chrome-parity，parity
                // iOS/Android). LIVE pill ⟺ isLive && !isReplay; viewer count ⟺ isLive
                // (usesLiveChrome). 兩種回放皆隱 LIVE 膠囊：behind-edge replay（m.isReplay，鏡像
                // playbackProgress.isReplay）與 finished-live replay（m.isFinishedLiveReplay，已結束
                // 直播）——後者非正在直播，顯紅 LIVE 會誤導，但兩者都保留 viewer-count（design
                // `hideLivePill = isReplay`，這裡的 isReplay 引數把兩種回放都併進去）。
                isLive: usesLiveChrome,
                isReplay: m.isReplay || m.isFinishedLiveReplay,
                live: widget.live,
                // fix-flutter-endscreen-close-button-blocked: forced to onCloseRequest
                // while the end screen is active — see resolveHeaderCloseButton above.
                onMinimize: headerCloseButton.onMinimize,
                onToggleSubscribe: widget.onToggleSubscribe,
                showSubscribe: widget.showSubscribe,
                // PlayerHeader 觀看人數徽章顯示/隱藏（rb-flutter-viewer-count-visibility-toggle，
                // parity iOS/Android showViewerCount）。The sibling `_buildUpcoming` header below
                // MUST forward the same value (see this field's own doc comment).
                showViewerCount: widget.showViewerCount,
                // Merchant title-marquee gate, raw pass-through (rb-flutter-marquee-title-scroll).
                // The sibling `_buildUpcoming` header below MUST forward the same value.
                titleScroll: widget.titleScroll,
                // host pill tap → toggle the info panel (parity iOS onTapHostBadge — the only
                // opener now that the rail no longer carries a `more` pill).
                onTapHostBadge: () => _setInfoPanel(!_infoPanelOpen),
                // 乾淨模式（rb-flutter-gesture-clean-mode-rewrite）：隱藏 host pill、保留 minimize 鈕
                // 原位（design.md D3）。upcoming 分支（下方 `_buildUpcoming`）維持不傳（預設 false）——
                // `_cleanMode` 在該分支結構上不可達。
                hideHostPill: _cleanMode,
                // 右上角按鈕圖示 minimize ↔ close（rb-flutter-player-direct-close-button），純呈現
                // by-value 旗標轉發，比照 titleScroll / showSubscribe 的既有轉發慣例。
                // fix-flutter-endscreen-close-button-blocked: forced true while the end
                // screen is active — see resolveHeaderCloseButton above.
                showCloseIcon: headerCloseButton.showCloseIcon,
                // 乾淨模式限定靜音鈕（rb-flutter-gesture-clean-mode-v2）：補回單擊切靜音手勢退役後
                // 的操作管道，沿用既有 `widget.onToggleMute` host-wired seam，只是觸發手勢從「影片
                // 區單擊」改成「點頂列這顆鈕」。`_cleanMode == false` 時 `onToggleMute` 傳 null →
                // 鈕不渲染、不佔位，既有非乾淨模式 baseline byte-identical。
                muted: m.muted,
                onToggleMute: _cleanMode ? widget.onToggleMute : null,
              ),
            ),
            const Spacer(),
            // Side rail is purely-VOD-ONLY chrome (design screens.jsx gates `LBPSideRail`
            // on `!isLive`, extended here to `!usesLiveChrome` — rb-flutter-replay-live-chrome-
            // parity). In live-chrome family (真直播 OR 已結束直播回放) the bottom bar (below)
            // replaces it — the two are mutually exclusive by mode. Suppressed only during the
            // intro 片頭 (introPlaying) and the VOD OPENING sequence (`startPhase`
            // loading/splash) — design `showMainChrome` hides VOD chrome there; from `buffering`
            // onward the rail shows (no-intro VOD: channel loaded, rail enablement set, header
            // filled), so it appears alongside the header instead of waiting for the first frame
            // (`done`). Header is kept throughout (rb-flutter-vod-rail-show-on-buffering,
            // parity to iOS rb-ios-vod-rail-show-on-buffering).
            if (!usesLiveChrome && !m.introPlaying && m.startPhase != LBPStartPhase.loading && m.startPhase != LBPStartPhase.splash && !_isScrubbing && !_cleanMode)
              Row(
                children: [
                  const Spacer(),
                  // Rail anchored bottom 68 (rb-flutter-gesture-clean-mode-v2, design LBPSideRail
                  // R29 — was 80, moved down 12 to follow the floating bag's own R29 shrink, see
                  // the `FloatingBagButton` size constants in `operation_rail.dart`) so the
                  // SEPARATE floating bag (bottom 16) sits below it next to the mini-cart strip.
                  // Lifted an extra _scrubChromeLift while released-but-still-held
                  // (rb-flutter-vod-playback-progress-bar) so it clears the still-expanded
                  // transport bar.
                  Padding(
                    padding: EdgeInsets.only(
                        right: 12,
                        // rb-flutter-player-shell-bottom-chrome-safearea: clears the system
                        // bottom safe area on top of the existing `_scrubBarExpanded` lift.
                        bottom: vodSideRailBottomInset(safeAreaBottom,
                            lift: _scrubBarExpanded ? _scrubChromeLift : 0.0)),
                    child: OperationRailView(
                      theme: theme,
                      items: m.railItems,
                      bagCount: m.bagCount,
                      heartBurstTick: m.heartBurstTick,
                      muted: m.muted,
                      subtitleEnabled: m.subtitleEnabled,
                      onTapItem: _handleRailTap,
                      // rb-flutter-replay-live-chrome-parity: this rail's `isFinishedLiveReplay`
                      // / `onTapMore` collapsed-more-pill capability is now component-level ONLY
                      // (see `OperationRailView`'s own doc comment) — this call site MUST NOT
                      // feed it anymore, because the `!usesLiveChrome` gate above guarantees
                      // `m.isFinishedLiveReplay == false` whenever this block actually renders
                      // (usesLiveChrome = isLive || isFinishedLiveReplay). The real「更多」entry
                      // for a closed-chat finished replay is now `LiveBottomBarView.onMore`
                      // (see its call site below).
                    ),
                  ),
                ],
              ),
          ],
        ),

        // Floating shopping bag (design LBPBagButton, iOS FloatingBagButtonView): a SEPARATE
        // affordance from the side rail, anchored low (bottom 16) — distinct from the rail
        // (bottom 68, rb-flutter-gesture-clean-mode-v2 — was 80). Purely-VOD-main chrome only
        // (rb-flutter-replay-live-chrome-parity: `!usesLiveChrome`, was `!m.isLive`). Tap →
        // open the product list (_handleRailTap(goods)).
        if (!usesLiveChrome && !m.introPlaying && m.startPhase != LBPStartPhase.loading && m.startPhase != LBPStartPhase.splash && !_isScrubbing && !_cleanMode)
          Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: EdgeInsets.only(
                  right: 12,
                  // rb-flutter-player-shell-bottom-chrome-safearea: clears the system bottom
                  // safe area on top of the existing `_scrubBarExpanded` lift.
                  bottom: floatingBagButtonBottomInset(safeAreaBottom,
                      lift: _scrubBarExpanded ? _scrubChromeLift : 0.0)),
              child: FloatingBagButton(
                theme: theme,
                bagCount: m.bagCount,
                onTap: () => _handleRailTap(LBSideRailKind.goods),
              ),
            ),
          ),

        // 「退出乾淨模式」小圓鈕（rb-flutter-gesture-clean-mode-v2，位置對齊設計稿由
        // rb-flutter-clean-mode-exit-icon-fix 補齊）：`_cleanMode == true` 時可見，點擊即退出。
        // `left: 14` 兩側共用，對齊 `design/templates/minimal/screens.jsx` VOD/LIVE 兩分支皆用的
        // 同一水平位移。`bottom` 依 `m.isLive` 分流：VOD/回放（`!m.isLive`）base `52`（設計稿
        // `16 + 36`，疊在 transport 列展開態上方，清開展開態進度條的高度）；LIVE（`m.isLive`）
        // base `16`（設計稿本就是這個值，不變）。兩者共用同一顆 widget / 同一個
        // `LbTestKeys.cleanModeExitButton`（`m.isLive` 互斥，永遠只有一顆存在於渲染子樹）。
        // rb-flutter-player-shell-bottom-chrome-safearea 起，base 值之上疊加 `safeAreaBottom`
        // （取代先前「這裡刻意不新增 safe-area」的舊決策——見本 change design.md）。
        if (_cleanMode)
          Positioned(
            left: 14,
            bottom: cleanModeExitButtonBottomInset(safeAreaBottom, isLive: m.isLive),
            child: _CleanModeExitButton(onTap: () => setState(() => _cleanMode = false)),
          ),

        // LIVE bottom bar — surfaces the design's `LBLiveBottomBar` at the bottom in the
        // live-chrome family (真直播 OR 已結束直播回放, usesLiveChrome) OR the intro 片頭
        // (introPlaying) (純 VOD uses the side rail above instead). introPlaying → the BAG-ONLY
        // variant (just the bag). Pinned bottom, over the live overlay chrome and below the
        // info-panel modal. bag / share / like / nickname / CC route through the existing
        // `onTapRailItem` host wiring by kind; 留言 raises the dedicated `onComment` intent.
        // Hidden while the opaque 留言 composer is up (composerPresented) so the two do not
        // overlap (parity iOS hide-bottom-bar).
        // `!_cleanMode` scope is narrowed to ONLY the `usesLiveChrome` branch (rb-flutter-intro-
        // cleanmode-bottombar-fix, parity iOS `usesLiveChrome && !cleanMode` —
        // rb-flutter-replay-live-chrome-parity lands the target formula, was narrow `m.isLive`):
        // `_cleanMode` does NOT auto-reset across an in-place video switch, so a viewer who
        // entered clean mode on the PREVIOUS video would otherwise lose this bar entirely on the
        // NEXT video's intro preroll (nothing left but the skip-intro button) — clean mode's
        // intent is to hide the "live-chrome family in progress" chrome, not the opening-MP4
        // chrome.
        // `&& !_isScrubbing` (rb-flutter-replay-live-chrome-parity, parity iOS's own
        // `!isScrubbing` gate on this same bar): unifying `usesLiveChrome` means an already-
        // finished-live replay now simultaneously qualifies for BOTH this bar AND the VOD-style
        // `PlaybackProgressBarView` (`showsPlaybackProgressBar`'s `!isLive` term is unaffected by
        // this change and stays true for a finished replay) — a combination that could not occur
        // before this change (a genuinely-live broadcast never shows the progress bar). Without
        // this guard, dragging the replay's progress bar would leave this bar visibly overlapping
        // the expanded transport bar. Reuses the SAME `_scrubBarExpanded` / `_scrubChromeLift`
        // released-but-still-held lift the VOD side rail / floating bag / now-introducing
        // carousel already apply — no new mechanism.
        if (((usesLiveChrome && !_cleanMode) || m.introPlaying) && !widget.composerPresented && !_isScrubbing)
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              // rb-flutter-player-shell-bottom-chrome-safearea: clears the system bottom safe
              // area on top of the existing `_scrubBarExpanded` lift.
              padding: EdgeInsets.only(
                  bottom: liveBottomBarBottomInset(safeAreaBottom,
                      lift: _scrubBarExpanded ? _scrubChromeLift : 0.0)),
              child: LiveBottomBarView(
                theme: theme,
                bagCount: m.bagCount,
                isReplay: m.isReplay,
                bagOnly: m.introPlaying,
                // 已結束直播回放的獨立變體（rb-flutter-replay-live-chrome-parity，parity iOS
                // `chatClosed`）：留言區改 disabled「聊天室已關閉」、暱稱鈕換「更多」、分享鈕位置換
                // CC 切換。`isUpcoming`/`bagOnly` 優先序高於此旗標（widget 內部已處理）。
                isFinishedLiveReplay: m.isFinishedLiveReplay,
                // 讚鈕亮色狀態（rb-flutter-live-like-burst-restyle，design R37）。
                liked: _liveLiked,
                // CC 切換按鈕 active 填色態（rb-flutter-live-bottom-bar-cc-icon-active-fill-state）——
                // 與 VOD 側欄 CC pill / SubtitleOverlay 共用同一個既有 getter。
                subtitleEnabled: m.subtitleEnabled,
                // CC 是否有字幕來源可用（R42，rb-flutter-cc-icon-availability-redesign）——與 VOD
                // 側欄 `OperationRailView` 內部由 `items` 衍生的同一個 `m.railItems` 讀出，parity
                // `showShare` / `showContact` 已用的既有衍生慣例（見上方「更多」選單呼叫處）。
                subtitleAvailable: m.railItems.any(
                    (it) => it.kind == LBSideRailKind.subtitle && it.enabled),
                onBag: () => _handleRailTap(LBSideRailKind.goods),
                onComment: widget.onComment,
                // 暱稱鈕 → 容器本地呈現 設定暱稱 modal（onNickname；parity）；未接時退回 rail 路徑
                // （demo / standalone）。
                onNickname: widget.onNickname ??
                    () => _handleRailTap(LBSideRailKind.guestNameEdit),
                onShare: () => _handleRailTap(LBSideRailKind.share),
                // 真 like（host exit）+ 隨機 1-4 顆錯開飄心 burst + 讚鈕短暫亮色（
                // rb-flutter-live-bottom-heart-burst 起源，rb-flutter-live-like-burst-restyle 改版，
                // design R37 `likeAnimation()`）。
                onLike: () {
                  _handleRailTap(LBSideRailKind.like);
                  _triggerLiveLikeBurst();
                },
                onToggleCC: () => _handleRailTap(LBSideRailKind.subtitle),
                // 「更多」(⋯) → 開啟既有「更多」選單 sheet（rb-flutter-replay-live-chrome-parity）：
                // 觸發來源從側欄的 onTapMore 搬到這裡（見上方 OperationRailView 呼叫處的說明），
                // 重用同一個 _moreMenuOpen state + BottomSheetPresenter + 選單內容，機制不變。只在
                // isFinishedLiveReplay 變體實際渲染「更多」按鈕時才可觸達。
                onMore: () => _setMoreMenuOpen(true),
              ),
            ),
          ),

        // LIVE 底部 bar 愛心 burst（rb-flutter-live-bottom-heart-burst，問題 5）：錨於底部 bar 愛心
        // （trailing-most 鈕）上方。introPlaying（bag-only，無愛心）不畫。靜止態不畫 → golden 中立。
        // 乾淨模式（rb-flutter-gesture-clean-mode-rewrite）追加 `&& !_cleanMode`。
        // `(m.isLive || m.isFinishedLiveReplay)` 數值上等於 `usesLiveChrome`（rb-flutter-replay-
        // live-chrome-parity 起）：此子句原本是 rb-flutter-live-double-tap-like-replay-extend（已
        // retired，見「Flutter player-shell LIVE 模式雙擊影片區送愛心」REMOVED Requirement）留下的
        // 歷史殘留，當時已結束直播回放走 VOD 側欄 chrome、不組出 `LiveBottomBarView`，沒有 `onLike`
        // 入口，故此子句先前恆為 no-op。本 change 讓 `LiveBottomBarView` 的 `isFinishedLiveReplay`
        // 變體保留愛心按鈕（`onLike` 現在可達），此子句從 no-op 變成真實生效——效果本身（乾淨模式下
        // 隱藏愛心 burst）未變，只是現在真的有東西可以隱藏。`&& !_isScrubbing` 追加理由同上方
        // `LiveBottomBarView` 的組裝條件（iOS 對應的 heart-burst 是巢狀在同一個 `!isScrubbing`
        // guard 內的 sibling，Flutter 這裡是平行的獨立 `if`，故需要在這裡也顯式追加，避免拖曳進度條
        // 時愛心 burst 浮在已隱藏的底部 bar 上方、失去錨點）；位置維持 `bottom: 64` 不加
        // `_scrubChromeLift`——burst 本身是瞬時動畫（觸發後自行淡出），與其餘常駐 chrome 的
        // 「放開後停留提升」語意不同，不需要跟著底部 bar 一起上移。
        if (usesLiveChrome && !_cleanMode && !_isScrubbing)
          Positioned(
            right: 18,
            bottom: 64,
            child: HeartBurst(theme: theme, tick: _liveHeartTick),
          ),

        // VOD/回放播放進度條 (rb-flutter-vod-playback-progress-bar). Independent top-level Stack
        // sibling (composed after the LIVE bottom bar / heart-burst block, before the
        // restriction mask — mirrors iOS ordering) so it can render over whichever chrome above
        // is currently composed. `showsProgressBar` already guarantees `!m.isLive` (see
        // `showsPlaybackProgressBar`'s doc comment). (fix-flutter-player-shell-bottom-safearea-
        // gaps — corrects a stale claim left behind by rb-flutter-replay-live-chrome-parity):
        // this slot DOES coexist with `LiveOverlayChromeView` during an already-finished-live-
        // replay (`usesLiveChrome = m.isLive || m.isFinishedLiveReplay` now decides that chrome
        // branch, and `showsProgressBar` covers `isReplay: m.isFinishedLiveReplay` too) — it only
        // overlays the VOD-only chrome (side rail / floating bag / now-introducing carousel) for
        // genuine pure-VOD content, which is the ONE state that never wears LIVE chrome.
        //
        // STABLE `Key` (player-gesture-feedback-overlays-flutter, kept by rb-flutter-gesture-
        // clean-mode-v2 even though that change's own two paused-overlay/mute-toast slots were
        // retired — see below): `PlaybackProgressBarView` MUST survive a mid-gesture rebuild (a
        // touch-down…touch-up pair spans at least one `setState` — `onScrubStart` — in between)
        // — its OWN internal `GestureDetector` is already keyed for exactly this reason (see this
        // widget's own file-header comment), but that only protects ITS internal subtree, not
        // THIS outer `Stack`'s reconciliation of `PlaybackProgressBarView` itself. Flutter's
        // unkeyed list-child reconciliation (`Element.updateChildren`) matches a common PREFIX
        // from the front and a common SUFFIX from the back, and only reuses a KEYED element for
        // anything left in the unmatched middle — an UNKEYED item is simply discarded and
        // recreated wherever it lands in that middle window. Other still-toggling trailing
        // siblings (`LiveNowPillView`, gated on `_isScrubbing` among other things, and the
        // contact-merchant modal further below) sit AFTER this item and can still break the
        // backward scan the same way the now-removed paused-overlay/mute-toast slots once did —
        // this `Key` is retained defensively so `PlaybackProgressBarView` stays positively
        // identifiable regardless of how many other siblings appear/disappear around it.
        if (showsProgressBar)
          Positioned(
            key: const ValueKey('lb-playback-progress-bar-slot'),
            left: 0,
            right: 0,
            // rb-flutter-player-shell-bottom-safearea: EXPANDED state lifts the slot clear of
            // the system bottom safe area (home indicator / Android gesture bar); IDLE state
            // stays flush to the physical bottom edge (`0`) regardless of the ambient safe area
            // — see the design formula in `progressBarBottomSafeAreaInset`'s doc comment. Only
            // THIS slot is affected; the other 4 bottom-pinned player-shell elements are
            // unchanged (design.md Non-Goals). `context` here is `_buildContent`'s own method
            // parameter — MediaQuery is already an ancestor by the time this executes, no nested
            // `Builder` needed.
            bottom: progressBarBottomSafeAreaInset(
              MediaQuery.of(context).padding.bottom,
              expanded: progressBarExpanded,
              isAndroid: defaultTargetPlatform == TargetPlatform.android,
            ),
            child: PlaybackProgressBarView(
              theme: theme,
              position: m.playbackPosition,
              duration: m.playbackDuration,
              isPlaying: m.isPlaybackPlaying,
              isScrubbing: _isScrubbing,
              // 乾淨模式（rb-flutter-gesture-clean-mode-rewrite）：強制展開為完整 transport 列
              // （對齊設計稿 `scrubVisible || cleanMode`）；`isScrubbing` 不受影響 —— 拖曳時長
              // 讀數只綁真實拖曳，乾淨模式強制展開時 MUST NOT 顯示讀數。
              scrubBarExpanded: progressBarExpanded,
              onTogglePlayPause: widget.onTogglePlayPause,
              // PlayerShellModel already knows the current duration — enrich the leaf's raw
              // `(seconds)` report with it before forwarding host-ward (design.md: `liveStatus`
              // deliberately omitted, this shell has no raw numeric getter for it and the
              // display gate above already guarantees non-live).
              onSeek: (seconds) =>
                  widget.onSeek?.call(seconds, duration: m.playbackDuration),
              onScrubStart: _handleScrubStart,
              onScrubEnd: _handleScrubEnd,
            ),
          ),

        // 「現正直播」右緣提示鈕 (rb-flutter-live-now-pill). Independent top-level `Align` Stack
        // sibling (parity iOS `ZStack` sibling / Android `Box(contentAlignment=CenterEnd)` / RN
        // absolute `View`): `Alignment.centerRight` naturally pins it vertically-centered to the
        // right edge, matching the design's absolute positioning without needing an extra
        // `Row`/`Spacer` wrapper. `live: widget.live` gates the pulse animation (see
        // `LiveNowPillView`'s own doc comment) — demo/golden stays static, host runtime pulses.
        if (showsLiveNowPillNow)
          Align(
            alignment: Alignment.centerRight,
            child: LiveNowPillView(
              theme: theme,
              live: widget.live,
              onTap: widget.onGoLive,
            ),
          ),

        // rb-flutter-gesture-clean-mode-v2 — the centre paused-overlay / mute-toast slots that
        // `player-gesture-feedback-overlays-flutter` composed here are RETIRED (the gestures that
        // triggered them — single-tap-to-mute with a delayed commit, and a genuinely-paused VOD/
        // replay state — no longer exist under the R29 model). `PlaybackPausedOverlayView` /
        // `GestureMuteToastView` remain valid standalone widgets (see their own file headers) but
        // are no longer composed by `PlayerShellView`. VOD / finished-live-replay play/pause now
        // lives on `PlaybackProgressBarView`'s own expanded-state button below.

        // 會員等級限定升級遮罩（restriction-mask ②）。`is_restriction` 為**軟性顯示閘門**：core 不擋
        // 播放（後端仍回完整內容），reference-ui 在播放畫面上疊全幅暗罩 + 升級提示並阻擋下層互動。疊
        // 在播放 chrome 之上、info panel / 聯絡商家 modal 之下（對齊 iOS/RN）。預設隱藏
        // （`m.isRestricted == false`）→ golden byte-identical。最終視覺 / 退出 affordance
        // DECISION-PENDING 待設計稿。
        if (m.isRestricted) Positioned.fill(child: _RestrictionMask(theme: theme)),

        // Surface 3 — info panel, bottom sheet. Presented via the shared
        // [BottomSheetPresenter] (iOS `.lbBottomSheet` parity): a full-bleed dim scrim
        // BLOCKS the host content below + dismisses on a background tap, and the panel
        // slides up on present / down on dismiss (the presenter keeps the outgoing panel
        // rendered so the dismiss slide has content).
        BottomSheetPresenter(
          open: _infoPanelOpen,
          sheetKey: const ValueKey('info-open'),
          // Background (scrim) tap closes the info panel — the same toggle the `more`
          // rail affordance drives.
          onDismiss: () => _setInfoPanel(false),
          child: !_infoPanelOpen
              ? null
              : VideoInfoPanelView(
                  theme: theme,
                  fields: m.infoFields,
                  isSubscribed: m.isSubscribed,
                  activeTab: m.activeTab,
                  noticeCanOpen: m.noticeCanOpen,
                  systemNotice: m.systemNotice,
                  notice: m.notice,
                  // 商家列 logo 的 runtime 圖片閘門 —— 刻意與上方 header 呼叫點用**同一個**
                  // `widget.live`。兩個 surface 畫的是同一顆 shopLogo，gate 若各自推導遲早
                  // 分岔（header 已顯真 logo、面板還停在字母漸層）。
                  live: widget.live,
                  // isLive 文案分流（rb-flutter-live-replay-more-menu-and-video-info-live-copy，
                  // design R32）：直播中標題/tab/日期列改版。刻意複用 `PlayerHeaderBarView` 同一個
                  // `m.isLive`（`channel.liveStatus == 1`）——與這個面板既有的 `live`（image gate）
                  // 語意不同，不衝突（見 `VideoInfoPanelView.isLiveBroadcast` 自身 dartdoc）。
                  isLiveBroadcast: m.isLive,
                  // Template-owned navigation intent (NOT a core simulate*): only
                  // flips presentation state. `notice` is honoured by the template
                  // only when `noticeCanOpen`.
                  onSelectTab: m.selectInfoTab,
                  // 與商家一對一對話 → reuse the existing side-rail serviceLink host exit
                  // (Flutter routes rail taps through onTapRailItem; same destination
                  // as the rail serviceLink tap).
                  onContactMerchant: () => _handleRailTap(LBSideRailKind.serviceLink),
                  // header 右上角關閉 icon → 收合 info panel（rb-flutter-sheet-header-close-unify）：
                  // 第四個合法關閉入口（與 scrim / 下拉 / host-badge re-tap 同路）。
                  onClose: () => _setInfoPanel(false),
                  // 訂閱功能的第二個渲染位置（rb-flutter-subscribe-favorite-visibility-toggle）：
                  // 與 header 頭像徽章共用同一個 `showSubscribe` 旗標——這不是獨立元件，是同一個
                  // 訂閱功能在 shop row 的第二個渲染點。
                  showSubscribe: widget.showSubscribe,
                ),
        ),

        // 「更多」選單 sheet（design R32；rb-flutter-replay-live-chrome-parity 起觸發來源改為
        // `LiveBottomBarView.onMore`——僅 `m.isFinishedLiveReplay` 時該 bar 渲染出「更多」按鈕才可
        // 達，取代先前的 `OperationRailView.onTapMore`，機制本身不變）。內容為分享 + 客服兩個可互動
        // 格（各自轉發到既有 `_handleRailTap` chokepoint）+ 2 個逐字對齊設計稿的隱藏佔位格（見
        // `_RailMoreMenuSheet`）。用既有 [BottomSheetPresenter] 做 scrim + 滑入滑出；
        // `_RailMoreMenuSheet` 自己內部另包一層 `LBSheetScaffold`（rb-flutter-live-more-sheet-
        // drag-resize-parity）拿到跟其他四張 family-3 sheet 一致的拖曳把手 + 縮放/關閉手勢，`onDismiss`
        // 與下面 `BottomSheetPresenter.onDismiss` 指向同一個 `_setMoreMenuOpen(false)`——鏡射
        // `VideoInfoPanelView.onClose` 既有的雙寫接線模式。
        BottomSheetPresenter(
          open: _moreMenuOpen,
          sheetKey: const ValueKey('rail-more-open'),
          onDismiss: () => _setMoreMenuOpen(false),
          child: !_moreMenuOpen
              ? null
              : _RailMoreMenuSheet(
                  theme: theme,
                  showShare: m.railItems.any(
                      (it) => it.kind == LBSideRailKind.share && it.enabled),
                  showContact: m.railItems.any(
                      (it) => it.kind == LBSideRailKind.serviceLink && it.enabled),
                  onShare: () {
                    _setMoreMenuOpen(false);
                    _handleRailTap(LBSideRailKind.share);
                  },
                  onContact: () {
                    _setMoreMenuOpen(false);
                    _handleRailTap(LBSideRailKind.serviceLink);
                  },
                  onDismiss: () => _setMoreMenuOpen(false),
                ),
        ),

        // 「聯絡商家」confirm modal — composed LAST so it overlays the info-panel + chrome.
        // 「確定」proceeds to the existing serviceLink host exit; 「取消」/ scrim just closes.
        if (_contactMerchantPresented)
          ContactMerchantModalView(
            theme: theme,
            onConfirm: _confirmContactMerchant,
            onCancel: () => setState(() => _contactMerchantPresented = false),
          ),
      ],
    );
  }

  /// VOD-main now-introducing carousel surface (rb-flutter-now-introducing，問題 9/10/1). Builds the
  /// [LBMiniCartPeek] list from `m.vodActiveProducts` (pic = `photos.first ?? pic`), minus locally
  /// dismissed, and anchors a bottom-leading [NowIntroducingCarousel] (full width + page dots). The
  /// trailing inset clears the bottom-anchored side rail when it is shown (VOD-main, startPhase
  /// done): `60 = right 12 + pill 40 + gap 8`; the VOD start sequence (no side rail) keeps 8.
  /// Returns `[]` (drawn nothing) when there is no in-flight introducing product, OR while
  /// actively scrubbing the playback progress bar (`_isScrubbing`,
  /// rb-flutter-vod-playback-progress-bar — VOD-side chrome collapses during a drag), OR while
  /// `startPhase` is still `loading`/`splash` (rb-flutter-now-introducing-carousel-buffering-
  /// gate — the card now waits for the SAME threshold as the side rail / floating bag,
  /// `startPhase ∈ {buffering, done}`, rb-flutter-vod-rail-show-on-buffering). While
  /// released-but-still-held (`_scrubBarExpanded && !_isScrubbing`) the card lifts an extra
  /// [_scrubChromeLift] to clear the still-expanded transport bar. [safeAreaBottom]
  /// (fix-flutter-player-shell-bottom-safearea-gaps, ADDED Requirement — this card's bottom
  /// position was never covered by any prior `reference-ui-rendering` Requirement) is folded into
  /// the outer `Padding`'s `bottom`, matching the design authority
  /// (`design/templates/minimal/sdk-components.jsx:908` `LBPMiniCart`'s `bottom: 12 + safeBottom`)
  /// — MUST feed the SAME `MediaQuery.of(context).padding.bottom` value `_buildContent` already
  /// reads for every other bottom-pinned chrome in this file.
  List<Widget> _buildNowIntroducing(
      PlayerShellModel m, ReferenceUITheme theme, double safeAreaBottom) {
    // 乾淨模式（rb-flutter-gesture-clean-mode-rewrite）：與拖曳進度條同一個「不畫」出口。
    if (_isScrubbing || _cleanMode) return const [];
    final introducing = m.vodActiveProducts
        .where((p) => !_dismissedVodProductIds.contains(p.id))
        .toList();
    if (introducing.isEmpty) return const [];
    // The card's OWN mount now follows the side rail's visibility (shown from `buffering`
    // onward, suppressed only in loading/splash) — rb-flutter-now-introducing-carousel-
    // buffering-gate. `railShown` used to feed ONLY the trailing-padding calculation below
    // (never gated whether this card drew at all), so an early-populated `vodActiveProducts`
    // could surface the card BEFORE the side rail (`OperationRailView`) / floating bag
    // (`FloatingBagButton`) — both of which already gate on this same expression
    // (rb-flutter-vod-rail-show-on-buffering). Computed once; reused below for the trailing
    // inset so there is still only one `startPhase` read for both purposes.
    final railShown =
        m.startPhase != LBPStartPhase.loading && m.startPhase != LBPStartPhase.splash;
    if (!railShown) return const [];
    final lift = _scrubBarExpanded ? _scrubChromeLift : 0.0;
    return [
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Padding(
          padding: EdgeInsets.only(
              left: 8, right: railShown ? 60 : 8, bottom: safeAreaBottom + 12 + lift),
          child: NowIntroducingCarousel(
            theme: theme,
            peeks: [
              for (final p in introducing)
                LBMiniCartPeek(
                  productId: p.id,
                  name: p.name,
                  priceShow: p.priceShow,
                  soldOut: p.soldOut,
                  pic: p.photos.isNotEmpty ? p.photos.first : p.pic,
                ),
            ],
            live: widget.live,
            onDismiss: (id) =>
                setState(() => _dismissedVodProductIds.add(id)),
            onOpenDetail: (id) {
              for (final p in introducing) {
                if (p.id == id) {
                  widget.onTapNowIntroducingProduct?.call(p);
                  break;
                }
              }
            },
          ),
        ),
      ),
    ];
  }

  /// VOD closed-caption surface (rb-flutter-subtitle-vtt-caption-display). Resolves
  /// `effectiveCaption` from `_subtitleCues` at the current `m.playbackPosition`
  /// (`VTTSubtitleParser.activeCue`) exactly once, gates via [shouldShowSubtitleCaption] +
  /// `!_isScrubbing && !_cleanMode` (mirrors Android's own call-site AND split — those two flags
  /// are NOT baked into the pure gate function), and anchors bottom-center, lifted
  /// [_scrubChromeLift] while released-but-still-held (parity `_buildNowIntroducing`'s own lift).
  /// [isLive] feeds [shouldShowSubtitleCaption]'s own same-named argument directly — it MUST be
  /// the narrow `m.isLive`, NOT the caller-computed `usesLiveChrome = m.isLive ||
  /// m.isFinishedLiveReplay`. `rb-flutter-subtitle-vtt-caption-display` (archived 2026-08-31)
  /// deliberately chose `m.isLive` here (design.md Decision 2) and predicted in its own
  /// Risks/Trade-offs that a future `usesLiveChrome` unification would make captions follow it.
  /// `rb-flutter-replay-live-chrome-parity` (archived 2026-09-06) was exactly that predicted
  /// unification — feeding `usesLiveChrome` here was an explicit, itemized goal of that change
  /// (its own proposal.md/design.md list this call site by name), not an accidental sweep; it
  /// deliberately stopped showing captions for an already-finished live replay, matching
  /// iOS/Android at the time. `rb-flutter-replay-caption-overlay-fix` (2026-09-09) deliberately
  /// REVERSES that unification for captions only, per a user report + a four-platform sibling
  /// product decision — a new product decision, not a regression fix. Captions and "does this
  /// state wear LIVE chrome" are independent: a finished-live-replay is mechanically still
  /// playing back a recorded file, so it gets captions same as VOD, even while it also wears the
  /// LIVE bottom bar / overlay chrome. This means the caption no longer mounts under the SAME
  /// branch as `_buildNowIntroducing` (`!usesLiveChrome`) — they diverge exactly when
  /// `isFinishedLiveReplay == true` (caption shows, now-introducing carousel doesn't). Returns
  /// `[]` (drawn nothing) when the gate is not satisfied.
  ///
  /// Horizontal position (rb-flutter-caption-overlay-align-hide-chat): centers inside a narrow
  /// box (`Positioned(left: 8, right: captionOverlayRightInset(...))`), NOT the full screen width
  /// — parity design `sdk-components.jsx` `LBPCaptionOverlay`. See [captionOverlayRightInset]'s
  /// own doc comment for why the inset only needs to branch on `isFinishedLiveReplay`.
  ///
  /// Vertical position (`bottom`, rb-flutter-caption-overlay-bottom-bar-clearance-fix): resolved
  /// by [captionOverlayBottomInset], which folds in [safeAreaBottom] and
  /// [LiveBottomBarView.barHeight] for the already-finished-live-replay branch (the state where
  /// this overlay shares the screen with `LiveBottomBarView`) — see that function's own doc
  /// comment for the full derivation. [safeAreaBottom] MUST feed the SAME
  /// `MediaQuery.of(context).padding.bottom` local `_buildContent` already computes and threads
  /// into every other bottom-pinned chrome element's own inset function. The existing
  /// `_scrubChromeLift` lift-on-release behavior is preserved unchanged (still applied via [lift],
  /// now folded into [captionOverlayBottomInset] instead of being added inline here) — this
  /// requirement predates and is orthogonal to the vertical-position fix itself.
  List<Widget> _buildSubtitleCaption(
      PlayerShellModel m, ReferenceUITheme theme, bool isLive, double safeAreaBottom) {
    final effectiveCaption =
        VTTSubtitleParser.activeCue(_subtitleCues, m.playbackPosition)?.text ?? '';
    final shows = shouldShowSubtitleCaption(
          isLive: isLive,
          introPlaying: m.introPlaying,
          subtitleEnabled: m.subtitleEnabled,
          captionText: effectiveCaption,
        ) &&
        !_isScrubbing &&
        !_cleanMode;
    if (!shows) return const [];
    final lift = _scrubBarExpanded ? _scrubChromeLift : 0.0;
    final rightInset =
        captionOverlayRightInset(isFinishedLiveReplay: m.isFinishedLiveReplay);
    final bottomInset = captionOverlayBottomInset(safeAreaBottom,
        isFinishedLiveReplay: m.isFinishedLiveReplay, lift: lift);
    return [
      Positioned(
        left: 8,
        right: rightInset,
        bottom: bottomInset,
        child: Align(
          alignment: Alignment.center,
          child: CaptionOverlayView(theme: theme, text: effectiveCaption),
        ),
      ),
    ];
  }

  /// The UPCOMING (直播預告 awaitingLive) chrome — the design's LIVE chrome
  /// composition for upcoming. Background = [UpcomingCountdownView] (`live: false`
  /// here so the golden paints the deterministic solid background — the host supplies
  /// the real cover at runtime). Chrome = [PlayerHeaderBarView] (`isLive: false` so
  /// the LIVE pill / viewer count are hidden) + the SLIM [LiveBottomBarView]
  /// (`isUpcoming: true` → bag + spacer + share + like). It draws NEITHER the VOD side
  /// rail / floating bag / mini-cart NOR the [LiveOverlayChromeView] announce-pinned
  /// card / info panel. Flutter parity of iOS PlayerShellView's upcoming branch /
  /// Android `UpcomingScaffold`. Plain `Stack` / `Column` only (golden-deterministic).
  ///
  /// [safeAreaBottom] (rb-flutter-player-shell-bottom-chrome-safearea): `_buildContent`'s own
  /// `MediaQuery.of(context).padding.bottom` read, threaded in as a plain `double` — this method
  /// has no `BuildContext` of its own (see design.md Decision 3). Feeds the SLIM
  /// [LiveBottomBarView] call site's outer `Padding` via [liveBottomBarBottomInset].
  Widget _buildUpcoming(
      ReferenceUITheme theme, PlayerShellModel m, double safeAreaBottom) {
    // fix-flutter-endscreen-close-button-blocked: same override as `_buildContent`'s
    // main branch (this method has no closure over that local, so it is recomputed
    // here verbatim) — logically unlikely to coexist with an upcoming (直播預告)
    // channel, but applied for call-site consistency / to avoid a future divergence,
    // same forwarding discipline as `titleScroll` / `showCloseIcon` elsewhere in
    // this method.
    final headerCloseButton = resolveHeaderCloseButton(
      endScreenActive: m.isEndScreenActive,
      showCloseIcon: widget.showCloseIcon,
      onMinimize: widget.onMinimize,
      onCloseRequest: widget.onCloseRequest,
    );

    return Stack(
      children: [
        // Background: the upcoming countdown surface (date + big time). `live: false`
        // → solid theme.background (deterministic golden, no remote cover load). The
        // host supplies the real cover behind this chrome at runtime.
        Positioned.fill(
          child: UpcomingCountdownView(
            theme: theme,
            scheduledStartAt: m.upcomingStartAt,
            live: false,
            coverUrl: m.upcomingCover,
          ),
        ),

        // Header pinned top (LIVE pill / viewer count hidden since isLive == false
        // for upcoming). The minimize / subscribe lambdas forward as usual.
        Column(
          children: [
            // rb-flutter-player-header-safearea: SAME top-safe-area wrap as the main
            // branch above — MUST stay identical (`SafeArea(bottom: false, ...)`) so
            // 直播預告 (upcoming) doesn't regress relative to the main chrome.
            SafeArea(
              bottom: false,
              child: PlayerHeaderBarView(
                theme: theme,
                title: m.title,
                hostName: m.hostName,
                shopLogo: m.shopLogo,
                viewerCount: m.viewerCount,
                isSubscribed: m.isSubscribed,
                isLive: false,
                isReplay: false,
                live: widget.live,
                // fix-flutter-endscreen-close-button-blocked: forced to onCloseRequest
                // while the end screen is active — see resolveHeaderCloseButton above.
                onMinimize: headerCloseButton.onMinimize,
                onToggleSubscribe: widget.onToggleSubscribe,
                showSubscribe: widget.showSubscribe,
                // PlayerHeader 觀看人數徽章顯示/隱藏（rb-flutter-viewer-count-visibility-toggle，
                // parity iOS/Android showViewerCount）— 即使 upcoming 分支 isLive 恆為 false（旗標
                // 在此分支無可見效果），仍須轉發，比照 titleScroll / showCloseIcon 既有紀律。
                showViewerCount: widget.showViewerCount,
                // Merchant title-marquee gate, raw pass-through (rb-flutter-marquee-title-scroll).
                // Upcoming (直播預告) draws / measures / scrolls the title exactly like the main
                // branch, so this MUST be forwarded here too — omitting it would let the header
                // fall back to its own default and silently ignore the merchant setting.
                titleScroll: widget.titleScroll,
                // 右上角按鈕圖示 minimize ↔ close (rb-flutter-player-direct-close-button) — same
                // forwarding discipline as titleScroll above: the upcoming header draws the
                // SAME button, so omitting this here would silently drop the resolved icon on
                // 直播預告 videos.
                // fix-flutter-endscreen-close-button-blocked: forced true while the end
                // screen is active — see resolveHeaderCloseButton above.
                showCloseIcon: headerCloseButton.showCloseIcon,
              ),
            ),
          ],
        ),

        // SLIM LIVE bottom bar pinned bottom (bag + spacer + share + like; no 留言 /
        // nickname / CC). bag / share / like route through the existing rail wiring by
        // kind. NO VOD side rail / floating bag / mini-cart / overlay chrome.
        //
        // rb-flutter-player-shell-bottom-chrome-safearea: this branch had NO `Padding` at all
        // before this change — a new one is added so the bar clears the system bottom safe area,
        // matching the design's `LBLiveBottomBar` (same component as the main branch's own call
        // site, see `liveBottomBarBottomInset`'s doc comment). `lift: 0.0` — the upcoming slim
        // state has no playback progress bar / `_scrubBarExpanded` concept.
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(
                bottom: liveBottomBarBottomInset(safeAreaBottom, lift: 0.0)),
            child: LiveBottomBarView(
              theme: theme,
              bagCount: m.bagCount,
              isReplay: false,
              isUpcoming: true,
              // 讚鈕亮色狀態（rb-flutter-live-like-burst-restyle，design R37）。
              liked: _liveLiked,
              onBag: () => _handleRailTap(LBSideRailKind.goods),
              onShare: () => _handleRailTap(LBSideRailKind.share),
              // 真 like（host exit）+ 隨機 1-4 顆錯開飄心 burst + 讚鈕短暫亮色（
              // rb-flutter-live-bottom-heart-burst 起源，rb-flutter-live-like-burst-restyle 改版）。
              onLike: () {
                _handleRailTap(LBSideRailKind.like);
                _triggerLiveLikeBurst();
              },
            ),
          ),
        ),

        // 愛心 burst 錨於 slim 底部 bar 愛心上方（靜止態不畫 → golden 中立）。
        Positioned(
          right: 18,
          bottom: 64,
          child: HeartBurst(theme: theme, tick: _liveHeartTick),
        ),
      ],
    );
  }

  /// Resolve a completed vertical swipe (rb-player-shell swipe-override seam +
  /// swipe-nav-close-on-empty). A host override ALWAYS wins when supplied; else the
  /// built-in template-nav FALLBACK navigates when the swiped direction has an adjacent
  /// video, else raises [PlayerShellView.onCloseRequest] (closes the player — the list is
  /// at its head / tail) instead of the prior silent no-op. The navigate-vs-close decision
  /// is the pure [resolveSwipeNavFallback]. Below the threshold magnitude → no-op. Flutter
  /// parity of iOS `handleSwipeEnded` / Android / RN `resolveSwipeNav`.
  ///
  /// **Live-in-progress gate (rb-flutter-live-swipe-gesture-gating)**: when
  /// [allowsSwipeNav] (`= !_model.isLive`) is false — a live stream is actively in progress —
  /// this method returns immediately for BOTH directions, before the host-override /
  /// built-in-navigate / close-on-empty branches: no `onSwipeUp` / `onSwipeDown`, no
  /// `navigateAndNotifySwitch`, no `onCloseRequest`. The gesture is still fully consumed by
  /// the enclosing `GestureDetector` (its drag callbacks already claimed the arena over
  /// `onTap`, unrelated to this early return), so it does not leak into tap-to-mute. Upcoming
  /// never reaches this method at all (`_buildUpcoming` composes no swipe detector); a
  /// finished-live replay already has `isLive == false` (mutually exclusive with `isLive`),
  /// so it falls through unaffected, same as ordinary VOD.
  ///
  /// **Product-sheet-open gate (rb-flutter-block-swipe-nav-when-sheet-open)**: [widget
  /// .sheetsPresented] is ORed onto the SAME [allowsSwipeNav] call (`sheetsPresented:` named
  /// arg) — this method also returns immediately for BOTH directions while the sibling
  /// `ProductSheetsOverlayView` has ANY product sheet/modal open, same "gesture still consumed,
  /// just never dispatched" shape as the live-in-progress gate above. See [allowsSwipeNav]'s
  /// own doc comment for the full mechanism and why this is a defensive (not confirmed-bug) gate.
  void _handleSwipeEnded(double dy) {
    if (!allowsSwipeNav(_model.isLive, sheetsPresented: widget.sheetsPresented)) {
      return;
    }
    if (dy <= -_swipeThreshold) {
      if (widget.onSwipeUp != null) {
        widget.onSwipeUp!.call();
      } else if (resolveSwipeNavFallback(_model.hasNextVideo) ==
          SwipeNavFallbackAction.navigate) {
        // swipe-UP → next; report the new id (swipe-video-switched-notify) so the host's
        // video mirror (minimized floating preview) follows, AND fire the direct-reload seam
        // (flutter-swipe-video-load-requester-wiring-reference-ui — `navigateToNext()`'s own
        // requester is dead in production, see [onSwipeVideoLoad]'s doc comment).
        navigateAndNotifySwitch(_model.nextVideoId, _model.navigateToNext,
            widget.onDidSwitchVideo, widget.onSwipeVideoLoad);
      } else {
        widget.onCloseRequest?.call(); // close at the tail
      }
    } else if (dy >= _swipeThreshold) {
      if (widget.onSwipeDown != null) {
        widget.onSwipeDown!.call();
      } else if (resolveSwipeNavFallback(_model.hasPrevVideo) ==
          SwipeNavFallbackAction.navigate) {
        // swipe-DOWN → prev; report the new id (swipe-video-switched-notify), AND fire the
        // direct-reload seam (flutter-swipe-video-load-requester-wiring-reference-ui).
        navigateAndNotifySwitch(_model.prevVideoId, _model.navigateToPrev,
            widget.onDidSwitchVideo, widget.onSwipeVideoLoad);
      } else {
        widget.onCloseRequest?.call(); // close at the head
      }
    }
  }

  /// Forward a side-rail tap. The shell owns NO core action — every kind is routed
  /// to the host (`onTapRailItem` → core `simulate*`). The single presentation-only
  /// kind the shell may own is `more` → toggle the info panel as a default
  /// affordance (parity with iOS's `handleRailTap`).
  void _handleRailTap(LBSideRailKind kind) {
    if (kind == LBSideRailKind.more) {
      _setInfoPanel(!_infoPanelOpen);
      widget.onTapRailItem?.call(kind);
      return;
    }
    // 分享（rb-flutter-player-share-default-sheet）— 單一 chokepoint：LIVE / 回放底部 bar 分享鈕
    // （`LiveBottomBarView.onShare`）、純 VOD 側欄 rail 分享鈕（`OperationRailView.onTapItem`）、以及
    // upcoming SLIM 底部 bar 分享鈕皆 funnel 到此 `_handleRailTap(share)`。容器注入的 `onShare` 非 null
    // 時 → 走它（含 `Share.share(channel.share_url)` 系統分享 fallback，與商品詳情分享共用同一條
    // `PlayerOverlayContext.onShare`），而非只派 `VIDEO_SHARE_REQUEST` 事件的舊 rail 路由（unwired host
    // = 死按鈕）。`onShare == null`（非容器 / snapshot / golden）→ 退回既有 `onTapRailItem` headless 路由
    // → 像素 / 行為不變。parity iOS rb-ios-{live,vod-rail}-share-default-sheet。
    if (kind == LBSideRailKind.share && widget.onShare != null) {
      widget.onShare!.call();
      return;
    }
    // serviceLink (rail tap OR info-panel「與商家一對一對話」, both funnel here) → present the
    // 「聯絡商家」confirm modal FIRST (parity rb-*-contact-merchant-modal); only its「確定」
    // proceeds to the host exit (see [_confirmContactMerchant]). Do NOT open the link directly.
    if (kind == LBSideRailKind.serviceLink) {
      setState(() => _contactMerchantPresented = true);
      return;
    }
    widget.onTapRailItem?.call(kind);
  }

  /// 「確定」on the confirm modal → close it, then proceed to the host exit
  /// (dropin-service-link-default-browser-flutter): [PlayerShellView.onServiceLink] WINS when
  /// supplied (host's precise override); else fall back to the existing serviceLink host exit via
  /// `onTapRailItem` (current behaviour unchanged — no smart default is injected here, see
  /// design.md).
  void _confirmContactMerchant() {
    setState(() => _contactMerchantPresented = false);
    if (widget.onServiceLink != null) {
      widget.onServiceLink!();
    } else {
      widget.onTapRailItem?.call(LBSideRailKind.serviceLink);
    }
  }
}

// MARK: - Restriction mask (restriction-mask ②)
//
// 會員等級限定升級遮罩：全幅暗罩 + 升級提示。`is_restriction` 為**軟性顯示閘門**（core 不擋播放、
// 後端仍回完整內容），此遮罩疊在播放畫面上擋住受限內容並阻擋下層互動（`GestureDetector` opaque +
// 空 onTap → 攔截觸控）。只在 `PlayerShellView` 偵測 `m.isRestricted == true` 時建出，故未受限時
// 不出像素（golden byte-identical）。鏡像 iOS canonical `RestrictionMaskView` / RN 文案；lock glyph /
// 最終視覺 / 退出 affordance DECISION-PENDING 待設計稿（純文字呈現）。
const String _restrictionTitle = '此內容限定會員等級觀看';
const String _restrictionSubtitle = '提升會員等級後即可觀看';

class _RestrictionMask extends StatelessWidget {
  final ReferenceUITheme theme;

  const _RestrictionMask({required this.theme});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // 攔截下層互動（軟閘門：core 不擋播放，refui 擋互動）。
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: ColoredBox(
        color: const Color(0xC7000000), // black 0.78
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _restrictionTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: const Color(0xFFFFFFFF),
                    fontSize: 15 * theme.fontScale,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _restrictionSubtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: const Color(0xB3FFFFFF), // white 0.7
                    fontSize: 12 * theme.fontScale,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// MARK: - Clean-mode exit button (rb-flutter-gesture-clean-mode-v2)
//
// A small 36×36 dark-glass round button, shown only while `_cleanMode == true`, that exits clean
// mode on tap — the reference-ui-side operation channel that supersedes the retired long-press
// toggle (short tap now enters/defers into clean mode; this button is the dedicated exit).
//
// `rb-flutter-gesture-clean-mode-v2`'s own design.md deferred pixel-for-pixel alignment (exact
// coordinates / icon) as a Non-Goal — semantics only (visible in clean mode, gone otherwise, tap
// exits). `rb-flutter-clean-mode-exit-icon-fix` supersedes that Non-Goal: the icon now IS
// `DetailGlyph` (design `Icons.detail` — a list/detail glyph, not fullscreen-exit), and the
// caller's position (see below) is aligned to the design. The prior "exact coordinates / icon are
// NOT required" description no longer holds — see this change's design.md.

class _CleanModeExitButton extends StatelessWidget {
  final VoidCallback? onTap;

  const _CleanModeExitButton({this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: LbTestKeys.cleanModeExitButton,
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: const DetailGlyph(color: Colors.white, size: 18),
      ),
    );
  }
}

// MARK: - 更多選單 sheet (originally rb-flutter-live-replay-more-menu-and-video-info-live-copy)
//
// Design source: `design/templates/minimal/screens.jsx` `LBPPlayerScreen`'s `live_more` state
// block (699-720) — a 4-slot row (分享 / 客服 / 2 hidden placeholders). Opened by
// `LiveBottomBarView.onMore` (only reachable when `PlayerShellModel.isFinishedLiveReplay` makes
// that bar render its「更多」leading slot — `rb-flutter-replay-live-chrome-parity` moved this
// trigger here from the now-component-level-only `OperationRailView.onTapMore`, once
// `usesLiveChrome` unification made the side rail unreachable for a closed-chat finished replay;
// see this change's `design.md` D3). Presented via the shared [BottomSheetPresenter] for the
// scrim + slide-in chrome, and (rb-flutter-live-more-sheet-drag-resize-parity) internally wraps
// its own content in [LBSheetScaffold] — the SAME shared drag-resize/dismiss scaffold every
// other family-3 sheet uses (`ProductListSheet` / `ProductDetailSheet` / `NotifyRestockSheet` /
// `VideoInfoPanelView`) — matching the design reference's own `<LBPBottomSheet heightPct={30}>`
// wrapper (`screens.jsx:699-720`), which carries `handle = true` as ITS OWN default. The
// PRE-FIX code skipped `LBSheetScaffold` entirely (a bare `ClipRRect` + `ColoredBox`) on the
// reasoning "small fixed content, no drag-resize / drag-dismiss needed" — that reasoning
// predates checking the design reference, which wraps this sheet in the SAME shared component
// as every other one; the pre-fix sheet had no grab handle and no drag-to-dismiss gesture at
// all, a real, user-reported inconsistency against every other sheet in the app.

/// One slot in the「更多」sheet: a 40×40 circular icon chip (`rgba(204,204,204,0.8)`) + a 12px
/// label below (design `sdk-components.jsx`-style action-list token, gap 8). `null` [onTap] AND
/// `null` [icon] together render an inert, invisible-but-space-reserving placeholder (design's
/// own `visibility:hidden` — a deliberately unwired upstream slot, verbatim, not a bug this
/// change introduces). [icon] is a pre-built glyph `Widget` (NOT an `IconData`) so a caller may
/// pass either a Material `Icon(...)` or a self-drawn glyph (`ShareGlyph`, matching this file's
/// existing convention of self-drawn glyphs over Material `Icons.*` where one already exists) —
/// the caller is responsible for tinting that glyph with [theme].text (see [_RailMoreMenuSheet]).
///
/// The label text color is [theme].text — design `screens.jsx:710`'s `color: theme.surface.text`
/// (dark, NOT white). This sheet sits on its own OPAQUE [theme].background card (see
/// [_RailMoreMenuSheet]'s `ColoredBox`), unlike the rail pills / bottom-bar icons elsewhere in
/// this file that float directly over video and so use a fixed white — a hardcoded white here
/// would be illegible against the light `minimal` theme's white background (caught by
/// independent verification; fixed, not a design decision).
class _RailMoreMenuSlot extends StatelessWidget {
  final Key? slotKey;
  final ReferenceUITheme theme;
  final Widget? icon;
  final String? label;
  final VoidCallback? onTap;

  const _RailMoreMenuSlot({
    this.slotKey,
    required this.theme,
    this.icon,
    this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (icon == null || label == null) {
      // Hidden placeholder — reserves the same 64-wide column, paints nothing, hit-tests nothing.
      return const SizedBox(width: 64, height: 76);
    }
    return GestureDetector(
      key: slotKey,
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFCCCCCC).withValues(alpha: 0.8),
                shape: BoxShape.circle,
              ),
              child: icon,
            ),
            const SizedBox(height: 8),
            Text(label!, style: TextStyle(fontSize: 12, color: theme.text)),
          ],
        ),
      ),
    );
  }
}

/// The「更多」sheet body: rounded-top card + a 4-slot row (分享 / 客服 / 2 hidden placeholders,
/// design `screens.jsx:699-720`). [showShare] / [showContact] gate whether that slot is the
/// interactive icon+label form or the hidden placeholder form — mirrors
/// `OperationRailView._presentationOrder`'s own `enabled`-gated visibility discipline, applied to
/// the SAME two `LBSideRailKind`s this sheet collapsed off the rail.
/// Grab-handle color for [_RailMoreMenuSheet] — `theme.surface.strokeStrong` in the design
/// reference; matches `video_info_panel.dart`'s own private `_strokeStrong` verbatim.
final Color _railMoreSheetStrokeStrong =
    colorFromHex('#D8D5DE') ?? const Color(0xFFD8D5DE);

class _RailMoreMenuSheet extends StatelessWidget {
  final ReferenceUITheme theme;
  final bool showShare;
  final bool showContact;
  final VoidCallback? onShare;
  final VoidCallback? onContact;

  /// Drag-to-dismiss forwarding (rb-flutter-live-more-sheet-drag-resize-parity) — mirrors
  /// `VideoInfoPanelView.onClose`'s own call-site pattern: the caller wires this to the SAME
  /// dismiss action (`_setMoreMenuOpen(false)`) as the outer `BottomSheetPresenter.onDismiss`,
  /// so dragging this sheet's own grab handle down past the threshold closes it exactly like a
  /// scrim tap does. `null` (default) → the drag still tracks visually but releasing past the
  /// threshold is inert — matches [LBSheetScaffold.onDismiss]'s own no-op contract.
  final VoidCallback? onDismiss;

  const _RailMoreMenuSheet({
    required this.theme,
    required this.showShare,
    required this.showContact,
    this.onShare,
    this.onContact,
    this.onDismiss,
  });

  /// Grab handle (36×4, rounded, `#D8D5DE` — design `theme.surface.strokeStrong`) — same
  /// visual recipe every other family-3 sheet's own private `_grabHandle()` draws (e.g.
  /// `VideoInfoPanelView._grabHandle()` / `_strokeStrong`), copied verbatim here since this
  /// file has no shared grab-handle widget to import and `ReferenceUITheme` carries no
  /// `strokeStrong` field of its own.
  Widget _grabHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: _railMoreSheetStrokeStrong,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      key: LbTestKeys.liveMoreSheet,
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(20),
        topRight: Radius.circular(20),
      ),
      child: ColoredBox(
        color: theme.background,
        // rb-flutter-live-more-sheet-drag-resize-parity: renders via the shared
        // `LBSheetScaffold` — same grab-handle-drag-resize/dismiss every other family-3 sheet
        // gets, and parity the design reference's own `<LBPBottomSheet heightPct={30}>` wrapper.
        child: LBSheetScaffold(
          heightFraction: 0.30,
          onDismiss: onDismiss,
          header: _grabHandle(),
          body: Padding(
            // rb-flutter-live-more-sheet-vertical-padding: top was 0 (missing) — design
            // `screens.jsx` `padding: '20px 18px'` (CSS shorthand = 20 top/bottom, 18
            // left/right) and both iOS (`LiveMoreSheetView.verticalPadding = 20`, applied via
            // `.padding(.vertical, ...)` on the action row) and Android (`LiveMoreMenuSheet.kt`
            // `padding(horizontal = 18.dp, vertical = 20.dp)`) already apply 20 on BOTH edges —
            // Flutter was the only platform missing the top half, making the action row sit
            // right up against the grab handle with visibly less breathing room.
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _RailMoreMenuSlot(
                  slotKey: LbTestKeys.liveMoreShare,
                  theme: theme,
                  // 分享 icon 改設計稿自繪實心三節點 ShareFillGlyph（rb-flutter-live-more-sheet-
                  // share-fill-icon，對齊 `Icons.shareFill`）——這顆「更多」sheet 的分享格子與既有
                  // rail pill（`operation_rail.dart`）/ LiveBottomBarView 用的外框（stroked）版
                  // `ShareGlyph`（對齊 `Icons.share`）是不同的設計 token，不可混用；那兩處維持不變。
                  // 顏色 `theme.text`（design `screens.jsx:710` `theme.surface.text`，深色）——這顆
                  // sheet 坐在自己不透明的 `theme.background` 卡片上，不是疊在影片上，MUST NOT 套用
                  // 其他 rail pill 的固定白字慣例（那是「疊在影片上」的配色，這裡誤套過一次，已由獨立
                  // 驗證抓到並修正）。
                  icon: showShare ? ShareFillGlyph(color: theme.text, size: 20) : null,
                  label: showShare ? '分享' : null,
                  onTap: onShare,
                ),
                const SizedBox(width: 20),
                _RailMoreMenuSlot(
                  slotKey: LbTestKeys.liveMoreContact,
                  theme: theme,
                  // 客服 icon 改設計稿自繪雙對話框+問號 ContactGlyph（rb-flutter-icon-parity-
                  // operation-rail-batch，取代 Material Icons.chat_bubble——parity 側欄
                  // serviceLink pill / VideoInfoPanel footer 兩處已同步改用的同一顆 ContactGlyph）。
                  icon: showContact ? ContactGlyph(color: theme.text, size: 20) : null,
                  label: showContact ? '客服' : null,
                  onTap: onContact,
                ),
                const SizedBox(width: 20),
                _RailMoreMenuSlot(theme: theme),
                const SizedBox(width: 20),
                _RailMoreMenuSlot(theme: theme),
              ],
            ),
          ),
          footer: const SizedBox.shrink(),
        ),
      ),
    );
  }
}
