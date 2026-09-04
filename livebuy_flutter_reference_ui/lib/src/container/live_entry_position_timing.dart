// live_entry_position_timing — pure (zero-pixel) 落點 / 時機 / 幾何 helpers for the Flutter
// turnkey「現正直播」浮窗入口容器 (rb-flutter-floating-entry-position-timing).
//
// Parity source: iOS `LivebuyLiveEntry.swift` (`LBFloatingEntryPosition` /
// `LBFloatingEntryTiming` / `entranceAnimation`, commit `54e66ddf`), Android
// `LivebuyLiveEntry.kt` (`wireValue` enum + `LB_LIVE_ENTRY_ENTRANCE_*`, commit `df17280f`),
// RN `liveEntryLogic.ts` (`normalizeFloatingPosition` / `lbLiveEntryRestingInset`, commit
// `692d809a`). 設計稿權威是 `design/templates/minimal/sdk-components.jsx` 的 `LBPFloatingWidget`。
//
// 三個設定 (`position` / `timing` / `delay`) 的來源是 `POST /sdk/config` 回應的
// `data.extensions.floating_setting`。`extensions` 是 **opaque raw bag**(`sdk-config` capability
// 明文規定 SDK 不解讀其語意)，所以那些值一律由 **host** 讀出後注入 `LivebuyLiveEntryConfig`；
// 本層只負責「raw string → enum」的 fallback 與幾何 / 時序推導。
//
// WHY A SEPARATE LIBRARY (design D9): `clampFloatingOffset` 住在
// `collapsible_live_buy_player.dart`，它要吃 [LBFloatingEntryPosition]；而
// `live_buy_live_entry.dart` **已經** import `collapsible_live_buy_player.dart`。把這些型別放進
// `live_buy_live_entry.dart` 會讓兩個 library 互相 import(Dart 允許，但依賴圖有環不可讀)。
// 本檔只 import `dart:math` + `flutter/widgets.dart`，是依賴圖的**葉節點**。
//
// ZERO PIXEL: 本檔不含任何 `Widget` 子類、不含任何 `build`。[LiveEntryEdgeInset] 是一個
// `@immutable` 值物件(不持狀態、不被綁定、不跨層暴露給 `livebuy_flutter_ui`)，不是 view-model。

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Wire 值域 + 嚴格相等正規化
// ─────────────────────────────────────────────────────────────────────────────

/// 浮窗入口靜止的底部角落。
///
/// 成員名對齊 iOS(`rightBottom` / `leftBottom`)，[wireValue] 欄位名對齊 Android。
/// **不能**像 RN 那樣讓「成員值即 wire 值」——Dart 的 `constant_identifier_names` lint 不接受
/// `right_bottom` 這種成員名，而本套件有 `flutter_lints` 在跑。
enum LBFloatingEntryPosition {
  /// 右下(本設定落地前 Flutter 的唯一行為，也是所有 fallback 的落點)。
  rightBottom('right_bottom'),

  /// 左下。
  leftBottom('left_bottom');

  const LBFloatingEntryPosition(this.wireValue);

  /// 後端 `extensions.floating_setting.position` 的逐字 wire 字串。
  final String wireValue;
}

/// 浮窗入口的出現時機。
enum LBFloatingEntryTiming {
  /// 一變成可顯示就畫(本設定落地前 Flutter 的唯一行為，也是所有 fallback 的落點)。
  immediate('immediate'),

  /// 等 `delaySeconds` 秒才畫，並播一段進場動畫。
  delay('delay');

  const LBFloatingEntryTiming(this.wireValue);

  /// 後端 `extensions.floating_setting.timing` 的逐字 wire 字串。
  final String wireValue;
}

/// THE ONLY place a raw `floating_setting.position` value becomes a corner.
///
/// 逐字鏡射設計稿的 `normalizeFloatingPosition(raw)`
/// (`raw === 'left_bottom' ? 'left_bottom' : 'right_bottom'`,
/// `design/templates/minimal/sdk-components.jsx`)：比對是**嚴格相等**，**不 trim**、
/// **不 case-fold**，所以 `' left_bottom '` / `'LEFT_BOTTOM'` 與任何白名單外字串一樣落回
/// [LBFloatingEntryPosition.rightBottom]。刻意與設計稿一樣嚴格，是為了讓四端在後端送出畸形值時
/// 落點相同——那正是分歧最難被發現的時候(後端對 `position` 是 RAW 透傳，不做任何列舉正規化)。
///
/// ⚠️ fallback 分支是 `rightBottom`——Flutter 在本設定落地前的行為——而**不是**後端自己的
/// 填值預設(`left_bottom`)。兩者回答**不同**問題：後端的是「商家沒設定時 wire 上要送什麼」，
/// 這一條是「host 什麼都沒注入 / 注入了垃圾時畫面要長怎樣」。只有 `rightBottom` 能讓既有 host
/// 逐字不變。不要「修正」成後端預設。
///
/// 正規化結果 MUST NOT 被回寫進 config 或任何 view-model。
LBFloatingEntryPosition normalizeFloatingPosition(String? raw) =>
    raw == LBFloatingEntryPosition.leftBottom.wireValue
        ? LBFloatingEntryPosition.leftBottom
        : LBFloatingEntryPosition.rightBottom;

/// THE ONLY place a raw `floating_setting.timing` value becomes a timing.
///
/// 與 [normalizeFloatingPosition] 同一條嚴格相等契約(不 trim、不 case-fold)；fallback 分支是
/// [LBFloatingEntryTiming.immediate]——Flutter 在本設定落地前的行為。
LBFloatingEntryTiming normalizeFloatingTiming(String? raw) =>
    raw == LBFloatingEntryTiming.delay.wireValue
        ? LBFloatingEntryTiming.delay
        : LBFloatingEntryTiming.immediate;

// ─────────────────────────────────────────────────────────────────────────────
// 幾何：靜止角落 + 拖曳位移(正負號的唯一實作點)
// ─────────────────────────────────────────────────────────────────────────────

/// 餵給 `Positioned` 的一組邊距。**所屬**那一邊有值、對邊是 `null`
/// (`Positioned(left: null, right: 12)` 與 `Positioned(right: 12)` 等價)。
@immutable
class LiveEntryEdgeInset {
  /// 距 `Stack` 左緣的距離；右下落點時為 `null`。
  final double? left;

  /// 距 `Stack` 右緣的距離；左下落點時為 `null`。
  final double? right;

  /// 距 `Stack` 底緣的距離。兩個落點都錨底，故恆有值。
  final double bottom;

  const LiveEntryEdgeInset({this.left, this.right, required this.bottom});

  @override
  bool operator ==(Object other) =>
      other is LiveEntryEdgeInset &&
      other.left == left &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, right, bottom);

  @override
  String toString() => 'LiveEntryEdgeInset(left: $left, right: $right, bottom: $bottom)';
}

/// THE ONLY place 落點 + 拖曳位移變成 `Positioned` 的邊距。靜止 = 同一函式帶
/// `offset: Offset.zero`，所以「不可拖曳」與「可拖曳」兩個 render 分支共用同一份幾何，不會漂移。
///
/// ⚠️ **換邊時位移的正負號會翻轉**——這是 Flutter 專有的坑(design D2)。Flutter 的拖曳位移
/// **不是**疊一層 transform(iOS `.offset` / Android `offset` modifier / RN `translateX`)，而是
/// **直接算進 `Positioned` 的邊距數值**，而 `left` 與 `right` 的增長方向相反。以 `off` 為
/// 「自靜止角落起算的螢幕座標位移(往右為正)」、`W` 為 `Stack` 寬、`cardW` 為卡片寬：
///
/// ```text
/// 右下：Positioned(right: R) ⇒ 卡片左緣 x = W − R − cardW
///       R = inset.dx − off.dx ⇒ x = W − inset.dx + off.dx − cardW   往右拖 → 卡片往右 ✅
///
/// 左下：Positioned(left: L)  ⇒ 卡片左緣 x = L
///       若沿用減號 L = inset.dx − off.dx ⇒ 往右拖 → 卡片往左  ❌ 朝手指反方向
///       正確     L = inset.dx + off.dx ⇒ 往右拖 → 卡片往右   ✅
/// ```
///
/// 垂直方向兩個落點**相同**(皆錨底)：`bottom: B` ⇒ 卡片上緣 `y = H − B − cardH`，
/// `B = inset.dy − off.dy` ⇒ 往下拖(`off.dy > 0`)→ 卡片往下 ✅，故 `bottom` 的式子兩側共用。
///
/// [inset] 的 `dx` 是「距**所屬**水平邊的距離」(右下 → right、左下 → left)，`dy` 恆是 bottom。
LiveEntryEdgeInset lbLiveEntryEdgeInset({
  required LBFloatingEntryPosition position,
  required Offset inset,
  Offset offset = Offset.zero,
}) {
  final bottom = inset.dy - offset.dy; // 兩個落點共用(皆錨底)
  return position == LBFloatingEntryPosition.leftBottom
      ? LiveEntryEdgeInset(left: inset.dx + offset.dx, bottom: bottom)
      : LiveEntryEdgeInset(right: inset.dx - offset.dx, bottom: bottom);
}

/// 進場動畫的縮放錨點：卡片從所屬角落長出來(對齊設計稿
/// `transformOrigin: side === 'left' ? 'left bottom' : 'right bottom'`)。
Alignment lbLiveEntryEntranceAlignment(LBFloatingEntryPosition position) =>
    position == LBFloatingEntryPosition.leftBottom
        ? Alignment.bottomLeft
        : Alignment.bottomRight;

// ─────────────────────────────────────────────────────────────────────────────
// 時機
// ─────────────────────────────────────────────────────────────────────────────

/// `timing == delay` 時的等待秒數預設。承載後端 Int-秒欄位 `extensions.floating_setting.delay`，
/// 該欄位自己的預設也是 `3`。
const int kLiveEntryDefaultDelaySeconds = 3;

/// 入口出現前要等多久。[LBFloatingEntryTiming.immediate] 恆 `Duration.zero`——該模式下
/// `delaySeconds` 完全無作用。`delay` 模式把秒轉成 [Duration]，並把 `<= 0` 的值(host 可能從
/// JSON bag 撈到負數)收斂成 `Duration.zero`，而不是產生一個永遠不觸發或立刻觸發不了的排程。
Duration lbLiveEntryAppearDelay(LBFloatingEntryTiming timing, int delaySeconds) {
  if (timing != LBFloatingEntryTiming.delay) return Duration.zero;
  if (delaySeconds <= 0) return Duration.zero;
  return Duration(seconds: delaySeconds);
}

/// 容器出現時機閘的**每個 timing 的基準初值**：`immediate` → `true`(入口一可顯示就畫，與本設定
/// 落地前逐字相同)、`delay` → `false`(由排程翻起)。
///
/// ⚠️ 這個函式是「一個 timing enum 該起始成什麼布林」的**唯一**來源，呼叫點 MUST NOT 自己把這個
/// 基準寫死。它**真的載有行為**——消費鏈是對 `live_buy_live_entry.dart` 下 `grep -n "_appeared"`
/// **機器列舉**後逐點追的(design D5)，不是照抄別端的宣稱：
///
/// ```text
/// 讀取點共 2 處(grep 列舉，非「唯一一處」)：
///   build                  if (_state.dismissed || live == null || !_appeared) return SizedBox.shrink();
///                            → 渲染條件；閘關著就不畫
///   _reconcileAppearance   if (_appeared || _appearTimer != null) return;
///                            → 去重判斷：已顯示 / 已在倒數就不重排程
///
/// 寫入點共 5 處(grep 列舉，非「唯一一處」；rb-flutter-live-entry-close-grace-period 前是 4 處)：
///   initState                      _appeared = lbLiveEntryInitialAppeared(_timing)
///                                    && _closeGraceRemainingMs() <= 0
///                                    → 兩個模式都執行；本函式的回傳值再 AND 一個獨立的 close-grace
///                                      條件(rb-flutter-live-entry-close-grace-period)
///   _applyFloatingSettingUpdate    同上一式
///                                    → 只在 host 熱抽換且 timing 真的改變時執行
///   _reconcileAppearance           _appeared = false（`!_eligible` 分支）
///                                    → rb-flutter-live-entry-close-grace-period 前被該方法第一行
///                                      `if (_timing != delay) return;` 擋住、immediate 路徑不可達；
///                                      該 early-return 已移除，兩個 timing 現在都會執行到
///   _reconcileAppearance           _appeared = true（`immediate` 分支、close-grace 已為 0 時的同步早返回）
///                                    → **新增寫入點**(rb-flutter-live-entry-close-grace-period)：
///                                      immediate 路徑本來完全不會進入 `_reconcileAppearance`，現在
///                                      會，且這個分支直接寫死 `true`——但這是「已知沒有 grace 要等」
///                                      的收斂結果，不是繞過本函式的基準值，兩者回答不同問題(見下)
///   _onAppearTimerFired            setState(() => _appeared = true)
///                                    → 由 _reconcileAppearance 排的 `Timer` 觸發；
///                                      rb-flutter-live-entry-close-grace-period 前只有 `delay` 會走到
///                                      這裡，之後 `immediate` 在有 close-grace 要等時也會走到
/// ```
///
/// 也就是說：**本函式**仍是「某個 timing 的基準初值」唯一權威，那條「呼叫點 MUST NOT 自己寫死布林」
/// 的規範，指的是這個基準值本身——`initState` / `_applyFloatingSettingUpdate` 這兩個真正做「初始化」
/// 的寫入點，繼續、只、透過本函式取得基準，再 AND 上一個完全獨立的 close-grace 條件（後者是一個不同的
/// 純函式 `liveEntryCloseGraceRemainingMs` 決定的，不是把本函式的基準值繞過）。`_reconcileAppearance`
/// 的兩個寫入點做的是「執行期的資格 / 等待時間收斂」，不是「timing 基準」，本來就不透過本函式（連
/// rb-flutter-live-entry-close-grace-period 之前，`delay` 的排程觸發寫入點 `_onAppearTimerFired` 也一
/// 樣不透過本函式）——把這裡改成恆 `false`，唯一的直接後果是每一個預設 host 的入口在「冷開、沒有
/// close-grace 要等」時永遠不會同步出現(仍可能在 grace 收斂後由 `_reconcileAppearance` 的新分支救回，
/// 但那已不是本函式的責任範圍)。這條性質在 Flutter 有**執行期**證據(`container timing > immediate …`
/// widget 測試)，不是只有原始碼釘樁。
bool lbLiveEntryInitialAppeared(LBFloatingEntryTiming timing) =>
    timing != LBFloatingEntryTiming.delay;

// ─────────────────────────────────────────────────────────────────────────────
// 進場動畫常數 —— 逐值對齊設計稿 `lbp-float-in`
// (`design/templates/minimal/sdk-components.jsx` · `LBPFloatingWidget`)
//
//   @keyframes lbp-float-in {
//     0%   { opacity: 0; transform: translateY(16px) scale(0.78); }
//     60%  { opacity: 1; }
//     100% { opacity: 1; transform: translateY(0) scale(1); }
//   }
//   animation: lbp-float-in 0.42s cubic-bezier(0.22,1,0.36,1) both;
//
// 具名 export，讓四端抄同一組數字而不是各自重新推導。
//
// ⚠️ 平台差異(誠實記錄，design D8)：iOS 用 SwiftUI `AnyTransition.scale + .opacity + .offset`、
// Android 用 Compose `scaleIn + fadeIn + slideInVertically`，兩端的 fade 都跑**滿**整個 420ms，
// **沒有**實作 keyframe 的 60% opacity 停點。Flutter(與 RN 相同)有完整控制權，故照設計稿實作
// [kLiveEntryEntranceOpacityStop]。這是「平台 transition 原語的近似」與「逐格照設計稿」的差別。
// ─────────────────────────────────────────────────────────────────────────────

/// 進場動畫時長(設計稿 `0.42s`)。
const Duration kLiveEntryEntranceDuration = Duration(milliseconds: 420);

/// 進場動畫曲線(設計稿 `cubic-bezier(0.22, 1, 0.36, 1)`)。
const Cubic kLiveEntryEntranceCurve = Cubic(0.22, 1, 0.36, 1);

/// 進度 0 時的縮放(設計稿 `scale(0.78)`)。
const double kLiveEntryEntranceInitialScale = 0.78;

/// 進度 0 時的垂直位移，logical px(設計稿 `translateY(16px)`)。
const double kLiveEntryEntranceTranslateY = 16;

/// opacity 到達 `1` 的進度(設計稿 keyframe `60%`)。
const double kLiveEntryEntranceOpacityStop = 0.6;

/// 由 eased 進度 `t`(0→1)算出 opacity。設計稿的 opacity 在 60% 就到 1，之後維持。
double lbLiveEntryEntranceOpacity(double t) =>
    (t / kLiveEntryEntranceOpacityStop).clamp(0.0, 1.0);

/// 由 eased 進度 `t`(0→1)算出縮放(`0.78 → 1`)。
double lbLiveEntryEntranceScale(double t) =>
    kLiveEntryEntranceInitialScale +
    (1.0 - kLiveEntryEntranceInitialScale) * t.clamp(0.0, 1.0);

/// 由 eased 進度 `t`(0→1)算出垂直位移(`16 → 0`)。
double lbLiveEntryEntranceTranslateY(double t) =>
    kLiveEntryEntranceTranslateY * (1.0 - t.clamp(0.0, 1.0));

// ─────────────────────────────────────────────────────────────────────────────
// clamp 的落點相依邊界(供 `clampFloatingOffset` 使用，見 collapsible_live_buy_player.dart)
// ─────────────────────────────────────────────────────────────────────────────

/// 水平位移在該落點下的合法區間夾取。
///
/// `span = 容器邊長 − 卡片邊長 − inset`(同一個量，左右對稱)：
///
/// ```text
/// rightBottom : dx ∈ [math.min(0.0, -span), 0]   靜止在右，只能往左
/// leftBottom  : dx ∈ [0, math.max(0.0,  span)]   靜止在左，只能往右
/// ```
///
/// **右下分支的語意與本設定落地前逐位元相同**(既有呼叫端 `CollapsibleLivebuyPlayer` 與既有測試
/// 行為不變)。⚠️ 不是「逐字相同」——原式 `math.min(0.0, -(container − card − inset))` 已改寫為
/// `math.min(0.0, -span)` 並從 `collapsible_live_buy_player.dart` 移到本檔；位元結果不變，字面已變。
/// 左下是新寫的鏡像式。
///
/// ⚠️ **不宣稱「絕不產生 `-0.0`」**。Dart 實測：`-0.0 == 0.0` 為 true、`package:test` 的
/// `expect(x, 0.0)` 與 `Offset.==` 皆以 `==` 比較(皆通過)，所以 `-0.0` 在 Flutter **無行為影響、
/// 也不會造成測試假紅**(與 RN 的 jest `Object.is` 語意不同)；而右下分支的 `math.min(0.0, -span)`
/// 在 `span == 0.0`(卡片剛好貼齊)時**本來就**回 `-0.0`——那是本設定落地前既有的行為，不是這裡
/// 引入的。正負零的實際形狀由**記錄型**測試(`isNegative`)寫下來，而不是用絕對條文假裝乾淨。
double lbLiveEntryClampDx({
  required LBFloatingEntryPosition position,
  required double desiredDx,
  required double span,
}) {
  if (position == LBFloatingEntryPosition.leftBottom) {
    final maxX = math.max(0.0, span);
    return math.min(maxX, math.max(0.0, desiredDx));
  }
  final minX = math.min(0.0, -span);
  return math.max(minX, math.min(0.0, desiredDx));
}
