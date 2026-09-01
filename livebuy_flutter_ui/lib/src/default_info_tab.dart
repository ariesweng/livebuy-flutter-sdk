import 'package:flutter/foundation.dart';

import 'default_moment_state.dart';
import 'default_notice_tab.dart';

// player-chrome-template — Default template VideoInfoPanel info-tab view-model +
// two-tab switching (behaviour / view-model layer; NO pixels).
//
// Spec ref: ui-template-foundation/spec.md
//   § "Default Template VideoInfoPanel Info-Tab 與分頁切換狀態暴露"
//   (+ MODIFIED "Default Template Bindable State 變更通知").
// Design: design.md D4 / D6.
//
// core stays headless: it owns `channel` data + the subscribe API + the
// `simulateSubscribeTap` exit + the「公告皆空則不顯示」notice contract. This model
// surfaces the「直播資訊」tab fields { title, publishAt, shopName, shopIntro,
// shopLogo, isSubscribed } + a two-tab `activeTab` { info | notice } + `selectTab`.
// The template draws NO tabs (host draws `LBPSheetHeader` / `LBPBottomSheet`).
//
// SINGLE-SOURCE invariants (D4, Risks R2 / R4):
//   - `isSubscribed` is READ from the EXISTING PlayerHeader view-model
//     (`DefaultPlayerHeaderState.isSubscribed`) — NOT stored here — so PlayerHeader
//     and VideoInfoPanel never diverge (subscribe success updates one truth).
//   - `selectTab(notice)` is honoured ONLY when the EXISTING notice-tab
//     (`DefaultNoticeTab.canOpen`) is true; otherwise it is a no-op. When the
//     current tab is `notice` and `canOpen` turns false (公告轉空), the active tab
//     auto-falls-back to `info` (never stuck on an unselectable tab).
//
// Flutter wiring note (D6): the info-tab fields are HOST-FED (the host reads its
// channel and calls `handleInfo`), like moment-state / notice-tab. The host wires
// the notice-tab so `canOpen` reflects its channel notices (via
// `DefaultPlayerTemplate.handleChannelNotices`). `info` tab is always selectable.

/// The two tabs of VideoInfoPanel. `info` is the「直播資訊」tab (always selectable);
/// `notice` is the existing 公告 tab (selectable only when notice-tab `canOpen`).
enum LBInfoPanelTab { info, notice }

/// One host-bindable info-tab field snapshot. `isSubscribed` is NOT stored here —
/// it is read live from PlayerHeader (single truth, D4).
@immutable
class LBInfoTabFields {
  final String title;
  final String publishAt;
  final String shopName;
  final String shopIntro;
  final String shopLogo;

  const LBInfoTabFields({
    this.title = '',
    this.publishAt = '',
    this.shopName = '',
    this.shopIntro = '',
    this.shopLogo = '',
  });

  @override
  bool operator ==(Object other) =>
      other is LBInfoTabFields &&
      other.title == title &&
      other.publishAt == publishAt &&
      other.shopName == shopName &&
      other.shopIntro == shopIntro &&
      other.shopLogo == shopLogo;

  @override
  int get hashCode =>
      Object.hash(title, publishAt, shopName, shopIntro, shopLogo);
}

/// VideoInfoPanel info-tab + two-tab-switch view-model. A [ChangeNotifier] so the
/// host binds with `ListenableBuilder`. Holds the「直播資訊」fields and the active
/// tab; reads `isSubscribed` from the injected [DefaultPlayerHeaderState] (single
/// truth) and gates the `notice` tab on the injected [DefaultNoticeTab.canOpen].
///
/// IMPORTANT: this view-model subscribes to the notice-tab's notifications so a
/// `canOpen` true→false transition (公告轉空) auto-falls-back `activeTab` to `info`
/// even when the host did not call `selectTab`.
class DefaultInfoTab extends ChangeNotifier {
  final DefaultPlayerHeaderState _header;
  final DefaultNoticeTab _noticeTab;

  LBInfoTabFields _fields = const LBInfoTabFields();
  LBInfoPanelTab _activeTab = LBInfoPanelTab.info;

  DefaultInfoTab({
    required DefaultPlayerHeaderState header,
    required DefaultNoticeTab noticeTab,
  })  : _header = header,
        _noticeTab = noticeTab {
    // Auto-fall-back: when the notice-tab becomes un-openable while the info-panel
    // is showing the notice tab, drop back to `info` (D4 — never stuck on an
    // unselectable tab). This listener is the ONLY cross-view-model wiring.
    _noticeTab.addListener(_onNoticeChanged);
  }

  void _onNoticeChanged() {
    if (_activeTab == LBInfoPanelTab.notice && !_noticeTab.canOpen) {
      _activeTab = LBInfoPanelTab.info;
      notifyListeners();
    }
  }

  /// The「直播資訊」fields (host-fed via [handleInfo]).
  LBInfoTabFields get fields => _fields;

  /// The currently active tab (initial [LBInfoPanelTab.info]).
  LBInfoPanelTab get activeTab => _activeTab;

  /// Live subscribe state — READ from PlayerHeader (single truth, D4). Subscribe
  /// success updates `header.setSubscribed`, which both PlayerHeader AND this
  /// info-tab read; they never diverge.
  bool get isSubscribed => _header.isSubscribed;

  /// Whether the `notice` tab is currently selectable (mirrors notice-tab canOpen).
  bool get noticeSelectable => _noticeTab.canOpen;

  /// Feed the「直播資訊」fields (host reads its `channel`: title / publish_at /
  /// shop.name / shop.intro / shop.logo). EXCLUDES `description` (LBChannel has no
  /// such field — R6). Notifies only on a real change.
  @internal
  void handleInfo(LBInfoTabFields fields) {
    if (fields == _fields) return;
    _fields = fields;
    notifyListeners();
  }

  /// Host taps a tab. `info` is ALWAYS selectable. `notice` is selectable ONLY
  /// when notice-tab `canOpen` is true; otherwise this is a no-op (activeTab kept).
  /// Notifies only on a real change.
  void selectTab(LBInfoPanelTab tab) {
    if (tab == LBInfoPanelTab.notice && !_noticeTab.canOpen) return; // no-op
    if (tab == _activeTab) return;
    _activeTab = tab;
    notifyListeners();
  }

  @override
  void dispose() {
    _noticeTab.removeListener(_onNoticeChanged);
    super.dispose();
  }
}
