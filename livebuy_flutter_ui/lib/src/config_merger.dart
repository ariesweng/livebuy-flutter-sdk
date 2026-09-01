import 'package:livebuy_flutter/livebuy_flutter.dart';
import 'lb_ui_options.dart';

/// Three-layer config merge for the LivebuyUI template system.
///
/// Priority (low → high):
///   Layer 1: Template defaults  (written in template source)
///   Layer 2: Host install() options  (LBUIOptions)
///   Layer 3: sdkConfig  (backend — always wins when non-null)
///
/// `null` means "hands off" (this layer does not express a preference).
/// `null` ≠ `false`.
class ConfigMerger {
  ConfigMerger._();

  // Visibility (Task 6.6)

  static bool effectiveVisibility({
    required bool? sdkValue,
    required bool? hostValue,
    required bool templateDefault,
  }) =>
      sdkValue ?? hostValue ?? templateDefault;

  // Layout map

  static Object? effectiveLayoutValue({
    required String key,
    required Map<String, Object?>? sdkMap,
    required Map<String, Object?>? hostMap,
    required Map<String, Object?> templateDefaults,
  }) {
    if (sdkMap != null && sdkMap.containsKey(key)) return sdkMap[key];
    if (hostMap != null && hostMap.containsKey(key)) return hostMap[key];
    return templateDefaults[key];
  }

  // Theme

  static String? effectivePrimaryColor({
    required SDKConfig sdkConfig,
    required LBUIOptions? hostOptions,
    required String? templateDefault,
  }) =>
      sdkConfig.theme?.primaryColor ??
      hostOptions?.theme?.primaryColor ??
      templateDefault;

  static double? effectiveFontScale({
    required SDKConfig sdkConfig,
    required LBUIOptions? hostOptions,
    required double? templateDefault,
  }) =>
      sdkConfig.theme?.fontScale ??
      hostOptions?.theme?.fontScale ??
      templateDefault;
}
