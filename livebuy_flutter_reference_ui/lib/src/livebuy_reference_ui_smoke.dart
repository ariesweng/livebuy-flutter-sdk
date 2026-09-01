import 'package:flutter/widgets.dart';
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show DefaultPlayerTemplate;

import 'reference_ui_theme.dart';

// LivebuyReferenceUISmoke — minimal chain-proof widget.
//
// Spec: `reference-ui-rendering/spec.md`
//   § "Flutter Reference-UI 像素只在 livebuy_flutter_reference_ui 層（template /
//      core 零像素外洩）"
// Design: rb-flutter-scaffold design.md D4.
//
// Flutter parity of iOS `ReferenceUISmokeView` and Android
// `LivebuyReferenceUISmoke`. This is the scaffold's sole pixel artifact: it
// proves the chain
//   livebuy_flutter_reference_ui -> livebuy_flutter_ui -> livebuy_flutter
// compiles AND renders. It does NOT render any family's full pixels
// (player-shell / feed-win / product-sheets / moments / widget / gap-surfaces) —
// that is each family change's job.
//
// === iOS / Android lessons baked in for future families (read before drawing) ===
//
//  1. GOLDEN DETERMINISM > convenience. AVOID lazy/scrolling containers
//     (`ListView` / `GridView` / slivers) for content that must appear in a
//     baseline PNG — use plain `Column` / `Row` and have the host forward scroll
//     (parity to the iOS "pure VStack/HStack + host forwards" rule).
//  2. A GREEN golden test != correct pixels. Always open the produced PNG and
//     eyeball it; do not trust the byte-compare pass alone.
//  3. Latin labels render deterministically with the bundled test font; CJK is
//     deferred to family changes (this smoke uses a short latin displayName).

/// A minimal, deterministic widget that renders the resolved [ReferenceUITheme]
/// (background / accent / text / cornerRadius / fontScale all applied) plus a
/// label — proving the Flutter pixel chain works end-to-end.
///
/// Uses only plain `Container` / `Column` (NO lazy/scrolling containers) so it
/// renders deterministically under golden tests (see lesson 1 above).
class LivebuyReferenceUISmoke extends StatelessWidget {
  /// The resolved reference-ui theme (from [ReferenceUIThemeResolver]).
  final ReferenceUITheme theme;

  /// A label drawn into the smoke surface (e.g. an identity name). null falls
  /// back to a stable placeholder so the golden stays deterministic.
  final String? displayName;

  const LivebuyReferenceUISmoke({
    super.key,
    required this.theme,
    this.displayName,
  });

  @override
  Widget build(BuildContext context) {
    final name = displayName ?? 'Guest';
    return Container(
      // Themed surface — the resolved background token.
      color: theme.background,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Accent swatch — the resolved accent token, drawn as a rounded chip.
          Container(
            width: 120,
            height: 48,
            decoration: BoxDecoration(
              color: theme.accent,
              borderRadius: BorderRadius.circular(theme.cornerRadius),
            ),
          ),
          const SizedBox(height: 12),
          // A themed label — applies accent-independent text color + font scale.
          Text(
            'reference-ui · $name',
            textDirection: TextDirection.ltr,
            style: TextStyle(
              color: theme.text,
              fontSize: 14 * theme.fontScale,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Read the host-bindable identity-label display name off the Default player
/// template, proving the dependency chain compiles against template + core
/// (`livebuy_flutter_ui` → `livebuy_flutter`). Returns null when the template is
/// null or no `AUTH_STATE_CHANGED` has arrived yet (the view-model's `current`
/// is null until then).
///
/// Pure read — it does NOT mutate the template or feed it events (the host owns
/// that wiring). reference-ui only READS existing host-bindable view-models.
String? smokeIdentityName(DefaultPlayerTemplate? template) =>
    template?.identityLabel.current?.displayName;
