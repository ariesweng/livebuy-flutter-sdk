// Dart-side type definitions for SDKConfig, mirroring
// `openspec/specs/sdk-config/spec.md` §"SDKConfig DTO 結構". The native side
// (iOS / Android) owns the cache and SWR logic; Dart only receives
// serialized snapshots via `LivebuySDK.getSdkConfig()` and the
// `SDK_CONFIG_REFRESHED` / `SDK_CONFIG_LOAD_FAILED` event payloads.

class LBSdkVisibility {
  final bool? chat;
  final bool? productOverlay;
  final bool? activityNotification;
  final bool? endScreen;
  final bool? videoInfoPanel;

  const LBSdkVisibility({
    this.chat,
    this.productOverlay,
    this.activityNotification,
    this.endScreen,
    this.videoInfoPanel,
  });

  factory LBSdkVisibility.fromMap(Map<Object?, Object?> map) {
    return LBSdkVisibility(
      chat: map['chat'] as bool?,
      productOverlay: map['productOverlay'] as bool?,
      activityNotification: map['activityNotification'] as bool?,
      endScreen: map['endScreen'] as bool?,
      videoInfoPanel: map['videoInfoPanel'] as bool?,
    );
  }
}

class LBSdkTheme {
  final String? primaryColor;
  final double? fontScale;

  const LBSdkTheme({this.primaryColor, this.fontScale});

  factory LBSdkTheme.fromMap(Map<Object?, Object?> map) {
    final fs = map['fontScale'];
    return LBSdkTheme(
      primaryColor: map['primaryColor'] as String?,
      fontScale: fs is num ? fs.toDouble() : null,
    );
  }
}

/// Schema v1 reserves `behavior` empty; this is exposed as a `Map` for
/// forward-compat (Phase 2 will populate it via `apply-sdk-config-behavior`).
class LBSdkBehavior {
  const LBSdkBehavior();
}

/// Opaque layout settings for the `livebuy_flutter_ui` template layer.
/// SDK core does NOT interpret or validate the map contents — values are
/// passed through as-is to the template layer at Widget/Player instantiate time.
class LBSdkTemplateLayout {
  final Map<String, Object?>? player;
  final Map<String, Object?>? widget;

  const LBSdkTemplateLayout({this.player, this.widget});

  factory LBSdkTemplateLayout.fromMap(Map<Object?, Object?> map) {
    final p = map['player'];
    final w = map['widget'];
    return LBSdkTemplateLayout(
      player: p is Map ? p.cast<String, Object?>() : null,
      widget: w is Map ? w.cast<String, Object?>() : null,
    );
  }
}

class SDKConfig {
  final int schemaVersion;
  final LBSdkVisibility? visibility;
  final LBSdkTheme? theme;
  final LBSdkBehavior? behavior;
  final LBSdkTemplateLayout? layout;
  final Map<String, Object?> extensions;

  const SDKConfig({
    required this.schemaVersion,
    this.visibility,
    this.theme,
    this.behavior,
    this.layout,
    this.extensions = const {},
  });

  /// SDK-built-in fallback ("no merchant settings"). Used when no cache
  /// exists AND `/sdk/config` fetch fails. Equivalent to v0.x
  /// decouple-ui-from-logic state — visibility / theme / behavior / layout all null.
  static const SDKConfig fallback = SDKConfig(schemaVersion: 1);

  factory SDKConfig.fromMap(Map<Object?, Object?> map) {
    final vis = map['visibility'];
    final theme = map['theme'];
    final beh = map['behavior'];
    final lay = map['layout'];
    final ext = (map['extensions'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
    return SDKConfig(
      schemaVersion: (map['schemaVersion'] as num?)?.toInt() ?? 1,
      visibility: vis is Map ? LBSdkVisibility.fromMap(vis.cast<Object?, Object?>()) : null,
      theme: theme is Map ? LBSdkTheme.fromMap(theme.cast<Object?, Object?>()) : null,
      behavior: beh is Map ? const LBSdkBehavior() : null,
      layout: lay is Map ? LBSdkTemplateLayout.fromMap(lay.cast<Object?, Object?>()) : null,
      extensions: ext,
    );
  }
}

/// Source values for `SDK_CONFIG_LOAD_FAILED` events. Per
/// `event-interceptor/spec.md`.
class LBSdkConfigLoadFailedSource {
  static const String configure = 'configure';
  static const String backgroundRefresh = 'background_refresh';
  static const String refresh = 'refresh';
  static const String cacheCorrupted = 'cache_corrupted';
}

class LBSdkConfigLoadFailedParams {
  final String source;
  final bool fellBackToDefault;
  final String errorCode;

  const LBSdkConfigLoadFailedParams({
    required this.source,
    required this.fellBackToDefault,
    required this.errorCode,
  });

  factory LBSdkConfigLoadFailedParams.fromMap(Map<String, Object?> params) {
    return LBSdkConfigLoadFailedParams(
      source: params['source'] as String? ?? 'unknown',
      fellBackToDefault: params['fell_back_to_default'] as bool? ?? false,
      errorCode: params['error_code'] as String? ?? 'unknown',
    );
  }
}

class LBSdkConfigRefreshedParams {
  /// `'background_refresh'` (cold start refresh) or `'refresh'` (host
  /// triggered `refreshConfig()`).
  final String source;

  /// Snapshot of `sdkConfig` immediately before the refresh. `null` only in
  /// the (currently unreachable) edge case where refresh is dispatched
  /// without a prior cached value — kept nullable for spec-schema symmetry.
  final SDKConfig? previous;

  /// Snapshot of `sdkConfig` after the refresh — the new value.
  final SDKConfig current;

  const LBSdkConfigRefreshedParams({
    required this.source,
    required this.current,
    this.previous,
  });

  factory LBSdkConfigRefreshedParams.fromMap(Map<String, Object?> params) {
    final prevRaw = params['previous'];
    final currRaw = params['current'];
    return LBSdkConfigRefreshedParams(
      source: params['source'] as String? ?? 'unknown',
      previous: prevRaw is Map
          ? SDKConfig.fromMap(prevRaw.cast<Object?, Object?>())
          : null,
      current: currRaw is Map
          ? SDKConfig.fromMap(currRaw.cast<Object?, Object?>())
          : SDKConfig.fallback,
    );
  }
}
