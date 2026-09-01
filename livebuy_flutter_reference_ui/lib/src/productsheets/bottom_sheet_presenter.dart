import 'package:flutter/widgets.dart';

import '../sheet_slide_transition.dart';
import '../testing/lb_test_keys.dart';

// bottom_sheet_presenter.dart — the cohesive shared bottom-sheet presenter
// (scrim + slide + bottom-pinned card), Flutter parity of iOS
// `LivebuyReferenceUI/SheetKit/BottomSheetPresenter.swift`'s `.lbBottomSheet`.
//
// Parity: iOS `BottomSheetChrome` (rb-ios-sheet-* / sheetkit) gives EVERY grab-handle
//   bottom sheet (1) a full-bleed dim scrim that BLOCKS the host gesture layer below +
//   dismisses on a background tap, (2) a bottom-anchored card, (3) the present/dismiss
//   slide. Before this presenter the Flutter side had the slide (via `AnimatedSwitcher`
//   + `sheetSlideTransition` inlined per container) but NO scrim — an open sheet did not
//   dim or block the video gesture layer underneath, and a background tap did not close
//   it. This widget folds the scrim + the slide into ONE presenter so every grab-handle
//   sheet (ProductDetail / AddToCart / NotifyRestock / ProductList + the player-shell
//   VideoInfoPanel) presents identically.
//
// SCRIM (the new piece — design `lbp-fade-in` dim, iOS `Color.black.opacity(0.55)`):
//   • a full-bleed `Container(color: Colors.black.withValues(alpha: 0.55))`,
//   • wrapped in a `GestureDetector(behavior: opaque, onTap: onDismiss)` so it BLOCKS
//     the host content underneath (absorbs taps) AND closes on a background tap,
//   • faded in / out (`AnimatedSwitcher` over a keyed scrim child vs an empty box) so it
//     follows the card's enter / exit rather than popping.
//   The scrim sits BELOW the card in the `Stack`, so the card (and its grab-handle drag
//   target / buttons) stay interactive while the rest of the screen is dimmed + inert.
//
// SLIDE: the card animates with the SHARED `sheetSlideTransition` + `sheetBottomLayoutBuilder`
//   (design `lbp-sheet-in`, translate-only — the card carries NO fade; the fade belongs to
//   the scrim). `AnimatedSwitcher` keeps the OUTGOING card rendered during the dismiss so the
//   slide-down has content (no manual last-content retention).
//
// The presenter renders nothing about WHEN it shows — the caller owns the [open] flag
// (mirrors iOS, where presentation state stays with the container). When [open] is false
// it draws an empty box (the outgoing card / scrim still slide + fade out for one frame
// via the switchers), so it is always safe to compose unconditionally in a `Stack`.
//
// GOLDEN NOTE: the per-surface goldens pin `find.byType(<SurfaceWidget>)` (e.g.
// `ProductDetailSheet`), which renders the sheet CONTENT only — NOT this presenter and
// NOT the scrim — so they are unchanged. There is no container-level golden that would
// capture the scrim, so no baseline regenerates.

/// The cohesive shared bottom-sheet presenter. Composes (1) a full-bleed dim scrim
/// that blocks the content below + dismisses on a background tap, and (2) the shared
/// present/dismiss slide for the bottom-anchored [child] card.
///
/// [open] — whether the sheet is presented (the caller owns this). `false` → empty box
/// (the outgoing card slides down + the scrim fades out for one frame).
/// [child] — the grab-handle sheet leaf (already top-rounded + grab-handle + scaffold).
///   MUST be `null` when [open] is false (mirrors the keyed-switch contract); the caller
///   passes the sheet only while presenting.
/// [sheetKey] — the `ValueKey` distinguishing the presented card from the empty box (so
///   the slide `AnimatedSwitcher` animates present / dismiss / SWITCH between sheets).
/// [onDismiss] — invoked on a background (scrim) tap. `null` → the scrim still blocks the
///   content below but a tap is inert.
class BottomSheetPresenter extends StatelessWidget {
  /// Whether the sheet is presented (caller-owned). `false` → empty box (animate-out).
  final bool open;

  /// The grab-handle sheet leaf to present (already top-rounded + grab-handle + scaffold),
  /// or `null` when [open] is false.
  final Widget? child;

  /// The key that identifies the presented card (so the switchers animate present / dismiss
  /// / switch). Use a STABLE key per logical sheet so a re-present re-animates.
  final Key sheetKey;

  /// Background (scrim) tap → dismiss. `null` → inert tap (scrim still blocks below).
  final VoidCallback? onDismiss;

  const BottomSheetPresenter({
    super.key,
    required this.open,
    required this.child,
    required this.sheetKey,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // (1) Full-bleed dim scrim — fades in/out with the card. Blocks the host content
        // below (opaque GestureDetector absorbs taps) + closes on a background tap.
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: kSheetSlideDuration,
            switchInCurve: kSheetSlideCurve,
            switchOutCurve: kSheetSlideCurve,
            child: open
                // E2E key (INERT — KeyedSubtree paints nothing) on the tappable on-state
                // scrim. The functional `lb-sheet-scrim-on` identity key on the inner
                // GestureDetector is left UNCHANGED; the AnimatedSwitcher still distinguishes
                // the keyed on-state (this KeyedSubtree's key) from the off-state below.
                ? KeyedSubtree(
                    key: LbTestKeys.bottomSheetScrim,
                    child: GestureDetector(
                      key: const ValueKey('lb-sheet-scrim-on'),
                      behavior: HitTestBehavior.opaque,
                      onTap: onDismiss,
                      child: Container(
                        color: const Color(0x8C000000), // black @ 0.55 (iOS parity)
                      ),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('lb-sheet-scrim-off')),
          ),
        ),

        // (2) The bottom-anchored card with the shared present/dismiss slide. The
        // AnimatedSwitcher keeps the outgoing card rendered during the dismiss slide.
        Positioned.fill(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedSwitcher(
              duration: kSheetSlideDuration,
              switchInCurve: kSheetSlideCurve,
              switchOutCurve: kSheetSlideCurve,
              transitionBuilder: sheetSlideTransition,
              layoutBuilder: sheetBottomLayoutBuilder,
              child: (!open || child == null)
                  ? const SizedBox.shrink(key: ValueKey('lb-sheet-card-off'))
                  : KeyedSubtree(key: sheetKey, child: child!),
            ),
          ),
        ),
      ],
    );
  }
}
