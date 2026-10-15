// MARK: - ReferenceUILanguage — the reference-ui "current language" notifier
//
// Spec: `reference-ui-rendering/spec.md`
//   §「（Flutter）reference-ui 文案走字串表並支援執行中切換語言」
// Change: `rb-flutter-i18n-string-table`（design.md D4 / D5）; parity iOS `ReferenceUILanguage.swift`,
// Android `ReferenceUILanguage.kt`, RN `ReferenceUILanguage.ts`.
//
// The current language comes from the core (`LivebuySDK.currentLanguage`, a synchronous Dart cache
// kept up to date by `i18n-language-source-flutter-core`). This notifier:
//   • reads the core cache LIVE on every [current] read (no stale copy of its own), so a lookup made
//     while nothing is listening still sees the latest value;
//   • notifies its listeners when the core's `LivebuySDK.languageChanges` stream emits;
//   • holds AT MOST ONE subscription to that stream, ref-counted by its own listener count: the
//     first listener subscribes (and issues one `LivebuySDK.getLanguage()` re-read — natively
//     originated changes reach Dart only while a native listener is installed, so a Tier A surface
//     mounted on its own re-reads once on mount), the last listener removed cancels it;
//   • supports a test-only override ([setOverrideForTesting]). While an override is set the core is
//     never touched (no stream subscription, no native read) — the package's
//     `test/flutter_test_config.dart` pins every test to zh-TW this way.
//
// Widgets that render string-table copy rebuild through [referenceUILocalized], which listens to
// [referenceUILanguage] while mounted.

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart';

/// The 5 supported reference-ui languages (= core `LBLocaleCode` codes).
const List<String> referenceUILanguages = ['zh-TW', 'zh-CN', 'en', 'ms-MY', 'id-ID'];

/// Fallback language (`rb-flutter-i18n-fallback-en`: `en`, aligned with the core's last-resort
/// fallback): the missing-key table fallback, the normalisation target for unknown codes, and the
/// value returned when the language source cannot be read.
const String referenceUIFallbackLanguage = 'en';

/// Normalise any value to one of [referenceUILanguages] (unknown → [referenceUIFallbackLanguage],
/// i.e. en).
String normalizeReferenceUILanguage(Object? code) =>
    code is String && referenceUILanguages.contains(code) ? code : referenceUIFallbackLanguage;

/// Where the current language comes from. Production: the core (`LivebuySDK`); tests inject a fake.
abstract class ReferenceUILanguageSource {
  /// Synchronous current value (any code; normalised by the notifier).
  String current();

  /// Emits whenever the value actually changes.
  Stream<Object?> changes();

  /// One native re-read (fire-and-forget; failures are swallowed by the notifier).
  Future<void> refresh();
}

/// The production source: core `LivebuySDK.currentLanguage` / `languageChanges` / `getLanguage()`.
class CoreReferenceUILanguageSource implements ReferenceUILanguageSource {
  const CoreReferenceUILanguageSource();

  @override
  String current() => LivebuySDK.currentLanguage.code;

  @override
  Stream<Object?> changes() => LivebuySDK.languageChanges.map((c) => c.code);

  @override
  Future<void> refresh() => LivebuySDK.getLanguage();
}

/// Change notifier for the current reference-ui language (see file header).
class ReferenceUILanguage extends ChangeNotifier {
  ReferenceUILanguage(this._source, {String? initialOverride}) : _override = initialOverride;

  final ReferenceUILanguageSource _source;
  String? _override;
  int _listenerCount = 0;
  final List<VoidCallback> _tracked = <VoidCallback>[];
  StreamSubscription<Object?>? _subscription;

  /// The current language: the test override if set, else the core value (read live).
  String get current {
    final override = _override;
    if (override != null) return normalizeReferenceUILanguage(override);
    try {
      return normalizeReferenceUILanguage(_source.current());
    } catch (_) {
      return referenceUIFallbackLanguage;
    }
  }

  /// Number of live subscriptions to the source's change stream (0 or 1).
  @visibleForTesting
  int get sourceSubscriptionCount => _subscription == null ? 0 : 1;

  /// Number of registered listeners (mounted `referenceUILocalized` builders + others).
  @visibleForTesting
  int get listenerCountForTesting => _listenerCount;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _tracked.add(listener);
    _listenerCount++;
    if (_listenerCount == 1) _attach();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    // Only count down for a listener that was actually added (ChangeNotifier allows the same
    // callback to be added more than once, so track instances, not a set).
    if (!_tracked.remove(listener)) return;
    _listenerCount--;
    if (_listenerCount == 0) _detach();
  }

  /// Test-only: pin the language (`null` = follow the source). Notifies listeners; while an
  /// override is set the source is not subscribed.
  @visibleForTesting
  void setOverrideForTesting(String? language) {
    if (_override == language) return;
    _override = language;
    if (_listenerCount > 0) {
      if (language == null) {
        _attach();
      } else {
        _detach();
      }
    }
    notifyListeners();
  }

  void _attach() {
    if (_override != null || _subscription != null) return;
    try {
      _subscription = _source.changes().listen((_) => notifyListeners(), onError: (Object _) {});
    } catch (_) {
      _subscription = null;
      return;
    }
    try {
      _source.refresh().then<void>((_) {}, onError: (Object _) {});
    } catch (_) {
      // A synchronous throw from the re-read is swallowed too.
    }
  }

  void _detach() {
    final sub = _subscription;
    _subscription = null;
    sub?.cancel();
  }
}

/// Test-only: pin [referenceUILanguage] (`null` = follow the core). `test/flutter_test_config.dart`
/// pins every test in this package to zh-TW before any test runs.
@visibleForTesting
void pinReferenceUILanguageForTesting(String? language) =>
    referenceUILanguage.setOverrideForTesting(language);

/// The package-wide language notifier.
final ReferenceUILanguage referenceUILanguage =
    ReferenceUILanguage(const CoreReferenceUILanguageSource());

/// Wrap a widget's build so it re-runs on a language change (listens while mounted, stops on
/// unmount — so the core subscription is released when no surface is mounted). Use as
/// `Widget build(BuildContext context) => referenceUILocalized(() => _buildLocalized(context));`
/// — the original build keeps its own `context`.
Widget referenceUILocalized(Widget Function() build) => ListenableBuilder(
      listenable: referenceUILanguage,
      builder: (_, __) => build(),
    );
