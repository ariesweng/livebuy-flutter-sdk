import 'package:flutter/foundation.dart';

// auth-gate-template-state — Default template auth-gate view-model
// (behaviour / view-model layer; NO pixels).
//
// Spec ref: ui-template-foundation/spec.md
//   § "Default Template Auth-Gate 狀態暴露".
// Design: design.md Decision 1 (route B aux/unified listener) / Decision 2
//   (single latest value + host-takeover exclude).
//
// core stays headless: it owns `AUTH_REQUIRED` (sync_interceptor), the
// `PendingAuthStore` write, the 30s replay timer and any default「請先登入」
// fallback. This model maps an un-intercepted `AUTH_REQUIRED` into a
// host-bindable `{ triggerAction, productId?, videoId? }` so the host can draw
// its own login prompt. The template renders NOTHING.
//
// Flutter wiring note (design D2): the Flutter UI subscribes through the SINGLE
// unified bridge listener (`LivebuySDK.setListener`), so the template's listener
// IS the unified listener — it cannot observe what a separate host PRIMARY
// listener returned. Therefore host-takeover exclusion reuses the EXISTING
// host-set-flag precedent (`DefaultActivityFeed.hostOwnsActivity`): the host
// that installs its own primary `AUTH_REQUIRED` handling sets [hostOwnsAuthGate]
// and the template re-implements NO interception judgement.

/// Which gated action raised `AUTH_REQUIRED`. Unknown / future strings map to
/// [other] for forward-compatibility (the mapper never throws).
enum LBAuthTriggerAction { cartAdd, commentSend, couponClaim, subscribe, other }

/// Pure mapper `params.trigger_action` (snake_case wire) → [LBAuthTriggerAction].
/// `cart_add` → cartAdd, `comment_send` → commentSend, `coupon_claim` →
/// couponClaim, `subscribe` → subscribe (subscribe-auth-gate-trigger-action,
/// parity iOS `.subscribe` / Android `SUBSCRIBE` / RN `Subscribe`); anything else
/// (incl. null / empty) → [LBAuthTriggerAction.other] (forward-compat bucket).
LBAuthTriggerAction triggerActionFromWire(String? wire) {
  switch (wire) {
    case 'cart_add':
      return LBAuthTriggerAction.cartAdd;
    case 'comment_send':
      return LBAuthTriggerAction.commentSend;
    case 'coupon_claim':
      return LBAuthTriggerAction.couponClaim;
    case 'subscribe':
      return LBAuthTriggerAction.subscribe;
    default:
      return LBAuthTriggerAction.other;
  }
}

/// One host-bindable「請先登入」snapshot. null when no un-intercepted
/// `AUTH_REQUIRED` has been seen (or after login / host-dismiss clear).
@immutable
class LBAuthGateState {
  final LBAuthTriggerAction triggerAction;
  final String? productId;
  final String? videoId;

  const LBAuthGateState({
    required this.triggerAction,
    this.productId,
    this.videoId,
  });

  @override
  bool operator ==(Object other) =>
      other is LBAuthGateState &&
      other.triggerAction == triggerAction &&
      other.productId == productId &&
      other.videoId == videoId;

  @override
  int get hashCode => Object.hash(triggerAction, productId, videoId);
}

/// Auth-gate view-model. Implements [ChangeNotifier] so the host binds with
/// `ListenableBuilder` and re-reads [current] on change (parity with
/// [DefaultErrorState]). A coalesced notification fires EXACTLY ONCE per single
/// change (record / login-clear / host-dismiss clear).
class DefaultAuthGate extends ChangeNotifier {
  /// Set by the host when it installs its own primary `AUTH_REQUIRED` handling
  /// and takes over the login prompt. While true [recordRequired] is EXCLUDED
  /// (no state, no notify) — exact parity with `DefaultActivityFeed.hostOwnsActivity`.
  bool hostOwnsAuthGate;

  LBAuthGateState? _current;

  DefaultAuthGate({this.hostOwnsAuthGate = false});

  /// Current「請先登入」snapshot, or null when no prompt is needed.
  LBAuthGateState? get current => _current;

  /// Record an un-intercepted `AUTH_REQUIRED` (snake_case wire params). Excluded
  /// (no state, no notify) when the host owns the auth gate. The state is the
  /// SINGLE latest value — a new event OVERWRITES the previous one (not a queue).
  void recordRequired(Map<String, Object?> params) {
    if (hostOwnsAuthGate) return; // host took over — exclude.
    _current = LBAuthGateState(
      triggerAction: triggerActionFromWire(params['trigger_action'] as String?),
      productId: params['product_id'] as String?,
      videoId: params['video_id'] as String?,
    );
    notifyListeners();
  }

  /// Login succeeded (`AUTH_STATE_CHANGED.state == "logged_in"`) → clear the
  /// prompt. Fires one notification iff it cleared something.
  void clearOnLogin() {
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }

  /// Host-dismiss clear (symmetric with [DefaultErrorState.clear]). Fires one
  /// notification iff it cleared something.
  void clear() {
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }
}
