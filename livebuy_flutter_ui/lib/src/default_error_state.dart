import 'package:flutter/foundation.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart';

// livebuy-ui-event-join-and-error-state-template — Player error-state exposure
// (behaviour / view-model layer; NO pixels).
//
// Spec: ui-template-foundation/spec.md § "Default Template Player Error-State 暴露".
// Design: design.md Decision 3 / Decision 4.
//
// core stays headless: it owns the player state machine, the LBError
// classification, and the 3×/3s HLS retry. This model maps a typed [LBError]
// into a host-bindable `{ kind, phase }` so the host can draw the `moments.jsx`
// `LBPErrorScreen`. The template never renders the error screen itself.
//
// Flutter wiring note (design — host-wired typed error): the Flutter UI template
// subscribes to the unified bridge listener, where `VIDEO_ERROR` carries only a
// platform-dependent `description` (NOT a cross-platform type). The typed,
// cross-platform `LBError` is available on the per-view channel via
// `LivebuyPlayer.onError`, which the HOST owns. So the host wires its player's
// `onError` → [DefaultPlayerTemplate.handleError] → [recordError]; error CLEARING
// is auto-driven from the unified `VIDEO_STATE_CHANGE` (see
// `DefaultPlayerTemplate.handlePlayerStateChange`). The template owns the mapping
// + state + clearing on all platforms — only the typed-error subscription seam
// differs (inherent to Flutter's host-owned-player architecture).

/// Host-bindable error category for `LBPErrorScreen`. Mirrors the design's three
/// error visuals; the host picks copy / artwork per kind.
enum LBPlayerErrorKind {
  /// Stream / playback failure — also the GENERIC bucket for any [LBError] not
  /// otherwise mapped (network / restricted / invalidSignature / …).
  stream,

  /// `LBErrorVideoNotFound` — the video does not exist / was removed.
  notFound,

  /// `LBErrorSdkVersionUnsupported` — this SDK build is no longer accepted (426).
  outdated,
}

/// Error lifecycle phase. Only [failed] (terminal) is in scope — `retrying` is
/// NOT exposed by core (retries stay `buffering`), deferred to a follow-up core
/// change (see proposal Follow-up).
enum LBPlayerErrorPhase { failed }

/// One host-bindable error snapshot. null when the player is not in `error`.
@immutable
class LBPlayerErrorState {
  final LBPlayerErrorKind kind;
  final LBPlayerErrorPhase phase;

  const LBPlayerErrorState({required this.kind, required this.phase});

  @override
  bool operator ==(Object other) =>
      other is LBPlayerErrorState && other.kind == kind && other.phase == phase;

  @override
  int get hashCode => Object.hash(kind, phase);
}

/// Player error-state view-model. Implements [ChangeNotifier] so the host binds
/// with `ListenableBuilder` and re-reads [current] on change (parity with
/// [DefaultActivityFeed]). A coalesced notification fires EXACTLY ONCE per
/// single change (record / leave-error clear / explicit clear).
class DefaultErrorState extends ChangeNotifier {
  LBPlayerErrorState? _current;

  /// Current error snapshot, or null when the player is not in `error`.
  LBPlayerErrorState? get current => _current;

  /// Record a terminal player error (host wires `LivebuyPlayer.onError`). Always
  /// `phase = failed`; `kind` per the mapping table.
  void recordError(LBError error) {
    _current =
        LBPlayerErrorState(kind: kindFor(error), phase: LBPlayerErrorPhase.failed);
    notifyListeners();
  }

  /// React to a player state change (canonical name). When an error is shown and
  /// the player LEAVES `error` (host re-loaded → core transitions out of error),
  /// clear it and notify so the host dismisses `LBPErrorScreen`. No-op while not
  /// in error / still in error.
  void handleStateChange(String canonicalName) {
    if (_current == null || canonicalName == 'error') return;
    _current = null;
    notifyListeners();
  }

  /// Explicit reset (e.g. video reload). Fires one notification iff it cleared.
  void clear() {
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }

  /// Pure mapping [LBError] → [LBPlayerErrorKind] (design Decision 3 / spec
  /// table). `signatureExpired` was removed from core in the backend-contract
  /// fix batch; anything not listed falls back to [LBPlayerErrorKind.stream].
  static LBPlayerErrorKind kindFor(LBError error) {
    if (error is LBErrorVideoNotFound) return LBPlayerErrorKind.notFound;
    if (error is LBErrorSdkVersionUnsupported) return LBPlayerErrorKind.outdated;
    // LBErrorNetwork / LBErrorRestricted / LBErrorInvalidSignature / others.
    return LBPlayerErrorKind.stream;
  }
}
