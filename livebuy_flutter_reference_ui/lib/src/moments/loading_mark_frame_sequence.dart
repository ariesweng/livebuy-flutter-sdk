// loading_mark_frame_sequence — pure frame-index logic for the `.loading` brand
// PNG-sequence animation (17 frames, 500×500 RGBA, parity iOS
// `LoadingMarkAnimationView.frameIndex(elapsed:)` / Android
// `loadingMarkFrameIndex(elapsedMs:)`).
//
// Spec: `reference-ui-rendering/spec.md`
//   § "Flutter reference-ui `.loading` 品牌動畫改用 PNG 序列幀播放"
// Design: `rb-flutter-loading-mark-png-sequence` design.md 決策 1/4.
// Change: rb-flutter-loading-mark-png-sequence.
//
// This file deliberately has ZERO Flutter import (`dart:core` only) so the
// timeline logic can be unit-tested independently of any widget lifecycle
// (`docs/unit-test-discipline.md`: "不用 self.* 也不做 IO → 寫成 static / top-level").
//
// Timeline (decision-locked, matches the iOS/Android extraction of the original
// `livebuy-loading.webp`): frame 0 → 68ms, frames 1-15 → 34ms each, frame 16 →
// 476ms hold. Total loop 1054ms, then repeats from frame 0.
abstract final class LoadingMarkFrameSequence {
  /// Total number of frames in the sequence (`frame_00.png` ~ `frame_16.png`).
  static const int frameCount = 17;

  /// Frame 0's display duration.
  static const int frame0DurationMs = 68;

  /// Each of frames 1-15's display duration.
  static const int midFrameDurationMs = 34;

  /// Count of "mid" frames (frames 1-15 inclusive).
  static const int midFrameCount = 15;

  /// Frame 16's hold duration (the longest single-frame hold in the loop).
  static const int lastFrameHoldMs = 476;

  /// Total loop duration — matches the original `livebuy-loading.webp`
  /// extraction exactly (frame0 + 15×mid + last hold).
  static const int totalLoopMs =
      frame0DurationMs + midFrameDurationMs * midFrameCount + lastFrameHoldMs;

  /// Maps elapsed time (since the animation loop started) to the frame index
  /// (`0`..`16`) that MUST be displayed, per the locked timeline. Wraps back to
  /// frame 0 once [elapsed] exceeds [totalLoopMs] (e.g. `elapsed = 1054ms + 17ms`
  /// MUST equal `elapsed = 17ms`). Negative [elapsed] also wraps (defensive; not
  /// expected from the monotonic clock driving the animation view).
  static int frameIndex(Duration elapsed) {
    final elapsedMs = elapsed.inMicroseconds / 1000.0;
    var t = elapsedMs % totalLoopMs;
    if (t < 0) t += totalLoopMs;

    if (t < frame0DurationMs) {
      return 0;
    }
    final afterFrame0 = t - frame0DurationMs;
    final midFramesTotalMs = midFrameDurationMs * midFrameCount;
    if (afterFrame0 < midFramesTotalMs) {
      final offset = (afterFrame0 / midFrameDurationMs).floor();
      return 1 + (offset < midFrameCount - 1 ? offset : midFrameCount - 1);
    }
    return frameCount - 1;
  }

  /// The bundled asset path for [index] (`assets/loading_mark/frame_00.png` ~
  /// `frame_16.png`), zero-padded to two digits — shared naming convention
  /// between the pubspec `assets:` declaration and [LoadingMarkAnimationView].
  static String assetPathForFrame(int index) =>
      'assets/loading_mark/frame_${index.toString().padLeft(2, '0')}.png';
}
