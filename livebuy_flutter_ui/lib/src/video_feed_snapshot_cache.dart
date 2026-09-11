import 'package:flutter/foundation.dart';

import 'default_activity_feed.dart';

// chat-history-video-switch-cache-flutter — process-level bounded chat-history
// switchback cache. Flutter parity of iOS
// `ios/Sources/LivebuyUI/Templates/Default/VideoFeedSnapshotCache.swift` / Android
// `tv.livebuy.ui.templates.default_template.VideoFeedSnapshotCache`
// (`chat-history-video-switch-cache-template`(-android) +
// `chat-history-video-switch-cache-cross-instance`(-android), both already archived).
//
// Spec: `chat-history-dedupe-feed/spec.md`
//   § "in-place 換片還原已造訪影片的聊天歷史快照（Flutter）"
// Design: openspec/changes/chat-history-video-switch-cache-flutter/design.md D1–D5.
//
// Reported bug this closes: switching A → B → A on Flutter cleared the chat/activity feed on
// EVERY switch (`DefaultPlayerTemplate.handleVideoSwitch` unconditionally called
// `feed.clear()`), even though core's `MessagesCursorStore` (headless, unchanged) already keeps
// A's poll cursor warm — `PollManager` correctly skips `is_init` when landing back on A, but with
// no consumer-side cache the template had nothing to show until new messages trickled in. This
// mirrors EXACTLY the gap iOS/Android already fixed.
//
// D1 (ported unchanged) — `{history, seenPushIds}` is cached/restored as ONE atomic unit per
// videoId, never `history` alone: `LBFeedItem`s from the poll `push[]` bucket carry a stable id
// and are de-duped against `DefaultPlayerTemplate._seenPushIds`
// (`flutter-chat-push-id-dedupe-template`) — if `seenPushIds` reset to empty on restore, a later
// poll round that happens to redeliver an already-restored id would no longer be recognized as
// "already seen" and could append a visible duplicate.
//
// D2 (ported unchanged, enforced by `default_template.dart`'s `handleVideoSwitch`, NOT this
// file) — on a cache-hit restore, `_hasIngestedBacklog` is forced `true` so a stray whole backlog
// round for an already-known video is dropped wholesale (the id-less `user[]`/`rush[]` buckets
// get no protection from D1 alone).
//
// D3 — scope decision for THIS change (Flutter, single-shot catch-up rather than iOS/Android's
// staged `-template` then `-cross-instance` rollout): built as a PROCESS-LEVEL SINGLETON
// ([shared]) from the start, matching iOS/Android's CURRENT shape — so a future cross-instance
// follow-up (if pursued) is a pure wiring change, not a cache-shape migration. However, ONLY
// `DefaultPlayerTemplate.handleVideoSwitch`'s `from`/`to` path saves/restores via this cache in
// this change (parity with the ORIGINAL `chat-history-video-switch-cache-template`'s scope) —
// Flutter's `TemplateAttachment` already threads `from`/`to` through BOTH the in-place
// `VIDEO_SWITCH` case AND the `flutter-video-open-reset-backstop-template` VIDEO_OPEN backstop
// (both funnel through the SAME `DefaultPlayerTemplate` instance, which — unlike the native
// player view — is NOT torn down across those transitions), so this already covers every
// host-driven video transition within one player session. NOT covered (explicit non-goal,
// mirrors iOS/Android's original `-template`-only scope): saving a final snapshot when the WHOLE
// player (and this `DefaultPlayerTemplate` instance) is disposed with no replacement video opened
// — that would need a new save-on-dispose hook in `TemplateAttachment`, out of scope here (see
// design.md Non-Goals / Open Questions).

/// One saved snapshot: the feed's `history` at the moment the user switched away, PLUS the
/// push-id de-dup set (`DefaultPlayerTemplate._seenPushIds`,
/// `flutter-chat-push-id-dedupe-template`) at that same moment — an immutable value,
/// saved/restored together as ONE atomic unit (D1) so restoring history can never reopen a
/// duplicate-id hole.
@immutable
class VideoFeedSnapshot {
  final List<LBFeedItem> history;
  final Set<String> seenPushIds;

  const VideoFeedSnapshot({required this.history, required this.seenPushIds});
}

/// Result pair for [inserting] — a small named value class (Dart records postdate this
/// package's existing tuple-shaped helpers, e.g. `default_active_event.dart`'s
/// `resolveOnVideoSwitch`, which return a single value; this one genuinely needs two, so a
/// named class keeps the pure function's return self-documenting without introducing a new
/// tuple idiom into the file).
@visibleForTesting
class LruUpsertResult {
  final Map<String, VideoFeedSnapshot> snapshots;
  final List<String> order;

  const LruUpsertResult(this.snapshots, this.order);
}

/// Pure: LRU insert-or-update + bound eviction (docs/unit-test-discipline.md — extracted so
/// eviction is unit-testable without constructing [VideoFeedSnapshotCache]). Moves [videoId] to
/// most-recently-used; evicts the single least-recently-visited entry once [order]'s length
/// would exceed [maxEntries]. Mirrors iOS `VideoFeedSnapshotCache.inserting` / Android
/// `VideoFeedSnapshotCache.inserting` exactly (D5).
@visibleForTesting
LruUpsertResult inserting({
  required String videoId,
  required VideoFeedSnapshot snapshot,
  required Map<String, VideoFeedSnapshot> snapshots,
  required List<String> order,
  required int maxEntries,
}) {
  final nextSnapshots = Map<String, VideoFeedSnapshot>.of(snapshots);
  final nextOrder = List<String>.of(order);
  nextSnapshots[videoId] = snapshot;
  nextOrder.remove(videoId);
  nextOrder.add(videoId);
  if (nextOrder.length > maxEntries) {
    final oldest = nextOrder.removeAt(0);
    nextSnapshots.remove(oldest);
  }
  return LruUpsertResult(nextSnapshots, nextOrder);
}

/// Process-level bounded chat-history switchback cache (D3). See file header for the full
/// rationale and this change's explicit in-place-switch-only scope.
class VideoFeedSnapshotCache {
  /// Max distinct videoIds retained — matches iOS/Android's CURRENT (post cross-instance
  /// promotion) bound. See those files' doc comments for the sizing rationale.
  static const int maxEntriesDefault = 20;

  /// Process-wide shared instance used by production `DefaultPlayerTemplate`s (the default for
  /// its `feedSnapshotCache` constructor parameter). Tests inject an independent
  /// `VideoFeedSnapshotCache()` instance, or call [resetForTesting] on this shared instance, to
  /// avoid cross-test bleed within one test file (mirrors iOS/Android `.shared.reset()`).
  static VideoFeedSnapshotCache shared = VideoFeedSnapshotCache();

  final int maxEntries;
  Map<String, VideoFeedSnapshot> _snapshots = {};

  /// Recency order, oldest (least-recently-visited) first — LRU eviction.
  List<String> _order = [];

  VideoFeedSnapshotCache({int maxEntries = maxEntriesDefault})
      : maxEntries = maxEntries < 1 ? 1 : maxEntries;

  /// The cached snapshot for [videoId], or `null` if never visited (or evicted). A lookup does
  /// NOT affect recency — only [save] moves an entry to most-recently-used.
  VideoFeedSnapshot? snapshotFor(String videoId) => _snapshots[videoId];

  /// Save (or refresh) [videoId]'s snapshot. A snapshot with EMPTY [history] is not worth caching
  /// (nothing to restore later, and it would just occupy a slot) — skipped silently.
  void save(String videoId, List<LBFeedItem> history, Set<String> seenPushIds) {
    if (history.isEmpty) return;
    final result = inserting(
      videoId: videoId,
      snapshot: VideoFeedSnapshot(
        history: List.unmodifiable(history),
        seenPushIds: Set.unmodifiable(seenPushIds),
      ),
      snapshots: _snapshots,
      order: _order,
      maxEntries: maxEntries,
    );
    _snapshots = result.snapshots;
    _order = result.order;
  }

  /// Test-only: drop every saved snapshot — needed because [shared] is a process-wide singleton
  /// so multiple `test()` cases in one file don't bleed videoIds into each other. No production
  /// caller.
  @visibleForTesting
  void resetForTesting() {
    _snapshots = {};
    _order = [];
  }
}
