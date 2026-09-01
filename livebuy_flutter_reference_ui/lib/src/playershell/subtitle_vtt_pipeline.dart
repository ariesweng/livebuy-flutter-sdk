import 'dart:convert';
import 'dart:io';

import '../reference_ui_image_url.dart';
import 'vtt_subtitle_parser.dart';

// VTT subtitle fetch pipeline (rb-flutter-subtitle-vtt-caption-display)
//
// `CaptionOverlayView` is pure presentation and core exposes no active-caption TEXT (only
// `SubtitleTrack.{available,enabled}` booleans, mirrored by `PlayerShellModel.subtitleEnabled`)
// — `PlayerShellView` itself is responsible for fetching + parsing `template.subtitle.url` (a
// WebVTT file) and driving `VTTSubtitleParser.activeCue(_, model.playbackPosition)`. See
// design.md Decision 3 for why this pipeline is driven from `_PlayerShellViewState` rather than
// a separate Tier-B container layer (unlike iOS `LivebuyPlayer.swift` / Android
// `LivebuyPlayer.kt`) — Flutter's `PlayerShellView` is the only place directly bound to the live
// `DefaultPlayerTemplate`.
//
// Deliberately dependency-free beyond `dart:io` (no `http`/`dio` pubspec dependency — a VTT file
// is a small text file, mirrors iOS `URLSession` / Android `HttpURLConnection` precedent).

/// Injected VTT-fetch side effect — the seam a test substitutes a fake for (no real network).
/// Returns the decoded UTF-8 body, or `null` on any failure (no data / bad encoding / transport
/// error / non-2xx status) — this pipeline is silently best-effort.
typedef SubtitleVttFetcher = Future<String?> Function(String url);

/// Pure: normalize a raw `template.subtitle.url` into a fetchable URL, or `null` when blank.
/// Wraps [referenceUiHttpsUpgraded] (which alone does not trim / blank-check) with a trim +
/// blank->null check, mirroring iOS `ReferenceUIImageURL.make` / Android `subtitleVttUrl`.
String? subtitleVttUrl(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  return referenceUiHttpsUpgraded(trimmed);
}

/// Pure: should a subtitle fetch be (re)triggered for [url], given the last url this pipeline
/// already fetched (or explicitly cleared) for is [lastFetchedUrl]? De-dupes on the URL itself
/// — **not** a channel id (Flutter core does not bridge `LBChannel`/id to Dart; `url` is itself
/// the per-channel signal, `onSubtitleChange` already fires only once per genuine channel load).
/// `lastFetchedUrl == null` is treated as `''` (nothing fetched/cleared yet).
bool shouldRefetchSubtitleCues({required String url, required String? lastFetchedUrl}) =>
    url != (lastFetchedUrl ?? '');

/// Production [SubtitleVttFetcher]: a plain `HttpClient` fetch (no caching, no retry — a VTT
/// file is small and fetched at most once per channel, de-duped by
/// [shouldRefetchSubtitleCues]). Any failure (connect timeout, transport error, non-2xx status,
/// bad encoding) returns `null` — never throws.
Future<String?> defaultSubtitleVttFetcher(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(Uri.parse(url));
    final response = await request.close();
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    return await response.transform(utf8.decoder).join();
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Fetch + parse [url]'s WebVTT body via [fetcher] (default [defaultSubtitleVttFetcher]).
/// - [url] `null` (no fetchable subtitle) -> `[]`, no fetch.
/// - A fetch/decode/parse failure ([fetcher] returning `null`, or throwing — caught here as an
///   extra safety net even though the production fetcher never throws) -> `[]` (best-effort, no
///   crash, no retry, no event; core itself has no opinion on VTT fetch failures either — this
///   pipeline is reference-ui-only).
Future<List<VTTCue>> fetchAndParseSubtitleCues({
  required String? url,
  SubtitleVttFetcher fetcher = defaultSubtitleVttFetcher,
}) async {
  if (url == null) return const [];
  String? raw;
  try {
    raw = await fetcher(url);
  } catch (_) {
    raw = null;
  }
  if (raw == null || raw.isEmpty) return const [];
  return VTTSubtitleParser.parse(raw);
}
