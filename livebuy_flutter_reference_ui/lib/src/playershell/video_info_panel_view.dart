// video_info_panel_view.dart — re-export shim.
//
// The family-1 surface 3 source lives in `video_info_panel.dart` (the filename
// mandated by the rb-flutter-player-shell surface task). The container
// `player_shell_view.dart` skeleton imports it under the `…_view.dart` name
// (parity with `player_header_bar_view.dart`), so this one-line shim re-exports
// `VideoInfoPanelView` (+ its demo seeds) under that import path. The shim keeps
// the container's call-site import resolvable WITHOUT editing the container
// (`player_shell_view.dart` is owned by the skeleton, not this surface).
export 'video_info_panel.dart';
