// player_error_feed — which core per-view errors reach the template's error state
// (rb-flutter-dropin-player-error-wiring; mirrors RN `container/playerErrorFeed.ts`).
//
// `DefaultPlayerTemplate.handleError` is host-fed: the container that owns `LivebuyPlayerCore`
// must call it. The drop-in `LivebuyPlayer` never did, so a video that could not load left a black
// screen. The core's per-view `onError` also carries chat / cart business errors while the video
// keeps playing, and `handleError` raises the error screen for any error, so the feed filters:
//
// - chat / cart business errors are never forwarded;
// - errors meaning "this video cannot be played at all" are forwarded immediately;
// - any other error is forwarded only while the player is in `error` — one that arrives before the
//   state change is held and forwarded when the player enters `error`; entering `error` with nothing
//   held forwards a network error. Leaving `error` drops what was held.

import 'package:livebuy_flutter/livebuy_flutter.dart'
    show
        LBError,
        LBErrorCartAddDeduplicated,
        LBErrorChatRateLimited,
        LBErrorChatRequiresLogin,
        LBErrorGuestNameTaken,
        LBErrorInvalidSignature,
        LBErrorNetwork,
        LBErrorNotLive,
        LBErrorRestricted,
        LBErrorSdkVersionUnsupported,
        LBErrorVideoNotFound,
        LBPlayerState;

/// Fed when the player enters `error` without a usable error on record.
const LBError playerErrorFallback = LBErrorNetwork('Playback failed');

/// PURE: `true` for an error that must never raise the player error screen.
bool isNonPlaybackError(LBError error) =>
    error is LBErrorChatRateLimited ||
    error is LBErrorGuestNameTaken ||
    error is LBErrorChatRequiresLogin ||
    error is LBErrorNotLive ||
    error is LBErrorCartAddDeduplicated;

/// PURE: `true` for an error that is terminal for the load regardless of player state.
bool isLoadTerminalError(LBError error) =>
    error is LBErrorVideoNotFound ||
    error is LBErrorSdkVersionUnsupported ||
    error is LBErrorRestricted ||
    error is LBErrorInvalidSignature;

/// Stateful filter between the core's `onError` / `onStateChange` and `handleError`.
class PlayerErrorFeed {
  PlayerErrorFeed(this._handleError);

  final void Function(LBError error) _handleError;
  bool _inError = false;
  LBError? _latest;

  /// The core's per-view error callback.
  void onError(LBError error) {
    if (isNonPlaybackError(error)) return;
    _latest = error;
    if (_inError || isLoadTerminalError(error)) _handleError(error);
  }

  /// The core's player-state callback.
  void onStateChange(LBPlayerState state) {
    final entering = state == LBPlayerState.error && !_inError;
    _inError = state == LBPlayerState.error;
    if (entering) _handleError(_latest ?? playerErrorFallback);
    if (!_inError) _latest = null;
  }
}
