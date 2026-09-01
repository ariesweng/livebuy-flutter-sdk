import 'package:flutter/foundation.dart';

// await-toggle-and-notice-tab-template-state — VideoInfoPanel notice-tab model
// (behaviour / view-model layer; NO pixels).
//
// Spec ref: ui-template-foundation/spec.md
//   § "Default Template VideoInfoPanel 公告分頁 open-state 行為".
// Design: design.md D4.
//
// core stays headless: it owns `sys_notice` / `notice` on the channel and the
// "公告分頁任一不為空才開放" contract. This model holds the two text snapshots +
// an explicit `isOpen` and DERIVES `canOpen`. On Flutter the texts are HOST-FED
// (the host reads its channel and calls `handleChannelNotices`), like moment-state.

/// One host-bindable notice-tab snapshot. `canOpen` is DERIVED (never stored).
@immutable
class LBNoticeTabState {
  /// Whether the panel may open at all — `true` iff either text is non-empty.
  final bool canOpen;

  /// Whether the panel is currently expanded (only ever true when `canOpen`).
  final bool isOpen;
  final String systemNotice;
  final String notice;

  const LBNoticeTabState({
    required this.canOpen,
    required this.isOpen,
    required this.systemNotice,
    required this.notice,
  });

  @override
  bool operator ==(Object other) =>
      other is LBNoticeTabState &&
      other.canOpen == canOpen &&
      other.isOpen == isOpen &&
      other.systemNotice == systemNotice &&
      other.notice == notice;

  @override
  int get hashCode => Object.hash(canOpen, isOpen, systemNotice, notice);
}

/// Notice-tab view-model. A [ChangeNotifier] so the host binds with
/// `ListenableBuilder` and re-reads [current] on change.
class DefaultNoticeTab extends ChangeNotifier {
  String _systemNotice = '';
  String _notice = '';
  bool _isOpen = false;

  /// DERIVED: the panel may open iff either text is non-empty.
  bool get canOpen => _systemNotice.isNotEmpty || _notice.isNotEmpty;

  /// Host-bindable snapshot.
  LBNoticeTabState get current => LBNoticeTabState(
        canOpen: canOpen,
        isOpen: _isOpen,
        systemNotice: _systemNotice,
        notice: _notice,
      );

  /// Inject the latest notice texts (host-fed from its channel). If the panel
  /// becomes un-openable while open, `isOpen` is forced false (no illegal "open
  /// but not openable" state). Notifies iff anything changed.
  void injectNotices(String systemNotice, String notice) {
    if (systemNotice == _systemNotice && notice == _notice) return;
    _systemNotice = systemNotice;
    _notice = notice;
    if (!canOpen) _isOpen = false;
    notifyListeners();
  }

  /// Host opens the panel — only honoured when [canOpen] (un-openable → no-op).
  void openNoticeTab() {
    if (!canOpen || _isOpen) return;
    _isOpen = true;
    notifyListeners();
  }

  /// Host closes the panel.
  void closeNoticeTab() {
    if (!_isOpen) return;
    _isOpen = false;
    notifyListeners();
  }

  /// Reset on teardown / new video. Notifies iff anything was present.
  void clear() {
    if (_systemNotice.isEmpty && _notice.isEmpty && !_isOpen) return;
    _systemNotice = '';
    _notice = '';
    _isOpen = false;
    notifyListeners();
  }
}
