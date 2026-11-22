import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../safearea/lb_safe_area.dart' show lbChromeSafeInsets;

// product_list_keyboard_avoidance.dart — 商品清單 drawer 搜尋時的鍵盤避讓
// （rb-flutter-product-list-keyboard-avoid，parity iOS SwiftUI 預設鍵盤避讓 / Android `adjustResize`
// / RN `productListKeyboardAvoidance.ts`）。
//
// 商品清單 drawer 由 `ProductSheetsOverlayView` 自己以 `Align(bottomCenter)` 貼底呈現，搜尋框聚焦
// 後鍵盤升起時，drawer 原本會留在鍵盤底下。Flutter 與 RN 不同的地方：
//
//   - Flutter 在 iOS 與 Android 都不會因鍵盤縮小 Flutter 畫面——鍵盤高度一律以
//     `MediaQuery.viewInsets.bottom` 交給 app 自己處理（Android embedding 的 `FlutterView` 把 IME
//     inset 直接寫進 `viewInsetBottom`），所以這裡**不分平台**，兩端都依 `viewInsets` 上移。
//   - 不會雙重上移：host 若已用 `Scaffold(resizeToAvoidBottomInset: true)` 讓 body 避開鍵盤，
//     `Scaffold` 會把子樹 `viewInsets.bottom` 歸零；host 若只用 `Padding` 把容器推離底緣，
//     `LBSafeAreaScope` 會把已推開的距離從 `viewInsets` 扣掉。drawer 讀到的就是「還沒被處理的鍵盤
//     重疊量」，零就不上移。
//
// 純函式，直接單測。

/// drawer 要往上移多少（logical px）：鍵盤重疊量扣掉 drawer 本來就在底部保留的安全區 spacer
/// （`LBSheetScaffold` 的 bottom spacer）。扣掉後 spacer 落到鍵盤底下，購物車 footer 剛好停在鍵盤
/// 上緣。沒有鍵盤（`keyboardBottom <= 0`）回傳 `0`。
double productListKeyboardLift({
  required double keyboardBottom,
  required double safeAreaBottom,
}) {
  if (!(keyboardBottom > 0)) return 0;
  return math.max(0, keyboardBottom - math.max(0, safeAreaBottom));
}

/// 套在 drawer 外層的邊距：上移量 > 0 時，`bottom` = 上移量、`top` = 上方安全區——後者讓使用者
/// 拖高過（最高 80%）的 drawer 在上移後頂端（搜尋列）不會跑到狀態列底下或螢幕外：`LBSheetScaffold`
/// 的 `ConstrainedBox` 會被父層剩下的高度夾住，只影響畫出來的高度，拖曳手勢自己記住的高度不變，
/// 收鍵盤後回到原高度。上移量為 `0` 時回傳 [EdgeInsets.zero]（排版與本 change 之前相同）。
EdgeInsets productListKeyboardInsets({
  required double keyboardBottom,
  required double safeAreaTop,
  required double safeAreaBottom,
}) {
  final double lift = productListKeyboardLift(
    keyboardBottom: keyboardBottom,
    safeAreaBottom: safeAreaBottom,
  );
  if (!(lift > 0)) return EdgeInsets.zero;
  return EdgeInsets.only(top: math.max(0, safeAreaTop), bottom: lift);
}

/// 包住商品清單 drawer 的鍵盤避讓層。
///
/// 子樹結構**固定不變**（永遠是 `Padding` → `MediaQuery` → [child]），不論鍵盤有沒有升起——條件式
/// 多包一層會讓 drawer 的 `State`（搜尋展開狀態、query、輸入框焦點）在鍵盤升起那一刻被重建，焦點
/// 掉了鍵盤又收回去。已經避開的鍵盤量會從子樹的 `viewInsets` 扣掉，子孫不再避讓第二次。
class ProductListKeyboardAvoider extends StatelessWidget {
  final Widget child;

  const ProductListKeyboardAvoider({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);
    final EdgeInsets safe = lbChromeSafeInsets(mq);
    final EdgeInsets insets = productListKeyboardInsets(
      keyboardBottom: mq.viewInsets.bottom,
      safeAreaTop: safe.top,
      safeAreaBottom: safe.bottom,
    );
    final bool lifted = insets.bottom > 0;
    // 只把 `viewInsets.bottom` 歸零，`padding` / `viewPadding` 原樣保留。不用
    // `MediaQueryData.removeViewInsets(removeBottom: true)`：它會連帶把 `viewPadding.bottom`
    // 扣成 `max(0, viewPadding.bottom − viewInsets.bottom)`（鍵盤比安全區高時＝0），
    // `LBSheetScaffold` 的底部 spacer（讀 `lbChromeSafeInsets(mq).bottom`）就跟著消失；但上移量
    // 是「扣掉 spacer」算出來的，spacer 不見會讓 footer 底緣被鍵盤蓋住 safeAreaBottom 那一段。
    return Padding(
      padding: insets,
      child: MediaQuery(
        data: lifted ? mq.copyWith(viewInsets: mq.viewInsets.copyWith(bottom: 0)) : mq,
        child: child,
      ),
    );
  }
}
