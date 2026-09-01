// chat_feed_view.dart — re-export shim.
//
// The family-2 surface 1 source lives in `chat_feed.dart` (the filename mandated
// by the rb-flutter-feed-win surface task). The container `feed_win_view.dart`
// SKELETON imports it under the `…_view.dart` name (parity with the family-1
// `operation_rail_view.dart` shim, and with the `win_entry_view.dart` /
// `win_claim_sheet_view.dart` sibling surfaces). This one-line shim re-exports
// `ChatFeedView` under that import path so the container's call-site import
// resolves WITHOUT editing the container (`feed_win_view.dart` is owned by the
// skeleton, not this surface).
export 'chat_feed.dart';
