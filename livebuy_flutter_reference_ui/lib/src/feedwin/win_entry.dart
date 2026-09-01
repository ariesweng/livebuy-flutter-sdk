import 'package:flutter/widgets.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart' show LBActiveEvent, LBWinner;

import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';
import 'win_glyph.dart';

// WinEntryView — family-2 feed-win surface 2 (unclaimed-win entry + live-event
// entry, two `variant`s of the SAME widget).
//
// Spec: `reference-ui-rendering/spec.md` (family-2 feed-win, surface 2).
// Flutter sibling of iOS `WinEntryView.swift` (rb-ios-win-entry-restyle) and
// Android `WinEntry.kt` (rb-android-win-entry-restyle).
//   Design source: `design/templates/minimal/moments.jsx` · `LBWinEntry`
//     (2026-08-28 visual restyle, R24 / rb-flutter-win-entry-restyle — a floating,
//     STATIC 48×48 SQUARE button pinned right-side by the container: white `#fff`
//     background, `borderRadius 10`, a fixed-color two-path trophy/gift glyph (NOT
//     `theme.accent` — the outer fill is hardcoded `#F03246`), and a bottom
//     semi-transparent label bar reading「領獎」. No pulsing ring, no gradient fill,
//     no numeric count badge — the PRIOR circular/gradient/pulse-ring/count-badge
//     design is retired by this restyle).
//
// `activity` variant (rb-flutter-live-activity-sheet, R26, design.md D1): `LBWinEntry`
// in the design source is ONE function serving TWO uses (a `variant` prop) — this
// widget mirrors that shape rather than forking a second `ActivityEntryView` class,
// so the 48×48 shell / corner radius / glyph Path stay in exactly one place. The
// `activity` variant binds `live-activity-entry-flutter-template`'s
// `DefaultActiveEvent` (`hasActiveEvent` / `current`) instead of `DefaultWinClaim`;
// see [WinEntryVariant] below for the full behavioral diff table.
//
// SUB-VIEW INPUT PATTERN (mirrors family-1 `OperationRailView` and the iOS /
// Android surfaces EXACTLY — see `FeedWinOverlayView`'s documented contract):
//   1. `theme:` (ReferenceUITheme, required)  — FIRST, always.
//   2. its bound SNAPSHOT VALUES it renders   — `unclaimedCount` (drives whether
//      the `win` variant draws at all — R24: the count no longer has any other
//      visual effect, the numeric badge is gone) and `unclaimedWinners` (the
//      by-value mirror of `DefaultWinClaim.unclaimedWinners`; the container opens
//      the claim sheet on the EARLIEST one, so this read-only surface keeps the
//      value so the wired-intent contract is explicit but NEVER records / removes /
//      reorders winners). `activity` variant analogues: `hasActiveEvent` (drives
//      whether it draws) + `currentEvent` (the by-value mirror of
//      `DefaultActiveEvent.current`, forwarded verbatim to `onOpenActivity`). All
//      passed BY VALUE from `FeedWinModel`.
//   3. optional action callbacks, trailing, each defaulting to a no-op (`onOpen`
//      for `win`, `onOpenActivity` for `activity`). The container / host funnels
//      `onOpen` to open the claim sheet on the earliest unclaimed winner and
//      `onOpenActivity` to open the activity sheet on `currentEvent`; this surface
//      does NOT own either open intent and renders correctly with them omitted (so
//      demo / golden / preview construct action-free).
//
// One-way data flow (D-1): this view reads ONLY its passed-in values — it never
// reaches back into `FeedWinModel` or `DefaultPlayerTemplate`, and it neither
// records a win nor removes one (those live in `DefaultWinClaim`), nor does it
// decide whether an activity has ended or been joined (that lives in
// `DefaultActiveEvent`). It only surfaces `onOpen` / `onOpenActivity` open intents;
// the container funnels those to the claim sheet (`unclaimedWinners.first`) /
// activity sheet (`currentEvent`) respectively.
//
// Visibility rule (D-3, unchanged by rb-flutter-win-entry-restyle): the `win`
// variant is drawn ONLY when `unclaimedCount > 0`; the `activity` variant is drawn
// ONLY when `hasActiveEvent`. At the "nothing to show" state either renders nothing
// (a zero-size `SizedBox.shrink()`) so the container's trailing slot is visually
// empty. (The container ALSO gates on the same conditions; this surface self-gates
// too, mirroring iOS / Android, so it is safe to compose unconditionally.)
//
// RENDERING CONSTRAINTS (inherited from family-1 / iOS / Android — CRITICAL):
// NO scrollable container, NO network image, NO animation / randomness. R24
// removed the ONLY runtime-varying state this surface ever had (the pulse ring's
// static-but-animatable ring) — the restyled button has no animation state at
// all, so the golden baseline stays trivially deterministic. The trophy/gift
// glyph is drawn with `CustomPaint` (the design's two filled `Path`s) so it does
// not depend on any icon font for a stable golden.

// MARK: - Design tokens (lifted from moments.jsx · LBWinEntry, R24)

/// Button width/height (`width: 48, height: 48`).
const double _entrySize = 48;

/// Button corner radius (`borderRadius: 10`).
const double _entryCornerRadius = 10;

/// Icon render size. The design renders the glyph at `width="29" height="29"`
/// inside the 48×48 button (icon-authoring.md Rule 2: checked against the real
/// call site, not canvas/gallery scale — design.md Open Questions resolves this
/// to the design's literal 29×29 ratio, there being no legacy slot size to
/// preserve for this purpose-built glyph).
const double _glyphSize = 29;

/// Bottom label bar height (`lineHeight: '14px'`, the label span's implied height).
const double _labelHeight = 14;

/// Bottom label bar background (`rgba(55,60,68,0.8)`).
const Color _labelBackground = Color(0xCC373C44);

/// Bottom label bar text size (`fontSize: 9`).
const double _labelFontSize = 9;

/// Bottom label bar text for `variant: win`. Reference-ui hardcoded copy, not i18n.
const String _labelText = '領獎';

// MARK: - Design tokens (`activity` variant, rb-flutter-live-activity-sheet, R26)
//
// The 48×48 shell size, `borderRadius: 10`, and glyph Path data (now in
// `win_glyph.dart`, shared with `ActivitySheetView`) above are 100% SHARED with
// `variant: win` — only the button background + bottom label text differ
// (design.md D1 / the ADDED spec Requirement's diff table).

/// `variant: activity` button background (`rgb(58 58 58 / 30%)` in the design) —
/// a semi-transparent dark fill, replacing `win`'s opaque white.
const Color _activityBackground = Color(0x4D3A3A3A);

/// Bottom label bar text for `variant: activity`. Reference-ui hardcoded copy,
/// not i18n.
const String _activityLabelText = '活動';

/// The two uses of the SAME `WinEntryView` widget (design.md D1 — one component,
/// two variants, mirroring `moments.jsx`'s `LBWinEntry(variant)` prop rather than
/// forking a second widget class). Differences are limited to background color,
/// bottom label text, and which view-model snapshot gates visibility — the 48×48
/// shell, corner radius, and glyph Path are 100% shared.
enum WinEntryVariant {
  /// Unclaimed-win entry (`DefaultWinClaim`). White background, 「領獎」label,
  /// gated on `unclaimedCount > 0`. The pre-existing (R24) behavior.
  win,

  /// Live-event entry (`DefaultActiveEvent`, rb-flutter-live-activity-sheet /
  /// R26). Semi-transparent dark background, 「活動」label, gated on
  /// `hasActiveEvent`.
  activity,
}

/// The family-2 unclaimed-win / live-event entry (two [WinEntryVariant]s of one
/// widget). A floating square button (the container pins it right-side over the
/// live video), drawn ONLY when its variant's gate passes (`unclaimedCount > 0`
/// for `win`, `hasActiveEvent` for `activity`). Tapping surfaces the variant's
/// open intent: `win` → [onOpen] with `unclaimedWinners.first`; `activity` →
/// [onOpenActivity] with [currentEvent].
///
/// Renders correctly with the default no-op callbacks (golden / preview safe).
class WinEntryView extends StatelessWidget {
  /// The resolved reference-ui theme (FIRST named argument, always). This
  /// design hardcodes both the glyph fills and the button background
  /// (design.md D-1/D-2), so `theme` is only read for [ReferenceUITheme.fontScale]
  /// on the bottom label text.
  final ReferenceUITheme theme;

  /// Which use of this widget to render (design.md D1). Defaults to [WinEntryVariant.win]
  /// so every EXISTING win-only call site (which never passes this) stays source- and
  /// behavior-compatible.
  final WinEntryVariant variant;

  /// Distinct unclaimed-win count (`DefaultWinClaim.unclaimedCount`), BY VALUE.
  /// `variant: win` is drawn ONLY when this is `> 0` (R24 dropped the numeric badge
  /// itself — the count no longer has any other visual effect). Unused by
  /// `variant: activity`.
  final int unclaimedCount;

  /// Unclaimed winners, insertion-ordered, deduped by id
  /// (`DefaultWinClaim.unclaimedWinners`), passed BY VALUE. The container opens
  /// the claim sheet on `unclaimedWinners.first` (earliest); this read-only
  /// surface keeps the value so the wired-intent contract is explicit, but it
  /// NEVER records / removes / reorders winners. Defaults to empty. Unused by
  /// `variant: activity`.
  final List<LBWinner> unclaimedWinners;

  /// Open-claim intent (`variant: win` only). The entry does NOT own the action —
  /// the container / host funnels it to the claim sheet on the EARLIEST unclaimed
  /// winner (D-3). When there is at least one winner it is invoked with
  /// `unclaimedWinners.first`. Default no-op so demo / golden / preview instances
  /// construct action-free.
  final void Function(LBWinner winner)? onOpen;

  /// Whether there is a currently active live event (`DefaultActiveEvent.hasActiveEvent`),
  /// BY VALUE. `variant: activity` is drawn ONLY when this is `true` (R26). Default
  /// `false` — every EXISTING win-only call site (which never passes this) stays
  /// unaffected. Unused by `variant: win`.
  final bool hasActiveEvent;

  /// The bound active event snapshot (`DefaultActiveEvent.current`), BY VALUE — the
  /// `activity`-variant analogue of [unclaimedWinners]. Forwarded VERBATIM to
  /// [onOpenActivity] on tap; this read-only surface never records / clears / mutates
  /// it. `null` when there is nothing active (mirrors [hasActiveEvent] `false`).
  /// Unused by `variant: win`.
  final LBActiveEvent? currentEvent;

  /// Open-activity intent (`variant: activity` only). The entry does NOT own the
  /// action — the container / host funnels it to open the activity sheet on
  /// [currentEvent]. Invoked with [currentEvent] when non-null (a no-op tap
  /// otherwise — defensive; the entry is not drawn when [hasActiveEvent] is false
  /// anyway). Default no-op so demo / golden / preview instances construct
  /// action-free.
  final void Function(LBActiveEvent event)? onOpenActivity;

  const WinEntryView({
    super.key,
    required this.theme,
    this.variant = WinEntryVariant.win,
    this.unclaimedCount = 0,
    this.unclaimedWinners = const [],
    this.onOpen,
    this.hasActiveEvent = false,
    this.currentEvent,
    this.onOpenActivity,
  });

  @override
  Widget build(BuildContext context) {
    final isActivity = variant == WinEntryVariant.activity;

    // Visibility rule (D-3 / R26): nothing to show for this variant → draw nothing.
    if (isActivity) {
      if (!hasActiveEvent) return const SizedBox.shrink();
    } else {
      if (unclaimedCount <= 0) return const SizedBox.shrink();
    }

    return SizedBox(
      key: isActivity ? LbTestKeys.activityEntry : LbTestKeys.winEntry,
      width: _entrySize,
      height: _entrySize,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: isActivity ? _handleOpenActivity : _handleTap,
        child: ClipRRect(
          // `overflow: hidden` — clips the bottom label bar's straight edges to
          // the button's rounded corners.
          borderRadius: BorderRadius.circular(_entryCornerRadius),
          child: Container(
            width: _entrySize,
            height: _entrySize,
            color: isActivity ? _activityBackground : const Color(0xFFFFFFFF),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // Glyph — centered on the FULL 48×48 button area (the design's
                // icon `<span>` is `flex:1` filling the WHOLE button; the label
                // below is `position:absolute` and does NOT shrink it). 100%
                // shared between variants (design.md D1) — no second Path.
                Center(
                  child: CustomPaint(
                    size: const Size(_glyphSize, _glyphSize),
                    painter: const WinTrophyGlyphPainter(),
                  ),
                ),

                // Bottom semi-transparent label bar (`position:absolute; left:0;
                // right:0; bottom:0`).
                Container(
                  width: double.infinity,
                  height: _labelHeight,
                  color: _labelBackground,
                  alignment: Alignment.center,
                  child: Text(
                    isActivity ? _activityLabelText : _labelText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: const Color(0xFFFFFFFF),
                      fontSize: _labelFontSize * theme.fontScale,
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Open the claim sheet on the EARLIEST unclaimed winner. No-op when there is
  /// nothing to open (the entry is not drawn at count 0 anyway).
  void _handleTap() {
    final winners = unclaimedWinners;
    if (winners.isEmpty) return;
    onOpen?.call(winners.first);
  }

  /// Open the activity sheet on [currentEvent]. No-op when there is nothing to
  /// open (the entry is not drawn when `hasActiveEvent` is false anyway; the null
  /// check is defensive).
  void _handleOpenActivity() {
    final event = currentEvent;
    if (event == null) return;
    onOpenActivity?.call(event);
  }
}

