import 'package:flutter/painting.dart' show Color;
// `LBSdkTheme` is a CORE public type — reached transitively through the template
// path dependency (`livebuy_flutter_ui -> livebuy_flutter`). The template barrel
// re-exports its own view-models but not the core DTOs, so we import the core
// type from its own package (still a single-direction, transitive reach).
import 'package:livebuy_flutter/livebuy_flutter.dart' show LBSdkTheme;
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart' show LBUIOptions;

// ReferenceUITheme — reference-ui (pixel layer) resolved palette + tokens.
//
// Spec: `reference-ui-rendering/spec.md`
//   § "Flutter Reference-UI 主題解析合併序 sdkConfig.theme > host options > minimal palette"
// Design: rb-flutter-scaffold design.md D2.
//
// Flutter parity of iOS `ReferenceUITheme` / `ReferenceUIThemeResolver` and
// Android `ReferenceUITheme` / `ReferenceUIThemeResolver`.
//
// ── RELATION TO `widget_color` / `widget_bgcolor` (rb-flutter-widget-embed-colors) ──
// The RESOLVER below stays INDEPENDENT of those two web-embed colors: they MUST NOT
// become inputs to `ReferenceUIThemeResolver.resolve(...)` and its output MUST NOT change
// because of them. `background` / `text` are GLOBAL tokens (player shell, product sheets,
// win-claim, auth-gate, … all read them), so interpreting merchant widget colors here
// would tint the whole app.
//
// They ARE interpreted — but in a SECOND, NARROWER step that runs AFTER this resolver and
// ONLY on the widget surfaces: `ReferenceUIWidgetEmbedTheme.derive`
// (`reference_ui_widget_embed_theme.dart`, contract `widget-embed-colors`). Effective
// priority becomes: `sdkConfig.theme` > widget colors > `LBUIOptions` > minimal palette.
//
// The minimal-palette fallback values are sourced from the design reference
// `design/templates/minimal/*.jsx` (same source & values as iOS / Android):
//   - accent       #F03246  (LIVE badge / brand action red)
//   - text         #15131A  (primary text color)
//   - background   #FFFFFF  (on-accent / surface white)
//   - cornerRadius 12       (most common card radius)
//   - fontScale    1.0      (unscaled)

/// Resolved reference-ui theme: the palette a reference-ui Flutter widget paints
/// with, plus a couple of layout tokens. Produced by [ReferenceUIThemeResolver].
class ReferenceUITheme {
  /// Brand / action accent (e.g. the LIVE badge, primary CTA). Resolved from
  /// `sdkConfig.theme.primaryColor` > `LBUIOptions.theme.primaryColor` >
  /// minimal palette accent.
  final Color accent;

  /// Page / surface background.
  final Color background;

  /// Primary foreground text color.
  final Color text;

  /// Card / surface corner radius token (logical px).
  final double cornerRadius;

  /// Global font scale (1.0 = unscaled). Resolved from
  /// `sdkConfig.theme.fontScale` > `LBUIOptions.theme.fontScale` > 1.0.
  final double fontScale;

  const ReferenceUITheme({
    required this.accent,
    required this.background,
    required this.text,
    required this.cornerRadius,
    required this.fontScale,
  });

  @override
  bool operator ==(Object other) =>
      other is ReferenceUITheme &&
      other.accent == accent &&
      other.background == background &&
      other.text == text &&
      other.cornerRadius == cornerRadius &&
      other.fontScale == fontScale;

  @override
  int get hashCode =>
      Object.hash(accent, background, text, cornerRadius, fontScale);
}

/// The minimal palette fallback (lowest-priority source). Color values are
/// lifted from the design reference `design/templates/minimal/*.jsx` — same
/// source & values as iOS `ReferenceUIThemePalette.minimal` and Android
/// `ReferenceUIThemePalette.minimal`.
class ReferenceUIThemePalette {
  ReferenceUIThemePalette._();

  /// Accent hex from the minimal design (`#F03246`).
  static const String minimalAccentHex = '#F03246';

  /// Primary text hex from the minimal design (`#15131A`).
  static const String minimalTextHex = '#15131A';

  /// Surface / background hex from the minimal design (`#FFFFFF`).
  static const String minimalBackgroundHex = '#FFFFFF';

  /// Default card corner radius from the minimal design (`12`).
  static const double minimalCornerRadius = 12;

  /// Unscaled font scale.
  static const double minimalFontScale = 1.0;

  /// The fully-resolved minimal fallback theme.
  static final ReferenceUITheme minimal = ReferenceUITheme(
    accent: colorFromHex(minimalAccentHex) ?? const Color(0xFFF03246),
    background: colorFromHex(minimalBackgroundHex) ?? const Color(0xFFFFFFFF),
    text: colorFromHex(minimalTextHex) ?? const Color(0xFF15131A),
    cornerRadius: minimalCornerRadius,
    fontScale: minimalFontScale,
  );
}

/// Parse a `#RRGGBB` / `RRGGBB` (or `#RGB` shorthand) hex string into a [Color]
/// (full opacity). Returns null on null / malformed input so the resolver can
/// fall through to the next source. Mirrors iOS `Color(hex:)` / Android
/// `colorFromHex` (malformed → null fall-through).
Color? colorFromHex(String? rawValue) {
  if (rawValue == null) return null;
  var s = rawValue.trim();
  if (s.startsWith('#')) s = s.substring(1);

  // Expand 3-digit shorthand (RGB → RRGGBB).
  if (s.length == 3) {
    s = s.split('').map((c) => '$c$c').join();
  }
  if (s.length != 6) return null;

  final rgb = int.tryParse(s, radix: 16);
  if (rgb == null) return null;

  return Color(0xFF000000 | rgb);
}

/// Pure theme merge — inputs three sources, outputs a resolved [ReferenceUITheme],
/// NO implicit global side effects, never reads a widget `BuildContext`.
///
/// Merge order (high → low):
///   `coreTheme` (sdkConfig.theme) > `hostOptions.theme` > minimal palette
///
/// Each token resolves INDEPENDENTLY through the chain — a core theme that
/// supplies only `primaryColor` still lets `fontScale` fall through to host /
/// minimal. This is intentional per-field merge (not all-or-nothing), exactly
/// like iOS / Android.
///
/// `widget_color` / `widget_bgcolor` MUST NOT be inputs here and MUST NOT change this
/// output — the widget surfaces overlay them AFTERWARDS via
/// `ReferenceUIWidgetEmbedTheme.derive` (`widget-embed-colors`).
class ReferenceUIThemeResolver {
  ReferenceUIThemeResolver._();

  /// Resolve the effective reference-ui theme from the three sources.
  ///
  /// - [coreTheme]: `sdkConfig.theme` (core global theme), highest priority.
  /// - [hostOptions]: the host-supplied `LBUIOptions` (its `.theme`), middle.
  /// - [fallback]: the lowest-priority palette (default: minimal).
  static ReferenceUITheme resolve({
    LBSdkTheme? coreTheme,
    LBUIOptions? hostOptions,
    ReferenceUITheme? fallback,
  }) {
    final base = fallback ?? ReferenceUIThemePalette.minimal;
    final hostTheme = hostOptions?.theme;

    // primaryColor → accent (per-field chain: core > host > fallback).
    final accent =
        _firstColor([coreTheme?.primaryColor, hostTheme?.primaryColor]) ??
            base.accent;

    // fontScale (double on the wire) → double (core > host > fallback).
    final fontScale =
        _firstFontScale([coreTheme?.fontScale, hostTheme?.fontScale]) ??
            base.fontScale;

    // background / text / cornerRadius have no core/host wire field today, so
    // they take the fallback palette directly (future family changes may add
    // host inputs; the chain shape stays the same).
    return ReferenceUITheme(
      accent: accent,
      background: base.background,
      text: base.text,
      cornerRadius: base.cornerRadius,
      fontScale: fontScale,
    );
  }

  /// First parseable hex color from the priority-ordered hex strings, or null.
  static Color? _firstColor(List<String?> candidates) {
    for (final candidate in candidates) {
      final color = colorFromHex(candidate);
      if (color != null) return color;
    }
    return null;
  }

  /// First present font scale from the priority-ordered values, or null.
  static double? _firstFontScale(List<double?> candidates) {
    for (final candidate in candidates) {
      if (candidate != null) return candidate;
    }
    return null;
  }
}
