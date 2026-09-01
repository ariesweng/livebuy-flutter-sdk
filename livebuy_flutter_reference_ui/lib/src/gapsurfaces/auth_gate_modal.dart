import 'package:flutter/material.dart';
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show LBAuthGateState, LBAuthTriggerAction;

import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';

// AuthGateModalView — family-6 gap-surfaces surface 1 (「請先登入」auth-gate modal).
//
// Spec: `reference-ui-rendering/spec.md` (family-6 gap-surfaces — the LAST Flutter
//        Phase-3 family; this surface is one of the 2 ADDED gap modals).
// Design: `design/templates/minimal/sdk-components.jsx` `LBPAuthGate` (1055) +
//          `LBP_AUTH_COPY` (1048) — a centered card over a black-0.55 scrim, 18pt
//          corner card, OVERHANGING accent lock badge, trigger-specific body, and a
//          VERTICAL two-button footer (`LBPButton` primary「前往登入」over plain
//          「稍後再說」).
// Parity: iOS `GapSurfaces/AuthGateModalView.swift` (rb-ios-gap-surfaces +
//          rb-ios-gap-surfaces-design-reconcile) and Android
//          `gapsurfaces/AuthGateModalView.kt` (rb-android-gap-surfaces) — mirrors the
//          structure / copy / tokens verbatim. Golden parity name: `auth-gate-modal`.
//
// The「請先登入」auth-gate modal for ONE pending un-intercepted `AUTH_REQUIRED`. It is
// the first of the TWO ADDED family-6 surface sub-views composed by
// `GapSurfacesOverlayView`, and it implements the agreed SUB-VIEW INPUT PATTERN
// documented verbatim in `gap_surfaces_view.dart`:
//
//   1. `theme:` (ReferenceUITheme, required)  — FIRST, always.
//   2. bound SNAPSHOT VALUE(S) (read-only, BY VALUE):
//        `gate: LBAuthGateState?`  — drives the body copy via `gate.triggerAction`;
//        `isLoggedIn: bool`        — read-only context.
//      Both passed BY VALUE from `GapSurfacesModel` (never the model, never the
//      template).
//   3. action callbacks (LAST, each defaulting to a no-op / null):
//        `onLogin`   (「前往登入」CTA → the HOST's own login flow wired by the
//                      container; reference-ui NEVER logs in itself), and
//        `onDismiss` (「稍後再說」/ scrim tap → host → `template.clearAuthGate()`).
//
// This sub-view reads ONLY its passed-in `gate` / `isLoggedIn`; it never reaches back
// into `GapSurfacesModel` / `DefaultPlayerTemplate` (one-way data flow), holds NO
// second copy of the auth-gate state, and renders correctly with all callbacks null
// (so demo / golden / widget tests construct it action-free).
//
// VISIBILITY (read-only guard — mirrors Android + the spec): `isLoggedIn == true`
// (or `gate == null`) → it draws NOTHING (`SizedBox.shrink()`). The container's
// priority predicate (auth-gate shown only `authGate != null && !isLoggedIn`) already
// encodes the same gate, so this is belt-and-braces / spec-literal — a logged-in user
// needs no login gate.
//
// RENDERING GOTCHAS (family-1..5 lessons, CRITICAL): plain `Stack` / `Column` only —
// NO scrollable container (`ListView` / `GridView` / `SingleChildScrollView`) and NO
// network image (`Image.network` / `NetworkImage`). The lock badge is a self-contained
// `Icons.lock_outline` on an accent circle (no Coil / AsyncImage equivalent). No
// animation / no randomness so the golden is byte-stable. It reuses the
// `product_detail_sheet.dart` `_selectVariantPrompt()` idiom (black-0.55 scrim,
// centered card radius 18, `theme.background`, accent primary button).
//
// TRIGGER COPY TABLE (verbatim from the design's `LBP_AUTH_COPY` + iOS / Android):
//   LBAuthTriggerAction.cartAdd     → 「登入後即可將商品加入購物車」
//   LBAuthTriggerAction.commentSend → 「登入後即可參與留言互動」
//   LBAuthTriggerAction.couponClaim → 「登入後即可領取優惠與獎品」
//   LBAuthTriggerAction.subscribe   → 「登入後即可訂閱直播主，第一時間掌握開播與專屬優惠」(rb-flutter-subscribe-login-gate)
//   LBAuthTriggerAction.other       → 「登入後即可使用完整功能」(forward-compat bucket)

// MARK: - Decorative design tokens (literal minimal hex via colorFromHex)
//
// accent / text / background come from the resolved [ReferenceUITheme]. These are
// FIXED decorative colors lifted verbatim from the design's `theme.surface.*` —
// design-literal, NOT theme-resolved. Kept byte-consistent with iOS / Android
// `AuthGateModalView` so the three platforms read as one family.

/// `theme.surface.textDim` (secondary / body reason text).
final Color _textDim = colorFromHex('#6B6775') ?? const Color(0xFF6B6775);

/// `theme.surface.strokeStrong` (plain-button outline —「稍後再說」border).
final Color _strokeStrong = colorFromHex('#D8D5DE') ?? const Color(0xFFD8D5DE);

// MARK: - Fixed localized copy (static presentation strings, 繁中 — parity verbatim)

const String _title = '請先登入';
const String _dismissLabel = '稍後再說';
const String _loginLabel = '前往登入';

// Trigger-specific body copy — verbatim from the design's `LBP_AUTH_COPY`.
const String _bodyCartAdd = '登入後即可將商品加入購物車';
const String _bodyCommentSend = '登入後即可參與留言互動';
const String _bodyCouponClaim = '登入後即可領取優惠與獎品';
// 訂閱情境（rb-flutter-subscribe-login-gate，parity iOS `bodySubscribe` / Android `BODY_SUBSCRIBE` /
// RN `BODY_SUBSCRIBE`）— 未登入點訂閱時顯示。
const String _bodySubscribe = '登入後即可訂閱直播主，第一時間掌握開播與專屬優惠';
const String _bodyOther = '登入後即可使用完整功能';

/// Optional-preserving login forward with a dismiss (dropin-hide-unwired-affordances-flutter,
/// parity iOS / Android / RN `lbForwardLogin`): a gate that wants「前往登入」to ALSO dismiss its own
/// local modal (LIVE 留言 login gate / cart-needs-login gate) must NOT wrap [onLogin] into an
/// eternally-non-null callback — that would defeat `AuthGateModalView`'s `onLogin != null` render
/// guard and leave the dead button. `null` in → `null` out (button stays hidden, dismiss still
/// reachable via「稍後再說」/ scrim); non-null in → a callback that dismisses FIRST then runs the host login.
VoidCallback? lbForwardLogin(VoidCallback? onLogin, VoidCallback dismiss) =>
    onLogin == null
        ? null
        : () {
            dismiss();
            onLogin();
          };

/// The family-6「請先登入」auth-gate modal for one pending `AUTH_REQUIRED`. Renders a
/// centered `LBPAuthGate` card (overhanging accent lock badge / title「請先登入」/
/// trigger-specific body / vertical two-button footer) over a black-0.55 scrim.
/// `gate.triggerAction` drives the body copy; `onLogin` / `onDismiss` are host-wired.
///
/// When `isLoggedIn == true` (or `gate == null`) it draws NOTHING — the gate is only
/// for a pending un-intercepted `AUTH_REQUIRED` on a guest. Renders correctly with the
/// default null actions (golden / preview safe).
class AuthGateModalView extends StatelessWidget {
  /// Resolved reference-ui theme (FIRST positional argument, always).
  final ReferenceUITheme theme;

  /// The pending auth-gate SNAPSHOT VALUE (`triggerAction` drives the body copy), or
  /// `null` when no gate is pending → draws nothing. Read-only, BY VALUE.
  final LBAuthGateState? gate;

  /// Whether the user is already logged in. When `true` the gate is suppressed
  /// (a logged-in user needs no login gate). Read-only convenience.
  final bool isLoggedIn;

  /// Host-wired「前往登入」CTA → host → `LivebuySDK.login(...)` (open the host's login
  /// flow). reference-ui NEVER logs in itself. `null` for demo / golden instances.
  final void Function()? onLogin;

  /// Host-wired「稍後再說」/ scrim tap → host → `template.clearAuthGate()`
  /// (≡ `authGate.clear()`). This layer NEVER clears the gate itself. `null` for
  /// demo / golden instances.
  final void Function()? onDismiss;

  const AuthGateModalView({
    super.key,
    required this.theme,
    required this.gate,
    this.isLoggedIn = false,
    this.onLogin,
    this.onDismiss,
  });

  // MARK: - Derived presentation (pure)

  /// Trigger-specific body copy (`LBAuthTriggerAction` → 繁中 reason line). `.other`
  /// is the forward-compatible bucket (a generic「使用完整功能」line).
  String _bodyCopy(LBAuthTriggerAction triggerAction) {
    switch (triggerAction) {
      case LBAuthTriggerAction.cartAdd:
        return _bodyCartAdd;
      case LBAuthTriggerAction.commentSend:
        return _bodyCommentSend;
      case LBAuthTriggerAction.couponClaim:
        return _bodyCouponClaim;
      case LBAuthTriggerAction.subscribe:
        return _bodySubscribe;
      case LBAuthTriggerAction.other:
        return _bodyOther;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Read-only visibility guard (spec): logged-in OR no pending gate → draw nothing.
    final pendingGate = gate;
    if (isLoggedIn || pendingGate == null) return const SizedBox.shrink();

    final bodyCopy = _bodyCopy(pendingGate.triggerAction);

    // Full-bleed dim scrim (LBPAuthGate backdrop). Tap = dismiss (mirrors the design's
    // `onClick={onDismiss}`). The centered card overhangs an accent lock badge.
    return GestureDetector(
      key: LbTestKeys.authGateScrim,
      behavior: HitTestBehavior.opaque,
      onTap: onDismiss,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.55),
        child: Center(
          // The card+badge sit in a Stack so the badge can overhang the card top
          // (design `top: -30`) while the GestureDetector below blocks the tap from
          // dismissing when the user taps INSIDE the card.
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {}, // absorb taps on the card (do NOT dismiss)
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                _card(bodyCopy),
                // Accent lock badge overhangs the card top (design `top: -30`).
                Positioned(top: -30, child: _lockBadge()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // MARK: - Centered alert card (LBPAuthGate — radius 18 over theme.background)
  //
  // padding `34 22 20` clears the overhanging lock badge at the top. maxWidth 320,
  // 18pt corner. Reuses the `_selectVariantPrompt()` idiom (radius 18, theme.background).

  Widget _card(String bodyCopy) {
    return Container(
      key: LbTestKeys.authGateModal,
      constraints: const BoxConstraints(maxWidth: 320),
      margin: const EdgeInsets.symmetric(horizontal: 36),
      padding: const EdgeInsets.fromLTRB(22, 34, 22, 20),
      decoration: BoxDecoration(
        color: theme.background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: theme.text,
              fontSize: 18 * theme.fontScale,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            bodyCopy,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _textDim,
              fontSize: 13 * theme.fontScale,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 22),
          _footer(),
        ],
      ),
    );
  }

  // MARK: - Overhanging accent lock badge (LBPAuthGate brand badge)
  //
  // accent-filled 60×60 circle + `theme.background` ring (4pt) + a white lock glyph
  // (`Icons.lock_outline`) + a soft accent glow halo. Reads instantly as "login
  // required" and keeps it on-brand. The glow mirrors the design badge
  // `boxShadow: '0 8px 20px ${accent}55'` (iOS `.shadow(accent 0.33, r10, y8)` /
  // Android deterministic radial). A `BoxShadow` does not shift layout (vs a wrapping
  // glow View), and renders deterministically in the golden here.

  Widget _lockBadge() {
    return Container(
      width: 60,
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: theme.accent,
        shape: BoxShape.circle,
        border: Border.all(color: theme.background, width: 4),
        boxShadow: [
          BoxShadow(
            // NOTE: `withOpacity` (pre-existing, HEAD baseline) is retained here on purpose — it is
            // NOT byte-identical to `withValues(alpha:)` for the lock-badge shadow, so switching would
            // break the `auth-gate-modal` golden.
            //
            // flutter-reference-ui-analyze-gate: the deprecation is now MARKED rather than merely
            // tolerated, so `flutter analyze` can be a HARD gate at the same strictness as the core
            // package. Swapping the API would mean re-recording that golden (a visual change, and a
            // reference-ui-layer decision) and possibly raising pubspec's `flutter: ">=3.10.0"`;
            // neither belongs in a CI-coverage change. The ignore is deliberately SINGLE-LINE and
            // named: any NEW deprecation elsewhere in this package still turns the gate red.
            // ignore: deprecated_member_use
            color: theme.accent.withOpacity(0.33),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Icon(Icons.lock_outline, size: 26, color: Colors.white),
    );
  }

  // MARK: - Vertical two-button footer (LBPButton primary over plain)
  //
  // Primary「前往登入」(accent fill, white fg) → onLogin, on TOP. Plain「稍後再說」
  // (transparent fill, strokeStrong 1pt border, theme.text) → onDismiss, BELOW. Full
  // width, 12pt corner, 13pt vertical padding, gap 10 (design `column`).

  Widget _footer() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Primary「前往登入」(LBPButton primary). Rendered ONLY when host-wired (`onLogin != null`) —
        // an un-wired login CTA is a dead button (reference-ui NEVER logs in itself;
        // dropin-hide-unwired-affordances-flutter). null → footer degrades to「稍後再說」only
        // (the 10-gap below is part of the conditional).
        if (onLogin != null) ...[
          GestureDetector(
            key: LbTestKeys.authGateLogin,
            behavior: HitTestBehavior.opaque,
            onTap: onLogin,
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.accent,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 13),
              child: Text(
                _loginLabel,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15 * theme.fontScale,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        // Plain「稍後再說」(LBPButton plain).
        GestureDetector(
          key: LbTestKeys.authGateLater,
          behavior: HitTestBehavior.opaque,
          onTap: onDismiss,
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _strokeStrong, width: 1),
            ),
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Text(
              _dismissLabel,
              style: TextStyle(
                color: theme.text,
                fontSize: 15 * theme.fontScale,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

