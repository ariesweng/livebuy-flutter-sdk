import 'package:flutter/material.dart';

import '../reference_ui_theme.dart';

// GestureMuteToastView — family-1 centre mute toast (0.7s tap-to-mute feedback).
//
// Spec: `reference-ui-rendering/spec.md`
//   § "Flutter player-shell 提供暫停覆蓋層與靜音提示 toast overlay，與 iOS/Android 一致"
// Parity: iOS `PlayerShell/GestureMuteToastView.swift` / Android
// `playershell/GestureFeedbackViews.kt`'s `GestureMuteToastView`. Change:
// player-gesture-feedback-overlays-flutter (from-scratch Flutter port — this component did not
// previously exist in flutter-reference-ui).
//
// The small centred toast `PlayerShellView` used to show for ~0.7s after a LIVE video-area tap's
// deferred mute-commit actually fired (see the retired `_handleLiveTap()` / `_showMuteToast()`).
// PURE presentation: it reads only `theme` / `muted` (the resulting mute state, read from
// `PlayerShellModel.muted`) and paints a speaker glyph + label on a dark-glass pill. It owns NO
// timer — a caller drives its presentation (transient state, auto-dismiss). Renders correctly
// standalone (demo / golden).
//
// ⚠️ RETIRED-BUT-KEPT (rb-flutter-gesture-clean-mode-v2, 2026-09-02): `PlayerShellView` no
// longer composes this widget — the video-area tap-to-mute gesture (and its deferred-commit
// path) that used to trigger it is retired under the R29 gesture model (a short tap now toggles
// clean mode instead; the header's new clean-mode-only mute button, see
// `player_header_bar_view.dart`, toggles mute directly with no toast). The type and its
// standalone tests are KEPT for cross-platform registry parity with iOS/Android, which made the
// identical call for their own copies — construct and test it directly, it is not dead code,
// just no longer reached from `PlayerShellView`'s own render tree.

/// The centred mute toast: a dark-glass pill with a speaker glyph + a state label.
/// `muted == true` → 靜音 (`Icons.volume_off`); `false` → 聲音開啟 (`Icons.volume_up`).
class GestureMuteToastView extends StatelessWidget {
  /// The resolved reference-ui theme.
  final ReferenceUITheme theme;

  /// The resulting mute state to reflect (read from `PlayerShellModel.muted`).
  final bool muted;

  const GestureMuteToastView({super.key, required this.theme, required this.muted});

  /// Dark-glass pill surface (design `rgba(20,20,24,0.78)`, parity iOS/Android
  /// `GestureMuteToastView.glass`).
  static final Color _glass =
      (colorFromHex('#141418') ?? const Color(0xFF141418)).withValues(alpha: 0.78);

  static const String _mutedLabel = '靜音';
  static const String _unmutedLabel = '聲音開啟';

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: _glass, borderRadius: BorderRadius.circular(999)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              muted ? Icons.volume_off : Icons.volume_up,
              size: 18 * theme.fontScale,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Text(
              muted ? _mutedLabel : _unmutedLabel,
              style: TextStyle(
                fontSize: 14 * theme.fontScale,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
