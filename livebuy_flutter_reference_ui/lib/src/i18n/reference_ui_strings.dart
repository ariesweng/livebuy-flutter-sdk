// MARK: - ReferenceUIStrings — reference-ui 自帶字串表的查表入口
//
// Spec: `reference-ui-rendering/spec.md`
//   §「（Flutter）reference-ui 文案走字串表並支援執行中切換語言」
// Change: `rb-flutter-i18n-string-table`（design.md 有 key 清單、Flutter 獨有 key、zh-TW 差異清單與
// 命名規則）；key / 譯文 / 占位符與 iOS lead `rb-ios-i18n-string-table` 一致。
//
// reference-ui 的使用者可見文案一律經 `ReferenceUIStrings.text(key, args)` 依「目前語言」查表：
//   • 目前語言 = `referenceUILanguage.current`（來源是 core 的 `LivebuySDK.currentLanguage`，經
//     `LivebuySDK.languageChanges` 即時更新，見 `reference_ui_language.dart`）。要在語言改變時重繪的
//     widget，build 必須經 `referenceUILocalized(...)` 包一層。
//   • 找不到 key 時依序 fallback：目前語言表 → en 表（`referenceUIFallbackLanguage`，
//     `rb-flutter-i18n-fallback-en`）→ key 本身（debug 模式 log）。
//   • 占位符四端統一為具名 `{name}`（不用 `%s` / `%d`），由 [ReferenceUIStrings.format] 代入。
//
// 字串表本體在同目錄的 `strings_<locale>.dart`，每個 locale 一個檔、一行一筆（四端對照 script 與
// 對照測試以 regex 逐行解析，所以每筆 MUST 獨佔一行、不跨行、不串接、不用插值）。

import 'package:flutter/foundation.dart';

import 'reference_ui_language.dart';
import 'strings_en.dart';
import 'strings_id_id.dart';
import 'strings_ms_my.dart';
import 'strings_zh_cn.dart';
import 'strings_zh_tw.dart';

/// Missing-key log signature.
typedef ReferenceUIMissingKeyLog = void Function(String key);

/// Lookup + formatting helpers for the reference-ui string tables. Package-internal (not exported
/// from `livebuy_flutter_reference_ui.dart`, parity iOS / Android internal tables).
abstract final class ReferenceUIStrings {
  /// locale code → table.
  static const Map<String, Map<String, String>> tables = {
    'zh-TW': zhTW,
    'zh-CN': zhCN,
    'en': en,
    'ms-MY': msMY,
    'id-ID': idID,
  };

  /// Look up [key] in the CURRENT reference-ui language and substitute `{name}` placeholders. A
  /// widget calling this during build MUST build through `referenceUILocalized(...)` so a
  /// language change rebuilds it.
  static String text(String key, [Map<String, Object> args = const {}]) =>
      resolve(key, args, referenceUILanguage.current);

  /// Pure lookup: [language] table → en table ([referenceUIFallbackLanguage]) → [key] itself
  /// (with a debug log). Tables and log are injectable for tests.
  static String resolve(
    String key,
    Map<String, Object> args,
    String language, {
    Map<String, Map<String, String>> tables = tables,
    ReferenceUIMissingKeyLog missingKeyLog = logMissingKey,
  }) {
    final value = tables[language]?[key] ?? tables[referenceUIFallbackLanguage]?[key];
    if (value != null) return format(value, args);
    missingKeyLog(key);
    return key;
  }

  /// Debug-only missing-key log.
  static void logMissingKey(String key) {
    if (kDebugMode) {
      debugPrint("[LivebuyReferenceUI] missing string key '$key' — falling back to the key itself");
    }
  }

  /// Replace every `{name}` in [template] with `args[name]` (`toString()`). Placeholders without
  /// an arg are left as-is (visible in QA rather than silently blanked).
  static String format(String template, Map<String, Object> args) {
    var out = template;
    args.forEach((name, value) => out = out.replaceAll('{$name}', value.toString()));
    return out;
  }

  /// The set of `{name}` placeholder names in [value] (used by the completeness tests).
  static Set<String> placeholders(String value) =>
      RegExp(r'\{([^{}]*)\}').allMatches(value).map((m) => m.group(1)!).toSet();

  // MARK: - Locale-aware month/day (design.md D8)
  //
  // Same output as iOS (`DateFormatter` CLDR `MMMd`) / Android (ICU `getInstanceForSkeleton("MMMd")`)
  // / RN (fixed table): zh-TW / zh-CN `6月11日`, en `Jun 11`, ms-MY / id-ID `11 Jun`. Fixed CLDR
  // abbreviated month names (identical to RN's table) instead of the `intl` package's locale data,
  // so the four platforms stay byte-identical without a new dependency.

  static const List<String> _enMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec', //
  ];
  static const List<String> _msMonths = [
    'Jan', 'Feb', 'Mac', 'Apr', 'Mei', 'Jun', 'Jul', 'Ogo', 'Sep', 'Okt', 'Nov', 'Dis', //
  ];
  static const List<String> _idMonths = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des', //
  ];

  /// Days in [month] of a leap year (2/29 stays valid — the year is not displayed).
  static const List<int> _daysInMonth = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

  /// Month + day in [language]'s CLDR `MMMd` form; `''` for an invalid month/day.
  static String monthDay(int month, int day, String language) {
    if (month < 1 || month > 12 || day < 1 || day > _daysInMonth[month - 1]) return '';
    switch (language) {
      case 'en':
        return '${_enMonths[month - 1]} $day';
      case 'ms-MY':
        return '$day ${_msMonths[month - 1]}';
      case 'id-ID':
        return '$day ${_idMonths[month - 1]}';
      default:
        // zh-TW / zh-CN (and any unknown code, which the notifier never produces).
        return '$month月$day日';
    }
  }
}
