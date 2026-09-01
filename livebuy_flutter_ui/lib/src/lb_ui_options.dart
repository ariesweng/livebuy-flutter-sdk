import 'package:livebuy_flutter/livebuy_flutter.dart';

/// Host-supplied options passed to [LivebuyUI.install].
/// All fields are optional (null = "hands off" / use template default).
class LBUIOptions {
  final LBSdkVisibility? visibility;
  final LBSdkTheme? theme;
  final Map<String, Object?>? layoutPlayer;
  final Map<String, Object?>? layoutWidget;

  const LBUIOptions({
    this.visibility,
    this.theme,
    this.layoutPlayer,
    this.layoutWidget,
  });
}
