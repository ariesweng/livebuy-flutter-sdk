import 'package:flutter/widgets.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart' show LBVideoItem;

import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';
import 'carousel_card.dart';
import 'widget_model.dart' show WidgetGoods;

// FloatingWidgetView — family-5 widget surface 3 (LBPFloatingWidget).
//
// Spec: `reference-ui-rendering/spec.md` (family-5 widget surfaces — the standalone
// 懸浮直播預覽視窗). Flutter parity of iOS `FloatingWidgetView.swift` (rb-ios-widget)
// + Android `FloatingWidgetView.kt` (rb-android-widget).
//
// ── DESIGN SOURCE — read this before following ANY line number in this file ──────
//   CANONICAL component today:
//     `design/templates/minimal/sdk-components.jsx` `LBPFloatingWidget` (590-710)
//     (contract anchor: `design/contract/components.md`).
//
//   TWO KINDS OF COORDINATE COEXIST IN THIS FILE. Check the tag before following one:
//
//   (a) PLAIN coordinates (`sdk-components.jsx N-M`) address the CANONICAL component
//       on disk today. Everything about the top-right CLOSE BUTTON is of this kind
//       since 2026-08-11: its placement, size, fill, border-less-ness and glyph size
//       were re-aligned to `sdk-components.jsx` `LBPFloatingWidget` 694-702 (framed
//       top-right at `top: 4, right: 4`, 20×20, `rgba(0,0,0,0.55)`, `border: 'none'`).
//
//   (b) `[HISTORICAL widgets.jsx@e98ac146^ N-M]` coordinates address a DIFFERENT,
//       now-deleted component — the carousel-card version of `LBPFloatingWidget`, which
//       took `{video, theme, accent, onTap, onClose, width, height}` and reused
//       `LBPCarouselCard`. It occupied [HISTORICAL widgets.jsx@e98ac146^ 374-419] and
//       was REMOVED from `design/templates/minimal/widgets.jsx` on 2026-06-09
//       (divergence ledger `design/contract/claude-design-sync.md` **R5**);
//       `widgets.jsx` carries only a guard comment in its place today. Each such number
//       resolves against `widgets.jsx` as of git commit `e98ac146^`, the last commit
//       that still contained the definition, and MUST NOT be read against the
//       `widgets.jsx` on disk today.
//
//   WHY (b) STILL EXISTS after the close-button re-alignment: three STRUCTURAL values
//   this file still renders survive only in the removed component and are found NOWHERE
//   in the canonical one — reusing `CarouselCardView` instead of drawing a 96-wide pill,
//   treating the preview as a LIVE card unconditionally, and the `width` default `132`
//   (the canonical component is `width: 96`, `sdk-components.jsx` 666). Those coordinates
//   MUST NOT be re-pointed at `sdk-components.jsx`: doing so would manufacture citations
//   that resolve to something else. They are recorded as a known, deliberate divergence
//   in `openspec/specs/reference-ui-rendering/spec.md` (this surface's requirement,
//   「對齊 `LBPFloatingWidget`」的除外條款); converging them would be a separate,
//   four-platform change.
//
//   This comment records provenance only.
//
// The standalone 懸浮直播預覽視窗 (`LBWidgetContentMode.floating`): a self-contained,
// dismissible floating window that previews a single LIVE stream. Unlike the carousel
// / video-shop surfaces (which embed many videos in a host page), this is instantiated
// standalone by 3rd-party hosts and floats over their own content. It REUSES the shared
// `CarouselCardView` primitive for the 9:16 live thumbnail (so the brand language
// matches the carousel / grid cards) and overlays a top-right round close button
// (floating-only).
//
// SUB-VIEW INPUT PATTERN (parity with families 1-4; matches the call site the container
// `WidgetOverlayView` uses verbatim):
//   1. `theme:` (ReferenceUITheme, required)  — FIRST, always. Passed straight through
//      to the reused `CarouselCardView`.
//   2. `liveVideo: LBVideoItem?`              — the single floating preview video
//      (`WidgetModel.liveVideo`). When NULL → render NOTHING (`SizedBox.shrink`). The
//      design basis is the R5 guard note in `widgets.jsx` (426-436): the solicitation
//      entry is mounted by the host ONLY while a live stream exists. (The canonical
//      `LBPFloatingWidget` in `sdk-components.jsx` carries no per-video prop at all — its
//      early return gates the entrance delay, not the presence of a stream.) The
//      container passes `model.liveVideo`, which may be null before a live stream.
//   3. `goods: WidgetGoods?`                  — optional product overlay (reference-ui
//      value — Flutter core `LBVideoItem` has NO `goods` field). Forwarded to the reused
//      card; null → no overlay.
//   4. action callbacks (LAST, EACH defaulting to null):
//      • `onTap: void Function(LBVideoItem item)?` — whole-window tap → `onTap(liveVideo)`
//        (canonical `videoTap`). Host-wired exit → host → core open player for the live
//        `liveVideo.id`. This layer NEVER opens the player itself.
//      • `onClose: VoidCallback?`              — top-right close button → `onClose`
//        (canonical `close`, floating-only). Host owns re-mount; this layer just
//        forwards the dismiss intent. The close tap MUST NOT also fire `onTap`.
//
// LIVE TREATMENT: the design always treats the floating preview as a LIVE card visually
// (`kind: video.kind || 'live'` — [HISTORICAL widgets.jsx@e98ac146^ 378-379]). The core
// `LBVideoItem` is a read-only value carrying only `liveStatus: int`, and the reused
// `WidgetModel.isLive` / `CarouselCardView` key on `liveStatus == 1`. We pass `liveVideo`
// STRAIGHT THROUGH to the card (we never build a live-forced copy — `LBVideoItem` is
// immutable and we must not mutate the host's model). The card therefore reads LIVE iff
// `liveVideo.liveStatus == 1`; in practice the container only routes a genuine live
// stream (`WidgetModel.liveVideo`) into this surface, so it reads LIVE. A non-live
// `liveVideo` would render the VOD duration pill instead — an accepted approximation
// (documented in `CarouselCardView`'s kind mapping). NO separate upcoming / replay
// handling.
//
// CLOSE-TAP ISOLATION (`e.stopPropagation()` — sdk-components.jsx 695-696; the canonical
// component swallows the pointer on BOTH `onPointerDown` and `onClick`):
// the close button is a SEPARATE `GestureDetector` overlaid ON TOP of the card in a
// `Stack`. Flutter hit-testing routes the tap to the front-most widget, so a tap on the
// close button fires ONLY `onClose` and never the card's `onTap`. The card tap is wired
// through `CarouselCardView`'s own `onTap` (its whole-card `GestureDetector`), so the
// two exits stay cleanly separated without a custom gesture.
//
// One-way data flow: this surface reads ONLY its passed-in `liveVideo` + `goods` +
// `theme`; it never reaches back into `WidgetModel` / `DefaultWidgetTemplate`, holds NO
// second copy of state, calls NO core `simulate*` / `requestLoadMore`, and NEVER opens
// the player / closes itself. It renders correctly with `onTap` / `onClose` null (so
// demo / golden / widget tests construct it action-free).
//
// TITLE SUPPRESSION (rb-flutter-floating-widget-hide-title): the reused `CarouselCardView`
// is built with `showTitle: false` — the canonical `LBPFloatingWidget` (`sdk-components.jsx`
// 590-712) has NO title element at all, so the title `CarouselCardView` draws by default was
// purely an artifact of reusing that shared card, never something the design asked this
// surface to show. This is a design-alignment fix, not a new divergence: the floating card's
// intrinsic height shrinks accordingly (see `CarouselCardView`'s own `showTitle` doc).
//
// EMBED COLORS (rb-flutter-widget-embed-colors): this surface is DELIBERATELY EXCLUDED
// (same exclusion as `product_card`). It takes NO `widgetColor` / `widgetBgcolor`
// parameter and its `theme` MUST stay the underived `ReferenceUIThemeResolver` output.
// The container's `_buildSurface` local `theme` is handed to this branch too — which is
// exactly why the derivation lives inside the two card-bearing surfaces and NOT there.
//
// NO `ListView` / `GridView` / `SingleChildScrollView`. The
// reused card draws the deterministic placeholder by default; on the live runtime path
// (`live == true`) it overlays the real `liveVideo.cover` (gated by `liveProductImage`),
// forwarded through the `live` flag.

/// The family-5 standalone floating live-preview window (`LBPFloatingWidget`). When
/// `liveVideo == null` it renders NOTHING (`SizedBox.shrink`). When non-null it draws ONE
/// reused [CarouselCardView] (the live preview) with a top-right round close button
/// overlay. Whole-window tap → `onTap(liveVideo)`; close button → `onClose` (the close tap
/// never also fires `onTap`). All exits are host-wired; this layer never opens / closes
/// itself.
class FloatingWidgetView extends StatelessWidget {
  /// The resolved reference-ui theme (FIRST — SUB-VIEW INPUT PATTERN). Passed straight
  /// through to the reused [CarouselCardView].
  final ReferenceUITheme theme;

  /// The single floating preview video (`WidgetModel.liveVideo`). null → render NOTHING
  /// (`SizedBox.shrink`) — design basis: the R5 guard note in `widgets.jsx` (426-436),
  /// where the host mounts the solicitation entry only while a live stream exists.
  /// Read-only.
  final LBVideoItem? liveVideo;

  /// Optional product overlay (reference-ui `WidgetGoods` — Flutter core `LBVideoItem`
  /// has no `goods` field). Forwarded to the reused card; null → no overlay.
  final WidgetGoods? goods;

  /// Floating window width (logical px). Defaults to `132` — the carousel-card version's
  /// own default ([HISTORICAL widgets.jsx@e98ac146^ 374]). The CANONICAL
  /// `sdk-components.jsx` `LBPFloatingWidget` uses `width: 96` instead
  /// (`sdk-components.jsx` 666); this default still follows the historical component —
  /// one of the three STRUCTURAL divergences the close-button re-alignment deliberately
  /// did NOT collapse (see the file header, kind (b)). The reused card's 9:16 thumbnail
  /// height is derived from this value.
  final double width;

  /// Whether the reused card loads its real cover photo. `false` (DEFAULT — demo /
  /// golden) → placeholder ONLY (byte-stable goldens); `true` (host runtime) → the card
  /// overlays `liveVideo.cover` over the placeholder. Parity with iOS
  /// `FloatingWidgetView.live`.
  final bool live;

  /// Whole-window tap → host-wired `onTap(liveVideo)` → host → core open player for the
  /// live `liveVideo.id` (canonical `videoTap`). null for demo / golden instances — the
  /// window is inert. This layer NEVER opens the player itself.
  final void Function(LBVideoItem item)? onTap;

  /// Top-right close button → host-wired `onClose` (canonical `close`, floating-only).
  /// Host owns re-mount. null for demo / golden instances. The close tap MUST NOT also
  /// fire `onTap` (separate front-most `GestureDetector` — Flutter hit-testing isolates it).
  final VoidCallback? onClose;

  const FloatingWidgetView({
    super.key,
    required this.theme,
    required this.liveVideo,
    this.goods,
    this.width = 132,
    this.live = false,
    this.onTap,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    // liveVideo == null → render NOTHING (design basis: `widgets.jsx` 426-436 R5 guard
    // note — the host mounts this entry only while a live stream exists).
    final video = liveVideo;
    if (video == null) return const SizedBox.shrink();
    return _window(video);
  }

  // MARK: - Floating window (reused card + top-right close button)
  //
  // The window BODY still mirrors the carousel-card version of `LBPFloatingWidget`
  // ([HISTORICAL widgets.jsx@e98ac146^ 381-417] — see the file header, kind (b)): a
  // `position: relative` box of the reused `LBPCarouselCard` (whole-window tap →
  // videoTap). The CLOSE BUTTON on top of it follows the CANONICAL component instead
  // (`sdk-components.jsx` 694-702, framed top-right at `top: 4, right: 4`).
  //
  // NO drop-shadow is drawn — neither here nor by the reused `CarouselCardView`. The
  // canonical component has one (`0 8px 24px rgba(0,0,0,0.35)` plus a
  // `0 0 0 1px rgba(255,255,255,0.08)` hairline, `sdk-components.jsx` 668); this surface
  // has never drawn either. Recorded as a known divergence in the spec's carve-out, NOT
  // silently omitted.

  Widget _window(LBVideoItem video) {
    return SizedBox(
      key: LbTestKeys.floatingWidget,
      // The window is EXACTLY the card: the close button sits INSIDE the card frame, so
      // nothing has to be padded out of the way. (It used to be `width + 8` with the card
      // inset by 8, to make room for a close button nudged past the corner — that layout
      // went away with the re-alignment.)
      width: width,
      child: Stack(
        // Nothing overflows any more, so this is a no-op upper bound; kept so the Stack
        // never introduces a clip of its own.
        clipBehavior: Clip.none,
        children: [
          // Reuse the shared 9:16 card primitive (DO NOT re-draw a card). Its own
          // whole-card `GestureDetector` carries the videoTap exit → forward the bound
          // `video`. It is the Stack's only non-`Positioned` child, so the window's
          // measured size IS the card's size.
          //
          // NO `productCard:` here — DELIBERATE, and the same decision on all four
          // platforms (rb-flutter-widget-product-card-modes D9 #3): this surface is bound
          // to `content.liveVideo`, whose data comes from `/sdk/widget/live`, a response
          // that does NOT carry `product_card`; and the surface takes a bare `LBVideoItem`
          // + by-value `goods` with no `WidgetModel` to read a mode from. Omitting it
          // leaves the card at its default → `inside`, i.e. today's behaviour exactly.
          //
          // NO 標題，刻意（rb-flutter-floating-widget-hide-title）：`showTitle: false` —
          // 設計稿 `LBPFloatingWidget` 本身沒有標題元素，本次是往設計稿對齊，非新增偏離。
          CarouselCardView(
            theme: theme,
            item: video,
            goods: goods,
            width: width,
            live: live,
            showTitle: false,
            onTap: onTap == null ? null : () => onTap!(video),
          ),
          // Top-right round close button (floating-only). A SEPARATE front-most
          // `GestureDetector` — a tap here fires ONLY `onClose`, never the card's
          // `onTap` (`e.stopPropagation()` — sdk-components.jsx 695-696).
          // Anchored INSIDE the card's top-right corner
          // (`top: 4, right: 4` — sdk-components.jsx 698).
          Positioned(
            top: 4,
            right: 4,
            child: _closeButton(),
          ),
        ],
      ),
    );
  }

  /// Top-right round close button (`sdk-components.jsx` `LBPFloatingWidget` 694-702 —
  /// the CANONICAL component): a 20×20 `rgba(0,0,0,0.55)` circle with a white ✕ glyph,
  /// NO border (the design writes `border: 'none'`, 700) and NO shadow of its own.
  /// Byte-identical to `MinimizedWidgetView._closeButton` — the same design element.
  /// Forwards `onClose` only.
  ///
  /// Glyph size 11 is the design's own `<Icons.close size={11} />` (702) taken at face
  /// value: `Icon(size:)` is the em-box edge of a 24-unit MaterialIcons glyph, the same
  /// quantity as the design icon's `viewBox="0 0 24 24"` edge, so the ink spans match
  /// (both ≈ 11 × 14/24). iOS's `9` is an SF-Symbol conversion and does NOT transfer.
  Widget _closeButton() {
    final button = Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: _closeGlass,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: const Icon(closeGlyph, size: 11, color: Color(0xFFFFFFFF)),
    );
    // Host-wired (no-op when null). Opaque hit-testing so the close tap is isolated to
    // this front-most widget and never falls through to the card behind it.
    return GestureDetector(
      key: LbTestKeys.floatingClose,
      onTap: onClose,
      behavior: HitTestBehavior.opaque,
      child: button,
    );
  }

  // MARK: - Decorative design tokens (literal sdk-components.jsx values)
  //
  // theme is passed through to the card; this is a FIXED decorative color lifted
  // verbatim from the CANONICAL `LBPFloatingWidget` (the close button is the same
  // regardless of the host theme — the design's standalone floating chrome), kept
  // consistent with the family-2/3/4 surfaces' fixed-token approach.

  /// Close-button translucent-dark surface (`rgba(0,0,0,0.55)`, `sdk-components.jsx` 699).
  /// Written as the same expression `MinimizedWidgetView` uses so the two instances of
  /// this one design element stay byte-identical.
  ///
  /// The design pairs that fill with `backdrop-filter: blur(6px)` (same line). NOT
  /// implemented here, and NOT because Flutter cannot: `BackdropFilter` exists. This
  /// layer draws EVERY `rgba(…)` glass in the design as a plain translucent solid
  /// (zero backdrop-blur call sites anywhere in this package), all four
  /// platforms do the same, and a real backdrop blur would need its own `ClipRRect` plus
  /// a `saveLayer` — cost and golden non-determinism for a 20-logical-px decoration.
  /// Recorded as a known, deliberate gap; see this surface's spec requirement.
  static final Color _closeGlass =
      const Color(0xFF000000).withValues(alpha: 0.55);

  /// Close ✕ glyph. The `Icons.close` codepoint (`0xe16a`) — declared inline to avoid a
  /// material import in a widgets-only file (parity with `CarouselCardView`'s inline
  /// play glyph). Exposed so tests can locate it without a material import.
  static const IconData closeGlyph =
      IconData(0xe16a, fontFamily: 'MaterialIcons');
}
