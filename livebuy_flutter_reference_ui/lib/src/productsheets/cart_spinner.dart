import 'package:flutter/material.dart';

// CartSpinner — 加購 CTA「請求中」spinner（靜態 3/4 環，design `LBPSpinner`）.
//
// Spec: `reference-ui-rendering/spec.md`「加購 CTA 請求中 loading」(rb-flutter-cart-add-loading-state).
// Flutter parity of iOS `SpinnerRingView` / Android `CartSpinner` / RN `CartSpinnerView` /
// 設計 `sdk-components.jsx` `LBPSpinner`（3/4 環 `lbp-spin` 邊框 spinner）。以 `CustomPaint` 畫
// faint 全環 + bright 3/4 arc（白），**無動畫** —— 比照既有 `_CountdownRingPainter`
// 「CustomPaint no animation」慣例 + iOS / Android 凍結幀：golden 確定、`pumpAndSettle` 不卡
// （無 infinite animation）。runtime 仍是 loading affordance（spinner 旋轉非 golden 必要）。
//
// 純呈現：只有 `size` / `strokeWidth` / `color`（default 白，accent 底上）。

const double _twoPi = 6.283185307179586;
const double _topStart = -1.5707963267948966; // -90° → 12 o'clock
const double _threeQuarter = _twoPi * 0.75; // 3/4 arc

/// 加購 CTA 的「請求中」spinner：faint 全環 + bright 3/4 arc（靜態，golden 確定）。
class CartSpinner extends StatelessWidget {
  final double size;
  final double strokeWidth;
  final Color color;

  const CartSpinner({
    super.key,
    this.size = 18,
    this.strokeWidth = 2,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CartSpinnerPainter(strokeWidth: strokeWidth, color: color),
      ),
    );
  }
}

class _CartSpinnerPainter extends CustomPainter {
  final double strokeWidth;
  final Color color;

  _CartSpinnerPainter({required this.strokeWidth, required this.color});

  /// Faint 全環軌道色（白 28% = `0x47FFFFFF`，對齊 `end_screen` `_ringTrack`）。
  static const Color _track = Color(0x47FFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    final inset = strokeWidth / 2;
    final rect = Rect.fromLTWH(
      inset,
      inset,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );

    // Faint 全環（spinner 軌道）。
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = _track;
    canvas.drawArc(rect, 0, _twoPi, false, track);

    // Bright 3/4 arc（spinner 頭，從 12 點順時針，圓角端）。
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(rect, _topStart, _threeQuarter, false, arc);
  }

  @override
  bool shouldRepaint(covariant _CartSpinnerPainter old) =>
      old.strokeWidth != strokeWidth || old.color != color;
}
