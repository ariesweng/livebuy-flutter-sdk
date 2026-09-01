import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../reference_ui_theme.dart';

// MARK: - HeartBurst — shared floating-hearts burst (`LBPHeartBurst`)
//
// Spec: `reference-ui-rendering/spec.md` (rb-flutter-live-bottom-heart-burst, 問題 5).
// Design: `design/templates/minimal/sdk-components.jsx` `LBPHeartBurst` +
//          `live-chrome.jsx` `LBLiveBottomBar onLike → spawnHeart`.
// Flutter parity of iOS `HeartBurstView.swift` / Android `HeartBurstView.kt`
// (rb-ios-live-bottom-heart-burst / 1733176).
//
// A `tick`-driven burst: each time `tick` INCREASES, one accent heart spawns at the origin and
// flies up (offset -90), fading + shrinking + rotating over 2.4s, then self-removes so repeated
// ticks never accumulate. Pure presentation — never calls core / template.
//
// Golden-neutral: at rest (no in-flight heart) NOTHING is drawn. `tick` does NOT change during a
// static golden capture, so no heart spawns → baseline carries no burst (matches iOS/Android).

const double _flyDistance = -90; // upward travel
const Duration _flyDuration = Duration(milliseconds: 2400); // lbp-heart-fly 2.4s
const double _dxMax = 22; // --dx jitter ±22
const double _rotMaxDeg = 28; // --rot jitter ±28°

/// The shared floating-hearts burst. Spawns one heart each time [tick] increases.
class HeartBurst extends StatefulWidget {
  final ReferenceUITheme theme;

  /// Monotonic trigger — each increase spawns one burst.
  final int tick;

  /// Heart glyph size (design `Icons.heartFill` 26).
  final double glyphSize;

  const HeartBurst({
    super.key,
    required this.theme,
    required this.tick,
    this.glyphSize = 26,
  });

  @override
  State<HeartBurst> createState() => _HeartBurstState();
}

class _Heart {
  final AnimationController controller;
  final double dx;
  final double rotation; // radians
  _Heart(this.controller, this.dx, this.rotation);
}

class _HeartBurstState extends State<HeartBurst> with TickerProviderStateMixin {
  final List<_Heart> _hearts = [];
  final math.Random _rng = math.Random();

  @override
  void didUpdateWidget(covariant HeartBurst oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only spawn on a CHANGE (mirrors iOS `onChange(of: tick)`), never on the first build.
    if (widget.tick != oldWidget.tick) _spawn();
  }

  void _spawn() {
    final controller = AnimationController(vsync: this, duration: _flyDuration);
    final heart = _Heart(
      controller,
      (_rng.nextDouble() * 2 - 1) * _dxMax,
      (_rng.nextDouble() * 2 - 1) * _rotMaxDeg * math.pi / 180,
    );
    setState(() => _hearts.add(heart));
    controller.forward().whenComplete(() {
      if (mounted) setState(() => _hearts.remove(heart));
      controller.dispose();
    });
  }

  @override
  void dispose() {
    for (final h in _hearts) {
      h.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: widget.glyphSize,
        height: widget.glyphSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            for (final h in _hearts)
              AnimatedBuilder(
                animation: h.controller,
                builder: (context, child) {
                  final p = h.controller.value;
                  return Transform.translate(
                    offset: Offset(h.dx * p, _flyDistance * p),
                    child: Transform.rotate(
                      angle: h.rotation * p,
                      child: Transform.scale(
                        scale: 1 - 0.3 * p,
                        child: Opacity(opacity: 1 - p, child: child),
                      ),
                    ),
                  );
                },
                child: Text(
                  '♥',
                  style: TextStyle(
                    color: widget.theme.accent,
                    fontSize: widget.glyphSize * widget.theme.fontScale,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
