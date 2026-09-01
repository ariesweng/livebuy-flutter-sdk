import 'package:livebuy_flutter/livebuy_flutter.dart';

import 'default_template.dart';

// widget-content-template — Flutter widget template attach wiring (design D7).
//
// Symmetric with `TemplateAttachment` (the player attach point): the host's
// widget widget creates a [WidgetTemplateAttachment] for a `LivebuyWidget`,
// holding the per-widget [DefaultWidgetTemplate] + its content view-model. Unlike
// the player attachment it does NOT subscribe the unified SDK event stream — the
// widget content + web-embed colors arrive on the PER-VIEW widget bridge
// (`LivebuyWidgetController`, supplied by widget-bridge-color-core), so this
// attachment wires `controller.onWidgetResponse → template.handleWidgetColors`
// and lets the host feed content snapshots via `template.handleWidgetSnapshot`.
//
// widget-product-card-content-template — `product_card` is NOT on this per-view
// colors path: Flutter's `LBWidgetColors` deliberately carries no such field
// (widget-product-card-bridge-flutter added no Dart type). It reaches the
// view-model on the SNAPSHOT path instead, from the raw snake_case
// `LivebuySDK.fetchWidget` map the host feeds to `handleWidgetSnapshot`.
//
// Flutter's accessor idiom is HOST-HELD (no global per-widget lookup): the host
// keeps the attachment its widget widget created and reads `.template`. The
// optional [LivebuyUI.widgetTemplate] lookup returns the registered attachment's
// template (or null when not installed / no attachment), preserving the
// four-platform「given widget → template (or empty)」accessor contract.

/// Bridges a per-view `LivebuyWidgetController` to a [DefaultWidgetTemplate] for
/// the Flutter UI layer. Created by the host's widget widget on mount.
class WidgetTemplateAttachment {
  /// FORMAL HOST-ACCESS POINT (widget-content-template): the host obtains the
  /// Default widget template by holding the [WidgetTemplateAttachment] its widget
  /// created and reading this getter. Through it the host reads the bindable,
  /// observable widget content view-model — [DefaultWidgetTemplate.content] (a
  /// `ChangeNotifier`: `videos` / `mode` / `currentPage` / `lastPage` /
  /// `liveVideo` / `widgetColor` / `widgetBgcolor` / `productCard`) — and binds it with
  /// `ListenableBuilder`. The template's constructor and `handle*` ingestion
  /// methods are NOT for host use (the host consumes state; it does not build the
  /// instance or feed events). Parity with the player `TemplateAttachment.template`.
  final DefaultWidgetTemplate template;

  /// The per-view widget controller this attachment is bound to (so the host
  /// `LivebuyUI.widgetTemplate(for:)` lookup can resolve it).
  final LivebuyWidgetController? controller;

  bool _attached = false;

  WidgetTemplateAttachment({
    required this.template,
    this.controller,
  });

  /// Wire the per-view widget bridge: `controller.onWidgetResponse` (web-embed
  /// colors from widget-bridge-color-core) → [DefaultWidgetTemplate.handleWidgetColors].
  /// Idempotent — calling twice keeps a single wiring. Purely additive: the host
  /// can still set its OWN `onWidgetResponse` if it captures + forwards.
  void attach() {
    if (_attached) return;
    _attached = true;
    controller?.onWidgetResponse = template.handleWidgetColors;
  }

  /// Tear the wiring down (host unmount). Idempotent.
  void detach() {
    if (!_attached) return;
    _attached = false;
    controller?.onWidgetResponse = null;
  }

  /// True while a per-view widget wiring is active.
  bool get isAttached => _attached;
}
