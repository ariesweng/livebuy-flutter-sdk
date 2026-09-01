// win_claim_sheet_view.dart — re-export shim.
//
// The family-2 surface 3 source lives in `win_claim_sheet.dart` (the filename
// mandated by the rb-flutter-feed-win surface task — parity with the Android
// `WinClaimSheet.kt` filename). The container `feed_win_view.dart` skeleton imports
// it under the `…_view.dart` name (parity with `win_entry_view.dart` /
// `chat_feed_view.dart`), so this one-line shim re-exports `WinClaimSheetView` under
// that import path. The shim keeps the container's call-site import resolvable
// WITHOUT editing the container (`feed_win_view.dart` is owned by the skeleton, not
// this surface).
export 'win_claim_sheet.dart';
