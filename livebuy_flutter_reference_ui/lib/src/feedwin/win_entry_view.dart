// win_entry_view.dart — re-export shim.
//
// The family-2 surface 2 source lives in `win_entry.dart` (the filename mandated
// by the rb-flutter-feed-win surface task — parity with the Android `WinEntry.kt`
// filename). The container `feed_win_view.dart` skeleton imports it under the
// `…_view.dart` name (parity with `chat_feed_view.dart` /
// `win_claim_sheet_view.dart`), so this one-line shim re-exports `WinEntryView`
// under that import path. The shim keeps the container's call-site import
// resolvable WITHOUT editing the container (`feed_win_view.dart` is owned by
// the skeleton, not this surface).
export 'win_entry.dart';
