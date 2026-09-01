// url-open-policy-flutter （parity of url-open-policy-and-host-routing-core）
//
// 「一個網址該用 app 內瀏覽器還是外部瀏覽器開」的四端共用裁決規則，Flutter/Dart 端實作。
//
// 這裡**只裁決、不開啟**。core 維持 headless：本檔 MUST NOT import `url_launcher` /
// `webview_flutter` / 任何瀏覽器或 UI 套件（連 `package:flutter/*` 都不需要——`Uri` 來自
// `dart:core`）。實際呈現由 view-model 層 / reference-ui 層依 `target` 選擇既有的開啟機制
// （Flutter: `LaunchMode.inAppBrowserView` / `LaunchMode.externalApplication`）。
//
// **消費端已接線，且集中在各層的單一 URL 出口。** 接線由 `url-open-host-routing-template-flutter`
// （view-model 層）與 `rb-flutter-win-claim-footer-links`（reference-ui 層）落地：view-model 層
// `default_template.dart` 的唯一 URL 出口、以及 reference-ui 層中獎 widget 的法務連結路由，
// 都是先呼叫 `decide()`、再依 `target` 分流。
// ⚠️ 這兩層在 Flutter 是**獨立的頂層套件目錄**（`flutter-ui/` 與 `flutter-reference-ui/`，
// **不在** `flutter/` 底下）——只在本套件目錄內 grep 消費者會得到「無消費者」的假陰性。
//
// ⚠️ **reference-ui 層仍有不經本策略的既有 outbound 出口**——例如
// `flutter-reference-ui/lib/src/widget/external_live.dart` 的外部直播平台卡，直接
// `launchUrl(uri, mode: LaunchMode.externalApplication)`，不呼叫 `decide()`。
// 那是**待收斂的債、不是已定案的例外**，屬 reference-ui 層另案。因此 **MUST NOT** 從上一段
// 推得「所有開啟都已由本策略裁決」。
//
// ⚠️ 「消費端已接線」那一段刻意寫成「**層 + 單一出口**」而非消費者清單或數量：走既有出口的
// 新消費點不會使它過期，而繞過出口的消費點本來就該在 review 被擋下。**MUST NOT** 改寫成
// 「目前有 N 個消費者」這類快照式敘述——本檔頭的前一版正是那樣寫的（「可被呼叫但尚無
// production 消費者」），並在接線落地的**同一天**就成為假敘述。（點名的 change id 是
// **接線來源的歷史事實**、不會翻面，與會翻面的消費者普查不同。）
//
// ⚠️ **層別邊界不變**：core 只裁決、不開啟；接線與呈現一律屬上層（I7 單層規則：core change
// 不得改 view-model / reference-ui capability）。
//
// ⚠️ **Dart 的 `Uri` 與 iOS Foundation 的 `URL` 語意差很多**，本檔的每一處差異都由
// `openspec/changes/url-open-policy-flutter/design.md` 決策 F-A 的**實測輸出**支撐，
// 不是從 iOS 類推的。改動本檔前請先讀那一節。

/// 一個網址的開啟方式。
///
/// 兩個值的語意是**契約**，不是提示——呈現端必須照這個語意實作：
/// - [inApp]：以平台原生 in-app browser 呈現（Flutter: `LaunchMode.inAppBrowserView`），
///   使用者留在 App 內。
/// - [external]：**交給系統 URL router**（Flutter: `LaunchMode.externalApplication`）。
///   呈現端 **MUST NOT** 把 [external] 的 URL 載進任何 WebView（含
///   `LaunchMode.inAppWebView`）——那會讓該 URL 在**當前已載入頁面的 origin** 下被求值。
///
/// 註：`external` 在 Dart 是 built-in identifier（用於 external 宣告），但可以合法作為
/// enum 常數名，因此四端命名得以逐字對齊。
enum LBURLOpenTarget {
  /// 以 app 內瀏覽器開（使用者留在 App 內）。
  inApp,

  /// 交給系統 URL router 開（可能離開 App）。MUST NOT 以 WebView 載入。
  external,
}

/// 一則已裁決的開啟請求：**已解析的 URL** + **怎麼開**。
///
/// 「不可開」不由本型別表達，而由 [LBURLOpenPolicy.decide] 回傳 `null` 表達——[LBURLOpenTarget.inApp]
/// 與 [LBURLOpenTarget.external] 兩態都必然帶著一個可開的 URL，第三態必然沒有，所以
/// 「有沒有東西可開」交給 nullable、「怎麼開」交給 [target]，呼叫端得以一次 null 檢查
/// 完成安全 no-op。
class LBURLOpenDecision {
  const LBURLOpenDecision({required this.url, required this.target});

  /// 要開啟的 URL。
  ///
  /// **呈現端 MUST 直接使用這個值，MUST NOT 拿原始字串另跑一套 parser 重新取 host** ——
  /// 判定是對「本 URL 解析器解出的 host」做的，換一套 parser 就換了一組解析差異
  /// （parser differential），等於繞過判定。
  ///
  /// 策略**自身**不改寫 URL（不補 scheme、不改 host、不動 path / query），但這個值是
  /// **Dart `Uri` 的產物**，可能已帶有解析器自己的正規化。實測：
  /// `'HTTPS://LiveBuy.TV/Terms'` 的 `toString()` 為 `'https://livebuy.tv/Terms'`
  /// （Dart 自動小寫 scheme 與 host）。加上入口的空白 trim——所以
  /// `url.toString() == 輸入字串` **不成立**，MUST NOT 寫這種斷言。
  final Uri url;

  /// 開啟方式。
  final LBURLOpenTarget target;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LBURLOpenDecision && other.url == url && other.target == target);

  @override
  int get hashCode => Object.hash(url, target);

  @override
  String toString() => 'LBURLOpenDecision(url: $url, target: $target)';
}

/// URL 開啟策略（純函式命名空間）。
///
/// 純函式：不讀寫持久化狀態、不發網路請求、不讀系統時鐘、不抓任何 singleton，因此同一輸入
/// 恆回相同結果，可在任何機器上單測（不需要模擬器 / 網路）。
///
/// 用 `abstract final class` 而非 `enum`：Dart 的 `enum` 必須至少有一個常數，無法當
/// caseless 命名空間；`abstract final class` 是 Dart 表達「只有靜態成員、不可實例化
/// 也不可繼承」的標準形狀。
abstract final class LBURLOpenPolicy {
  /// 判為 app 內開啟的註冊域。此網域**與其任意層子網域**皆走 app 內。
  ///
  /// 公開的理由：四端各只有這一處字面量，host（Tier 0）與各端實作都讀它，
  /// 而不是各自再寫一次 `'livebuy.tv'`。
  static const String inAppDomain = 'livebuy.tv';

  /// 裁決一個原始網址字串該怎麼開。
  ///
  /// - [rawUrl]：原始字串（`LBProduct.diversionUrl` / `LBShop.serviceLink` /
  ///   `LBLegalLinks` 常數皆為字串，故此處吃字串而非 [Uri]——解析只在這裡發生一次，
  ///   呼叫點不必各自重寫一份空值 + 解析檢查）。
  /// - 回傳 `null` 代表**不可開**（呼叫端 MUST 安全 no-op）；否則為已解析 URL + 開啟方式。
  ///
  /// 求值順序（固定，先成立者決定結果）：
  /// 1. trim 後為空 → `null`
  /// 2. `Uri.tryParse` 回 `null` → `null`
  /// 3. 沒有 scheme → `null`
  /// 4. scheme 不在 [_openableSchemes] **允許清單**內 → `null`
  /// 5. **原始字串的 authority 段含 `\` → `null`**（跨 parser fail-closed，
  ///    見 [_rawAuthorityContainsBackslash]。此步驟為四端共同裁決，不是 Flutter 專屬）
  /// 6. 非 web scheme（`mailto` / `tel` / `sms`）→ [LBURLOpenTarget.external]
  /// 7. web scheme 但沒有 host → `null`
  /// 8. web scheme：[isInAppHost] 判定 → `inApp` / `external`
  ///
  /// ⚠️ **Dart 專屬型別陷阱**：
  /// - [Uri.scheme] 是**非 nullable `String`**，缺 scheme 時其值為 `''` 而**不是** `null`。
  ///   `Uri.tryParse('')` / `Uri.tryParse('livebuy.tv/terms')` /
  ///   `Uri.tryParse('//livebuy.tv/x')` **都回傳非 null 的 `Uri`**（前兩者 host 為 `''`，
  ///   第三者 host 實測**就是** `'livebuy.tv'`）。因此第 3 步 MUST 判**空字串**——寫成
  ///   「scheme != null」會恆為真而形同不存在。
  ///
  ///   ⚠️ **但本行沒有可觀測的鑑別力，據實說明**（獨立驗收提出，本檔實跑複核）：把
  ///   `if (scheme.isEmpty) return null;` **整行刪掉，行為與全部測試結果零改變**——因為
  ///   `''` 本來就不在 [_openableSchemes] 內，下一行的允許清單會接住同一批輸入。
  ///   兩行**僅在「scheme 為空字串」這一族輸入上互為冗餘**（皆為實測）：對該族而言，只刪本行、
  ///   或只刪允許清單，`decide('//livebuy.tv/x')` 皆仍為 `null`；**兩行都刪**才有變化，而結果是
  ///   `external`（`''` 也不在 [_webSchemes]，host 判定根本到不了）——**即使如此也不是 `inApp`**。
  ///
  ///   🔴 **這個冗餘 MUST NOT 被推廣成「刪哪一行都無所謂」。** 兩者的刪除影響**極不對稱**
  ///   （同一組 22 個輸入實測）：刪本行 → **0 個**輸入改變；刪 [_openableSchemes] 檢查 →
  ///   **9 個**輸入從 `null` 變 `external`（`intent:` / `javascript:` / `data:` / `file:` /
  ///   `content:` / 自訂 scheme / `wss:` / `ftp:` / `x:`）。**允許清單對非空 scheme 是唯一防線**，
  ///   其中 `intent://…#Intent;…;end` 正是規格點名的 Android 開洞向量。
  ///
  ///   本行保留的理由因此**不是**「少了它會開洞」，而是：(i) 讓程式碼逐行對得上規格
  ///   「URL 開啟目標裁決規則」的**固定求值順序**（第 3 步獨立於第 4 步），可被逐條稽核；
  ///   (ii) defense-in-depth——實測「只刪允許清單」時，正是本行擋住 protocol-relative。
  ///   **MUST NOT** 把它描述成 protocol-relative 的唯一防線或主要防線。
  /// - [Uri.host] 同樣非 nullable，無 host 時為 `''`（`'https:///path'` 實測即是），
  ///   因此第 6 步 MUST 用 `isEmpty`。
  /// - 入口的 trim 不只是禮貌：`'  https://livebuy.tv/x  '` 未 trim 時 `Uri.tryParse`
  ///   實測回 `null`。Dart 的 `String.trim()` 不會去除零寬空格（U+200B 不屬 Unicode
  ///   White_Space），所以 trim 不會意外改變安全判定。
  ///
  /// 完整實測輸出見 `openspec/changes/url-open-policy-flutter/design.md` 決策 F-A。
  static LBURLOpenDecision? decide(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;

    final scheme = uri.scheme.toLowerCase();
    if (scheme.isEmpty) return null;
    if (!_openableSchemes.contains(scheme)) return null;
    if (_rawAuthorityContainsBackslash(trimmed)) return null;

    if (!_webSchemes.contains(scheme)) {
      return LBURLOpenDecision(url: uri, target: LBURLOpenTarget.external);
    }

    final host = uri.host;
    if (host.isEmpty) return null;

    return LBURLOpenDecision(
      url: uri,
      target: isInAppHost(host) ? LBURLOpenTarget.inApp : LBURLOpenTarget.external,
    );
  }

  /// 原始（已 trim）輸入字串的 **authority 段**是否含反斜線 `\`。含則整個輸入不可開。
  ///
  /// 🔴 **這是 fail-closed 的跨 parser 防線，不是潔癖。** `\` 正好落在兩大 URL parser 家族
  /// 對「authority 在哪裡結束」意見分歧的位置：
  ///
  /// | parser 家族 | 代表 | 對 authority 內 `\` 的處理 |
  /// |---|---|---|
  /// | WHATWG | Chrome / GURL / **Dart `Uri`** | 當成 authority 終止字元（等同 `/`） |
  /// | RFC 3986 | **Foundation / NSURL** | **不**當分隔字元，`\` 留在 host 內 |
  ///
  /// 後果是**判定用的 parser 與開啟用的 parser 可以對同一字串得到不同的主機**。
  /// `https://livebuy.tv\@evil.com/x` 在 Dart 下 `host == 'livebuy.tv'`（會被判 in-app），
  /// 而同一個**原始字串**餵給 Foundation `URL(string:)` 實測 host 是 `evil.com`。
  ///
  /// ⚠️ **但危害路徑不是「經由 `decision.url`」，據實說明**（本 change 以 `swiftc` 探針實測）：
  /// `url_launcher` 送出的是 `url.toString()`（`url_launcher/lib/src/url_launcher_uri.dart`
  /// 的 `launchUrl`），而 Dart 的 `toString()` **已經把 `\` 正規化成 `/`** ——
  /// 送出的字串是 `https://livebuy.tv/@evil.com/x`，Foundation 對它解出的 host 是
  /// **`livebuy.tv`**（`@` 已落在 path）。也就是說：**只要消費端確實用 `decision.url`，
  /// 這條路徑上不會發生主機接管。**
  ///
  /// 真正成立的危害路徑是**原始字串被送進 RFC 3986 家族的 opener**（實測 host = `evil.com`，
  /// 真正的主機接管）。本策略仍 **MUST** fail-closed，理由有三，且都不依賴上面那條被推翻的鏈：
  /// 1. 「消費端必須用 `decision.url`」是規格**能規範但不能保證**的事——而 `isInAppHost` 的
  ///    誤用警告所描述的「拿原始字串自己處理」是真實可能發生的呼叫形態。
  /// 2. 裁決結果**不該取決於下游剛好轉發哪一個字串**；那是一個關於下游程式碼的未經驗證前提。
  /// 3. 「Dart 的 `toString()` 剛好做了正規化」是**巧合而非契約**，MUST NOT 被當成防線。
  ///
  /// 因此 **MUST NOT** 挑任何一家 parser 對齊（對齊任一家都會讓其他家曝險），而是
  /// **只要 authority 段出現 `\` 就一律不可開**。`\` 在合法 URL 的 authority 裡沒有真實用途
  /// （RFC 3986 的 `reg-name` / `userinfo` 文法都不含它），所以這條規則不會誤傷正常網址。
  ///
  /// ⚠️ 實際的開啟端**不只兩家**（本 change 讀 `url_launcher` 原始碼確認）：iOS 走 Foundation
  /// `URL(string:)`、Android 走 `android.net.Uri.parse`、Custom Tabs 再交給 Chrome 的 GURL。
  /// 上表只列出**分歧最相關的兩個家族**，MUST NOT 被讀成「開啟端只有這兩家」——fail-closed 的
  /// 價值正在於它**不需要**列舉完整家數也成立。
  ///
  /// ⚠️ **必須看原始字串，因為 Dart 的 `Uri` 把 `\` 藏起來了**（實測）：對
  /// `https://livebuy.tv\@evil.com/x`，`uri.host` 是 `'livebuy.tv'`、`uri.authority` 是
  /// `'livebuy.tv'`、**連 `uri.toString()` 都是 `'https://livebuy.tv/@evil.com/x'`**
  /// （`\` 被正規化成 `/`）。三個 `Uri` 屬性沒有一個看得到那個 `\`。
  ///
  /// 掃描分兩段，兩段都必須看，**因為 `\` 可以出現在兩個不同位置**：
  ///
  /// 1. **authority 的前綴分隔字元**（`scheme:` 之後那兩個字元）。RFC 3986 只認 `//`，
  ///    但 **WHATWG 把 `/` 與 `\` 視為可互換**，所以 `https:\\livebuy.tv/x` 與
  ///    `https:/\livebuy.tv/x` 在 Dart 下**有** host（實測皆為 `livebuy.tv`），在 Foundation
  ///    下**沒有** host（整段成為 path）。分隔字元本身只要出現 `\` 就 fail-closed。
  ///    ⚠️ 本檔初版只比對字面 `'//'`，因此漏掉這兩個形狀（實測當時判 in-app）——
  ///    那是一個「authority 前綴一定是 `//`」的**未言明前提**，已移除。
  /// 2. **authority 本體**：從分隔字元之後起，到第一個 `/`、`?`、`#` 或字串結尾為止
  ///    （**刻意不把 `\` 當終止字元**，否則就永遠掃不到它）。此範圍是 RFC 3986 的 authority，
  ///    也是 WHATWG authority 的**超集或等集**（WHATWG 多把 `\` 也當終止字元）。取聯集上界而非
  ///    對齊某一家，是為了讓這道檢查**不隨開啟端家數增減而失效**。
  ///
  /// `\` 落在 path / query 時**不**攔截——那時 authority 已結束，兩家對 host 沒有分歧
  /// （實測 `https://livebuy.tv/a\b` 兩側 host 皆為 `livebuy.tv`）。
  static bool _rawAuthorityContainsBackslash(String raw) {
    final colon = raw.indexOf(':');
    if (colon < 0) return false;

    // ① 分隔字元：WHATWG 認 `/` 與 `\` 互換，故兩者皆計數。
    var i = colon + 1;
    var delimiters = 0;
    var backslashDelimiter = false;
    while (i < raw.length && delimiters < 2) {
      final c = raw.codeUnitAt(i);
      if (c == 0x2F) {
        delimiters++;
      } else if (c == 0x5C) {
        delimiters++;
        backslashDelimiter = true;
      } else {
        break;
      }
      i++;
    }
    if (delimiters < 2) return false; // 沒有 authority 段（例：`mailto:` / `https:/x`）
    if (backslashDelimiter) return true; // 分隔字元本身就分歧 → fail-closed

    // ② authority 本體。
    for (; i < raw.length; i++) {
      final c = raw.codeUnitAt(i);
      if (c == 0x2F || c == 0x3F || c == 0x23) return false; // / ? #  → authority 結束
      if (c == 0x5C) return true; // \  → 各家 parser 分歧，fail-closed
    }
    return false;
  }

  /// [host] 是否落在 [inAppDomain] 這個註冊域（含任意層子網域）。
  ///
  /// **為什麼是公開成員（iOS 對應的 `isInAppHost` 是 `internal`）**：Dart 沒有等價於 Swift
  /// `internal` 的可見度（`_` 前綴會讓測試也叫不到），而規格
  /// `Scenario: 每個 authority 終止字元皆使 host 失去 in-app 資格` 判定的對象是 **host 字串**；
  /// Dart 的 `Uri` 對其中部分終止字元不會讓該 host 字串抵達判定（實測：`@` 之前的部分被吃成
  /// `userInfo`，`https://evil.com@.livebuy.tv/x` 的 host 是 `'.livebuy.tv'`；`:` 那例
  /// `Uri.tryParse` 直接回 `null`）。沒有這個入口，該 Scenario 在 Flutter 上無法驗收。
  /// 它是**純謂詞**：無副作用、無狀態、同輸入恆同輸出。
  ///
  /// 🔴 **誤用警告——公開它並不代表它可以取代 [decide]。** 呼叫端 **MUST NOT** 拿原始網址
  /// 字串自己 parse 出 host 再餵進本方法，也 **MUST NOT** 用本方法的回傳值決定要用哪種
  /// 瀏覽器開。那正是規格 `Scenario: 消費端不得另用一套 parser` 禁止的 **parser
  /// differential**：本 capability 的判定是對「[decide] 所用解析器解出的 host」做的，換一套
  /// parser（或換一次解碼時機）就換了一組解析差異，等同繞過判定——而且會拿到一個看起來
  /// 「SDK 認證過」的結果。
  ///
  /// 本方法**只**供兩種用途：(i) 驗收規格中以 **host 字串**為判定對象的 Scenario；
  /// (ii) 呼叫端手上**本來就是**可信 host 字串（非自行從 URL 解析而來）的判斷。
  /// 要決定一個**網址**怎麼開，唯一正確入口是 [decide]，並直接使用它回傳的
  /// [LBURLOpenDecision.url]。
  ///
  /// 三道處理，順序有意義：
  /// 1. **小寫**——DNS 大小寫不敏感。Dart 的 `Uri` 實測**會**自動小寫 host（Foundation 不會），
  ///    所以這一步在 Dart 上是冪等的；保留它是為了四端寫法一致，且不依賴「Dart 永遠會小寫」
  ///    這個未被規格保證的實作細節。
  /// 2. **去掉至多一個結尾的點**——`https://livebuy.tv./x` 的 host 實測是 `'livebuy.tv.'`
  ///    （FQDN 根點，解析到同一台主機）。**只去一個**：`'livebuy.tv..'` 去一個後仍不匹配 →
  ///    external（保守方向，寧可少給 in-app）。
  /// 3. **乾淨 host guard（[_isPlainHost]）——這道不是裝飾。** 見該函式的 doc。
  ///
  /// 判定本身是**正面連言**（滿足全部條件才授予 in-app），刻意不寫成黑名單——黑名單會在新的
  /// 攻擊形狀出現時變成不完整的窮盡敘述。
  static bool isInAppHost(String host) {
    final lowered = host.toLowerCase();
    final bare = lowered.endsWith('.')
        ? lowered.substring(0, lowered.length - 1)
        : lowered;
    if (bare.isEmpty) return false;
    if (!_isPlainHost(bare)) return false;
    return bare == inAppDomain || bare.endsWith('.$inAppDomain');
  }

  /// [bare] 是否只由「普通主機字元」組成：ASCII 小寫英數字 + `.` + `-`。
  ///
  /// **這個集合的安全性質不是「不含 `/`」，而是「不含任何可終止 authority 的字元」。**
  /// URL authority 的終止字元 `/`、`\`、`@`、`:`、`?`、`#`、空白、NUL，以及百分比編碼
  /// 自身的 `%`，全都不在集合內。因此「host 字串以 `.livebuy.tv` 結尾」與「真正被連線的
  /// 主機是別人」**無法同時成立**——要讓真實 host 落在別處，就必須有一個終止字元把
  /// authority 切斷，而那個字元會讓整個 host 直接失去 in-app 資格。
  ///
  /// ⚠️ **維護警告**：往這個集合加字元會削弱上述不變式。加 `%` 會**直接開洞**——Dart 實測
  /// `Uri.tryParse('https://evil.com%2f.livebuy.tv/x').host` 為 `'evil.com%2F.livebuy.tv'`
  /// （Dart 遵循 RFC 3986，**不**把 reserved 字元的百分比編碼解碼，只把 hex 轉大寫），
  /// 該字串**確實以 `.livebuy.tv` 結尾**，naive 後綴比對會誤放行；`%` 是唯一擋住它的字元。
  /// `_`、`~`、`+` 之類看似無害的字元同樣 MUST 先重新論證「不含終止字元」是否仍成立，
  /// 並補對應測試。
  ///
  /// 以 code unit 逐一比對而非 `RegExp`：沒有任何需要讀者驗證的正則語意（跳脫 / 多行 /
  /// Unicode 旗標），且對代理對天然安全——任何非 ASCII 的 code unit 都不落在四個區間內。
  static bool _isPlainHost(String bare) {
    for (var i = 0; i < bare.length; i++) {
      final c = bare.codeUnitAt(i);
      final ok = (c >= 0x61 && c <= 0x7A) // a-z
          ||
          (c >= 0x30 && c <= 0x39) // 0-9
          ||
          c == 0x2E // .
          ||
          c == 0x2D; // -
      if (!ok) return false;
    }
    return true;
  }

  /// 會進入 host 判定的 scheme。
  static const Set<String> _webSchemes = {'http', 'https'};

  /// **外送允許清單**：只有這些 scheme 會得到裁決，其餘一律 `null`（不可開）。
  ///
  /// 這是**正面允許清單，不是黑名單**，理由是餵進 [decide] 的字串主要來自
  /// **後端可控欄位**（`LBProduct.diversionUrl` / `LBShop.serviceLink`）。黑名單式的
  /// 「非 http(s) 就交給 OS」在 Android 上是實質風險：`intent://…#Intent;…;end` 是公認
  /// 可觸達任意 exported component 的向量，而它照黑名單寫法會被原樣送進系統 router。
  /// 允許清單讓這類 scheme（`intent` / `javascript` / `data` / `file` / `content` /
  /// 任意 app 自訂 scheme）在 **core 就被擋掉**，四端不必各自記得補防護。
  ///
  /// 代價（明列，非疏忽）：後端把 `diversionUrl` 填成 host app 自訂 scheme 的 deep link
  /// 會變成安全 no-op。目前沒有任何已知使用情境依賴它；若日後出現，那是一個要獨立論證的
  /// change，而不是預設就開著的洞。
  static const Set<String> _openableSchemes = {
    'http',
    'https',
    'mailto',
    'tel',
    'sms',
  };
}
