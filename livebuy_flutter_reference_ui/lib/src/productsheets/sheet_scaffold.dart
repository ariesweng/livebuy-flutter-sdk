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
/// `LBPBottomSheet`，parity Android — supersedes `rb-flutter-product-sheet-resize-fav-inline`'s
/// opt-in `draggable` + dead-fixed 25% floor with no dismiss concept）: EVERY presentation gets
/// one continuous handle-drag gesture, no opt-in flag — there is no longer a "non-draggable
/// `LBSheetScaffold`". Dragging UP grows the card from its STRUCTURAL floor
/// (`_floorFraction` — the presentation's own default/resting height) toward a shared 80%
/// ([kSheetResizeCeilingFraction]) CEILING; dragging DOWN — in the SAME gesture, or a later,
/// separate one — shrinks the RENDERED height back toward that same structural floor first, as
/// pure resize (release before reaching the floor holds the card at wherever it was let go, no
/// bounce). The DISMISS decision is a SEPARATE calculation (rb-flutter-sheetkit-resize-floor-
/// not-reanchored — see [_dismissFloorFraction]'s own doc for the full two-floor rationale and
/// the accepted trade-off it reintroduces, parity Android `rb-android-sheetkit-resize-floor-
/// reanchor-fix`): it measures a constant [kSheetDismissThresholdPx] of drag from THIS gesture's
/// OWN start, independent of the structural floor — release past it invokes [onDismiss]
/// (regardless of how far the rendered height has shrunk so far), else the card-follow peek
/// bounces back to the structural floor.
///
/// `_activeFloor` — the RESIZE floor — therefore stays FIXED at the structural floor across
/// every gesture (see that getter's own doc for the earlier, reverted design where a single
/// shared floor was re-anchored per-gesture, and the real-hardware bug that reversion fixes: a
/// short-content sheet, resized up then down in two separate gestures, could get visually stuck
/// with a large blank area no subsequent drag could shrink away). Only [_virtualFraction] —
/// where a NEW gesture's own accumulator starts counting from — is re-baselined at
/// [_onDragStart], so the drag still tracks the finger continuously from wherever the card is
/// currently rendered; the RESIZE floor it is clamped against never moves. [_dismissFloorFraction]
/// — the separate DISMISS floor — IS re-anchored every gesture, on purpose (see its own doc).
///
/// `_floorFraction` (the presentation's own default/resting height) is: for `fillToCap` leaves,
/// the constant cap itself (no measurement needed — the card always renders at exactly that
/// height); for content-sized leaves, the height actually rendered at first layout, LATCHED ONCE
/// (see `_latchFloorFromMeasurement`) and never re-measured for the rest of this presentation —
/// this is what keeps the drag path pure arithmetic with zero re-measurement feedback loop (no
/// SwiftUI-style `GeometryReader`/`PreferenceKey` jitter risk; see design.md).
///
/// 與 iOS 共用單一 `BottomSheetChrome` 畫「一個」grab handle（因此把拖曳手勢放在那顆共用 chrome
/// 上）不同，Flutter 的 grab handle 是**每個 leaf 各自畫**（`ProductDetailSheet` /
/// `NotifyRestockSheet` / `ProductListSheet` / `VideoInfoPanelView` 各有自己私有的
/// `_grabHandle()`，包在傳給這個 scaffold 的 [header] 裡）—— `BottomSheetPresenter`（scrim +
/// slide chrome）本身完全不畫任何把手、也不持有任何拖曳狀態。故拖曳手勢掛在**這裡**，包住呼叫端
/// 傳入的 [header]，讓這個能力完全留在「本就擁有 cap 計算」的同一個檔案內，對任何 leaf sheet 自己
/// 的 grab-handle 渲染零改動。
///
/// SCROLL RESET（`rb-flutter-recommendation-switch-scroll-reset`）：呼叫端可傳入
/// [scrollResetKey]（IDENTITY 值，如 `detail.productId`）——該值改變時，可捲動的 [body] 會被重置回
/// 頂部；預設 `null`／未傳時完全不影響既有行為。詳見該欄位自己的 doc comment。
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

  /// Scroll-reset identity token (rb-flutter-recommendation-switch-scroll-reset). The BODY's
  /// scroll offset resets to `0` whenever this value CHANGES between two builds of the SAME
  /// `LBSheetScaffold` `State` (`didUpdateWidget`, compared with `!=`) — e.g. a caller passing
  /// the current product's id so a same-slot "更多商品" recommendation tap (which swaps the
  /// bound content in place, no new `Key` / no remount — see `product_sheets_view.dart`'s
  /// `_buildDetailOrRestockSheet`) scrolls the sheet back to its top instead of preserving
  /// whatever offset the PREVIOUS product happened to leave it at.
  ///
  /// `null` (the DEFAULT) → NEVER resets — every existing call site (none of which pass this
  /// today) stays byte-identical. A caller that never changes this value between rebuilds
  /// (e.g. only `qty` / `variantSelection` changed, same product) also never resets — this is
  /// an IDENTITY comparison, not "did anything change".
  final Object? scrollResetKey;

  const LBSheetScaffold({
    super.key,
    required this.header,
    required this.body,
    required this.footer,
    this.fillToCap = false,
    this.heightFraction,
    this.onDismiss,
    this.scrollResetKey,
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
  /// completes (`fillToCap` leaves latch synchronously in [initState], never `null`). Read
  /// directly by every gesture's resize clamp + dismiss-offset math via [_activeFloor] — see
  /// that getter's own doc for why it is never re-anchored to anything else. It MUST NOT also
  /// govern the AT-REST render cap (see [build] — that was a real
  /// regression caught in review: latching this once and then using it as the render
  /// `maxHeight` itself froze a content-sized leaf's height at whatever it happened to be on
  /// first layout, so a later rebuild with taller content (e.g. a tab switch on the SAME
  /// `LBSheetScaffold` State — no remount, so no fresh latch) would clip/scroll into the STALE
  /// cap instead of growing to fit — a loss of the "follows content" behavior the leaf had
  /// before this drag feature existed. Mirrors iOS `BottomSheetChrome`: `floorFraction` (there,
  /// `measuredCardHeight`) is a DRAG-ONLY input; the undragged render cap is always the
  /// constant `capFraction`.
  double? _floorFraction;

  /// The unclamped, persistent "virtual" fraction the handle drag has accumulated (can dip
  /// below the active floor — that excess becomes the dismiss `dragOffset`). `null` until the
  /// first drag frame; stays `null` forever if the user never drags this presentation.
  ///
  /// Re-baselined to [_currentRenderedFraction] at the START of every new gesture ([_onDragStart])
  /// so a fresh touch-down continues smoothly from wherever the card is ACTUALLY resting right
  /// now, rather than jumping. This does NOT change which [floorFraction] gesture math clamps
  /// against — see [_activeFloor] — only where THIS gesture's own accumulator starts counting
  /// from.
  double? _virtualFraction;

  /// This GESTURE's own dismiss reference floor (rb-flutter-sheetkit-resize-floor-not-reanchored,
  /// parity Android `rb-android-sheetkit-resize-floor-reanchor-fix` / iOS `rb-ios-sheetkit-
  /// resize-shrink-after-grow-fix`) — re-anchored at the START of every gesture ([_onDragStart])
  /// to wherever the card is ACTUALLY resting right now. Read ONLY by [_onDragEnd]'s DISMISS
  /// decision — completely separate from [_activeFloor] (the STRUCTURAL floor, which governs the
  /// rendered height / card-follow peek in [build] and never moves).
  ///
  /// WHY TWO INDEPENDENT FLOORS: a single shared floor cannot satisfy both goals at once — (a)
  /// a downward drag should visibly shrink the card all the way back to its true structural
  /// floor on ANY gesture (this is [_activeFloor]'s job — see its own doc for the real-hardware
  /// bug this fixes), and (b) dismissing after a prior resize-up should still need only a
  /// constant [kSheetDismissThresholdPx] of drag, not that same full structural distance PLUS
  /// the threshold on top (which the ORIGINAL, pre-`rb-flutter-sheetkit-resize-floor-not-
  /// reanchored` design fixed by re-anchoring a single shared floor — the very re-anchoring
  /// [_activeFloor] no longer does, since it broke goal (a) instead). Android hit and fixed this
  /// exact tension first: feeding one shared "current height" floor into both the resize clamp
  /// AND the dismiss-excess calculation was itself the bug (`rb-android-sheetkit-dismiss-after-
  /// resize-fix` introduced it; `rb-android-sheetkit-resize-floor-reanchor-fix` split the two).
  /// This field is that split's Flutter counterpart — [_activeFloor] never re-anchors (goal a),
  /// this field always does (goal b).
  ///
  /// ACCEPTED TRADE-OFF (ported verbatim from Android's own documented one): because this floor
  /// can sit ABOVE [_activeFloor]'s structural value, [_onDragEnd] can decide to dismiss even
  /// while the card is STILL visibly shrinking toward the structural floor (the resize-relative
  /// `dragOffset` in [build] is still `0` — no card-follow peek has appeared yet). A user who
  /// drags down far enough with dismiss intent reaches that outcome regardless; this is not
  /// fixed here, matching Android's own accepted scope.
  double? _dismissFloorFraction;

  /// Bounce-back-to-floor animation (release under the dismiss threshold, or under a full
  /// resize-up — `null` when no bounce is in flight).
  AnimationController? _bounceController;

  /// The BODY's scroll controller (rb-flutter-recommendation-switch-scroll-reset). Persistent
  /// for the lifetime of this `State` — shared by whichever of the two `SingleChildScrollView`
  /// branches ([effectiveFillToCap]'s `Expanded` vs `Flexible` wrapper) is currently mounted
  /// (the two are mutually exclusive at any instant, so a single controller never attaches to
  /// two `ScrollPosition`s at once). [didUpdateWidget] is the only place it is driven directly
  /// (via [widget.scrollResetKey]); nothing else in this file reads its offset.
  final ScrollController _bodyScrollController = ScrollController();

  double get _defaultFraction => LBSheetScaffold.defaultFraction(
        fillToCap: widget.fillToCap,
        heightFraction: widget.heightFraction,
      );

  /// The floor fed into every gesture's resize clamp + dismiss-offset math
  /// (rb-flutter-sheetkit-resize-floor-not-reanchored) — ALWAYS this presentation's own
  /// STRUCTURAL floor ([_floorFraction], its natural default/resting height), regardless of
  /// which gesture (first or a later, separate one) is currently dragging.
  ///
  /// Deliberately NOT re-anchored to "wherever the card currently sits" (an earlier design,
  /// `rb-flutter-sheetkit-dismiss-after-resize-fix`, tried that — see design.md's own retired
  /// Decision for why it was reverted): re-anchoring made a SEPARATE gesture's downward drag,
  /// after a PRIOR gesture had resized the card up, count toward the dismiss threshold from the
  /// very first pixel — a user who just wanted to shrink the card back to its normal size in a
  /// second, distinct drag had NO way to do that; every down-drag either bounced back to the
  /// SAME oversized height or dismissed the whole sheet outright, with no reachable middle
  /// ground (confirmed on real hardware — a 3-item product list, dragged up then down in two
  /// separate gestures, left a large blank area below its content that no subsequent drag could
  /// shrink away). Keeping the floor fixed at the structural value restores "drag down → shrinks
  /// toward the normal size first, only converts to a dismiss past that point" for every gesture,
  /// including a later, separate one. See [_onDragStart] for the accepted trade-off this
  /// reintroduces (dismissing straight from a resized-up state again needs a longer drag).
  double get _activeFloor => _floorFraction ?? _defaultFraction;

  /// The height fraction ACTUALLY rendered right now — [SheetDragState.heightFraction] under
  /// the current [_activeFloor] and the shared ceiling. `null` [_virtualFraction] (never
  /// dragged) → the structural floor (or the default fraction before it latches).
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

  @override
  void didUpdateWidget(covariant LBSheetScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    // rb-flutter-recommendation-switch-scroll-reset: an IDENTITY change (not merely
    // non-null) — a caller that never sets `scrollResetKey` (both `null`) never resets, and a
    // caller whose value happens to stay the same across a rebuild (same product, only e.g.
    // `qty`/`variantSelection` changed) also never resets. Mirrors this package's existing
    // `chat_feed.dart` `_ScrollableChatFeedState.didUpdateWidget` convention: schedule the jump
    // via `addPostFrameCallback` (this callback runs BEFORE the body's own rebuild lands, so the
    // scroll controller may not have a `ScrollPosition` attached yet this frame) and guard with
    // `hasClients` before touching it.
    if (widget.scrollResetKey != oldWidget.scrollResetKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _bodyScrollController.hasClients) {
          _bodyScrollController.jumpTo(0);
        }
      });
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
    // rb-flutter-sheetkit-resize-floor-not-reanchored: re-baseline the accumulator to wherever
    // the card is ACTUALLY (visually) resting right now — never reuse a stale value from a
    // previous gesture, and never the raw unclamped `_virtualFraction` (a prior gesture that
    // overshot past the ceiling leaves it far above what is actually rendered; re-baselining to
    // that raw overshoot instead of the visually-rendered height would make a fresh drag's delta
    // insignificant relative to the large, invisible gap). This only affects where THIS
    // gesture's drag STARTS counting from — it does NOT change [_activeFloor] itself, which
    // stays the fixed structural floor for every gesture (see its own doc for why). Byte-
    // identical no-op for the presentation's first gesture and for any gesture that never
    // overshot the ceiling.
    final double current = _currentRenderedFraction(screenHeight);
    _virtualFraction = current;
    // This gesture's OWN dismiss reference — see [_dismissFloorFraction]'s own doc for why this
    // is a SEPARATE re-anchored value from the structural [_activeFloor] above.
    _dismissFloorFraction = current;
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
    final double resizeFloor = _activeFloor;
    final double dismissFloor = _dismissFloorFraction ?? resizeFloor;
    final double virtual = _virtualFraction ?? resizeFloor;

    // Dismiss decision FIRST, against the GESTURE's OWN dismiss floor
    // (rb-flutter-sheetkit-resize-floor-not-reanchored) — parity Android's `onDragEnd` checking
    // `dragShouldDismiss(computeDismissExcessPx(..., floorFraction = startDismissFloor), ...)`
    // unconditionally, before any resize-hold/bounce branch. See [_dismissFloorFraction]'s own
    // doc for why this can fire even while the resize-relative `dragOffset` below is still `0`
    // (the accepted trade-off).
    final double dismissExcess = sheetDragState(
      virtualFraction: virtual,
      floorFraction: dismissFloor,
      screenHeight: screenHeight,
    ).dragOffset;
    if (sheetShouldDismiss(dismissExcess)) {
      // Deliberately does NOT reset `_virtualFraction` here — the residual drag offset
      // stacks additively (same direction) with the presenter's own exit slide instead of
      // snapping back first. See design.md Decision 5.
      widget.onDismiss?.call();
      return;
    }

    // not dismissing: resize-floor-relative decision (hold vs bounce the card-follow peek).
    final SheetDragState visual = sheetDragState(
      virtualFraction: virtual,
      floorFraction: resizeFloor,
      screenHeight: screenHeight,
    );
    // Pure resize (up, or down but not yet past the structural floor) — MUST hold the height
    // as released, no bounce / no dismiss judgement (spec: "使用者在尚未觸及下限以下的任何時刻
    // 放手...卡片 SHALL 維持放手當下的高度，MUST NOT 彈回、MUST NOT 觸發關閉判斷").
    if (visual.dragOffset <= 0) return;
    _bounceBackToFloor(resizeFloor);
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
    _bodyScrollController.dispose();
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
              ? Expanded(
                  child: SingleChildScrollView(
                      controller: _bodyScrollController, child: widget.body))
              : Flexible(
                  child: SingleChildScrollView(
                      controller: _bodyScrollController, child: widget.body)),
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
///
/// **Fade-in on a genuine async decode** (rb-flutter-product-image-loading-polish):
/// the overlaid image fades in from the placeholder over [kProductImageFadeInDuration]
/// UNLESS it resolved synchronously from cache (e.g. warmed ahead of time by
/// `PlayerShellView`'s `precacheImage` prefetch — see `product_image_prefetch.dart`),
/// in which case it renders instantly with no animation — see [_fadeInFrameBuilder].
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
  // TEST SEAM (`docs/unit-test-discipline.md` naming contract) — `null` (default, every
  // existing call site + host runtime) keeps the exact `Image.network(...)` branch below,
  // byte-identical to before this seam existed. A widget / golden test that needs to
  // exercise ACTUAL decoded pixel content (not just the placeholder — `Image.network`
  // never resolves in a test environment with no network) may set this to a zero-network
  // synthetic [ImageProvider] for the duration of one test, then reset it to `null`.
  // MUST NOT be mutated outside `test/` (`rb-flutter-product-detail-main-image-scale-down-
  // letterbox` verifier fix).
  final ImageProvider? testProvider = liveProductImageProviderForTesting?.call(uri.toString());
  final Widget image = testProvider != null
      ? Image(
          image: testProvider,
          fit: fit,
          width: double.infinity,
          height: double.infinity,
          loadingBuilder: (context, child, progress) =>
              progress == null ? child : const SizedBox.expand(),
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
          frameBuilder: _fadeInFrameBuilder,
        )
      : Image.network(
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
          // rb-flutter-product-image-loading-polish: a cache-hit (e.g. warmed by
          // `PlayerShellView`'s prefetch) renders instantly, unanimated; a genuine
          // async decode fades in — see `_fadeInFrameBuilder`'s own doc comment.
          frameBuilder: _fadeInFrameBuilder,
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

/// Fade-in duration for [liveProductImage]'s overlaid photo when it decodes
/// ASYNCHRONOUSLY (cache miss) — see [_fadeInFrameBuilder]. 180ms.
const Duration kProductImageFadeInDuration = Duration(milliseconds: 180);

/// Shared `Image.frameBuilder` for [liveProductImage]'s two branches (the real
/// `Image.network` + the [liveProductImageProviderForTesting] test seam) —
/// rb-flutter-product-image-loading-polish. `wasSynchronouslyLoaded == true` (the
/// frame was already available — a cache hit, e.g. one this package's own
/// `precacheImage` prefetch warmed) returns [child] UNCHANGED, no animation: a warm
/// cache hit renders exactly as it did before this fade-in existed. `false` (a
/// genuine async decode) fades in via the canonical Flutter recipe — `AnimatedOpacity`
/// driven by [frame] itself (`null` while still decoding → opacity `0`, the first
/// decoded frame → opacity `1`): the SAME `AnimatedOpacity` element persists across
/// that transition (same position in the tree, across the SAME underlying `Image`
/// element's rebuilds), which is what makes it animate the opacity change rather than
/// snap straight to the end value.
Widget _fadeInFrameBuilder(
  BuildContext context,
  Widget child,
  int? frame,
  bool wasSynchronouslyLoaded,
) {
  if (wasSynchronouslyLoaded) return child;
  return AnimatedOpacity(
    opacity: frame == null ? 0.0 : 1.0,
    duration: kProductImageFadeInDuration,
    curve: Curves.easeOut,
    child: child,
  );
}

/// TEST SEAM — see [liveProductImage]'s doc comment above. `null` by default (host
/// runtime + every pre-existing call site): the real `Image.network(url)` path.
@visibleForTesting
ImageProvider Function(String url)? liveProductImageProviderForTesting;

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
