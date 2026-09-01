// LBRoute — endpoint constants for type-check parity with native.
//
// Native iOS / Android SDKs own the **authoritative** endpoint paths via
// their own LBRoute enum / sealed class. The Flutter plugin doesn't make
// HTTP calls directly — the native side does. This file exists purely to
// let Dart code (and host Flutter apps) reference the canonical path
// strings, without re-declaring magic literals.
//
// Per api-version-resilience §Endpoint 集中註冊表 `LBRoute` §「四端 LBRoute 一致」.

enum LBRoute {
  video('/sdk/video'),
  widget('/sdk/widget'),
  widgetLive('/sdk/widget/live'),
  videoMessages('/sdk/video/messages'),
  videoGoods('/sdk/video/goods'),
  videoComments('/sdk/video/comments'),
  videoCommentsub('/sdk/video/commentsub'),
  videoCheckname('/sdk/video/checkname'),
  videoSubscribe('/sdk/video/subscribe'),
  videoLike('/sdk/video/like'),
  videoAddcart('/sdk/video/addcart'),
  // addcart-track ④ — token 平台結帳前回報 cart token (canonical path mirrored;
  // native SDK owns the HTTP via reportCartTrack).
  videoAddcartTrack('/sdk/video/addcart/track'),
  goodsAwait('/sdk/goods/await'),
  goodsNotice('/sdk/goods/notice'),
  videoClaim('/sdk/video/claim'),
  // flutter-lbroute-eventstay-parity — event-stay heartbeat. Canonical path mirrored for four-end
  // LBRoute parity (Flutter never calls it directly; the native SDK owns the HTTP via reportEventStay).
  videoEventstay('/sdk/video/eventstay'),
  login('/sdk/login'),
  log('/sdk/log'),
  logConfig('/sdk/log_config'),
  sdkConfig('/sdk/config');

  final String path;
  const LBRoute(this.path);
}
