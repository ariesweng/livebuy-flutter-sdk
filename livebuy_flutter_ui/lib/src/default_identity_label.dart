import 'package:flutter/foundation.dart';

// auth-gate-template-state — Default template identity-label view-model
// (behaviour / view-model layer; NO pixels).
//
// Spec ref: ui-template-foundation/spec.md
//   § "Default Template Identity-Label 狀態暴露".
// Design: design.md Decision 3.
//
// core stays headless: it owns `setUser` / `clearUser` and the
// `AUTH_STATE_CHANGED` notification. This model maps that event into a
// host-bindable `{ displayName, isLoggedIn }` for `PlayerHeader` / `ChatView`.
// The template renders NOTHING and MUST NOT seed from configure identity — the
// SINGLE source of truth is `AUTH_STATE_CHANGED` (initial [current] is null).
// `resumed_action` is intentionally NEVER read / stored (replay is host's job).

/// One host-bindable identity-label snapshot. null until the first
/// `AUTH_STATE_CHANGED` (template MUST NOT seed from configure identity).
@immutable
class LBIdentityLabel {
  final String displayName;
  final bool isLoggedIn;

  const LBIdentityLabel({required this.displayName, required this.isLoggedIn});

  @override
  bool operator ==(Object other) =>
      other is LBIdentityLabel &&
      other.displayName == displayName &&
      other.isLoggedIn == isLoggedIn;

  @override
  int get hashCode => Object.hash(displayName, isLoggedIn);
}

/// Identity-label view-model. Implements [ChangeNotifier] so the host binds with
/// `ListenableBuilder` and re-reads [current] on change. Diff-then-notify
/// (skips the notification when the mapped value is unchanged) for parity with
/// the moment view-models.
class DefaultIdentityLabel extends ChangeNotifier {
  LBIdentityLabel? _current;

  /// Current identity label, or null before the first `AUTH_STATE_CHANGED`.
  LBIdentityLabel? get current => _current;

  /// Map one `AUTH_STATE_CHANGED` (snake_case wire `state` / `display_name`):
  /// `logged_in` → `{ displayName, isLoggedIn: true }`; `logged_out` →
  /// `{ displayName (fallback ''), isLoggedIn: false }`; any other state →
  /// `isLoggedIn = false`. Fires one notification iff the value changed.
  void update(String? state, String? displayName) {
    final next = LBIdentityLabel(
      displayName: displayName ?? '',
      isLoggedIn: state == 'logged_in',
    );
    if (next == _current) return; // diff-then-notify (skip when unchanged).
    _current = next;
    notifyListeners();
  }
}
