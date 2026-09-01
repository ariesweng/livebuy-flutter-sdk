// url-open-policy-flutter （parity of url-open-policy-and-host-routing-core）

/// Livebuy 法務連結的**四端共用單一事實來源**。
///
/// **為什麼放 core，而不是放在中獎 modal footer 旁邊（reference-ui）**：
/// - 它是四端共用的**同一個事實**——同一個網址會被 iOS / Android / RN / Flutter 各自的 footer
///   消費；放 reference-ui 等於四份複製，任一端漂移一次就再也對不齊。
/// - footer **只是它的其中一個消費點**——完全自繪 UI 的 headless（Tier 0）host 一樣需要在自家
///   中獎畫面上放這兩個連結；常數鎖在 reference-ui 會逼 Tier 0 host 自己抄字串。
/// - core 已有同類前例：native SDK 的 `StatReporter` 端點同樣是不屬於 `LBRoute` API 端點家族、
///   但放在 core 的 non-API URL 常數。
///
/// **為什麼是 `String` 而不是 [Uri]**：(i) Kotlin / TypeScript / Dart 沒有等價於 Foundation
/// `URL` 的 value type，`String` 是四端共同的最低公分母，各端可逐字照抄；
/// (ii) `LBURLOpenPolicy.decide` 本來就吃字串，兩者天然接得起來。
///
/// **不是 i18n key**：網址不隨語系變化，MUST NOT 進入任何語系資源。
///
/// 與政策自洽：兩個常數都是 `livebuy.tv`，餵進 `LBURLOpenPolicy.decide` 必得
/// `LBURLOpenTarget.inApp`（由 `test/lb_url_open_policy_test.dart` 釘死）。
abstract final class LBLegalLinks {
  /// 使用條款。
  static const String termsOfUse = 'https://livebuy.tv/terms-of-use';

  /// 隱私政策。
  static const String privacyPolicy = 'https://livebuy.tv/privacy-policy';
}
