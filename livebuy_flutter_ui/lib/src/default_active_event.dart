import 'package:flutter/foundation.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart';

// live-activity-entry-flutter-template — Flutter view-model that merges core's
// existing `activeEvents()` snapshot + `ACTIVE_EVENT_STARTED` fire-once push
// into one reference-ui-bindable "current active event" state, plus a「參加」
// intent that reuses the existing `EventJoinRequester` seam. Role symmetric
// with `DefaultWinClaim` (merges `winner[]`/`award` → `unclaimedCount` /
// `unclaimedWinners`), but kept as an INDEPENDENT file/class (design.md D5) —
// not folded into `DefaultActivityFeed`, whose concern is the merged chat/
// activity feed ordering, not this persistent "is there an active event" state.
//
// Spec: `ui-template-foundation/spec.md`
//   § "Default Template（Flutter）進行中活動合流狀態（`DefaultActiveEvent`）"
//   § "Default Template（Flutter）參加進行中活動（重用既有 join 機制）"
//   § "Default Template（Flutter）活動入口換片快取"
// Design: design.md D1–D5 (live-activity-entry-flutter-template) +
//   activity-sheet-multi-activity-template-flutter design.md D1–D4.
//
// zero-pixel: only `package:flutter/foundation.dart` (ChangeNotifier) +
// the core package for `LBActiveEvent` — NO material.dart / widgets.dart /
// build().
//
// D2 — `handleActiveEventStarted` never CLEARS the list (ACTIVE_EVENT_STARTED
//      is fire-once, with no matching "event ended" push). `updateSnapshot` is
//      the ONLY path that can empty [activities] out (an empty snapshot means
//      the next `activeEvents()` round no longer returns any active event).
// D3 — `join()` reuses the EXISTING `EventJoinRequester` typedef (the same seam
//      `DefaultPlayerTemplate.joinEvent` already uses) — no second typedef, no
//      second call-into-core path. The「活動」entry CTA and the chat-flow
//      `LBEventJoinLine`「加入活動」CTA are the SAME core action
//      (`EVENT_JOIN_INTENT`), just triggered from a different visual entry point.
// D4 — `joined` is deduped by `current.id` against a persistent `Set<int>`, not
//      a transient widget-local `useState` — it survives reopening a sheet.
// D5 — independent file/class from `DefaultActivityFeed` (see header above).
//
// activity-entry-video-switch-cache-and-hide-flutter — [switchVideo] adds a
// per-videoId snapshot cache so an in-place video switch (`navigateToPrev` /
// `navigateToNext` → core → `VIDEO_SWITCH` event) resolves [current]
// IMMEDIATELY (not waiting for the next 5s poll's [updateSnapshot]): a video
// visited earlier this session restores its last-known snapshot, a
// never-visited video collapses to `null`. Deliberately instance-level —
// NOT a process-level singleton like iOS's chat-history
// `VideoFeedSnapshotCache.shared` — because an in-place switch reuses the SAME
// `DefaultPlayerTemplate` / `DefaultActiveEvent` instance (it is never
// recreated mid-session), so a plain `Map` already survives the switch.
//
// activity-sheet-multi-activity-template-flutter — REVERSES the original
// live-activity-entry-flutter-template design.md D1 ("`current` only ever
// takes the array's first entry, never a list — `moments.jsx` has no
// multi-active-event visual language"). That premise no longer holds: hosts
// now need the FULL list + a page index to draw multiple simultaneously
// live activities with swipeable pagination dots (reference-ui concern,
// out of scope here). [current] is KEPT (same signature) but is now a
// DERIVED value — `activities.isEmpty ? null : activities[currentActivityPageIndex]`
// — so existing callers (`join()`, `DefaultPlayerTemplate`) do not need to
// change. See design.md (this change) D1–D4 for the full rationale, including
// how the per-videoId switch cache (above) integrates with the list model:
// the cache still stores a single `LBActiveEvent?` snapshot (the page that was
// showing at the moment of leaving), restored into a one-item list at page 0;
// any other concurrently-active events for that video are backfilled by the
// next poll round's [updateSnapshot], not by the switch cache.
class DefaultActiveEvent extends ChangeNotifier {
  // Deliberately NOT importing `default_template.dart`'s `EventJoinRequester`
  // typedef here (would create a circular file import, and would add a third
  // import beyond this file's zero-pixel self-check surface — task 1.7). A
  // Dart typedef of a function type is a pure alias, not a distinct nominal
  // type, so this inline signature IS `EventJoinRequester` structurally — any
  // value typed `EventJoinRequester` (e.g. `DefaultPlayerTemplate`'s
  // `_eventJoinRequester`) assigns here with zero cast. This is the SAME seam,
  // not a second typedef (design.md D3).
  final void Function(int eid, String keyword) _eventJoinRequester;

  /// Full list of currently-active events (activity-sheet-multi-activity-template-flutter
  /// D1 — reverses the original "only keep the first entry" decision). [current]
  /// is a derived view into this list at [_pageIndex].
  List<LBActiveEvent> _events = [];

  /// Index into [_events] the host is currently paged to. Always kept within
  /// `[0, _events.length - 1]` (or `0` when [_events] is empty) via
  /// [clampActivityPageIndex] — see [setActivityPageIndex] / [updateSnapshot].
  int _pageIndex = 0;

  /// Event ids already joined (D4) — dedupe persists across sheet reopen,
  /// reset only by [clear] / [switchVideo] (`VIDEO_SWITCH`). A NEW event id
  /// (not yet in this set) naturally reports `joined == false` with no extra
  /// "reset" logic.
  final Set<int> _joinedEventIds = {};

  /// Per-videoId snapshot cache (activity-entry-video-switch-cache-and-hide-flutter),
  /// keyed by the videoId `String` wire shape (`from_video_id` / `to_video_id`).
  /// Instance-level — see the class-header note above for why this does NOT need to
  /// be a process-level singleton. Written / read only by [switchVideo]. Deliberately
  /// KEPT as a single `LBActiveEvent?` value (not upgraded to a list) — see the
  /// class-header note on activity-sheet-multi-activity-template-flutter / design.md D2:
  /// this cache is a switch-time display placeholder, not an attempt to reconstruct the
  /// full concurrent-activity set at the moment of leaving.
  final Map<String, LBActiveEvent?> _snapshotByVideoId = {};

  DefaultActiveEvent({void Function(int eid, String keyword)? eventJoinRequester})
      : _eventJoinRequester = eventJoinRequester ?? ((_, __) {});

  /// Full list of currently-active events (activity-sheet-multi-activity-template-flutter
  /// D1) — reference-ui binds this to draw pagination dots / swipe between
  /// simultaneously-live activities. `List.unmodifiable` — callers MUST NOT mutate.
  List<LBActiveEvent> get activities => List.unmodifiable(_events);

  /// The page index [current] is derived from. Always within
  /// `[0, activities.length - 1]` (or `0` when [activities] is empty).
  int get currentActivityPageIndex => _pageIndex;

  /// The active event snapshot currently paged to; `null` = no active event.
  /// DERIVED from [activities] / [currentActivityPageIndex] — no longer a
  /// stored field (activity-sheet-multi-activity-template-flutter D1).
  LBActiveEvent? get current => _events.isEmpty ? null : _events[_pageIndex];

  /// True while [current] is non-null (host binds this to show the entry).
  bool get hasActiveEvent => current != null;

  /// Whether [current] has already been joined — deduped by `current.id`
  /// against the persistent [_joinedEventIds] set (D4). `false` when
  /// [current] is `null`.
  bool get joined {
    final event = current;
    return event != null && _joinedEventIds.contains(event.id);
  }

  /// `ACTIVE_EVENT_STARTED` fire-once push arrived. UPSERTS [event] into
  /// [_events] by `event.id` (activity-sheet-multi-activity-template-flutter D3):
  /// an existing id is updated in place (keeps its position); a new id is
  /// appended. Either way [_pageIndex] jumps to that event's index — preserving
  /// the original "you immediately see the newly-started event" guarantee —
  /// without discarding any other concurrently-active events already in the
  /// list (the pre-reversal implementation replaced the single `current`
  /// wholesale; this upserts instead). MUST NEVER empty [activities] out (D2):
  /// this push declares a new/updated event, it is not a continuous "is it
  /// still alive" signal for the OTHER entries already in the list.
  void handleActiveEventStarted(LBActiveEvent event) {
    final idx = _events.indexWhere((e) => e.id == event.id);
    if (idx >= 0) {
      _events = List.of(_events)..[idx] = event;
      _pageIndex = idx;
    } else {
      _events = List.of(_events)..add(event);
      _pageIndex = _events.length - 1;
    }
    notifyListeners();
  }

  /// Host-driven backfill after calling the core `activeEvents()` accessor
  /// (covers the "joined mid-live, missed the fire-once push" blind spot, and
  /// is the authoritative source for "an activity has ended" — goods simply
  /// stops returning it). Replaces [activities] wholesale with [events]
  /// (activity-sheet-multi-activity-template-flutter D1 — keeps the FULL list,
  /// no longer takes only `.first`), then safely clamps [_pageIndex] into the
  /// new list's range via [clampActivityPageIndex]. `events.isEmpty` is the
  /// path that clears [current] back to `null`.
  void updateSnapshot(List<LBActiveEvent> events) {
    _events = List.unmodifiable(events);
    _pageIndex = clampActivityPageIndex(_pageIndex, _events.length);
    notifyListeners();
  }

  /// Host-driven pagination (activity-sheet-multi-activity-template-flutter):
  /// switch [current] to [activities][index]. Out-of-range [index] is safely
  /// clamped via [clampActivityPageIndex] — MUST NOT throw. A no-op call (the
  /// clamped index equals the current one — including every call while
  /// [activities] is empty, which always clamps to `0`) does NOT notify.
  void setActivityPageIndex(int index) {
    final clamped = clampActivityPageIndex(index, _events.length);
    if (clamped == _pageIndex) return;
    _pageIndex = clamped;
    notifyListeners();
  }

  /// Host-triggered「參加」intent (D3). Safe no-op when there is no active
  /// event; otherwise calls the injected `EventJoinRequester`-shaped seam with
  /// `(current!.id, current!.keyword ?? '')` — the SAME seam
  /// `DefaultPlayerTemplate.joinEvent` already uses, so there is exactly one
  /// call-into-core path for「加入活動」regardless of entry point — then
  /// records `current!.id` as joined and notifies once.
  void join() {
    final event = current;
    if (event == null) return;
    _eventJoinRequester(event.id, event.keyword ?? '');
    _joinedEventIds.add(event.id);
    notifyListeners();
  }

  /// `VIDEO_SWITCH` — reset for the next video (parity with `feed.clear()` /
  /// `winClaim.clear()`): clears [activities] to `[]`, resets [_pageIndex] to
  /// `0`, and clears the joined-ids set. No videoId context (no cache save /
  /// restore) — for call sites that don't have `from`/`to` (e.g. direct test
  /// calls). See [switchVideo] for the videoId-aware path.
  void clear() {
    _events = [];
    _pageIndex = 0;
    _joinedEventIds.clear();
    notifyListeners();
  }

  /// `VIDEO_SWITCH` with videoId context (activity-entry-video-switch-cache-and-hide-flutter,
  /// extended by activity-sheet-multi-activity-template-flutter D2). Saves the
  /// pre-switch [current] (the single event currently paged to — NOT the full
  /// [activities] list) under [from] (so switching back later can restore it),
  /// then immediately resolves it for [to] via [resolveOnVideoSwitch] — no
  /// waiting for the next 5s poll's [updateSnapshot]. The restored snapshot (if
  /// any) becomes [activities]'s sole entry at page `0`; any OTHER events that
  /// were concurrently active for [to] at the time it was left are NOT
  /// reconstructed by this cache — they are backfilled by the next poll round's
  /// [updateSnapshot] (design.md D2: this cache is a display placeholder, not a
  /// full-set reconstruction). Also clears [_joinedEventIds] (parity with
  /// [clear]'s existing per-video-session reset — the cache only carries the
  /// [current] snapshot, not joined state). Omitting both [from] / [to] behaves
  /// identically to [clear] (keeps existing no-id call sites — e.g.
  /// `DefaultPlayerTemplate.handleVideoSwitch()`'s legacy no-arg calls — working
  /// unchanged).
  void switchVideo({String? from, String? to}) {
    if (from != null) _snapshotByVideoId[from] = current;
    final restored = resolveOnVideoSwitch(_snapshotByVideoId, to);
    _events = restored == null ? [] : [restored];
    _pageIndex = 0;
    _joinedEventIds.clear();
    notifyListeners();
  }
}

/// Pure: resolve [DefaultActiveEvent.current] for a video switch to [to] — a cache
/// hit restores the last-known snapshot for that video (may itself be `null`,
/// meaning "visited, but had no active event"); a miss (never visited this session,
/// or [to] itself `null`) resolves to `null` (hide immediately; the next poll round's
/// `updateSnapshot` fills in the real answer). Extracted as a top-level pure function
/// per docs/unit-test-discipline.md (mirrors `default_activity_feed.dart`'s
/// `trimmedByType` convention) — directly unit-testable without instantiating
/// [DefaultActiveEvent]. Signature/behavior UNCHANGED by
/// activity-sheet-multi-activity-template-flutter — it still resolves a single
/// `LBActiveEvent?`; [DefaultActiveEvent.switchVideo] wraps the result into a
/// one-item (or empty) list.
@visibleForTesting
LBActiveEvent? resolveOnVideoSwitch(Map<String, LBActiveEvent?> cache, String? to) =>
    to == null ? null : cache[to];

/// Pure: clamp a page [index] into the valid range for a list of [length]
/// activities — `[0, length - 1]`, or `0` when [length] is `0` (empty list).
/// Never throws. Extracted as a top-level pure function per
/// docs/unit-test-discipline.md (mirrors [resolveOnVideoSwitch]) — directly
/// unit-testable without instantiating [DefaultActiveEvent]. Used by both
/// [DefaultActiveEvent.updateSnapshot] (clamp after a list-size change) and
/// [DefaultActiveEvent.setActivityPageIndex] (clamp a host-supplied index).
@visibleForTesting
int clampActivityPageIndex(int index, int length) {
  if (length <= 0) return 0;
  if (index < 0) return 0;
  if (index >= length) return length - 1;
  return index;
}
