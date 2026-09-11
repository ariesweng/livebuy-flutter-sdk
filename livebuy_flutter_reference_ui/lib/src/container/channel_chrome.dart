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
/// completed here (isfinishedlivereplay-wiring-reference-ui-flutter). `isFlashSale` ←
/// `info.isFlashSale` verbatim raw passthrough (`channel-flash-sale-flag-core-flutter` added
/// the field to `LBPlayerChannelInfo`; `channel-flash-sale-flag-template-flutter` added the
/// `handleHeaderChrome(isFlashSale:)` parameter this derivation now actually feeds —
/// rb-flutter-flash-sale-live-signal-wiring). Independent of `isLive` /
/// `isFinishedLiveReplay` — a flash-sale channel can be live, VOD, or a finished replay, and
/// this field does not gate or interact with either. Returns a record — a one-off
/// structural value with no identity/methods, matching this file's existing
/// `({int eid, String keyword})?` convention rather than a new named class.
({
  String title,
  String hostName,
  String shopLogo,
  String shareUrl,
  bool isLive,
  bool isFinishedLiveReplay,
  bool isFlashSale,
}) deriveHeaderChromeFields(LBPlayerChannelInfo info) => (
      title: info.title,
      hostName: info.shopName,
      shopLogo: info.shopLogo,
      shareUrl: info.shareUrl,
      isLive: info.liveStatus == 1,
      isFinishedLiveReplay: isFinishedLiveReplay(info.type, info.liveStatus),
      isFlashSale: info.isFlashSale,
    );

/// Derive the side-rail「聯繫商家」enabled flag from the channel's serviceLink
/// (parity iOS `!ch.shop.serviceLink.isEmpty`). `''` (no service link configured,
/// or `onChannelChange` not yet fired) → `false`.
bool deriveServiceLinkAvailable(String serviceLink) => serviceLink.isNotEmpty;

/// flutter-rail-enablement-channel-derive-reference-ui — derive the「留言」rail item's
/// enabled flag from THIS channel-change tick's own `liveStatus` / `guestComment`
/// (parity iOS `ingestChannel`'s `ch.liveStatus == 1 && ch.guestComment == 1`). Same
/// formula `TemplateAttachment`'s existing `LBEvent.pollReceived` case already uses
/// (`template_attachment.dart`) — this just makes it available at channel-load time too,
/// instead of only on the next `POLL_RECEIVED` (which never fires for a finished-live
/// replay — native `PollManager` only runs while `liveStatus == 1`).
bool deriveChatEnabled(int liveStatus, int guestComment) =>
    liveStatus == 1 && guestComment == 1;

/// flutter-rail-enablement-channel-derive-reference-ui — derive the「設定暱稱」rail item's
/// enabled flag from THIS channel-change tick's own `guestComment` (parity iOS
/// `ingestChannel`'s `ch.guestComment == 1`, deliberately narrower than
/// [deriveChatEnabled] — no `liveStatus` gate). Same formula `TemplateAttachment`'s
/// existing `LBEvent.pollReceived` case already uses.
bool deriveGuestEditAvailable(int guestComment) => guestComment == 1;
