import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show LBEndNavItem, LBEndHotItem, LBEndCountdown;

import '../productsheets/sheet_scaffold.dart' show liveProductImage;
import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';

// EndScreenView — family-4 moments surface 2 (full-screen END moment).
//
// Spec: `reference-ui-rendering/spec.md` (family-4 moments, full-screen END moment).
// Design: `design/templates/minimal/moments.jsx` `LBPEndScreen` (266-364) +
//          `LBPHotCard` (226-264).
// Parity: iOS `EndScreenView.swift`
//   (ios/Sources/LivebuyReferenceUI/Moments/EndScreenView.swift, rb-ios-moments §2)
//   and Android `EndScreenView.kt`
//   (android/livebuy-reference-ui/.../moments/EndScreenView.kt, rb-android-moments).
//   Golden parity name: `end-screen-countdown-variant` (countdown != null).
//
// The full-screen END moment shown when the video finishes. It is the second of the
// three family-4 moment surface widgets composed by `MomentsOverlayView`, and it
// implements the agreed SUB-VIEW INPUT PATTERN documented verbatim in
// `moments_view.dart`:
//
//   1. `theme:` (ReferenceUITheme, required)        — FIRST, always.
//   2. bound SNAPSHOT VALUES (read-only, BY VALUE from `MomentsModel` — never the
//      model, never the template):
//        • `countdown: LBEndCountdown?` — non-null ⇔ 倒數變體; `{ remain, total }`
//          drives the ring progress (`remain / total`). null ⇔ 熱門變體.
//        • `next: List<LBEndNavItem>`   — watch-next targets; `next.first` is the 倒
//          數變體 preview card source (`cover` placeholder / `title`). Empty `next`
//          also forces the 熱門變體.
//        • `hot: List<LBEndHotItem>`    — 熱門變體 set; rendered as `LBPHotCard`s in
//          a PLAIN `Row` FIXED SMALL set (first N). `duration` is an `int` in SECONDS
//          — formatted here to `mm:ss` (e.g. `28` → `"00:28"`).
//   3. action callbacks (LAST, each defaulting to null / no-op):
//        • `onWatchNext` — 倒數變體「立即觀看」CTA → host-wired → host → core
//          load(next videoId). This layer NEVER loads / advances itself.
//        • `onPickHot(item)` — 熱門變體 card tap → host-wired → host → core
//          load(hot.id). This layer NEVER switches videos itself.
//        • `onCancel` — 倒數變體「取消」exit → host-wired → host (dismiss / stay).
//
// VARIANT GATING (mirrors `LBPEndScreen`'s `showCountdown`, moments.jsx line 268):
//   • 倒數變體 — `countdown != null` AND `next` non-empty: a big `next.first` preview
//     card with a centered countdown RING (auto-advance-to-next) + 立即觀看 / 取消.
//   • 熱門變體 — `countdown == null` OR `next` empty: 為你推薦 header + a PLAIN `Row`
//     of `LBPHotCard`s, each tap → `onPickHot`.
//
// One-way data flow: this surface reads ONLY its passed-in values; it never reaches
// back into `MomentsModel` / `DefaultPlayerTemplate`, holds NO second copy of
// countdown / next / hot, and NEVER drives the auto-next countdown itself (core owns
// the tick — the ring is PURE PRESENTATION of the snapshot `remain` / `total`). It
// renders correctly with all actions null (so demo / golden / widget tests construct
// it action-free).
//
// VISUAL LANGUAGE: a full-bleed dark scrim (`rgba(8,8,12,0.8)`) with white text /
// glyphs (the moment composites over the ended video — design §2). The literal dark
// scrim + white-on-dark decorative colors are FIXED design colors lifted from
// `LBPEndScreen` via `colorFromHex` (consistent with the family-1/2/3 surfaces'
// surface-token approach); `theme.accent` paints the「立即觀看」CTA + the ring trim.
//
// RENDERING GOTCHAS (inherited from iOS / Android / family-1/2/3): plain Column / Row
// / Stack only — NO scrollable container (`ListView` / `GridView` /
// `SingleChildScrollView`). The auto-next countdown ring is self-drawn with
// `CustomPaint`; the 熱門 list is a PLAIN `Row` FIXED SMALL set (first N — NOT a
// `ListView` / `GridView`). No animation / no randomness so the golden is byte-stable.
//
// COVER IMAGES (rb-flutter-endscreen-recommended-video-cover): the two video cards —
// the 熱門卡 (`_hotCard`) and the 倒數變體 大預覽卡 (`_previewCard`) — are LIVE-GATED via
// the `live` flag. `live == false` (demo / golden) draws ONLY the deterministic black
// cover placeholder (no network → byte-stable golden); `live == true` (host runtime)
// overlays the real `cover` via the shared `liveProductImage` loader (mirrors the
// widget card `CarouselCardView` cover branch — `Image.network` + http→https +
// loading / error fallback to the placeholder). Flutter carries ONLY a `cover` (the
// `LBEndNavItem` / `LBEndHotItem` value types have NO `preview` field), so there is NO
// loop preview here — cover still image only (parity RN; iOS / Android add preview).

// MARK: - Decorative design tokens (literal moments.jsx hex via colorFromHex)
//
// accent comes from the resolved [ReferenceUITheme]; these are FIXED decorative
// colors lifted verbatim from `LBPEndScreen` / `LBPHotCard` (the dark-scrim moment is
// white-on-dark regardless of the host theme background — design §2). Kept consistent
// with the family-1/2/3 surfaces' surface-token approach (colorFromHex literals), and
// they mirror the iOS `EndScreenView` static colors + Android `EndScreenView`.

/// Full-bleed scrim base (`rgba(8,8,12,0.8)` → `#08080C` @ 0.8). Encoded as an
/// ARGB literal (alpha 0xCC ≈ 0.8) to match the family-1/2/3 surface-token style.
const Color _scrim = Color(0xCC08080C);

/// Faint on-dark rule line (`rgba(255,255,255,0.3)`; alpha 0x4D ≈ 0.3).
const Color _onDarkFaint = Color(0x4DFFFFFF);

/// Dim on-dark caption (`rgba(255,255,255,0.6)`; alpha 0x99 ≈ 0.6).
const Color _onDarkDim = Color(0x99FFFFFF);

/// Fainter on-dark meta / empty text (`rgba(255,255,255,0.5)`; alpha 0x80 ≈ 0.5).
const Color _onDarkFaintText = Color(0x80FFFFFF);

/// Translucent on-dark fill (button / pill `rgba(255,255,255,0.12)`; alpha 0x1F ≈ 0.12).
const Color _onDarkFill = Color(0x1FFFFFFF);

/// Translucent on-dark outline (`rgba(255,255,255,0.28)`; alpha 0x47 ≈ 0.28).
const Color _onDarkStroke = Color(0x47FFFFFF);

/// Countdown ring faint track (`rgba(255,255,255,0.28)`; alpha 0x47 ≈ 0.28).
const Color _ringTrack = Color(0x47FFFFFF);

/// Cover placeholder body (the 9:16 preview / hot card background — `#000`).
const Color _coverBg = Color(0xFF000000);

/// Dark veil over the preview cover (`rgba(0,0,0,0.4)`; alpha 0x66 ≈ 0.4).
const Color _coverVeil = Color(0x66000000);

/// Center play affordance circle on a cover (`rgba(0,0,0,0.5)`; alpha 0x80 ≈ 0.5).
const Color _playCircle = Color(0x80000000);

/// Duration pill capsule on a cover (`rgba(0,0,0,0.55)`; alpha 0x8C ≈ 0.55).
const Color _durationPill = Color(0x8C000000);

/// FIXED SMALL hot set cap — a PLAIN `Row` of a bounded N (NEVER lazy / scroll).
const int _maxHotCards = 3;

// MARK: - Fixed localized copy (static presentation strings — parity to iOS/Android)

const String _endedLabel = '影片結束';
/// No-countdown LIVE-ENDED title (end-screen-no-countdown). Parity iOS / Android / RN.
const String _liveEndedLabel = '直播已結束';
const String _autoPlayPrefix = '秒後自動播放下一支'; // "{remain} {秒後自動播放下一支}"
const String _untitledNext = '下一支影片';
const String _cancelLabel = '取消';
const String _watchNextLabel = '立即觀看';
const String _recommendTitle = '為你推薦';
const String _shuffleLabel = '換一批';
const String _emptyHotLabel = '目前沒有推薦影片';

/// Format `int` seconds → `mm:ss` (for `LBEndHotItem.duration`, which IS seconds —
/// reference-ui formats it, e.g. `28` → `"00:28"`, `2316` → `"38:36"`). Pure /
/// deterministic. Mirrors iOS `EndScreenView.formatSeconds` / Android
/// `formatNavDuration`.
String _formatSeconds(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final m = s ~/ 60;
  final r = s % 60;
  return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
}

// MARK: - 熱門變體「換一批」本地視窗輪播 (rb-flutter-endscreen-reshuffle-local-window)
//
// The 熱門變體「換一批」pill is a LOCAL recommendation-window carousel — it advances a
// local `_hotPage` window within the ALREADY-LOADED `hot` list, and NEVER opens /
// switches a video (mirrors iOS `860cd5b9` / Android `3bab95f7` / RN `e4d065c1` — the
// four-platform reshuffle收官). The design's pill (`moments.jsx`) is a refresh-glyph
// no-op stub (`onPickHot={() => {}}`, never wired to open a video); all four
// reference-uis had earlier mis-forwarded it as `onPickHot(hot.first)` (the same
// four-platform proxy bug). `hot` is fetched once at channel load, is often > 3, and
// core has NO re-fetch API / no backend reshuffle endpoint — so a local window is the
// correct minimal fix (zero core / view-model / container / backend).

/// Number of 3-per-page windows for a `hot` list of [len] items. `len <= 0 → 0`;
/// otherwise `ceil(len / _maxHotCards)`. Pure / deterministic — the pill is inert
/// (single page) when this is `<= 1`. Mirrors iOS/Android/RN `pageCount`.
///
/// `@visibleForTesting` (not part of the stable package API — parity to iOS `internal`
/// / RN exported test helper): production callers are the「換一批」pill + `_hotRow`
/// inside THIS library; external references are analyzer-flagged outside tests.
@visibleForTesting
int pageCount(int len) => len <= 0 ? 0 : (len / _maxHotCards).ceil();

/// The [page]-th 3-item window of [hot]. `start = page * size`; an out-of-range
/// [page] (`page < 0` or `start >= hot.length`) safely falls back to the FIRST page
/// (`hot.take(size)`) so a stale index never crashes. `page == 0` is IDENTICAL to the
/// prior `hot.take(size)` (default → baseline byte-identical). Pure / deterministic.
/// Mirrors iOS/Android/RN `hotWindow`.
///
/// `@visibleForTesting` (see [pageCount]).
@visibleForTesting
List<LBEndHotItem> hotWindow(List<LBEndHotItem> hot, int page,
    {int size = _maxHotCards}) {
  final start = page * size;
  if (page < 0 || start >= hot.length) {
    return hot.take(size).toList(growable: false);
  }
  return hot.sublist(start, math.min(start + size, hot.length));
}

/// The family-4 full-screen END moment. In the 倒數變體 (`countdown != null` &&
/// `next` non-empty) it draws a big `next.first` preview card with a centered
/// countdown RING (`remain / total`) representing the auto-advance-to-next countdown,
/// plus 立即觀看 ([onWatchNext]) / 取消 ([onCancel]). In the 熱門變體 (`countdown ==
/// null` || `next` empty) it draws a 為你推薦 header + a PLAIN `Row` of `LBPHotCard`s
/// ([onPickHot]). All actions are host-wired forwarders; this layer never loads /
/// advances / picks itself.
class EndScreenView extends StatefulWidget {
  /// The resolved reference-ui theme (FIRST parameter, always).
  final ReferenceUITheme theme;

  /// Auto-next countdown snapshot (`MomentsModel.countdown`). Non-null ⇔ 倒數變體;
  /// `{ remain, total }` drives the ring progress. Read-only.
  final LBEndCountdown? countdown;

  /// Watch-next targets (`MomentsModel.next`). `next.first` is the 倒數變體 preview
  /// card source. Empty also forces the 熱門變體. Read-only.
  final List<LBEndNavItem> next;

  /// 熱門推薦 set (`MomentsModel.hot`). Rendered as a FIXED SMALL PLAIN `Row` of
  /// `LBPHotCard`s. `duration` is an `int` in SECONDS — formatted to `mm:ss`.
  /// Read-only.
  final List<LBEndHotItem> hot;

  /// 倒數變體「立即觀看」CTA → host-wired → host → core load(next). null for demo /
  /// golden instances — the CTA is inert. This layer NEVER loads / advances itself.
  final void Function()? onWatchNext;

  /// 熱門變體 card tap → host-wired `onPickHot(item)` → host → core load(hot.id).
  /// null for demo / golden instances. This layer NEVER switches videos itself.
  final void Function(LBEndHotItem item)? onPickHot;

  /// 倒數變體「取消」exit → host-wired → host (dismiss / stay). null for demo /
  /// golden instances.
  final void Function()? onCancel;

  /// No-countdown LIVE-ENDED state (`endScreenVisible && countdown == null`, i.e. live
  /// ended with no next). The 熱門變體 then prepends a「直播已結束」rule-flanked title
  /// (end-screen-no-countdown). Default `false` → existing 熱門變體 demo / golden
  /// unchanged. No ring, no auto-advance. Parity iOS / Android / RN `liveEnded`.
  final bool liveEnded;

  /// Real-image gate for the two video cards' `cover`
  /// (rb-flutter-endscreen-recommended-video-cover). `live == false` (demo / golden /
  /// standalone) → the 熱門卡 / 大預覽卡 draw ONLY the black cover placeholder (no
  /// network → byte-stable golden). `live == true` (host runtime, composited over a
  /// real video surface) → `liveProductImage` overlays the real `cover` (mirrors the
  /// widget card `CarouselCardView` cover branch). Default `false`. Threaded from the
  /// turnkey container (`MinimalDesign.playerOverlay` → `MomentsOverlayView`), parity
  /// iOS / Android / RN. Flutter is cover-only (value types carry NO `preview`).
  final bool live;

  const EndScreenView({
    super.key,
    required this.theme,
    required this.countdown,
    required this.next,
    required this.hot,
    this.onWatchNext,
    this.onPickHot,
    this.onCancel,
    this.liveEnded = false,
    this.live = false,
  });

  @override
  State<EndScreenView> createState() => _EndScreenViewState();
}

class _EndScreenViewState extends State<EndScreenView> {
  /// Local 熱門變體 recommendation-window index (pure presentation, default `0`; NOT
  /// part of the widget config / constructor). The「換一批」pill advances this within
  /// the already-loaded `widget.hot` list (每頁 `_maxHotCards` 張) — it NEVER opens a
  /// video. `_hotPage == 0` shows the first 3 → baseline byte-identical. Mirrors iOS
  /// `@State hotPage` / Android `remember { mutableStateOf(0) }` / RN `useState(0)`.
  int _hotPage = 0;

  /// Whether the 倒數變體 is active — `countdown != null` AND a preview target exists
  /// (mirrors `LBPEndScreen`'s `showCountdown`, moments.jsx line 268).
  bool get _showCountdown =>
      widget.countdown != null && widget.next.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      key: LbTestKeys.momentEnd,
      style: TextStyle(
        color: Colors.white,
        fontSize: 14 * widget.theme.fontScale,
        decoration: TextDecoration.none,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Full-bleed dark scrim (LBPEndScreen `rgba(8,8,12,0.8)`). The moment
          // composites over the ended video — a fixed design color, not theme bg.
          Container(color: _scrim),
          if (_showCountdown)
            _buildCountdownVariant(context)
          else
            _buildHotVariant(context),
        ],
      ),
    );
  }

  // MARK: - 倒數變體 (preview card + ring + 立即觀看 / 取消)
  //
  // Mirrors `LBPEndScreen`'s `showCountdown` branch (moments.jsx 284-339):
  //   • 「— 影片結束 —」rule-flanked label.
  //   • a 150×(9:16) preview card of `next.first` with a centered countdown ring.
  //   • 「{remain} 秒後自動播放下一支」+ the next title + the design's
  //     「{shopName} · {duration}」meta line (now renderable since
  //     align-endscreen-nav-meta-template added shopName / duration to LBEndNavItem;
  //     the meta line is drawn only when at least one field is host-fed).
  //   • 取消 (outline) / 立即觀看 (accent, play glyph) buttons.

  Widget _buildCountdownVariant(BuildContext context) {
    // next.first is guaranteed present here (_showCountdown gates on next non-empty).
    final n0 = widget.next.first;
    final remain = widget.countdown?.remain ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _endedRule(),
          const SizedBox(height: 20),
          _previewCard(n0, remain),
          const SizedBox(height: 14),
          _previewCaption(n0, remain),
          const SizedBox(height: 20),
          _countdownActions(),
        ],
      ),
    );
  }

  /// 「— {label} —」rule-flanked caption (LBPEndScreen 287-291). [label] defaults to
  /// 「影片結束」for the countdown variant; the no-countdown LIVE-ENDED hot variant passes
  /// [_liveEndedLabel] (end-screen-no-countdown). Same rendering → existing goldens
  /// byte-identical. Parity iOS / Android / RN `EndedRule(label)`.
  Widget _endedRule({String label = _endedLabel}) {
    Widget rule() => Container(width: 18, height: 1, color: _onDarkFaint);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        rule(),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12 * widget.theme.fontScale,
            fontWeight: FontWeight.w600,
            color: _onDarkDim,
            letterSpacing: 1,
            decoration: TextDecoration.none,
          ),
        ),
        const SizedBox(width: 8),
        rule(),
      ],
    );
  }

  /// The 150×(9:16) preview card with the centered countdown ring (LBPEndScreen
  /// 295-314). The cover is LIVE-GATED: `live == false` (demo / golden) → only the
  /// black placeholder; `live == true` (runtime) → the real `n0.cover` over the
  /// placeholder (shared `liveProductImage`). The dark veil + ring + remaining seconds
  /// are drawn centered ABOVE the cover.
  Widget _previewCard(LBEndNavItem n0, int remain) {
    const w = 150.0;
    const h = w * 16 / 9;
    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: _coverBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x80000000), // black @ 0.5 (alpha 0x80)
            blurRadius: 40,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 9:16 cover — live-gated: real `n0.cover` at runtime over the black
            // placeholder; placeholder-only at demo / golden (no network). Clipped by
            // the enclosing ClipRRect (16). Mirrors CarouselCardView cover branch.
            liveProductImage(
              live: widget.live,
              url: n0.cover,
              placeholder: Container(color: _coverBg),
              fit: BoxFit.cover,
            ),
            // Dark veil over the cover (`rgba(0,0,0,0.4)`).
            Container(color: _coverVeil),
            // Centered countdown ring + remaining seconds.
            Center(child: _countdownRing(remain)),
          ],
        ),
      ),
    );
  }

  /// The auto-advance-to-next countdown RING (LBPEndScreen 298-313). Per the design
  /// recipe: a faint full track circle + an accent arc `from top, swept by
  /// progress = remain / total`, with `remain` centered. The ring is PURE
  /// PRESENTATION of the snapshot — this layer NEVER ticks it. Self-drawn with
  /// `CustomPaint` (no animation), mirroring iOS `Circle().trim` + Android `Canvas`.
  Widget _countdownRing(int remain) {
    final total = widget.countdown?.total ?? 0;
    final raw = total > 0 ? remain / total : 0.0;
    final progress = raw.clamp(0.0, 1.0).toDouble();
    return SizedBox(
      width: 72,
      height: 72,
      child: CustomPaint(
        painter: _CountdownRingPainter(
          progress: progress,
          trackColor: _ringTrack,
          arcColor: widget.theme.accent,
          strokeWidth: 4,
        ),
        child: Center(
          child: Text(
            '$remain',
            style: TextStyle(
              fontSize: 26 * widget.theme.fontScale,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }

  /// Preview caption block (LBPEndScreen 315-322): the auto-play line + the next
  /// title (2-line clamp). The Flutter `LBEndNavItem` carries no shopName / duration,
  /// so the design's「{shop_name} · {duration}」meta line has no source here and is
  /// intentionally omitted (the title + auto-play line carry the moment).
  Widget _previewCaption(LBEndNavItem n0, int remain) {
    final title = n0.title.isEmpty ? _untitledNext : n0.title;
    // 「{shopName} · {mm:ss}」meta line (LBPEndScreen moments.jsx:321) — now
    // renderable since align-endscreen-nav-meta-template added shopName / duration to
    // LBEndNavItem. Drawn only when at least one field is present (host-fed).
    final hasMeta = n0.shopName.isNotEmpty || n0.duration > 0;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$remain $_autoPlayPrefix',
            style: TextStyle(
              fontSize: 12 * widget.theme.fontScale,
              color: _onDarkDim,
              decoration: TextDecoration.none,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15 * widget.theme.fontScale,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.4,
              decoration: TextDecoration.none,
            ),
          ),
          if (hasMeta) ...[
            const SizedBox(height: 4),
            Text(
              _metaLine(n0),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12 * widget.theme.fontScale,
                color: _onDarkDim,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 「{shopName} · {mm:ss}」preview meta (LBPEndScreen moments.jsx:321). Joins the
  /// two host-fed `LBEndNavItem` fields with「 · 」, omitting an absent side.
  String _metaLine(LBEndNavItem n0) {
    final parts = <String>[
      if (n0.shopName.isNotEmpty) n0.shopName,
      if (n0.duration > 0) _formatSeconds(n0.duration),
    ];
    return parts.join(' · ');
  }

  /// 取消 (outline) / 立即觀看 (accent + play glyph) action row (LBPEndScreen
  /// 325-338). Each forwards to its host-wired callback; this layer never advances.
  Widget _countdownActions() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Row(
        children: [
          // 取消 — translucent outline button.
          Expanded(
            child: _DarkButton(
              key: LbTestKeys.momentEndCancel,
              label: _cancelLabel,
              fontScale: widget.theme.fontScale,
              fill: _onDarkFill,
              borderColor: _onDarkStroke,
              onTap: widget.onCancel,
            ),
          ),
          const SizedBox(width: 10),
          // 立即觀看 — accent filled button with a play glyph.
          Expanded(
            child: _DarkButton(
              key: LbTestKeys.momentEndWatch,
              label: _watchNextLabel,
              fontScale: widget.theme.fontScale,
              fill: widget.theme.accent,
              leading: const Icon(Icons.play_arrow, size: 16, color: Colors.white),
              onTap: widget.onWatchNext,
            ),
          ),
        ],
      ),
    );
  }

  // MARK: - 熱門變體 (為你推薦 header + PLAIN Row of LBPHotCards)
  //
  // Mirrors `LBPEndScreen`'s 熱門 branch (moments.jsx 340-361): a「為你推薦」title +
  // a「換一批」pill, then the `hot` cards. The design uses a 2-col grid in a scroll;
  // the reference-ui surface renders a FIXED SMALL set in a PLAIN `Row` (NEVER lazy /
  // scroll — the verified family lesson). A drop-in 熱門 set is short; a very long set
  // is a documented follow-up (host can wrap its own).

  Widget _buildHotVariant(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 18, right: 18, top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // end-screen-no-countdown: live ended with no next →「直播已結束」rule-flanked
          // title (same rendering as the countdown variant's「影片結束」) above 為你推薦.
          if (widget.liveEnded) ...[
            Center(child: _endedRule(label: _liveEndedLabel)),
            const SizedBox(height: 14),
          ],
          _hotHeader(),
          const SizedBox(height: 12),
          _hotRow(),
        ],
      ),
    );
  }

  /// 為你推薦 title + 換一批 pill (LBPEndScreen 343-355). The「換一批」pill is a LOCAL
  /// recommendation-window carousel (rb-flutter-endscreen-reshuffle-local-window): its
  /// `onTap` advances `_hotPage` within the already-loaded `widget.hot` list (每頁
  /// `_maxHotCards` 張) and NEVER opens / switches a video — it does NOT call
  /// `onPickHot`. `onTap` is ALWAYS non-null; a body `if (pageCount > 1)` guard short-
  /// circuits when `hot.length <= 3`（單頁、無可換）→ inert no-op WITHOUT any disabled
  /// visual (a `GestureDetector.onTap == null` changes no pixels in Flutter, but the
  /// non-null-onTap + guard form keeps the hit region constant across all `hot` sizes
  /// and matches the iOS/Android/RN inert 語意 — baseline byte-identical). The design's
  /// pill is a refresh-glyph no-op stub (`onPickHot={() => {}}`, never opens a video);
  /// all four reference-uis had mis-forwarded it as `onPickHot(hot.first)` (四端同款
  /// proxy bug — this is the Flutter parity收官, iOS 860cd5b9 / Android 3bab95f7 / RN
  /// e4d065c1). The 熱門卡 tap (`_hotCard`) keeps `onPickHot` (open a video) — decoupled
  /// from this pill.
  Widget _hotHeader() {
    return Row(
      children: [
        Text(
          _recommendTitle,
          style: TextStyle(
            fontSize: 18 * widget.theme.fontScale,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: -0.2,
            decoration: TextDecoration.none,
          ),
        ),
        const Spacer(),
        GestureDetector(
          key: LbTestKeys.momentEndReshuffle,
          behavior: HitTestBehavior.opaque,
          // Local window advance ONLY — never opens a video (never calls onPickHot).
          // Always non-null; guard short-circuits to inert no-op for a single page
          // (`hot.length <= 3`) with no disabled visual → baseline byte-identical.
          onTap: () {
            final pages = pageCount(widget.hot.length);
            if (pages > 1) {
              setState(() => _hotPage = (_hotPage + 1) % pages);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _onDarkFill,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.refresh, size: 13, color: Colors.white),
                const SizedBox(width: 5),
                Text(
                  _shuffleLabel,
                  style: TextStyle(
                    fontSize: 12 * widget.theme.fontScale,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// A PLAIN `Row` of `LBPHotCard`s — a FIXED SMALL set (the current 3-per-page window
  /// `_hotWindow(widget.hot, _hotPage)`), NEVER a lazy / scroll container. `_hotPage ==
  /// 0` shows the first 3 → baseline byte-identical; the「換一批」pill advances the
  /// window. Each card taps to `onPickHot(item)` (open a video — decoupled from pill).
  Widget _hotRow() {
    if (widget.hot.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Text(
            _emptyHotLabel,
            style: TextStyle(
              fontSize: 13 * widget.theme.fontScale,
              color: _onDarkFaintText,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      );
    }
    final cards = hotWindow(widget.hot, _hotPage);
    return Row(
      key: LbTestKeys.momentEndHotRow,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: _hotCard(cards[i], LbTestKeys.momentHotCard(i))),
        ],
      ],
    );
  }

  /// One 熱門卡 (LBPHotCard, moments.jsx 226-264): a 9:16 cover with a duration pill
  /// (top-left) + a centered play affordance, then a 2-line title. `duration` is an
  /// `int` in SECONDS — formatted to `mm:ss` here (unlike the iOS `LBHotItem.duration`
  /// which is an already-formatted string; the Flutter `LBEndHotItem.duration` is an
  /// `int` per the view-model, so we format it). The cover is LIVE-GATED: `live ==
  /// false` (demo / golden) → only the black placeholder; `live == true` (runtime) →
  /// the real `item.cover` over the placeholder (shared `liveProductImage`).
  Widget _hotCard(LBEndHotItem item, Key key) {
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: () => widget.onPickHot?.call(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 9 / 16,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 9:16 cover — live-gated: real `item.cover` at runtime over the
                  // black placeholder; placeholder-only at demo / golden (no network).
                  // Clipped by the enclosing ClipRRect (12).
                  liveProductImage(
                    live: widget.live,
                    url: item.cover,
                    placeholder: Container(color: _coverBg),
                    fit: BoxFit.cover,
                  ),
                  // Centered play affordance (`rgba(0,0,0,0.5)` circle + play glyph).
                  Center(
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _playCircle,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow,
                          size: 18, color: Colors.white),
                    ),
                  ),
                  // Duration pill (top-left, `rgba(0,0,0,0.55)`).
                  Positioned(
                    top: 6,
                    left: 6,
                    child: _durationPillWidget(_formatSeconds(item.duration)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12 * widget.theme.fontScale,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              height: 1.3,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }

  /// Duration pill (LBPHotCard 232-241) — a play glyph + the formatted `mm:ss` over a
  /// translucent dark capsule.
  Widget _durationPillWidget(String text) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 2, 6, 2),
      decoration: BoxDecoration(
        color: _durationPill,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.play_arrow, size: 10, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 10 * widget.theme.fontScale,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

// MARK: - Private widgets

/// A dark-scrim action button (取消 outline / 立即觀看 accent). Forwards [onTap]
/// (null → inert). Drawn as a plain padded capsule with an optional [leading] glyph.
class _DarkButton extends StatelessWidget {
  final String label;
  final double fontScale;
  final Color fill;
  final Color? borderColor;
  final Widget? leading;
  final void Function()? onTap;

  const _DarkButton({
    super.key,
    required this.label,
    required this.fontScale,
    required this.fill,
    this.borderColor,
    this.leading,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(12),
          border: borderColor != null
              ? Border.all(color: borderColor!, width: 1)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 15 * fontScale,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Self-drawn auto-next countdown ring: a faint full track + an accent arc swept by
/// [progress] (`remain / total`), starting from 12 o'clock and going clockwise.
/// PURE PRESENTATION — never animates / ticks; the snapshot drives [progress].
/// Mirrors iOS `Circle().trim(from:0,to:progress)` + Android `Canvas.drawArc`.
class _CountdownRingPainter extends CustomPainter {
  final double progress;
  final Color trackColor;
  final Color arcColor;
  final double strokeWidth;

  _CountdownRingPainter({
    required this.progress,
    required this.trackColor,
    required this.arcColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );

    // Faint full track (`stroke rgba(255,255,255,0.28) 4`).
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = trackColor;
    canvas.drawArc(rect, 0, 6.283185307179586, false, track);

    // Accent remaining arc (`stroke accent 4 round`), from top (-90°), clockwise.
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = arcColor;
    const startAngle = -1.5707963267948966; // -90° → 12 o'clock
    final sweep = 6.283185307179586 * progress;
    canvas.drawArc(rect, startAngle, sweep, false, arc);
  }

  @override
  bool shouldRepaint(covariant _CountdownRingPainter old) =>
      old.progress != progress ||
      old.trackColor != trackColor ||
      old.arcColor != arcColor ||
      old.strokeWidth != strokeWidth;
}
