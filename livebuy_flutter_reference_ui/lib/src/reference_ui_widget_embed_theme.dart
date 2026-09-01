import 'package:flutter/painting.dart' show Color;

import 'reference_ui_theme.dart';

// ReferenceUIWidgetEmbedTheme — widget-scope embed-color derivation (Flutter).
//
// Spec: `widget-embed-colors/spec.md`
// Design: rb-flutter-widget-embed-colors design.md FD1 / FD3 / FD5.
// Flutter sibling of iOS `ReferenceUIWidgetEmbedTheme.swift` (rb-ios-widget-embed-colors,
// `a5736fc1`) and Android `ReferenceUIWidgetEmbedTheme.kt` (rb-android-widget-embed-colors,
// `a75ee327`).
//
// A SECOND, NARROWER step that runs AFTER [ReferenceUIThemeResolver] and ONLY on the
// widget surfaces (`CarouselView` — both its windowed and `scrollable` modes — and
// `VideoShopGridView`). It takes the already-resolved theme and overlays the two
// web-embed colors from `POST /sdk/widget`:
//
//     ReferenceUIThemeResolver.resolve(...)   →  ReferenceUITheme   (global)
//                                                      │
//              widgetColor / widgetBgcolor  ──▶  derive(...)        (widget only)
//                                                      │
//                                                      ▼
//                              CarouselView / VideoShopGridView
//
// WHY NOT FEED THE RESOLVER: `background` / `text` are GLOBAL tokens — the player shell,
// the product sheets, `WinClaimSheetView`, `AuthGateModalView` and dozens of other
// surfaces read them. Injecting a merchant's widget colors into the resolver would tint
// all of them. The resolver stays UNTOUCHED and still MUST NOT see these two values
// (`reference-ui-rendering` § 解析器輸出不受 widget 顏色影響).
//
// WHY NOT DERIVE ON `WidgetOverlayView._buildSurface`'s LOCAL `theme` EITHER (the
// Flutter-specific trap): that one local is shared by ALL FOUR mode branches, including
// `floating` (`FloatingWidgetView`) and `minimized` (`MinimizedWidgetView`), so deriving
// there would tint the floating / minimized cards too. Android has the same trap one node
// higher (`WidgetSurfaceContext.theme`); iOS has none (its floating card takes a video,
// not a shared context).
//
// Effective priority (high → low):
//
//     sdkConfig.theme  >  widget colors (here)  >  LBUIOptions  >  minimal palette
//
// Pure — no global reads, no `BuildContext` / widget tree, unit-testable as plain Dart.

/// The widget-scope `/sdk/widget` embed-color derivation (`widget-embed-colors`).
class ReferenceUIWidgetEmbedTheme {
  ReferenceUIWidgetEmbedTheme._();

  /// `widget_color == 2`（色彩反轉）的文字色，對齊 web embed 渲染端的 `#ffffff`.
  static const String invertedTextHex = '#FFFFFF';

  /// The wire value of `widget_color` meaning「色彩反轉」(inverted text).
  static const int invertedColorMode = 2;

  /// Resolved `#FFFFFF` for the inverted text mode.
  static final Color invertedText =
      colorFromHex(invertedTextHex) ?? const Color(0xFFFFFFFF);

  /// Overlay the `/sdk/widget` embed colors onto an already-resolved theme.
  ///
  /// - [widgetColor] `2`（色彩反轉）→ `text` becomes `#FFFFFF`. `1`（預設色彩）and every
  ///   other value leave `text` UNTOUCHED. Web's `1` means "emit no color override" — its
  ///   native equivalent is keeping the resolved `text`, NOT adopting the third-party
  ///   page's `#3C3C3C` body default (design D1).
  /// - [widgetBgcolor] overrides `background` ONLY when it parses as a hex color. The
  ///   empty string `""`（後端的「透明」表示法）, `null` and any unparseable string all mean
  ///   "leave it alone" (design D2) — [colorFromHex] returns null for all three (null
  ///   guard / length guard / `int.tryParse` failure), so they land on the same branch
  ///   with no special case. `""` is specifically NOT a native transparent background:
  ///   web's transparency has a third-party page showing through, native has no
  ///   equivalent backing surface, and the backend writes the key unconditionally so `""`
  ///   is the MAJORITY state rather than a rare one.
  ///
  /// Value-domain tolerance (numeric string `"2"` → `2`, unparseable → `1`) is core's job
  /// per `widget-decode-robustness`; this function does NOT redo it.
  ///
  /// Returns a theme where at most `text` / `background` differ. When nothing is
  /// configured the result EQUALS [theme] (design D6 / FD5 — keeps every existing golden
  /// baseline byte-identical). A future token added to [ReferenceUITheme] must be carried
  /// through here as well (this rebuilds field-by-field, mirroring the iOS baseline).
  static ReferenceUITheme derive(
    ReferenceUITheme theme,
    int widgetColor,
    String? widgetBgcolor,
  ) {
    final text = widgetColor == invertedColorMode ? invertedText : theme.text;
    final background = colorFromHex(widgetBgcolor) ?? theme.background;

    return ReferenceUITheme(
      accent: theme.accent,
      background: background,
      text: text,
      cornerRadius: theme.cornerRadius,
      fontScale: theme.fontScale,
    );
  }
}
