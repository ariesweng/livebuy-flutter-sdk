import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../productsheets/sheet_scaffold.dart' show liveProductImage;
import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';

// PlayerHeaderBarView — family-1 surface 1 (top-bar chrome).
//
// Spec: `reference-ui-rendering/spec.md` (family-1 player-shell, surface 1).
// Flutter parity of iOS `PlayerHeaderBarView.swift` (rb-ios-player-shell, D-2 #1)
// and Android `PlayerHeaderBar.kt` (rb-android-player-shell).
//   Mirrors design `LBPTopBar` / `LBPHostBadge` (sdk-components.jsx): a pinned top
//   bar with a glassy host pill (avatar + title + host name + LIVE pill + viewer
//   count + subscribe affordance) on the leading edge, and a SINGLE round glass
//   minimize button on the trailing edge. The bar itself paints NO background
//   (rb-flutter-live-chrome-gradient-removal — the design's top-down scrim is
//   removed, not approximated). info / share live in the side rail; mute is the
//   tap-to-mute gesture on the video area — none of them is a header control.
//
// SUB-VIEW INPUT PATTERN (the contract documented in `player_shell_view.dart`):
//   1. `theme:` (ReferenceUITheme, required)            — FIRST, always.
//   2. its bound SNAPSHOT VALUES (title / hostName / shopLogo / viewerCount /
//      isSubscribed), passed BY VALUE from PlayerShellModel — never the model,
//      never the template. (The header no longer binds `muted` / `shareUrl`:
//      mute is the tap-to-mute gesture, share lives in the side rail.)
//   3. optional action callbacks, trailing, EACH defaulting to a no-op
//      (`VoidCallback? onX`). The shell owns NO action; the host wires taps to
//      core `simulate*` (D-4).
//
// It reads ONLY its passed-in values (one-way data flow, D-1/D-4): it never reaches
// back into `PlayerShellModel` or `DefaultPlayerTemplate`, holds NO second copy of
// state, and renders correctly with EVERY callback null / omitted (so the
// demo / golden / widget tests construct it action-free).
//
// Determinism (iOS / Android lessons baked in): plain `Column` / `Row` / `Stack`
// only — NO scrollable container (`ListView` / `GridView` / `SingleChildScrollView`),
// NO random state. The LIVE-pill dot is drawn static.
//
// ⚠️ ONE animation lives here since `rb-flutter-marquee-title-scroll`: the title
// marquee ([_MarqueeTitleLoop]). Its STRUCTURE (two duplicated `Text` copies + the
// fixed gap) mounts purely on the measurement + `titleScroll` gate, but its DRIVER
// (`AnimationController.repeat()`) only runs on the host-runtime path
// ([live] `== true`). On the demo / golden / widget-test path ([live] `== false`, the
// DEFAULT) the marquee renders its RESTING FRAME (offset `0`) and no controller ever
// ticks — so every golden stays byte-stable and `tester.pumpAndSettle()` still
// converges. Same "no-animation-for-determinism" convention this package already uses
// in `productsheets/product_row.dart`'s `_GridPlayButton`.
//
// The avatar is the ONE place this surface can reach the network, and it is gated:
// on the demo / golden path (`live == false`, the DEFAULT) it paints ONLY the
// deterministic monogram — NO `Image.network` / `NetworkImage` — so the baseline
// stays byte-stable. On the host-runtime path (`live == true`) it overlays the real
// `shopLogo` through the shared `liveProductImage` primitive, with the monogram
// underneath as the loading / failure placeholder. The URL handed to the primitive
// is decided by the single predicate [PlayerHeaderBarView.resolveShopLogoUrl] — and so is
// the `ClipOval` wrapper: an unusable URL early-returns the bare monogram, matching
// `VideoInfoPanelView._shopLogo` (change `flutter-header-shop-logo-clipoval-parity-refui`).

// MARK: - Decorative design tokens (literal hex from live-chrome.jsx)
//
// FIXED decorative colors from the design (glass pill / on-glass white text).
// These are deliberately literal — they are NOT the theme accent / text /
// background, which feed the LIVE pill + subscribe badge (pulled from `theme`).

/// Glass fill `rgba(20,20,24,0.55)` (host pill, live-chrome.jsx).
final Color _pillGlass =
    (colorFromHex('#141418') ?? const Color(0xFF000000)).withValues(alpha: 0.55);

/// Glass fill `rgba(20,20,24,0.45)` (round icon buttons, live-chrome.jsx).
final Color _iconGlass =
    (colorFromHex('#141418') ?? const Color(0xFF000000)).withValues(alpha: 0.45);

/// On-glass primary text — white.
const Color _onGlass = Color(0xFFFFFFFF);

/// On-glass secondary text `rgba(255,255,255,0.85)`.
const Color _onGlassDim = Color(0xD9FFFFFF); // white @ 0.85

// MARK: - Marquee constants (verbatim from design `LBPMarqueeText`)
//
// Flutter logical pixels are device-independent, exactly like iOS points and Android dp,
// so these port across with no unit conversion.

/// Gap between the two duplicated title copies in the marquee loop
/// (design `LBPMarqueeText`'s `gap = 36`; iOS `marqueeGap`, Android `MARQUEE_GAP_DP`).
const double kMarqueeTitleGap = 36.0;

/// Marquee scroll speed (design `LBPMarqueeText`'s `speedPxPerSec = 32`).
const double kMarqueeTitleSpeedPixelsPerSecond = 32.0;

/// Marquee minimum loop duration floor in seconds (design `Math.max(8, ...)`;
/// iOS `marqueeMinDurationSeconds`, Android `MARQUEE_MIN_DURATION_SECONDS`).
const double kMarqueeTitleMinDurationSeconds = 8.0;

/// The family-1 top-bar chrome. Pinned to the top of the player shell; paints the
/// glassy host pill + a SINGLE round glass minimize button, over NO background
/// (rb-flutter-live-chrome-gradient-removal). Top-right = a single minimize
/// affordance (design `LBPTopBar` pip; user requirement「右上角只有縮小的元件」)
/// → [onMinimize] (host collapses the player into the bottom-right floating
/// preview). info / share live in the side rail; mute is the tap-to-mute gesture
/// on the video area.
///
/// Follows the SUB-VIEW INPUT PATTERN: `theme` first, then the bound snapshot
/// values BY VALUE, then optional host-wired callbacks (each a no-op default).
class PlayerHeaderBarView extends StatelessWidget {
  // -- 1. theme (FIRST, always) ----------------------------------------------

  /// The resolved reference-ui theme.
  final ReferenceUITheme theme;

  // -- 2. bound snapshot values (BY VALUE from PlayerShellModel) --------------

  /// Host-pill title (`DefaultPlayerHeaderState.title`).
  final String title;

  /// Host / shop name (`DefaultPlayerHeaderState.hostName`).
  final String hostName;

  /// Host-pill / top-bar logo URL (`DefaultPlayerHeaderState.shopLogo`). Whether it
  /// is actually loaded is decided by [resolveShopLogoUrl] — on the demo / golden
  /// path ([live] `== false`, the DEFAULT) nothing is fetched and the avatar paints
  /// the deterministic monogram placeholder, keeping the baseline byte-stable.
  final String shopLogo;

  /// Live viewer count (`DefaultPlayerHeaderState.viewerCount`).
  final int viewerCount;

  /// Subscribe affordance state (`DefaultPlayerHeaderState.isSubscribed`).
  final bool isSubscribed;

  /// LIVE vs VOD flag (`DefaultPlayerHeaderState.isLive`, channel `liveStatus == 1`).
  /// Per design `LBPHostBadge`: the viewer count shows ⟺ `isLive`; the LIVE pill shows
  /// ⟺ `isLive && !isReplay`. VOD (`isLive == false`) shows neither.
  final bool isLive;

  /// Replay (回放) flag — a LIVE stream scrubbed behind the live edge
  /// (`DefaultPlaybackProgressState.isReplay`; `liveStatus == 1` so `isLive` STAYS true,
  /// `isReplay == true`). A by-value presentation flag fed from `PlayerShellModel.isReplay`
  /// (NOT a header view-model field). Per design `hideLivePill = isReplay`: replay HIDES
  /// the LIVE pill but KEEPS the viewer count.
  final bool isReplay;

  /// Live-runtime image gate (parity with iOS/Android `live`). `true` → the avatar
  /// loads the real [shopLogo] via [liveProductImage]; `false` (demo / golden —
  /// DEFAULT) → deterministic monogram placeholder (no network, baseline stable).
  final bool live;

  // -- 3. optional action callbacks (LAST, each defaulting to a no-op) --------
  //
  // The top-right is a SINGLE minimize affordance → onMinimize; subscribe stays on
  // the avatar badge. The shell owns NO action; the host wires taps to core
  // `simulate*` (D-4). mute / share / info / close are NOT header controls.

  /// Tap on the top-right minimize button → host collapses the player into the
  /// bottom-right floating preview. null → drawn but inert (host-wired).
  final VoidCallback? onMinimize;

  /// Tap on the subscribe affordance (the small badge on the avatar).
  final VoidCallback? onToggleSubscribe;

  /// Tap on the host pill → open the video info panel (parity iOS `onTapHostBadge`, which
  /// replaced the removed rail「more」pill). null → pill not tappable (demo / upcoming).
  final VoidCallback? onTapHostBadge;

  /// Whether the subscribe badge (the small +/✓ affordance overlaid on the avatar) is
  /// drawn at all (rb-flutter-subscribe-favorite-visibility-toggle, parity iOS / Android /
  /// RN). Default `true` — this WIDGET's own default preserves EXISTING call sites /
  /// golden baselines byte-identical (this file never gated the badge before); the
  /// production turnkey container (`LivebuyPlayer`) is the one that actually flips it
  /// off by default via `LivebuyPlayerConfig.showSubscribe` (default `false` there —
  /// subscribe is opt-IN chrome a host explicitly turns on). `false` removes the whole
  /// `Positioned` node (not just its child), so the avatar's layout does not reserve
  /// dead space for a hidden badge.
  final bool showSubscribe;

  /// MERCHANT capability gate for the top-bar title MARQUEE
  /// (rb-flutter-marquee-title-scroll, parity iOS / Android `titleScroll`).
  ///
  /// Takes the RAW `extensions.video_title_scroll` wire value the merchant set in
  /// `/admin/additional` (backend setting item `video_title_display` — the wire key and
  /// the setting item deliberately do NOT share a name). `extensions` is an OPAQUE RAW
  /// BAG the SDK never interprets, so this widget does NOT read `sdkConfig` — the host
  /// does, and hands it down through `LivebuyPlayerConfig(titleScroll: ...)` with zero
  /// cast and zero home-grown default. Same raw-`Object?` shape this package already
  /// uses for the sibling `extensions` flag `showStock` / [normalizeShowStock].
  ///
  /// The single fallback lives in [normalizeTitleScroll], called EXACTLY ONCE (in
  /// [_titleSlot]): only `false`, numeric zero and the verbatim string `'0'` turn
  /// scrolling off; DEFAULT `null` ("nothing injected") scrolls, matching the backend's
  /// own "unset ⇒ `1`" default and this widget's behavior before the marquee landed.
  ///
  /// ⚠️ NOT A VISIBILITY SWITCH. Per the backend contract
  /// (`openspec/specs/backend/sdk-config.md`), `video_title_scroll` says whether the
  /// title SCROLLS, never whether it SHOWS. Off ⇒ the title still renders, single-line
  /// with a tail ellipsis, at the SAME height — see [_titleSlot].
  ///
  /// It answers「MAY the title scroll」; [marqueeTitleOverflows] answers「is there
  /// anything TO scroll」. They are ANDed in [showsMarqueeTitle] — this flag NEVER
  /// changes the measurement.
  final Object? titleScroll;

  /// 乾淨模式的 chrome 隱藏（rb-flutter-gesture-clean-mode-rewrite, design.md D3）: `true` →
  /// MUST NOT 渲染 [_hostPill()]（頭像 / 標題 / host 名 / LIVE pill / 觀看數）—— [_minimizeButton()]
  /// MUST 維持原位可見可點（對齊設計稿「VOD/回放保留最小化(PIP)鈕」）。Default `false` (leaf-safe —
  /// every EXISTING call site / golden baseline keeps rendering the host pill unchanged).
  ///
  /// 設計稿 `screens.jsx` 對這裡是兩個獨立布林（`LBPTopBar.showLogo` 只隱藏 logo 圖、
  /// `LBPHostBadge` 整顆隱藏）；Flutter 的 header 從一開始就把這兩個設計元件合併成單一 widget
  /// （沒有獨立的品牌 logo 節點——`shopLogo` 餵的是頭像，不是另一張 logo wordmark），故這裡收斂成
  /// 單一布林，語意上仍精確覆蓋「minimize 鈕留、其餘 header 內容走」。
  final bool hideHostPill;

  /// Whether the top-right button shows a "close" (✕) glyph instead of the default
  /// "minimize" (pip) glyph — a pure BY-VALUE presentation flag
  /// (rb-flutter-player-direct-close-button, parity iOS `PlayerHeaderBarView.showCloseIcon`).
  ///
  /// This widget holds NO concept of "mode": it never reads
  /// `LivebuySDK.enableDirectCloseButton` / `LivebuyPlayerConfig.enableDirectCloseButton`
  /// itself — the caller (`CollapsibleLivebuyPlayer` / `LivebuyPlayer._overlayContext()`)
  /// resolves that elsewhere (via the shared pure function
  /// `resolvedEnableDirectCloseButton`) and hands down this single bool.
  ///
  /// `false` (DEFAULT — every EXISTING call site / golden baseline) → draws the existing
  /// `Icons.picture_in_picture_alt` glyph, semantics label `'最小化'`. `true` → draws
  /// `Icons.close` (the same codepoint `FloatingWidgetView` / `MinimizedWidgetView` already
  /// use for their own close buttons — no new glyph invented), semantics label `'關閉'`
  /// (see [minimizeButtonSemanticsLabel]). `onMinimize`'s trigger timing is COMPLETELY
  /// UNCHANGED by this flag — only the icon + semantics label change; what tapping actually
  /// DOES is decided entirely by the caller.
  final bool showCloseIcon;

  /// The CURRENT mute state (`PlayerShellModel.muted`) — selects the mute button's glyph
  /// (rb-flutter-gesture-clean-mode-v2). Only meaningful when [onToggleMute] is non-null (the
  /// button only renders then); default `false` keeps every EXISTING call site's construction
  /// unchanged.
  final bool muted;

  /// Tap on the乾淨模式-only mute-toggle button → host-wired mute forwarder
  /// (rb-flutter-gesture-clean-mode-v2 — the SAME `PlayerShellView.onToggleMute` seam the retired
  /// tap-to-mute video-area gesture used to call, just re-triggered from this header button
  /// instead). `null` (DEFAULT — every EXISTING call site) → the button MUST NOT render at all
  /// (not just inert): `PlayerShellView` only passes a non-null value while `_cleanMode == true`.
  final VoidCallback? onToggleMute;

  const PlayerHeaderBarView({
    super.key,
    required this.theme,
    required this.title,
    required this.hostName,
    required this.shopLogo,
    required this.viewerCount,
    required this.isSubscribed,
    this.isLive = false,
    this.isReplay = false,
    this.live = false,
    this.onMinimize,
    this.onToggleSubscribe,
    this.onTapHostBadge,
    this.showSubscribe = true,
    this.titleScroll,
    this.hideHostPill = false,
    this.showCloseIcon = false,
    this.muted = false,
    this.onToggleMute,
  });

  @override
  Widget build(BuildContext context) {
    // rb-flutter-live-chrome-gradient-removal: the top-down dark scrim gradient (linear-gradient
    // rgba(0,0,0,0.45) → transparent) is REMOVED, matching the corrected design source
    // (`sdk-components.jsx` `LBPTopBar` no longer carries a `background` gradient). `DecoratedBox`
    // is kept (not restructured away) purely so `key: LbTestKeys.playerHeader` — a widget-test
    // hook, not part of the decoration — stays attached at the same tree position; its
    // `decoration:` is an empty `BoxDecoration()` (no-op pass-through), NOT `Color.clear` /
    // omitted-and-restructured, so this node paints nothing extra.
    return DecoratedBox(
      key: LbTestKeys.playerHeader,
      decoration: const BoxDecoration(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Leading slot flexes up to the icon cluster; the title/host-name Column
            // inside stretches to fill it (Expanded, rb-flutter-player-header-title-flex-width
            // — parity to design `LBPHostBadge`'s `flex: '1 1 auto'`, NOT "parity to iOS /
            // Android" as an earlier comment here claimed: Android's own PlayerHeaderBar.kt
            // never hugged content either, that line was simply wrong). The host name still
            // truncates so the fixed LIVE pill + viewer badge + the trailing icon cluster stay
            // fully visible at the fixed golden width — that part of the intent is unchanged.
            // Whole host pill is tappable → open the info panel (parity iOS host badge). The
            // subscribe badge inside keeps its own gesture (hit-tested first).
            //
            // 乾淨模式（rb-flutter-gesture-clean-mode-rewrite, [hideHostPill]）: swap the pill
            // for an empty `SizedBox.shrink()` — still wrapped in `Expanded` so the trailing
            // minimize button keeps its trailing alignment (no layout jump).
            Expanded(
              child: hideHostPill
                  ? const SizedBox.shrink()
                  : GestureDetector(
                      key: LbTestKeys.playerHeaderHostPill,
                      onTap: () => onTapHostBadge?.call(),
                      behavior: HitTestBehavior.opaque,
                      child: _hostPill(),
                    ),
            ),
            const SizedBox(width: 8),
            // 乾淨模式限定靜音鈕（rb-flutter-gesture-clean-mode-v2）：`onToggleMute != null` 時
            // （即 `_cleanMode == true` 期間）在 minimize 鈕左側多渲染一顆；`onToggleMute == null`
            // 時整顆 MUST NOT 渲染、MUST NOT 佔位（既有非乾淨模式 baseline byte-identical）。
            if (onToggleMute != null) ...[
              _muteButton(),
              const SizedBox(width: 8),
            ],
            _minimizeButton(),
          ],
        ),
      ),
    );
  }

  // MARK: - Host pill (LBPTopBar host pill + LBPHostBadge)

  // rb-flutter-player-header-viewer-pill: `_hostPill()` no longer paints a shared
  // `_pillGlass` background — only `_viewerBadge()` does (see its own `ShapeDecoration`
  // below). Parity `LBPHostBadge` (`sdk-components.jsx:355-458`), which has NO outer
  // background container at all; its text contrast comes from `textShadow` alone.
  // ⚠️ KNOWN GAP (not fixed by this change, flagged intentionally): `title` / `hostName`
  // carry ZERO `Shadow` / independent contrast mechanism — unlike the design's
  // `textShadow` — so once this background is gone there is no legibility fallback for
  // those two texts. Left for a follow-up change; MUST NOT be "fixed" here by re-adding
  // a background (that would defeat the point of this change).
  Widget _hostPill() {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _avatar(),
          const SizedBox(width: 8),
          // rb-flutter-player-header-title-flex-width: `Expanded` (FlexFit.tight), not
          // `Flexible` (FlexFit.loose) — the title/host-name Column MUST stretch to fill its
          // allocated share of this Row, matching design `LBPHostBadge`'s `flex: '1 1 auto'`.
          //
          // ⚠️ Empirically verified to be a NO-OP on today's rendered pixels / hit-testing
          // (see `design.md` of the change above): the outer `Expanded` in `build()` already
          // gives this whole `_hostPill()` subtree a TIGHT width constraint, which Flutter's
          // `BoxConstraints.constrain()` propagates through the `Container`(padding) / outer
          // `Row(mainAxisSize.min)` chain regardless of what this inner flex fit is — so the
          // `GestureDetector` hit-test area, the `LayoutBuilder` width `_titleSlot()` measures
          // for the marquee decision, and the title/host-name `Text` draw position are all
          // UNCHANGED by this line. The only thing that actually changes is this `Column`
          // node's OWN reported size (content-hugging → stretched) — a structural fact with no
          // downstream reader today. This is a latent-defect-prevention fix (align the internal
          // contract to the design's literal semantics), not a visible bug fix — do NOT read
          // the git history here as "this used to look broken."
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _titleSlot(),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Host name yields room (truncates) so the fixed LIVE pill +
                    // viewer badge that follow stay fully visible.
                    Flexible(
                      child: Text(
                        hostName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _onGlassDim,
                          fontSize: 10.5 * theme.fontScale,
                          fontWeight: FontWeight.normal,
                          height: 1.2,
                        ),
                      ),
                    ),
                    // Per design `LBPHostBadge`: LIVE pill ⟺ isLive && !isReplay;
                    // viewer count ⟺ isLive (replay KEEPS the count, only HIDES the
                    // pill; VOD shows neither). The spacing folds into each gate so no
                    // dangling gap remains when an element is hidden.
                    if (isLive && !isReplay) ...[
                      const SizedBox(width: 6),
                      _livePill(),
                    ],
                    if (isLive) ...[
                      const SizedBox(width: 6),
                      _viewerBadge(),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // MARK: - Title slot (design LBPMarqueeText) — rb-flutter-marquee-title-scroll

  /// The host-pill title slot. Parity design `LBPMarqueeText` and the already-shipped
  /// iOS `PlayerHeaderBarView.titleView` / Android `MarqueeTitle` — BEHAVIOR parity, not
  /// code parity (SwiftUI `.overlay` + `GeometryReader` and Compose
  /// `rememberInfiniteTransition` have no verbatim Flutter counterpart).
  ///
  /// ── THE LAYOUT-PARTICIPATING ELEMENT IS ALWAYS THE SAME `Text` ──
  ///
  /// The `Stack`'s ONLY non-positioned child is the very same single-line, ellipsized
  /// `Text` this widget rendered before the marquee landed — same font size / weight /
  /// `height` / `maxLines` / `overflow`, no width constraint. A `Stack` takes its size
  /// from its non-positioned children ALONE, and the marquee is attached through
  /// `Positioned.fill`, which is layout-inert. So the title slot's height — and
  /// therefore the hostName / LIVE-pill / viewer-count row beneath it — CANNOT move
  /// between the static and the scrolling state. That is a STRUCTURAL fact, not two
  /// branches whose numbers happen to agree today. This is the Flutter equivalent of
  /// iOS's `.overlay` argument; Android could not use it (Compose has no overlay) and
  /// had to fall back to two mutually-exclusive branches + a measurement test.
  ///
  /// MUST NOT be "fixed" by adding a parallel static branch
  /// (`shows ? _Marquee(...) : Text(...)`): two copies drift, and that downgrades the
  /// equal-height guarantee from a structural fact to a coincidence. `Text(...)` with
  /// `maxLines: 1` + `TextOverflow.ellipsis` ALREADY IS the design's non-scrolling
  /// branch (`nowrap` + `overflow:hidden` + `textOverflow:ellipsis`).
  ///
  /// ── WHY THE BASE `Text` GOES TRANSPARENT UNDER THE MARQUEE ──
  ///
  /// The marquee paints directly on top of the base `Text`. If the base kept its color,
  /// a second, motionless, ellipsized copy would show through from underneath as soon as
  /// the loop moved. So the base's `color` — and ONLY its color — becomes fully
  /// transparent in the scrolling state. Color has ZERO layout effect, so the structural
  /// height guarantee above is untouched. (This is a deliberate Flutter-side call; iOS's
  /// current implementation keeps its base `Text` colored. Noted, not "fixed" here —
  /// this change does not touch iOS.)
  ///
  /// ── MEASUREMENT: ONE SYNCHRONOUS PASS, NO SECOND FRAME ──
  ///
  ///   • text width      = [marqueeIntrinsicTextWidth] (`TextPainter`, unbounded) —
  ///                       pure, no widget, no render round-trip.
  ///   • container width = the `LayoutBuilder`'s `constraints.maxWidth`, i.e. the width
  ///                       actually AVAILABLE to the title slot (design JSX compares
  ///                       against the same thing: the wrapper's `clientWidth`).
  ///
  /// A `GlobalKey` + `RenderBox.size` (or any `onPreferenceChange`-style idiom) would
  /// need a SECOND build pass before the measurement exists — first frame wrong, second
  /// frame corrected — which is exactly the non-determinism iOS's design notes warn
  /// about. An unbounded `constraints.maxWidth` (`double.infinity`) makes
  /// [marqueeTitleOverflows] naturally `false` → static branch, no guard needed.
  ///
  /// ── ONE DECISION POINT, ONE NORMALIZATION POINT ──
  ///
  /// [normalizeTitleScroll] is called EXACTLY ONCE here, and [showsMarqueeTitle] is the
  /// ONLY thing that decides whether the marquee mounts. This build MUST NOT restate the
  /// AND condition, and MUST NOT call [marqueeTitleOverflows] directly.
  Widget _titleSlot() {
    final TextStyle baseStyle = TextStyle(
      color: _onGlass,
      fontSize: 12 * theme.fontScale,
      fontWeight: FontWeight.bold,
      height: 1.2,
    );
    // THE one normalization point for the raw wire value (see [titleScroll]).
    final bool scrollAllowed = normalizeTitleScroll(titleScroll);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Measure with the SAME scaler the `Text` below will paint with, so a host with
        // OS font scaling on does not get a measurement that disagrees with the pixels.
        final TextScaler textScaler = MediaQuery.textScalerOf(context);
        final double textWidth =
            marqueeIntrinsicTextWidth(title, baseStyle, textScaler: textScaler);
        final double containerWidth = constraints.maxWidth;
        final bool shows = showsMarqueeTitle(
          titleScroll: scrollAllowed,
          textWidth: textWidth,
          containerWidth: containerWidth,
        );
        return Stack(
          children: [
            // The ONE layout-participating element, identical in both states except for
            // its (layout-irrelevant) color.
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: shows
                  ? baseStyle.copyWith(color: const Color(0x00000000))
                  : baseStyle,
            ),
            if (shows)
              Positioned.fill(
                child: _MarqueeTitleLoop(
                  title: title,
                  style: baseStyle,
                  textWidth: textWidth,
                  gap: kMarqueeTitleGap,
                  durationSeconds: marqueeDurationSeconds(textWidth: textWidth),
                  // DRIVER gate only — never the mount gate. See the file header.
                  animate: live,
                ),
              ),
          ],
        );
      },
    );
  }

  /// The title's intrinsic single-line width at [style] — a pure, synchronous
  /// `TextPainter` measurement with NO `maxWidth`, so it reports the width the text
  /// WANTS, unaffected by truncation. Zero widget / render-tree dependency, so it is
  /// directly unit-testable. Mirrors iOS `marqueeIntrinsicTextWidth`
  /// (`NSString.size(withAttributes:)`) and Android's `TextMeasurer` call.
  static double marqueeIntrinsicTextWidth(
    String text,
    TextStyle style, {
    TextScaler textScaler = TextScaler.noScaling,
  }) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    return painter.width;
  }

  /// Marquee overflow decision (parity JSX `LBPMarqueeText`'s `scrollWidth <=
  /// clientWidth`, and the iOS / Android functions of the same name). Pure /
  /// deterministic. Overflow (→ marquee) ⟺ the text is STRICTLY wider than the
  /// container — a direct `>` port of the two shipped platforms' decision, NOT the JSX's
  /// own `+ 1` CSS tolerance: agreeing with the platforms that already shipped beats
  /// re-deriving from the JSX independently.
  ///
  /// This answers「is there anything TO scroll」ONLY. It is 100% content-driven and MUST
  /// stay that way: no caller preference may stand in for this measurement. Whether the
  /// marquee actually mounts is [showsMarqueeTitle], which ANDs this with the
  /// [titleScroll] capability gate. [_titleSlot] MUST call [showsMarqueeTitle], never
  /// this function directly.
  static bool marqueeTitleOverflows({
    required double textWidth,
    required double containerWidth,
  }) {
    return textWidth > containerWidth;
  }

  /// THE single decision for whether the marquee overlay mounts. Pure / deterministic.
  /// Two orthogonal questions, ANDed — and they MUST NOT substitute for one another:
  ///
  ///   • [titleScroll] — MAY it scroll? A backend / merchant capability gate sourced
  ///     from `extensions.video_title_scroll` (design `LBPHostBadge`'s `titleScroll`
  ///     prop), ALREADY normalized to a `bool` by [normalizeTitleScroll]. NOT a caller
  ///     preference knob, and it MUST NOT influence the measurement below.
  ///   • [marqueeTitleOverflows] — is there anything TO scroll? Content measurement,
  ///     automatic.
  ///
  /// `titleScroll == false` therefore means「single-line, tail-ellipsized, not
  /// scrolling」— NOT「hidden」: the same `Text` keeps rendering, at the same height.
  static bool showsMarqueeTitle({
    required bool titleScroll,
    required double textWidth,
    required double containerWidth,
  }) {
    return titleScroll &&
        marqueeTitleOverflows(
          textWidth: textWidth,
          containerWidth: containerWidth,
        );
  }

  /// Marquee loop duration in seconds (parity JSX `dur = Math.max(8, scrollWidthPx /
  /// speedPxPerSec)`, iOS `marqueeDurationSeconds`, Android `marqueeDurationMillis`).
  /// Flutter logical pixels are device-independent just like iOS points / Android dp, so
  /// this is a direct port with no unit adjustment. Pure / deterministic.
  static double marqueeDurationSeconds({
    required double textWidth,
    double speedPixelsPerSecond = kMarqueeTitleSpeedPixelsPerSecond,
    double minDurationSeconds = kMarqueeTitleMinDurationSeconds,
  }) {
    return math.max(minDurationSeconds, textWidth / speedPixelsPerSecond);
  }

  /// The avatar's shop-logo gate: the URL to hand [liveProductImage], or null when
  /// nothing should be loaded. Pure — no I/O, no global state, no widget types.
  ///
  /// ── THE LADDER (three rungs, deliberately NOT four) ──
  ///
  ///   1. [live] is false (demo / golden / preview)          → null
  ///   2. [urlString] is null, or blank after trimming       → null
  ///   3. otherwise                                          → the TRIMMED string
  ///
  /// ── WHY SCHEME VALIDATION IS *NOT* RUNG 4 ──
  ///
  /// A non-empty return does NOT promise an image will paint: `http` / `https`
  /// whitelisting and the cleartext http→https upgrade live in the shared primitive
  /// ([liveProductImage] → `_httpUri`, `sheet_scaffold.dart`). Re-deriving them here
  /// would put the scheme policy in a SECOND place that can disagree with the
  /// primitive the moment either side moves. Same call — and the same `String?`
  /// (not `Uri?`) signature — as the sibling `VideoInfoPanelView.resolveShopLogoUrl`.
  /// The pure-function matrix therefore covers rungs 1-2; the structural widget
  /// tests cover the primitive's scheme rung.
  ///
  /// ── STRUCTURAL COUPLING: THE URL FED TO THE PRIMITIVE *IS* THIS RETURN VALUE ──
  ///
  /// [_avatar] MUST pass this function's return value as `liveProductImage(url:)`
  /// and MUST NOT pass the raw [shopLogo], nor re-derive an equivalent test at the
  /// draw site. Once the decision and the drawing are implemented separately they
  /// drift, and this function's unit tests stop saying anything about what is
  /// actually painted. Coupling them structurally is the ONLY thing that makes the
  /// matrix meaningful.
  ///
  /// ── ⚠️ `live` IS NOT `isLive` ⚠️ ──
  ///
  /// [live] is the **live-runtime IMAGE GATE**. [isLive] is the LIVE broadcast state
  /// (LIVE pill + viewer count). This surface carries BOTH, so they are easy to
  /// confuse: the golden fixtures pass `isLive: true` while [live] stays false.
  ///
  /// ── CROSS-SURFACE STATUS (checked 2026-07-20) ──
  ///
  /// LADDER: **no divergence.** This ladder and `VideoInfoPanelView.resolveShopLogoUrl`
  /// return the same result for every input — both trim, both delegate scheme policy to
  /// the same primitive. (Unlike iOS, whose two surfaces DO diverge on trimming.) The
  /// `階梯一致性` test in `player_header_bar_view_test.dart` pins that equality.
  ///
  /// SHAPE: **converged** (change `flutter-header-shop-logo-clipoval-parity-refui`).
  /// The `ClipOval` wrapper is gated by THIS function's return value — never by [live] —
  /// so an unusable logo early-returns the bare monogram, exactly like the info panel
  /// returns its chip unwrapped. See the `convergedWithInfoPanel` test in
  /// `player_header_bar_view_test.dart`, which pins BOTH directions.
  static String? resolveShopLogoUrl({
    required bool live,
    required String? urlString,
  }) {
    // Rung 1 — the runtime image gate is closed (demo / golden / preview).
    if (!live) return null;
    // Rung 2 — nothing usable to load (null / empty / whitespace-only).
    final trimmed = urlString?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    // Rung 3 — hand the trimmed URL over; scheme policy is the primitive's contract.
    return trimmed;
  }

  /// Avatar — a white-backed circle with the subscribe badge overlaid at the
  /// bottom-trailing, filled with the shop mark. The URL loaded (if any) is decided
  /// SOLELY by [resolveShopLogoUrl]; the accent-tinted monogram (first letter of the
  /// host name) is the placeholder underneath, so the demo / golden path and the
  /// loading / failure states all paint something deterministic.
  Widget _avatar() {
    return SizedBox(
      width: 28 + 3, // room for the badge offset (3px) at the bottom-trailing
      height: 28 + 3,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFFFFFFF),
              shape: BoxShape.circle,
            ),
            child: _avatarFill(),
          ),
          if (showSubscribe)
            Positioned(
              // Bottom-trailing of the 28px avatar, offset out by 3px (LBPHostBadge).
              left: 28 - 16 + 3,
              top: 28 - 16 + 3,
              child: _subscribeBadge(),
            ),
        ],
      ),
    );
  }

  /// The avatar circle's fill: the real shop logo when there is one to load, the bare
  /// monogram otherwise.
  ///
  /// ── THE `ClipOval` IS GATED BY URL USABILITY, *NOT* BY [live] ──
  ///
  /// `ClipOval`'s only job is rounding off a loaded square image. With no image it has no
  /// job left — only a side effect on the placeholder. So the unusable-logo path early
  /// returns the monogram WIDGET-FOR-WIDGET (no `ClipOval`, no `SizedBox`, nothing), the
  /// same discipline as `VideoInfoPanelView._shopLogo`'s `if (logoUrl == null) return chip;`.
  ///
  /// That side effect is REAL, not theoretical (measured, change
  /// `flutter-header-shop-logo-clipoval-parity-refui`): `ClipOval` takes the monogram
  /// `Text`'s INTRINSIC size as its clip box, and the inscribed ellipse starts cutting the
  /// glyph once `theme.fontScale >= 1.6` — a host-settable token (`sdkConfig.theme.fontScale`
  /// / `LBUIOptions.theme.fontScale`). At the shipped default 1.0 the pixels are identical,
  /// which is exactly why nobody ever noticed: every golden runs at scale 1.0.
  ///
  /// ── WHY NO `SizedBox` HERE (the info panel needs one, we do NOT) ──
  ///
  /// `liveProductImage`'s drawing branch returns `Stack(fit: StackFit.expand)`, which needs
  /// BOUNDED constraints. The info panel's chip sits in a width-unbounded `Row`, so it must
  /// re-impose 44×44 with a load-bearing `SizedBox`. Here the enclosing
  /// `Container(width: 28, height: 28, alignment: center)` already yields loose-but-BOUNDED
  /// constraints (`0..28`), so `constraints.biggest` resolves to 28×28 on its own. Copying
  /// the info panel's `SizedBox` would be cargo-culting a fix for a problem we don't have.
  /// Pinned by the `Image` sizing test.
  ///
  /// `live: true` is a literal on purpose: the gate is already settled by
  /// [resolveShopLogoUrl], so the primitive's own `_httpUri` re-check is its contract (and
  /// carries the cleartext http→https upgrade), not a second copy of the gate.
  /// `VideoInfoPanelView` passes the same literal. `fit` is deliberately NOT passed — the
  /// primitive already defaults to `BoxFit.cover`.
  ///
  /// Note the white circle survives either way: it is painted by the enclosing
  /// `Container`'s `BoxDecoration(shape: BoxShape.circle)`, never by this `ClipOval`.
  Widget _avatarFill() {
    final String? logoUrl = resolveShopLogoUrl(live: live, urlString: shopLogo);
    // Nothing to load (demo / golden / preview, or a blank / unusable URL) — hand back the
    // monogram unwrapped. NOT `live`-gated: that was the old shape, and it clipped.
    if (logoUrl == null) return _monogramText();
    return ClipOval(
      child: liveProductImage(
        live: true,
        url: logoUrl,
        placeholder: _monogramText(),
      ),
    );
  }

  /// First grapheme of the host name (or title) for the placeholder monogram.
  String _monogram() {
    final source = hostName.isEmpty ? title : hostName;
    return source.isEmpty ? '·' : source.substring(0, 1).toUpperCase();
  }

  /// The deterministic monogram text (avatar fallback / golden baseline). Used as
  /// both the `live == false` avatar child AND the [liveProductImage] placeholder.
  Widget _monogramText() => Text(
        _monogram(),
        style: TextStyle(
          color: theme.accent,
          fontSize: 13 * theme.fontScale,
          fontWeight: FontWeight.bold,
        ),
      );

  /// The small +/✓ subscribe badge overlaid on the avatar (LBPHostBadge).
  /// Subscribed → theme text fill + check; not subscribed → accent fill + plus.
  Widget _subscribeBadge() {
    return GestureDetector(
      key: LbTestKeys.subscribeBadge,
      onTap: onToggleSubscribe,
      child: Container(
        width: 16,
        height: 16,
        alignment: Alignment.center,
        // White ring (2px) around the fill, like the design's `border:2px solid #fff`.
        decoration: const BoxDecoration(
          color: Color(0xFFFFFFFF),
          shape: BoxShape.circle,
        ),
        child: Container(
          width: 12,
          height: 12,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSubscribed ? theme.text : theme.accent,
            shape: BoxShape.circle,
          ),
          child: Text(
            isSubscribed ? '✓' : '+',
            style: TextStyle(
              color: const Color(0xFFFFFFFF),
              fontSize: 9 * theme.fontScale,
              fontWeight: FontWeight.bold,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }

  /// The red LIVE pill (accent-filled) with a dot — drawn static for the golden
  /// baseline. Background uses `theme.accent` (the brand action red the design
  /// uses for the LIVE badge).
  Widget _livePill() {
    return Container(
      decoration: BoxDecoration(
        color: theme.accent,
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: const BoxDecoration(
              color: Color(0xFFFFFFFF),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            'LIVE',
            style: TextStyle(
              color: const Color(0xFFFFFFFF),
              fontSize: 9.5 * theme.fontScale,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  /// Viewer count with a small people glyph.
  ///
  /// rb-flutter-player-header-viewer-pill: carries its OWN `_pillGlass` glass-pill
  /// background (`StadiumBorder`, same color token as the now-removed `_hostPill()`
  /// outer background — no new color value). Small internal padding keeps the icon /
  /// text off the pill edge; this is purely a local detail of this widget and does
  /// not affect `_hostPill()`'s outer `Row` negotiation (this `Container` is already
  /// `mainAxisSize: MainAxisSize.min`-equivalent — it hugs its own content).
  Widget _viewerBadge() {
    return Container(
      decoration: ShapeDecoration(
        color: _pillGlass,
        shape: const StadiumBorder(),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 11 * theme.fontScale, color: _onGlassDim),
          const SizedBox(width: 3),
          Text(
            formatViewerCount(viewerCount),
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: _onGlassDim,
              fontSize: 10.5 * theme.fontScale,
              fontWeight: FontWeight.normal,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  // MARK: - Trailing — minimize button (LBPTopBar pip affordance) + clean-mode-only mute button
  //
  // The top-right normally contains ONLY a minimize control (design `LBPTopBar` pip; user
  // requirement「右上角只有縮小的元件」). Tapping it collapses the player into the
  // bottom-right floating preview (host-owned). info / share live in the side rail. Mute WAS the
  // tap-to-mute gesture on the video area (R23) — rb-flutter-gesture-clean-mode-v2 (R29) retired
  // that gesture (a short tap now toggles clean mode instead) and moved the mute operation here,
  // gated to only appear while [onToggleMute] is non-null (i.e. clean mode is active).

  Widget _minimizeButton() {
    // picture_in_picture_alt = the Material PiP-enter glyph (parity to the iOS SF
    // Symbol `pip.enter`): collapse into the bottom-right floating preview.
    // `_glassIconButton` is a shared helper → wrap (not key) so the minimize key is
    // specific to this button (KeyedSubtree → no RenderObject, golden byte-identical).
    //
    // rb-flutter-player-direct-close-button: [showCloseIcon] swaps the glyph for
    // `Icons.close` (same codepoint `FloatingWidgetView` / `MinimizedWidgetView` already
    // use) and the `Semantics.label` accordingly — a pure by-value presentation switch,
    // `onMinimize`'s trigger timing is unaffected. DEFAULT `false` keeps every EXISTING
    // call site / golden baseline byte-identical.
    return KeyedSubtree(
      key: LbTestKeys.playerMinimize,
      child: Semantics(
        label: minimizeButtonSemanticsLabel(showCloseIcon),
        button: true,
        child: _glassIconButton(
          showCloseIcon ? Icons.close : Icons.picture_in_picture_alt,
          onMinimize,
        ),
      ),
    );
  }

  /// The top-right button's semantics label, driven purely by [showCloseIcon]
  /// (rb-flutter-player-direct-close-button, parity iOS
  /// `minimizeButtonAccessibilityLabel`). Pure / deterministic — no widget dependency.
  static String minimizeButtonSemanticsLabel(bool showCloseIcon) =>
      showCloseIcon ? '關閉' : '最小化';

  /// The clean-mode-only mute-toggle button (rb-flutter-gesture-clean-mode-v2). Only ever
  /// composed by [build] while [onToggleMute] is non-null. Icon follows [muted] — parity
  /// `GestureMuteToastView` / `PlaybackPausedOverlayView`'s own `Icons.volume_off` /
  /// `Icons.volume_up` convention.
  Widget _muteButton() {
    return KeyedSubtree(
      key: LbTestKeys.playerHeaderMuteButton,
      child: _glassIconButton(
          muted ? Icons.volume_off : Icons.volume_up, onToggleMute),
    );
  }

  /// A 36×36 round glass icon button (live-chrome.jsx iconBtn). Always rendered so
  /// the chrome is visually complete; inert when its callback is null.
  Widget _glassIconButton(IconData icon, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _iconGlass,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20 * theme.fontScale, color: _onGlass),
      ),
    );
  }
}

// MARK: - _MarqueeTitleLoop (LBPMarqueeText overflow branch) — rb-flutter-marquee-title-scroll

/// The continuously-looping title marquee: the overflow branch of
/// [PlayerHeaderBarView._titleSlot]. Parity design `LBPMarqueeText`'s covered branch —
/// duplicate the text with a fixed gap, translate leftwards by exactly
/// `textWidth + gap` so the SECOND copy lands where the first started (a seamless loop,
/// the equivalent of the JSX's `-50%` of the doubled content, and of iOS
/// `MarqueeTitleLoopView` / Android `MarqueeLoop`'s identical target).
///
/// ── ANIMATION MECHANISM ──
///
/// `AnimationController` + `SingleTickerProviderStateMixin` + `.repeat()` — this
/// package's OWN established continuous-loop idiom (`productsheets/product_row.dart`'s
/// `_GridPlayButton`, `productsheets/sheet_scaffold.dart`'s `_bounceController`). The
/// `Timer.periodic` idiom in `moments/loading_mark_animation_view.dart` is deliberately
/// NOT reused: its own header comment says it exists for DISCRETE PNG-sequence frame
/// stepping, whereas this is CONTINUOUS interpolated motion.
///
/// ── WHY [animate] EXISTS (and what it is NOT) ──
///
/// [animate] gates ONLY whether the controller `.repeat()`s. It does NOT decide whether
/// this widget is built, does NOT touch the measurement, and does NOT change
/// [PlayerHeaderBarView.showsMarqueeTitle] — so it is NOT the kind of "caller preference
/// standing in for the measurement" flag the spec forbids.
///
/// It exists because an infinite `AnimationController.repeat()` re-schedules a frame on
/// every tick, which (a) makes `tester.pumpAndSettle()` THROW (measured during this
/// change; the same conclusion `loading_mark_animation_view.dart`'s header already
/// records) and (b) would make any golden depend on pump timing. So on the demo / golden
/// / widget-test path (`live == false`, the leaf DEFAULT) the loop renders its RESTING
/// FRAME — both copies laid out, offset `0`, first copy exactly over the base `Text` —
/// which is the same thing iOS's `ImageRenderer` captures (its `.onAppear` does not fire
/// there either). On the host-runtime path (`live == true`, which the turnkey container
/// `MinimalDesign.playerOverlay` hard-codes) it really scrolls.
class _MarqueeTitleLoop extends StatefulWidget {
  /// The title text — rendered TWICE (the loop's two copies).
  final String title;

  /// Exactly the base `Text`'s style (so both copies read identically to the static
  /// branch, and the resting frame overlaps the base pixel-for-pixel).
  final TextStyle style;

  /// The measured intrinsic single-line width; the loop travels `textWidth + gap`.
  final double textWidth;

  /// Fixed spacing between the two copies (design `gap = 36`).
  final double gap;

  /// One full loop's duration, `max(8, textWidth / 32)` seconds.
  final double durationSeconds;

  /// Host-runtime driver gate. `true` → `.repeat()`; `false` → resting frame, no ticks.
  final bool animate;

  const _MarqueeTitleLoop({
    required this.title,
    required this.style,
    required this.textWidth,
    required this.gap,
    required this.durationSeconds,
    required this.animate,
  });

  @override
  State<_MarqueeTitleLoop> createState() => _MarqueeTitleLoopState();
}

class _MarqueeTitleLoopState extends State<_MarqueeTitleLoop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  Duration get _loopDuration => Duration(
        microseconds:
            (widget.durationSeconds * Duration.microsecondsPerSecond).round(),
      );

  @override
  void initState() {
    super.initState();
    // The controller is ALWAYS created (an un-started one schedules no frames, so
    // `pumpAndSettle()` is unaffected); only `.repeat()` is gated.
    _controller = AnimationController(vsync: this, duration: _loopDuration);
    _syncDriver();
  }

  /// Start / stop the infinite loop to match [_MarqueeTitleLoop.animate], always
  /// returning to the resting offset when stopped.
  void _syncDriver() {
    if (widget.animate) {
      if (!_controller.isAnimating) _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0.0;
    }
  }

  @override
  void didUpdateWidget(covariant _MarqueeTitleLoop oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A new title ⇒ a new measured width ⇒ a new duration: restart from the top so the
    // loop stays seamless for the NEW text rather than finishing the old one's cycle.
    if (oldWidget.durationSeconds != widget.durationSeconds) {
      _controller.duration = _loopDuration;
      _controller.stop();
      _controller.value = 0.0;
      if (widget.animate) _controller.repeat();
      return;
    }
    if (oldWidget.animate != widget.animate) _syncDriver();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double travel = widget.textWidth + widget.gap;
    // `Positioned.fill` hands down TIGHT constraints (the base `Text`'s own resolved
    // box). `OverflowBox` re-opens the horizontal axis so the two copies can lay out at
    // their full natural width instead of overflowing the flex; `ClipRect` then clips
    // the result back to the slot, exactly like the design's `overflow: hidden` wrapper.
    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.centerLeft,
        minWidth: 0,
        maxWidth: double.infinity,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (BuildContext context, Widget? child) => Transform.translate(
            offset: Offset(-travel * _controller.value, 0),
            child: child,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.title,
                  maxLines: 1, softWrap: false, style: widget.style),
              SizedBox(width: widget.gap),
              Text(widget.title,
                  maxLines: 1, softWrap: false, style: widget.style),
            ],
          ),
        ),
      ),
    );
  }
}

// MARK: - Pure helpers

/// The ONE place the raw `extensions.video_title_scroll` wire value becomes a `bool`
/// (rb-flutter-marquee-title-scroll). Mirrors the design's `normalizeTitleScroll(raw)`
/// (`design/templates/minimal/sdk-components.jsx`, verbatim
/// `return !(raw === 0 || raw === '0' || raw === false);`), and is the Flutter
/// counterpart of iOS / Android `LBVideoTitleScroll.normalized(...)`.
///
/// Only three values turn scrolling OFF — `false`, the NUMBER zero (Dart's `0 == 0.0` is
/// `true`, so `int` `0` and `double` `0.0` / `-0.0` are all covered by the single
/// comparison), and the VERBATIM string `'0'`. Everything else returns `true`:
///
/// ```text
/// off : false | 0 | 0.0 | -0.0 | '0'
/// on  : null | missing key | true | 1 | 2 | -1 | 0.5 | '' | ' 0 ' | '0 ' | '00'
///       | '0.0' | '1' | 'false' | 'FALSE' | Map | List | any other type
/// ```
///
/// The comparison is STRICT: it does **not** trim surrounding whitespace, does **not**
/// case-fold and does **not** alias (`'false'` / `'off'` stay ON). Deliberately as
/// strict as the design so all four platforms land on the SAME value when the backend
/// emits a malformed one — precisely when a divergence is hardest to notice (the backend
/// passes `extensions` through RAW and normalizes nothing). The fallback lands on `true`
/// (scroll), the same side as the backend's own "unset ⇒ `1`" default.
///
/// Shape parity with this package's sibling `extensions` flag helper
/// [normalizeShowStock] — one raw `Object?` all the way down, one normalization point.
bool normalizeTitleScroll(Object? raw) {
  return !(raw == 0 || raw == '0' || raw == false);
}

/// Compact viewer-count formatting (e.g. `12345` → `12.3K`). Pure / deterministic.
/// Mirrors iOS `PlayerHeaderBarView.formatViewerCount` and Android
/// `formatViewerCount`.
String formatViewerCount(int count) {
  if (count < 1000) return count.toString();
  final thousands = count / 1000.0;
  // One decimal, trim trailing `.0` (e.g. 2000 → "2K", 12345 → "12.3K").
  final rounded = (thousands * 10).round() / 10.0;
  if (rounded == rounded.roundToDouble()) {
    return '${rounded.toInt()}K';
  }
  return '${rounded.toStringAsFixed(1)}K';
}
