import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show
        DefaultPlayerTemplate,
        LBAuthGateState,
        LBIdentityLabel,
        LBAuthTriggerAction;

// GapSurfacesModel — family-6 gap-surfaces read-only snapshot bridge (Flutter).
//
// Spec: `reference-ui-rendering/spec.md` (family-6 gap-surfaces, 2 ADDED modals).
// Flutter sibling of iOS `GapSurfacesModel.swift` (rb-ios-gap-surfaces) and Android
// `GapSurfacesModel.kt` (rb-android-gap-surfaces).
//
// It bridges the headless template gap-surface view-models exposed by
// `DefaultPlayerTemplate` (obtained at runtime by the host; tests take
// `LivebuyUI.attachedTemplateForTesting`) into a read-only snapshot the two
// family-6 Flutter modal surface widgets read. It is a pure read-only MIRROR —
// IDENTICAL pattern to family-1 `PlayerShellModel` / family-2 `FeedWinModel` /
// family-3 `ProductSheetsModel` / family-4 `MomentsModel`:
//
//   - It owns NO second copy of authoritative state. Every getter reads the
//     template's own public getter each call (`authGate.current` /
//     `identityLabel.current`), so there is nothing to drift from the template.
//   - It adds NO pixels and adds NO accessor / view-model to `livebuy_flutter_ui`
//     (that would be a template-layer concern, out of scope here).
//
// ── CRITICAL: NO mutating forwarders (like family-4) ─────────────────────────────
//   The two gap-surface actions — login (host → `LivebuySDK.login`) / dismiss
//   (host → `authGate.clear()` via `clearAuthGate()`) / submit-name
//   (host → `LivebuySDK.setUser`) / request-name-edit (core exit
//   `template.requestGuestNameEdit()` emitting `GUEST_NAME_EDIT_REQUEST`) — are NOT
//   model methods. login / dismiss / submit are HOST-WIRED CONTAINER closures (like
//   family-2's event-join / family-3's product-tap / family-4's moment exits), and
//   request-name-edit is a CORE EXIT the CONTAINER funnels to directly. So this
//   model is a PURE read-only snapshot; it carries NO mutating methods. The
//   container (`GapSurfacesOverlayView`) holds the host-wired exits (`onLogin` /
//   `onDismiss` / `onSubmitName`) and the single core exit
//   (`template.requestGuestNameEdit()`). Do NOT invent template forwarders for
//   login / dismiss / submit — none belong on this model (mirrors iOS / Android
//   `GapSurfacesModel`, also pure reads).
//
// ── FLUTTER vs Android scope NOTE (this change is PURELY ADDITIVE) ────────────────
//   Android family-6 needed 2 ADDED + 2 MODIFIED because Android family-1/3 were
//   built BEFORE the 2026-06-06 design reconcile. The Flutter family-1
//   (`video_info_panel.dart` 公告 notice-tab two-segment) and family-3
//   (`product_detail_sheet.dart` 收藏鈕) were built AFTER the reconcile and ALREADY
//   carry those surfaces. So the Flutter gap-surfaces change is PURELY ADDITIVE —
//   ONLY the 2 NEW modals (auth-gate + guest-name-edit); ZERO MODIFIED. This model
//   touches NEITHER the family-1 公告 NOR the family-3 收藏 view-models.
//
// ── FLUTTER vs iOS / Android deltas ──────────────────────────────────────────────
//   • auth-gate is read via `template.authGate.current: LBAuthGateState?`
//     ({ triggerAction: LBAuthTriggerAction (cartAdd / commentSend / couponClaim /
//     other), productId?, videoId? }) — iOS `authGate.current`, Android
//     `authGateState.current`.
//   • identity is read via `template.identityLabel.current: LBIdentityLabel?`
//     ({ displayName, isLoggedIn }). `isLoggedIn` is surfaced as a convenience
//     getter so the container can gate the auth-gate modal (shown only while NOT
//     logged in) without re-reaching into the template.
//
// Flutter observes via ChangeNotifier; the container [GapSurfacesOverlayView] binds
// the two sub view-models (`authGate` / `identityLabel`, each a `ChangeNotifier`)
// with `ListenableBuilder` and RE-READS these getters on each notify — so this
// holder keeps NO Flutter state of its own (no `extends ChangeNotifier`); it just
// centralizes the read mapping + deterministic demo seeds. Mirrors the iOS / Android
// `GapSurfacesModel` intent.
//
// No Flutter-framework dependency here — pure reads + plain-literal demo seeds, so
// it stays unit-testable (see `docs/unit-test-discipline.md`).

/// Read-only snapshot bridge for the family-6 gap-surface modals. Wraps a live
/// [DefaultPlayerTemplate]; every accessor reads the template's public getter each
/// call (no stored mirror). For demos / previews / golden tests, construct with
/// `template: null` — the getters then return the deterministic at-attach defaults
/// (matching a freshly-constructed template: no auth-gate / no identity label);
/// the surfaces' richer fixtures are passed by value from [GapSurfacesSeeds].
class GapSurfacesModel {
  /// The bound template, or `null` for demo / golden instances.
  final DefaultPlayerTemplate? template;

  /// Bridge a live template (host-supplied) — or `null` for the deterministic demo
  /// seeds (previews / golden / widget tests).
  const GapSurfacesModel({this.template});

  // -- Surface 1: AuthGateModalView ← 「請先登入」snapshot -----------------------

  /// Auth-gate「請先登入」snapshot (`DefaultPlayerTemplate.authGate.current`);
  /// non-null ONLY after an un-intercepted `AUTH_REQUIRED` (cleared on login or
  /// host-dismiss). `{ triggerAction, productId?, videoId? }`. The container shows
  /// the auth-gate modal ONLY while this is non-null AND NOT logged in. Demo
  /// default `null`.
  LBAuthGateState? get authGate => template?.authGate.current;

  // -- Surface 2: GuestNameEditModalView ← identity label ----------------------

  /// Identity-label snapshot (`DefaultPlayerTemplate.identityLabel.current`);
  /// `null` before the first `AUTH_STATE_CHANGED`. `{ displayName, isLoggedIn }`.
  /// The guest-name-edit modal seeds its field from `displayName`. Demo default
  /// `null`.
  LBIdentityLabel? get identity => template?.identityLabel.current;

  /// Convenience: whether the user is logged in (`identity?.isLoggedIn`, default
  /// `false`). Gates the auth-gate modal (shown only while NOT logged in) without
  /// the container re-reaching into the template. Demo default `false`.
  bool get isLoggedIn => template?.identityLabel.current?.isLoggedIn ?? false;
}

// MARK: - Deterministic demo seeds (previews / golden / widget tests)

/// Plain-literal deterministic seeds for the family-6 surfaces' previews + the
/// per-surface golden / widget tests. Constructed via the public template value
/// types (`LBAuthGateState` / `LBIdentityLabel`) so a snapshot does NOT depend on a
/// live player. Mirrors the iOS demo seeds (the memberwise `GapSurfacesModel` demo
/// init values) and the Android `GapSurfacesSeeds`.
///
/// The golden baselines each drive ONE modal from these seeds:
///   • [cartAddGate] — the auth-gate modal baseline (`auth-gate-modal-cart-add`,
///     triggered by a gated 加入購物車 → 「請先登入」).
///   • [guestIdentity] — the guest-name-edit modal baseline
///     (`guest-name-edit-modal`, seeded from a guest display name).
class GapSurfacesSeeds {
  GapSurfacesSeeds._();

  // -- Surface 1: auth-gate「請先登入」--------------------------------------------

  /// A deterministic auth-gate fixture raised by a gated add-to-cart
  /// (`triggerAction == cartAdd`; no productId / videoId). Drives the
  /// `auth-gate-modal-cart-add` baseline.
  static const LBAuthGateState cartAddGate =
      LBAuthGateState(triggerAction: LBAuthTriggerAction.cartAdd);

  // -- Surface 2: guest identity label -----------------------------------------

  /// A deterministic guest identity fixture (`Guest_4F2A`, not logged in). Drives
  /// the `guest-name-edit-modal` baseline (the field seeds from `displayName`).
  static const LBIdentityLabel guestIdentity =
      LBIdentityLabel(displayName: 'Guest_4F2A', isLoggedIn: false);
}
