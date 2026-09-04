// live_entry_close_gate — pure (zero-pixel) close-grace math + a thin impure clock-backed store,
// bridging TWO independent Flutter turnkey containers: `CollapsibleLivebuyPlayer` (the collapsible
// player presenter) and `LivebuyLiveEntry` (the「現正直播」floating entry) —
// rb-flutter-live-entry-close-grace-period.
//
// WHY THIS EXISTS: a host mounts `LivebuyLiveEntry` only while there is no player in the
// foreground (`sessionVideo == null`), so closing `CollapsibleLivebuyPlayer` and mounting
// `LivebuyLiveEntry` happen almost back-to-back. `LivebuyLiveEntry` already has an entrance-timing
// setting (`kLiveEntryDefaultDelaySeconds` / `LBFloatingEntryTiming`, `live_entry_position_timing.dart`),
// but that setting answers a DIFFERENT question — "should the entry wait before appearing on a cold
// app open, before the user has watched anything" — not "did the user JUST close a player in this
// exact corner". Reusing that merchant-configured value would conflate the two, and the common
// default (`immediate`, zero wait) does not cover the close case at all — hence a SEPARATE, fixed,
// SDK-internal 2s buffer, entirely independent of `floating_setting` / any merchant config.
//
// WHY A SEPARATE LIBRARY (mirrors design D9 in `live_entry_position_timing.dart`): both consuming
// containers already import `live_entry_position_timing.dart` (`LivebuyLiveEntry` directly;
// `CollapsibleLivebuyPlayer` for `LBFloatingEntryPosition` / `lbLiveEntryClampDx`) — this coordination
// concern is orthogonal to that file's position/timing/geometry helpers, so it lives in its own leaf
// module rather than growing an unrelated file or forcing a two-way import between the two containers.
//
// ZERO PIXEL: no `Widget` subclass, no `build`. The two top-level functions below are PURE — they
// take every timestamp explicitly (no `DateTime.now()` inside them) so they are deterministically
// unit-testable. Only [LiveEntryCloseGate] touches a real clock, and it is a thin, intentionally
// under-tested impure singleton (design instruction: "薄薄的一層 impure glue,不強求完整測試覆蓋").

/// The fixed close-grace window (rb-flutter-live-entry-close-grace-period): **2 seconds**,
/// merchant-config-independent — NOT sourced from `extensions.floating_setting`, NOT a new wire
/// field, NOT host-configurable. Consumed as [liveEntryCloseGraceRemainingMs]'s default `graceMs`.
const int kLiveEntryCloseGraceMs = 2000;

/// How long, in milliseconds, since the player was last closed by the user. `null` when
/// [lastClosedAtMs] is `null` (the player has never been closed this process — a genuine cold
/// open). Pure: both timestamps are passed in explicitly, so this is testable without a real
/// clock and without waiting real wall-clock time.
int? msSinceLastPlayerClose({required int? lastClosedAtMs, required int nowMs}) {
  if (lastClosedAtMs == null) return null;
  return nowMs - lastClosedAtMs;
}

/// How much of the close-grace window remains, in milliseconds. `0` — no wait needed — when
/// [msSinceClose] is `null` (never closed; see [msSinceLastPlayerClose]) or has already reached
/// or exceeded [graceMs]. Otherwise the remaining `graceMs - msSinceClose`. Pure.
int liveEntryCloseGraceRemainingMs({
  required int? msSinceClose,
  int graceMs = kLiveEntryCloseGraceMs,
}) {
  if (msSinceClose == null || msSinceClose >= graceMs) return 0;
  return graceMs - msSinceClose;
}

/// Thin impure singleton recording the wall-clock moment `CollapsibleLivebuyPlayer` was last
/// closed by the user (`_close()` / `onDismiss()` — see that file), for [LivebuyLiveEntry] (a
/// fully independent sibling container, see `live_buy_live_entry.dart`) to read. Module-level
/// shared memory, NOT React/Flutter widget state and NOT tied to either container's lifecycle —
/// same "small opt-in bridge singleton" shape as the existing `LivebuyWidgetVisibility` bridge
/// (`widget/live_buy_widget_visibility.dart`).
///
/// Deliberately NOT `@immutable` / a value object — unlike the pure helpers above, this class
/// exists specifically to hold real, changing, wall-clock-derived state.
class LiveEntryCloseGate {
  LiveEntryCloseGate._();

  /// The single shared instance both containers read/write.
  static final LiveEntryCloseGate instance = LiveEntryCloseGate._();

  int? _lastClosedAtMs;

  /// Records "now" (real wall clock) as the last-close timestamp. Called by
  /// `CollapsibleLivebuyPlayer._close()` / its `onDismiss()` config seam — the two confirmed
  /// genuine user-close paths — and by no other call site.
  void recordClose() {
    _lastClosedAtMs = DateTime.now().millisecondsSinceEpoch;
  }

  /// The last recorded close timestamp (epoch ms), or `null` if the player has never been closed
  /// this process. Feed straight into [msSinceLastPlayerClose]'s `lastClosedAtMs`.
  int? get lastClosedAtMs => _lastClosedAtMs;

  /// Test-only: clears the recorded timestamp so tests don't leak state across runs (this is a
  /// process-wide singleton, not scoped to a widget's lifecycle).
  void resetForTesting() {
    _lastClosedAtMs = null;
  }
}
