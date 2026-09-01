import 'package:flutter/widgets.dart';

// sheet_slide_transition — shared bottom-sheet slide animation (rb-flutter-sheet-slide-consistency).
//
// Parity: iOS `BottomSheetPresenter.sheetSlide` + Android `ProductSheetsOverlayView.sheetEnter/
//          sheetExit` (rb-*-sheet-slide-consistency). The design `lbp-sheet-in` curve
//          (`cubic-bezier(0.32, 0.72, 0.18, 1)` / 0.32s). present → slide-up（卡片純位移）;
//          dismiss → slide-down（卡片純位移）.
//
// The card carries NO fade — design `lbp-sheet-in` is translate-only (opacity stays 1); the
// `lbp-fade-in` dim belongs to the scrim/`dimUnderneath`, not the card (rb-sheet-card-slide-only).
//
// Used with `AnimatedSwitcher` to animate a present/dismiss bottom sheet: switch the child
// between the sheet (when shown) and a `SizedBox.shrink()` (when hidden); the
// `transitionBuilder` slides the incoming sheet up + the outgoing sheet down. `AnimatedSwitcher`
// keeps the OUTGOING child rendered during the transition, so the dismiss animation has content
// to slide out for free (no manual last-content retention needed).

/// The shared sheet slide duration (design `lbp-sheet-in`, 0.32s).
const Duration kSheetSlideDuration = Duration(milliseconds: 320);

/// The shared sheet slide curve (design `lbp-sheet-in`, `cubic-bezier(0.32, 0.72, 0.18, 1)`).
const Curve kSheetSlideCurve = Cubic(0.32, 0.72, 0.18, 1.0);

/// `AnimatedSwitcher.transitionBuilder` for a bottom sheet: slide from below (`Offset(0, 1)` →
/// `Offset.zero`), translate-only (no fade — design `lbp-sheet-in`). The incoming child animates
/// 0→1 (slide up); the outgoing child's reversed animation 1→0 slides it down — so present slides
/// up and dismiss slides down. The card opacity stays 1 throughout (rb-sheet-card-slide-only).
Widget sheetSlideTransition(Widget child, Animation<double> animation) {
  return SlideTransition(
    position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(animation),
    child: child,
  );
}

/// `AnimatedSwitcher.layoutBuilder` that BOTTOM-anchors the switched children (the sheet card)
/// — `AnimatedSwitcher` has no `alignment` param and its default layout centers; a bottom-center
/// Stack makes the slide travel the card height from below and keeps the sheet pinned to the
/// bottom edge.
Widget sheetBottomLayoutBuilder(Widget? currentChild, List<Widget> previousChildren) {
  return Stack(
    alignment: Alignment.bottomCenter,
    children: <Widget>[
      ...previousChildren,
      if (currentChild != null) currentChild,
    ],
  );
}
