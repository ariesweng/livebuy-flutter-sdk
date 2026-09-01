import 'package:flutter/material.dart';

import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';

// CartToastView — family-3 add-to-cart success toast (~1.8s confirmation, Flutter).
//
// Spec: `reference-ui-rendering/spec.md` § "渲染 Flutter 加入購物車成功提示 toast".
// Design: `design/templates/minimal/sdk-components.jsx` `LBPCartToast`.
// Flutter parity of iOS `CartToastView.swift` (rb-ios-cart-add-success-toast) + Android
// `CartToastView.kt` + RN `CartToastView.tsx`.
//
// A small dark-glass pill flashed for ~1.8s after an add-to-cart SUCCEEDS (the bound template's
// `cartCTA.count` ticks up). It is PURE 呈現: it reads only `theme` (accent ring) + a label, owns
// NO timer, NO business state, and NO trigger logic — `ProductSheetsOverlayView` drives its
// presentation (transient state, `Timer` auto-dismiss) and wraps it in an `IgnorePointer` so it
// never eats taps (iOS `allowsHitTesting(false)` parity). The accent-ringed checkmark springs in
// on appear (`lbp-toast-check`, `TweenAnimationBuilder` scale 0.4→1.0 `elasticOut`); the golden
// captures the settled resting state (scale 1.0) after `pumpAndSettle`.

/// `rgba(20,20,24,0.86)` — the dark glass pill fill (`LBPCartToast`), parity iOS/Android/RN. */
const Color _glassFill = Color(0xDB141418);

/// The confirmation label (design default 「已加入購物車」).
const String _defaultLabel = '已加入購物車';

/// Accent-ringed checkmark diameter (design `LBPCartToast` 24px circle).
const double _checkSize = 24;

/// The add-to-cart success toast: a dark-glass pill with an accent-ringed checkmark + a
/// confirmation label (「已加入購物車」). Pure presentation — the container drives presentation +
/// auto-dismiss; this widget only paints + springs the checkmark in on appear.
class CartToastView extends StatelessWidget {
  const CartToastView({
    super.key,
    required this.theme,
    this.label = _defaultLabel,
  });

  /// The resolved reference-ui theme (FIRST, always). The accent drives the checkmark ring.
  final ReferenceUITheme theme;

  /// The confirmation label (design default 「已加入購物車」).
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: LbTestKeys.cartToast,
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
      decoration: const BoxDecoration(
        color: _glassFill,
        borderRadius: BorderRadius.all(Radius.circular(999)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Accent-ringed checkmark, springs in (lbp-toast-check). The tween animates once on
          // appear; `pumpAndSettle` settles it to the resting 1.0 for the deterministic golden.
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.4, end: 1.0),
            duration: const Duration(milliseconds: 400),
            curve: Curves.elasticOut,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Container(
              width: _checkSize,
              height: _checkSize,
              decoration: BoxDecoration(
                color: theme.accent,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(Icons.check, color: Colors.white, size: 15),
            ),
          ),
          const SizedBox(width: 9),
          Text(
            label,
            style: TextStyle(
              color: Colors.white,
              fontSize: 13.5 * theme.fontScale,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
