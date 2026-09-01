import 'package:flutter/widgets.dart';
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show DefaultPlayerTemplate, LBAuthGateState;

import '../reference_ui_theme.dart';
import '../container/chat_composer_bar.dart'
    show NicknamePromptController, LoginPromptController;
import 'gap_surfaces_model.dart';
// Surface widgets — landed by the parallel Surfaces agents. The container fixes the
// call-site shapes; the file names match the imports EXACTLY (no shim files). Per
// the family file-naming discipline: auth_gate_modal.dart (AuthGateModalView) /
// guest_name_edit_modal.dart (GuestNameEditModalView).
import 'auth_gate_modal.dart';
import 'guest_name_edit_modal.dart';

// Re-export the two gap-surface modal widgets so they are publicly reachable through
// the package barrel (`AuthGateModalView` / `GuestNameEditModalView`), parity with
// the family-1..5 surface export requirement.
export 'auth_gate_modal.dart';
export 'guest_name_edit_modal.dart';

// GapSurfacesOverlayView — family-6 gap-surface modal container (Flutter SKELETON).
//
// Spec: `reference-ui-rendering/spec.md` (family-6 gap-surfaces, 2 ADDED modals).
// Flutter sibling of iOS `GapSurfacesOverlayView.swift` (rb-ios-gap-surfaces) and
// Android `GapSurfacesOverlayView.kt` (rb-android-gap-surfaces).
//
// The top-level family-6 container. It conditionally shows the single ACTIVE
// gap-surface modal over the player area — at most ONE modal on screen:
//
//   1. AuthGateModalView       — 「請先登入」gate (`LBAuthGateState`)
//   2. GuestNameEditModalView  — guest display-name edit (`LBIdentityLabel`)
//
// ─────────────────────────────────────────────────────────────────────────────
// FLUTTER vs Android SCOPE — this change is PURELY ADDITIVE (2 ADDED, 0 MODIFIED)
// ─────────────────────────────────────────────────────────────────────────────
// iOS family-6 was reconciled to: auth-gate modal + guest-name-edit modal, PLUS
// folding 公告 into family-1 `VideoInfoPanel` and 收藏鈕 into family-3
// `ProductDetailSheet`. Android gap-surfaces needed 2 ADDED + 2 MODIFIED because
// Android family-1/3 were built BEFORE the reconcile. The Flutter family-1
// (`playershell/video_info_panel.dart` 公告 notice-tab two-segment) and family-3
// (`productsheets/product_detail_sheet.dart` 收藏鈕) were built AFTER the reconcile
// and ALREADY carry those surfaces. So the Flutter gap-surfaces change is PURELY
// ADDITIVE — ONLY the 2 NEW modals here; ZERO MODIFIED. This container touches
// NEITHER `video_info_panel.dart` NOR `product_detail_sheet.dart`.
//
// ─────────────────────────────────────────────────────────────────────────────
// MODAL PRIORITY (mutually exclusive — at most ONE modal is shown)
// ─────────────────────────────────────────────────────────────────────────────
//   1. authGate != null && !isLoggedIn        → AuthGateModalView   (HIGHEST)
//   2. else _showNameEdit                      → GuestNameEditModalView
//   3. else                                    → nothing (`SizedBox.shrink()`)
//
// The auth-gate modal wins: an un-intercepted `AUTH_REQUIRED` is a blocking
// 「請先登入」prompt, so it pre-empts the (host-triggered) guest-name editor. Once
// the user logs in (`isLoggedIn` flips true), the auth-gate state clears (core
// clears it on `AUTH_STATE_CHANGED.logged_in`) and the gate falls away.
//
// ─────────────────────────────────────────────────────────────────────────────
// HOST-WIRED ACTION CALLBACKS + the ONE core exit (Model is PURE read-only)
// ─────────────────────────────────────────────────────────────────────────────
// login / dismiss / submit-name are HOST-WIRED CONTAINER callbacks — EXACTLY like
// family-2's event-join / family-3's product-tap / family-4's moment exits (the
// actual login / setUser / clear is the host's / core's job, not this layer's). The
// host wires them to the core exits it owns:
//   • onLogin      → host → `LivebuySDK.login(...)` (open the host's login flow)
//   • onDismiss    → host → `template.clearAuthGate()` (≡ `authGate.clear()`); auth-gate ONLY.
//                    The guest-name editor's own scrim closes via `nicknameController.dismiss()`
//                    (SEPARATE — does NOT clear the gate).
//   • onSubmitName → the turnkey container's gap seam (→
//                    `LivebuyPlayerController.setGuestNicknameVerified`, NEVER `setUser`; 設名 ≠
//                    登入), or a host override. Returns the host's `Future<String?>` UNCHANGED
//                    (rb-flutter-nickname-taken-inline-error): `null` = accepted (the host closes
//                    this modal separately), non-null = a user-facing error message the modal
//                    shows inline, staying open for retry.
//
// The ONLY core exit this container funnels DIRECTLY is the rename ENTRY:
// `_handleRequestNameEdit()` calls `template?.requestGuestNameEdit()` — the headless
// core exit that emits `GUEST_NAME_EDIT_REQUEST` (a safe no-op if the host wired no
// requester). That is a fire-and-forget INTENT, not a state mutation; the container
// owns NO core action beyond it (it MUST NOT call `LivebuySDK.login` / `setUser` /
// `clearAuthGate` itself — those flow through the host callbacks). The
// [GapSurfacesModel] carries NO mutating forwarder (mirrors iOS / Android
// `GapSurfacesModel`, both pure read-only snapshots).
//
// Every callback is null-defaulted, so the container renders correctly action-free
// (demo / golden / widget tests construct it without host wiring); a null callback
// means the corresponding CTA is inert.
//
// ─────────────────────────────────────────────────────────────────────────────
// SUB-VIEW INPUT PATTERN — the contract the 2 Surfaces agents MUST follow
// ─────────────────────────────────────────────────────────────────────────────
// Every family-6 modal surface widget is a `class … extends StatelessWidget` whose
// constructor takes, IN THIS ORDER (named params — identical convention to
// family-1 / family-2 / family-3 / family-4):
//
//   1. `theme:` (ReferenceUITheme, required)  — FIRST, always.
//   2. its bound SNAPSHOT VALUE(S)            — read-only state, passed BY VALUE from
//                                                GapSurfacesModel (never the model,
//                                                never the template).
//   3. optional action callbacks             — trailing, EACH defaulting to a
//                                                no-op / null. The container owns NO
//                                                host action; the host wires them.
//
// A surface widget reads ONLY its passed-in values — it MUST NOT reach back into
// GapSurfacesModel or DefaultPlayerTemplate (one-way data flow), MUST NOT hold a
// second copy of the auth-gate / identity state, MUST render correctly with all
// callbacks null / omitted (so golden / widget tests construct it action-free), and
// MUST NOT use any scrollable container (`ListView` / `GridView` /
// `SingleChildScrollView`) or network image (`Image.network` / `NetworkImage`). Both
// modals are LBPAlertModal-style centered cards on a black 0.55 scrim (reuse the
// `product_detail_sheet.dart` `_selectVariantPrompt()` idiom: radius 18,
// theme.background).
//
// The two Surfaces agents implement EXACTLY these constructors (see the call sites
// in `build` below):
//
//   AuthGateModalView({
//       required ReferenceUITheme theme,
//       required LBAuthGateState gate,           // non-null (container gates on non-null)
//       bool isLoggedIn = false,                 // read-only convenience (modal shown only !isLoggedIn)
//       void Function()? onLogin,                // 前往登入 → host (LivebuySDK.login)
//       void Function()? onDismiss })            // 稍後再說 / scrim → host (clearAuthGate)
//
//     依 `gate.triggerAction` 切換人話文案 (NO raw code): `cartAdd`「登入後即可將商品
//     加入購物車」/ `commentSend`「登入後即可參與留言互動」/ `couponClaim`「登入後即可
//     領取優惠與獎品」/ `other`「登入後即可使用完整功能」. A centered LBPAlertModal card
//     (title「請先登入」, 前往登入 onLogin + 稍後再說 onDismiss). reference-ui NEVER logs
//     in itself — it only FORWARDS onLogin.
//
//   GuestNameEditModalView({
//       required ReferenceUITheme theme,
//       required String displayName,             // current name (seeds the field)
//       bool editable = false,                   // golden/demo MUST pass false → static placeholder Text
//       Future<String?> Function(String name)? onSubmit,  // 送出 → host (setGuestNicknameVerified)
//       void Function()? onDismiss })            // scrim / close → host (close)
//
//     A centered LBPAlertModal card titled 「設定暱稱」+ subtitle「請輸入直播留言的暱稱」
//     with the current `displayName` seeded into the field + a 送出 primary (onSubmit,
//     enabled only while the trimmed buffer is 1..10 chars); scrim / close → onDismiss.
//     CRITICAL golden lesson (from iOS family-6): a LIVE `TextField` renders as a
//     yellow/red unsupported-control box under the golden renderer — so the surface
//     MUST take `editable:Bool` and, when `false` (demo / golden), render a STATIC
//     placeholder `Text` of the seeded name instead of a real field; only when
//     `true` (host runtime) does it use a real editable field. reference-ui NEVER
//     calls `setUser` itself — it only FORWARDS the typed name to onSubmit and AWAITS
//     + displays the `Future<String?>` result (rb-flutter-nickname-taken-inline-error:
//     `null` → success, the host dismisses separately; non-null → inline error, stays
//     open for retry).
// ─────────────────────────────────────────────────────────────────────────────

/// The family-6 gap-surface modal container. Binds the two template gap-surface
/// `ChangeNotifier`s (`authGate` + `identityLabel`) with `ListenableBuilder`,
/// re-reads the read-only [GapSurfacesModel] on each notify, and shows the single
/// ACTIVE modal (auth-gate > guest-name-edit, mutually exclusive) by passing
/// snapshot values BY VALUE to the surface widgets. Paints with the resolved
/// [ReferenceUITheme]. login / dismiss / submit are host-wired container callbacks;
/// the rename ENTRY funnels to the core exit `template.requestGuestNameEdit()`.
///
/// `template == null` → the container uses the deterministic [GapSurfacesSeeds] (no
/// listenables to bind); the host normally supplies a live [DefaultPlayerTemplate].
class GapSurfacesOverlayView extends StatefulWidget {
  /// Live template (host-supplied). `null` → deterministic demo seeds.
  final DefaultPlayerTemplate? template;

  /// Resolved reference-ui theme.
  final ReferenceUITheme theme;

  // Host-wired interaction callbacks. The container owns NO host action (the lone
  // core exit it owns is `template.requestGuestNameEdit()`); each callback is
  // forwarded to the host (which wires it to the core exit). All optional; a null
  // callback means an inert CTA. The Model carries NO forwarder for these (gap-
  // surface actions are NOT template state-mutating methods — mirrors iOS / Android
  // `GapSurfacesModel`).

  /// Auth-gate「前往登入」→ host → `LivebuySDK.login(...)` (open login flow).
  final void Function()? onLogin;

  /// Auth-gate「稍後再說」/ scrim tap → host → `template.clearAuthGate()` (≡
  /// `authGate.clear()`); also closes the guest-name editor. This layer NEVER
  /// clears the gate itself.
  final void Function()? onDismiss;

  /// Guest-name「送出」→ the turnkey container's gap seam (→
  /// `LivebuyPlayerController.setGuestNicknameVerified(name)`; NEVER `setUser`), or a host
  /// override (rb-flutter-nickname-taken-inline-error, previously a fire-and-forget
  /// `void Function(String)?` into `LivebuySDK.setGuestNickname`). This layer NEVER calls the SDK
  /// itself; it ONLY forwards the typed name and passes the host's `Future<String?>` result back
  /// UNCHANGED — `null` = accepted (the host closes this modal separately), non-null = a
  /// user-facing error message the modal shows inline (staying open for retry).
  final Future<String?> Function(String name)? onSubmitName;

  /// The container's 設定暱稱 modal controller (parity iOS / Android / RN). When wired (host
  /// runtime), it DRIVES the guest-name modal's visibility ([NicknamePromptController.isPresented])
  /// — replacing the test-only `_showNameEdit` flag that nothing could flip from outside — and the
  /// modal renders a LIVE editable field. When null (demo / golden / standalone) the modal stays
  /// controlled by the local `_showNameEdit` (default closed) and renders the static placeholder,
  /// so the baselines stay byte-identical. A guest-name scrim dismiss funnels to
  /// `controller.dismiss()`, SEPARATE from the auth-gate [onDismiss] (which clears the auth gate).
  final NicknamePromptController? nicknameController;

  /// The container's「請先登入」modal controller (rb-flutter-live-comment-login-gate, 方案 A;
  /// rb-flutter-subscribe-login-gate). When wired and `isPresented`, the container composes
  /// `AuthGateModalView` with a synthetic gate whose triggerAction follows
  /// [LoginPromptController.triggerAction] — `commentSend` when a guest taps the LIVE 留言 pill on a
  /// `chatEnabled == false` live (`guest_comment == 0`), `subscribe` when a guest taps 訂閱. 前往登入 →
  /// host [onLogin] + dismiss; 稍後再說 / scrim → dismiss. Default unwired → not shown
  /// (golden-neutral). SEPARATE from the template-driven auth gate.
  final LoginPromptController? loginController;

  const GapSurfacesOverlayView({
    super.key,
    this.template,
    required this.theme,
    this.onLogin,
    this.onDismiss,
    this.onSubmitName,
    this.nicknameController,
    this.loginController,
  });

  @override
  State<GapSurfacesOverlayView> createState() => _GapSurfacesOverlayViewState();
}

class _GapSurfacesOverlayViewState extends State<GapSurfacesOverlayView> {
  /// Read-only snapshot bridge (re-read inside the ListenableBuilder on notify).
  late GapSurfacesModel _model = GapSurfacesModel(template: widget.template);

  /// Whether the host-triggered guest-name editor is open. Unlike the auth-gate
  /// (whose visibility is template state), the rename modal has NO template
  /// visibility flag — it is opened by a host entry (`_handleRequestNameEdit`,
  /// which ALSO fires the core `GUEST_NAME_EDIT_REQUEST` exit) and closed on submit
  /// / dismiss. Demo / golden flip it directly via [showNameEditForTesting].
  bool _showNameEdit = false;

  @override
  void didUpdateWidget(covariant GapSurfacesOverlayView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.template != widget.template) {
      _model = GapSurfacesModel(template: widget.template);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.template;

    // Bind the two template gap-surface ChangeNotifiers + the wired nickname controller so
    // any change re-reads the model / re-evaluates modal visibility. With no live template
    // (demo seeds) and no controller there is nothing to listen to — render directly.
    final mergeable = <Listenable>[
      if (t != null) ...[
        t.authGate,
        t.identityLabel,
      ],
      if (widget.nicknameController != null) widget.nicknameController!,
      if (widget.loginController != null) widget.loginController!,
    ];

    if (mergeable.isEmpty) {
      return _buildActiveModal(context);
    }
    return ListenableBuilder(
      listenable: Listenable.merge(mergeable),
      builder: (context, _) => _buildActiveModal(context),
    );
  }

  /// The single active modal by priority, or an empty `SizedBox.shrink()` when no
  /// gap surface is active. Mutually exclusive — the blocking auth-gate wins, then
  /// the host-triggered guest-name editor.
  Widget _buildActiveModal(BuildContext context) {
    final theme = widget.theme;
    final m = _model;
    final authGate = m.authGate;
    final isLoggedIn = m.isLoggedIn;

    if (authGate != null && !isLoggedIn) {
      // 1. 「請先登入」gate — HIGHEST priority (blocking). The surface takes a
      //    non-null gate (the container gates on non-null here).
      return AuthGateModalView(
        theme: theme,
        gate: authGate,
        isLoggedIn: isLoggedIn,
        // Forward optional (dropin-hide-unwired-affordances-flutter): null when host did not wire
        // `config.onLogin`, so AuthGateModalView hides the dead「前往登入」button. MUST NOT wrap.
        onLogin: widget.onLogin,
        onDismiss: _handleAuthDismiss,
      );
    }

    if (widget.loginController?.isPresented ?? false) {
      // 1b. On-demand drop-in login gate: a guest tapped a gated affordance (留言 pill on a
      //     `chatEnabled == false` live → `commentSend`, rb-flutter-live-comment-login-gate 方案 A; or
      //     訂閱 → `subscribe`, rb-flutter-subscribe-login-gate). Compose `AuthGateModalView` with a
      //     SYNTHETIC gate whose triggerAction follows `loginController.triggerAction` (set by
      //     `present(triggerAction:)`), so ONE controller serves every gate with the correct body copy;
      //     `isLoggedIn: false` (a guest raised it). 前往登入 → host login + dismiss; 稍後再說 / scrim →
      //     dismiss. SEPARATE from the template-driven auth gate above (which wins if a real
      //     AUTH_REQUIRED is also pending).
      return AuthGateModalView(
        theme: theme,
        gate: LBAuthGateState(triggerAction: widget.loginController!.triggerAction),
        isLoggedIn: false,
        // Optional-preserving (lbForwardLogin): null onLogin → null → button hidden (dismiss still
        // via 稍後再說). Non-null → dismiss the local modal then host login.
        onLogin: lbForwardLogin(widget.onLogin, () => widget.loginController?.dismiss()),
        onDismiss: _handleLoginGateDismiss,
      );
    }

    // The guest-name editor is open when the wired controller says so (host runtime), else
    // when the test-only `_showNameEdit` is set. A wired controller ALSO means we are at
    // runtime → the field is a LIVE editable one (demo / golden — no controller — keep the
    // static placeholder so the baselines stay byte-identical).
    final nameEditOpen = widget.nicknameController?.isPresented ?? _showNameEdit;
    final nameEditEditable = widget.nicknameController != null;
    if (nameEditOpen) {
      // 2. Guest display-name editor. Seeds the field from the current identity display
      //    name (or the demo guest seed when no live identity yet). The scrim funnels to
      //    `_handleNameDismiss` (close-only; does NOT clear the auth gate).
      return GuestNameEditModalView(
        theme: theme,
        displayName:
            m.identity?.displayName ?? GapSurfacesSeeds.guestIdentity.displayName,
        editable: nameEditEditable,
        onSubmit: _handleSubmitName,
        onDismiss: _handleNameDismiss,
      );
    }
    // 3. No active gap surface.
    return const SizedBox.shrink();
  }

  // -- Host-wired action funnels + the ONE core exit --------------------------
  //
  // login / dismiss / submit forward to the host callback (the host wires it to the
  // core exit it owns: LivebuySDK.login / clearAuthGate /
  // LivebuyPlayerController.setGuestNicknameVerified). The rename ENTRY is the ONLY
  // core exit this container funnels directly (`template.requestGuestNameEdit()`).
  // reference-ui NEVER logs in / renames the guest / clears the gate itself; the Model
  // carries NO forwarder.

  // 「前往登入」on the auth gate forwards `widget.onLogin` DIRECTLY (optional — undefined when host
  // did not wire `config.onLogin`, so AuthGateModalView hides the dead button;
  // dropin-hide-unwired-affordances-flutter). The login-gate variant uses `lbForwardLogin` to add a
  // dismiss while preserving optional-ness. No always-non-null `_handleLogin` wrapper.

  /// Auth-gate「稍後再說」/ scrim → host (→ `clearAuthGate()`). SEPARATE from the guest-name
  /// editor's dismiss (parity iOS / Android / RN): clearing the blocking auth gate MUST NOT be
  /// triggered by closing the (non-blocking) 設定暱稱 modal.
  void _handleAuthDismiss() => widget.onDismiss?.call();

  /// Guest-name editor scrim / close → close the modal ONLY (controller-driven when wired, else
  /// the test-only local state). Does NOT clear the auth gate (so it never calls `onDismiss`).
  void _handleNameDismiss() {
    widget.nicknameController?.dismiss();
    if (widget.nicknameController == null && _showNameEdit) {
      setState(() => _showNameEdit = false);
    }
  }

  /// Forward the typed display name on「送出」→ the turnkey container's gap seam
  /// (→ `LivebuyPlayerController.setGuestNicknameVerified`, which on SUCCESS also updates the
  /// mirror + dismisses the controller + composeAfter — see `LivebuyPlayer._submitGuestNickname`),
  /// or a host override. Defaults an unwired host (`onSubmitName == null`) to an already-resolved
  /// `null` (= success) Future — preserves the pre-existing inert-CTA behavior for demo / golden /
  /// standalone construction, where nothing ever calls the SDK.
  Future<String?> _handleSubmitName(String name) =>
      widget.onSubmitName?.call(name) ?? Future<String?>.value(null);

  /// Login-gate「稍後再說」/ scrim → dismiss the local modal ONLY (does NOT clear the template auth gate).
  void _handleLoginGateDismiss() => widget.loginController?.dismiss();

  /// The rename ENTRY — funnels DIRECTLY to the core exit
  /// `template.requestGuestNameEdit()` (emits `GUEST_NAME_EDIT_REQUEST`; safe no-op
  /// when the host wired no requester). This is the one core exit the container
  /// owns. A host entry-point (e.g. a 「編輯名稱」affordance composed elsewhere) calls
  /// this to fire the intent AND open the local editor.
  // ignore: unused_element
  void _handleRequestNameEdit() => widget.template?.requestGuestNameEdit();

  // -- Test / host hooks -------------------------------------------------------

  /// Open / close the guest-name editor (for demo / golden / widget tests, and for
  /// a host composing its own 「編輯名稱」entry). Mutually exclusive with the
  /// auth-gate (the auth-gate wins in [_buildActiveModal] regardless).
  @visibleForTesting
  void showNameEditForTesting(bool show) {
    if (_showNameEdit == show) return;
    setState(() => _showNameEdit = show);
  }
}
