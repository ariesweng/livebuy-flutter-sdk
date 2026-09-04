// live_entry_dismiss_memory — pure (zero-pixel) "was THIS live already explicitly dismissed"
// predicate + a thin impure in-memory store, so `LivebuyLiveEntry`（浮動「現正直播」入口卡）can
// remember its own dismissal ACROSS its own remounted instances — rb-flutter-live-entry-dismiss-
// survives-remount.
//
// WHY THIS EXISTS: a host mounts `LivebuyLiveEntry` only while there is no player in the foreground
// (`sessionVideo == null`), so every time the user closes a player (or otherwise leaves that
// no-player state and comes back), the host builds a BRAND NEW `LivebuyLiveEntry` widget instance —
// a fresh `State`, seeded from `initialLiveEntryState` (`dismissed == false`). The existing
// `dismissed` state (`LiveEntryState.dismissed`, reset by `liveEntryShouldResetDismiss` inside
// `applyLiveEntry`) is element-instance-scoped: it lives inside THIS widget instance's `State`, so
// it cannot outlive that instance. The container's own `onClose` doc had already promised「關掉一次，
// 同一場直播不再跳出來，直到下一場」— but that promise could not actually hold once the container
// itself got torn down and rebuilt for the SAME still-ongoing live, which is exactly the common host
// lifecycle above. This module closes that gap: a small piece of state that outlives any single
// `LivebuyLiveEntry` element, remembering the id of the live the user last explicitly dismissed via
// the close button.
//
// ONLY the close button counts. Tapping the card itself to actually go watch the live is a
// completely separate code path (`onTap` → `_openDefaultPlayer` / host `onTapVideo` /
// `externalLiveAwareTap`) and is NOT "I don't want to see this again" — it must NEVER record here.
// The single confirmed write site is `_dismiss()` (`live_buy_live_entry.dart`), called only from the
// close button's `onClose` handler.
//
// WHY A SEPARATE MODULE from `live_entry_close_gate.dart` (mirrors that file's own "why a separate
// library" note): `live_entry_close_gate.dart` bridges TWO different sibling containers
// (`CollapsibleLivebuyPlayer` writes, `LivebuyLiveEntry` reads). This module's producer and consumer
// are the SAME container — just two different instances of it, across a remount — a different
// coordination shape entirely, so it gets its own leaf module rather than growing an unrelated file.
//
// IN-MEMORY ONLY: no persistence (no `SharedPreferences` / disk), no TTL, not merchant-configurable,
// not a new wire field. A process restart naturally clears it (a cold `LiveEntryDismissMemory`
// behaves exactly like `lastDismissedId == null`, i.e. no memory — identical to this module never
// having existed).
//
// ZERO PIXEL: no `Widget` subclass, no `build`. [liveEntryInitialDismissedForId] is PURE — it takes
// every value explicitly (no direct singleton read inside it) so it is deterministically
// unit-testable without touching [LiveEntryDismissMemory]. Only [LiveEntryDismissMemory] itself
// holds real, mutable state, and it is a thin, intentionally under-tested impure singleton (same
// "薄薄的一層 impure glue" posture as `LiveEntryCloseGate`).

/// Whether a freshly-(re)detected live with id [newId] should start `dismissed == true` because the
/// user already explicitly closed the entry for THIS EXACT id before (possibly in a prior
/// `LivebuyLiveEntry` element instance). `newId == null`（no live）→ always `false`（nothing to
/// dismiss). Pure — [lastDismissedId] is passed in explicitly rather than this function reading
/// [LiveEntryDismissMemory] itself, so it is testable without touching the singleton.
///
/// This is a DIFFERENT question from `liveEntryShouldResetDismiss` (which asks "did the live id
/// change, so should we re-evaluate `dismissed` at all") — that existing pure function's contract is
/// UNCHANGED by this module; this function only answers "what should the re-evaluated value BE".
bool liveEntryInitialDismissedForId({
  required String? newId,
  required String? lastDismissedId,
}) =>
    newId != null && newId == lastDismissedId;

/// Thin impure singleton recording the id of the live `LivebuyLiveEntry` was last explicitly
/// dismissed for (close-button tap → `_dismiss()`, see `live_buy_live_entry.dart`), so a FUTURE
/// `LivebuyLiveEntry` element instance (a fresh mount, e.g. after the host closes then reopens the
/// no-player state) can tell it was already dismissed for this exact live and start hidden. Module-
/// level shared memory, NOT Flutter widget `State` and NOT tied to any single element's lifecycle —
/// same "small opt-in bridge singleton" shape as `LiveEntryCloseGate` / `LivebuyWidgetVisibility`.
///
/// Deliberately NOT `@immutable` / a value object — like `LiveEntryCloseGate`, this class exists
/// specifically to hold real, changing state across the container's own remounts.
class LiveEntryDismissMemory {
  LiveEntryDismissMemory._();

  /// The single shared instance every `LivebuyLiveEntry` element instance reads/writes.
  static final LiveEntryDismissMemory instance = LiveEntryDismissMemory._();

  String? _lastDismissedId;

  /// Records [liveId] as the live the user just explicitly closed via the close button. Called by
  /// `LivebuyLiveEntry`'s `_dismiss()` ONLY — no other call site (tapping the card to watch the live
  /// MUST NOT reach this).
  void recordDismissed(String liveId) {
    _lastDismissedId = liveId;
  }

  /// The id of the live last explicitly dismissed, or `null` if none has been this process (or this
  /// singleton was reset for testing). Feed straight into [liveEntryInitialDismissedForId]'s
  /// `lastDismissedId`.
  String? get lastDismissedId => _lastDismissedId;

  /// Test-only: clears the recorded id so tests don't leak state across runs (this is a process-wide
  /// singleton, not scoped to any widget's lifecycle).
  void resetForTesting() {
    _lastDismissedId = null;
  }
}
