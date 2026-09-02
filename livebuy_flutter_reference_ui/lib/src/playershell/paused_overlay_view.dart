import 'package:flutter/material.dart';

import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';

// PlaybackPausedOverlayView — family-1 centre paused overlay (interactive).
//
// Spec: `reference-ui-rendering/spec.md`
//   § "Flutter player-shell 提供暫停覆蓋層與靜音提示 toast overlay，與 iOS/Android 一致"
// Parity: iOS `PlayerShell/PlaybackPausedOverlayView.swift` / Android
// `playershell/GestureFeedbackViews.kt`'s `PausedCenterControlsView`. Change:
// player-gesture-feedback-overlays-flutter (from-scratch Flutter port — this component did not
// previously exist in flutter-reference-ui; Flutter has no retired hold-to-pause icon to take
// over from, unlike iOS/Android's history).
//
// ⚠️ RETIRED-BUT-KEPT (rb-flutter-gesture-clean-mode-v2, 2026-09-02): this widget is no longer
// composed by `PlayerShellView` — the R29 gesture model removed the "tap toggles play/pause,
// non-playing VOD/replay shows a paused overlay" behavior this component was built for (VOD /
// finished-live-replay play/pause now lives on `PlaybackProgressBarView`'s own expanded-state
// button). The type, its `LbTestKeys` constants, and its standalone tests are all KEPT for
// cross-platform registry parity with iOS/Android (which made the identical "keep the type,
// drop the composition" call for their own copies) — construct and test it directly, it is not
// dead code, just no longer reached from `PlayerShellView`'s own render tree.
//
// The centred, interactive "paused" overlay: a mute-toggle button (44px) stacked above a
// play/resume button (64px), both on translucent dark-glass circles. Driven by the REAL
// `PlayerShellModel.isPlaybackPlaying` (not a gesture transient) — `PlayerShellView` composes it
// ⟺ `showsPlaybackPausedOverlay(...)` — so it stays up, and stays INTERACTIVE, for as long as the
// engine is actually paused, however that pause was triggered (a VOD/replay tap, or an
// SDK-internal lifecycle pause).
//
// PURE presentation: reads only its passed-in values, owns no state, and never reaches back into
// `PlayerShellModel` (one-way data flow). Both buttons forward to host-wired closures the shell
// already owns:
//   - 靜音切換 (44px) → `onToggleMute` (the SAME closure the video-area tap uses on a LIVE stream
//     — this overlay only ever shows for a NON-live stream, but the mute affordance is still
//     meaningful there, per the design's paused overlay).
//   - 播放恢復 (64px) → `onResume` (the shell wires this to `widget.onTogglePlayPause`; since the
//     overlay only shows while genuinely paused, "toggle" here always means "resume").

/// The centred, interactive "paused" overlay: a mute-toggle button (44px) stacked above a
/// play/resume button (64px), both on translucent dark-glass circles.
class PlaybackPausedOverlayView extends StatelessWidget {
  /// The resolved reference-ui theme.
  final ReferenceUITheme theme;

  /// The CURRENT mute state (`PlayerShellModel.muted`) — selects the glyph, matching
  /// `GestureMuteToastView`'s icon convention.
  final bool muted;

  /// Tap the mute-toggle button → host-wired mute forwarder (the SAME closure the video-area
  /// tap-to-mute gesture uses). `null` → the button renders but is inert (demo / golden).
  final VoidCallback? onToggleMute;

  /// Tap the resume button → resume playback. `PlayerShellView` wires this to
  /// `widget.onTogglePlayPause` (meaningful only as "resume" here, since the overlay is shown ⟺
  /// the engine is actually paused). `null` → inert (demo / golden).
  final VoidCallback? onResume;

  const PlaybackPausedOverlayView({
    super.key,
    required this.theme,
    required this.muted,
    this.onToggleMute,
    this.onResume,
  });

  /// Mute-toggle button diameter (design 44px).
  static const double _muteButtonSize = 44;

  /// Resume button diameter (design 64px).
  static const double _resumeButtonSize = 64;

  /// Vertical gap between the two buttons (design 14px).
  static const double _gap = 14;

  /// Translucent dark-glass circle fill (design `rgba(0,0,0,0.45)`).
  static final Color _glass = Colors.black.withValues(alpha: 0.45);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _glassCircleButton(
          key: LbTestKeys.pausedOverlayMuteButton,
          size: _muteButtonSize,
          icon: muted ? Icons.volume_off : Icons.volume_up,
          iconSize: 18,
          onTap: onToggleMute,
        ),
        const SizedBox(height: _gap),
        _glassCircleButton(
          key: LbTestKeys.pausedOverlayResumeButton,
          size: _resumeButtonSize,
          icon: Icons.play_arrow,
          iconSize: 28,
          onTap: onResume,
        ),
      ],
    );
  }

  Widget _glassCircleButton({
    required Key key,
    required double size,
    required IconData icon,
    required double iconSize,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: _glass, shape: BoxShape.circle),
        // Fixed glyph size, NOT scaled by `theme.fontScale` — parity iOS
        // `PlaybackPausedOverlayView.swift` (`.font(.system(size: 18/28, weight: ...))`, no
        // fontScale multiplier) / Android `GestureFeedbackViews.kt` (`18.dp`/`28.dp` glyph
        // `Modifier.size`, no fontScale multiplier). Unlike `GestureMuteToastView`'s icon+label
        // (which DOES scale, matching both reference platforms' own toast glyph), these two
        // button glyphs sit inside a FIXED 44px/64px circle, so both platforms keep them fixed
        // too — verifier-flagged pixel-parity fix (player-gesture-feedback-overlays-flutter).
        child: Icon(icon, size: iconSize, color: Colors.white),
      ),
    );
  }
}
