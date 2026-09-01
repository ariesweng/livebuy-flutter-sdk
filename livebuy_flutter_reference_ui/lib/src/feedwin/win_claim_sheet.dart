import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:livebuy_flutter/livebuy_flutter.dart' show LBWinner;
import 'package:livebuy_flutter_ui/livebuy_flutter_ui.dart'
    show
        DefaultWinClaim,
        LBClaimClassification,
        LBClaimOutcome,
        LBClaimResultState;

import '../reference_ui_theme.dart';
import '../testing/lb_test_keys.dart';
import 'win_glyph.dart';

// WinClaimSheetView — family-2 feed-win surface 3 (四階段領獎 modal，含 email 輸入，Flutter).
//
// Spec: `reference-ui-rendering/spec.md`
//   § "渲染 Flutter 四階段領獎 modal（含 email 輸入），綁 DefaultWinClaim 提交、送出中與結果狀態"
// Design: `design/templates/minimal/moments.jsx` `LBWinSheet`（2026-07-24 v2 四階段重寫）
//         + `design/contract/claude-design-sync.md` **R13**（含兩條刻意分歧裁示）。
// Parity: iOS `ios/Sources/LivebuyReferenceUI/FeedWin/WinClaimModalView.swift`
//         （`rb-ios-win-claim-email-flow`, commit 62133e9c —— 本檔逐點鏡像其 D-1 ~ D-11）
//         + RN `react-native-reference-ui/src/feedwin/WinClaimSheetView.tsx`
//         （`rb-rn-win-claim-email-flow`, commit 276b252d）。
//
// ─────────────────────────────────────────────────────────────────────────────
// EMAIL-LESS 已退役（rb-flutter-win-claim-email-flow）
// ─────────────────────────────────────────────────────────────────────────────
// 這張 modal 先前是 EMAIL-LESS 的「通知型」單頁置中卡：CTA 直接 `onSubmit(winner)`
// → `DefaultWinClaim.submit(winner)` → core `requestAwardClaim(winner, null)`。
// 但 core 預設領獎路徑 `email` **必填** —— host 未攔截 `awardClaimIntent` 又沒有 email 時，
// core fail-fast 發 `AWARD_CLAIM_RESULT(status='failed')`、**連 `POST /sdk/video/claim` 都沒
// 送出**。訪客（僅 `guest_id`）全程可參加抽獎並中獎，卻沒有任何地方能填 email，於是 turnkey
// host 必然回報「中獎領取失敗」。本檔即是把 email 欄位真正畫出來的那一層。
//
// 四階段流程（對齊設計稿 `LBWinSheet` 現行 HEAD 的 `stage` 機，含 R27 關閉機制簡化 +
// 分頁能力，rb-flutter-win-claim-pagination）：
//
//   claim         恭喜中獎 + award.name + ✉ email 欄 +「確認領獎」+ footer（`pageCount > 1`
//                 時卡底追加分頁圓點）
//     └「確認領獎」→ confirmSubmit alert →（確定）→ submitting → done / fail
//   done          discount → 折扣碼 + 複製 + 寄送信箱；product → 待結帳商品卡
//   fail          領獎失敗 + 通用錯誤提示列 +「重新領獎」（回 confirmSubmit）
//
// 🔴 R27 關閉機制簡化：claim 卡右上角 ✕、claim 卡「關閉視窗」次要文字鈕、fail 卡「關閉視窗」
// 次要文字鈕，連同它們原本觸發的 `confirmClose` stage/phase 與強勸阻確認 alert 全數退役，不由
// 任何替代 UI 補上。取而代之，外層 scrim 在**任何 stage** 皆無條件轉發 `onDismiss`（見
// `build()` 的 scrim `GestureDetector`）。底層行為不變（R13 純 dismiss 不變式逐字保留，見
// `FeedWinOverlayView._handleDismissClaim` 的說明）——這次退役的只是文案與二次確認 UI。
//
// ─────────────────────────────────────────────────────────────────────────────
// 單一真相（stage 怎麼來的）
// ─────────────────────────────────────────────────────────────────────────────
// 設計稿用「一個 `stage` state」跑完全程。原生若照抄，`submitting` / `done` / `fail` 會變成
// 本層自己維護的**第二份真相**，與 view-model 的 `submitInFlight` / `resultState` 必然分歧。
// 因此這裡拆成：
//
//   • 本層 `State` 只存**使用者互動意圖**（[WinClaimPhase]）與 email 輸入字串
//     （外加「已複製」的視覺回饋）。
//   • 實際 stage 由**純函式** [winClaimStage] 推導，`submitting` 綁傳入的 `submitInFlight`、
//     `done` / `fail` 綁 `resultState`。
//
// ⚠️ Known hang（view-model 已載明）：native host 攔截 `awardClaimIntent` 時 core 不發
// `AWARD_CLAIM_RESULT`，`submitInFlight` 會一直為真、畫面停在 submitting。收尾責任在 host
// （呼叫 `dismissClaim()`）。本層 **MUST NOT** 自加提交逾時或自行猜測結果 —— 那就是第二份真相。
//
// ─────────────────────────────────────────────────────────────────────────────
// SUB-VIEW INPUT PATTERN（與 family-2 其餘 surface 相同）
// ─────────────────────────────────────────────────────────────────────────────
//   1. `theme:` (ReferenceUITheme, required)        — FIRST, always.
//   2. bound SNAPSHOT VALUES (read-only, BY VALUE):
//        `winner` / `classification` / `resultState` / `submitInFlight` —— 由 `FeedWinModel`
//        by value 傳入（never the model, never the template）。`pageCount` / `pageIndex`
//        （rb-flutter-win-claim-pagination，R27）—— 容器持有的分頁狀態，同樣 by value。
//   3. action callbacks (LAST, each defaulting to a no-op):
//        `onSubmit: void Function(String email)?`（帶使用者輸入的 email，funnel 到
//        `FeedWinModel.submitClaimWithEmail(winner, email)` → `DefaultWinClaim.submitWithEmail`）、
//        `onDismiss: VoidCallback?`（關閉，funnel 到 `dismissClaim()` + 清容器綁定）、
//        `onPage: ValueChanged<int>?`（滑動 / 點分頁圓點，funnel 到容器更新其索引狀態）、
//        `onOpenTermsOfUse` / `onOpenPrivacyPolicy: VoidCallback?`（footer 兩段文字被點擊，
//        rb-flutter-win-claim-footer-links——funnel 到容器 `openLegalLink(LBLegalLinks.*)`）。
//
// 本 sub-view 只讀傳入值，從不回抓 `FeedWinModel` / `DefaultPlayerTemplate`（單向資料流），
// 且所有 callback 為 null 時仍能正確渲染（demo / golden 可 action-free 建構）。
//
// RENDER DISCIPLINE（沿用本層既有紀律）：plain `Column` / `Row` / `Stack`，本 change 新增
// `TextField`（email 欄位的必要新增，且沿用本層既有的 `editable` 慣例）。仍然 NO `ListView` /
// `GridView` / `SingleChildScrollView`、NO `Image.network` / `NetworkImage`、NO 動畫 / 亂數
// （confetti 取決定性首幀靜態），故 golden byte-stable。

// MARK: - Stage 機（型別 + 純函式推導）

/// 對外可辨識的呈現階段（對齊設計稿 `LBWinSheet` 的 `stage`）。
///
/// 🔴 R27 起不再含 `confirmClose`（rb-flutter-win-claim-pagination 已整個退役該值，見檔頭
/// 「四階段流程」段落）——不由任何替代值取代。
enum WinClaimStage {
  /// 恭喜中獎 + email 輸入（可提交）。
  claim,

  /// 「確認領獎」alert（確認 email 正確）。
  confirmSubmit,

  /// 送出中（scrim + spinner），由 view-model `submitInFlight` 驅動。
  submitting,

  /// 領獎完成，由 view-model `resultState` 的成功態驅動。
  done,

  /// 領獎失敗，由 view-model `resultState` 的 `failure` 驅動。
  fail,
}

/// 本層 `State` 持有的**使用者互動意圖**（不是 stage 本身）。
///
/// [WinClaimPhase.editing] 這一格原本是為了忠實還原設計稿「fail →「重新領獎」→ 確認 alert →
/// （取消）→ 回到可改 email 的 claim 卡」路徑：alert 取消時一律設 `editing`，讓殘留的
/// `resultState`（仍是 `failure`）不要把畫面拉回 fail 卡。真正送出時設回 `idle`，讓新一輪
/// 結果能重新驅動 done / fail。分頁能力（rb-flutter-win-claim-pagination，design.md D-2）
/// 沿用同一格：換頁時同樣設回 `editing`，避免上一筆 winner 殘留的 `confirmSubmit` alert 相位
/// 或 `resultState` 帶到新頁 —— 見 [WinClaimSheetView.didUpdateWidget]。
///
/// 🔴 R27 起不再含 `confirmClose`（見 [WinClaimStage] 的等效說明）。
enum WinClaimPhase {
  /// 無 alert、也未明示要回填單 —— stage 完全由 view-model 的結果決定。
  idle,

  /// 使用者明示要（回到）填單畫面，覆蓋殘留的舊結果；換頁時亦重置到此。
  editing,

  /// 正顯示「確認領獎」alert。
  confirmSubmit,
}

/// 由 view-model 結果狀態映射出的終態 stage（純函式）。
/// `null`（或未知 outcome）→ [WinClaimStage.claim]（提交前態）。
WinClaimStage winClaimResultStage(LBClaimResultState? result) {
  if (result == null) return WinClaimStage.claim;
  switch (result.outcome) {
    case LBClaimOutcome.successProduct:
    case LBClaimOutcome.successDiscount:
      return WinClaimStage.done;
    case LBClaimOutcome.failure:
      return WinClaimStage.fail;
  }
}

/// stage 推導（純函式）。優先序：
/// 1. view-model 說在送出中 → [WinClaimStage.submitting]（畫面不得比 view-model 樂觀）。
/// 2. 正在顯示 alert → 該 alert 階段（alert 疊在底卡之上）。
/// 3. 使用者明示回填單 → [WinClaimStage.claim]（覆蓋殘留舊結果）。
/// 4. 其餘一律由 view-model 的 `resultState` 決定。
WinClaimStage winClaimStage(
  WinClaimPhase phase,
  bool submitInFlight,
  LBClaimResultState? result,
) {
  if (submitInFlight) return WinClaimStage.submitting;
  switch (phase) {
    case WinClaimPhase.confirmSubmit:
      return WinClaimStage.confirmSubmit;
    case WinClaimPhase.editing:
      return WinClaimStage.claim;
    case WinClaimPhase.idle:
      return winClaimResultStage(result);
  }
}

/// `done`（discount）要顯示的折扣碼（純函式）：優先用領獎結果帶回的 `awardCode`（權威），
/// 缺值 / 非 discount 結果時退回 award 自帶的 `code`。
String winClaimDiscountCode(LBClaimResultState? result, LBWinner winner) {
  if (result != null &&
      result.outcome == LBClaimOutcome.successDiscount &&
      (result.awardCode ?? '').isNotEmpty) {
    return result.awardCode!;
  }
  return winner.award.code;
}

/// 置中卡在鍵盤彈出時該套用的垂直位移（負值 = 上移）。純函式（parity iOS
/// `WinClaimModalView.keyboardShift`）。
///
/// - 鍵盤高度 0（含所有 golden 路徑）→ 回 `0`，baseline 決定式。
/// - 卡底緣被鍵盤壓到時上移剛好露出（[bottomGap] 留白）。
/// - 上移量以 [topGap] 夾住，**MUST NOT** 把卡頂（含浮出 30 的徽章）推出畫面上緣。
///
/// 之所以量測卡高而非固定上移 `keyboardHeight / 2`：後者在小螢幕（667）+ 300 鍵盤 +
/// ~400 卡高時會把卡頂推出畫面（切頭）。量測後才能同時保證「不被鍵盤遮」與「頭不出界」。
double winClaimKeyboardShift({
  required double keyboardHeight,
  required double containerHeight,
  required double cardHeight,
  double bottomGap = 12,
  double topGap = 42,
}) {
  if (keyboardHeight <= 0 || containerHeight <= 0 || cardHeight <= 0) return 0;
  final cardTop = (containerHeight - cardHeight) / 2;
  final overlap =
      (cardTop + cardHeight) - (containerHeight - keyboardHeight - bottomGap);
  if (overlap <= 0) return 0;
  return -math.min<double>(overlap, math.max<double>(0, cardTop - topGap));
}

// MARK: - Decorative design tokens (literal minimal hex via colorFromHex)
//
// accent / text / background come from the resolved [ReferenceUITheme]. These are
// FIXED decorative colors lifted verbatim from the design `theme.surface.*` (light
// mode, `design/brands/livebuy/tokens.jsx`). They mirror the iOS / Android / RN
// `WinClaim*` static colors byte-for-byte so the four platforms read as one family.

/// `theme.surface.textDim` (secondary / caption text).
final Color _textDim = colorFromHex('#6B6775') ?? const Color(0xFF6B6775);

/// `theme.surface.textFaint` (empty-field placeholder).
final Color _textFaint = colorFromHex('#B6B2BE') ?? const Color(0xFFB6B2BE);

/// `theme.surface.stroke` (hairline border / spinner track).
final Color _stroke = colorFromHex('#ECEAF0') ?? const Color(0xFFECEAF0);

/// `theme.surface.bgSunken` (sunken card / input fill — light mode).
final Color _bgSunken = colorFromHex('#F4F4F6') ?? const Color(0xFFF4F4F6);

/// 設計稿 `DANGER`（失敗徽章 / 錯誤提示列）。
final Color _danger = colorFromHex('#EB6E5F') ?? const Color(0xFFEB6E5F);

/// Modal scrim (`LBWinSheet` `rgba(0,0,0,0.6)`).
final Color _scrimColor = Colors.black.withValues(alpha: 0.6);

/// alert / submitting 疊層自己的 scrim（`rgba(0,0,0,0.28)`）。
final Color _alertScrimColor = Colors.black.withValues(alpha: 0.28);

/// 分頁圓點（rb-flutter-win-claim-pagination）非目前頁的顏色 —— 設計稿
/// `background: i === pageIndex ? accent : (S.border || '#D8DBE0')`。`theme.surface`
/// 實際**沒有** `border` 欄位（`design/brands/livebuy/tokens.jsx` 的 `surface` 只有
/// `stroke` / `strokeStrong`），故該運算式永遠退回字面值 `#D8DBE0` —— 這才是真正被畫出來
/// 的顏色，**不是** [_stroke]（`#ECEAF0`，hairline border / spinner track 用，數值不同，
/// 勿混用）。
final Color _pageDotInactive = colorFromHex('#D8DBE0') ?? const Color(0xFFD8DBE0);

// MARK: - Confetti palette (LBWinSheet CONFETTI — fixed colors, port of iOS/Android/RN)

final Color _confettiRed = colorFromHex('#F03246') ?? const Color(0xFFF03246);
final Color _confettiTeal = colorFromHex('#0FC3B4') ?? const Color(0xFF0FC3B4);
final Color _confettiAmber = colorFromHex('#F39C12') ?? const Color(0xFFF39C12);
final Color _confettiInk = colorFromHex('#111111') ?? const Color(0xFF111111);

/// confetti 顆數（v2：22 → 20）。
const int _confettiCount = 20;

// MARK: - Fixed localized copy (static presentation strings — parity iOS / Android / RN)
//
// 本層全層寫死中文常數，**不使用**任何 i18n API（與 `_textDim` 等 design-literal 同慣例）。

const String _congratsTitle = '恭喜中獎';
const String _awardNameFallback = '直播間限定獎品';
const String _emailPlaceholder = '電子郵件';
const String _ctaSubmit = '確認領獎';
const String _footerTerms = '使用條款';
const String _footerSeparator = ' | ';
const String _footerPrivacy = '隱私政策';

const String _submitAlertTitle = '確認領獎';
const String _submitAlertBodyPrefix = '請確認 ';
const String _submitAlertBodySuffix = ' 填寫正確，送出後將不可變更，確定要送出領獎資料嗎？';
const String _submitAlertNoteDiscount = '※結帳折扣碼將會寄送到您的信箱內。';
const String _submitAlertNoteProduct = '※獎品將自動加入為待結帳商品。';

const String _alertCancelLabel = '取消';
const String _alertConfirmLabel = '確定';

const String _submittingLabel = '送出中…';

const String _doneTitle = '領獎完成';
const String _doneSublineDiscount = '結帳折扣碼已寄送到以下電子郵件';
const String _doneSublineProduct = '獎品已加入待結帳商品，結帳前完成訂購';
const String _copyLabel = '複製';
const String _copiedLabel = '已複製';
const String _pendingItemCaption = '待結帳商品';

const String _failTitle = '領獎失敗';
const String _failSubline = '領獎過程發生錯誤，你的中獎資格仍保留，請稍後再試一次。';

/// 🔴 通用文案 —— **MUST NOT** 換成 `CLAIM_TIMEOUT` 之類捏造的錯誤代碼，理由見 `_failNoticeRow`
/// 的註解（R13 刻意分歧 2/2）。
const String _failNotice = '若持續發生，請聯繫客服';
const String _retryLabel = '重新領獎';

// MARK: - Pure color helpers

/// 把 [color] 朝白色提亮 [amount]（0…1），對應設計稿 `lbShade(hex, +amount)`
/// （`c' = (255 - c) * p + c`）。disabled CTA 底色用。純函式。
Color _lightened(Color color, double amount) {
  int channel(double c) =>
      ((255 - c * 255) * amount + c * 255).round().clamp(0, 255);
  return Color.fromARGB(
    (color.a * 255).round(),
    channel(color.r),
    channel(color.g),
    channel(color.b),
  );
}

// MARK: - Submitting spinner ring (static 3/4 arc — NO animation, golden-stable)
//
// 設計稿的 spinner 是旋轉的 3/4 圓弧。本層 **不掛動畫**（golden determinism 的既有紀律），
// 改畫「靜態 3/4 弧 + 底環」——與 iOS 旋轉 spinner 的視覺同構、與 RN 的靜態環一致。
// 用 `CustomPaint` 而非 `BoxDecoration(border:)`：Flutter 的 `BoxShape.circle` 只接受
// **均勻** border，四邊不同色會直接觸發 assert。

class _SpinnerRingPainter extends CustomPainter {
  final Color trackColor;
  final Color arcColor;

  /// 環寬（設計稿 `border: 3px`）。
  static const double strokeWidth = 3;

  const _SpinnerRingPainter({
    required this.trackColor,
    required this.arcColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = trackColor;
    canvas.drawArc(rect, 0, 2 * math.pi, false, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = arcColor;
    // 由 12 點鐘方向起、順時針 3/4 圈（設計稿 `borderTopColor` 的等效表現）。
    canvas.drawArc(rect, -math.pi / 2, 1.5 * math.pi, false, arc);
  }

  @override
  bool shouldRepaint(covariant _SpinnerRingPainter oldDelegate) =>
      oldDelegate.trackColor != trackColor || oldDelegate.arcColor != arcColor;
}

/// The family-2 四階段領獎 modal（一次一個 [LBWinner]）。畫恭喜中獎 + 獎品名 + email
/// 輸入欄，經確認 alert 後以 `onSubmit(email)` 提交，並依 view-model 的 [submitInFlight] /
/// [resultState] 呈現送出中 / 領獎完成 / 領獎失敗。
class WinClaimSheetView extends StatefulWidget {
  /// Resolved reference-ui theme (FIRST positional argument, always).
  final ReferenceUITheme theme;

  /// The winner this modal claims for (`unclaimedWinners` earliest). Read-only.
  final LBWinner winner;

  /// award 造型 / 內容分流（`DefaultWinClaim.classify(winner)`）。唯讀。
  ///
  /// ⚠️ 它 **不再**決定主 CTA 文案（v2 起 CTA 統一「確認領獎」），也**不**決定是否要收
  /// email（兩種 award type 都要同一個 email 欄位）；只影響 `confirmSubmit` 的提示文案與
  /// `done` 階段的內容分流。
  final LBClaimClassification classification;

  /// Latest mapped claim-result feedback (`DefaultWinClaim.resultState`); `null`
  /// until a result arrives（提交前態）。驅動 `done` / `fail` 階段。Read-only.
  final LBClaimResultState? resultState;

  /// 送出中旗標（`DefaultWinClaim.submitInFlight`）。驅動 `submitting` 階段。
  /// **本層 MUST NOT 自造第二份 in-flight 真相** —— 只讀這一個。預設 `false`。
  final bool submitInFlight;

  /// email 欄位是否為**真的可輸入** `TextField`（runtime 預設 `true`），或靜態唯讀呈現
  /// （`false`）。**沿用本層既有慣例**（`GuestNameEditModalView.editable`、iOS
  /// `WinClaimModalView.editable`），不發明第二種做法：golden / demo 走 `false`，使 baseline
  /// 不受游標閃爍 / 輸入法狀態影響。
  final bool editable;

  /// email 欄位的初始值（host 可預填已知信箱；golden 以此種出「已填 email」的 stage）。
  /// 預設空字串。使用者輸入後即以本層的 `TextEditingController` 為準。
  final String initialEmail;

  /// 分頁能力（R27 新增，rb-flutter-win-claim-pagination）：目前未領獎項清單的總頁數。
  /// 容器傳入 `unclaimedWinners.length`。`<= 1` 時分頁圓點不畫、滑動手勢為安全 no-op。
  /// 預設 `1`（既有 golden / demo 單頁行為不變）。
  final int pageCount;

  /// 目前顯示的頁碼（`unclaimedWinners` 的索引）。這是容器持有的呈現層開啟狀態 by value 傳
  /// 入，**不是**本 widget 自己的狀態 —— 本 widget 只在 [didUpdateWidget] 偵測其變化以重置
  /// 互動意圖（design.md D-2）。預設 `0`。
  final int pageIndex;

  /// 領獎提交（帶使用者輸入的 email）。容器轉發 `model.submitClaimWithEmail(winner, email)` →
  /// `DefaultWinClaim.submitWithEmail(winner, email)`。demo / golden 為 `null` —— 本 widget
  /// 在所有 callback 為 null 時仍正確渲染。
  final void Function(String email)? onSubmit;

  /// 關閉（任何 stage 點外層 scrim —— R27 關閉機制簡化，見檔頭「四階段流程」段落）。容器
  /// 轉發 `dismissClaim()` 後清掉自己的呈現綁定。demo / golden 為 `null`。
  final VoidCallback? onDismiss;

  /// 換頁（滑動或點分頁圓點）。容器轉發更新其索引狀態並改渲染新索引對應的 winner。`null`
  /// （demo / golden / `pageCount <= 1`）→ 滑動手勢與圓點點擊皆安全 inert。
  final ValueChanged<int>? onPage;

  /// footer「使用條款」文字被點擊（rb-flutter-win-claim-footer-links）。容器轉發
  /// `openLegalLink(LBLegalLinks.termsOfUse)`。本層只轉發「使用者點了哪一段」，不自行判定
  /// 網域或呼叫任何開啟 API（單向資料流）。demo / golden 為 `null` —— 點擊仍安全 inert。
  final VoidCallback? onOpenTermsOfUse;

  /// footer「隱私政策」文字被點擊（rb-flutter-win-claim-footer-links）。容器轉發
  /// `openLegalLink(LBLegalLinks.privacyPolicy)`。同 [onOpenTermsOfUse] 的轉發紀律。
  final VoidCallback? onOpenPrivacyPolicy;

  const WinClaimSheetView({
    super.key,
    required this.theme,
    required this.winner,
    required this.classification,
    this.resultState,
    this.submitInFlight = false,
    this.editable = true,
    this.initialEmail = '',
    this.pageCount = 1,
    this.pageIndex = 0,
    this.onSubmit,
    this.onDismiss,
    this.onPage,
    this.onOpenTermsOfUse,
    this.onOpenPrivacyPolicy,
  });

  @override
  State<WinClaimSheetView> createState() => _WinClaimSheetViewState();
}

class _WinClaimSheetViewState extends State<WinClaimSheetView> {
  // -- 本層 UI local state（不是 view-model）---------------------------------
  //
  // MUST NOT 出現 local `isSubmitting` 或第二份 result —— 那會在 view-model guard 擋下
  // （re-entrancy / invalid email）時卡住畫面，也會在 host 攔截時與 view-model 分歧。

  /// 使用者正在輸入的 email。**UI local state** —— view-model 不保存正在打的字
  /// （避免 keystroke 汙染 view-model）。驗證則一律呼叫 view-model 的純函式，見 [_emailValid]。
  late final TextEditingController _emailController =
      TextEditingController(text: widget.initialEmail);

  /// 使用者互動意圖（見 [WinClaimPhase]）。
  WinClaimPhase _phase = WinClaimPhase.idle;

  /// 折扣碼「複製」後的回饋（純視覺）。**刻意不加自動復原計時器** —— Flutter widget test
  /// 對未取消的 `Timer` 會直接判失敗，為此加計時器只是給 golden / widget test 製造 flake
  /// 來源，而本 modal 本身是短命的（parity RN，同樣 sticky）。
  bool _copied = false;

  /// 量測到的底卡高度，只用於算鍵盤位移（見 [winClaimKeyboardShift]）。
  double _cardHeight = 0;

  /// 量測底卡用的 key。
  final GlobalKey _cardKey = GlobalKey();

  /// 累積目前這次水平拖曳手勢的位移（正 = 向右拖、負 = 向左拖）。只在拖曳期間有意義，手勢
  /// 結束時由 [_handleSwipeEnd] 消費並歸零（rb-flutter-win-claim-pagination）。
  double _dragAccumulator = 0;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  /// 分頁換頁（rb-flutter-win-claim-pagination，design.md D-2）：`pageIndex` 改變（或呈現
  /// 的 winner 身分改變 —— 容器理論上永遠同動，這裡的 `winner.id` 比對只是多一層防禦）時，
  /// 互動意圖 SHALL 重置為可編輯的 `claim` 版面，避免上一筆 winner 殘留的 `confirmSubmit`
  /// alert 相位（或 stale `resultState`）帶到新頁。同時清掉「已複製」視覺回饋與 email 輸入
  /// 內容 —— 換頁視同開一次新 sheet，**不**做跨頁快取（design.md D-2：「NOT preserved
  /// across a page change」）。不需要 `setState`：`didUpdateWidget` 本身已在這次 rebuild
  /// 過程中，framework 會用新欄位值接著跑 `build()`。
  @override
  void didUpdateWidget(covariant WinClaimSheetView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pageIndex != oldWidget.pageIndex ||
        widget.winner.id != oldWidget.winner.id) {
      _phase = WinClaimPhase.editing;
      _copied = false;
      _emailController.clear();
    }
  }

  // -- Derived presentation (pure) --------------------------------------------

  WinClaimStage get _stage => winClaimStage(
        _phase,
        widget.submitInFlight,
        widget.resultState,
      );

  bool get _isDiscount =>
      widget.classification == LBClaimClassification.discount;

  /// 主 CTA 是否可按 —— **一律**呼叫 view-model 的純函式 `DefaultWinClaim.isValidEmail`，
  /// 本層不自寫第二份規則，這樣「畫面說可以送」與「view-model 願意送」永遠同一條判定。
  bool get _emailValid => DefaultWinClaim.isValidEmail(_emailController.text);

  /// 獎品名（空值退回本層既有 fallback 常數）。
  String get _awardName => widget.winner.award.name.isEmpty
      ? _awardNameFallback
      : widget.winner.award.name;

  /// `confirmSubmit` alert 是否正疊在底卡上（R27 起 `confirmClose` 已退役，只剩這一種）。
  bool get _isAlert => _stage == WinClaimStage.confirmSubmit;

  /// 底卡是否應被壓暗且不可互動（alert 或送出中）。
  bool get _isBusy => _isAlert || _stage == WinClaimStage.submitting;

  // -- Interactions ------------------------------------------------------------

  /// alert 的「確定」。
  void _handleAlertConfirm() {
    // 回到 `idle` 後才提交：這樣新一輪的 `submitInFlight` / `resultState` 能直接驅動
    // submitting → done / fail，不被殘留的互動意圖擋住。
    setState(() => _phase = WinClaimPhase.idle);
    widget.onSubmit?.call(_emailController.text);
  }

  Future<void> _handleCopy() async {
    setState(() => _copied = true);
    await Clipboard.setData(ClipboardData(
      text: winClaimDiscountCode(widget.resultState, widget.winner),
    ));
  }

  /// 量測底卡高度（只在鍵盤真的彈出時才需要；golden 路徑 `viewInsets.bottom == 0` →
  /// 完全不量測、不觸發額外 setState，故 baseline 決定式）。
  void _scheduleCardMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _cardKey.currentContext?.findRenderObject() as RenderBox?;
      final h = box?.hasSize == true ? box!.size.height : 0.0;
      if (h != _cardHeight) setState(() => _cardHeight = h);
    });
  }

  // -- 版型 --------------------------------------------------------------------
  //
  // 置中 modal 卡（非底部 sheet）：全幅容器內畫暗 scrim + 置中卡（寬 84%、上限 320）。
  // 卡上 MUST NOT 有「中獎通知」標題列 / grab handle；唯一卡頭 chrome 是右上角 ✕，
  // 且只出現在 claim 卡。

  @override
  Widget build(BuildContext context) {
    final stage = _stage;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    if (keyboardHeight > 0) _scheduleCardMeasure();

    return GestureDetector(
      // 分頁滑動手勢（rb-flutter-win-claim-pagination）：包住整個 modal（scrim + 底卡），
      // 對齊設計稿 `LBWinSheet` 外層 `onTouchStart`/`onTouchEnd` 量測 `clientX` 位移的做法。
      // `_handleSwipeEnd` 本身對 `pageCount <= 1` / `onPage == null` 皆安全 no-op，故此手勢
      // 不需要另外用 `pageCount > 1` 條件式掛載。
      onHorizontalDragStart: (_) => _dragAccumulator = 0,
      onHorizontalDragUpdate: (details) => _dragAccumulator += details.delta.dx,
      onHorizontalDragEnd: (_) => _handleSwipeEnd(),
      child: Stack(
        children: [
          // 外層 scrim —— R27 關閉機制簡化：設計稿由「僅 `stage === 'done'` 才可點擊背景
          // 關閉」改為「任何 stage 皆可點擊背景直接關閉，不再跳確認」
          // （`onClick={onClose}` 無條件）。claim 卡右上角 ✕、claim / fail 卡的「關閉視窗」
          // 次要文字鈕已隨 `confirmClose` 一併退役，外層 scrim 現在是**唯一**的關閉入口。
          Positioned.fill(
            child: GestureDetector(
              key: LbTestKeys.winClaimScrim,
              behavior: HitTestBehavior.opaque,
              onTap: widget.onDismiss,
              child: ColoredBox(color: _scrimColor),
            ),
          ),

          // 底卡（含浮出卡頂外的徽章）。鍵盤彈出時整體上移，位移由純函式決定。
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final shift = winClaimKeyboardShift(
                  keyboardHeight: keyboardHeight,
                  containerHeight: constraints.maxHeight,
                  cardHeight: _cardHeight,
                );
                return Transform.translate(
                  offset: Offset(0, shift),
                  child: Center(
                    child: FractionallySizedBox(
                      widthFactor: 0.84,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 320),
                        child: _cardStack(stage),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // ② confirmSubmit alert 疊層（R27 起唯一的 alert 相位）。
          if (_isAlert) _alertLayer(),

          // ③ submitting 疊層（由 view-model `submitInFlight` 驅動）。
          if (stage == WinClaimStage.submitting) _submittingLayer(),
        ],
      ),
    );
  }

  /// 分頁滑動手勢結束時的判定（rb-flutter-win-claim-pagination；對齊設計稿 `LBWinSheet` 的
  /// 40px 位移閾值）。`pageCount <= 1` 或 [WinClaimSheetView.onPage] 為 `null` 時安全
  /// no-op（MUST NOT 拋錯）；換算出的下一頁索引在 `[0, pageCount)` 範圍外（已在第一頁往左 /
  /// 最後一頁往右）同樣安全 no-op。
  void _handleSwipeEnd() {
    final dx = _dragAccumulator;
    _dragAccumulator = 0;
    if (widget.pageCount <= 1 || widget.onPage == null) return;
    if (dx.abs() < 40) return;
    final next = dx < 0 ? widget.pageIndex + 1 : widget.pageIndex - 1;
    if (next < 0 || next >= widget.pageCount) return;
    widget.onPage!(next);
  }

  /// 底卡外殼：外層 `Stack` 不裁切（讓徽章浮出卡頂外），內層卡才 `ClipRRect`。
  ///
  /// alert / submitting 期間**整張底卡（含浮出的徽章與 confetti）**一起壓暗且不可互動
  /// （設計稿 `ClaimCard` 的 `opacity: isBusy ? 0.55 : 1` + `pointerEvents: 'none'`，
  /// parity RN 的外殼 `View`）。
  ///
  /// 🔴 R27 起卡上**不再**畫任何明確關閉按鈕（右上角 ✕ 已隨 `confirmClose` 一併退役）——
  /// 唯一的關閉入口是外層 scrim，見 `build()`。
  Widget _cardStack(WinClaimStage stage) {
    return IgnorePointer(
      ignoring: _isBusy,
      child: Opacity(
        opacity: _isBusy ? 0.55 : 1,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            _card(stage),
            // 徽章 + confetti —— 浮在卡頂外（設計稿 `top:-30`），放在**不被裁切**的外層。
            Positioned(
              top: -30,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child:
                      stage == WinClaimStage.fail ? _failBadge() : _giftBadge(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // MARK: - 卡本體（radius 20，claim 上內距 46 / done·fail 48）

  Widget _card(WinClaimStage stage) {
    final theme = widget.theme;
    return GestureDetector(
      key: LbTestKeys.winClaimSheet,
      behavior: HitTestBehavior.opaque,
      // 吞掉卡上的點擊，避免穿透到 scrim。
      onTap: () {},
      child: DecoratedBox(
        // Soft drop shadow lifts the centered card off the scrim. 由 OUTER 圓角形狀投射；
        // 內層 ClipRRect 仍負責裁切卡內內容。
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x59000000), // black @ 0.35
              blurRadius: 32,
              offset: Offset(0, 24),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: ColoredBox(
            color: theme.background,
            child: Padding(
              key: _cardKey,
              padding: EdgeInsets.only(
                top: stage == WinClaimStage.claim ? 46 : 48,
                left: 22,
                right: 22,
                bottom: 22,
              ),
              child: _cardBody(stage),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cardBody(WinClaimStage stage) {
    switch (stage) {
      case WinClaimStage.done:
        return _doneCardBody();
      case WinClaimStage.fail:
        return _failCardBody();
      case WinClaimStage.claim:
      case WinClaimStage.confirmSubmit:
      case WinClaimStage.submitting:
        return _claimCardBody();
    }
  }

  // MARK: - 徽章（60，浮出卡頂外，4 卡背景色描邊）
  //
  // 禮物徽章 glyph **恆為 gift**，MUST NOT 依 `classification` 路由（對齊設計稿
  // `LBWinSheet` 的 `giftSvg` 與 iOS / Android / RN）。confetti 疊在它後面。

  Widget _giftBadge() {
    final theme = widget.theme;
    return SizedBox(
      width: 60,
      height: 60,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          ..._confetti(),
          Container(
            width: 60,
            height: 60,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFFFFFFF),
              border: Border.all(color: theme.background, width: 4),
            ),
            child: CustomPaint(
              size: const Size(30, 30),
              painter: WinTrophyGlyphPainter(outerColor: theme.accent),
            ),
          ),
        ],
      ),
    );
  }

  /// 失敗徽章（danger 實心，無 confetti）。
  Widget _failBadge() {
    return Container(
      width: 60,
      height: 60,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _danger,
        border: Border.all(color: widget.theme.background, width: 4),
      ),
      child: const Icon(Icons.error_outline, size: 30, color: Colors.white),
    );
  }

  // MARK: - Confetti（LBWinSheet CONFETTI — 20 顆決定式扇形方塊，錨在徽章中心）
  //
  // 設計稿 `CONFETTI` map 的直接移植（v2：`i / 19`、`dist = 34 + (i % 4) * 14`、`ty -= 16`），
  // 靜態（無動畫 / 無亂數）故 golden 決定式。調色盤 index 3 是解析後的 accent。

  List<Widget> _confetti() {
    final cols = <Color>[
      _confettiRed,
      _confettiTeal,
      _confettiAmber,
      widget.theme.accent,
      _confettiInk,
    ];
    return List<Widget>.generate(_confettiCount, (i) {
      final angDeg = -90.0 + ((i / 19.0) * 160.0 - 80.0);
      final ang = angDeg * math.pi / 180.0;
      final dist = 34.0 + (i % 4) * 14.0;
      final tx = math.cos(ang) * dist;
      final ty = math.sin(ang) * dist - 16.0;
      final rotation = ((i * 47) % 360) * math.pi / 180.0;
      final size = 5.0 + (i % 3) * 2.0;
      return Transform.translate(
        offset: Offset(tx, ty),
        child: Transform.rotate(
          angle: rotation,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: cols[i % 5],
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
        ),
      );
    });
  }

  // MARK: - ① claim 卡（恭喜中獎 + award.name + email 欄 + CTA + footer）

  Widget _claimCardBody() {
    final theme = widget.theme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 恭喜中獎標題 + **副標＝`award.name`**（v2 起不再是固定賀詞文案）。
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _congratsTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.text,
                fontSize: 22 * theme.fontScale,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _awardName,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _textDim,
                fontSize: 14.5 * theme.fontScale,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _emailRow(),
        const SizedBox(height: 14),
        _claimActions(),
        // 分頁圓點（R27 新增，rb-flutter-win-claim-pagination）—— 僅 `claim` 卡、僅
        // `pageCount > 1` 時畫（done / fail / alert / submitting 疊層 MUST NOT 畫）。
        if (widget.pageCount > 1) ...[
          const SizedBox(height: 14),
          _paginationDots(),
        ],
        const SizedBox(height: 14),
        _footerRow(),
      ],
    );
  }

  /// ✉ email 輸入列（mail glyph + 欄位），sunken 底 + hairline 邊框。
  ///
  /// `editable == true` 走真的 `TextField`；`editable == false`（golden / demo）走靜態 `Text`
  /// —— 沿用本層既有的 `GuestNameEditModalView.editable` 慣例。
  Widget _emailRow() {
    return Container(
      decoration: BoxDecoration(
        color: _bgSunken,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _stroke, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.mail_outline, size: 18, color: _textDim),
          const SizedBox(width: 9),
          Expanded(
            child: widget.editable ? _liveEmailField() : _staticEmailField(),
          ),
        ],
      ),
    );
  }

  Widget _liveEmailField() {
    final theme = widget.theme;
    return TextField(
      key: LbTestKeys.winClaimEmailField,
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      textCapitalization: TextCapitalization.none,
      autocorrect: false,
      enableSuggestions: false,
      maxLines: 1,
      // 每個 keystroke 重評 CTA gate（判定本身呼叫 view-model 的 isValidEmail）。
      onChanged: (_) => setState(() {}),
      cursorColor: theme.accent,
      style: TextStyle(
        color: theme.text,
        fontSize: 14.5 * theme.fontScale,
      ),
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
        hintText: _emailPlaceholder,
        hintStyle: TextStyle(
          color: _textFaint,
          fontSize: 14.5 * theme.fontScale,
        ),
      ),
    );
  }

  Widget _staticEmailField() {
    final theme = widget.theme;
    final text = _emailController.text;
    final isEmpty = text.isEmpty;
    return Text(
      isEmpty ? _emailPlaceholder : text,
      key: LbTestKeys.winClaimEmailField,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: isEmpty ? _textFaint : theme.text,
        fontSize: 14.5 * theme.fontScale,
      ),
    );
  }

  /// 主 CTA「確認領獎」（email 不合格 → disabled 灰底）。
  ///
  /// 🔴 R27 起卡上**不再**有次要「關閉視窗」文字鈕（已隨 `confirmClose` 一併退役）——唯一
  /// 的關閉入口是外層 scrim，見 `build()`。
  Widget _claimActions() {
    final theme = widget.theme;
    final valid = _emailValid;
    return GestureDetector(
      key: LbTestKeys.winClaimPrimary,
      behavior: HitTestBehavior.opaque,
      onTap: valid
          ? () => setState(() => _phase = WinClaimPhase.confirmSubmit)
          : null,
      child: Opacity(
        opacity: valid ? 1 : 0.6,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: valid ? theme.accent : _lightened(theme.accent, 0.35),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Text(
            _ctaSubmit,
            style: TextStyle(
              color: Colors.white,
              fontSize: 15.5 * theme.fontScale,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }

  /// 分頁圓點列（R27 新增，rb-flutter-win-claim-pagination）——`pageCount` 個 6×6 圓點，
  /// 5px 間距，僅 `claim` 卡且僅 `pageCount > 1` 時畫（見 [_claimCardBody]）。當前頁
  /// [ReferenceUITheme.accent] 實色、其餘為設計稿等效色 [_pageDotInactive]。每顆圓點皆可
  /// 點擊，呼叫 `onPage(index)`（[WinClaimSheetView.onPage] 為 `null` 時安全 inert）。
  Widget _paginationDots() {
    final theme = widget.theme;
    return Row(
      key: LbTestKeys.winClaimPageDots,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < widget.pageCount; i++) ...[
          if (i > 0) const SizedBox(width: 5),
          GestureDetector(
            key: LbTestKeys.winClaimPageDot(i),
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onPage?.call(i),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == widget.pageIndex ? theme.accent : _pageDotInactive,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // MARK: - ② confirmSubmit alert 疊層（R27 起唯一的 alert 相位——`confirmClose` 已退役，
  // 不再有分支需要保留，見 design.md D-4）

  Widget _alertLayer() {
    final theme = widget.theme;
    final title = _submitAlertTitle;
    final body =
        '$_submitAlertBodyPrefix${_emailController.text.trim()}$_submitAlertBodySuffix';
    final note = _isDiscount ? _submitAlertNoteDiscount : _submitAlertNoteProduct;

    return Positioned.fill(
      child: Stack(
        children: [
          // alert 自己的 scrim：只收起 alert（回可編輯的 claim 版面），MUST NOT 關整個 modal。
          Positioned.fill(
            child: GestureDetector(
              key: LbTestKeys.winClaimAlertScrim,
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _phase = WinClaimPhase.editing),
              child: ColoredBox(color: _alertScrimColor),
            ),
          ),
          Center(
            child: FractionallySizedBox(
              widthFactor: 0.84,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: DecoratedBox(
                  key: LbTestKeys.winClaimAlert,
                  decoration: BoxDecoration(
                    color: theme.background,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: theme.text,
                            fontSize: 20 * theme.fontScale,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          body,
                          style: TextStyle(
                            color: _textDim,
                            fontSize: 14 * theme.fontScale,
                            height: 1.65,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          note,
                          style: TextStyle(
                            color: theme.accent,
                            fontSize: 14 * theme.fontScale,
                            fontWeight: FontWeight.w600,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                key: LbTestKeys.winClaimAlertCancel,
                                behavior: HitTestBehavior.opaque,
                                onTap: () => setState(
                                    () => _phase = WinClaimPhase.editing),
                                child: Container(
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: theme.accent, width: 1.5),
                                  ),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 13),
                                  child: Text(
                                    _alertCancelLabel,
                                    style: TextStyle(
                                      color: theme.accent,
                                      fontSize: 15 * theme.fontScale,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: GestureDetector(
                                key: LbTestKeys.winClaimAlertConfirm,
                                behavior: HitTestBehavior.opaque,
                                onTap: _handleAlertConfirm,
                                child: Container(
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: theme.accent,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 13),
                                  child: Text(
                                    _alertConfirmLabel,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15 * theme.fontScale,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // MARK: - ③ submitting 疊層（scrim + 44 spinner 環 +「送出中…」）
  //
  // 靜態 3/4 弧（accent 頂邊 + stroke 底環）—— 本層無動畫（golden determinism），與 iOS 的
  // 旋轉 spinner 視覺同構。

  Widget _submittingLayer() {
    final theme = widget.theme;
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(color: _alertScrimColor),
            ),
          ),
          Center(
            child: DecoratedBox(
              key: LbTestKeys.winClaimSubmitting,
              decoration: BoxDecoration(
                color: theme.background,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomPaint(
                      size: const Size(44, 44),
                      painter: _SpinnerRingPainter(
                        trackColor: _stroke,
                        arcColor: theme.accent,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      _submittingLabel,
                      style: TextStyle(
                        color: theme.text,
                        fontSize: 15 * theme.fontScale,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // MARK: - ④ done 卡（領獎完成）

  Widget _doneCardBody() {
    final theme = widget.theme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _doneTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.text,
                fontSize: 22 * theme.fontScale,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isDiscount ? _doneSublineDiscount : _doneSublineProduct,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _textDim,
                fontSize: 14 * theme.fontScale,
                fontWeight: FontWeight.w500,
                height: 1.5,
              ),
            ),
            if (_isDiscount) ...[
              const SizedBox(height: 8),
              Text(
                _emailController.text.trim(),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.accent,
                  fontSize: 16 * theme.fontScale,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        _isDiscount ? _discountCodeRow() : _pendingItemRow(),
        const SizedBox(height: 14),
        _footerRow(),
      ],
    );
  }

  /// 折扣碼 + 複製鈕（`Clipboard.setData` 為 Flutter 框架內建，不引入外部依賴）。
  Widget _discountCodeRow() {
    final theme = widget.theme;
    final code = winClaimDiscountCode(widget.resultState, widget.winner);
    return Container(
      key: LbTestKeys.winClaimResultBanner,
      decoration: BoxDecoration(
        color: _bgSunken,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _stroke, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              code,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: theme.text,
                fontSize: 16 * theme.fontScale,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            key: LbTestKeys.winClaimCopyCode,
            behavior: HitTestBehavior.opaque,
            onTap: _handleCopy,
            child: Text(
              _copied ? _copiedLabel : _copyLabel,
              style: TextStyle(
                color: theme.accent,
                fontSize: 14.5 * theme.fontScale,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 待結帳商品卡（product 類獎品）。
  Widget _pendingItemRow() {
    final theme = widget.theme;
    return Container(
      key: LbTestKeys.winClaimResultBanner,
      decoration: BoxDecoration(
        color: _bgSunken,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _stroke, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 10% accent tint 讓全色 glyph 讀得出來（parity iOS / Android / RN）。
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.redeem, size: 20, color: theme.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _pendingItemCaption,
                  style: TextStyle(
                    color: _textDim,
                    fontSize: 11 * theme.fontScale,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _awardName,
                  style: TextStyle(
                    color: theme.text,
                    fontSize: 14 * theme.fontScale,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // MARK: - ⑤ fail 卡（領獎失敗）

  Widget _failCardBody() {
    final theme = widget.theme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _failTitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: theme.text,
                fontSize: 22 * theme.fontScale,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _failSubline,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _textDim,
                fontSize: 14 * theme.fontScale,
                fontWeight: FontWeight.w500,
                height: 1.6,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _failNoticeRow(),
        const SizedBox(height: 16),
        _failActions(),
        const SizedBox(height: 14),
        _footerRow(),
      ],
    );
  }

  /// 🔴 **錯誤提示列：版面保留、文案通用、MUST NOT 顯示捏造的錯誤代碼。**
  ///
  /// 設計稿這一列寫的是「錯誤代碼 …… · 若持續發生請聯繫客服」，但那個代碼與稿內
  /// `jasper@livebuy.tv` / `1L9zOdX` 同性質 ＝ **demo 佔位值**。後端**刻意不區分**領獎失敗
  /// 原因（已領過 / 活動結束 / 票券無效 / email 被拒，全部 `500 api.fail`，anti-enumeration），
  /// SDK 拿不到任何有意義的錯誤碼，硬填就是騙人。因此版面照留（danger 底色 + 警示 glyph），
  /// 文案固定為通用值。權威：`design/contract/claude-design-sync.md` **R13「刻意分歧（2/2）」**。
  /// 待後端真的細分錯誤碼再回來接，屆時才可顯示真實代碼。
  Widget _failNoticeRow() {
    final theme = widget.theme;
    return Container(
      key: LbTestKeys.winClaimFailNotice,
      decoration: BoxDecoration(
        // danger 10% tint 底 + 30% 描邊，讓全色 danger glyph 讀得出來。
        color: _danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _danger.withValues(alpha: 0.30), width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 18, color: _danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _failNotice,
              style: TextStyle(
                color: _danger,
                fontSize: 12.5 * theme.fontScale,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 「重新領獎」（回 confirmSubmit，**沿用原本輸入的 email**）。
  ///
  /// 🔴 R27 起不再有旁邊的「關閉視窗」文字鈕（該按鈕原本已是直接 `onDismiss`，整顆一併移
  /// 除，非改成別的東西——見 design.md D-3）；仍能透過外層 scrim 關閉（純 dismiss）。
  Widget _failActions() {
    final theme = widget.theme;
    return GestureDetector(
      key: LbTestKeys.winClaimPrimary,
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _phase = WinClaimPhase.confirmSubmit),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: theme.accent,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Text(
          _retryLabel,
          style: TextStyle(
            color: Colors.white,
            fontSize: 15.5 * theme.fontScale,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  // MARK: - Footer（使用條款 | 隱私政策 — 各自可點擊，接容器 legalLinkRoute 分流）
  //
  // rb-flutter-win-claim-footer-links：兩段文字各自可點擊，轉發到 [onOpenTermsOfUse] /
  // [onOpenPrivacyPolicy]（皆 `null` 時安全 inert）。開啟哪個連結、以何種方式開啟由容器
  // （`FeedWinOverlayView.legalLinkRoute` / `openLegalLink`，其內部以 core
  // `LBURLOpenPolicy.decide` 為唯一判準）決定——本層 MUST NOT 自行判定網域或呼叫任何開啟 API
  // （單向資料流，本層只轉發「使用者點了哪一段」）。分隔符 `_footerSeparator` 維持純 `Text`，
  // 不可點擊。`GestureDetector`（沿用本檔既有 `_claimActions` / 折扣碼複製鈕的既有慣例）不
  // 繪製任何像素，故既有 golden baseline 逐位元組不變。

  Widget _footerRow() {
    final theme = widget.theme;
    final style = TextStyle(
      color: _textDim,
      fontSize: 12.5 * theme.fontScale,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.2,
    );
    return Row(
      key: LbTestKeys.winClaimFooter,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          key: LbTestKeys.winClaimFooterTerms,
          behavior: HitTestBehavior.opaque,
          onTap: widget.onOpenTermsOfUse,
          child: Text(_footerTerms, style: style),
        ),
        Opacity(opacity: 0.5, child: Text(_footerSeparator, style: style)),
        GestureDetector(
          key: LbTestKeys.winClaimFooterPrivacy,
          behavior: HitTestBehavior.opaque,
          onTap: widget.onOpenPrivacyPolicy,
          child: Text(_footerPrivacy, style: style),
        ),
      ],
    );
  }
}
