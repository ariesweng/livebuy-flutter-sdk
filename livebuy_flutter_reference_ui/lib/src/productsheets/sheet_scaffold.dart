import 'package:flutter/widgets.dart';

import '../reference_ui_image_url.dart';
import '../sheet_slide_transition.dart';
import '../testing/lb_test_keys.dart';

// sheet_scaffold.dart — shared family-3 bottom-sheet layout + gated product image.
//
// Parity: iOS `LivebuyReferenceUI/SheetKit/BottomSheetPresenter.swift`
//   (`LBSheetScaffold`, rb-ios-sheet-pinned-header-footer) + the `live` real-image
//   gating threaded through every product-sheet surface (rb-ios-product-real-images)
//   and Android's equivalent sheet scaffold / `RemoteProductImage`.
//
// Two reusable pieces the four family-3 surfaces share so they read as one family:
//
//   1. [LBSheetScaffold] — a bottom sheet with a PINNED header + PINNED footer and a
//      SCROLLABLE body, capped at a screen-height fraction (`fillToCap ? 0.4 : 0.5` by
//      default, overridable per-caller via `heightFraction`). The header (title / close /
//      grab handle) and footer (CTA / toggle) stay fixed while only the body scrolls; a
//      short (non-`fillToCap`) sheet stays content-sized, a `fillToCap` sheet always fills
//      to the cap. EVERY presentation (rb-flutter-sheetkit-resize-dismiss-unify — takes
//      over from rb-flutter-product-sheet-resize-fav-inline's opt-in `draggable`) gets a
//      unified drag: the caller's grab handle (inside `header`) resizes the card live
//      between this presentation's FLOOR (its own default/resting height — the `fillToCap`
//      constant, or, for content-sized leaves, the height actually rendered at first layout,
//      latched once) and a shared 80% CEILING; dragging DOWN past the floor converts the
//      excess into a drag-to-dismiss offset (`onDismiss` past `kSheetDismissThresholdPx`,
//      else bounces back to the floor). See the class doc for the full contract and why the
//      gesture lives here, not in `bottom_sheet_presenter.dart`.
//
//   2. [liveProductImage] — the `live` real-image gate. `live == false` (demo /
//      golden) draws ONLY the deterministic [placeholder] (so goldens are
//      byte-stable — no network). `live == true` (host runtime) overlays
//      `Image.network(url)` on top, falling back to the placeholder on load / error.
//
// RENDERING NOTE: unlike the iOS snapshot path (`ImageRenderer` renders `ScrollView`
// content BLANK, so iOS goldens use an `uncapped` flag), the Flutter golden path
// renders a real `SingleChildScrollView` correctly. So the scaffold needs NO snapshot
// escape hatch — the golden reflects the pinned layout directly.

/// The result of one drag frame: the sheet's live height fraction and the excess (in
/// logical pixels) pushed past this presentation's floor — the latter is the
/// drag-to-dismiss offset once positive. `dragOffset > 0` implies
/// `heightFraction == floorFraction` (mutually exclusive at every instant — see
/// [sheetDragState]).
class SheetDragState {
  final double heightFraction;
  final double dragOffset;
  const SheetDragState({required this.heightFraction, required this.dragOffset});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SheetDragState &&
          other.heightFraction == heightFraction &&
          other.dragOffset == dragOffset);

  @override
  int get hashCode => Object.hash(heightFraction, dragOffset);

  @override
  String toString() =>
      'SheetDragState(heightFraction: $heightFraction, dragOffset: $dragOffset)';
}

/// Shared resize ceiling across every bottom sheet (rb-flutter-sheetkit-resize-dismiss-unify,
/// parity iOS `resizeCeilingFraction` / Android — dragging the handle up never grows the card
/// past 80% of the screen, regardless of the sheet's own floor).
const double kSheetResizeCeilingFraction = 0.80;

/// Pure: applies one frame's incremental drag delta ([deltaY], `DragUpdateDetails.delta.dy`
/// sign — negative = finger moved UP) to a running, UNCLAMPED "virtual" fraction. Dragging up
/// increases it; dragging down decreases it — no clamping here. Keeping this step unclamped
/// (deferring clamping to [sheetDragState]) is what makes reversal (drag past the floor into
/// dismiss-offset territory, then drag back up) fall out of the math for free, with no extra
/// branching for "am I currently past the floor".
///
/// `screenHeight <= 0`（defensive — 真實裝置不會發生）回傳 [virtualFraction] 原值。
double advanceVirtualFraction({
  required double virtualFraction,
  required double deltaY,
  required double screenHeight,
}) {
  if (screenHeight <= 0) return virtualFraction;
  return virtualFraction - (deltaY / screenHeight);
}

/// Pure: derives the live (heightFraction, dragOffset) pair from the unclamped virtual
/// fraction (see [advanceVirtualFraction]). `heightFraction` clamps [virtualFraction] into
/// `[floorFraction, max(ceilingFraction, floorFraction)]` (the `max` is a defensive guard —
/// every real presentation's floor is well under the shared ceiling); `dragOffset` is the
/// (always >= 0) excess in logical pixels once [virtualFraction] dips below [floorFraction].
SheetDragState sheetDragState({
  required double virtualFraction,
  required double floorFraction,
  required double screenHeight,
  double ceilingFraction = kSheetResizeCeilingFraction,
}) {
  final double ceiling = ceilingFraction < floorFraction ? floorFraction : ceilingFraction;
  double heightFraction = virtualFraction;
  if (heightFraction < floorFraction) heightFraction = floorFraction;
  if (heightFraction > ceiling) heightFraction = ceiling;
  final double dragOffset = (screenHeight > 0 && virtualFraction < floorFraction)
      ? (floorFraction - virtualFraction) * screenHeight
      : 0.0;
  return SheetDragState(heightFraction: heightFraction, dragOffset: dragOffset);
}

/// The shared drag-to-dismiss pixel threshold (rb-flutter-sheetkit-resize-dismiss-unify —
/// established here since Flutter had NO prior drag-to-dismiss mechanism on any bottom sheet;
/// chosen to match the already-established cross-platform convention, iOS `dismissThreshold`
/// 100pt / Android `100.dp`, 1:1 numeric parity — not an arbitrary default).
const double kSheetDismissThresholdPx = 100.0;

/// Pure: whether an accumulated dismiss-drag offset ([dragOffset], logical pixels, from
/// [SheetDragState.dragOffset]) should close the sheet on release.
bool sheetShouldDismiss(double dragOffset, {double threshold = kSheetDismissThresholdPx}) =>
    dragOffset > threshold;

/// A bottom sheet with a pinned [header], a scrollable [body], and a pinned [footer],
/// capped at a screen-height fraction. The header + footer stay fixed; the body scrolls
/// within `cap − header − footer`. Short sheets（非 `fillToCap`）stay content-sized.
///
/// Mirrors iOS `LBSheetScaffold` (`VStack { header; ScrollView{body}; footer }` within
/// the cap) — the four family-3 sheets wrap their three regions in this so the chrome
/// pins and only the body scrolls.
///
/// DRAG-RESIZE + DRAG-TO-DISMISS（rb-flutter-sheetkit-resize-dismiss-unify，design
/// `LBPBottomSheet`，parity iOS `BottomSheetChrome.dragState` / Android — supersedes
/// `rb-flutter-product-sheet-resize-fav-inline`'s opt-in `draggable` + dead-fixed 25% floor
/// with no dismiss concept）: EVERY presentation gets one continuous handle-drag gesture,
/// no opt-in flag — there is no longer a "non-draggable `LBSheetScaffold`". Dragging UP
/// grows the card from the CURRENT GESTURE's floor toward a shared 80%
/// ([kSheetResizeCeilingFraction]) CEILING; dragging DOWN shrinks it back toward that same
/// floor; once at the floor, further downward drag converts the excess into a drag-to-dismiss
/// offset — release past [kSheetDismissThresholdPx] invokes [onDismiss], else the card
/// bounces back to that floor.
///
/// GESTURE FLOOR RE-ANCHORING（rb-flutter-sheetkit-dismiss-after-resize-fix）: the floor fed
/// into the drag math is re-anchored at the START of every new gesture (see
/// `_gestureFloorFraction` / `_activeFloor`) to whatever height the card is ACTUALLY resting
/// at right now — NOT the presentation's original structural floor (`_floorFraction`). The
/// very FIRST gesture of a presentation is unaffected (the card is still at its structural
/// floor then, so the gesture floor equals it exactly — byte-identical to "never dragged up").
/// Once the user has resized up at least once, a LATER, separate gesture's floor is wherever
/// the card currently sits — so dragging down in that later gesture counts toward the dismiss
/// threshold immediately, instead of first needing to travel all the way back down to the
/// original structural floor (which, from near the 80% ceiling, routinely exceeds what a
/// single touch can physically cover — this was the reported "can't dismiss after resizing
/// up" bug). See the class doc's `_gestureFloorFraction` field for the full rationale.
///
/// `_floorFraction` (the presentation's own default/resting height — STRUCTURAL, not the
/// per-gesture value) is: for `fillToCap` leaves, the constant cap itself (no measurement
/// needed — the card always renders at exactly that height); for content-sized leaves, the
/// height actually rendered at first layout, LATCHED ONCE (see `_latchFloorFromMeasurement`)
/// and never re-measured for the rest of this presentation — this is what keeps the drag path
/// pure arithmetic with zero re-measurement feedback loop (no SwiftUI-style
/// `GeometryReader`/`PreferenceKey` jitter risk; see design.md). It now only seeds the FIRST
/// gesture's floor (via `_gestureFloorFraction`) rather than being read directly by the drag
/// math on every gesture.
///
/// 與 iOS 共用單一 `BottomSheetChrome` 畫「一個」grab handle（因此把拖曳手勢放在那顆共用 chrome
/// 上）不同，Flutter 的 grab handle 是**每個 leaf 各自畫**（`ProductDetailSheet` /
/// `NotifyRestockSheet` / `ProductListSheet` / `VideoInfoPanelView` 各有自己私有的
/// `_grabHandle()`，包在傳給這個 scaffold 的 [header] 裡）—— `BottomSheetPresenter`（scrim +
/// slide chrome）本身完全不畫任何把手、也不持有任何拖曳狀態。故拖曳手勢掛在**這裡**，包住呼叫端
/// 傳入的 [header]，讓這個能力完全留在「本就擁有 cap 計算」的同一個檔案內，對任何 leaf sheet 自己
/// 的 grab-handle 渲染零改動。
class LBSheetScaffold extends StatefulWidget {
  /// Pinned header (title / tabs / close / grab handle). Never scrolls. This is always the
  /// drag-resize/dismiss target (wrapped in a `GestureDetector`).
  final Widget header;

  /// Scrollable body (photo / variant chips / qty / etc.). Scrolls within the cap.
  final Widget body;

  /// Pinned footer (CTA / toggle). Never scrolls.
  final Widget footer;

  /// `true` → 固定高度填滿到 cap（內容頂部對齊、footer 釘底、不足處下方留白、超出捲動）。
  /// `false`（預設）→ content-sized，cap 只當上限（既有行為）。
  final bool fillToCap;

  /// 明確的螢幕高度比例覆寫。`null`（預設）→ 沿用既有常數（`fillToCap ? 0.4 : 0.5`，對既有
  /// 呼叫點 byte-identical）。
  final double? heightFraction;

  /// Drag-to-dismiss forwarding (rb-flutter-sheetkit-resize-dismiss-unify): invoked once when
  /// the user drags the handle past this presentation's floor by more than
  /// [kSheetDismissThresholdPx] and releases. `null` → the drag still tracks visually but
  /// releasing past the threshold is inert (no dismiss) — matches the existing no-op contract
  /// for a `null` close callback elsewhere in this package.
  final VoidCallback? onDismiss;

  const LBSheetScaffold({
    super.key,
    required this.header,
    required this.body,
    required this.footer,
    this.fillToCap = false,
    this.heightFraction,
    this.onDismiss,
  });

  /// 沒有任何使用者拖曳時這個 scaffold 會用的比例 —— 既有的 `fillToCap ? 0.4 : 0.5` 常數，可被
  /// [heightFraction] 覆寫。抽成 static pure helper，讓 build 與測試共用同一份計算。
  static double defaultFraction({
    required bool fillToCap,
    double? heightFraction,
  }) =>
      heightFraction ?? (fillToCap ? 0.4 : 0.5);

  @override
  State<LBSheetScaffold> createState() => _LBSheetScaffoldState();
}

class _LBSheetScaffoldState extends State<LBSheetScaffold>
    with SingleTickerProviderStateMixin {
  /// Pinned to the outermost rendered box — used ONCE (post first frame) to measure this
  /// presentation's floor for non-`fillToCap` leaves. See `_latchFloorFromMeasurement`.
  final GlobalKey _measureKey = GlobalKey();

  /// This presentation's STRUCTURAL floor (its own default/resting height) — latched once,
  /// `null` only for the single frame before a content-sized leaf's post-frame measurement
  /// completes (`fillToCap` leaves latch synchronously in [initState], never `null`). As of
  /// `rb-flutter-sheetkit-dismiss-after-resize-fix` this is no longer read directly by the
  /// drag math (`_onDragUpdate` / `_onDragEnd` / [build]) — it only SEEDS the very first
  /// gesture's floor via [_gestureFloorFraction] / [_activeFloor] (see that field's doc for
  /// why). It MUST NOT also govern the AT-REST render cap (see [build] — that was a real
  /// regression caught in review: latching this once and then using it as the render
  /// `maxHeight` itself froze a content-sized leaf's height at whatever it happened to be on
  /// first layout, so a later rebuild with taller content (e.g. a tab switch on the SAME
  /// `LBSheetScaffold` State — no remount, so no fresh latch) would clip/scroll into the STALE
  /// cap instead of growing to fit — a loss of the "follows content" behavior the leaf had
  /// before this drag feature existed. Mirrors iOS `BottomSheetChrome`: `floorFraction` (there,
  /// `measuredCardHeight`) is a DRAG-ONLY input; the undragged render cap is always the
  /// constant `capFraction`.
  double? _floorFraction;

  /// The floor ACTUALLY used by the CURRENT (or most recently completed) gesture's resize
  /// clamp + dismiss-offset math (rb-flutter-sheetkit-dismiss-after-resize-fix). Re-anchored
  /// at the START of every new gesture ([_onDragStart]) to whatever height the card is
  /// ACTUALLY resting at right now — see [_activeFloor]. `null` only before the presentation's
  /// very first drag frame.
  ///
  /// WHY THIS EXISTS: `sheetDragState`'s `dragOffset` is `(floor − virtualFraction) ×
  /// screenHeight` once `virtualFraction` dips below `floor`. Feeding it the STRUCTURAL floor
  /// ([_floorFraction], this presentation's natural resting height — typically 40–50% of the
  /// screen) meant that after a PRIOR gesture had resized the card up toward the 80% ceiling,
  /// dismissing required first dragging all the way back down to that structural floor — often
  /// 40–50% of the screen height — PLUS the 100px dismiss threshold on top, a total distance
  /// that routinely exceeds what a single continuous drag gesture can cover on a touchscreen,
  /// so the card was practically stuck open. Worse, [_floorFraction] and [_virtualFraction] are
  /// both STATE-level fields that persist for the whole presentation, not per-gesture — unlike
  /// SwiftUI's `DragGesture.translation`, which zeroes automatically for every new gesture, a
  /// brand-new Flutter gesture (release, then touch down again) got NO relief either, since
  /// nothing here ever re-anchored to the current position.
  ///
  /// Re-anchoring the floor to the CURRENT height at the start of every gesture fixes this:
  /// any downward drag from wherever the card currently sits now counts immediately toward the
  /// dismiss threshold — resize-up no longer moves the goalposts for the next dismiss attempt.
  /// A known, accepted side effect: once a presentation has been resized up at least once, a
  /// LATER gesture can no longer "shrink back down toward the structural floor" as a pure
  /// resize step first — any further downward movement in that later gesture is
  /// drag-to-dismiss territory from the first pixel (this independently converges with iOS's
  /// `rb-ios-sheetkit-resize-dismiss-separate-gestures` architecture, where the down branch is
  /// `max(0, translation.height)` with zero dependency on the resize floor — reached via a
  /// separate analysis of iOS's own SwiftUI gesture model, not copied). The presentation's very
  /// FIRST gesture is unaffected — `_virtualFraction == null` at that point, so
  /// [_activeFloor] equals [_floorFraction] exactly, preserving the existing "never dragged up"
  /// byte-identical contract.
  double? _gestureFloorFraction;

  /// The unclamped, persistent "virtual" fraction the handle drag has accumulated (can dip
  /// below the active floor — that excess becomes the dismiss `dragOffset`). `null` until the
  /// first drag frame; stays `null` forever if the user never drags this presentation.
  double? _virtualFraction;

  /// Bounce-back-to-floor animation (release under the dismiss threshold, or under a full
  /// resize-up — `null` when no bounce is in flight).
  AnimationController? _bounceController;

  double get _defaultFraction => LBSheetScaffold.defaultFraction(
        fillToCap: widget.fillToCap,
        heightFraction: widget.heightFraction,
      );

  /// The floor actually fed into the drag math right now (rb-flutter-sheetkit-dismiss-after-
  /// resize-fix) — the current gesture's re-anchored floor if one has started, else the
  /// presentation's structural floor, else the default fraction. See [_gestureFloorFraction]'s
  /// doc for the full rationale.
  double get _activeFloor => _gestureFloorFraction ?? _floorFraction ?? _defaultFraction;

  /// The height fraction ACTUALLY rendered right now (rb-flutter-sheetkit-dismiss-after-
  /// resize-fix) — i.e. [SheetDragState.heightFraction] under the floor/ceiling that governed
  /// the PREVIOUS gesture (or the structural floor, before any gesture has ever run).
  ///
  /// MUST be used (not raw [_virtualFraction]) when re-anchoring [_gestureFloorFraction] at a
  /// new gesture's start: [_virtualFraction] is deliberately UNCLAMPED (see
  /// [advanceVirtualFraction]) and is never clamped back down after a resize-up gesture ends —
  /// a large upward drag can leave it far past the 80% ceiling even though the card visually
  /// rendered (and held) at exactly the ceiling. Re-anchoring a new gesture's floor to that raw
  /// overshot value instead of the visually-rendered ceiling would make the new gesture
  /// (incorrectly) require dragging back down past the overshoot before anything registers.
  double _currentRenderedFraction(double screenHeight) {
    final double? virtual = _virtualFraction;
    if (virtual == null) return _floorFraction ?? _defaultFraction;
    return sheetDragState(
      virtualFraction: virtual,
      floorFraction: _activeFloor,
      screenHeight: screenHeight,
    ).heightFraction;
  }

  @override
  void initState() {
    super.initState();
    if (widget.fillToCap) {
      // Always renders at exactly defaultFraction*screenHeight — the floor equals that
      // constant algebraically, no measurement needed.
      _floorFraction = _defaultFraction;
    } else {
      WidgetsBinding.instance.addPostFrameCallback(_latchFloorFromMeasurement);
    }
  }

  /// Latches [_floorFraction] to the height ACTUALLY rendered at the first stable layout
  /// (content-sized leaves only). Runs at most once per presentation — once
  /// `_floorFraction != null` this is a no-op even if re-scheduled defensively, so the drag
  /// path (`_onDragUpdate`/`build`) never triggers a re-measurement.
  void _latchFloorFromMeasurement(Duration _) {
    if (!mounted || _floorFraction != null) return;
    final RenderObject? renderObject = _measureKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      // Not laid out yet (rare — defensive, not the normal path). Retry next frame.
      WidgetsBinding.instance.addPostFrameCallback(_latchFloorFromMeasurement);
      return;
    }
    final double screenHeight = MediaQuery.of(context).size.height;
    if (screenHeight <= 0) return;
    final double measured = (renderObject.size.height / screenHeight)
        .clamp(0.0, _defaultFraction);
    setState(() => _floorFraction = measured);
  }

  void _onDragStart(DragStartDetails details, double screenHeight) {
    _bounceController?.stop();
    // rb-flutter-sheetkit-dismiss-after-resize-fix: re-anchor THIS gesture's floor to
    // wherever the card is ACTUALLY (visually) resting right now — never reuse a stale value
    // from a previous gesture (that cross-gesture freeze is precisely the "調高後關不掉" bug
    // this fixes), and never the raw unclamped `_virtualFraction` (see
    // `_currentRenderedFraction`'s doc for why that would be wrong after an overshot
    // resize-up). See `_gestureFloorFraction`'s doc for the full rationale.
    final double current = _currentRenderedFraction(screenHeight);
    _gestureFloorFraction = current;
    // Also re-baseline the accumulator itself to the same (clamped) value: `_virtualFraction`
    // is UNCLAMPED and a prior gesture that overshot past the ceiling leaves it far above what
    // is actually rendered. Without this, `_onDragUpdate`'s `_virtualFraction ?? floor` would
    // keep accumulating from that stale overshoot instead of from the visible height, making a
    // fresh downward drag's delta insignificant relative to the (large, invisible) gap — the
    // exact same "goalposts moved" failure mode this whole fix targets, just re-introduced via
    // the accumulator instead of the floor. Byte-identical no-op for the presentation's first
    // gesture (there, `current` is already what `_onDragUpdate` would have started from) and
    // for any gesture that never overshot the ceiling.
    _virtualFraction = current;
  }

  void _onDragUpdate(DragUpdateDetails details, double screenHeight) {
    final double floor = _activeFloor;
    setState(() {
      _virtualFraction = advanceVirtualFraction(
        virtualFraction: _virtualFraction ?? floor,
        deltaY: details.delta.dy,
        screenHeight: screenHeight,
      );
    });
  }

  void _onDragEnd(DragEndDetails details, double screenHeight) {
    final double floor = _activeFloor;
    final SheetDragState state = sheetDragState(
      virtualFraction: _virtualFraction ?? floor,
      floorFraction: floor,
      screenHeight: screenHeight,
    );
    // Pure resize (up, or down but not yet past the floor) — MUST hold the height as
    // released, no bounce / no dismiss judgement (spec: "使用者在尚未觸及下限以下的任何時刻
    // 放手...卡片 SHALL 維持放手當下的高度，MUST NOT 彈回、MUST NOT 觸發關閉判斷").
    if (state.dragOffset <= 0) return;
    if (sheetShouldDismiss(state.dragOffset)) {
      // Deliberately does NOT reset `_virtualFraction` here — the residual drag offset
      // stacks additively (same direction) with the presenter's own exit slide instead of
      // snapping back first. See design.md Decision 5.
      widget.onDismiss?.call();
      return;
    }
    _bounceBackToFloor(floor);
  }

  void _bounceBackToFloor(double floor) {
    final double start = _virtualFraction ?? floor;
    if (start == floor) return;
    _bounceController?.dispose();
    final AnimationController controller =
        AnimationController(vsync: this, duration: kSheetSlideDuration);
    final Animation<double> animation = Tween<double>(begin: start, end: floor)
        .chain(CurveTween(curve: kSheetSlideCurve))
        .animate(controller);
    animation.addListener(() {
      if (!mounted) return;
      setState(() => _virtualFraction = animation.value);
    });
    _bounceController = controller;
    controller.forward();
  }

  @override
  void dispose() {
    _bounceController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double screenHeight = MediaQuery.of(context).size.height;
    final double floor = _activeFloor;
    final SheetDragState state = sheetDragState(
      virtualFraction: _virtualFraction ?? floor,
      floorFraction: floor,
      screenHeight: screenHeight,
    );
    // At rest (never dragged this presentation) the render cap is the CONSTANT
    // `_defaultFraction * screenHeight` — byte-identical to this leaf's pre-drag-feature cap
    // computation, and NOT derived from `_floorFraction` (a latch-once measurement that is a
    // DRAG-MATH input only — see `_floorFraction`'s doc for the regression this avoids: using
    // the latched value as the render cap itself would freeze a content-sized leaf's height at
    // whatever it happened to be on first layout, breaking "follows content" on a later
    // rebuild with different content in the SAME State, e.g. a tab switch). Once the user has
    // dragged (`_virtualFraction != null`), the drag-derived `state.heightFraction` governs —
    // matches iOS `heightFractionOverride ?? capFraction`.
    final double cap = _virtualFraction == null
        ? _defaultFraction * screenHeight
        : state.heightFraction * screenHeight;
    // Any active drag override (even one that settled back exactly at the floor) switches a
    // content-sized leaf into fill-mode for the rest of this presentation — mirrors iOS
    // `effectiveFillToCap = fillToCap || heightFractionOverride != nil`. Since the floor IS the
    // content's own natural rendered height, filling to exactly the floor renders identically
    // to the pre-drag content-sized layout (no visible jump).
    final bool effectiveFillToCap = widget.fillToCap || _virtualFraction != null;
    final Widget header = GestureDetector(
      key: LbTestKeys.sheetDragHandle,
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: (d) => _onDragStart(d, screenHeight),
      onVerticalDragUpdate: (d) => _onDragUpdate(d, screenHeight),
      onVerticalDragEnd: (d) => _onDragEnd(d, screenHeight),
      child: widget.header,
    );
    final Widget scaffold = ConstrainedBox(
      key: _measureKey,
      // effectiveFillToCap：固定 = cap（min == max）；否則上限 cap、content-sized。
      constraints: effectiveFillToCap
          ? BoxConstraints(minHeight: cap, maxHeight: cap)
          : BoxConstraints(maxHeight: cap),
      child: Column(
        mainAxisSize: effectiveFillToCap ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          // effectiveFillToCap：`Expanded` 填滿剩餘空間（內容頂部、下方留白 / 超出捲動）→ 整張
          // = cap；否則 `Flexible` content-sized（短 sheet 取內容高、長 sheet 捲動）。
          effectiveFillToCap
              ? Expanded(child: SingleChildScrollView(child: widget.body))
              : Flexible(child: SingleChildScrollView(child: widget.body)),
          widget.footer,
        ],
      ),
    );
    // Live-drag / residual dismiss offset — a no-op transform (Offset.zero) at rest.
    return state.dragOffset > 0
        ? Transform.translate(offset: Offset(0, state.dragOffset), child: scaffold)
        : scaffold;
  }
}

/// A gated product image: ALWAYS draws [placeholder]; when [live] is true AND [url]
/// is a non-empty/parseable http(s) URL, overlays `Image.network(url)` on top
/// (clipped to [borderRadius] when given), falling back to the placeholder while
/// loading or on error.
///
/// `live == false` (demo / golden) → ONLY the placeholder renders (no network →
/// byte-stable goldens). `live == true` (host runtime, real video surface) → the real
/// product photo loads over the placeholder. Parity with iOS `RemoteStillImageView`
/// gated by the sheets' `live` flag (rb-ios-product-real-images).
Widget liveProductImage({
  required bool live,
  required String? url,
  required Widget placeholder,
  BorderRadius? borderRadius,
  // How the loaded image fills the frame. Default `cover` (product-sheet thumbs fill). The widget
  // card cover + product chip pass `contain` so the WHOLE image shows (iOS `.scaleAspectFit`).
  BoxFit fit = BoxFit.cover,
}) {
  final Uri? uri = _httpUri(url);
  if (!live || uri == null) return placeholder;
  final Widget image = Image.network(
    uri.toString(),
    fit: fit,
    width: double.infinity,
    height: double.infinity,
    // While loading, keep the placeholder visible underneath (the Stack below
    // already draws it); fade in nothing extra — just show the frame when ready.
    loadingBuilder: (context, child, progress) =>
        progress == null ? child : const SizedBox.expand(),
    // On any decode / network error, fall back to the placeholder (draw nothing
    // over it — the Stack's placeholder stays visible).
    errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
  );
  final Widget overlay = borderRadius == null
      ? image
      : ClipRRect(borderRadius: borderRadius, child: image);
  return Stack(
    fit: StackFit.expand,
    children: [
      placeholder,
      Positioned.fill(child: overlay),
    ],
  );
}

/// Parse [s] into a non-empty http(s) [Uri], or null (empty / whitespace / non-http
/// → placeholder-only). Pure.
Uri? _httpUri(String? s) {
  // Upgrade a cleartext http:// pic to https:// before parsing — Flutter iOS ATS blocks
  // cleartext so Image.network would never load it → placeholder. https / non-http unchanged.
  final trimmed = referenceUiHttpsUpgraded(s?.trim());
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  return uri;
}
