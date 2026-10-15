// i18n-language-source-flutter-core — Dart-side synchronous cache of the
// native core's current language (iOS `Livebuy.currentLanguage` / Android
// `LivebuySDK.currentLanguage`).
//
// Flutter wraps the native core on both platforms, so the language priority
// (host > device system language > API `lang` > `en`) and the
// `LANGUAGE_CHANGED` dispatch timing are inherited from native. What Flutter
// lacked was a way for Dart (e.g. `livebuy_flutter_reference_ui`) to READ the
// current language. This class keeps a synchronous snapshot, refreshed by:
//   - an async native read (`fetch`, i.e. method channel `getLanguage`), and
//   - the unified `LANGUAGE_CHANGED { from, to }` event (`to` is applied).
//
// Race rule (sequence number, "newest wins"; parity RN `languageCache.ts`):
// every native read captures the sequence value at issue time, and every
// applied event bumps the sequence. A read's response is applied only if no
// event arrived and no newer read was issued in between, so a stale read that
// resolves after a `LANGUAGE_CHANGED` can never overwrite the newer value.
//
// Kept as a plain class with an injected `fetch` so it is unit-testable
// without a platform channel; `LivebuySDK` wires the singleton to the real
// `tv.livebuy/sdk` method channel.

import 'dart:async';

import 'models.dart';

/// Native read used by [LBLanguageCache.refresh]. Expected to complete with
/// one of the 5 supported locale code strings.
typedef LBLanguageFetch = Future<Object?> Function();

class LBLanguageCache {
  LBLanguageCache(this._fetch);

  /// Initial value before any native read / event arrives (= native fallback,
  /// `en` since `i18n-fallback-en-flutter-core`).
  static const LBLocaleCode fallback = LBLocaleCode.en;

  final LBLanguageFetch _fetch;
  LBLocaleCode _current = fallback;
  int _seq = 0;
  final StreamController<LBLocaleCode> _changes =
      StreamController<LBLocaleCode>.broadcast();

  /// Current cached value (synchronous).
  LBLocaleCode get current => _current;

  /// Broadcast stream that emits the new value only when [current] actually
  /// changes (same value → no emission). Does not replay the current value.
  Stream<LBLocaleCode> get changes => _changes.stream;

  /// Issue a native read. Completes with the native value; applies it to the
  /// cache unless a newer read or an event superseded it. Completes with an
  /// error (never throws synchronously) when the read fails or the native
  /// value is not one of the 5 supported codes — the cache is left untouched.
  Future<LBLocaleCode> refresh() async {
    final issuedAt = ++_seq;
    final raw = await _fetch();
    final value = raw is String ? LBLocaleCode.fromCode(raw) : null;
    if (value == null) {
      throw FormatException('getLanguage: unexpected native value $raw');
    }
    if (issuedAt == _seq) _set(value);
    return value;
  }

  /// [refresh] with every failure swallowed (cache keeps its value).
  void refreshSilently() {
    refresh().then<void>((_) {}, onError: (Object _) {});
  }

  /// Apply a `LANGUAGE_CHANGED` event's `to` (ignored unless it is one of the
  /// 5 supported codes). Always wins over in-flight reads.
  void applyEvent(Object? to) {
    final value = to is String ? LBLocaleCode.fromCode(to) : null;
    if (value == null) return;
    _seq++; // invalidate every in-flight read
    _set(value);
  }

  void _set(LBLocaleCode next) {
    if (next == _current) return;
    _current = next;
    _changes.add(next);
  }
}
