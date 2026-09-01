// VTTSubtitleParser — WebVTT parsing pipeline (rb-flutter-subtitle-vtt-caption-display)
//
// Spec: `reference-ui-rendering/spec.md` "Flutter PlayerShellView 提供 VOD WebVTT 字幕解析、fetch 與
// CaptionOverlayView 渲染".
//
// Core exposes only `SubtitleTrack.{available,enabled}` (booleans, mirrored by
// `PlayerShellModel.subtitleEnabled`) — there is NO active-caption TEXT source. `channel
// .subtitle_url` (forwarded to Dart as `template.subtitle.url` via `handleSubtitleChannelInfo`)
// points at a WebVTT file the turnkey container fetches and parses itself (see
// `subtitle_vtt_pipeline.dart`); this file is the pure, offline-testable parsing half of that
// pipeline. Deliberately dependency-free (no Flutter / widget types) so it is trivial to unit
// test.
//
// Ported RULE-for-rule (NOT code-for-code) from iOS `VTTSubtitleParser.swift`
// (rb-ios-subtitle-vtt-caption-display) / Android `VTTSubtitleParser.kt`
// (rb-android-subtitle-vtt-caption-display) — same decode-tolerant philosophy as the repo's
// existing JSON-decoder-fallback discipline (CLAUDE.md "JSON decoder fallback"): a single
// malformed cue block is skipped without discarding the rest of the file.

/// A single parsed WebVTT cue: a `[start, end)` time window (seconds) and its display text.
class VTTCue {
  final double start;
  final double end;
  final String text;

  const VTTCue({required this.start, required this.end, required this.text});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VTTCue &&
          runtimeType == other.runtimeType &&
          start == other.start &&
          end == other.end &&
          text == other.text;

  @override
  int get hashCode => Object.hash(start, end, text);

  @override
  String toString() => 'VTTCue(start: $start, end: $end, text: $text)';
}

/// Pure WebVTT parsing + time-indexed cue lookup. No I/O, no side effects — the network fetch
/// lives in `subtitle_vtt_pipeline.dart`, which feeds this parser raw text.
abstract final class VTTSubtitleParser {
  /// Parse raw WebVTT text into an ordered `List<VTTCue>`. Decode-tolerant (mirrors the repo's
  /// existing JSON-decoder-fallback philosophy, CLAUDE.md "JSON decoder fallback"): a missing
  /// `WEBVTT` header, cue-identifier lines, `NOTE` blocks, and cue settings trailing the
  /// timestamp line (e.g. `align:middle`) are all tolerated; a single malformed cue block is
  /// skipped without discarding the rest of the file. Empty / entirely unparsable input -> `[]`.
  static List<VTTCue> parse(String raw) {
    final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final blocks = normalized.split('\n\n');
    final cues = <VTTCue>[];
    for (final block in blocks) {
      final cue = _parseBlock(block);
      if (cue != null) cues.add(cue);
    }
    return cues;
  }

  /// Parse ONE cue block (the lines between two blank-line separators). A block may open with
  /// a `WEBVTT` header line, a `NOTE` comment, or a bare cue-identifier line — all skipped while
  /// scanning forward for the first line containing `-->` (the timestamp line). Returns `null`
  /// when no timestamp line is found, the timestamps fail to parse, or no non-empty text
  /// follows (all treated as "not a real cue", not a fatal error for the rest of [parse]).
  static VTTCue? _parseBlock(String block) {
    final lines = block.split('\n');
    final timestampIndex = lines.indexWhere((l) => l.contains('-->'));
    if (timestampIndex < 0) return null;

    final range = _parseTimestampLine(lines[timestampIndex]);
    if (range == null) return null;

    final text = lines
        .sublist(timestampIndex + 1)
        .map(_stripInlineTags)
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .join('\n');
    if (text.isEmpty) return null;
    return VTTCue(start: range.$1, end: range.$2, text: text);
  }

  /// Parse a `"<start> --> <end> [cue settings...]"` line into `(start, end)` seconds. Cue
  /// settings after the end timestamp (e.g. `align:middle line:90%`) are ignored — only the
  /// first two whitespace-separated tokens either side of `-->` are consumed.
  static (double, double)? _parseTimestampLine(String line) {
    final parts = line.split('-->');
    if (parts.length < 2) return null;
    final start = _parseTimestamp(parts[0]);
    if (start == null) return null;
    // The end side may carry trailing cue settings after the timestamp token; take only the
    // first whitespace-separated token.
    final endTokens = parts[1].trim().split(RegExp(r'\s+'));
    final endToken = endTokens.isNotEmpty ? endTokens.first : '';
    final end = _parseTimestamp(endToken);
    if (end == null) return null;
    return (start, end);
  }

  /// Parse a single VTT timestamp token — `HH:MM:SS.mmm` or the shorter `MM:SS.mmm` — into
  /// seconds. Any other shape -> `null` (the caller skips the enclosing cue, not the whole
  /// file).
  static double? _parseTimestamp(String raw) {
    final token = raw.trim();
    final secAndMs = token.split('.');
    if (secAndMs.length != 1 && secAndMs.length != 2) return null;

    final hms = secAndMs[0].split(':');
    double milliseconds;
    if (secAndMs.length == 2) {
      // Pad/truncate to exactly 3 digits so "5" -> 500ms, "500" -> 500ms, "5000" invalid.
      final msString = secAndMs[1];
      if (msString.length > 3) return null;
      final msValue = double.tryParse(msString);
      if (msValue == null) return null;
      final scale = _pow10(3 - msString.length);
      milliseconds = msValue * scale / 1000.0;
    } else {
      milliseconds = 0.0;
    }

    switch (hms.length) {
      case 3:
        final h = double.tryParse(hms[0]);
        final m = double.tryParse(hms[1]);
        final s = double.tryParse(hms[2]);
        if (h == null || m == null || s == null) return null;
        return h * 3600 + m * 60 + s + milliseconds;
      case 2:
        final m = double.tryParse(hms[0]);
        final s = double.tryParse(hms[1]);
        if (m == null || s == null) return null;
        return m * 60 + s + milliseconds;
      default:
        return null;
    }
  }

  static double _pow10(int exponent) {
    var result = 1.0;
    for (var i = 0; i < exponent; i++) {
      result *= 10.0;
    }
    return result;
  }

  /// Strip WebVTT inline cue-span tags (`<b>`, `</i>`, `<c.classname>`, `<00:00:01.000>`, ...)
  /// from a cue text line. The result feeds a plain `Text` (`CaptionOverlayView`), which does
  /// not interpret markup — leaving tags in would show literal `<i>...</i>` on screen. This is
  /// a simple regex strip, not full VTT cue-span style support (design.md Non-Goals).
  static String _stripInlineTags(String line) {
    if (!line.contains('<')) return line;
    final result = StringBuffer();
    var insideTag = false;
    for (final ch in line.runes) {
      final char = String.fromCharCode(ch);
      if (char == '<') {
        insideTag = true;
      } else if (char == '>') {
        insideTag = false;
      } else if (!insideTag) {
        result.write(char);
      }
    }
    return result.toString();
  }

  /// Find the cue whose `[start, end)` window contains `at` (start inclusive, end exclusive).
  /// `cues` need not be sorted. Multiple overlapping matches -> the first one found (overlapping
  /// cue stacking is out of scope, design.md Non-Goals). No match -> `null`.
  static VTTCue? activeCue(List<VTTCue> cues, double at) {
    for (final cue in cues) {
      if (cue.start <= at && at < cue.end) return cue;
    }
    return null;
  }
}
