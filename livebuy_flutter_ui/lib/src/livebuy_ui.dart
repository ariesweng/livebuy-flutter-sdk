import 'package:flutter/widgets.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart';

import 'default_template.dart';
import 'lb_ui_options.dart';
import 'template_attachment.dart';
import 'widget_template_attachment.dart';

/// Entry-point for the Livebuy UI template layer.
///
/// One-line install: `LivebuyUI.install()`
///
/// Merge happens at Widget / Player instantiate time, not at install() time (D6).
/// Repeated install() replaces the previous template and options.
///
/// Event wiring (livebuy-ui-event-wiring-template, design D3): unlike iOS /
/// Android — which hook the core's `onInstantiate` — the Flutter UI layer
/// subscribes to the single bridge event channel via
/// `LivebuySDK.setListener(...)`. `install()` attaches a [TemplateAttachment]
/// that routes events to the Default template; `uninstall()` detaches it
/// (`setListener(null)`), returning the SDK to headless.
class LivebuyUI {
  LivebuyUI._();

  static Object? _installedTemplate;
  static LBUIOptions? _hostOptions;
  static TemplateAttachment? _attachment;

  // widget-content-template — per-widget attachment registry. The host's widget
  // widget registers a [WidgetTemplateAttachment] for its `LivebuyWidgetController`
  // so [widgetTemplate] can resolve「given widget → its Default widget template」
  // (parity with the iOS/Android/RN accessor). Keyed by the controller identity
  // (the Flutter host-held idiom — the controller IS the per-widget handle).
  static final Map<LivebuyWidgetController, WidgetTemplateAttachment>
      _widgetAttachments = {};

  /// Optional resolver for the active player `BuildContext` (for `DISMISS_REQUEST`
  /// → `Navigator.pop`). The host sets this from its player widget so the wiring
  /// can pop without flutter-ui holding the native instance. Cleared on uninstall.
  static BuildContext? Function()? playerContextProvider;

  /// Optional resolver for the active [LivebuyPlayerController] (for the
  /// `GUEST_NAME_EDIT_REQUEST` exit). The host sets this from its player widget
  /// (e.g. after `onPlatformViewCreated`) so the Default template's
  /// `requestGuestNameEdit()` can reach the already-public core exit
  /// `operationPanel.simulateGuestNameEditTap()` without flutter-ui holding the
  /// native instance. Mirrors [playerContextProvider]; cleared on uninstall.
  /// Unset / returns null → the wired requester is an inert no-op (headless-safe).
  static LivebuyPlayerController? Function()? playerControllerProvider;

  /// Install the Default template with optional host options, and subscribe the
  /// template attachment to the unified SDK event stream (design D3 — host mount).
  static void install({Object? template, LBUIOptions? options}) {
    _installedTemplate = template ?? DefaultTemplate();
    _hostOptions = options;

    // Detach any prior attachment first (idempotent re-install).
    _attachment?.detach();
    final attachment = TemplateAttachment(
      template: DefaultPlayerTemplate(
        sdkConfig: SDKConfig.fallback,
        hostOptions: _hostOptions,
        // Auto-wire the guest-name-edit exit to parity with iOS/Android/RN.
        // provider unset / returns null → `?.` short-circuits to an inert no-op.
        guestNameEditRequester: () =>
            playerControllerProvider?.call()?.operationPanel
                .simulateGuestNameEditTap(),
        // Auto-wire the「查看購物車」CTA to the core seam `requestViewCart`
        // (emit VIEW_CART) — parity with iOS/Android TemplateAttachment. provider
        // unset / returns null → `?.` short-circuits to an inert no-op.
        viewCartRequester: (productId) =>
            playerControllerProvider?.call()?.requestViewCart(productId: productId),
      ),
      contextProvider: () => playerContextProvider?.call(),
    )..attach();
    _attachment = attachment;

    // mute-preference-persist-across-session-flutter-template — per-NEW-
    // Player-instance mute seed. Distinct from (and does NOT replace) the
    // ONE-SHOT `TemplateAttachment.attach()` seed above (`handleMuted(false)`,
    // fires once per install()): this hook fires once per NEW native Player
    // platform view (`flutter-player-instantiation-hook-core`'s
    // `LivebuyPlayerController.onInstantiate`), letting each new Player
    // instance seed the mute icon from its OWN actual native mute state —
    // e.g. a fresh instance created after the user closed and reopened the
    // player may have inherited a non-default app-session mute preference
    // (`mute-preference-persist-across-session-{ios,android}-core`).
    //
    // `attachment` is captured in a LOCAL (not re-read from the static
    // `_attachment` field) and the resolve callback re-checks
    // `identical(_attachment, attachment)` before writing. This guards two
    // races: (a) a REPEATED `install()` call replaces both `_attachment` and
    // `onInstantiate` with a new closure bound to the new attachment, but an
    // already-in-flight `isMuted()` query from THIS closure is not
    // cancelled by that reassignment — its late resolve must not write into
    // either the stale attachment it was bound to (already detached, no
    // longer observed) or the newer one (never queried by this call, would
    // corrupt its own not-yet-run seed); (b) `uninstall()` sets `_attachment`
    // to null before a pending query resolves, which must not resurrect a
    // write into an already-torn-down attachment.
    LivebuyPlayerController.onInstantiate = (controller) {
      controller.isMuted().then((muted) {
        if (identical(_attachment, attachment)) {
          attachment.template.handleMuted(muted);
        }
      });
    };
  }

  /// Remove any installed template, detach the event subscription
  /// (`setListener(null)`), and clear host options (design D3 — unmount).
  static void uninstall() {
    _installedTemplate = null;
    _hostOptions = null;
    playerContextProvider = null;
    playerControllerProvider = null;
    // mute-preference-persist-across-session-flutter-template — release
    // ownership of the per-instance instantiation hook (single-owner seam,
    // `flutter-player-instantiation-hook-core`: later assignment replaces the
    // prior one). `install()` above already claimed exclusive ownership of
    // this GLOBAL static field the moment it ran, so returning it to `null`
    // here is symmetric with clearing `playerContextProvider` /
    // `playerControllerProvider` — it is not a new restriction, it completes
    // the same ownership handoff `install()` started.
    LivebuyPlayerController.onInstantiate = null;
    _attachment?.detach();
    _attachment = null;
    // widget-content-template — tear down every per-widget attachment.
    for (final a in _widgetAttachments.values) {
      a.detach();
    }
    _widgetAttachments.clear();
  }

  /// True when a template has been installed.
  static bool get isInstalled => _installedTemplate != null;

  /// widget-content-template — attach a Default widget template to a per-view
  /// `LivebuyWidgetController`. The host's widget widget calls this on mount
  /// (after creating its controller) so the colors (widget-bridge-color-core) are
  /// wired and [widgetTemplate] can later resolve the template. Returns the
  /// created [WidgetTemplateAttachment] (the host may also hold it directly — the
  /// Flutter host-held accessor idiom). Re-attaching the SAME controller detaches
  /// the prior wiring first (idempotent). No-op semantics: the returned
  /// attachment is inert until [WidgetTemplateAttachment.attach] runs (done here).
  static WidgetTemplateAttachment attachWidget(
    LivebuyWidgetController controller, {
    LBUIOptions? options,
  }) {
    _widgetAttachments.remove(controller)?.detach();
    final attachment = WidgetTemplateAttachment(
      template: DefaultWidgetTemplate(
        sdkConfig: SDKConfig.fallback,
        hostOptions: options ?? _hostOptions,
      ),
      controller: controller,
    )..attach();
    _widgetAttachments[controller] = attachment;
    return attachment;
  }

  /// widget-content-template — detach + forget a per-view widget attachment (host
  /// unmount). Idempotent — safe when the controller was never attached.
  static void detachWidget(LivebuyWidgetController controller) {
    _widgetAttachments.remove(controller)?.detach();
  }

  /// widget-content-template — host accessor: given a `LivebuyWidgetController`
  /// (the per-widget handle), return its Default widget template instance, or
  /// `null` when the template is not installed OR the widget was never attached.
  /// MUST NOT throw. Symmetric with the iOS `LivebuyUI.widgetTemplate(for:)` /
  /// Android `LivebuyUI.widgetTemplate(widget)` / RN attach handle. The host reads
  /// the returned template's [DefaultWidgetTemplate.content] (a `ChangeNotifier`)
  /// from outside the module.
  static DefaultWidgetTemplate? widgetTemplate(
      LivebuyWidgetController controller) {
    if (!isInstalled) return null;
    return _widgetAttachments[controller]?.template;
  }

  /// PUBLIC per-player read path: the live [DefaultPlayerTemplate] the current global
  /// attachment wired (`null` when [install] has not run). The turnkey `LivebuyPlayer`
  /// container reads this to bind the reference-ui surfaces to LIVE state (header / rail /
  /// merged feed / info panel) instead of the deterministic demo seeds. Symmetric with the
  /// iOS `LivebuyUI.playerTemplate(for:)` / Android `LivebuyUI.playerTemplate(view)` accessors;
  /// Flutter attaches ONE template SDK-globally (via `setListener`), so there is no per-view
  /// key. MUST NOT throw. The host reads the returned template's public `ChangeNotifier`
  /// view-models (`feed` / `header` / `winClaim` …) from outside the module.
  static DefaultPlayerTemplate? get playerTemplate => _attachment?.template;

  /// Test-only access to the [DefaultPlayerTemplate] the current attachment
  /// wired (null when not installed). Retained alias of [playerTemplate] for existing tests.
  @visibleForTesting
  static DefaultPlayerTemplate? get attachedTemplateForTesting =>
      _attachment?.template;

  /// The current host options (null if not installed or no options were passed).
  static LBUIOptions? get hostOptions => _hostOptions;

  /// PUBLIC forwarding accessor (`add-flutter-dropin-container-event-forward-template`):
  /// hand one unified [LBSdkEvent] to the currently-attached template and get
  /// back its [LBEventReply], WITHOUT calling `LivebuySDK.setListener` again
  /// (which would itself replace the caller's own listener — `setListener` is
  /// a single global slot, `flutter/lib/src/livebuy_sdk.dart`).
  ///
  /// This is the template-layer half of the (separate, not-yet-applied)
  /// reference-ui-layer change `rb-flutter-dropin-container-event-forwarding`:
  /// the drop-in container's own wrapper listener (installed via its own
  /// `LivebuySDK.setListener(...)` call, which replaces this attachment's
  /// subscription) is intended to call this from inside its handler, e.g.:
  ///
  /// ```dart
  /// LivebuySDK.setListener((event) async {
  ///   final hostReply = await hostListener?.call(event);
  ///   final templateReply = await LivebuyUI.forwardToTemplate(event);
  ///   return hostReply ?? templateReply;
  /// });
  /// ```
  ///
  /// (host-reply-first, template-reply-fallback — design D3). This change does
  /// NOT itself edit `flutter-reference-ui` code; the snippet above is
  /// illustrative only.
  ///
  /// Headless-safe: when [install] has never been called, or [uninstall] has
  /// run since the last [install], returns [LBEventReply.passthrough] and
  /// produces no side effect — the same "no opinion" fallback a host that
  /// never installs a template already sees today.
  static Future<LBEventReply> forwardToTemplate(LBSdkEvent event) {
    final attachment = _attachment;
    if (attachment == null) return Future.value(LBEventReply.passthrough);
    return attachment.handleEvent(event);
  }
}
