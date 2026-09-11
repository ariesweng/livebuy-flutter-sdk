// cc_tooltip_layout.dart — pure horizontal layout math for the CC (字幕) "unavailable" tooltip
// bubble (`rb-flutter-cc-tooltip-viewport-clamp`).
//
// Spec: `reference-ui-rendering/spec.md` (`rb-flutter-cc-tooltip-viewport-clamp`, MODIFIED
// section of the "LivebuyReferenceUI（Flutter）渲染 LIVE 底部 bar 並把側欄改 VOD-only"
// Requirement).
//
// Both `live_bottom_bar_view.dart`'s `_CcTrailingButton` (LIVE 回放 bottom-bar, `top` placement)
// and `operation_rail.dart`'s `_CcPillButton` (VOD side rail, `left` placement) show a
// short-lived `CcUnavailableTooltip` when the CC glyph is tapped while unavailable. The `left`
// placement grows AWAY from the screen edge it hugs (the rail sits at the right edge, the bubble
// extends further left into open video space) and has no reported overflow issue — it is NOT
// touched by this file or its call site.
//
// The `top` placement, however, was naively centered on the tapped button's own X position with
// no awareness of the screen edge: a CC button sitting close to the right edge of the LIVE
// bottom bar could have its bubble's right side pushed past the visible viewport, rendering as a
// truncated/incomplete-looking tooltip. [clampCcTooltipCenterX] is the fix — pure, deterministic
// math with no Flutter dependency, so it can be unit tested exhaustively without a widget
// pipeline.
library;

/// Clamps the tooltip bubble's desired horizontal center ([desiredCenterX], normally the tapped
/// button's own global center X) so a [bubbleWidth]-wide bubble drawn at the returned center
/// stays at least [edgeMargin] logical pixels inside both viewport edges (`[0, viewportWidth]`).
///
/// Falls back to centering the bubble in the viewport (`viewportWidth / 2`) when [bubbleWidth]
/// itself does not fit inside the clampable interior (`viewportWidth - 2 * edgeMargin`) — e.g. an
/// unrealistically narrow viewport — rather than returning an interval with `min > max`, which
/// `num.clamp` would throw on.
double clampCcTooltipCenterX({
  required double viewportWidth,
  required double desiredCenterX,
  required double bubbleWidth,
  double edgeMargin = 8,
}) {
  final halfBubble = bubbleWidth / 2;
  final minCenter = edgeMargin + halfBubble;
  final maxCenter = viewportWidth - edgeMargin - halfBubble;
  if (minCenter > maxCenter) {
    return viewportWidth / 2;
  }
  return desiredCenterX.clamp(minCenter, maxCenter);
}

/// Compensating horizontal offset for the tooltip's ARROW glyph, given the horizontal shift
/// already applied to the BUBBLE for the viewport-edge clamp above (`rb-flutter-cc-tooltip-
/// arrow-anchor-fix`).
///
/// [clampCcTooltipCenterX] fixes the bubble body overflowing the viewport, but the caller applies
/// its resulting [bubbleShift] to the WHOLE tooltip (bubble + arrow) as one rigid group — the
/// arrow's own horizontal position is otherwise defined purely relative to the bubble's center,
/// with no awareness of the button it is meant to point at. Once [bubbleShift] is non-zero (the
/// button sits close enough to a screen edge to engage the clamp), the arrow drifts away from the
/// real button by the same amount, no longer pointing at it.
///
/// The fix is a second, independent `Transform.translate` applied ONLY to the arrow, on top of
/// the existing bubble-level shift. This function returns that second offset: the exact negation
/// of [bubbleShift]. In screen space the two cancel out (`bubbleShift + -bubbleShift == 0`), so
/// the arrow's absolute horizontal position stays pinned to wherever it was BEFORE any clamp was
/// applied — i.e. the button's true, unclamped center — while the bubble itself keeps the full
/// [bubbleShift] and stays safely on-screen.
///
/// `bubbleShift == 0` (the common case, button not near an edge) returns `0` — a no-op, so
/// rendering stays byte-identical to before this compensation existed.
double arrowCompensationOffset(double bubbleShift) => -bubbleShift;
