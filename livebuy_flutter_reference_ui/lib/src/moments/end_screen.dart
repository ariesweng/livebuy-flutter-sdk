import 'package:flutter/material.dart';
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show LBEndNavItem, LBEndCountdown;

import '../productsheets/sheet_scaffold.dart' show liveProductImage;
import '../productsheets/cart_fill_glyph.dart' show CartFillGlyph;
import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';

// EndScreenView — family-4 moments surface 2 (full-screen END moment, LIVE-only).
//
// Spec: `component-contracts/spec.md` "EndScreen 元件契約" (this surface's rendering
// half) + `reference-ui-rendering/spec.md` (family-4 moments, full-screen END moment).
// Design: `design/templates/minimal/moments.jsx` `LBPEndScreen` (rb-flutter-endscreen-
// live-empty-state; R41 / D7 of `design/contract/claude-design-sync.md`, commit
// `c480363ad` — the「為你推薦」熱門變體 grid + `LBPHotCard` were REMOVED upstream and
// this surface follows). Parity: iOS `EndScreenView.swift` / Android
// `EndScreenView.kt` (this specific redesign is Flutter-only as of this change — the
// other three platforms are documented follow-ups, see this change's proposal.md).
//
// The full-screen END moment shown when a LIVE broadcast finishes. It is the second
// of the three family-4 moment surface widgets composed by `MomentsOverlayView`, and
// it implements the agreed SUB-VIEW INPUT PATTERN documented verbatim in
// `moments_view.dart`:
//
//   1. `theme:` (ReferenceUITheme, required)        — FIRST, always.
//   2. bound SNAPSHOT VALUES (read-only, BY VALUE from `MomentsModel` — never the
//      model, never the template):
//        • `countdown: LBEndCountdown?` — non-null ⇔ 倒數變體; `{ remain, total }`
//          drives the ring progress (`remain / total`). null / empty `next` ⇔
//          空狀態 (liveEmpty).
//        • `next: List<LBEndNavItem>`   — watch-next targets; `next.first` is the 倒
//          數變體 preview card source (`cover` placeholder / `title`). Empty `next`
//          forces the 空狀態.
//   3. action callbacks (LAST, each defaulting to null / no-op):
//        • `onWatchNext` — 倒數變體「立即觀看」CTA → host-wired → host → core
//          load(next videoId). This layer NEVER loads / advances itself.
//        • `onCancel` — 倒數變體「取消」exit → host-wired. `MomentsOverlayView`
//          (the container) now treats this as "close the WHOLE end-screen overlay"
//          (there is no longer a 熱門 fallback to drop back to) — this surface
//          itself does not know or care what the host does with the tap; it only
//          forwards it.
//        • `onViewCart` — 空狀態「查看購物車」CTA → host-wired; the container's
//          default forwards to core `Player.requestViewCart()` — the SAME seam the
//          product list / detail sheet's own cart CTA already uses
//          (`DefaultPlayerTemplate.openCart()` → `viewCartRequester`), dispatching
//          the notification-type `VIEW_CART` event (`event-interceptor` spec). The
//          template owns no cart page — the host is the sole handler.
//
// VARIANT GATING (mirrors `LBPEndScreen`'s `isEmpty = variant === 'liveEmpty'`,
// moments.jsx `164-165`, which for this reference-ui's two-input shape collapses to
// "does a countdown target exist"):
//   • 倒數變體 — `countdown != null` AND `next` non-empty: a big `next.first` preview
//     card with a centered countdown RING (auto-advance-to-next) + 立即觀看 / 取消.
//     UNCHANGED by this redesign.
//   • 空狀態 (liveEmpty) — `countdown == null` OR `next` empty: large「直播已結束」
//     title + 「直播時長：HH:MM:SS」 caption + a full-width「查看購物車」CTA. NO
//     card wall, NO countdown ring, NO 熱門 recommendations — replaces the retired
//     熱門變體 entirely (moments.jsx no longer has an `LBPHotCard` / 為你推薦 branch
//     at all, R41).
//
// LIVE-ONLY, ENFORCED BY THE CONTAINER, NOT THIS WIDGET: `MomentsOverlayView` only
// ever constructs this widget while the Player is in the (live-only) `endScreenShown`
// sub-state (`live-end-no-next-endstate` — a VOD/回放 ending never enters that state;
// it either auto-advances silently when it has a `next`, or rests in the DISTINCT
// `ended` state, per `vod-replay-direct-next`). The container reacts to a VOD/回放
// settling into `ended` with no next by triggering the SAME "close the player" exit
// `PlayerShellView.onCloseRequest` uses (`swipe-nav-close-on-empty` precedent) instead
// of ever building this widget — so this file itself needs NO `isLive` check of its
// own; the fact that it was constructed at all already means "this was a live end".
//
// 直播時長 (liveDuration): `component-contracts/spec.md` documents `live_time`'s wire
// semantics as UNKNOWN / unreliable ("SDK v1 不依此欄位做業務邏輯" — a measured
// 58885224 for a 38s video) and NO platform threads it into any UI today. This surface
// therefore accepts an OPTIONAL [liveDuration] string (host-fed, already formatted;
// default `''`) and renders the design's own `'--:--:--'` fallback when it is empty —
// `MomentsOverlayView` does not yet pass a real value (no reliable source exists), so
// in practice this always renders the placeholder until a future change wires one.
//
// One-way data flow: this surface reads ONLY its passed-in values; it never reaches
// back into `MomentsModel` / `DefaultPlayerTemplate`, holds NO second copy of
// countdown / next, and NEVER drives the auto-next countdown itself (core owns the
// tick — the ring is PURE PRESENTATION of the snapshot `remain` / `total`). It renders
// correctly with all actions null (so demo / golden / widget tests construct it
// action-free). Stateless — the retired 熱門變體's `_hotPage` reshuffle-window state
// was the only local mutable state this surface ever held.
//
// VISUAL LANGUAGE: a full-bleed scrim (`rgba(50,50,50,0.64)`, no blur — moments.jsx
// `173`; CHANGED from the prior `rgba(8,8,12,0.8)` dark-glass scrim by this redesign)
// with white text / glyphs (the moment composites over the ended video — design §2).
// The literal scrim + white-on-dark decorative colors are FIXED design colors lifted
// from `LBPEndScreen` via `colorFromHex` (consistent with the family-1/2/3 surfaces'
// surface-token approach); `theme.accent` paints the「立即觀看」/「查看購物車」CTAs +
// the ring trim.
//
// RENDERING GOTCHAS (inherited from iOS / Android / family-1/2/3): plain Column / Row
// / Stack only — NO scrollable container (`ListView` / `GridView` /
// `SingleChildScrollView`). The auto-next countdown ring is self-drawn with
// `CustomPaint`. No animation / no randomness so the golden is byte-stable.
//
// COVER IMAGES (rb-flutter-endscreen-recommended-video-cover): the 倒數變體 大預覽卡
// (`_previewCard`) is LIVE-GATED via the `live` flag. `live == false` (demo / golden)
// draws ONLY the deterministic black cover placeholder (no network → byte-stable
// golden); `live == true` (host runtime) overlays the real `cover` via the shared
// `liveProductImage` loader (mirrors the widget card `CarouselCardView` cover branch —
// `Image.network` + http→https + loading / error fallback to the placeholder).
// Flutter carries ONLY a `cover` (`LBEndNavItem` has NO `preview` field), so there is
// NO loop preview here — cover still image only (parity RN; iOS / Android add
// preview).

// MARK: - Decorative design tokens (literal moments.jsx hex via colorFromHex)
//
// accent comes from the resolved [ReferenceUITheme]; these are FIXED decorative
// colors lifted verbatim from `LBPEndScreen` (the dark moment is white-on-dark
// regardless of the host theme background — design §2). Kept consistent with the
// family-1/2/3 surfaces' surface-token approach (colorFromHex literals), and they
// mirror the iOS `EndScreenView` static colors + Android `EndScreenView`.

// moments.jsx (line 173) applies ONE shared scrim — `rgba(50,50,50,0.64)`, no
// blur — OUTSIDE the `isEmpty` ternary (moments.jsx:180), i.e. BOTH variants
// share the exact same value; it is not two independent per-variant tokens.
// Flutter's render tree mirrors that literally: a SINGLE full-bleed `Container`
// painted once in `build`, shared by both branches (see `build` below).
//
// Applying this DOES repaint the countdown variant's background too, which
// made the EXISTING `end-screen-countdown-variant.png` golden stale (verified
// 86% pixel diff) when this scrim value first shipped (rb-flutter-endscreen-
// live-empty-state, commit `181dff491`). That was accepted, not worked around:
// the "don't touch existing baselines" rule protects the PNG FILE from being
// overwritten / deleted — it does NOT license silently diverging the rendered
// pixels from the design to keep an old file green. That change deliberately
// left the stale golden exactly as it was on disk (not regenerated, not
// deleted), for "a human [to decide] whether/when to regenerate it" later.
// `fix-flutter-endscreen-countdown-golden` IS that later regeneration: the
// golden now reflects this scrim value (see `test/moments/end_screen_test
// .dart`'s golden group for the Flutter-side note). Parity iOS
// `rb-ios-endscreen-live-empty-state` (commit `fb585fef7`, archived) hit the
// identical conflict and made the same call for its own snapshot; that
// platform's own regeneration timeline is independent of this one.

/// Full-bleed scrim (`rgba(50,50,50,0.64)`, moments.jsx `173`). Encoded as an
/// ARGB literal (`0.64 * 255 ≈ 163 = 0xA3`) to match the family-1/2/3
/// surface-token style. Shared by BOTH variants (see the block comment above
/// for why, and for the `end-screen-countdown-variant.png` golden's staleness
/// / regeneration history).
/// CHANGED by rb-flutter-endscreen-live-empty-state from the prior
/// `rgba(8,8,12,0.8)` dark-glass scrim (`Color(0xCC08080C)`).
const Color _scrim = Color(0xA3323232);

/// Faint on-dark rule line (`rgba(255,255,255,0.3)`; alpha 0x4D ≈ 0.3).
const Color _onDarkFaint = Color(0x4DFFFFFF);

// NOTE: moments.jsx's caption line (212) actually specifies `rgba(255,255,255,
// 0.62)`, but — same as `_autoPlayPrefix`'s doc above — this is unrelated,
// undocumented drift NOT reflected on iOS (`onDarkDim = Color.white.opacity(0.6)`,
// `EndScreenView.swift:482`) / Android, and outside R41's scope. Kept at the
// existing 0.6 four-platform-parity value (byte-stable against the untouched
// `end-screen-countdown-variant` golden).
/// Dim on-dark caption (`rgba(255,255,255,0.6)`; alpha 0x99 ≈ 0.6).
const Color _onDarkDim = Color(0x99FFFFFF);

/// Translucent on-dark fill (button `rgba(255,255,255,0.12)`; alpha 0x1F ≈ 0.12).
const Color _onDarkFill = Color(0x1FFFFFFF);

/// Translucent on-dark outline (`rgba(255,255,255,0.28)`; alpha 0x47 ≈ 0.28).
const Color _onDarkStroke = Color(0x47FFFFFF);

/// Countdown ring faint track (`rgba(255,255,255,0.28)`; alpha 0x47 ≈ 0.28).
const Color _ringTrack = Color(0x47FFFFFF);

/// Cover placeholder body (the 9:16 preview background — `#000`).
const Color _coverBg = Color(0xFF000000);

/// Dark veil over the preview cover (`rgba(0,0,0,0.4)`; alpha 0x66 ≈ 0.4).
const Color _coverVeil = Color(0x66000000);

/// 空狀態 title text-shadow (`0 2px 10px rgba(0,0,0,0.4)`, moments.jsx `240`).
const List<Shadow> _titleShadow = [
  Shadow(color: Color(0x66000000), blurRadius: 10, offset: Offset(0, 2)),
];

/// 空狀態 caption text-shadow (`0 1px 6px rgba(0,0,0,0.4)`, moments.jsx `241`).
const List<Shadow> _captionShadow = [
  Shadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 1)),
];

/// 空狀態 caption color (`rgba(255,255,255,0.85)`; alpha 0xD9 ≈ 0.85, moments.jsx `241`).
const Color _emptyCaptionColor = Color(0xD9FFFFFF);

// MARK: - Fixed localized copy (static presentation strings — parity to iOS/Android)

const String _endedLabel = '影片結束';

/// 空狀態 big title (moments.jsx `240` — replaces the retired 熱門變體's small
/// rule-flanked「直播已結束」label with a large standalone headline).
const String _liveEndedTitle = '直播已結束';
// NOTE: moments.jsx's CURRENT text reads「秒後播放其他精采影片」(line 212), but this
// is UNRELATED, pre-existing drift the design source picked up at some undocumented
// point — NOT part of R41's scope (which only removes the 熱門變體), and NOT yet
// reflected on iOS / Android / RN either (all three still ship「秒後自動播放下一支」,
// verified against `EndScreenView.swift` / `.kt` / `.tsx`). Kept at the FOUR-platform
// parity value here (byte-stable against the EXISTING `end-screen-countdown-variant`
// golden, which this redesign does NOT touch) — re-syncing the wording is a separate,
// documented follow-up, not this change's job.
const String _autoPlayPrefix = '秒後自動播放下一支';
const String _untitledNext = '下一支影片';
const String _cancelLabel = '取消';
const String _watchNextLabel = '立即觀看';

/// 空狀態 CTA label (moments.jsx `250`, `LBPCartCTA`「查看購物車」).
const String _viewCartLabel = '查看購物車';

/// 空狀態 duration fallback when no `liveDuration` is host-fed (moments.jsx `241`
/// `(liveInfo && liveInfo.duration) || '--:--:--'`).
const String _liveDurationFallback = '--:--:--';

/// Format `int` seconds → `mm:ss` (for `LBEndNavItem.duration`, which IS seconds —
/// reference-ui formats it, e.g. `28` → `"00:28"`, `2316` → `"38:36"`). Pure /
/// deterministic. Mirrors iOS `EndScreenView.formatSeconds` / Android
/// `formatNavDuration`.
String _formatSeconds(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final m = s ~/ 60;
  final r = s % 60;
  return '${m.toString().padLeft(2, '0')}:${r.toString().padLeft(2, '0')}';
}

/// The family-4 full-screen END moment (LIVE-only — see the file doc comment for the
/// container-level gate). In the 倒數變體 (`countdown != null` && `next` non-empty) it
/// draws a big `next.first` preview card with a centered countdown RING (`remain /
/// total`) representing the auto-advance-to-next countdown, plus 立即觀看
/// ([onWatchNext]) / 取消 ([onCancel]). In the 空狀態 (`countdown == null` || `next`
/// empty) it draws a large「直播已結束」title + 直播時長 caption + a full-width
/// 「查看購物車」CTA ([onViewCart]). All actions are host-wired forwarders; this
/// layer never loads / advances / dismisses itself. Stateless: the retired
/// 熱門變體「換一批」reshuffle window was this widget's only local mutable state.
class EndScreenView extends StatelessWidget {
  /// The resolved reference-ui theme (FIRST parameter, always).
  final ReferenceUITheme theme;

  /// Auto-next countdown snapshot (`MomentsModel.countdown`). Non-null ⇔ 倒數變體;
  /// `{ remain, total }` drives the ring progress. Read-only.
  final LBEndCountdown? countdown;

  /// Watch-next targets (`MomentsModel.next`). `next.first` is the 倒數變體 preview
  /// card source. Empty forces the 空狀態. Read-only.
  final List<LBEndNavItem> next;

  /// 倒數變體「立即觀看」CTA → host-wired → host → core load(next). null for demo /
  /// golden instances — the CTA is inert. This layer NEVER loads / advances itself.
  final void Function()? onWatchNext;

  /// 倒數變體「取消」exit → host-wired. The container now closes the WHOLE
  /// end-screen overlay on this tap (there is no 熱門 fallback left to drop back
  /// to) — this surface only forwards the tap, it does not decide what "cancel"
  /// means. null for demo / golden instances.
  final void Function()? onCancel;

  /// 空狀態「查看購物車」CTA → host-wired; the container's DEFAULT forwards to core
  /// `Player.requestViewCart()` (the notification-type `VIEW_CART` event — the SAME
  /// seam the product list / detail sheet's own cart CTA already uses). null for
  /// demo / golden instances — the CTA is inert. This layer NEVER opens the cart
  /// itself.
  final void Function()? onViewCart;

  /// Host-fed, ALREADY-FORMATTED live-broadcast duration (e.g. `"1:24:30"`) for the
  /// 空狀態's「直播時長：…」caption. Default `''` renders [_liveDurationFallback]
  /// (`'--:--:--'`) — there is currently no reliable source for a real value (see
  /// the file doc comment's `live_time` note), so `MomentsOverlayView` does not yet
  /// pass one. Read-only, never parsed by this layer.
  final String liveDuration;

  /// Real-image gate for the 倒數變體 大預覽卡's `cover`
  /// (rb-flutter-endscreen-recommended-video-cover). `live == false` (demo / golden /
  /// standalone) → draws ONLY the black cover placeholder (no network → byte-stable
  /// golden). `live == true` (host runtime, composited over a real video surface) →
  /// `liveProductImage` overlays the real `cover` (mirrors the widget card
  /// `CarouselCardView` cover branch). Default `false`. Threaded from the turnkey
  /// container (`MinimalDesign.playerOverlay` → `MomentsOverlayView`), parity iOS /
  /// Android / RN. Flutter is cover-only (value types carry NO `preview`).
  final bool live;

  const EndScreenView({
    super.key,
    required this.theme,
    required this.countdown,
    required this.next,
    this.onWatchNext,
    this.onCancel,
    this.onViewCart,
    this.liveDuration = '',
    this.live = false,
  });

  /// Whether the 倒數變體 is active — `countdown != null` AND a preview target exists
  /// (mirrors `LBPEndScreen`'s `!isEmpty && n0`, moments.jsx `165` / `180`).
  bool get _showCountdown => countdown != null && next.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      key: LbTestKeys.momentEnd,
      style: TextStyle(
        color: Colors.white,
        fontSize: 14 * theme.fontScale,
        decoration: TextDecoration.none,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Full-bleed scrim — SHARED by both variants (see the `_scrim` doc
          // comment above for why, and why the resulting stale countdown-variant
          // golden is accepted rather than worked around). The moment composites
          // over the ended video — a fixed design color, not theme bg.
          //
          // fix-flutter-endscreen-close-button-blocked: wrapped in `IgnorePointer` —
          // `Container(color:)` lowers to a `ColoredBox`, whose `hitTestSelf` is
          // ALWAYS `true` regardless of whether any gesture is attached, so this
          // full-bleed node was swallowing every tap in its bounds, including the
          // `PlayerHeaderBarView` minimize/close button painted UNDERNEATH this
          // overlay by the enclosing `Stack` (`MinimalDesign.playerOverlay`).
          // `IgnorePointer` removes it from hit-testing while leaving it fully
          // painted (zero visual effect) — ONLY this node is wrapped, not the
          // whole `Stack`, so the variant's own 取消 / 立即觀看 / 查看購物車
          // `GestureDetector`s (the OTHER Stack child, built below) are unaffected.
          IgnorePointer(child: Container(color: _scrim)),
          if (_showCountdown)
            _buildCountdownVariant()
          else
            _buildEmptyVariant(),
        ],
      ),
    );
  }

  // MARK: - 倒數變體 (preview card + ring + 立即觀看 / 取消)
  //
  // Mirrors `LBPEndScreen`'s countdown branch (moments.jsx `180-235`). UNCHANGED
  // content by this redesign — only the ENCLOSING scrim color changed (see above).
  //   • 「— 影片結束 —」rule-flanked label.
  //   • a 150×(9:16) preview card of `next.first` with a centered countdown ring.
  //   • 「{remain} 秒後播放其他精采影片」+ the next title + the design's
  //     「{shopName} · {duration}」meta line (renderable since
  //     align-endscreen-nav-meta-template added shopName / duration to LBEndNavItem;
  //     the meta line is drawn only when at least one field is host-fed).
  //   • 取消 (outline) / 立即觀看 (accent, play glyph) buttons.

  Widget _buildCountdownVariant() {
    // next.first is guaranteed present here (_showCountdown gates on next non-empty).
    final n0 = next.first;
    final remain = countdown?.remain ?? 0;
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

  /// 「— 影片結束 —」rule-flanked caption (LBPEndScreen `183-187`). Parity iOS /
  /// Android / RN `EndedRule`.
  Widget _endedRule() {
    Widget rule() => Container(width: 18, height: 1, color: _onDarkFaint);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        rule(),
        const SizedBox(width: 8),
        Text(
          _endedLabel,
          style: TextStyle(
            fontSize: 12 * theme.fontScale,
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
  /// `190-210`). The cover is LIVE-GATED: `live == false` (demo / golden) → only the
  /// black placeholder; `live == true` (runtime) → the real `n0.cover` over the
  /// placeholder (shared `liveProductImage`). The dark veil + ring + remaining
  /// seconds are drawn centered ABOVE the cover.
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
            // placeholder; placeholder-only at demo / golden (no network). Clipped
            // by the enclosing ClipRRect (16). Mirrors CarouselCardView cover branch.
            liveProductImage(
              live: live,
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

  /// The auto-advance-to-next countdown RING (LBPEndScreen `195-209`). Per the
  /// design recipe: a faint full track circle + an accent arc `from top, swept by
  /// progress = remain / total`, with `remain` centered. The ring is PURE
  /// PRESENTATION of the snapshot — this layer NEVER ticks it. Self-drawn with
  /// `CustomPaint` (no animation), mirroring iOS `Circle().trim` + Android `Canvas`.
  Widget _countdownRing(int remain) {
    final total = countdown?.total ?? 0;
    final raw = total > 0 ? remain / total : 0.0;
    final progress = raw.clamp(0.0, 1.0).toDouble();
    return SizedBox(
      width: 72,
      height: 72,
      child: CustomPaint(
        painter: _CountdownRingPainter(
          progress: progress,
          trackColor: _ringTrack,
          arcColor: theme.accent,
          strokeWidth: 4,
        ),
        child: Center(
          child: Text(
            '$remain',
            style: TextStyle(
              fontSize: 26 * theme.fontScale,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }

  /// Preview caption block (LBPEndScreen `211-218`): the auto-play line + the next
  /// title (2-line clamp) + the「{shopName} · {mm:ss}」meta line (drawn only when
  /// at least one field is host-fed — the Flutter `LBEndNavItem` may carry empty
  /// `shopName` / zero `duration`).
  Widget _previewCaption(LBEndNavItem n0, int remain) {
    final title = n0.title.isEmpty ? _untitledNext : n0.title;
    final hasMeta = n0.shopName.isNotEmpty || n0.duration > 0;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$remain $_autoPlayPrefix',
            style: TextStyle(
              fontSize: 12 * theme.fontScale,
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
              fontSize: 15 * theme.fontScale,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              height: 1.4,
              decoration: TextDecoration.none,
            ),
          ),
          if (hasMeta) ...[
            const SizedBox(height: 4),
            // NOTE: moments.jsx (line 217) actually specifies `fontSize: 11.5` +
            // `rgba(255,255,255,0.5)` here (matching iOS `metaLine`'s `11.5 *
            // theme.fontScale` / `onDarkFaintText` and Android's `11.5f` / alpha
            // `0.5f` exactly) — Flutter alone is a `12` / `_onDarkDim` (0.6 alpha)
            // OUTLIER, a pre-existing parity gap UNRELATED to R41 (this redesign
            // only removes the 熱門變體). Left byte-identical to the EXISTING
            // Flutter code here (not "corrected" to 11.5/0.5) so the untouched
            // `end-screen-countdown-variant` golden keeps passing; re-aligning is a
            // separate, documented follow-up, not this change's job.
            Text(
              _metaLine(n0),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12 * theme.fontScale,
                color: _onDarkDim,
                decoration: TextDecoration.none,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 「{shopName} · {mm:ss}」preview meta (LBPEndScreen moments.jsx `217`). Joins the
  /// two host-fed `LBEndNavItem` fields with「 · 」, omitting an absent side.
  String _metaLine(LBEndNavItem n0) {
    final parts = <String>[
      if (n0.shopName.isNotEmpty) n0.shopName,
      if (n0.duration > 0) _formatSeconds(n0.duration),
    ];
    return parts.join(' · ');
  }

  /// 取消 (outline) / 立即觀看 (accent + play glyph) action row (LBPEndScreen
  /// `221-234`). Each forwards to its host-wired callback; this layer never
  /// advances or decides what "cancel" means (see [onCancel]'s doc).
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
              fontScale: theme.fontScale,
              fill: _onDarkFill,
              borderColor: _onDarkStroke,
              onTap: onCancel,
            ),
          ),
          const SizedBox(width: 10),
          // 立即觀看 — accent filled button with a play glyph.
          Expanded(
            child: _DarkButton(
              key: LbTestKeys.momentEndWatch,
              label: _watchNextLabel,
              fontScale: theme.fontScale,
              fill: theme.accent,
              leading:
                  const Icon(Icons.play_arrow, size: 16, color: Colors.white),
              onTap: onWatchNext,
            ),
          ),
        ],
      ),
    );
  }

  // MARK: - 空狀態 (直播已結束 title + 直播時長 caption + 查看購物車 CTA)
  //
  // Mirrors `LBPEndScreen`'s empty branch (moments.jsx `237-252`) — REPLACES the
  // retired 熱門變體 (為你推薦 header + hot-card row + 換一批 pill) wholesale; there
  // is no card wall / countdown / recommendation content in this variant at all.

  Widget _buildEmptyVariant() {
    final duration =
        liveDuration.isEmpty ? _liveDurationFallback : liveDuration;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                _liveEndedTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 30 * theme.fontScale,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: -0.2,
                  shadows: _titleShadow,
                  decoration: TextDecoration.none,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '直播時長：$duration',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15.5 * theme.fontScale,
                  color: _emptyCaptionColor,
                  shadows: _captionShadow,
                  decoration: TextDecoration.none,
                ),
              ),
            ],
          ),
          const SizedBox(height: 36),
          _viewCartButton(),
        ],
      ),
    );
  }

  /// Full-width「查看購物車」CTA (LBPEndScreen `243-251`, `LBPCartCTA`). Forwards
  /// [onViewCart] (null → inert here; the container supplies the real
  /// `Player.requestViewCart()` default one layer up — see [onViewCart]'s doc).
  Widget _viewCartButton() {
    return GestureDetector(
      key: LbTestKeys.momentEndViewCart,
      behavior: HitTestBehavior.opaque,
      onTap: onViewCart,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
        decoration: BoxDecoration(
          color: theme.accent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CartFillGlyph(color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Text(
              _viewCartLabel,
              style: TextStyle(
                fontSize: 16 * theme.fontScale,
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
