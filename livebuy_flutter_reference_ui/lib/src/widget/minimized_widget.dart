import 'package:flutter/widgets.dart';

import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';
import 'carousel_card.dart' show CarouselCardView;

// MinimizedWidgetView — family-5 widget surface 4 (LBPFloatingWidget).
//
// Spec: `reference-ui-rendering/spec.md` (family-5 widget surfaces —
//        carousel / video-shop grid / floating / minimized). Flutter parity of iOS
//        `MinimizedWidgetView.swift` (rb-ios-widget) + Android `MinimizedWidgetView
//        .kt` (rb-android-widget). Design: `design/templates/minimal/sdk-components
//        .jsx` `LBPFloatingWidget` (lines 590-710).
//
// ── DESIGN SYMBOL RENAMED ────────────────────────────────────────────────────────
//   Every design pointer in this file used to name `LBPMinimizedWidget`. That symbol
//   no longer exists anywhere under `design/templates/minimal/` — it was RENAMED to
//   `LBPFloatingWidget` on 2026-06-09 (divergence ledger
//   `design/contract/claude-design-sync.md` **R2**, "已對齊"), in the same sync that
//   removed the unrelated carousel-card `LBPFloatingWidget` from `widgets.jsx`.
//   This was a rename with the pixels CARRIED OVER: every value this file cites was
//   re-verified against the renamed component and found there, so the pointers below
//   address the LIVE `sdk-components.jsx` on disk today — ordinary current coordinates.
//   `floating_widget.dart` carries BOTH kinds: current coordinates for its close button
//   (re-aligned to this same canonical component on 2026-08-11) and `[HISTORICAL …]`
//   ones for the structural values that did not survive its component's removal.
//
// The MINIMIZED widget surface: a small ~96-wide 9:16 floating pill the SDK collapses
// to (the design's PiP-style corner widget). It maps to `LBWidgetContentMode
// .minimized` (the template-derived floating "isClosed" state) and is the fourth of
// the four family-5 widget sub-views the container (`WidgetOverlayView`) switches on.
// It implements the FROZEN constructor documented verbatim in `widget_overlay_view
// .dart`'s SUB-VIEW INPUT PATTERN:
//
//     MinimizedWidgetView({
//         required ReferenceUITheme theme,
//         required bool isLive,                 // derived from liveVideo?.liveStatus
//         VoidCallback? onExpand,               // pill tap → host (restore full-screen)
//         VoidCallback? onClose })              // top-right close → host
//
// SELF-CONTAINED (no WidgetModel): unlike the carousel / grid surfaces, the minimized
// pill takes NO `WidgetModel` — it is a tiny chrome affordance with only a single
// derived bound field, `isLive` (the container/host derives it from
// `WidgetModel.minimizedIsLive`, i.e. `liveVideo?.liveStatus == 1`, the SAME source as
// the shared `CarouselCardView` kind badge, per the Android delta — `LBWidgetContent`
// has no `isLive` field). So this view binds ONLY `isLive`; it reads no other
// view-model state and holds NO copy of model state (one-way data flow preserved).
//
// STRUCTURE (mirrors `LBPFloatingWidget`, sdk-components.jsx 657-708):
//   • a 96-wide 9:16 rounded (12) pill with a soft drop shadow + a 1px white hairline
//     (`0 0 0 1px rgba(255,255,255,0.08)`),
//   • a deterministic dark cover placeholder (the design's `<VideoBG>` — NO
//     Image.network / NetworkImage; a gradient + play-glyph chip, mirroring
//     `CarouselCardView._coverPlaceholder`),
//   • a top-left LIVE red tag (`#F03246`, static pulse dot) ONLY when `isLive`,
//   • a top-right round close affordance (`rgba(0,0,0,0.55)` + close glyph),
//   • a bottom centered drag-handle hint (24×3 pill, `rgba(255,255,255,0.4)`).
//
// HOST-WIRED EXITS (design §"守住的不變式": 互動一律 host-wired exit 轉發):
//   • BODY tap   → `onExpand` → host → core re-open the floating widget (the design
//                  restores the player to full screen on a no-drag tap,
//                  sdk-components.jsx 651).
//   • CLOSE tap  → `onClose`  → host → core floating-close.
//   The design's grip-DRAG-to-reposition (pointer math, sdk-components.jsx 618-653)
//   is a host / PiP-window concern, NOT pixel rendering — this layer renders at a fixed
//   position and forwards only tap / close (NO drag re-positioning, NO core
//   `simulate*` / template intents). Renders correctly with both actions null (so demo
//   / golden / widget tests construct it action-free).
//
// EMBED COLORS (rb-flutter-widget-embed-colors): `widget_color` / `widget_bgcolor` are
// NOT consulted here — this surface is DELIBERATELY EXCLUDED, takes no such parameter,
// and its `theme` MUST stay the underived `ReferenceUIThemeResolver` output. ⚠️ It reads
// ONLY `theme.fontScale`, so a theme leak from the container's shared local would have NO
// pixel signature here — the regression guard is a theme-object assertion in
// `widget_embed_colors_test.dart`, NOT a golden.
//
// NO scrollable container, NO network image, NO animation / randomness.

/// The family-5 MINIMIZED widget pill (`LBPFloatingWidget`): a small ~96-wide 9:16
/// floating placeholder pill with an optional LIVE tag, a close affordance, and a
/// drag-handle hint. Body tap → `onExpand`; close → `onClose`. Self-contained (no
/// `WidgetModel`) — it binds only the derived `isLive` flag and never reaches back
/// into the model / template.
class MinimizedWidgetView extends StatelessWidget {
  /// The resolved reference-ui theme (FIRST — SUB-VIEW INPUT PATTERN). The minimized
  /// pill is white-on-dark chrome (fixed design colors for the cover / LIVE tag /
  /// close), so `theme` is consulted only for `fontScale` consistency. It MUST be the
  /// UNDERIVED theme — the widget embed colors never reach this surface
  /// (rb-flutter-widget-embed-colors).
  final ReferenceUITheme theme;

  /// Whether a LIVE card sits behind the minimized pill — the SINGLE bound field (the
  /// container/host derives it from `WidgetModel.minimizedIsLive`, i.e.
  /// `liveVideo?.liveStatus == 1`). When true, the top-left LIVE red tag is drawn
  /// (design `isLive` gate, sdk-components.jsx 683).
  final bool isLive;

  /// BODY tap → host-wired `onExpand` → host → core re-open the floating widget (the
  /// design restores full screen on a no-drag tap). null for demo / golden instances
  /// — the pill is inert. This layer NEVER re-opens / calls core itself.
  final VoidCallback? onExpand;

  /// CLOSE tap → host-wired `onClose` → host → core floating-close. null for demo /
  /// golden instances. This layer NEVER closes / calls core itself.
  final VoidCallback? onClose;

  const MinimizedWidgetView({
    super.key,
    required this.theme,
    required this.isLive,
    this.onExpand,
    this.onClose,
  });

  /// Pill width (logical px) — the design's fixed `width: 96`
  /// (sdk-components.jsx 666).
  static const double pillWidth = 96;

  @override
  Widget build(BuildContext context) {
    final h = pillWidth * 16.0 / 9.0;
    // BODY tap restores the player (no-drag tap → onExpand, sdk-components.jsx 651). The
    // inner close button has its own gesture and swallows the tap so only one fires.
    return GestureDetector(
      key: LbTestKeys.minimizedWidget,
      onTap: onExpand,
      behavior: HitTestBehavior.opaque,
      child: DecoratedBox(
        // Soft drop shadow (`0 8px 24px rgba(0,0,0,0.35)`, sdk-components.jsx 668).
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: _shadow,
              blurRadius: 24,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: pillWidth,
            height: h,
            child: Stack(
              children: [
                // Deterministic dark cover placeholder (`<VideoBG>`).
                Positioned.fill(child: _coverPlaceholder()),
                // 1px white hairline (`0 0 0 1px rgba(255,255,255,0.08)`,
                // sdk-components.jsx 668).
                Positioned.fill(child: _hairlineBorder()),
                // LIVE red tag top-left (only when a live card is behind the pill).
                if (isLive) Positioned(top: 6, left: 6, child: _liveTag()),
                // Close affordance top-right → onClose.
                Positioned(top: 4, right: 4, child: _closeButton()),
                // Centered drag-handle hint at the bottom (pure decoration — the real
                // grip-drag is a host / PiP-window concern, not rendered here).
                Positioned(
                  bottom: 4,
                  left: 0,
                  right: 0,
                  child: Center(child: _dragHandle()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // MARK: - Cover placeholder (9:16 dark gradient + play glyph)

  /// 9:16 deterministic dark cover placeholder (the design's `<VideoBG>`) — a gradient
  /// + a play-glyph monogram (no remote image). Mirrors
  /// `CarouselCardView._coverPlaceholder`.
  Widget _coverPlaceholder() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3A3A44), Color(0xFF111118)],
        ),
      ),
      child: Center(
        child: Icon(
          _playGlyph,
          size: 18 * theme.fontScale,
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.85),
        ),
      ),
    );
  }

  /// The 1px white hairline overlay (`0 0 0 1px rgba(255,255,255,0.08)`,
  /// sdk-components.jsx 668).
  Widget _hairlineBorder() {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFFFFFF).withValues(alpha: 0.08),
          width: 1,
        ),
      ),
    );
  }

  // MARK: - LIVE tag (top-left, isLive only)

  /// LIVE red tag (`LBPFloatingWidget` 683-693): a static pulse dot +「LIVE」on the
  /// brand-red surface (`#F03246`). The pulse animation is drawn statically
  /// (golden-safe). Reuses the same `#F03246` red as `CarouselCardView` (its private
  /// `_liveRed`, replicated here as the shared design token).
  Widget _liveTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: _liveRed,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 3,
            height: 3,
            decoration: const BoxDecoration(
              color: Color(0xFFFFFFFF),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            CarouselCardView.liveLabel,
            style: TextStyle(
              fontSize: 9 * theme.fontScale,
              fontWeight: FontWeight.w800,
              color: const Color(0xFFFFFFFF),
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // MARK: - Close affordance (top-right → onClose)

  /// Top-right round close button (`LBPFloatingWidget` 694-702): a 20×20
  /// translucent-dark circle (`rgba(0,0,0,0.55)`) + a close (×) glyph. Tap →
  /// host-wired `onClose`. Its own `GestureDetector` swallows the tap so the body
  /// `onExpand` does not also fire.
  Widget _closeButton() {
    return GestureDetector(
      key: LbTestKeys.minimizedClose,
      onTap: onClose,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF000000).withValues(alpha: 0.55),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          _closeGlyph,
          size: 11,
          color: Color(0xFFFFFFFF),
        ),
      ),
    );
  }

  // MARK: - Drag-handle hint (bottom center, decorative)

  /// The bottom-centered drag-handle hint (`LBPFloatingWidget` 703-707): a 24×3
  /// rounded pill (`rgba(255,255,255,0.4)`). Pure decoration — the real grip-drag
  /// reposition is host / PiP-window logic, NOT rendered at this layer.
  Widget _dragHandle() {
    return Container(
      width: 24,
      height: 3,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFFFF).withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }

  // MARK: - Decorative design tokens (literal sdk-components.jsx values)

  /// Brand-red LIVE tag surface (`#F03246`, LBPFloatingWidget 686). Same token as
  /// the shared `CarouselCardView` LIVE tag.
  static const Color _liveRed = Color(0xFFF03246);

  /// Soft drop shadow (`0 8px 24px rgba(0,0,0,0.35)`, sdk-components.jsx 668).
  static const Color _shadow = Color(0x59000000); // 0.35 alpha black.

  /// Play glyph for the cover placeholder (▶). `Icons.play_arrow` codepoint —
  /// declared inline to avoid a material import in a widgets-only file (consistent
  /// with `CarouselCardView`'s inline-glyph approach).
  static const IconData _playGlyph =
      IconData(0xe4cb, fontFamily: 'MaterialIcons');

  /// Close glyph (×) for the top-right affordance. `Icons.close` codepoint.
  static const IconData _closeGlyph =
      IconData(0xe16a, fontFamily: 'MaterialIcons');
}
