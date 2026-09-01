import 'package:flutter/foundation.dart';

// player-chrome-template — Default template OperationPanel side-rail view-model
// (behaviour / view-model layer; NO pixels).
//
// Spec ref: ui-template-foundation/spec.md
//   § "Default Template OperationPanel Side-Rail 狀態暴露"
//   (+ MODIFIED "Default Template Bindable State 變更通知").
// Design: design.md D2 / D6.
//
// core stays headless: it owns the 10 `simulate*` exits, the 250ms like throttle,
// `likePerformed` (the愛心 API actually-succeeded broadcast) and the service-link /
// guest-rename action machinery. This model surfaces ONLY the presentation state
// of the side-rail — an ordered `{ kind, enabled }` item list + bag-count +
// heart-burst tick + muted — so the host can draw `live-chrome.jsx` `LBLiveBottomBar`
// / `sdk-components.jsx` `LBPSideRail` / `LBPBagButton` / `LBPHeartBurst`. The
// template draws NO buttons / badges / heart animation and MUST NOT re-do action
// machinery (actions go through the host's per-view player `simulate*`).
//
// Flutter wiring note (D6): on Flutter the enablement flags + bag-count are
// HOST-FED (the host reads `channel` / `momentState` it owns and calls
// `handleEnablement` / `handleBagCount`, like moment-state / notice-tab); the
// heart-burst tick is driven by the unified `VIDEO_LIKE` / `LIKE_PERFORMED`
// bridge event (`handleLikePerformed`) OR a host-wired tick; `muted` mirrors the
// SAME source as PlayerHeader's muted (host echoes via `handleMuted` →
// `header.setMuted` AND `operationRail.setMuted`). View-model SHAPE +
// notification behaviour are four-platform identical; only ingestion differs.

/// Side-rail action kinds — the subset of core `simulate*` exits the Default
/// template surfaces (aligns `live-chrome.jsx` `LBLiveBottomBar` + `LBPSideRail`).
/// Each maps to an existing core action; the template adds NO new core action.
enum LBSideRailKind {
  goods,
  chat,
  like,
  share,
  subtitle,
  serviceLink,
  guestNameEdit,
  more,
}

/// One side-rail item: a [kind] + whether it is currently [enabled]. The host
/// draws the icon and routes the tap through the matching core `simulate*`.
@immutable
class LBSideRailItem {
  final LBSideRailKind kind;
  final bool enabled;

  const LBSideRailItem({required this.kind, required this.enabled});

  @override
  bool operator ==(Object other) =>
      other is LBSideRailItem && other.kind == kind && other.enabled == enabled;

  @override
  int get hashCode => Object.hash(kind, enabled);
}

/// OperationPanel side-rail view-model. A [ChangeNotifier] so the host binds with
/// `ListenableBuilder` and re-reads on change (parity with the moment view-models).
/// Each mutator is diff-then-notify: a real change fires EXACTLY ONE notification;
/// an unchanged value (e.g. the 5s products refresh delivering the same count, or
/// re-echoing the same enablement flags) does NOT notify.
class DefaultOperationRail extends ChangeNotifier {
  // Derived enablement flags. `goods` / `like` / `share` / `more` are ALWAYS
  // enabled (per spec); the four below are derived from reachable flags.
  bool _chatEnabled = false;
  bool _subtitleAvailable = false;
  bool _serviceLinkAvailable = false;
  bool _guestEditAvailable = false;

  int _bagCount = 0;
  int _heartBurstTick = 0;
  bool _muted = false; // unmuted / sound on by default (parity with PlayerHeader).

  /// Ordered side-rail items with derived `enabled` per kind. `goods` / `like` /
  /// `share` / `more` are always enabled; the rest reflect the latest flags.
  List<LBSideRailItem> get items => List.unmodifiable([
        const LBSideRailItem(kind: LBSideRailKind.goods, enabled: true),
        LBSideRailItem(kind: LBSideRailKind.chat, enabled: _chatEnabled),
        const LBSideRailItem(kind: LBSideRailKind.like, enabled: true),
        const LBSideRailItem(kind: LBSideRailKind.share, enabled: true),
        LBSideRailItem(
            kind: LBSideRailKind.subtitle, enabled: _subtitleAvailable),
        LBSideRailItem(
            kind: LBSideRailKind.serviceLink, enabled: _serviceLinkAvailable),
        LBSideRailItem(
            kind: LBSideRailKind.guestNameEdit, enabled: _guestEditAvailable),
        const LBSideRailItem(kind: LBSideRailKind.more, enabled: true),
      ]);

  /// Bag (shopping bag) badge count — DERIVED from the ProductOverlay view-model's
  /// products count (MUST NOT store a second products copy). Host echoes via
  /// [handleBagCount] alongside the products snapshot.
  int get bagCount => _bagCount;

  /// Monotonically increasing heart-burst tick. +1 each time the core愛心 API
  /// actually succeeds (`likePerformed` / unified `VIDEO_LIKE`). The host observes
  /// the increment to play the heart-burst animation; the template draws NONE.
  int get heartBurstTick => _heartBurstTick;

  /// Player mute flag — mirrors the SAME source as PlayerHeader's muted (single
  /// truth; host echoes both). Defaults false (unmuted / sound on by default —
  /// the core main playback starts UNMUTED per `player-default-unmuted-core`).
  bool get muted => _muted;

  /// host-bindable「LIVE 留言對訪客開放」signal (`live_status==1 && !(isGuest && guest_comment==0)`),
  /// the SAME source as the `.chat` rail item's `enabled` flag. reference-ui reads it
  /// (`template.operationRail.chatEnabled`) to gate the LIVE「留言」pill to a「請先登入」modal when a
  /// guest taps it on a `guest_comment==0` live (rb-flutter-live-comment-login-gate). Default false.
  bool get chatEnabled => _chatEnabled;

  /// Echo the derived enablement flags (host reads `channel` / `momentState`).
  /// Notifies only when at least one flag actually changed.
  @internal
  void handleEnablement({
    required bool chatEnabled,
    required bool subtitleAvailable,
    required bool serviceLinkAvailable,
    required bool guestEditAvailable,
  }) {
    if (chatEnabled == _chatEnabled &&
        subtitleAvailable == _subtitleAvailable &&
        serviceLinkAvailable == _serviceLinkAvailable &&
        guestEditAvailable == _guestEditAvailable) {
      return;
    }
    _chatEnabled = chatEnabled;
    _subtitleAvailable = subtitleAvailable;
    _serviceLinkAvailable = serviceLinkAvailable;
    _guestEditAvailable = guestEditAvailable;
    notifyListeners();
  }

  /// Update ONLY the LIVE chat-enabled flag (問題4 — a mid-live `guest_comment` change relayed via
  /// POLL_RECEIVED), preserving the other rail flags. Notifies only on a real change.
  @internal
  void handleChatEnabled(bool chatEnabled) {
    if (chatEnabled == _chatEnabled) return;
    _chatEnabled = chatEnabled;
    notifyListeners();
  }

  /// Update ONLY the subtitle-availability rail flag (flutter-subtitle-template-wiring),
  /// preserving the other rail flags — narrow-feed mirror of [handleChatEnabled], driven from
  /// the SAME channel-static signal that feeds `DefaultTemplate.subtitle.available`
  /// (`DefaultTemplate.handleSubtitleChannelInfo`), bypassing the not-yet-wired-in-production
  /// `handleEnablement` path (parity iOS `handleMomentState`'s single `s.subtitleAvailable`
  /// feeding both `subtitle.handle(...)` and `operationRail.handleEnablement(...)`). Notifies
  /// only on a real change.
  @internal
  void handleSubtitleAvailable(bool subtitleAvailable) {
    if (subtitleAvailable == _subtitleAvailable) return;
    _subtitleAvailable = subtitleAvailable;
    notifyListeners();
  }

  /// Echo the bag-count (= products.count). Notifies only on a real change.
  @internal
  void handleBagCount(int count) {
    if (count == _bagCount) return;
    _bagCount = count;
    notifyListeners();
  }

  /// One core `likePerformed` arrived (愛心 API succeeded) → bump the burst tick.
  /// ALWAYS notifies (the tick monotonically increases per like).
  @internal
  void handleLikePerformed() {
    _heartBurstTick += 1;
    notifyListeners();
  }

  /// Echo the player mute flag (host echoes alongside `controller.setMuted` AND
  /// PlayerHeader.muted — single truth). Notifies only on change.
  @internal
  void setMuted(bool value) {
    if (value == _muted) return;
    _muted = value;
    notifyListeners();
  }

  /// Reset on teardown / new video. Notifies iff anything non-default cleared
  /// (parity with DefaultNoticeTab.clear). The heart-burst tick is intentionally
  /// NOT reset (it is a monotonic animation beat, not view-state).
  ///
  /// `_muted` is intentionally PRESERVED across `clear()` (NOT reset) — the mute
  /// preference persists across an in-place switch (`userMuted` single source,
  /// `mute-preference-persist-across-switch-core`; the Flutter native core keeps
  /// `userMuted` across switch). It is excluded from the `hadState` change
  /// detection and never re-written below, mirroring the monotonic `heartBurstTick`
  /// preservation. NOTE: `clear()` currently has NO caller in the repo — the
  /// in-place switch path (`DefaultPlayerTemplate.handleVideoSwitch()`) only clears
  /// `feed` + `winClaim`, not this rail — so this preservation is a defensive
  /// parity alignment (if a host / future switch wiring calls `clear()`, the mute
  /// presentation MUST NOT be reset).
  void clear() {
    final hadState = _chatEnabled ||
        _subtitleAvailable ||
        _serviceLinkAvailable ||
        _guestEditAvailable ||
        _bagCount != 0;
    if (!hadState) return;
    _chatEnabled = false;
    _subtitleAvailable = false;
    _serviceLinkAvailable = false;
    _guestEditAvailable = false;
    _bagCount = 0;
    notifyListeners();
  }
}
