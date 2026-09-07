import 'package:livebuy_flutter/livebuy_flutter.dart' show LBPlayerChannelInfo;
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart' show isFinishedLiveReplay;

// channel_chrome — pure derivation of PlayerHeader top-bar chrome fields + the
// side-rail「聯繫商家」availability flag from the native `onChannelChange`
// projection (player-channel-chrome-wiring-reference-ui-flutter). PURE (no
// `DefaultPlayerTemplate` / `DefaultOperationRail` dependency of its own) — mirrors
// RN `react-native-reference-ui/src/container/channelChrome.ts` field-for-field.
//
// Parity source: iOS `ingestChannel(_ ch: LBChannel)`
// (`ios/Sources/LivebuyUI/Templates/Default/DefaultPlayerTemplate.swift:698-729`),
// which auto-derives `handleHeaderChrome(...)` + `handleRailEnablement(
// serviceLinkAvailable: !ch.shop.serviceLink.isEmpty, ...)` on every channel load.
// Flutter has no `ingestChannel` — `LivebuyPlayer`'s `onChannelChange` (wired in
// `live_buy_player.dart`'s `forwardChannelChangeToTemplate`) is the host-fed
// equivalent trigger point.
//
// 🔴 UNLIKE RN, this module does NOT decide how `serviceLinkAvailable` is combined
// with the OTHER THREE `handleRailEnablement` flags (`chatEnabled` /
// `subtitleAvailable` / `guestEditAvailable`) — Flutter's
// `DefaultOperationRail.handleEnablement` is a full 4-field OVERWRITE (all four
// parameters `required`, no partial-merge shape like RN's
// `Partial<LBSideRailEnablement>`). That merge-safety concern is NOT pure (it needs
// to read the template's current rail state) and lives in `live_buy_player.dart`'s
// `forwardChannelChangeToTemplate` instead — see that function's doc + this change's
// design.md Decision 1.

/// Derive the PlayerHeader top-bar chrome fields from a channel-change projection.
/// `hostName` ← `info.shopName` (parity iOS `ch.shop.name`); `isLive` ← strict
/// `info.liveStatus == 1` (mirrors iOS's `ch.liveStatus == 1` — upcoming (`0`), VOD,
/// and the `-1` unknown sentinel are all NOT live). `isFinishedLiveReplay` ← the
/// existing top-level pure function `isFinishedLiveReplay(info.type, info.liveStatus)`
/// (`flutter_ui`, `livebuy_flutter_ui` barrel export) — `channel-type-bridge-core-flutter`
/// added `info.type` to `LBPlayerChannelInfo` specifically so this derivation could be
/// completed here (isfinishedlivereplay-wiring-reference-ui-flutter). Returns a record —
/// a one-off structural value with no identity/methods, matching this file's existing
/// `({int eid, String keyword})?` convention rather than a new named class.
({
  String title,
  String hostName,
  String shopLogo,
  String shareUrl,
  bool isLive,
  bool isFinishedLiveReplay,
}) deriveHeaderChromeFields(LBPlayerChannelInfo info) => (
      title: info.title,
      hostName: info.shopName,
      shopLogo: info.shopLogo,
      shareUrl: info.shareUrl,
      isLive: info.liveStatus == 1,
      isFinishedLiveReplay: isFinishedLiveReplay(info.type, info.liveStatus),
    );

/// Derive the side-rail「聯繫商家」enabled flag from the channel's serviceLink
/// (parity iOS `!ch.shop.serviceLink.isEmpty`). `''` (no service link configured,
/// or `onChannelChange` not yet fired) → `false`.
bool deriveServiceLinkAvailable(String serviceLink) => serviceLink.isNotEmpty;
