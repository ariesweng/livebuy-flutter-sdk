// operation_rail_view.dart — re-export shim.
//
// The family-1 surface 2 source lives in `operation_rail.dart` (the filename
// mandated by the rb-flutter-player-shell surface task). The container
// `player_shell_view.dart` skeleton imports it under the `…_view.dart` name
// (parity with `player_header_bar_view.dart` / `video_info_panel_view.dart`), so
// this one-line shim re-exports `OperationRailView` (+ its `railIconFor` /
// `badgeText` helpers) under that import path. The shim keeps the container's
// call-site import resolvable WITHOUT editing the container (`player_shell_view
// .dart` is owned by the skeleton, not this surface).
export 'operation_rail.dart';
