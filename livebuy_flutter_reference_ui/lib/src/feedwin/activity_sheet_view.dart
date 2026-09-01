// activity_sheet_view.dart — re-export shim.
//
// The family-2 抽獎活動彈窗 source lives in `activity_sheet.dart` (parity with
// `win_entry.dart` / `win_claim_sheet.dart`'s own naming — the surface's real
// filename doesn't carry the `_view` suffix). The container `feed_win_view.dart`
// imports it under the `…_view.dart` name (parity with `win_entry_view.dart` /
// `win_claim_sheet_view.dart`), so this one-line shim re-exports
// `ActivitySheetView` under that import path.
export 'activity_sheet.dart';
