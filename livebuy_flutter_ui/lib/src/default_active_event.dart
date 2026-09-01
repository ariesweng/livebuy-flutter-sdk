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
// Design: design.md D1–D5.
//
// zero-pixel: only `package:flutter/foundation.dart` (ChangeNotifier) +
// the core package for `LBActiveEvent` — NO material.dart / widgets.dart /
// build().
//
// D1 — `current` is a single `LBActiveEvent?`, not a list: `moments.jsx` only
//      draws one「活動」entry + one sheet, no multi-active-event visual language.
// D2 — `handleActiveEventStarted` only ever SETS `current`, never clears it
//      (ACTIVE_EVENT_STARTED is fire-once, with no matching "event ended" push).
//      `updateSnapshot` is the ONLY path that can null `current` out (an empty
//      snapshot means the next `activeEvents()` round no longer returns it).
// D3 — `join()` reuses the EXISTING `EventJoinRequester` typedef (the same seam
//      `DefaultPlayerTemplate.joinEvent` already uses) — no second typedef, no
//      second call-into-core path. The「活動」entry CTA and the chat-flow
//      `LBEventJoinLine`「加入活動」CTA are the SAME core action
//      (`EVENT_JOIN_INTENT`), just triggered from a different visual entry point.
// D4 — `joined` is deduped by `current.id` against a persistent `Set<int>`, not
//      a transient widget-local `useState` — it survives reopening a sheet.
// D5 — independent file/class from `DefaultActivityFeed` (see header above).
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

  LBActiveEvent? _current;

  /// Event ids already joined (D4) — dedupe persists across sheet reopen,
  /// reset only by [clear] (`VIDEO_SWITCH`). A NEW event id (not yet in this
  /// set) naturally reports `joined == false` with no extra "reset" logic.
  final Set<int> _joinedEventIds = {};

  DefaultActiveEvent({void Function(int eid, String keyword)? eventJoinRequester})
      : _eventJoinRequester = eventJoinRequester ?? ((_, __) {});

  /// The current active event snapshot; `null` = no active event.
  LBActiveEvent? get current => _current;

  /// True while [current] is non-null (host binds this to show the entry).
  bool get hasActiveEvent => _current != null;

  /// Whether [current] has already been joined — deduped by `current.id`
  /// against the persistent [_joinedEventIds] set (D4). `false` when
  /// [current] is `null`.
  bool get joined => _current != null && _joinedEventIds.contains(_current!.id);

  /// `ACTIVE_EVENT_STARTED` fire-once push arrived — SETS `current` to
  /// [event]. MUST NEVER clear `current` to `null` (D2): this push declares a
  /// new event has begun, it is not a continuous "is it still alive" signal.
  void handleActiveEventStarted(LBActiveEvent event) {
    _current = event;
    notifyListeners();
  }

  /// Host-driven backfill after calling the core `activeEvents()` accessor
  /// (covers the "joined mid-live, missed the fire-once push" blind spot).
  /// `events.isEmpty ? null : events.first` — the ONLY path that can clear
  /// [current] back to `null` (D1 / D2): an empty snapshot means the event has
  /// ended (the next `POST /sdk/video/goods` round no longer returns it).
  void updateSnapshot(List<LBActiveEvent> events) {
    _current = events.isEmpty ? null : events.first;
    notifyListeners();
  }

  /// Host-triggered「參加」intent (D3). Safe no-op when there is no active
  /// event; otherwise calls the injected `EventJoinRequester`-shaped seam with
  /// `(current!.id, current!.keyword ?? '')` — the SAME seam
  /// `DefaultPlayerTemplate.joinEvent` already uses, so there is exactly one
  /// call-into-core path for「加入活動」regardless of entry point — then
  /// records `current!.id` as joined and notifies once.
  void join() {
    final event = _current;
    if (event == null) return;
    _eventJoinRequester(event.id, event.keyword ?? '');
    _joinedEventIds.add(event.id);
    notifyListeners();
  }

  /// `VIDEO_SWITCH` — reset for the next video (parity with `feed.clear()` /
  /// `winClaim.clear()`): clears [current] and the joined-ids set.
  void clear() {
    _current = null;
    _joinedEventIds.clear();
    notifyListeners();
  }
}
