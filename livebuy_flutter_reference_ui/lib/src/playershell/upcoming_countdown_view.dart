import 'package:flutter/widgets.dart';

import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';

// UpcomingCountdownView — 直播預告 (upcoming / awaitingLive) full-bleed surface.
//
// Spec: `reference-ui-rendering/spec.md` (Flutter upcoming / intro chrome parity).
// Flutter sibling of iOS `UpcomingCountdownView.swift` (rb-ios-upcoming-align-design,
// commit 77505c6) + Android `UpcomingCountdownView.kt` (rb-android-upcoming-intro-chrome).
// Design source: `design/templates/minimal/live-chrome.jsx` `LBLiveUpcomingOverlay` —
// the cover/thumbnail + a dark mask + a centered "scheduled DATE + big scheduled TIME",
// with NO "即將開播" label and NO ticking "距開播 HH:MM:SS" countdown.
//
// The full-bleed background shown while the player is in `awaitingLive`
// (`live_status == 0`, 直播預告). Promoted from a top-most moment to the player-shell
// background (see PlayerShellView's upcoming branch). Binds the template
// DefaultUpcomingState (republished onto PlayerShellModel.upcomingStartAt /
// upcomingCover):
//   - live == true  -> cover placeholder background (NO Image.network — uses the
//                      established deterministic gradient convention) + a
//                      Color.black @ 0.35 dark mask (so the text reads),
//   - live == false -> solid theme.background (golden-deterministic, no cover load).
//   - centered Column: scheduled DATE (small ~14/600) + scheduled TIME (big ~56/800).
//
// GOLDEN-DETERMINISM (iOS / Android lessons baked in): plain Stack / Column only — NO
// scrollable, NO Canvas ring, NO ticking countdown / Timer, NO DateTime.now()
// dependency. Date / time are pure string reformats of the backend publish_at (see
// scheduledDate / scheduledTime below), so the live == false baseline is byte-stable.

// MARK: - Cover placeholder gradient (live == true runtime background)
//
// Reuses the same deterministic cover gradient as the widget CarouselCardView's
// thumbnail (top-left dark -> bottom-right darker), so a real network cover is NEVER
// fetched in this layer; the host supplies the real video surface behind the chrome
// at runtime.

const Color _coverGradientTop = Color(0xFF3A3A44);
const Color _coverGradientBottom = Color(0xFF111118);

/// `rgba(0,0,0,0.35)` dark mask over the cover (live == true).
const Color _darkMask = Color(0x59000000); // black @ 0.35

/// The 直播預告 (upcoming / awaitingLive) full-bleed surface. Renders a centered
/// scheduled DATE (small) + scheduled TIME (big) over either the cover placeholder +
/// dark mask (runtime, `live == true`) or the solid theme background (golden / demo,
/// `live == false`).
///
/// SUB-VIEW INPUT PATTERN (mirrors the family-1 surfaces): `theme` first → bound
/// SNAPSHOT VALUE(s) by value (`scheduledStartAt` / `coverUrl`) → `live` opt-in.
class UpcomingCountdownView extends StatelessWidget {
  /// The resolved reference-ui theme (FIRST argument, always).
  final ReferenceUITheme theme;

  /// The backend `publish_at` (`"yyyy-MM-dd HH:mm:ss"`, UTC+8), parsed for the
  /// centered date + time display.
  final String scheduledStartAt;

  /// Runtime opt-in. `false` (default — demo / golden) → solid `theme.background`,
  /// no cover (deterministic). `true` (host runtime) → cover placeholder + 0.35 mask.
  final bool live;

  /// The video cover URL (`PlayerShellModel.upcomingCover` ← `channel.cover`).
  /// Retained for host-supplied wiring; this layer paints a deterministic
  /// placeholder, never a network image.
  final String coverUrl;

  const UpcomingCountdownView({
    super.key,
    required this.theme,
    required this.scheduledStartAt,
    this.live = false,
    this.coverUrl = '',
  });

  @override
  Widget build(BuildContext context) {
    final date = scheduledDate(scheduledStartAt);
    return Stack(
      key: LbTestKeys.momentCountdownRoot,
      fit: StackFit.expand,
      children: [
        // Background: cover placeholder + dark mask (runtime); else solid background.
        if (live) ...[
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [_coverGradientTop, _coverGradientBottom],
              ),
            ),
          ),
          const ColoredBox(color: _darkMask),
        ] else
          ColoredBox(color: theme.background),

        // Content (centered): scheduled DATE (small) + scheduled TIME (big). White
        // text, mirroring the design's LBLiveUpcomingOverlay.
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (date.isNotEmpty)
                  Text(
                    date,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: const Color(0xFFFFFFFF),
                      fontSize: 14 * theme.fontScale,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (date.isNotEmpty) const SizedBox(height: 12),
                Text(
                  scheduledTime(scheduledStartAt),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: const Color(0xFFFFFFFF),
                    fontSize: 56 * theme.fontScale,
                    fontWeight: FontWeight.w900,
                    // Tabular figures so the big HH:MM digits keep a constant advance
                    // width (parity iOS `.monospacedDigit()` on the 56pt time).
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// MARK: - Pure display helpers (shared with CarouselCardView's upcoming card)

/// Reformat a backend `publish_at` (`"2026-06-20 20:00:00"`) → `"6月20日"` (M月D日,
/// leading zeros stripped) by pure string components (no DateTime round-trip →
/// timezone-independent + deterministic). Empty / unexpected shape → "".
/// Mirrors iOS / Android `scheduledDate`.
String scheduledDate(String publishAt) {
  final parts = publishAt.split(' ');
  if (parts.isEmpty) return '';
  final date = parts.first.split('-');
  if (date.length != 3) return '';
  final month = int.tryParse(date[1]);
  final day = int.tryParse(date[2]);
  if (month == null || day == null) return '';
  return '$month月$day日';
}

/// Reformat a backend `publish_at` (`"2026-06-20 20:00:00"`) → `"20:00"` (HH:MM) by
/// pure string components. Empty / unexpected shape → "".
/// Mirrors iOS / Android `scheduledTime`.
String scheduledTime(String publishAt) {
  final parts = publishAt.split(' ');
  if (parts.length != 2) return '';
  final time = parts[1].split(':');
  if (time.length < 2) return '';
  return '${time[0]}:${time[1]}';
}
