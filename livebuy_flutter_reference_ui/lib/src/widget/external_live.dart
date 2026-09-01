import 'package:livebuy_flutter/livebuy_flutter.dart' show LBVideoItem;
import 'package:url_launcher/url_launcher.dart';

// external_live — external-platform live detection (rb-flutter-external-live-watch).
//
// Flutter sibling of iOS `ExternalLive.swift` / Android `ExternalLive.kt` / RN
// `ExternalLive.ts`. Spec: `openspec/specs/external-live-watch`.
//
// The shop's latest live can be an externally-hosted broadcast (a Facebook live).
// The backend returns it as an `LBVideoItem` whose `liveurl` is a `facebook.com`
// page (verified dev shop `Pw8PJ99J`, video `7epqqM`) — none of the SDK playback
// engines can play that. The FB URL exists ONLY on the widget-layer
// `LBVideoItem.liveurl`; the in-app player loads `/sdk/video`, whose `path` is a
// livebuy MP4 with no `liveurl`/`source`, so detection MUST happen here (the widget
// card / tap-routing layer) before the player opens.

/// Hosts whose lives are watched on their own platform (NOT in-app). Each entry
/// matches the host itself and any sub-domain. Extend to add YouTube / IG live.
const List<String> kExternalLiveHosts = ['facebook.com', 'fb.watch', 'fb.gg'];

/// Whether [urlString] points at an external broadcast platform — a PURE, POSITIVE
/// host allowlist. NEVER a negative "not `.m3u8`" rule: the backend may legitimately
/// return a non-`.m3u8` MP4/VOD `liveurl` for a normal in-app video (per
/// `widget-live-nested-decode`), so a negative rule would misclassify those and break
/// in-app playback. Sub-domain match is anchored on a leading dot (`host == base` OR
/// `host.endsWith('.$base')`) so look-alikes like `facebook.com.evil.example` and
/// `notfacebook.com` do NOT match.
bool isExternalLiveUrl(String urlString) {
  final host = Uri.tryParse(urlString)?.host.toLowerCase();
  if (host == null || host.isEmpty) return false;
  return kExternalLiveHosts.any((base) => host == base || host.endsWith('.$base'));
}

/// The external-platform watch URL when this live's `liveurl` is an external broadcast
/// (Facebook today), else null. Tapping such a live opens this URL externally.
String? externalLiveWatchUrl(LBVideoItem item) =>
    isExternalLiveUrl(item.liveurl) ? item.liveurl : null;

/// Default external open — launches [url] in the installed Facebook app / browser via
/// `url_launcher` (externalApplication mode). Fire-and-forget.
void _defaultOpenExternal(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return;
  // ignore: discarded_futures
  launchUrl(uri, mode: LaunchMode.externalApplication);
}

/// Wraps a host-wired [onTapVideo] into an external-aware callback: when the tapped
/// live is an external-platform broadcast, open its `liveurl` via [openExternal]
/// (default `url_launcher`) and do NOT invoke [onTapVideo] (so no in-app player is
/// presented); otherwise forward unchanged. [openExternal] is injectable so the
/// routing is unit-testable without launching anything.
void Function(LBVideoItem item) externalLiveAwareTap(
  void Function(LBVideoItem item)? onTapVideo, {
  void Function(String url)? openExternal,
}) {
  final open = openExternal ?? _defaultOpenExternal;
  return (item) {
    final url = externalLiveWatchUrl(item);
    if (url != null) {
      open(url);
    } else {
      onTapVideo?.call(item);
    }
  };
}
