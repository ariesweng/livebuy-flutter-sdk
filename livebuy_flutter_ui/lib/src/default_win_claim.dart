import 'package:flutter/foundation.dart';
import 'package:livebuy_flutter/livebuy_flutter.dart';

// reconcile-activity-notification-contract-template §2 / §3 / §4 — win unclaimed
// entry + award-claim submit + result-state mapping (behaviour / view-model
// layer; NO pixels).
//
// §2 LBWinEntry behaviour: on showWin(text, winner) maintain an unclaimed set
//    deduped by winner.id, expose count + winner list + an "open claim flow"
//    intent. On awardClaimResult.status == claimed remove that winner.id and
//    decrement count. Independent from the feed's win notification.
// §3 LBWinSheet submit behaviour: submitWithEmail(winner, email) →
//    requestAwardClaim(winner, contact: LBAwardClaimInput(email)). Expose
//    winner.award.type classification (product / discount) for host CTA text.
//    ⚠️ The EMAIL-LESS entry point `submit(winner)` (contact ALWAYS null) is
//    RETIRED-but-kept: core's default (non-intercepted) claim path REQUIRES
//    `email`, so it fails fast without even sending POST /sdk/video/claim —
//    that is the bug win-claim-email-submit-flutter-template fixes. Kept only
//    as @Deprecated for source compatibility (removal: next MAJOR).
// §4 Result-state mapping + interception: subscribe awardClaimResult → a result
//    state model; awardCode ONLY for claimed + discount. Native host (iOS /
//    Android) intercepting awardClaimIntent → no result state. Flutter
//    interception is expressed via "whether submit is called" (eventJoinIntent
//    bridge pattern) — so reaching submit() always means SDK fulfils the claim.
//
// SDK core stays headless: the unclaimed set / submit / classification /
// result-state model live entirely here; core only delivers showWin, emits
// awardClaimIntent / awardClaimResult, and calls the claim API.
//
// Spec: `ui-template-foundation/spec.md` (win-claim-email-submit-flutter-template,
// parity iOS `f1bfb841` / Android `c3e09d08` / RN `48f3f292`)
//   § "Default Template（Flutter）帶 email 領獎提交行為（parity）"
//   § "Default Template（Flutter）領獎 email 前端驗證（純函式，parity）"
//   § "Default Template（Flutter）領獎送出中狀態（`submitInFlight`，parity）"
//   § "Default Template（Flutter）關閉領獎畫面僅 dismiss（不放棄中獎資格，parity）"
// Design: design.md D1–D9. view-model / zero-pixel: this file only exposes
// bindable state + pure logic (`package:flutter/foundation.dart` ChangeNotifier
// only — NO material.dart / widgets.dart); the four-stage sheet is drawn by
// `flutter-reference-ui`.

/// CTA classification derived from `winner.award.type` (§3). The host picks the
/// CTA copy: product → "查看獎品", discount → "立即使用".
enum LBClaimClassification {
  /// `award.type == "product"` → CTA「查看獎品」.
  product,

  /// `award.type == "discount"` → CTA「立即使用」.
  discount,

  /// Any other / future award type — host shows a neutral CTA.
  other;

  static LBClaimClassification fromAwardType(String type) {
    switch (type) {
      case 'product':
        return LBClaimClassification.product;
      case 'discount':
        return LBClaimClassification.discount;
      default:
        return LBClaimClassification.other;
    }
  }
}

/// Outcome bucket of an award-claim result (§4).
enum LBClaimOutcome {
  /// claimed + product → success/prize (no code).
  successProduct,

  /// claimed + discount → success/discount + awardCode.
  successDiscount,

  /// failed / unknown → failure, retryable.
  failure,
}

/// Result-state model the host binds to draw the success / failure feedback
/// (§4). The template draws NO feedback pixels.
///
/// [awardCode] is populated ONLY for [LBClaimOutcome.successDiscount]; for a
/// product success it is null (the model MUST NOT carry an empty code field —
/// design D3 / risk note).
class LBClaimResultState {
  final LBClaimOutcome outcome;

  /// Discount code; non-null ONLY when [outcome] == successDiscount.
  final String? awardCode;

  /// Originating event id, when the result carried one.
  final int? eventId;

  const LBClaimResultState._(this.outcome, {this.awardCode, this.eventId});

  bool get isSuccess =>
      outcome == LBClaimOutcome.successProduct ||
      outcome == LBClaimOutcome.successDiscount;

  /// `.failed` and `.unknown(Int)` map identically (retryable failure).
  bool get isRetryable => outcome == LBClaimOutcome.failure;

  /// Map a core `awardClaimResult(status, awardType, eventId?, awardCode?)`
  /// notification into the result-state model.
  ///
  /// - claimed + discount → successDiscount + awardCode
  /// - claimed + product  → successProduct (awardCode forced null)
  /// - failed / unknown   → failure (eventId / awardCode null)
  factory LBClaimResultState.fromResult({
    required LBAwardClaimStatus status,
    required String awardType,
    int? eventId,
    String? awardCode,
  }) {
    if (status == LBAwardClaimStatus.claimed) {
      if (awardType == 'discount') {
        return LBClaimResultState._(
          LBClaimOutcome.successDiscount,
          awardCode: awardCode,
          eventId: eventId,
        );
      }
      // product (or any non-discount) claimed success — never carry a code.
      return LBClaimResultState._(LBClaimOutcome.successProduct, eventId: eventId);
    }
    // .failed and .unknown(Int) both fall here (§4 — unknown ≡ failed).
    return const LBClaimResultState._(LBClaimOutcome.failure);
  }
}

/// Submits an award claim through the core, **carrying the host-collected
/// contact** (win-claim-email-submit-flutter-template — parity iOS
/// `AwardClaimRequesting` / Android `AwardClaimContactSubmitter` / RN
/// `RequestAwardClaimWithContact`).
///
/// Injected so the view-model never holds the native player controller (the
/// platform view owns it — same constraint as the other requester seams here),
/// and so unit tests can capture the call with a `Capturing` player (CLAUDE.md
/// test discipline) without a native channel.
///
/// Shape is **identical to core** `LivebuyPlayerController.requestAwardClaim`,
/// so a host can tear it off directly:
///
/// ```dart
/// DefaultWinClaim(contactSubmitter: controller.requestAwardClaim)
/// ```
///
/// (`Future<void> Function(LBWinner, {LBAwardClaimInput? contact})` is
/// assignable to this `void`-returning type — verified with `dart analyze`.)
///
/// `contact` is `LBAwardClaimInput(email: ...)` for [DefaultWinClaim.submitWithEmail]
/// and `null` for the DEPRECATED EMAIL-LESS [DefaultWinClaim.submit].
typedef AwardClaimContactSubmitter = void Function(
  LBWinner winner, {
  LBAwardClaimInput? contact,
});

/// Submits an award claim through the core **without any contact**.
///
/// @deprecated EMAIL-LESS 提交 seam（型別上沒有 contact 參數 → email 傳不出去），這正是
/// Flutter 版 EMAIL-LESS 陷阱的物理位置：core 預設（未被 host 攔截）領獎路徑 `email` 必填，
/// 缺 email 直接 fail-fast、連 `POST /sdk/video/claim` 都不送，必然
/// `AWARD_CLAIM_RESULT(status=failed)`。改用 [AwardClaimContactSubmitter]；本型別將於
/// 下一個 major 移除（`docs/contract-governance.md` I6 / 情境 F）。形狀刻意維持不變以保
/// 源碼相容 —— Dart **不允許**少參數 callback 指派給多參數函式型別，就地改形狀會讓既有
/// host 直接編譯失敗（BREAKING），故只能新增而非替換（design.md D5）。
@Deprecated(
  'EMAIL-LESS 領獎 seam（無 contact 參數 → email 傳不出去），未被 host 攔截時必然失敗。'
  '改用 AwardClaimContactSubmitter；本型別將於下一個 major 移除。',
)
typedef AwardClaimSubmitter = void Function(LBWinner winner);

/// Win unclaimed-entry + claim-submit + result-state view-model (§2 / §3 / §4).
///
/// The host binds [unclaimedCount] / [unclaimedWinners] to draw the floating
/// entry (`LBWinEntry`), calls [submitWithEmail] from the claim sheet
/// (`LBWinSheet`, four stages `claim → confirmSubmit / confirmClose →
/// submitting → done / fail`), reads [classify] for CTA copy, binds
/// [submitInFlight] / [resultState] for the feedback, and calls [dismissClaim]
/// to close.
///
/// Observability (expose-default-template-bindable-state, design D1):
/// implements [ChangeNotifier] so the host binds via `ListenableBuilder` and
/// re-reads [unclaimedCount] / [unclaimedWinners] / [resultState] on change. A
/// COALESCED notification fires EXACTLY ONCE after each single state change —
/// [onWin] (recordWin), claimed removal + result update via [onAwardClaimResult]
/// (one event → one notification even though it touches both the set and the
/// result), [removeUnclaimed], and [clearResultState]. [submit] / [classify]
/// are pure reads/intents and do NOT notify. Purely additive: no listener →
/// unchanged behaviour. Dispatches on the platform/UI thread (the wiring
/// consumes core events there already).
class DefaultWinClaim extends ChangeNotifier {
  /// DEPRECATED EMAIL-LESS seam (see [AwardClaimSubmitter]). Kept so existing
  /// `DefaultWinClaim(submitter: ...)` hosts still compile; used ONLY when no
  /// [AwardClaimContactSubmitter] was injected — in which case the contact is
  /// necessarily lost (design.md D5).
  // ignore: deprecated_member_use_from_same_package
  final AwardClaimSubmitter? _submitter;

  /// Contact-carrying seam (win-claim-email-submit-flutter-template). Preferred
  /// over [_submitter] whenever both are injected.
  final AwardClaimContactSubmitter? _contactSubmitter;

  // Insertion-ordered unclaimed set, deduped by winner.id (§2).
  final Map<String, LBWinner> _unclaimed = {};

  LBClaimResultState? _resultState;

  /// 領獎「送出中」flag (win-claim-email-submit-flutter-template). Host / reference-ui
  /// bind [submitInFlight] to draw the `LBWinSheet` `submitting` stage (scrim +
  /// spinner +「送出中…」) and to disable the CTA for the request lifecycle.
  ///
  /// Naming deliberately MIRRORS the existing
  /// `DefaultPlayerTemplate.addToCartInFlight` / `_addToCartInFlight`
  /// (`cart-add-loading-state-flutter`) convention — do NOT invent a second style.
  /// The NOTIFY behaviour follows this class's own `ChangeNotifier` contract
  /// (`expose-default-template-bindable-state` D1: one state change → exactly one
  /// coalesced `notifyListeners()`), unlike `addToCartInFlight` which is a plain
  /// field because `DefaultPlayerTemplate` is not a `ChangeNotifier`.
  ///
  ///   • [_beginSubmit] (shared by BOTH entry points) → `true` (+ one notification)
  ///   • guard rejected (already in flight / invalid email) → UNCHANGED, NO notification
  ///     (mirrors the sold-out / unselected-variant add-to-cart guards)
  ///   • [onAwardClaimResult] (success AND failure) / [dismissClaim] / [clear] → `false`
  ///
  /// Known hang: when a NATIVE host intercepts `awardClaimIntent` the core never emits
  /// `AWARD_CLAIM_RESULT`, so there is no result to consume — the host clears this by
  /// calling [dismissClaim] when it closes its own claim UI (or via [clear] on video
  /// switch / teardown). The template MUST NOT guess the outcome.
  bool _submitInFlight = false;

  /// The winner.id of the most recent submit (parity iOS / Android / RN — Flutter
  /// was the only platform missing it). The core `AWARD_CLAIM_RESULT` notification
  /// carries no winner id that [TemplateAttachment] forwards, so this is what lets a
  /// `claimed` result clear the right unclaimed entry. Deliberately NOT reset by
  /// [dismissClaim] or [clear] — a result that lands AFTER the sheet was closed must
  /// still be able to clear the right entry.
  String? _lastSubmittedWinnerId;

  DefaultWinClaim({
    // ignore: deprecated_member_use_from_same_package
    @Deprecated('EMAIL-LESS seam — 改用 contactSubmitter；下一個 major 移除。')
    AwardClaimSubmitter? submitter,
    AwardClaimContactSubmitter? contactSubmitter,
  })  : _submitter = submitter,
        _contactSubmitter = contactSubmitter;

  // ── §2 unclaimed entry state ──────────────────────────────────────────────

  /// On showWin(text, winner): add to the unclaimed set, deduped by winner.id.
  /// Re-delivering the same id does NOT inflate the count.
  void onWin(LBWinner winner) {
    _unclaimed[winner.id] = winner;
    notifyListeners(); // coalesced "unclaimed changed" — once per recordWin (D1).
  }

  /// Number of distinct unclaimed winners (host binds to the entry badge).
  int get unclaimedCount => _unclaimed.length;

  /// Snapshot of unclaimed winners (insertion order) for the host's list.
  List<LBWinner> get unclaimedWinners =>
      List.unmodifiable(_unclaimed.values);

  /// True while at least one winner is unclaimed (host shows the entry).
  bool get hasUnclaimed => _unclaimed.isNotEmpty;

  // ── §3 submit + classification ────────────────────────────────────────────

  /// Anchored backing pattern for [isValidEmail] (design `/.+@.+\..+/`).
  /// Compiled ONCE at class level. MUST NOT enable `dotAll` (would make `.` match
  /// `\n`) or `multiLine` (would turn `^`/`$` into per-line anchors) — either one
  /// re-admits the multi-line paste this anchoring exists to reject.
  static final RegExp _emailPattern = RegExp(r'^.+@.+\..+$');

  /// Pure front-end email validation (win-claim-email-submit-flutter-template,
  /// name parity iOS `DefaultWinClaim.isValidEmail` / Android companion
  /// `@JvmStatic isValidEmail` / RN `DefaultPlayerTemplate.isValidEmail`).
  ///
  /// The host / reference-ui calls this on every keystroke to decide whether the
  ///「確認領獎」CTA is disabled; [submitWithEmail] uses the SAME function to fail
  /// fast. No side effects, no state — `static`, so callers need no instance.
  ///
  /// Rule mirrors the delivery design `design/templates/minimal/moments.jsx`
  /// (`LBWinSheet`: `emailOk = /.+@.+\..+/.test(email.trim())`, moments.jsx:700):
  /// trim, then `.+@.+\..+` — local part, `@`, domain, `.`, TLD.
  ///
  /// The pattern is ANCHORED (`^…$`) while the design's is not. JS `RegExp.test`
  /// without anchors is a substring search, so `"junk\na@b.c"` would pass; anchored
  /// (and with Dart's `.` not matching `\n` by default) a multi-line paste is
  /// rejected. For SINGLE-LINE input — i.e. every real email field — the two are
  /// identical, so anchoring only ever tightens the multi-line edge case; it can
  /// never reject something the design accepts on one line. Equivalent to iOS
  /// `^.+@.+\..+$` / Android `Regex.matches` / RN `/^.+@.+\..+$/`.
  ///
  /// Deliberately NOT stricter (no RFC 5322): the truth lives in the backend
  /// (deliverability is only known once the mail is sent), and over-strict rules
  /// would kill valid addresses such as `user+tag@sub.domain.io`.
  static bool isValidEmail(String raw) => _emailPattern.hasMatch(raw.trim());

  /// Submit a claim for [winner] carrying the user-entered [email]
  /// (win-claim-email-submit-flutter-template — the fix for the EMAIL-LESS trap).
  ///
  /// Returns `true` when the request was actually handed to the injected submitter
  /// (and the model entered [submitInFlight]); `false` when a guard rejected the
  /// call, in which case the submitter is NOT called and NO state changes at all
  /// (no notification either).
  ///
  /// Guards, in order:
  ///   1. re-entrancy — already in flight (double-tap「確認領獎」/ host re-entry).
  ///      Re-sending `POST /sdk/video/claim` would come back as「已領過」→ `500
  ///      api.fail` → a FAKE failure for the user, so it is cheapest to stop here.
  ///   2. [isValidEmail] — an invalid address never reaches the network.
  ///
  /// The email is trimmed ONCE and the SAME trimmed string is both validated and
  /// sent, so「驗證過的字串」and「送出的字串」can never diverge (core
  /// `performAwardClaim` trims again — idempotent, harmless). The result arrives via
  /// [onAwardClaimResult] (driven by the core `AWARD_CLAIM_RESULT` event).
  ///
  /// NAME: iOS / Android / RN all spell this「same name, one more parameter」
  /// (`submit(winner:email:)` / `submit(winner, email)` / overloaded
  /// `submitAwardClaim`). **Dart has no method overloading**, so the Flutter parity
  /// name is `submitWithEmail`; semantics, guard order and return semantics are
  /// identical (design.md D2).
  bool submitWithEmail(LBWinner winner, String email) {
    if (_submitInFlight) return false;
    if (!isValidEmail(email)) return false;
    _beginSubmit(winner, LBAwardClaimInput(email: email.trim()));
    return true;
  }

  /// EMAIL-LESS claim submit — **DEPRECATED**, kept only for source compatibility.
  ///
  /// It submits with `contact: null`, and the core's default (non-intercepted) claim
  /// path requires `email`, so this entry point **always fails** unless a native host
  /// intercepts `awardClaimIntent`: core fails fast, never sends
  /// `POST /sdk/video/claim`, and emits `AWARD_CLAIM_RESULT(status=failed)`. That is
  /// the very bug this change fixes — use [submitWithEmail].
  ///
  /// Signature + `contact: null` behaviour are intentionally UNCHANGED (per
  /// `docs/contract-governance.md` I6 / 情境 F, removal only in the next MAJOR).
  /// It does now share the in-flight state machine with the new entry point so the
  /// model never exposes a half-populated state.
  @Deprecated(
    'EMAIL-LESS 領獎在未被 host 攔截時必然失敗（core 預設領獎路徑 email 必填，缺 email '
    '直接 fail-fast、連 API 都不送）。改用 submitWithEmail(winner, email)；'
    '本入口將於下一個 major 移除。',
  )
  void submit(LBWinner winner) {
    if (_submitInFlight) return;
    _beginSubmit(winner, null);
  }

  /// Shared submit core for BOTH entry points: remember the target winner, drop any
  /// stale result (so「重新領獎」does not show last round's failure underneath the
  /// spinner), enter in-flight, hand off to the injected seam, notify ONCE.
  ///
  /// Seam resolution: [_contactSubmitter] wins; otherwise the DEPRECATED
  /// [_submitter] is used and **the contact is necessarily lost** (its type has no
  /// contact parameter — that is the EMAIL-LESS trap itself). Neither injected →
  /// inert no-op (headless-safe), but the state machine still runs so the
  /// reference-ui behaves identically.
  void _beginSubmit(LBWinner winner, LBAwardClaimInput? contact) {
    _lastSubmittedWinnerId = winner.id;
    _resultState = null;
    _submitInFlight = true;
    final contactSubmitter = _contactSubmitter;
    if (contactSubmitter != null) {
      contactSubmitter(winner, contact: contact);
    } else {
      _submitter?.call(winner);
    }
    notifyListeners();
  }

  /// True while one claim request is in flight (past its guards, no result yet).
  /// reference-ui binds this to draw the `LBWinSheet` `submitting` stage and to lock
  /// the CTA. See [_submitInFlight] for the full lifecycle + the known-hang note.
  bool get submitInFlight => _submitInFlight;

  /// The winner.id of the most recent submit, or null before the first one.
  /// Used as the fallback target when a `claimed` result arrives without a caller-
  /// supplied winner id (see [onAwardClaimResult]). See [_lastSubmittedWinnerId].
  String? get lastSubmittedWinnerId => _lastSubmittedWinnerId;

  /// Close the claim sheet (design `LBWinSheet`「關閉視窗」/ 右上 ✕ / `done` 態點 scrim /
  /// `FailCard`「關閉視窗」, win-claim-email-submit-flutter-template).
  ///
  /// ⚠️ **刻意反直覺 —— 想「修好它」之前先讀這段。** 設計稿 `confirmClose` 文案是
  ///「您將放棄【獎品】的中獎資格，此動作無法復原」，但**實際行為是純 dismiss**：強烈文案
  /// 是降低隨手關閉機率的 **UX 摩擦設計**，並不真的剝奪資格（權威出處：
  /// `design/contract/claude-design-sync.md` R13「刻意分歧（1/2）」）。同元件 `FailCard`
  /// 的「你的中獎資格仍保留」才是正確描述；兩處措辭衝突為**已知且刻意**，
  /// MUST NOT「順手改一致」。
  ///
  /// 故本方法 MUST 只重置「本次領獎呈現」的暫態，並 MUST NOT：
  ///   • 從 [unclaimedWinners] 移除該 winner
  ///   • 遞減 [unclaimedCount]（中獎入口紅點保留 —— 使用者可再次開啟領取）
  ///   • 呼叫**任何** API（含注入的 submitter）
  ///   • 重置 [lastSubmittedWinnerId]（遲到的 `claimed` 仍需它才能正確消掉紅點）
  void dismissClaim() {
    _resultState = null;
    _submitInFlight = false;
    notifyListeners();
  }

  /// CTA classification from the winner's award type (§3). Drives wording / glyph
  /// only — it does NOT gate the email step (both award types go through the SAME
  /// single email field, see [submitWithEmail]).
  LBClaimClassification classify(LBWinner winner) =>
      LBClaimClassification.fromAwardType(winner.award.type);

  // ── §4 result-state mapping ───────────────────────────────────────────────

  /// Current claim result state for host feedback (null until a result arrives,
  /// or while a native host intercepts the claim — §4).
  LBClaimResultState? get resultState => _resultState;

  /// Consume a core `awardClaimResult`. On a claimed result, also removes the
  /// matching winner.id from the unclaimed set so [unclaimedCount] decrements
  /// (§2 link). On failure the winner stays unclaimed (retry allowed).
  ///
  /// [winnerId] is the participant ticket id (= winner.id) the claim was for;
  /// when known it lets a claimed result decrement the right entry. When the
  /// caller has no winner id (the `AWARD_CLAIM_RESULT` route does not read one
  /// off the wire), [lastSubmittedWinnerId] is used as the fallback — that is
  /// what makes「領獎成功 → 紅點消失」actually happen on the turnkey path
  /// (win-claim-email-submit-flutter-template, parity iOS / Android / RN).
  ///
  /// The fallback is used ONLY for `claimed`; a `failed` / `unknown` result MUST
  /// keep the winner unclaimed so the user can retry.
  ///
  /// The request is over either way, so [submitInFlight] clears on BOTH success
  /// and failure (failure must let the host draw「重新領獎」).
  void onAwardClaimResult({
    required LBAwardClaimStatus status,
    required String awardType,
    int? eventId,
    String? awardCode,
    String? winnerId,
  }) {
    _resultState = LBClaimResultState.fromResult(
      status: status,
      awardType: awardType,
      eventId: eventId,
      awardCode: awardCode,
    );
    _submitInFlight = false;
    if (status == LBAwardClaimStatus.claimed) {
      final id = winnerId ?? _lastSubmittedWinnerId;
      if (id != null) _unclaimed.remove(id);
    }
    // One core result event → result-state update (+ in-flight reset + optional
    // claimed removal) is a single state change → exactly one coalesced
    // notification (D1).
    notifyListeners();
  }

  /// Explicitly remove a winner from the unclaimed set (host reconcile hook).
  void removeUnclaimed(String winnerId) {
    _unclaimed.remove(winnerId);
    notifyListeners();
  }

  /// Clear the transient result state (e.g. when the host closes the sheet).
  ///
  /// @deprecated 改用 [dismissClaim]（四端 parity 名稱，語意完全相同且**一併結束**
  /// [submitInFlight]）。原本只清 [resultState] 會留下「結果清了、畫面仍卡在
  /// submitting」的懸掛。本方法現已薄委派 [dismissClaim]，行為只變得更安全；
  /// 將於下一個 major 移除（`docs/contract-governance.md` I6 / 情境 F）。
  @Deprecated('改用 dismissClaim()：語意相同並一併歸零 submitInFlight。'
      '本入口將於下一個 major 移除。')
  void clearResultState() => dismissClaim();

  /// Reset ALL unclaimed winners + the transient result state (e.g. on `VIDEO_SWITCH`
  /// / new video). Parity with iOS/Android/RN `clear()`. Fires one coalesced
  /// notification so a bound host re-reads the now-empty entry/result.
  ///
  /// Also drops any in-flight submit — including one left hanging by a claim a
  /// native host intercepted (no `AWARD_CLAIM_RESULT` ever arrives for those).
  /// [lastSubmittedWinnerId] is deliberately NOT reset (parity iOS / Android):
  /// the unclaimed set is emptied here anyway, so a stale id can only ever hit a
  /// no-op `remove`.
  void clear() {
    _unclaimed.clear();
    _resultState = null;
    _submitInFlight = false;
    notifyListeners();
  }
}
