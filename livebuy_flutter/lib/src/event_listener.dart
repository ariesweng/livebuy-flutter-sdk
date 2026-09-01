import 'lb_event.dart';

// MARK: - LBSdkEvent

/// One event delivered to your [LBEventListener] handler.
///
/// [eventName] is one of the [LBEvent] constants. [params] holds the event-specific
/// payload (see the migration guide for the schema of each event). [shareContext]
/// is non-null only for `VIDEO_SHARE_REQUEST`; mutate `shareUrl` / `title` on it
/// inside your handler and the SDK will pick up the override.
class LBSdkEvent {
  final String eventName;
  final Map<String, Object?> params;
  final LBShareContext? shareContext;

  const LBSdkEvent({
    required this.eventName,
    required this.params,
    this.shareContext,
  });
}

/// Mutable share-content override passed with [LBEvent.videoShareRequest].
/// Reassign [shareUrl] / [title] in your handler to override what the SDK shares.
class LBShareContext {
  String shareUrl;
  String title;
  LBShareContext({required this.shareUrl, required this.title});
}

// MARK: - Reply builders

/// Reply your handler returns from [LBEventListener].
///
/// Use the static constructors instead of building maps by hand — the map keys
/// are part of the native bridge contract and easy to mistype.
class LBEventReply {
  final Map<String, Object?> _map;

  const LBEventReply._(this._map);

  /// For sync-interceptor events: tell the SDK "I'm handling this, skip your default UI."
  /// Applies to `AUTH_REQUIRED`, `PRODUCT_CLICK`, `VIDEO_SHARE_REQUEST`, `INFO_CUSTOMER_SERVICE`.
  static const LBEventReply intercept = LBEventReply._({'result': true});

  /// For sync-interceptor events: tell the SDK to show its default UI.
  static const LBEventReply passthrough = LBEventReply._({'result': false});

  /// For notification events. The return value is ignored — returning [acknowledge]
  /// is conventional but functionally a no-op.
  static const LBEventReply acknowledge = LBEventReply._({'result': false});

  /// Vestigial (cart-add-tier2-unify). In Tier 2 `CART_ADD_REQUEST` is a
  /// notification (fired after a successful `addToCart`) — the native side does NOT
  /// wait for a reply, so this resolves nothing. Close the add-to-cart loop via
  /// `LivebuySDK.reportCartTrack` + the host order webhook instead. Retained for ABI
  /// compat; removed next major.
  @Deprecated(
    'Tier 2 CART_ADD_REQUEST is a notification — no reply is awaited; '
    'use LivebuySDK.reportCartTrack + order webhook. Removed next major.',
  )
  factory LBEventReply.cartSuccess(String appTrackCode) {
    return LBEventReply._({
      'result': true,
      'status': 'success',
      'appTrackCode': appTrackCode,
    });
  }

  /// Vestigial (cart-add-tier2-unify) — see [LBEventReply.cartSuccess].
  @Deprecated(
    'Tier 2 CART_ADD_REQUEST is a notification — no reply is awaited; '
    'use LivebuySDK.reportCartTrack + order webhook. Removed next major.',
  )
  factory LBEventReply.cartFailure({required String errorCode, required String msg}) {
    return LBEventReply._({
      'result': true,
      'status': 'failure',
      'errorCode': errorCode,
      'msg': msg,
    });
  }

  Map<String, Object?> toMap() => _map;
}

// MARK: - Handler typedef

/// Async handler installed via `LivebuySDK.setListener(...)`.
/// Return one of the [LBEventReply] constants or factories.
///
/// cart-add-tier2-unify: `CART_ADD_REQUEST` is now a notification (fired after a
/// successful `addToCart`) — no reply is awaited. Close the add-to-cart loop via
/// `LivebuySDK.reportCartTrack` + the host order webhook instead of replying.
typedef LBEventListener = Future<LBEventReply> Function(LBSdkEvent event);
