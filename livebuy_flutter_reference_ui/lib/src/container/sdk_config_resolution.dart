// sdk_config_resolution — how the Tier B containers obtain the SDKConfig
// (rb-flutter-container-sdk-config-retry, mirrors RN `container/sdkConfigResolution.ts`).
//
// A container mounted BEFORE the host's `LivebuySDK.configure()` has completed asks for the
// SDKConfig too early: `getSdkConfig()` throws (`NOT_CONFIGURED`). The containers used to ask
// exactly once and fall back to `SDKConfig.fallback` for the rest of their life — so a
// `LivebuyWidget` mounted by a host that calls `configure()` without awaiting it before `runApp`
// stayed blank until its first periodic refresh tick (forever with `listRefreshInterval: zero`),
// and the theme of every container stayed on the minimal fallback (issue
// ariesweng/livebuy-flutter-sdk#3).
//
// The lookup now retries on failure, on the SAME bounded schedule as RN, until it resolves or
// the container is disposed. An explicit `config.sdkConfig` still wins and issues no lookup.

import 'dart:async' show Timer;

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:livebuy_flutter/livebuy_flutter.dart' show LivebuySDK, SDKConfig;

/// Delay (ms) before retry #0, #1, #2, #3; every later retry waits [kLbSdkConfigRetrySteadyMs].
const List<int> kLbSdkConfigRetryRampMs = <int>[100, 200, 400, 800];

/// Delay (ms) between retries once the ramp is exhausted.
const int kLbSdkConfigRetrySteadyMs = 1000;

/// Retries issued after the first failed lookup before giving up (≈ 31.5 s in total).
const int kLbSdkConfigMaxRetries = 34;

/// PURE: the wait (ms) before retry number [attempt] (0-based, counted after the first failed
/// lookup), or `null` when no further retry should be issued. Takes `num` so a non-integral or
/// negative attempt (a caller bug) yields `null` instead of an out-of-range index; an integral
/// double (`2.0`) counts as its integer, like RN's `Number.isInteger`.
int? lbSdkConfigRetryDelayMs(num attempt) {
  if (attempt.isNaN || attempt.isInfinite || attempt != attempt.truncate()) return null;
  final n = attempt.toInt();
  if (n < 0 || n >= kLbSdkConfigMaxRetries) return null;
  return n < kLbSdkConfigRetryRampMs.length ? kLbSdkConfigRetryRampMs[n] : kLbSdkConfigRetrySteadyMs;
}

/// Schedules [run] after [delayMs]; returns a handle for [SdkConfigRetryCancel].
typedef SdkConfigRetrySchedule = Object Function(void Function() run, int delayMs);

/// Cancels a handle returned by [SdkConfigRetrySchedule].
typedef SdkConfigRetryCancel = void Function(Object handle);

/// Ask for the SDKConfig; on failure retry per [lbSdkConfigRetryDelayMs]. Calls [onResolved] at
/// most once. When every retry failed, calls [onGaveUp] (optional, at most once — RN has the same
/// hook since rb-rn-container-sdk-config-gave-up-fallback). Returns a cancel function: after it runs nothing further is
/// scheduled and a lookup still in flight is ignored.
VoidCallback resolveSdkConfigWithRetry({
  required Future<SDKConfig> Function() getSdkConfig,
  required SdkConfigRetrySchedule schedule,
  required SdkConfigRetryCancel cancelSchedule,
  required void Function(SDKConfig config) onResolved,
  VoidCallback? onGaveUp,
}) {
  final loop = _SdkConfigRetryLoop(getSdkConfig, schedule, cancelSchedule, onResolved, onGaveUp);
  loop.attempt(0);
  return loop.cancel;
}

class _SdkConfigRetryLoop {
  _SdkConfigRetryLoop(
      this._get, this._schedule, this._cancelSchedule, this._onResolved, this._onGaveUp);

  final Future<SDKConfig> Function() _get;
  final SdkConfigRetrySchedule _schedule;
  final SdkConfigRetryCancel _cancelSchedule;
  final void Function(SDKConfig config) _onResolved;
  final VoidCallback? _onGaveUp;
  bool _cancelled = false;
  Object? _pending;

  void attempt(int retriesIssued) {
    Future<SDKConfig>.sync(_get).then((config) {
      if (!_cancelled) _onResolved(config);
    }, onError: (Object _) => _onFailure(retriesIssued));
  }

  void _onFailure(int retriesIssued) {
    if (_cancelled) return;
    final delay = lbSdkConfigRetryDelayMs(retriesIssued);
    if (delay == null) {
      _onGaveUp?.call();
      return;
    }
    _pending = _schedule(() {
      _pending = null;
      if (!_cancelled) attempt(retriesIssued + 1);
    }, delay);
  }

  void cancel() {
    _cancelled = true;
    final pending = _pending;
    if (pending != null) _cancelSchedule(pending);
    _pending = null;
  }
}

/// The container-facing entry point. [explicit] non-null (the host supplied `config.sdkConfig`)
/// → [onResolved] is called synchronously with it and NO lookup is issued. Otherwise
/// `LivebuySDK.getSdkConfig()` is retried on a real [Timer] per [resolveSdkConfigWithRetry].
/// Call the returned function from `dispose()`.
VoidCallback startSdkConfigResolution({
  SDKConfig? explicit,
  required void Function(SDKConfig config) onResolved,
  VoidCallback? onGaveUp,
}) {
  if (explicit != null) {
    onResolved(explicit);
    return () {};
  }
  return resolveSdkConfigWithRetry(
    getSdkConfig: LivebuySDK.getSdkConfig,
    schedule: (run, delayMs) => Timer(Duration(milliseconds: delayMs), run),
    cancelSchedule: (handle) => (handle as Timer).cancel(),
    onResolved: onResolved,
    onGaveUp: onGaveUp,
  );
}
