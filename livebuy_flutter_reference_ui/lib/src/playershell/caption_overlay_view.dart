import 'package:flutter/widgets.dart';

import '../reference_ui_theme.dart';

// CaptionOverlayView — family-1 VOD closed-caption line (rb-flutter-subtitle-vtt-caption-display)
//
// Spec: `reference-ui-rendering/spec.md` "Flutter PlayerShellView 提供 VOD WebVTT 字幕解析、fetch 與
// CaptionOverlayView 渲染".
// Design: `design/templates/minimal/sdk-components.jsx` `LBPCaptionOverlay` — a centered caption
//         line near the bottom, shown only while CC is ON.
// Flutter sibling of iOS `CaptionOverlayView.swift` / Android `CaptionOverlayView.kt`.
//
// A centered closed-caption line. There is NO public core source for the active subtitle TEXT
// today (only `subtitle.{available,enabled}` booleans) — the text is resolved by
// `PlayerShellView` from the WebVTT pipeline (`vtt_subtitle_parser.dart` /
// `subtitle_vtt_pipeline.dart`) and passed in by value. Pure presentation — renders nothing for
// empty text.

/// A centered VOD closed-caption line. Renders nothing for empty [text] (the shell only shows it
/// while CC is on with a non-empty resolved caption). iOS/Android parity: 13sp/pt medium white
/// on a `black @ 0.55 opacity` capsule, h12 / v6 padding, up to 2 lines, centered.
class CaptionOverlayView extends StatelessWidget {
  final ReferenceUITheme theme;

  /// Resolved caption text (VTT `activeCue` lookup, done by the caller). Empty -> nothing.
  final String text;

  const CaptionOverlayView({super.key, required this.theme, required this.text});

  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF000000).withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          text,
          style: TextStyle(
            color: const Color(0xFFFFFFFF),
            fontSize: 13 * theme.fontScale,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
