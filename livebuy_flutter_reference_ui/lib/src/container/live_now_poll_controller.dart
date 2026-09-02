import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart' show LBVideoItem, LivebuySDK;

import 'live_buy_live_entry.dart' show liveEntryGate;

// LiveNowPollController — lightweight「現正直播」signal poller for LivebuyPlayer's
// LiveNowPillView (rb-flutter-live-now-pill, Flutter parity of iOS `LiveNowPollController` /
// Android `LiveNowPollController` / RN `useLiveNowPoll`).
//
// Only three things: poll interval / failure fast-retry / `liveStatus == 1` gate. Reuses the
// EXISTING pure `liveEntryGate` (does not re-implement the same logic). Deliberately does NOT
// share an instance with `LivebuyLiveEntry` — the two drop-in surfaces stay independent — and
// does NOT carry `LiveEntryState`'s dismissed / ended-live-id / reset-on-new-live machinery,
// which `LiveNowPillView` has no use for (no user-dismiss affordance, no "recently ended"
// suppression window).
//
// ctor decision (design.md Decision 1): the ctor takes a NON-NULL `shopId` — "whether to poll
// at all" is decided by the CALLER choosing whether to construct this controller, mirroring
// this file's own established `ForegroundResumeController` pattern (`live_buy_player.dart`,
// a nullable field built conditionally inside `initState`) rather than iOS/RN's
// nullable-ctor-internal-no-op shape (which iOS chose freely and RN was FORCED into by React's
// Rules of Hooks — neither constraint applies to a Flutter `StatefulWidget`'s imperative
// lifecycle).

/// Polls whether another live broadcast is currently in progress, for [LivebuyPlayer]'s
/// `LiveNowPillView`. `extends ChangeNotifier` so `_LivebuyPlayerState` can bridge state
/// changes into a rebuild via `addListener` + `setState` (mirrors `PlayerShellView`'s own
/// `template?.subtitle.addListener(...)` bridge — a `ChangeNotifier`, unlike iOS `@Published`
/// / Android `mutableStateOf`, does not auto-trigger a rebuild on its own).
class LiveNowPollController extends ChangeNotifier {
  LiveNowPollController({
    required this.shopId,
    this.pollInterval = const Duration(seconds: 30),
    this.retryInterval = const Duration(seconds: 3),
    Future<LBVideoItem?> Function(String id)? fetch,
  }) : fetch = fetch ?? LivebuySDK.fetchLatestLive;

  /// The shop whose ongoing live is polled. Non-null by construction — see the ctor decision
  /// above; the caller decides whether to build this controller at all.
  final String shopId;

  /// Steady-state poll cadence on success. Default 30s (parity iOS/Android/RN).
  final Duration pollInterval;

  /// Fast-retry cadence after a failed fetch. Default 3s (parity iOS/Android/RN).
  final Duration retryInterval;

  /// Fetch override hook. Dual-use (`docs/unit-test-discipline.md` §4): production default is
  /// the real `LivebuySDK.fetchLatestLive`; a test injects a fake to drive [start] deterministically.
  final Future<LBVideoItem?> Function(String id) fetch;

  LBVideoItem? _liveNow;

  /// The currently-detected other live (gated `liveStatus == 1`), or `null` when there is none.
  LBVideoItem? get liveNow => _liveNow;

  bool _running = false;

  /// Start the poll loop. Idempotent — a second call while already running is a no-op. Runs
  /// until [stop] is called. `try/catch` distinguishes "fetched, but not a qualifying live"
  /// (gated → `null` clears [liveNow]) from "request failed / not yet configured" (thrown →
  /// keep the last-known [liveNow], fast-retry after [retryInterval]).
  Future<void> start() async {
    if (_running) return;
    _running = true;
    while (_running) {
      try {
        final v = await fetch(shopId);
        if (!_running) return;
        _apply(v);
        await Future<void>.delayed(pollInterval);
      } catch (_) {
        await Future<void>.delayed(retryInterval);
      }
    }
  }

  /// Stop the poll loop (idempotent). Does not clear [liveNow] — the last-known value is kept
  /// until a future `start()` (there is none in production: the container tears this whole
  /// controller down on dispose, see `LivebuyPlayer`'s `initState`/`dispose` pairing).
  void stop() => _running = false;

  void _apply(LBVideoItem? raw) {
    _liveNow = liveEntryGate(raw);
    notifyListeners();
  }

  /// Test-only state-transition seam — bypasses the real poll loop entirely (parity iOS/Android
  /// `apply(_:)`). Production code never calls this; only [start]'s loop drives [liveNow] in
  /// production.
  @visibleForTesting
  void applyForTesting(LBVideoItem? raw) => _apply(raw);
}
