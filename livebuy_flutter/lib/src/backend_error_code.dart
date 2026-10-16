// backend-error-code-flutter-core — internal helper (not exported from
// `package:livebuy_flutter/livebuy_flutter.dart`).
//
// Reads the backend `error_code` string that the native core forwards as
// `backend_error_code` (error maps, PlatformException details, event params).
// Only a non-empty String is kept; a missing key, null, a non-String value or
// an empty string all mean "no backend error code" (mirrors iOS
// `BackendErrorCode.parse`, which treats the same inputs as absent).

/// Returns [value] when it is a non-empty `String`, otherwise `null`.
String? backendErrorCodeOf(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

/// Reads `backend_error_code` from a map-shaped [source] (e.g. a
/// `PlatformException.details`). Non-map sources yield `null`.
String? backendErrorCodeFromDetails(Object? source) =>
    source is Map ? backendErrorCodeOf(source['backend_error_code']) : null;
