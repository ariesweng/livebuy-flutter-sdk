import 'package:flutter/foundation.dart';

// await-toggle-and-notice-tab-template-state — goods-tracking dual-switch model
// (behaviour / view-model layer; NO pixels).
//
// Spec ref: ui-template-foundation/spec.md
//   § "Default Template 到貨追蹤與補貨通知雙開關狀態行為".
// Design: design.md D1 / D2 / D3.
//
// core stays headless: it owns the two independent endpoints (`setAwaitGoods`
// type=1 / `setNoticeGoods` type=2) and the authoritative `AWAIT_GOODS_CHANGED` /
// `NOTICE_GOODS_CHANGED` broadcasts. This model maps them into a per-`goodsGpn`
// pair of INDEPENDENT (non-mutually-exclusive) flags. Flutter's `LBProduct` does
// NOT carry `isAwait` / `isAwaitNotice`, so the host SEEDS initial flags via the
// template (host-wired typed source, exactly like moment-state / notice text).

/// Host-wired delegate for a toggle → core `setAwaitGoods` / `setNoticeGoods`.
typedef GoodsTrackingSetter = void Function(String goodsGpn, bool enabled);

/// One host-bindable per-product flag pair. Independent (non-mutually-exclusive).
@immutable
class LBGoodsTrackingFlags {
  /// 到貨追蹤 (await, type=1) — mirrors `LBProduct.isAwait`.
  final bool awaitEnabled;

  /// 補貨通知 (notice, type=2) — mirrors `LBProduct.isAwaitNotice`.
  final bool noticeEnabled;

  const LBGoodsTrackingFlags({
    required this.awaitEnabled,
    required this.noticeEnabled,
  });

  @override
  bool operator ==(Object other) =>
      other is LBGoodsTrackingFlags &&
      other.awaitEnabled == awaitEnabled &&
      other.noticeEnabled == noticeEnabled;

  @override
  int get hashCode => Object.hash(awaitEnabled, noticeEnabled);
}

/// Goods-tracking view-model. A [ChangeNotifier] so the host binds with
/// `ListenableBuilder` and re-reads on change (parity with [DefaultAuthGate]).
/// Optimistic on toggle; corrected by the authoritative broadcasts.
class DefaultGoodsTracking extends ChangeNotifier {
  final Map<String, LBGoodsTrackingFlags> _flags = {};
  final GoodsTrackingSetter _setAwait;
  final GoodsTrackingSetter _setNotice;

  DefaultGoodsTracking({
    GoodsTrackingSetter? setAwait,
    GoodsTrackingSetter? setNotice,
  })  : _setAwait = setAwait ?? ((_, __) {}),
        _setNotice = setNotice ?? ((_, __) {});

  /// Current flags for [goodsGpn] (both false when unseen).
  LBGoodsTrackingFlags flagsFor(String goodsGpn) =>
      _flags[goodsGpn] ??
      const LBGoodsTrackingFlags(awaitEnabled: false, noticeEnabled: false);

  bool awaitEnabled(String goodsGpn) => flagsFor(goodsGpn).awaitEnabled;
  bool noticeEnabled(String goodsGpn) => flagsFor(goodsGpn).noticeEnabled;

  /// Seed the INITIAL flags from `LBProduct.isAwait` / `isAwaitNotice` (0/1).
  /// Non-clobbering: a known key is NOT overwritten (a stale re-seed MUST NOT
  /// clobber an optimistic / broadcast-corrected value). Notifies iff it set a
  /// new key.
  void seed(String goodsGpn, {required int isAwait, required int isAwaitNotice}) {
    if (_flags.containsKey(goodsGpn)) return;
    _flags[goodsGpn] = LBGoodsTrackingFlags(
      awaitEnabled: isAwait != 0,
      noticeEnabled: isAwaitNotice != 0,
    );
    notifyListeners();
  }

  /// Toggle 到貨追蹤 (type=1): optimistically flip ONLY the await flag, notify,
  /// then delegate to `setAwaitGoods`. MUST NOT touch the notice flag.
  void toggleAwait(String goodsGpn) {
    final cur = flagsFor(goodsGpn);
    final next = !cur.awaitEnabled;
    _flags[goodsGpn] =
        LBGoodsTrackingFlags(awaitEnabled: next, noticeEnabled: cur.noticeEnabled);
    notifyListeners();
    _setAwait(goodsGpn, next);
  }

  /// Toggle 補貨通知 (type=2): optimistically flip ONLY the notice flag.
  void toggleNotice(String goodsGpn) {
    final cur = flagsFor(goodsGpn);
    final next = !cur.noticeEnabled;
    _flags[goodsGpn] =
        LBGoodsTrackingFlags(awaitEnabled: cur.awaitEnabled, noticeEnabled: next);
    notifyListeners();
    _setNotice(goodsGpn, next);
  }

  /// `AWAIT_GOODS_CHANGED` correction (authoritative). Touches ONLY the await
  /// flag; notifies iff it changed.
  void applyAwaitBroadcast(String goodsGpn, bool enabled) {
    final cur = flagsFor(goodsGpn);
    if (cur.awaitEnabled == enabled) return;
    _flags[goodsGpn] =
        LBGoodsTrackingFlags(awaitEnabled: enabled, noticeEnabled: cur.noticeEnabled);
    notifyListeners();
  }

  /// `NOTICE_GOODS_CHANGED` correction (authoritative). Touches ONLY the notice flag.
  void applyNoticeBroadcast(String goodsGpn, bool enabled) {
    final cur = flagsFor(goodsGpn);
    if (cur.noticeEnabled == enabled) return;
    _flags[goodsGpn] =
        LBGoodsTrackingFlags(awaitEnabled: cur.awaitEnabled, noticeEnabled: enabled);
    notifyListeners();
  }

  /// Reset on teardown / new video. Notifies iff anything was present.
  void clear() {
    if (_flags.isEmpty) return;
    _flags.clear();
    notifyListeners();
  }
}
