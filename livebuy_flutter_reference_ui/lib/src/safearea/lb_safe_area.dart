import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

// lb_safe_area.dart — reference-ui 的 edge-to-edge 系統邊距（rb-flutter-edge-to-edge-safe-area-audit）
//
// Parity: Android `safearea/LBSafeArea.kt`（rb-android-edge-to-edge-window-insets）/ iOS SwiftUI
// 「內容待在 safe area 內、背景 `ignoresSafeArea()`」。Tier B 容器在 edge-to-edge 下讓 chrome 避開
// 狀態列、導覽／手勢列與 display cutout，影片／背景／scrim 維持滿版。
//
// Flutter 的分工與 Android 不同的地方只有「值怎麼傳」：
//
//   - Flutter 已經有一條會被上游消費的值管道——`MediaQuery`。`SafeArea`、`Scaffold`、
//     `MediaQuery.removePadding` 都會把自己處理掉的量從子樹的 `MediaQueryData` 扣掉。所以 Tier A
//     表面**直接讀 ambient `MediaQuery`**（[lbChromeSafeInsets]），不另外開一條 InheritedWidget。
//   - `MediaQuery` 看不到的是「host 只用一般 `Padding` 把容器推開、沒有同步改 `MediaQuery`」。
//     [LBSafeAreaScope]（Tier B 容器根）量出容器外框在 view 中的實際位置，把「已經被推離 view
//     邊緣的距離」從 ambient 值扣掉，再以覆寫過的 `MediaQuery` 交給子樹。
//
// 兩者都只會讓值變小，所以不論 host 用哪種寫法都不會出現雙重邊距。沒有 scope 的路徑（host 直接組
// Tier A、golden、widget test）讀到的就是 ambient 值本身——零就是零，排版與本機制落地前相同。

// MARK: - 純函式

/// chrome 要避開的系統列＋cutout 邊距（逐邊 `max(padding, viewPadding)`）。
///
/// `viewPadding` 是不受鍵盤影響的系統列量；`padding` 在鍵盤升起時底部會歸零。chrome 不該跟著鍵盤
/// 上下跳，所以底部以 `viewPadding` 為準。同時取 `padding` 是為了讓「只帶 `padding` 的
/// `MediaQueryData`」（既有測試與部分 host 覆寫的寫法）仍然有效。上游 `SafeArea`／
/// `MediaQuery.removePadding` 會同時扣掉兩者，`Scaffold` 為鍵盤縮小 body 時會把鍵盤那一段從
/// `viewPadding` 扣掉——兩種情況這裡讀到的都是「還沒被處理的量」。
EdgeInsets lbChromeSafeInsets(MediaQueryData mq) => EdgeInsets.fromLTRB(
      math.max(mq.padding.left, mq.viewPadding.left),
      math.max(mq.padding.top, mq.viewPadding.top),
      math.max(mq.padding.right, mq.viewPadding.right),
      math.max(mq.padding.bottom, mq.viewPadding.bottom),
    );

/// 含文字輸入的表面的底部邊距：導覽／手勢列與鍵盤取**較大值**，不相加（鍵盤的量是從 view 底緣
/// 量起的，本來就涵蓋導覽列那一段）。
double lbInputBottomInset({required double safeBottom, required double keyboardBottom}) =>
    math.max(math.max(safeBottom, keyboardBottom), 0);

/// [container]（view 座標）四個邊各自距離 view 邊緣多遠。容器貼齊邊緣 → 0；已被往內推 → 正值；
/// 超出 view（轉場中）→ 夾成 0。
EdgeInsets lbEdgeDistances({required Rect container, required Size viewSize}) =>
    EdgeInsets.fromLTRB(
      math.max(0, container.left),
      math.max(0, container.top),
      math.max(0, viewSize.width - container.right),
      math.max(0, viewSize.height - container.bottom),
    );

/// 從 [insets] 逐邊扣掉容器已經被推離 view 邊緣的 [distances]，不會是負值。
EdgeInsets lbSubtractHandled(EdgeInsets insets, EdgeInsets distances) => EdgeInsets.fromLTRB(
      math.max(0, insets.left - distances.left),
      math.max(0, insets.top - distances.top),
      math.max(0, insets.right - distances.right),
      math.max(0, insets.bottom - distances.bottom),
    );

/// 逐邊取小。
EdgeInsets lbMinInsets(EdgeInsets a, EdgeInsets b) => EdgeInsets.fromLTRB(
      math.min(a.left, b.left),
      math.min(a.top, b.top),
      math.min(a.right, b.right),
      math.min(a.bottom, b.bottom),
    );

/// 容器實際還需要自己避開的量：[ambient]（已扣掉上游消費）再扣掉容器外框的位置。
///
/// [placement] 為 `null`（尚未完成第一次 layout）或 [viewSize] 無效時無法判斷位置，原樣回傳
/// [ambient]。`padding`／`viewPadding`／`viewInsets` 三組都套同一份距離——鍵盤量也適用「host 已
/// 處理的不重複套用」。
MediaQueryData lbResolveSafeAreaMediaQuery(
  MediaQueryData ambient, {
  required Rect? placement,
  required Size? viewSize,
}) {
  if (placement == null || viewSize == null || viewSize.isEmpty) return ambient;
  final d = lbEdgeDistances(container: placement, viewSize: viewSize);
  return ambient.copyWith(
    padding: lbSubtractHandled(ambient.padding, d),
    viewPadding: lbSubtractHandled(ambient.viewPadding, d),
    viewInsets: lbSubtractHandled(ambient.viewInsets, d),
  );
}

/// [mq] 是否帶任何系統邊距或鍵盤量。全為零時 scope 不需要量測位置。
bool lbHasSystemInsets(MediaQueryData mq) =>
    mq.padding != EdgeInsets.zero ||
    mq.viewPadding != EdgeInsets.zero ||
    mq.viewInsets != EdgeInsets.zero;

/// 表面套用 [applied] 之後，子樹該看到的 `MediaQueryData`：把已套用的邊從 `padding`／
/// `viewPadding` 扣掉；[keyboard] 為 `true` 時連鍵盤量一起扣（表面已經待在鍵盤上方）。
MediaQueryData lbConsumeSafeArea(
  MediaQueryData mq, {
  required EdgeInsets applied,
  bool keyboard = false,
}) {
  final vp = lbSubtractHandled(mq.viewPadding, applied);
  final p = lbSubtractHandled(mq.padding, applied);
  if (!keyboard) return mq.copyWith(padding: p, viewPadding: vp);
  return mq.copyWith(
    padding: p,
    viewPadding: vp,
    viewInsets: lbSubtractHandled(mq.viewInsets, EdgeInsets.only(bottom: applied.bottom)),
  );
}

/// 浮窗卡片／浮動入口的拖曳容器：容器尺寸扣掉 safe-area 邊距。餵給既有的
/// `clampFloatingOffset`，後者「同一個 `inset` 同時定義靜止間距與拖曳邊界」的契約不變。
Size lbFloatingDragContainerSize(Size container, EdgeInsets safe) => Size(
      math.max(0, container.width - safe.horizontal),
      math.max(0, container.height - safe.vertical),
    );

/// 浮窗卡片／浮動入口的靜止邊距：`config.inset` 加上所屬角落那兩邊的 safe-area 量。
/// [anchorsLeft] 為 `true` 表示靜止在左下，否則右下。
Offset lbFloatingRestingInset(Offset inset, EdgeInsets safe, {required bool anchorsLeft}) =>
    Offset(inset.dx + (anchorsLeft ? safe.left : safe.right), inset.dy + safe.bottom);

// MARK: - 位置量測

/// scope 往下傳的「上游原始 ambient 值」。巢狀的 scope（`CollapsibleLivebuyPlayer` 內含
/// `LivebuyPlayer`）以它為基準各自扣自己的位置，值不會被扣兩次。
class _LBSafeAreaAmbient extends InheritedWidget {
  final MediaQueryData ambient;

  const _LBSafeAreaAmbient({required this.ambient, required super.child});

  @override
  bool updateShouldNotify(_LBSafeAreaAmbient oldWidget) => ambient != oldWidget.ambient;
}

/// 量測「容器外框在 view 中的位置」並解析出容器還需要自己避開的邊距。
///
/// 位置在每個 frame 結束後量一次（post-frame callback 自己重新排下一次；它不會主動要求新的
/// frame），所以 host 的轉場動畫結束時量到的是最終位置。只有解析結果真的改變才 `setState`。
/// ambient 全為零時完全不量測。
mixin LBSafeAreaPlacementTracking<T extends StatefulWidget> on State<T> {
  Rect? _lbPlacement;
  Size? _lbViewSize;
  MediaQueryData? _lbBase;
  MediaQueryData? _lbCurrent;
  MediaQueryData? _lbResolved;
  bool _lbArmed = false;

  /// 當作「容器外框」的 render box。預設是這個 State 自己的。
  RenderBox? lbSafeAreaTargetBox() {
    final ro = context.findRenderObject();
    return ro is RenderBox ? ro : null;
  }

  /// 在 `build` 內呼叫。回傳這個容器子樹該用的 `MediaQueryData`，以及要往下傳的原始基準值。
  ({MediaQueryData resolved, MediaQueryData base}) lbResolveSafeArea(BuildContext context) {
    final current = MediaQuery.of(context);
    final base =
        context.dependOnInheritedWidgetOfExactType<_LBSafeAreaAmbient>()?.ambient ?? current;
    _lbBase = base;
    _lbCurrent = current;
    final resolved = _lbCompute(base, current);
    _lbResolved = resolved;
    if (lbHasSystemInsets(base)) _lbArm();
    return (resolved: resolved, base: base);
  }

  MediaQueryData _lbCompute(MediaQueryData base, MediaQueryData current) {
    if (!lbHasSystemInsets(base)) return current;
    final byPosition =
        lbResolveSafeAreaMediaQuery(base, placement: _lbPlacement, viewSize: _lbViewSize);
    return current.copyWith(
      padding: lbMinInsets(current.padding, byPosition.padding),
      viewPadding: lbMinInsets(current.viewPadding, byPosition.viewPadding),
      viewInsets: lbMinInsets(current.viewInsets, byPosition.viewInsets),
    );
  }

  void _lbArm() {
    if (_lbArmed) return;
    _lbArmed = true;
    SchedulerBinding.instance.addPostFrameCallback(_lbMeasure);
  }

  void _lbMeasure(Duration _) {
    _lbArmed = false;
    if (!mounted) return;
    final base = _lbBase;
    final current = _lbCurrent;
    if (base == null || current == null || !lbHasSystemInsets(base)) return;
    final box = lbSafeAreaTargetBox();
    if (box != null && box.attached && box.hasSize) {
      final view = View.of(context);
      _lbViewSize = view.physicalSize / view.devicePixelRatio;
      _lbPlacement = MatrixUtils.transformRect(box.getTransformTo(null), Offset.zero & box.size);
      final next = _lbCompute(base, current);
      final prev = _lbResolved;
      if (prev == null ||
          prev.padding != next.padding ||
          prev.viewPadding != next.viewPadding ||
          prev.viewInsets != next.viewInsets) {
        setState(() {});
      }
    }
    _lbArm();
  }
}

// MARK: - Widgets

/// Tier B 容器的 safe-area 量測點。本身**不套任何邊距**——影片與背景因此維持滿版；它只把
/// 「這個容器還需要自己避開多少」以覆寫過的 `MediaQuery` 交給子樹，真正的邊距由各 chrome 表面
/// 自己套。巢狀使用是安全的（內層以最外層看到的原始值為基準重新計算）。
class LBSafeAreaScope extends StatefulWidget {
  final Widget child;

  const LBSafeAreaScope({super.key, required this.child});

  @override
  State<LBSafeAreaScope> createState() => _LBSafeAreaScopeState();
}

class _LBSafeAreaScopeState extends State<LBSafeAreaScope>
    with LBSafeAreaPlacementTracking<LBSafeAreaScope> {
  @override
  Widget build(BuildContext context) {
    final r = lbResolveSafeArea(context);
    return LBSafeAreaResolved(base: r.base, resolved: r.resolved, child: widget.child);
  }
}

/// 把 [LBSafeAreaPlacementTracking.lbResolveSafeArea] 的結果交給子樹：[resolved] 成為子樹的
/// `MediaQuery`，[base] 留給巢狀的量測點當基準。[LBSafeAreaScope] 就是「mixin + 這個 widget」；
/// 容器的 State 需要在自己的 `build` 裡直接用到解析結果時，改為自己掛 mixin 並包這個 widget。
class LBSafeAreaResolved extends StatelessWidget {
  final MediaQueryData base;
  final MediaQueryData resolved;
  final Widget child;

  const LBSafeAreaResolved({
    super.key,
    required this.base,
    required this.resolved,
    required this.child,
  });

  @override
  Widget build(BuildContext context) =>
      _LBSafeAreaAmbient(ambient: base, child: MediaQuery(data: resolved, child: child));
}

/// chrome 表面的 safe-area 邊距：讀 ambient `MediaQuery`，在選定的邊套 padding，並把已套用的量
/// 從子樹的 `MediaQuery` 扣掉（子樹裡的 `SafeArea`／鍵盤處理不會把同一段再加一次）。
///
/// [includeKeyboard] 為 `true` 時底部取「導覽／手勢列與鍵盤較高者」，給含文字輸入的表面用。
/// 滿版背景／scrim 放在這個 widget **外面**。邊距為零時 padding 是零，像素與沒有這個 widget
/// 時相同。
class LBSafeAreaPadding extends StatelessWidget {
  final bool left;
  final bool top;
  final bool right;
  final bool bottom;
  final bool includeKeyboard;
  final Widget child;

  const LBSafeAreaPadding({
    super.key,
    this.left = true,
    this.top = true,
    this.right = true,
    this.bottom = true,
    this.includeKeyboard = false,
    required this.child,
  });

  /// PURE：這個 widget 會套的邊距。
  static EdgeInsets resolve(
    MediaQueryData mq, {
    bool left = true,
    bool top = true,
    bool right = true,
    bool bottom = true,
    bool includeKeyboard = false,
  }) {
    final safe = lbChromeSafeInsets(mq);
    return EdgeInsets.fromLTRB(
      left ? safe.left : 0,
      top ? safe.top : 0,
      right ? safe.right : 0,
      !bottom
          ? 0
          : includeKeyboard
              ? lbInputBottomInset(safeBottom: safe.bottom, keyboardBottom: mq.viewInsets.bottom)
              : safe.bottom,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final applied = resolve(mq,
        left: left, top: top, right: right, bottom: bottom, includeKeyboard: includeKeyboard);
    return Padding(
      padding: applied,
      child: MediaQuery(
        data: lbConsumeSafeArea(mq, applied: applied, keyboard: includeKeyboard && bottom),
        child: child,
      ),
    );
  }
}
